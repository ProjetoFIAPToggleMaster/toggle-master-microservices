variable "name_prefix" {
  description = "Prefixo aplicado ao nome dos recursos auxiliares (roles, node group)."
  type        = string
}

variable "cluster_name" {
  description = <<-EOT
    Nome do cluster EKS. Precisa ser idêntico ao valor usado nas tags de
    descoberta das subnets (kubernetes.io/cluster/<nome>) criadas pelo
    módulo de networking, senão o EKS não reconhece as subnets.
  EOT
  type        = string
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes do control plane."
  type        = string
  default     = "1.31"
}

variable "private_subnet_ids" {
  description = "Subnets privadas onde os nodes serão lançados."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = <<-EOT
    Subnets públicas. Entram apenas na configuração do control plane para
    permitir que Load Balancers públicos (nginx ingress) sejam criados nelas.
    Os nodes NÃO são lançados aqui.
  EOT
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Endpoint do control plane
# ---------------------------------------------------------------------------

variable "endpoint_public_access" {
  description = "Expõe o endpoint da API do cluster à internet (necessário para kubectl fora da VPC)."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = <<-EOT
    CIDRs autorizados a acessar o endpoint público da API. O padrão
    0.0.0.0/0 é permissivo; restrinja ao IP da equipe em produção real.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = <<-EOT
    Tipos de log do control plane enviados ao CloudWatch. Cada tipo gera
    custo de ingestão/armazenamento, por isso o padrão é vazio. Para uma
    postura de segurança mais forte, habilite ["api", "audit"].
  EOT
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Node group
# ---------------------------------------------------------------------------

variable "node_instance_types" {
  description = <<-EOT
    Tipos de instância dos nodes. t3.medium é o padrão porque o limite de
    pods por node no EKS é derivado do número de ENIs/IPs do tipo de
    instância: t3.micro suporta ~4 pods e t3.small ~11 — insuficiente depois
    de somar os pods de sistema (CoreDNS, kube-proxy, aws-node), o ingress
    controller e os 5 microsserviços. t3.medium suporta ~17 pods por node.
  EOT
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = <<-EOT
    ON_DEMAND ou SPOT. SPOT custa bem menos, mas a instância pode ser
    recuperada pela AWS com 2 minutos de aviso.
  EOT
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type deve ser ON_DEMAND ou SPOT."
  }
}

variable "node_desired_size" {
  description = "Quantidade desejada de nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Quantidade mínima de nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = <<-EOT
    Quantidade máxima de nodes. Precisa deixar folga para o HPA escalar os
    pods: se todos os nodes estiverem cheios, os pods novos ficam Pending.
  EOT
  type        = number
  default     = 4
}

variable "node_disk_size" {
  description = "Tamanho do disco EBS de cada node, em GB."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------------------
# Addons
# ---------------------------------------------------------------------------

variable "cluster_addons" {
  description = <<-EOT
    Addons gerenciados pelo EKS. metrics-server entra aqui de propósito:
    instalado como addon, ele já vem configurado corretamente para o EKS,
    evitando a instalação manual via manifesto (que exige corrigir selector
    duplicado e adicionar --kubelet-insecure-tls na mão). Sem ele, o HPA
    não consegue ler CPU e não escala.
  EOT
  type        = list(string)
  default     = ["vpc-cni", "coredns", "kube-proxy", "metrics-server"]
}

variable "tags" {
  description = "Tags aplicadas a todos os recursos do módulo."
  type        = map(string)
  default     = {}
}
