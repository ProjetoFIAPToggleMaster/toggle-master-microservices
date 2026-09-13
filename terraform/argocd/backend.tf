# ---------------------------------------------------------------------------
# Backend remoto do tfstate (S3)
# ---------------------------------------------------------------------------
# Mesmo bucket do estágio 1, mas com `key` diferente: cada estágio tem o seu
# próprio state, isolado. É o que permite destruir/recriar o ArgoCD sem tocar
# na infraestrutura, e vice-versa.
#
# O bucket é criado uma única vez por ./bootstrap. Inicialize com:
#
#   terraform init -backend-config=../backend.hcl
#
# ou informando os valores direto:
#
#   terraform init \
#     -backend-config="bucket=<NOME_DO_BUCKET_DE_STATE>" \
#     -backend-config="profile=<SEU_PROFILE_AWS>"
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {
    key          = "argocd/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
