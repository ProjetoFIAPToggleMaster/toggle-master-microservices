locals {
  queue_name = var.queue_name != "" ? var.queue_name : "${var.name_prefix}-events"
}

# ---------------------------------------------------------------------------
# Dead-letter queue
# ---------------------------------------------------------------------------
# Mensagens que falham repetidamente (ex.: corpo com JSON inválido) são
# movidas para cá depois de max_receive_count tentativas, em vez de ficarem
# em loop infinito na fila principal.
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.queue_name}-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds

  tags = merge(var.tags, {
    Name = "${local.queue_name}-dlq"
    Role = "dead-letter-queue"
  })
}

# ---------------------------------------------------------------------------
# Fila principal de eventos de avaliação de flags
# ---------------------------------------------------------------------------
resource "aws_sqs_queue" "events" {
  name                       = local.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = merge(var.tags, {
    Name = local.queue_name
    Role = "events"
  })
}

# ---------------------------------------------------------------------------
# Tabela DynamoDB de analytics
# ---------------------------------------------------------------------------
# Escrita append-only, um item por avaliação de flag. Sem sort key e sem
# índices secundários: o serviço apenas faz put_item com um event_id único.
# ---------------------------------------------------------------------------
resource "aws_dynamodb_table" "analytics" {
  name         = var.dynamodb_table_name
  billing_mode = var.dynamodb_billing_mode
  hash_key     = var.dynamodb_hash_key

  attribute {
    name = var.dynamodb_hash_key
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.dynamodb_point_in_time_recovery
  }

  tags = merge(var.tags, {
    Name = var.dynamodb_table_name
  })
}

# ---------------------------------------------------------------------------
# Documentos de política IAM (consumidos pelas roles IRSA na raiz)
# ---------------------------------------------------------------------------
# Cada serviço recebe apenas o que precisa:
#   - evaluation-service: só publica na fila
#   - analytics-service: só consome da fila e grava no DynamoDB
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "sqs_producer" {
  statement {
    sid    = "PublicarEventosNaFila"
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]

    resources = [aws_sqs_queue.events.arn]
  }
}

data "aws_iam_policy_document" "sqs_consumer" {
  statement {
    sid    = "ConsumirEventosDaFila"
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
    ]

    resources = [aws_sqs_queue.events.arn]
  }

  statement {
    sid    = "GravarAnalyticsNoDynamo"
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:BatchWriteItem",
    ]

    resources = [aws_dynamodb_table.analytics.arn]
  }
}
