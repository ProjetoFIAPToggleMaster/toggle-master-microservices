# ---------------------------------------------------------------------------
# Bootstrap do backend remoto
# ---------------------------------------------------------------------------
# Cria o bucket S3 que guardará o tfstate das demais configurações.
# Roda UMA vez, com state LOCAL (este diretório fica fora do backend remoto).
#
#   cd terraform/bootstrap
#   terraform init
#   terraform apply -var="aws_profile=<SEU_PROFILE>"
#
# O output state_bucket_name é o valor a passar em -backend-config na raiz.
# O lock do state é feito nativamente pelo S3 (use_lockfile), sem DynamoDB.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Component = "tf-backend"
    }
  }
}

variable "aws_region" {
  description = "Região AWS do bucket de state."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Profile de credenciais AWS. \"\" usa a cadeia padrão."
  type        = string
  default     = ""
}

variable "project_name" {
  description = "Prefixo do nome do bucket."
  type        = string
  default     = "toggle-master"
}

variable "state_bucket_name" {
  description = <<-EOT
    Nome exato do bucket de state. Se "", usa
    "<project_name>-tfstate-<account_id>" para garantir unicidade global.
  EOT
  type        = string
  default     = ""
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = var.state_bucket_name != "" ? var.state_bucket_name : "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  # Protege contra `terraform destroy` acidental do bucket de state.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "state_bucket_name" {
  description = "Nome do bucket S3 do backend remoto (usar em -backend-config)."
  value       = aws_s3_bucket.state.id
}
