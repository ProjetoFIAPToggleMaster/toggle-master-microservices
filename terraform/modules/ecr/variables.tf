variable "service_names" {
  description = <<-EOT
    Nomes dos microsserviços. Cada um vira um repositório ECR privado com
    exatamente esse nome (sem prefixo), para que os pipelines de CI possam
    usar apenas "$ECR_REGISTRY/<service-name>" sem lógica extra.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.service_names) > 0
    error_message = "Informe ao menos um serviço."
  }
}

variable "image_tag_mutability" {
  description = <<-EOT
    MUTABLE permite sobrescrever uma tag existente; IMMUTABLE proíbe.
    Como o CI publica tags únicas por commit (v1.0.0-<sha>), IMMUTABLE é o
    padrão mais seguro: garante que uma tag sempre aponta para a mesma imagem.
  EOT
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability deve ser MUTABLE ou IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Dispara scan de vulnerabilidades do ECR a cada push de imagem."
  type        = bool
  default     = true
}

variable "force_delete" {
  description = <<-EOT
    Permite que o `terraform destroy` remova repositórios que ainda contêm
    imagens. Deixe true em ambientes descartáveis; false protege produção.
  EOT
  type        = bool
  default     = true
}

variable "untagged_expire_days" {
  description = "Dias até expirar imagens sem tag (lixo de builds intermediários)."
  type        = number
  default     = 7
}

variable "max_image_count" {
  description = "Quantidade máxima de imagens com tag mantidas por repositório."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
