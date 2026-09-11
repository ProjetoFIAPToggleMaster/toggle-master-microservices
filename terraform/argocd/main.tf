# ---------------------------------------------------------------------------
# Estágio 2 — ArgoCD no cluster EKS
# ---------------------------------------------------------------------------
# Este é um root module SEPARADO de propósito.
#
# Configurar o provider `helm` com dados de um cluster criado no MESMO apply é
# um anti-padrão conhecido do Terraform: no primeiro `plan` o endpoint e o
# token ainda não existem, e o provider falha com "Provider configuration not
# known until apply". Como aqui o cluster já foi criado pelo estágio 1 e é
# apenas LIDO via data source (ver providers.tf), o provider sempre tem
# credencial válida.
#
# Ordem de execução:
#   1. terraform/         -> VPC, EKS, RDS, ElastiCache, SQS, DynamoDB, ECR
#   2. terraform/argocd/  -> ESTE estágio: instala o ArgoCD + a Application
#
# Por que o ArgoCD não está no kustomize da aplicação:
# o `k8s/overlays/prod` contém os 5 microsserviços, e o ArgoCD é quem os
# implanta — ele não pode implantar a si mesmo. Além disso, o recurso
# `Application` usa o CRD argoproj.io/v1alpha1, que só existe DEPOIS que o
# ArgoCD está instalado. Daí os dois helm_release encadeados por depends_on.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1. ArgoCD
# ---------------------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true

  # Espera os pods ficarem prontos antes de o Terraform seguir para a
  # Application. Sem isso, o segundo release pode tentar criar um recurso
  # cujo CRD ainda está sendo registrado.
  wait    = true
  timeout = var.helm_timeout_seconds

  values = [yamlencode({
    configs = {
      cm = {
        # Intervalo de polling do Git. O padrão do ArgoCD é 3 minutos — tempo
        # demais para demonstrar o sync automático na gravação do vídeo.
        "timeout.reconciliation" = var.reconciliation_timeout

        # O chart traz jitter de 60s por padrão, somado ao intervalo acima:
        # o sync levaria de 30s a 90s, de forma imprevisível. O jitter serve
        # para espalhar o polling de MUITAS Applications e evitar pico de
        # carga; com uma só, ele apenas torna a demonstração lenta e errática.
        "timeout.reconciliation.jitter" = var.reconciliation_jitter
      }
      params = {
        # Com true, o argocd-server serve HTTP puro. Necessário APENAS se a UI
        # for exposta por um Ingress nginx (que não faz passthrough de TLS).
        # Para acesso via `kubectl port-forward`, deixe false.
        "server.insecure" = var.server_insecure
      }
    }
    server = {
      service = {
        type = var.server_service_type
      }
    }
  })]
}

# ---------------------------------------------------------------------------
# 2. Application apontando para o overlay de produção
# ---------------------------------------------------------------------------
# Usa o chart oficial `argocd-apps` em vez do recurso `kubernetes_manifest`.
# Motivo: o kubernetes_manifest valida o schema contra a API do cluster no
# momento do PLAN, o que falha enquanto o CRD Application não existe — o mesmo
# problema do ovo e da galinha. O Helm renderiza no APPLY, já com o CRD no ar.
# ---------------------------------------------------------------------------
resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = var.argocd_namespace

  depends_on = [helm_release.argocd]

  values = [yamlencode({
    applications = {
      (var.application_name) = {
        namespace = var.argocd_namespace
        project   = "default"

        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_target_revision
          path           = var.gitops_path
        }

        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.app_namespace
        }

        syncPolicy = {
          automated = {
            # prune: removeu do Git -> remove do cluster.
            prune = true
            # selfHeal: alterou o cluster na mão -> reverte para o Git.
            selfHeal = true
          }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]
}
