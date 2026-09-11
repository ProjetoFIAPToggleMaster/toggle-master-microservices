# Estágio 2 — ArgoCD

Instala o ArgoCD no cluster EKS e cria a `Application` que observa
`k8s/overlays/prod`, fechando o ciclo GitOps.

## Por que é um estágio separado

Configurar o provider `helm` com dados de um cluster criado no **mesmo**
`apply` é um anti-padrão do Terraform: no primeiro `plan` o endpoint e o token
ainda não existem, e o provider falha com *"Provider configuration not known
until apply"*.

Aqui o cluster já existe e é apenas **lido** por data source, então o provider
sempre tem credencial válida. É o mesmo padrão de `../bootstrap`.

## Por que o ArgoCD não está no kustomize

O `k8s/overlays/prod` contém os 5 microsserviços — e o ArgoCD é quem os
implanta. Ele não pode implantar a si mesmo.

Além disso, o recurso `Application` usa o CRD `argoproj.io/v1alpha1`, que só
passa a existir **depois** que o ArgoCD está instalado. Por isso são dois
`helm_release` encadeados por `depends_on`, e por isso o segundo usa o chart
`argocd-apps` em vez de `kubernetes_manifest` (que validaria o CRD já no
`plan`, quando ele ainda não existe).

## Pré-requisitos

1. Estágio 1 (`../`) aplicado — o cluster EKS precisa estar no ar.
2. Credenciais AWS válidas no ambiente.
3. Bucket de state criado por `../bootstrap`.

## Como aplicar

Descubra o nome do cluster a partir do estado do estágio 1:

```bash
terraform -chdir=.. output -raw eks_cluster_name
```

Inicialize apontando para o bucket de state:

```bash
terraform init -backend-config=../backend.hcl
```

Aplique informando o nome do cluster:

```bash
terraform apply -var="cluster_name=<NOME_DO_CLUSTER>"
```

## Depois do apply

Aponte o `kubectl` para o cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name <NOME_DO_CLUSTER>
```

Pegue a senha inicial do `admin`:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

> A senha **não** é exposta como output de propósito: isso a gravaria em texto
> claro no `tfstate`. O Secret é gerado pelo próprio ArgoCD na instalação.

Abra a UI (deixe rodando em um terminal separado) em https://localhost:8080:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Confira o sync pela linha de comando:

```bash
kubectl get applications -n argocd
```

## Variáveis que talvez você queira ajustar

| Variável | Padrão | Quando mexer |
|---|---|---|
| `cluster_name` | — | **obrigatória** |
| `reconciliation_timeout` | `30s` | padrão do ArgoCD é `3m`, lento demais para demonstrar sync no vídeo |
| `server_service_type` | `ClusterIP` | `LoadBalancer` cria um ELB público (custa e expõe a UI) |
| `server_insecure` | `false` | `true` **apenas** se expuser a UI via Ingress nginx |
| `gitops_target_revision` | `master` | se observar outra branch |

## Destruir apenas o ArgoCD

```bash
terraform destroy -var="cluster_name=<NOME_DO_CLUSTER>"
```

Como o state é isolado por `key` no S3, isso não toca na infraestrutura do
estágio 1.
