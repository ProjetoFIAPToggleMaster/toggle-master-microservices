# ---------------------------------------------------------------------------
# Repositórios ECR privados (um por microsserviço)
# ---------------------------------------------------------------------------
# O nome do repositório é exatamente o nome do serviço, sem prefixo de
# projeto. Isso mantém o CI simples: ele publica em
# "$ECR_REGISTRY/$SERVICE_NAME:$IMAGE_TAG", onde $ECR_REGISTRY vem do output
# da action amazon-ecr-login.
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  for_each = toset(var.service_names)

  name                 = each.value
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name    = each.value
    Service = each.value
  })
}

# ---------------------------------------------------------------------------
# Lifecycle policy: impede o repositório de crescer (e custar) para sempre
# ---------------------------------------------------------------------------
# Regra 1 limpa imagens sem tag (camadas órfãs de builds sobrescritos).
# Regra 2 mantém apenas as N imagens com tag mais recentes.
# A regra com tagStatus "any" precisa ser sempre a de maior rulePriority.
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expira imagens sem tag após ${var.untagged_expire_days} dias."
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expire_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Mantém apenas as ${var.max_image_count} imagens mais recentes."
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}
