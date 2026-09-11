provider "aws" {
  region = var.aws_region

  # Deixe aws_profile vazio para cair na cadeia de credenciais padrão
  # (env vars, SSO, instance profile). Na AWS Academy, que exporta variáveis
  # de sessão temporárias, é esse o caminho.
  profile = var.aws_profile != "" ? var.aws_profile : null
}

# ---------------------------------------------------------------------------
# Leitura do cluster provisionado pelo estágio 1
# ---------------------------------------------------------------------------
# Estes data sources existem para alimentar o provider `helm` abaixo. Como o
# cluster já existe quando este estágio roda, o endpoint e o token são
# conhecidos ainda no `plan` — que é justamente o motivo de este ser um root
# module separado.
#
# O token do aws_eks_cluster_auth é temporário (~15 min) e regerado a cada
# plan/apply, então não há credencial de longa duração no state.
# ---------------------------------------------------------------------------
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
