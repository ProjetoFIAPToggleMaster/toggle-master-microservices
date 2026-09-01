# ---------------------------------------------------------------------------
# Backend remoto do tfstate (S3)
# ---------------------------------------------------------------------------
# O bucket S3 referenciado aqui NÃO é criado por esta raiz (problema do
# "ovo e a galinha"). Ele é provisionado uma única vez pela configuração
# em ./bootstrap. Depois disso, rode:
#
#   terraform init \
#     -backend-config="bucket=<NOME_DO_BUCKET_DE_STATE>" \
#     -backend-config="profile=<SEU_PROFILE_AWS>"
#
# ou preencha um arquivo backend.hcl (veja backend.hcl.example) e use:
#
#   terraform init -backend-config=backend.hcl
#
# Lock nativo do S3 via use_lockfile (Terraform >= 1.11), dispensando
# a tabela DynamoDB de lock.
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {
    # bucket  = "toggle-master-tfstate"   # informado via -backend-config
    key          = "networking/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true

    # profile = "toggle-master"           # informado via -backend-config
  }
}
