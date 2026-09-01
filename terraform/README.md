# Infraestrutura como Código — Toggle Master (Fase 3)

Projeto Terraform que substitui o provisionamento manual da Fase 2.
Provider oficial [`hashicorp/aws`](https://registry.terraform.io/providers/hashicorp/aws/latest).

## Estrutura

```
terraform/
├── backend.tf                 # backend remoto S3 (tfstate) + lock nativo (use_lockfile)
├── backend.hcl.example        # valores do backend a preencher (bucket, profile)
├── providers.tf               # provider AWS (profile parametrizável) + default_tags
├── versions.tf                # constraints de versão do Terraform e providers
├── variables.tf               # variáveis globais
├── main.tf                    # composição dos módulos
├── outputs.tf                 # outputs raiz
├── terraform.tfvars.example   # exemplo de valores
├── bootstrap/                 # cria o bucket S3 do backend (state local, roda 1x)
└── modules/
    └── networking/            # item 1 — VPC, subnets, IGW, NAT, route tables
```

## Pré-requisitos

- Terraform >= 1.11 (usa `use_lockfile` para lock nativo no S3, sem DynamoDB)
- Credenciais AWS configuradas em um profile (`~/.aws/config`)

## Passo a passo

### 1. Criar o bucket do backend (uma vez)

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="aws_profile=SEU_PROFILE"
```

Anote o output `state_bucket_name`.

### 2. Inicializar a raiz apontando para o backend

```bash
cd terraform
cp backend.hcl.example backend.hcl   # preencha bucket e profile
terraform init -backend-config=backend.hcl
```

### 3. Planejar e aplicar

```bash
cp terraform.tfvars.example terraform.tfvars   # preencha aws_profile
terraform plan
terraform apply
```

## Onde preencher as credenciais

| Local | Como |
|---|---|
| `bootstrap/` | `-var="aws_profile=..."` ou `terraform.tfvars` |
| Backend da raiz | `profile` em `backend.hcl` |
| Provider da raiz | `aws_profile` em `terraform.tfvars` |

Deixe os campos de profile vazios (`""`) para usar a cadeia de credenciais
padrão da AWS (variáveis de ambiente, SSO, instance profile, etc).

## Item 1 — Networking (`modules/networking`)

Provisiona:

- **VPC** dedicada (`vpc_cidr`, DNS support/hostnames habilitados)
- **Subnets públicas** — 1 por AZ, com `map_public_ip_on_launch`
- **Subnets privadas** — 1 por AZ
- **Internet Gateway** + route table pública com rota default para o IGW
- **NAT Gateway** — opcional (`enable_nat_gateway`), único compartilhado
  (`single_nat_gateway = true`) ou um por AZ, com EIP dedicado
- **Route tables privadas** — rota default para o NAT quando habilitado

As subnets já recebem as tags de descoberta do EKS
(`kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb`,
`kubernetes.io/cluster/<nome>`) para o item 2.

### Principais variáveis

| Variável | Default | Descrição |
|---|---|---|
| `aws_region` | `us-east-1` | Região |
| `aws_profile` | `""` | Profile de credenciais |
| `vpc_cidr` | `10.0.0.0/16` | CIDR da VPC |
| `az_count` | `2` | Nº de AZs (quando `availability_zones` vazio) |
| `subnet_newbits` | `8` | Tamanho das subnets (/16 + 8 = /24) |
| `enable_nat_gateway` | `true` | Cria NAT Gateway |
| `single_nat_gateway` | `true` | Um NAT compartilhado vs. um por AZ |
| `eks_cluster_name` | `toggle-master-eks` | Nome usado nas tags de subnet do EKS |

### Outputs

`vpc_id`, `vpc_cidr_block`, `public_subnet_ids`, `private_subnet_ids`,
`internet_gateway_id`, `nat_gateway_ids`, `availability_zones`.

## Roadmap (próximos itens do desafio)

- [ ] 2. Cluster EKS + Node Groups (atenção à `LabRole` no AWS Academy)
- [ ] 3. Bancos: 3x RDS PostgreSQL, 1x ElastiCache Redis, 1x DynamoDB `ToggleMasterAnalytics`
- [ ] 4. Mensageria: 1x fila SQS
- [ ] 5. Repositórios ECR (5x)
