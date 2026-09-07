output "vpc_id" {
  description = "ID da VPC."
  value       = module.networking.vpc_id
}

output "vpc_cidr_block" {
  description = "Bloco CIDR da VPC."
  value       = module.networking.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs das subnets públicas."
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs das subnets privadas."
  value       = module.networking.private_subnet_ids
}

output "internet_gateway_id" {
  description = "ID do Internet Gateway."
  value       = module.networking.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "IDs dos NAT Gateways."
  value       = module.networking.nat_gateway_ids
}

output "availability_zones" {
  description = "AZs efetivamente utilizadas."
  value       = module.networking.availability_zones
}

# ---------------------------------------------------------------------------
# ECR
# ---------------------------------------------------------------------------

output "ecr_repository_urls" {
  description = <<-EOT
    Mapa <serviço> => URL do repositório ECR. São exatamente os valores a
    usar em k8s/overlays/prod/patch-images.yaml (acrescentando :<tag>).
  EOT
  value       = module.ecr.repository_urls
}

# ---------------------------------------------------------------------------
# EKS
# ---------------------------------------------------------------------------

output "eks_cluster_name" {
  description = "Nome do cluster (aws eks update-kubeconfig --name <valor>)."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint da API do cluster."
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group do cluster, autorizado no RDS e no ElastiCache."
  value       = module.eks.cluster_security_group_id
}

output "eks_oidc_provider_arn" {
  description = "ARN do provedor OIDC (base do IRSA)."
  value       = module.eks.oidc_provider_arn
}

output "eks_node_role_name" {
  description = "Nome da IAM role dos nodes."
  value       = module.eks.node_role_name
}

# ---------------------------------------------------------------------------
# Data stores
# ---------------------------------------------------------------------------

output "rds_addresses" {
  description = "Mapa <chave> => hostname da instância RDS."
  value       = module.data.db_addresses
}

output "rds_database_names" {
  description = "Mapa <chave> => nome do banco lógico."
  value       = module.data.db_names
}

output "rds_master_username" {
  description = "Usuário master do PostgreSQL."
  value       = module.data.db_master_username
}

output "rds_master_secret_arns" {
  description = <<-EOT
    Mapa <chave> => ARN do secret com a senha master gerada pela AWS.
    Recupere com:
      aws secretsmanager get-secret-value --secret-id <arn> \
        --query SecretString --output text
  EOT
  value       = module.data.db_master_secret_arns
}

output "redis_url" {
  description = "Valor pronto para REDIS_URL do evaluation-service."
  value       = module.data.redis_url
}

# ---------------------------------------------------------------------------
# Mensageria
# ---------------------------------------------------------------------------

output "sqs_queue_url" {
  description = "Valor de AWS_SQS_URL para evaluation-service e analytics-service."
  value       = module.messaging.queue_url
}

output "sqs_dlq_url" {
  description = "URL da dead-letter queue (mensagens que falharam repetidamente)."
  value       = module.messaging.dlq_url
}

output "dynamodb_table_name" {
  description = "Valor de AWS_DYNAMODB_TABLE para o analytics-service."
  value       = module.messaging.dynamodb_table_name
}

# ---------------------------------------------------------------------------
# IRSA
# ---------------------------------------------------------------------------

output "irsa_role_arns" {
  description = <<-EOT
    Mapa <serviço> => ARN da role IAM. Anote no ServiceAccount do Kubernetes:
      annotations:
        eks.amazonaws.com/role-arn: <valor>
  EOT
  value       = { for k, role in aws_iam_role.irsa : k => role.arn }
}
