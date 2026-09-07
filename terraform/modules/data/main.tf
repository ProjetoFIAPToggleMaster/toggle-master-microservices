# ---------------------------------------------------------------------------
# Security group do RDS
# ---------------------------------------------------------------------------
# Sem regra de ingress a partir de CIDR: só os security groups informados
# (na prática, o do cluster EKS) conseguem abrir conexão na porta 5432.
# ---------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "Acesso PostgreSQL a partir dos nodes do EKS."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds"
  })
}

# Usa count, e não for_each: os IDs de security group vêm do módulo eks e só
# existem depois do apply. As chaves de um for_each precisam ser conhecidas no
# plan; já o count precisa apenas do tamanho da lista, que é conhecido.
resource "aws_vpc_security_group_ingress_rule" "rds" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL a partir dos nodes do EKS"
}

# ---------------------------------------------------------------------------
# Subnet group do RDS
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-rds"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds"
  })
}

# ---------------------------------------------------------------------------
# Instâncias PostgreSQL
# ---------------------------------------------------------------------------
# manage_master_user_password = true faz a AWS criar a senha e guardá-la no
# Secrets Manager, com rotação gerenciada. A senha nunca aparece no código,
# no tfstate em texto claro, nem precisa ser digitada por ninguém.
# ---------------------------------------------------------------------------
resource "aws_db_instance" "this" {
  for_each = var.databases

  identifier     = "${var.name_prefix}-${each.key}"
  engine         = "postgres"
  engine_version = var.postgres_version
  instance_class = var.db_instance_class

  db_name  = each.value.db_name
  username = var.db_master_username

  manage_master_user_password = true

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = var.db_deletion_protection
  skip_final_snapshot     = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : (
    "${var.name_prefix}-${each.key}-final"
  )

  auto_minor_version_upgrade = true
  apply_immediately          = true

  tags = merge(var.tags, {
    Name     = "${var.name_prefix}-${each.key}"
    Database = each.value.db_name
  })
}

# ---------------------------------------------------------------------------
# Security group do ElastiCache
# ---------------------------------------------------------------------------
resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis"
  description = "Acesso Redis a partir dos nodes do EKS."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-redis"
  })
}

# Mesmo motivo do ingress do RDS: count em vez de for_each.
resource "aws_vpc_security_group_ingress_rule" "redis" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.redis.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Redis a partir dos nodes do EKS"
}

# ---------------------------------------------------------------------------
# ElastiCache (Redis) — nó único
# ---------------------------------------------------------------------------
# Um único nó, sem réplica: é o cache de avaliação de flags do
# evaluation-service, com TTL curto. Perder o cache só causa cache miss, que
# o serviço já trata buscando nos serviços de origem — não justifica o custo
# de um replication group com failover.
# ---------------------------------------------------------------------------
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name_prefix}-redis"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-redis"
  })
}

resource "aws_elasticache_cluster" "this" {
  cluster_id           = "${var.name_prefix}-redis"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = var.redis_parameter_group
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-redis"
  })
}
