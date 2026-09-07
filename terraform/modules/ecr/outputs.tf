output "repository_urls" {
  description = "Mapa <serviço> => URL completa do repositório ECR (usar em patch-images.yaml)."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Mapa <serviço> => ARN do repositório ECR."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "registry_id" {
  description = "ID da conta AWS que hospeda o registry (usado para montar a URL do registry)."
  value       = values(aws_ecr_repository.this)[0].registry_id
}
