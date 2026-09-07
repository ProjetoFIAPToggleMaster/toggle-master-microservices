variable "name_prefix" {
  description = "Prefixo aplicado ao nome dos recursos (ex.: toggle-master-prod)."
  type        = string
}

variable "vpc_id" {
  description = "VPC onde os data stores serão criados."
  type        = string
}

variable "private_subnet_ids" {
  description = <<-EOT
    Subnets privadas dos subnet groups. RDS e ElastiCache ficam sem rota
    para a internet: só são alcançáveis de dentro da VPC.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "RDS e ElastiCache exigem subnets em ao menos 2 AZs."
  }
}

variable "allowed_security_group_ids" {
  description = <<-EOT
    Security groups autorizados a conectar (normalmente o security group do
    cluster EKS, ao qual os nodes pertencem).
  EOT
  type        = list(string)
}

# ---------------------------------------------------------------------------
# RDS
# ---------------------------------------------------------------------------

variable "databases" {
  description = <<-EOT
    Instâncias RDS a criar, indexadas por chave lógica.

    O padrão cria duas instâncias em vez de três: flag-service e
    targeting-service compartilham a mesma instância (bancos lógicos
    separados dentro dela), o que reduz custo mantendo o isolamento de
    schema exigido pelo desafio.
  EOT
  type = map(object({
    db_name = string
  }))
  default = {
    auth  = { db_name = "auth_db" }
    flags = { db_name = "flags_db" }
  }
}

variable "postgres_version" {
  description = "Versão maior do PostgreSQL. A AWS resolve para a menor versão mais recente."
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Classe de instância do RDS. db.t3.micro é elegível ao free tier."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Armazenamento inicial de cada instância, em GB."
  type        = number
  default     = 20
}

variable "db_master_username" {
  description = <<-EOT
    Usuário master. A senha NÃO é definida aqui: manage_master_user_password
    faz a própria AWS gerar e rotacionar a senha dentro do Secrets Manager.
  EOT
  type        = string
  default     = "postgres"
}

variable "db_multi_az" {
  description = "Replica a instância em outra AZ. Dobra o custo; desligado por padrão."
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "Dias de retenção dos backups automáticos. 0 desabilita backups."
  type        = number
  default     = 1
}

variable "db_deletion_protection" {
  description = "Impede exclusão acidental da instância. Ligue em produção real."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Pula o snapshot final ao destruir. true em ambiente descartável."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# ElastiCache (Redis)
# ---------------------------------------------------------------------------

variable "redis_node_type" {
  description = "Tipo de node do ElastiCache. cache.t4g.micro é a opção mais barata."
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_engine_version" {
  description = "Versão do Redis."
  type        = string
  default     = "7.1"
}

variable "redis_parameter_group" {
  description = "Parameter group do Redis, compatível com a versão do engine."
  type        = string
  default     = "default.redis7"
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
