output "cluster_name" {
  description = "Nome do cluster EKS (usar em: aws eks update-kubeconfig --name <nome>)."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Certificado da CA do cluster (base64)."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Versão do Kubernetes em execução no control plane."
  value       = aws_eks_cluster.this.version
}

output "cluster_security_group_id" {
  description = <<-EOT
    Security group gerenciado pelo EKS, associado ao control plane e aos
    nodes. É a origem a autorizar nas regras de ingress do RDS e do
    ElastiCache.
  EOT
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN do provedor OIDC (usado nas trust policies das roles IRSA)."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "URL do issuer OIDC, sem o prefixo https://."
  value       = replace(aws_iam_openid_connect_provider.this.url, "https://", "")
}

output "node_role_name" {
  description = "Nome da IAM role dos nodes."
  value       = aws_iam_role.node.name
}

output "node_role_arn" {
  description = "ARN da IAM role dos nodes."
  value       = aws_iam_role.node.arn
}

output "node_group_name" {
  description = "Nome do node group gerenciado."
  value       = aws_eks_node_group.this.node_group_name
}
