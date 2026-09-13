# ---------------------------------------------------------------------------
# Variáveis do estágio ArgoCD
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "Região AWS onde o cluster EKS foi criado."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = <<-EOT
    Profile do ~/.aws/credentials. Deixe vazio para usar as credenciais
    padrão do ambiente (útil na AWS Academy, que exporta variáveis de
    sessão temporárias em vez de um profile nomeado).
  EOT
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = <<-EOT
    Nome do cluster EKS criado pelo estágio 1. Deve bater exatamente com o
    output `cluster_name` daquele estado — pegue com:
      terraform -chdir=.. output -raw eks_cluster_name
  EOT
  type        = string
}

# --- ArgoCD ----------------------------------------------------------------

variable "argocd_namespace" {
  description = "Namespace onde o ArgoCD é instalado."
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = <<-EOT
    Versão do chart argo-cd (repo argoproj.github.io/argo-helm).
    A 10.8.4 entrega o ArgoCD v3.5.2.
  EOT
  type        = string
  default     = "10.8.4"
}

variable "argocd_apps_chart_version" {
  description = "Versão do chart argocd-apps, que cria o recurso Application."
  type        = string
  default     = "2.0.5"
}

variable "reconciliation_timeout" {
  description = <<-EOT
    Intervalo de polling do Git pelo ArgoCD. O padrão do produto é 3m, que
    torna a demonstração de sync automático lenta demais para o vídeo.
  EOT
  type        = string
  default     = "30s"
}

variable "reconciliation_jitter" {
  description = <<-EOT
    Atraso aleatório somado ao intervalo de polling. O chart traz 60s por
    padrão, o que faria o sync levar de 30s a 90s de forma imprevisível na
    gravação. O jitter só é útil para espalhar o polling de muitas
    Applications; com uma só, zerar deixa a demonstração previsível.
  EOT
  type        = string
  default     = "0s"
}

variable "server_service_type" {
  description = <<-EOT
    Tipo do Service do argocd-server.

      ClusterIP    - padrão; acesse via `kubectl port-forward` (recomendado)
      LoadBalancer - cria um ELB público na AWS (custa e expõe a UI na internet)
  EOT
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.server_service_type)
    error_message = "Use ClusterIP, NodePort ou LoadBalancer."
  }
}

variable "server_insecure" {
  description = <<-EOT
    Faz o argocd-server servir HTTP puro. Ative APENAS se for expor a UI por
    um Ingress nginx — ele não faz passthrough de TLS e o ArgoCD em HTTPS
    resulta em 502 ou redirect infinito. Para port-forward, mantenha false.
  EOT
  type        = bool
  default     = false
}

variable "helm_timeout_seconds" {
  description = "Tempo máximo de espera pelos pods do ArgoCD ficarem prontos."
  type        = number
  default     = 900
}

# --- GitOps ----------------------------------------------------------------

variable "application_name" {
  description = "Nome da Application no ArgoCD (é o card que aparece na UI)."
  type        = string
  default     = "toggle-master"
}

variable "gitops_repo_url" {
  description = "Repositório que o ArgoCD observa."
  type        = string
  default     = "https://github.com/ProjetoFIAPToggleMaster/toggle-master-microservices.git"
}

variable "gitops_target_revision" {
  description = "Branch observada pelo ArgoCD."
  type        = string
  default     = "master"
}

variable "gitops_path" {
  description = "Pasta do repositório com os manifestos (o ArgoCD detecta o kustomization.yaml sozinho)."
  type        = string
  default     = "k8s/overlays/prod"
}

variable "app_namespace" {
  description = "Namespace de destino dos 5 microsserviços."
  type        = string
  default     = "toggle-master"
}
