# ---------------------------------------------------------------------------
# IAM role do control plane
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name_prefix}-eks-cluster"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-cluster"
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# Cluster EKS
# ---------------------------------------------------------------------------
resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.private_subnet_ids, var.public_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  # -------------------------------------------------------------------------
  # Access entries (API) em vez do ConfigMap aws-auth.
  #
  # O modo antigo (CONFIG_MAP) exige editar o ConfigMap aws-auth à mão para
  # dar acesso a cada usuário IAM — processo frágil, sem validação, e que
  # falha de forma silenciosa e confusa quando o mapeamento está errado.
  # Com API_AND_CONFIG_MAP, o acesso passa a ser gerenciado por recursos
  # aws_eks_access_entry, versionados em código.
  #
  # bootstrap_cluster_creator_admin_permissions dá admin a quem roda o
  # terraform apply, e só pode ser definido na criação do cluster.
  # -------------------------------------------------------------------------
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = var.enabled_cluster_log_types

  depends_on = [aws_iam_role_policy_attachment.cluster]

  tags = merge(var.tags, {
    Name = var.cluster_name
  })
}

# ---------------------------------------------------------------------------
# Provedor OIDC — base do IRSA
# ---------------------------------------------------------------------------
# Permite que um ServiceAccount do Kubernetes assuma uma role IAM, de forma
# que os pods obtenham credenciais temporárias em vez de carregar
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY em Secrets.
# ---------------------------------------------------------------------------
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-oidc"
  })
}

# ---------------------------------------------------------------------------
# IAM role dos nodes
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-eks-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-node"
  })
}

# AmazonEC2ContainerRegistryReadOnly é o que permite ao kubelet puxar as
# imagens dos repositórios ECR privados criados pelo módulo ecr.
resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# Node group gerenciado
# ---------------------------------------------------------------------------
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = var.node_instance_types
  capacity_type  = var.node_capacity_type
  disk_size      = var.node_disk_size

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  # desired_size passa a ser gerenciado pelo cluster-autoscaler/HPA depois do
  # provisionamento inicial; ignorar evita que o terraform reverta a escala.
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.node]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nodes"
  })
}

# ---------------------------------------------------------------------------
# Addons gerenciados
# ---------------------------------------------------------------------------
# Dependem do node group: coredns e metrics-server precisam de nodes
# disponíveis para serem agendados.
# ---------------------------------------------------------------------------
resource "aws_eks_addon" "this" {
  for_each = toset(var.cluster_addons)

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.value

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${each.value}"
  })
}
