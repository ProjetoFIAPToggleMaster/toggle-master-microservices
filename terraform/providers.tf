provider "aws" {
  region = var.aws_region

  # -------------------------------------------------------------------------
  # Preencha aqui (ou via variável aws_profile / terraform.tfvars) o profile
  # de credenciais AWS que você vai utilizar. Deixe como null/"" para cair
  # na cadeia de credenciais padrão (env vars, SSO, instance profile, etc).
  # -------------------------------------------------------------------------
  profile = var.aws_profile != "" ? var.aws_profile : null

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
