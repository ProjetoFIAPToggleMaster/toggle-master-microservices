variable "name_prefix" {
  description = "Prefixo aplicado ao nome dos recursos (ex.: toggle-master-prod)."
  type        = string
}

# ---------------------------------------------------------------------------
# SQS
# ---------------------------------------------------------------------------

variable "queue_name" {
  description = <<-EOT
    Nome da fila SQS principal. Se "", usa "<name_prefix>-events".
    O evaluation-service publica nela; o analytics-service consome.
  EOT
  type        = string
  default     = ""
}

variable "visibility_timeout_seconds" {
  description = <<-EOT
    Tempo que uma mensagem fica invisível após ser recebida. Precisa ser
    maior que o tempo de processamento do analytics-service, senão a mesma
    mensagem volta para a fila e é processada duas vezes.
  EOT
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "Tempo que uma mensagem não consumida permanece na fila (padrão: 4 dias)."
  type        = number
  default     = 345600
}

variable "max_receive_count" {
  description = <<-EOT
    Quantas vezes uma mensagem pode falhar antes de ir para a DLQ.
    Isso resolve o problema de "poison pill": mensagem com JSON inválido que
    o worker nunca consegue processar e que, sem DLQ, seria reentregue para
    sempre, poluindo os logs indefinidamente.
  EOT
  type        = number
  default     = 5
}

variable "dlq_message_retention_seconds" {
  description = "Retenção na dead-letter queue (padrão: 14 dias, o máximo)."
  type        = number
  default     = 1209600
}

# ---------------------------------------------------------------------------
# DynamoDB
# ---------------------------------------------------------------------------

variable "dynamodb_table_name" {
  description = <<-EOT
    Nome da tabela DynamoDB de analytics. Precisa bater com a variável de
    ambiente AWS_DYNAMODB_TABLE consumida pelo analytics-service.
  EOT
  type        = string
  default     = "ToggleMasterAnalytics"
}

variable "dynamodb_hash_key" {
  description = "Chave de partição da tabela. O analytics-service grava um UUID em 'event_id'."
  type        = string
  default     = "event_id"
}

variable "dynamodb_billing_mode" {
  description = <<-EOT
    PAY_PER_REQUEST cobra por operação e custa zero quando ocioso — melhor
    para carga imprevisível e para manter o custo baixo em ambiente de estudo.
  EOT
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.dynamodb_billing_mode)
    error_message = "dynamodb_billing_mode deve ser PAY_PER_REQUEST ou PROVISIONED."
  }
}

variable "dynamodb_point_in_time_recovery" {
  description = "Habilita backup contínuo (PITR). Gera custo adicional por GB armazenado."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
