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
