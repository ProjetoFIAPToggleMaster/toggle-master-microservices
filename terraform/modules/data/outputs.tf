output "db_endpoints" {
  description = "Mapa <chave lógica> => endereço:porta da instância RDS."
  value       = { for k, db in aws_db_instance.this : k => db.endpoint }
}

output "db_addresses" {
  description = "Mapa <chave lógica> => hostname da instância RDS (sem a porta)."
  value       = { for k, db in aws_db_instance.this : k => db.address }
}

output "db_names" {
  description = "Mapa <chave lógica> => nome do banco lógico criado na instância."
  value       = { for k, db in aws_db_instance.this : k => db.db_name }
}

output "db_master_username" {
  description = "Usuário master das instâncias RDS."
  value       = var.db_master_username
}

output "db_master_secret_arns" {
  description = <<-EOT
    Mapa <chave lógica> => ARN do secret no Secrets Manager onde a AWS
    guarda a senha master gerada. Leia com:
      aws secretsmanager get-secret-value --secret-id <arn>
  EOT
  value       = { for k, db in aws_db_instance.this : k => db.master_user_secret[0].secret_arn }
}

output "db_security_group_id" {
  description = "Security group aplicado às instâncias RDS."
  value       = aws_security_group.rds.id
}

output "redis_endpoint" {
  description = "Hostname do nó Redis (compor como redis://<endpoint>:6379)."
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "redis_port" {
  description = "Porta do Redis."
  value       = aws_elasticache_cluster.this.cache_nodes[0].port
}

output "redis_url" {
  description = "URL pronta para a variável REDIS_URL do evaluation-service."
  value       = "redis://${aws_elasticache_cluster.this.cache_nodes[0].address}:${aws_elasticache_cluster.this.cache_nodes[0].port}"
}

output "redis_security_group_id" {
  description = "Security group aplicado ao ElastiCache."
  value       = aws_security_group.redis.id
}
