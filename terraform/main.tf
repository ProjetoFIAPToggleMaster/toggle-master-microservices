locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # Se availability_zones não for informado, usa as N primeiras AZs
  # disponíveis (opt-in excluídas) da região.
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, var.az_count)

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )

  # Roles IRSA: cada entrada vira uma IAM role que só pode ser assumida pelo
  # ServiceAccount correspondente, no namespace da aplicação.
  irsa_roles = {
    evaluation-service = {
      service_account = "evaluation-service"
      policy_json     = module.messaging.sqs_producer_policy_json
    }
    analytics-service = {
      service_account = "analytics-service"
      policy_json     = module.messaging.sqs_consumer_policy_json
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# ---------------------------------------------------------------------------
# 1. Networking
# ---------------------------------------------------------------------------
module "networking" {
  source = "./modules/networking"

  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.azs

  subnet_newbits = var.subnet_newbits

  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  eks_cluster_name = var.eks_cluster_name

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# 2. Registries de container (ECR privado, um por serviço)
# ---------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  service_names = var.service_names

  image_tag_mutability = var.ecr_image_tag_mutability
  max_image_count      = var.ecr_max_image_count

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# 3. Cluster EKS
# ---------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  name_prefix  = local.name_prefix
  cluster_name = var.eks_cluster_name

  kubernetes_version = var.kubernetes_version
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids

  node_instance_types = var.node_instance_types
  node_capacity_type  = var.node_capacity_type
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size

  public_access_cidrs = var.cluster_public_access_cidrs

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# 4. Mensageria e analytics (SQS + DynamoDB)
# ---------------------------------------------------------------------------
# Serviços regionais: não vivem dentro da VPC e por isso não dependem do EKS.
# ---------------------------------------------------------------------------
module "messaging" {
  source = "./modules/messaging"

  name_prefix         = local.name_prefix
  dynamodb_table_name = var.dynamodb_table_name

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# 5. Data stores dentro da VPC (RDS + ElastiCache)
# ---------------------------------------------------------------------------
# Só aceitam conexão vinda do security group do cluster EKS.
# ---------------------------------------------------------------------------
module "data" {
  source = "./modules/data"

  name_prefix        = local.name_prefix
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids

  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  db_instance_class = var.db_instance_class
  redis_node_type   = var.redis_node_type

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# 6. IRSA — credenciais temporárias para os pods
# ---------------------------------------------------------------------------
# Em vez de gravar AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY em Secrets do
# Kubernetes, cada ServiceAccount assume uma role IAM via OIDC e recebe
# credenciais temporárias, rotacionadas automaticamente pela AWS.
#
# A condição "sub" amarra a role a UM ServiceAccount específico em UM
# namespace: nenhum outro pod do cluster consegue assumi-la.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "irsa_assume_role" {
  for_each = local.irsa_roles

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.k8s_namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.irsa_roles

  name               = "${local.name_prefix}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role[each.key].json

  tags = merge(local.common_tags, {
    Name    = "${local.name_prefix}-${each.key}"
    Service = each.key
  })
}

resource "aws_iam_role_policy" "irsa" {
  for_each = local.irsa_roles

  name   = "${local.name_prefix}-${each.key}"
  role   = aws_iam_role.irsa[each.key].id
  policy = each.value.policy_json
}
