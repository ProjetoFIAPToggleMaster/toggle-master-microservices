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

variable "tags" {
  description = "Tags adicionais aplicadas a todos os recursos."
  type        = map(string)
  default     = {}
}
