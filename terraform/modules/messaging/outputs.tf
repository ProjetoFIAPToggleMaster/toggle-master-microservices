output "queue_url" {
  description = "URL da fila SQS principal (valor de AWS_SQS_URL nos serviços)."
  value       = aws_sqs_queue.events.url
}

output "queue_arn" {
  description = "ARN da fila SQS principal."
  value       = aws_sqs_queue.events.arn
}

output "queue_name" {
  description = "Nome da fila SQS principal."
  value       = aws_sqs_queue.events.name
}

output "dlq_url" {
  description = "URL da dead-letter queue (inspecionar aqui as mensagens que falharam)."
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN da dead-letter queue."
  value       = aws_sqs_queue.dlq.arn
}

output "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB (valor de AWS_DYNAMODB_TABLE)."
  value       = aws_dynamodb_table.analytics.name
}

output "dynamodb_table_arn" {
  description = "ARN da tabela DynamoDB."
  value       = aws_dynamodb_table.analytics.arn
}

output "sqs_producer_policy_json" {
  description = "Política IAM de publicação na fila (para a role IRSA do evaluation-service)."
  value       = data.aws_iam_policy_document.sqs_producer.json
}

output "sqs_consumer_policy_json" {
  description = "Política IAM de consumo da fila + escrita no DynamoDB (role IRSA do analytics-service)."
  value       = data.aws_iam_policy_document.sqs_consumer.json
}
