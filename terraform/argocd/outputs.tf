# ---------------------------------------------------------------------------
# Outputs — atalhos para o pós-apply
# ---------------------------------------------------------------------------

output "argocd_namespace" {
  description = "Namespace onde o ArgoCD foi instalado."
  value       = helm_release.argocd.namespace
}

output "argocd_chart_version" {
  description = "Versão do chart argo-cd efetivamente instalada."
  value       = helm_release.argocd.version
}

output "application_name" {
  description = "Nome da Application criada no ArgoCD."
  value       = var.application_name
}

output "kubeconfig_command" {
  description = "Aponta o kubectl para o cluster antes de qualquer comando abaixo."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}"
}

output "admin_password_command" {
  description = <<-EOT
    Recupera a senha inicial do usuário `admin`. O ArgoCD gera esse Secret na
    primeira instalação; ele NÃO é gerenciado pelo Terraform, por isso a senha
    não aparece como output (evita gravá-la no tfstate em texto claro).
  EOT
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "port_forward_command" {
  description = "Abre a UI em https://localhost:8080 (usuário: admin). Deixe rodando em um terminal separado."
  value       = "kubectl port-forward svc/argocd-server -n ${var.argocd_namespace} 8080:443"
}

output "sync_status_command" {
  description = "Acompanha o estado de sincronização pela linha de comando."
  value       = "kubectl get applications -n ${var.argocd_namespace}"
}
