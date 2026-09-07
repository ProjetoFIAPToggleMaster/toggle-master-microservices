# ---------------------------------------------------------------------------
# Variáveis globais
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "Região AWS onde a infraestrutura será provisionada."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = <<-EOT
    Profile de credenciais AWS (arquivo ~/.aws/config / ~/.aws/credentials)
    usado pelo provider. Deixe "" para usar a cadeia de credenciais padrão.
  EOT
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Nome do projeto, usado como prefixo e em tags."
  type        = string
  default     = "toggle-master"
}

variable "environment" {
  description = "Ambiente lógico (dev, staging, prod...)."
  type        = string
  default     = "prod"
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "Bloco CIDR primário da VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr precisa ser um bloco CIDR IPv4 válido."
  }
}

variable "availability_zones" {
  description = <<-EOT
    Lista de AZs a utilizar. Se vazio, as N primeiras AZs disponíveis da
    região são escolhidas automaticamente (N = az_count).
  EOT
  type        = list(string)
  default     = []
}

variable "az_count" {
  description = "Quantidade de AZs a usar quando availability_zones não é informado."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count deve estar entre 2 e 4."
  }
}

variable "subnet_newbits" {
  description = <<-EOT
    Bits adicionais somados ao prefixo da VPC para dimensionar cada subnet.
    Ex.: VPC /16 + newbits 8 => subnets /24.
  EOT
  type        = number
  default     = 8
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway(s) para dar saída à internet às subnets privadas (necessário para nodes EKS)."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Usa um único NAT Gateway compartilhado (mais barato) em vez de um por AZ."
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = <<-EOT
    Nome do futuro cluster EKS. Usado apenas para aplicar as tags de
    descoberta de subnets (kubernetes.io/cluster/<nome>) exigidas pelo EKS.
    Deixe "" para não aplicar essas tags agora.
  EOT
  type        = string
  default     = "toggle-master-eks"
}

# ---------------------------------------------------------------------------
# Aplicação
# ---------------------------------------------------------------------------

variable "service_names" {
  description = "Microsserviços do ToggleMaster. Cada um ganha um repositório ECR privado."
  type        = list(string)
  default = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

variable "k8s_namespace" {
  description = <<-EOT
    Namespace do Kubernetes onde os serviços rodam. Usado nas trust policies
    do IRSA: a role só pode ser assumida por um ServiceAccount deste namespace.
  EOT
  type        = string
  default     = "toggle-master"
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------

variable "ecr_image_tag_mutability" {
  description = <<-EOT
    IMMUTABLE impede sobrescrever uma tag já publicada. Exige que o CI use
    tags únicas por commit (v1.0.0-<sha>) e NÃO publique uma tag "latest"
    reaproveitada, pois o segundo push de "latest" seria rejeitado.
  EOT
  type        = string
  default     = "IMMUTABLE"
}

variable "ecr_max_image_count" {
  description = "Máximo de imagens com tag mantidas por repositório."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------

variable "kubernetes_version" {
  description = "Versão do Kubernetes do control plane."
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = <<-EOT
    Tipos de instância dos nodes. Evite t3.micro/t3.small: o limite de pods
    por node é derivado do tipo da instância e instâncias pequenas não
    comportam os pods de sistema + ingress + 5 microsserviços, resultando em
    pods presos em Pending com "Too many pods".
  EOT
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND ou SPOT (SPOT é mais barato, porém interrompível)."
  type        = string
  default     = "ON_DEMAND"
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade mínima de nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Quantidade máxima de nodes (deixe folga para o HPA escalar)."
  type        = number
  default     = 4
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs autorizados a acessar o endpoint público da API do EKS."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------------------------------------------------------------------------
# Data stores
# ---------------------------------------------------------------------------

variable "db_instance_class" {
  description = "Classe das instâncias RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "redis_node_type" {
  description = "Tipo de node do ElastiCache."
  type        = string
  default     = "cache.t4g.micro"
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB de analytics (bate com AWS_DYNAMODB_TABLE)."
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
