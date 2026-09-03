variable "name_prefix" {
  description = "Prefixo aplicado ao nome de todos os recursos (ex.: toggle-master-prod)."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR primário da VPC."
  type        = string
}

variable "availability_zones" {
  description = "Lista de AZs onde as subnets serão distribuídas (1 subnet pública + 1 privada por AZ)."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Informe ao menos 2 AZs para alta disponibilidade."
  }
}

variable "subnet_newbits" {
  description = "Bits adicionais somados ao prefixo da VPC para dimensionar cada subnet."
  type        = number
  default     = 8
}

variable "enable_nat_gateway" {
  description = "Cria NAT Gateway(s) para saída à internet das subnets privadas."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Compartilha um único NAT Gateway entre todas as AZs (mais barato, sem HA)."
  type        = bool
  default     = true
}

variable "eks_cluster_name" {
  description = "Nome do cluster EKS para as tags de descoberta de subnet. \"\" desativa essas tags."
  type        = string
  default     = ""
}

variable "map_public_ip_on_launch" {
  description = "Atribui IP público automaticamente às instâncias lançadas nas subnets públicas."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
