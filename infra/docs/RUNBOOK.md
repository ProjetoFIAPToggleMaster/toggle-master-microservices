# RUNBOOK — Provisionamento ToggleMaster na AWS (EKS)

Guia de execução passo a passo, **na ordem exata**, com comandos para
**Linux**, **macOS** e **Windows (PowerShell)**.

> Nenhum comando aqui é destrutivo até a seção **Teardown**. Rode tudo como o
> mesmo usuário IAM (o criador do cluster é o único que ganha acesso admin ao
> Kubernetes automaticamente).

---

## 🔖 Legenda — como executar cada bloco

| Marcador | Significado |
|---|---|
| 🟢 **BLOCO ÚNICO** | Copie e cole o bloco inteiro de uma vez. |
| 🔵 **EM SEQUÊNCIA** | Rode um comando, confira que funcionou, depois o próximo. |
| 🟡 **RODAR → ESPERAR → ANOTAR** | Dispare, aguarde ficar pronto e **copie o valor de saída** (você vai usá-lo depois). |
| 🟣 **TERMINAL SEPARADO** | Deixe rodando numa **outra janela** de terminal (não feche). |

## 💻 Qual terminal usar por SO

- **Linux** → `bash`
- **macOS** → `zsh` ou `bash` (praticamente igual ao Linux; só o `sed` muda)
- **Windows** → **PowerShell** (⚠️ **não** use o CMD). Abra o "Windows PowerShell".

Diferenças de sintaxe que você verá nos blocos:

| | Linux / macOS (bash/zsh) | Windows (PowerShell) |
|---|---|---|
| Definir variável | `export VAR=valor` | `$VAR = "valor"` |
| Variável de um comando | `export VAR=$(comando)` | `$VAR = (comando)` |
| Usar variável | `${VAR}` | `${VAR}` |
| Loop | `for x in a b; do ...; done` | `foreach ($x in "a","b") { ... }` |

> Onde o comando é **idêntico** nos 3 sistemas, o bloco aparece **uma vez**.
> Onde muda, há um bloco para **Linux / macOS** e outro para **Windows**.
> Sempre uso `${VAR}` (com chaves) para funcionar igual nos dois shells.

---

## 🔐 Como os Secrets funcionam (leia antes)

**O que é.** Um `Secret` é um objeto do Kubernetes que guarda valores sensíveis
(senhas, endpoints, chaves). O Deployment o referencia via `envFrom.secretRef` e
o Kubernetes injeta os valores como **variáveis de ambiente** no container. O app
lê com `os.Getenv(...)` — sem saber que veio de um Secret.

```
Secret (DATABASE_URL, MASTER_KEY, ...)
        │  envFrom.secretRef
        ▼
Deployment ──► env vars ──► Container ──► os.Getenv("DATABASE_URL")
```

**base64 / stringData.** O campo `data:` de um Secret exige base64. Para não ter
que rodar `base64` na mão, criamos os Secrets com `kubectl create secret ...
--from-literal` (texto puro) — o Kubernetes converte para base64 sozinho. O
requisito "secrets em base64" é cumprido automaticamente (veja com
`kubectl get secret auth-secret -n auth -o yaml`).

**Nesta stack** os Secrets são criados **imperativamente** (nenhuma senha vai pro
git). Os arquivos `secret.example.yaml` servem só como referência da estrutura.

**Ordem importa:** o Secret precisa existir **antes** do Deployment que o usa,
senão o pod fica em `CreateContainerConfigError`.

---

## 0. Pré-requisitos (uma vez por terminal)

> ⚠️ Essas variáveis valem só para **a janela atual**. Se abrir outro terminal
> (ex.: 🟣), exporte de novo. Troque as senhas pelos seus valores.

🟢 **BLOCO ÚNICO — Linux / macOS:**
```bash
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
export CLUSTER=toggle-master
export PROJ=~/dev/toggle-master-microservices
export AUTH_DB_PASS='Troque_Auth_123'
export FLAG_DB_PASS='Troque_Flag_123'
export TARG_DB_PASS='Troque_Targ_123'
export MASTER_KEY='admin-secreto-123'
```

🟢 **BLOCO ÚNICO — Windows (PowerShell):**
```powershell
$AWS_REGION = "us-east-1"
$AWS_ACCOUNT_ID = (aws sts get-caller-identity --query Account --output text)
$ECR = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
$CLUSTER = "toggle-master"
$PROJ = "$HOME/dev/toggle-master-microservices"
$AUTH_DB_PASS = "Troque_Auth_123"
$FLAG_DB_PASS = "Troque_Flag_123"
$TARG_DB_PASS = "Troque_Targ_123"
$MASTER_KEY = "admin-secreto-123"
```

✅ Confira: `echo ${AWS_ACCOUNT_ID}` mostra seu número de conta (12 dígitos).

---

# ETAPA 1 — ECR (repositórios + imagens)

### 1.1 — Criar os 5 repositórios
🟢 **BLOCO ÚNICO — Linux / macOS:**
```bash
for s in auth-service flag-service targeting-service evaluation-service analytics-service; do
  aws ecr create-repository --repository-name ${s} --region ${AWS_REGION}
done
```
🟢 **BLOCO ÚNICO — Windows (PowerShell):**
```powershell
foreach ($s in "auth-service","flag-service","targeting-service","evaluation-service","analytics-service") {
  aws ecr create-repository --repository-name $s --region ${AWS_REGION}
}
```

### 1.2 — Login do Docker no ECR
🔵 **EM SEQUÊNCIA — Linux / macOS:**
```bash
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR}
```
🔵 **EM SEQUÊNCIA — Windows (PowerShell):**
```powershell
(aws ecr get-login-password --region ${AWS_REGION}) | docker login --username AWS --password-stdin ${ECR}
```
✅ Aparece `Login Succeeded`.

### 1.3 — Build + push das 5 imagens (linux/amd64)
> Os nós são x86 (t3). No Mac (ARM) sem `--platform` o pod dá `exec format error`.

🟢 **BLOCO ÚNICO — Linux / macOS:**
```bash
cd ${PROJ}
for s in auth-service flag-service targeting-service evaluation-service analytics-service; do
  docker buildx build --platform linux/amd64 -t ${ECR}/${s}:latest ./${s} --push
done
```
🟢 **BLOCO ÚNICO — Windows (PowerShell):**
```powershell
cd ${PROJ}
foreach ($s in "auth-service","flag-service","targeting-service","evaluation-service","analytics-service") {
  docker buildx build --platform linux/amd64 -t "${ECR}/${s}:latest" "./$s" --push
}
```
⏳ Espere o build+push das 5 terminar. ✅ `aws ecr list-images --repository-name auth-service` mostra a tag `latest`.

---

# ETAPA 2 — Cluster EKS

### 2.1 — Criar o cluster (idêntico nos 3 SOs)
🟡 **RODAR → ESPERAR:**
```bash
eksctl create cluster -f ${PROJ}/infra/eks/cluster.yaml
```
⏳ ~15 min. O eksctl cria VPC, subnets, nós, OIDC e configura o `kubectl`.
✅ Confira:
```bash
kubectl get nodes
```
Deve mostrar **2 nós** `Ready`.

### 2.2 — Capturar identificadores da VPC
🟡 **RODAR → ANOTAR — Linux / macOS:**
```bash
export VPC_ID=$(aws eks describe-cluster --name ${CLUSTER} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.vpcId' --output text)
export CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
export PRIV_SUBNETS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=${VPC_ID} Name=tag:Name,Values="*Private*" --query 'Subnets[].SubnetId' --output text)
echo "VPC=${VPC_ID}"; echo "CLUSTER_SG=${CLUSTER_SG}"; echo "PRIV_SUBNETS=${PRIV_SUBNETS}"
```
🟡 **RODAR → ANOTAR — Windows (PowerShell):**
```powershell
$VPC_ID = (aws eks describe-cluster --name ${CLUSTER} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.vpcId' --output text)
$CLUSTER_SG = (aws eks describe-cluster --name ${CLUSTER} --region ${AWS_REGION} --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
$PRIV_SUBNETS = (aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Private*" --query 'Subnets[].SubnetId' --output text) -split "\s+"
echo "VPC=${VPC_ID}"; echo "CLUSTER_SG=${CLUSTER_SG}"; echo "PRIV_SUBNETS=${PRIV_SUBNETS}"
```
✅ Os 3 valores não podem estar vazios (`PRIV_SUBNETS` = 2 IDs).

---

# ETAPA 3 — Rede dos data stores

### 3.1 — Criar o Security Group dos bancos
🟡 **RODAR → ANOTAR — Linux / macOS:**
```bash
export DATA_SG=$(aws ec2 create-security-group --group-name toggle-data-sg --description "RDS+Redis toggle" --vpc-id ${VPC_ID} --query GroupId --output text)
echo "DATA_SG=${DATA_SG}"
```
🟡 **RODAR → ANOTAR — Windows (PowerShell):**
```powershell
$DATA_SG = (aws ec2 create-security-group --group-name toggle-data-sg --description "RDS+Redis toggle" --vpc-id ${VPC_ID} --query GroupId --output text)
echo "DATA_SG=${DATA_SG}"
```

### 3.2 — Liberar 5432 e 6379 só a partir do cluster (idêntico nos 3 SOs)
🔵 **EM SEQUÊNCIA (rode os dois, um após o outro):**
```bash
aws ec2 authorize-security-group-ingress --group-id ${DATA_SG} --protocol tcp --port 5432 --source-group ${CLUSTER_SG}
```
```bash
aws ec2 authorize-security-group-ingress --group-id ${DATA_SG} --protocol tcp --port 6379 --source-group ${CLUSTER_SG}
```

### 3.3 — Subnet groups do RDS e do ElastiCache (idêntico nos 3 SOs)
🔵 **EM SEQUÊNCIA (rode os dois):**
```bash
aws rds create-db-subnet-group --db-subnet-group-name toggle-db-subnets --db-subnet-group-description "toggle private subnets" --subnet-ids ${PRIV_SUBNETS}
```
```bash
aws elasticache create-cache-subnet-group --cache-subnet-group-name toggle-cache-subnets --cache-subnet-group-description "toggle private subnets" --subnet-ids ${PRIV_SUBNETS}
```

---

# ETAPA 4 — Bancos e mensageria

> RDS/Redis demoram. Dispare tudo e siga adiantando DynamoDB/SQS.

### 4.1 — RDS ×3 (idêntico nos 3 SOs)
🔵 **EM SEQUÊNCIA (pode disparar os 3 seguidos):**
```bash
aws rds create-db-instance --db-instance-identifier toggle-auth --db-name auth_db --engine postgres --engine-version 15 --db-instance-class db.t3.micro --allocated-storage 20 --storage-type gp3 --master-username postgres --master-user-password "${AUTH_DB_PASS}" --db-subnet-group-name toggle-db-subnets --vpc-security-group-ids ${DATA_SG} --no-publicly-accessible --no-multi-az --backup-retention-period 0
```
```bash
aws rds create-db-instance --db-instance-identifier toggle-flag --db-name flags_db --engine postgres --engine-version 15 --db-instance-class db.t3.micro --allocated-storage 20 --storage-type gp3 --master-username postgres --master-user-password "${FLAG_DB_PASS}" --db-subnet-group-name toggle-db-subnets --vpc-security-group-ids ${DATA_SG} --no-publicly-accessible --no-multi-az --backup-retention-period 0
```
```bash
aws rds create-db-instance --db-instance-identifier toggle-targeting --db-name targeting_db --engine postgres --engine-version 15 --db-instance-class db.t3.micro --allocated-storage 20 --storage-type gp3 --master-username postgres --master-user-password "${TARG_DB_PASS}" --db-subnet-group-name toggle-db-subnets --vpc-security-group-ids ${DATA_SG} --no-publicly-accessible --no-multi-az --backup-retention-period 0
```

### 4.2 — ElastiCache Redis (idêntico nos 3 SOs)
🟢 **BLOCO ÚNICO:**
```bash
aws elasticache create-cache-cluster --cache-cluster-id toggle-redis --engine redis --cache-node-type cache.t3.micro --num-cache-nodes 1 --cache-subnet-group-name toggle-cache-subnets --security-group-ids ${DATA_SG}
```

### 4.3 — DynamoDB (idêntico nos 3 SOs)
🟢 **BLOCO ÚNICO:**
```bash
aws dynamodb create-table --table-name ToggleMasterAnalytics --attribute-definitions AttributeName=event_id,AttributeType=S --key-schema AttributeName=event_id,KeyType=HASH --billing-mode PAY_PER_REQUEST
```

### 4.4 — SQS + capturar URL/ARN
🔵 **EM SEQUÊNCIA (crie a fila primeiro):**
```bash
aws sqs create-queue --queue-name toggle-evaluations
```
🟡 **RODAR → ANOTAR — Linux / macOS:**
```bash
export SQS_URL=$(aws sqs get-queue-url --queue-name toggle-evaluations --query QueueUrl --output text)
export SQS_ARN=$(aws sqs get-queue-attributes --queue-url ${SQS_URL} --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
echo "SQS_URL=${SQS_URL}"; echo "SQS_ARN=${SQS_ARN}"
```
🟡 **RODAR → ANOTAR — Windows (PowerShell):**
```powershell
$SQS_URL = (aws sqs get-queue-url --queue-name toggle-evaluations --query QueueUrl --output text)
$SQS_ARN = (aws sqs get-queue-attributes --queue-url ${SQS_URL} --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)
echo "SQS_URL=${SQS_URL}"; echo "SQS_ARN=${SQS_ARN}"
```

### 4.5 — Esperar RDS e capturar endpoints
🟡 **RODAR → ESPERAR (bloqueante, idêntico nos 3 SOs):**
```bash
aws rds wait db-instance-available --db-instance-identifier toggle-auth
aws rds wait db-instance-available --db-instance-identifier toggle-flag
aws rds wait db-instance-available --db-instance-identifier toggle-targeting
```
🟡 **RODAR → ANOTAR — Linux / macOS:**
```bash
export AUTH_DB_HOST=$(aws rds describe-db-instances --db-instance-identifier toggle-auth --query 'DBInstances[0].Endpoint.Address' --output text)
export FLAG_DB_HOST=$(aws rds describe-db-instances --db-instance-identifier toggle-flag --query 'DBInstances[0].Endpoint.Address' --output text)
export TARG_DB_HOST=$(aws rds describe-db-instances --db-instance-identifier toggle-targeting --query 'DBInstances[0].Endpoint.Address' --output text)
export REDIS_HOST=$(aws elasticache describe-cache-clusters --cache-cluster-id toggle-redis --show-cache-node-info --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' --output text)
echo "${AUTH_DB_HOST}"; echo "${FLAG_DB_HOST}"; echo "${TARG_DB_HOST}"; echo "${REDIS_HOST}"
```
🟡 **RODAR → ANOTAR — Windows (PowerShell):**
```powershell
$AUTH_DB_HOST = (aws rds describe-db-instances --db-instance-identifier toggle-auth --query 'DBInstances[0].Endpoint.Address' --output text)
$FLAG_DB_HOST = (aws rds describe-db-instances --db-instance-identifier toggle-flag --query 'DBInstances[0].Endpoint.Address' --output text)
$TARG_DB_HOST = (aws rds describe-db-instances --db-instance-identifier toggle-targeting --query 'DBInstances[0].Endpoint.Address' --output text)
$REDIS_HOST = (aws elasticache describe-cache-clusters --cache-cluster-id toggle-redis --show-cache-node-info --query 'CacheClusters[0].CacheNodes[0].Endpoint.Address' --output text)
echo "${AUTH_DB_HOST}"; echo "${FLAG_DB_HOST}"; echo "${TARG_DB_HOST}"; echo "${REDIS_HOST}"
```
> Se o Redis ainda não estiver `available`, o `REDIS_HOST` vem vazio — espere 1-2 min e rode só a linha do Redis de novo.

---

# ETAPA 5 — Namespaces + IRSA

### 5.1 — Namespaces (idêntico nos 3 SOs)
🟢 **BLOCO ÚNICO:**
```bash
kubectl apply -f ${PROJ}/infra/k8s/00-namespaces.yaml
```
✅ `kubectl get ns` lista auth, flags, targeting, evaluation, analytics.

### 5.2 — Policy + ServiceAccount do analytics (SQS + DynamoDB)
🟢 **BLOCO ÚNICO — Linux / macOS (cria a policy):**
```bash
cat > /tmp/analytics-policy.json <<EOF
{ "Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],"Resource":"${SQS_ARN}"},
  {"Effect":"Allow","Action":["dynamodb:PutItem"],"Resource":"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/ToggleMasterAnalytics"}
]}
EOF
aws iam create-policy --policy-name toggle-analytics-policy --policy-document file:///tmp/analytics-policy.json
```
🟢 **BLOCO ÚNICO — Windows (PowerShell) (cria a policy):**
```powershell
@"
{ "Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":["sqs:ReceiveMessage","sqs:DeleteMessage","sqs:GetQueueAttributes"],"Resource":"${SQS_ARN}"},
  {"Effect":"Allow","Action":["dynamodb:PutItem"],"Resource":"arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/ToggleMasterAnalytics"}
]}
"@ | Out-File -Encoding ascii "$env:TEMP\analytics-policy.json"
aws iam create-policy --policy-name toggle-analytics-policy --policy-document "file://$env:TEMP\analytics-policy.json"
```
🔵 **EM SEQUÊNCIA (cria a SA com IRSA — idêntico nos 3 SOs):**
```bash
eksctl create iamserviceaccount --cluster ${CLUSTER} --namespace analytics --name analytics-sa --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/toggle-analytics-policy --approve
```
✅ `kubectl get sa analytics-sa -n analytics` existe e tem annotation `eks.amazonaws.com/role-arn`.

### 5.3 — Policy + ServiceAccount do evaluation (SQS SendMessage)
🟢 **BLOCO ÚNICO — Linux / macOS (cria a policy):**
```bash
cat > /tmp/eval-policy.json <<EOF
{ "Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":["sqs:SendMessage"],"Resource":"${SQS_ARN}"}
]}
EOF
aws iam create-policy --policy-name toggle-eval-policy --policy-document file:///tmp/eval-policy.json
```
🟢 **BLOCO ÚNICO — Windows (PowerShell) (cria a policy):**
```powershell
@"
{ "Version":"2012-10-17","Statement":[
  {"Effect":"Allow","Action":["sqs:SendMessage"],"Resource":"${SQS_ARN}"}
]}
"@ | Out-File -Encoding ascii "$env:TEMP\eval-policy.json"
aws iam create-policy --policy-name toggle-eval-policy --policy-document "file://$env:TEMP\eval-policy.json"
```
🔵 **EM SEQUÊNCIA (cria a SA com IRSA — idêntico nos 3 SOs):**
```bash
eksctl create iamserviceaccount --cluster ${CLUSTER} --namespace evaluation --name evaluation-sa --attach-policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/toggle-eval-policy --approve
```

---

# ETAPA 6 — Carregar o schema (init.sql) em cada RDS

> Os apps **não** criam tabelas sozinhos. Rode o `init.sql` uma vez por RDS,
> a partir de um pod temporário dentro do cluster (que enxerga o RDS privado).

🔵 **EM SEQUÊNCIA — Linux / macOS (rode os 3, um de cada vez):**
```bash
kubectl run psql-auth --rm -i --image=postgres:15-alpine --restart=Never -- psql "postgresql://postgres:${AUTH_DB_PASS}@${AUTH_DB_HOST}:5432/auth_db?sslmode=require" < ${PROJ}/auth-service/db/init.sql
```
```bash
kubectl run psql-flag --rm -i --image=postgres:15-alpine --restart=Never -- psql "postgres://postgres:${FLAG_DB_PASS}@${FLAG_DB_HOST}:5432/flags_db" < ${PROJ}/flag-service/db/init.sql
```
```bash
kubectl run psql-targ --rm -i --image=postgres:15-alpine --restart=Never -- psql "postgres://postgres:${TARG_DB_PASS}@${TARG_DB_HOST}:5432/targeting_db" < ${PROJ}/targeting-service/db/init.sql
```
🔵 **EM SEQUÊNCIA — Windows (PowerShell) (PowerShell não tem `<`; use `Get-Content |`):**
```powershell
Get-Content "${PROJ}/auth-service/db/init.sql" | kubectl run psql-auth --rm -i --image=postgres:15-alpine --restart=Never -- psql "postgresql://postgres:${AUTH_DB_PASS}@${AUTH_DB_HOST}:5432/auth_db?sslmode=require"
```
```powershell
Get-Content "${PROJ}/flag-service/db/init.sql" | kubectl run psql-flag --rm -i --image=postgres:15-alpine --restart=Never -- psql "postgres://postgres:${FLAG_DB_PASS}@${FLAG_DB_HOST}:5432/flags_db"
```
```powershell
Get-Content "${PROJ}/targeting-service/db/init.sql" | kubectl run psql-targ --rm -i --image=postgres:15-alpine --restart=Never -- psql "postgres://postgres:${TARG_DB_PASS}@${TARG_DB_HOST}:5432/targeting_db"
```
✅ Cada um mostra `CREATE TABLE` sem erro.

---

# ETAPA 7 — Ingress Controller (Nginx + NLB)

🔵 **EM SEQUÊNCIA (rode os dois — idêntico nos 3 SOs):**
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx && helm repo update
```
```bash
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace -f ${PROJ}/infra/eks/ingress-nginx-values.yaml
```
🟡 **RODAR → ESPERAR → ANOTAR (repita até aparecer um hostname):**
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
⏳ ~2-3 min até a AWS provisionar o NLB. Anote o hostname.

---

# ETAPA 8 — Deploy de auth, flag e targeting

### 8.1 — Trocar ACCOUNT_ID nas imagens dos manifestos
🟢 **BLOCO ÚNICO — Linux:**
```bash
grep -rl 'ACCOUNT_ID.dkr.ecr' ${PROJ}/infra/k8s | xargs sed -i "s/ACCOUNT_ID.dkr.ecr.us-east-1/${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1/g"
```
🟢 **BLOCO ÚNICO — macOS (o `sed -i` precisa do `''`):**
```bash
grep -rl 'ACCOUNT_ID.dkr.ecr' ${PROJ}/infra/k8s | xargs sed -i '' "s/ACCOUNT_ID.dkr.ecr.us-east-1/${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1/g"
```
🟢 **BLOCO ÚNICO — Windows (PowerShell):**
```powershell
Get-ChildItem -Recurse "${PROJ}/infra/k8s" -Filter *.yaml | ForEach-Object {
  (Get-Content $_.FullName) -replace 'ACCOUNT_ID\.dkr\.ecr\.us-east-1', "${AWS_ACCOUNT_ID}.dkr.ecr.us-east-1" | Set-Content $_.FullName
}
```

### 8.2 — Criar os Secrets (idêntico nos 3 SOs)
🔵 **EM SEQUÊNCIA (rode os três):**
```bash
kubectl create secret generic auth-secret -n auth --from-literal=DATABASE_URL="postgresql://postgres:${AUTH_DB_PASS}@${AUTH_DB_HOST}:5432/auth_db?sslmode=require" --from-literal=MASTER_KEY="${MASTER_KEY}"
```
```bash
kubectl create secret generic flag-secret -n flags --from-literal=DATABASE_URL="postgres://postgres:${FLAG_DB_PASS}@${FLAG_DB_HOST}:5432/flags_db"
```
```bash
kubectl create secret generic targeting-secret -n targeting --from-literal=DATABASE_URL="postgres://postgres:${TARG_DB_PASS}@${TARG_DB_HOST}:5432/targeting_db"
```

### 8.3 — Aplicar auth primeiro (idêntico nos 3 SOs)
🔵 **EM SEQUÊNCIA:**
```bash
kubectl apply -f ${PROJ}/infra/k8s/auth/configmap.yaml -f ${PROJ}/infra/k8s/auth/deployment.yaml -f ${PROJ}/infra/k8s/auth/service.yaml -f ${PROJ}/infra/k8s/auth/ingress.yaml
```
🟡 **RODAR → ESPERAR:**
```bash
kubectl rollout status deploy/auth-service -n auth
```

### 8.4 — Aplicar flag e targeting (idêntico nos 3 SOs)
🔵 **EM SEQUÊNCIA (rode os dois):**
```bash
kubectl apply -f ${PROJ}/infra/k8s/flags/configmap.yaml -f ${PROJ}/infra/k8s/flags/deployment.yaml -f ${PROJ}/infra/k8s/flags/service.yaml -f ${PROJ}/infra/k8s/flags/ingress.yaml
```
```bash
kubectl apply -f ${PROJ}/infra/k8s/targeting/configmap.yaml -f ${PROJ}/infra/k8s/targeting/deployment.yaml -f ${PROJ}/infra/k8s/targeting/service.yaml -f ${PROJ}/infra/k8s/targeting/ingress.yaml
```
✅ `kubectl get pods -n auth` / `-n flags` / `-n targeting` → todos `Running`.
Se algum der `CrashLoopBackOff`, veja `kubectl logs` (provável `DATABASE_URL`
errada ou schema não aplicado na ETAPA 6).

---

# ETAPA 9 — Bootstrap da API key + deploy do evaluation

> A `SERVICE_API_KEY` do evaluation é **criada pelo auth em runtime**.

### 9.1 — Túnel para o auth
🟣 **TERMINAL SEPARADO (deixe rodando; idêntico nos 3 SOs):**
```bash
kubectl -n auth port-forward svc/auth-service 8001:8001
```

### 9.2 — Gerar a chave (no terminal principal)
> 📝 Se abriu terminal novo, reexporte `MASTER_KEY` (passo 0).

🔵 **EM SEQUÊNCIA — Linux / macOS:**
```bash
curl -s -X POST http://localhost:8001/admin/keys -H "Authorization: Bearer ${MASTER_KEY}" -H "Content-Type: application/json" -d '{"name":"evaluation-service"}'
```
🔵 **EM SEQUÊNCIA — Windows (PowerShell) (use `curl.exe`, não o alias `curl`):**
```powershell
curl.exe -s -X POST http://localhost:8001/admin/keys -H "Authorization: Bearer ${MASTER_KEY}" -H "Content-Type: application/json" -d '{"name":"evaluation-service"}'
```
✅ A resposta tem `"key":"<UMA_CHAVE_LONGA>"`. **Copie a chave.** Pode fechar o
`port-forward` (Ctrl+C no terminal 🟣).

### 9.3 — Secret do evaluation (com a key)
> 📝 Substitua `<COLE_A_CHAVE_AQUI>` pela chave copiada. (Idêntico nos 3 SOs.)

🟢 **BLOCO ÚNICO:**
```bash
kubectl create secret generic evaluation-secret -n evaluation --from-literal=REDIS_URL="redis://${REDIS_HOST}:6379" --from-literal=AWS_SQS_URL="${SQS_URL}" --from-literal=SERVICE_API_KEY="<COLE_A_CHAVE_AQUI>"
```

### 9.4 — Deploy do evaluation (idêntico nos 3 SOs)
🔵 **EM SEQUÊNCIA:**
```bash
kubectl apply -f ${PROJ}/infra/k8s/evaluation/configmap.yaml -f ${PROJ}/infra/k8s/evaluation/deployment.yaml -f ${PROJ}/infra/k8s/evaluation/service.yaml -f ${PROJ}/infra/k8s/evaluation/ingress.yaml
```
🟡 **RODAR → ESPERAR:**
```bash
kubectl rollout status deploy/evaluation-service -n evaluation
```

---

# ETAPA 10 — Deploy do analytics (idêntico nos 3 SOs)

🔵 **EM SEQUÊNCIA (secret depois deploy):**
```bash
kubectl create secret generic analytics-secret -n analytics --from-literal=AWS_SQS_URL="${SQS_URL}"
```
```bash
kubectl apply -f ${PROJ}/infra/k8s/analytics/configmap.yaml -f ${PROJ}/infra/k8s/analytics/deployment.yaml
```
✅ `kubectl logs -n analytics deploy/analytics-service` mostra
`Iniciando o worker SQS...` sem erro de credencial (IRSA ok).

---

# ETAPA 11 — Autoscaling (HPA) (idêntico nos 3 SOs)

🟢 **BLOCO ÚNICO:**
```bash
kubectl apply -f ${PROJ}/infra/k8s/hpa/evaluation-hpa.yaml -f ${PROJ}/infra/k8s/hpa/analytics-hpa.yaml
```
✅ `kubectl get hpa -A` → coluna `TARGETS` mostra `%/70%` (não `<unknown>`).
Se `<unknown>`, o metrics-server ainda sobe — espere 1-2 min.

---

# ETAPA 12 — Validação (roteiro do vídeo)

🟡 **RODAR → ANOTAR — Linux / macOS:**
```bash
export NLB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo ${NLB}
```
🟡 **RODAR → ANOTAR — Windows (PowerShell):**
```powershell
$NLB = (kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo ${NLB}
```

🔵 **EM SEQUÊNCIA (tudo no ar — idêntico nos 3 SOs):**
```bash
kubectl get pods -A
```

🔵 **EM SEQUÊNCIA — Linux / macOS (chamada via NLB):**
```bash
curl -s "http://${NLB}/evaluate?user_id=u1&flag_name=enable-new-dashboard"
```
🔵 **EM SEQUÊNCIA — Windows (PowerShell):**
```powershell
curl.exe -s "http://${NLB}/evaluate?user_id=u1&flag_name=enable-new-dashboard"
```

🟣 **TERMINAL SEPARADO (carga p/ HPA do evaluation; `hey` instalado):**
```bash
hey -z 60s "http://${NLB}/evaluate?user_id=u1&flag_name=enable-new-dashboard"
```
No terminal principal, observe as réplicas subirem:
```bash
kubectl get hpa -n evaluation -w
```

🔵 **EM SEQUÊNCIA (mensagem manual → analytics → DynamoDB — idêntico nos 3 SOs):**
```bash
aws sqs send-message --queue-url ${SQS_URL} --message-body '{"user_id":"u1","flag_name":"x","result":true,"timestamp":"2026-07-02T12:00:00Z"}'
```
```bash
aws dynamodb scan --table-name ToggleMasterAnalytics --max-items 5
```

---

# TEARDOWN (destrua tudo para parar a cobrança)

> Ordem importa: primeiro o que gera Load Balancer, depois o cluster, depois os
> recursos gerenciados. (Idêntico nos 3 SOs.)

🔵 **EM SEQUÊNCIA:**
```bash
helm uninstall ingress-nginx -n ingress-nginx
```
```bash
aws rds delete-db-instance --db-instance-identifier toggle-auth --skip-final-snapshot --delete-automated-backups
aws rds delete-db-instance --db-instance-identifier toggle-flag --skip-final-snapshot --delete-automated-backups
aws rds delete-db-instance --db-instance-identifier toggle-targeting --skip-final-snapshot --delete-automated-backups
```
```bash
aws elasticache delete-cache-cluster --cache-cluster-id toggle-redis
```
```bash
aws dynamodb delete-table --table-name ToggleMasterAnalytics
aws sqs delete-queue --queue-url ${SQS_URL}
```
```bash
eksctl delete cluster --name ${CLUSTER}
```
📝 **Por último:** apague os 5 repositórios ECR e as policies IAM
(`toggle-analytics-policy`, `toggle-eval-policy`). Confira no **Cost Explorer**
que nenhum NAT/EBS/Load Balancer ficou órfão.

---

## Resumo da ordem

1. ECR (repos + push)
2. Cluster EKS → capturar VPC/SG/subnets
3. SG dos bancos + subnet groups
4. RDS ×3, Redis, DynamoDB, SQS → esperar `available` + capturar endpoints
5. Namespaces → IRSA (analytics-sa, evaluation-sa)
6. **init.sql em cada RDS**
7. Nginx Ingress (NLB)
8. Deploy auth → flag → targeting
9. **Bootstrap da API key** → secret + deploy do evaluation
10. Deploy analytics
11. HPAs
12. Validar → **Teardown**
