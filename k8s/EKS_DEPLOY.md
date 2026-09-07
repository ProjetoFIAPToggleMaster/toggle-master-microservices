# EKS Deployment Guide

---

## Step 1 — AWS Infrastructure

Create these AWS resources **before** deploying. All must be in the **same VPC as your EKS cluster**.

### RDS — 3 Postgres Databases
Console → RDS → Create Database → PostgreSQL 15 → note each endpoint URL.

| Database | Used by |
|----------|---------|
| `auth_db` | auth-service |
| `flags_db` | flag-service |
| `targeting_db` | targeting-service |

### ElastiCache — Redis
Console → ElastiCache → Create → Redis → note endpoint URL.
Used by: evaluation-service.

### SQS — One Queue
Console → SQS → Create Queue → Standard → name: `toggle-queue` → note full URL.
Used by: evaluation-service (sends) and analytics-service (receives).

### DynamoDB — One Table
Console → DynamoDB → Create Table → Name: `ToggleMasterAnalytics` → Partition key: `event_id` (String).
Used by: analytics-service.

---

## Step 2 — ECR Images

If images need to be pushed or updated:

```powershell
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

docker build -t auth-service ./auth-service
docker tag auth-service:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest

# repeat for: flag-service, targeting-service, evaluation-service, analytics-service
```

---

## Step 3 — Connect kubectl to EKS

```powershell
aws eks update-kubeconfig --region us-east-1 --name <YOUR_CLUSTER_NAME>
kubectl get nodes
```

You should see your cluster nodes listed.

---

## Step 4 — Install Cluster Components (one time only)

### Metrics Server
```powershell
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Verify after ~1 minute:
```powershell
kubectl top nodes
```

### Nginx Ingress Controller

#### IRSA
IRSA gives the nginx pod permission to manage Load Balancers without giving full permissions to the node.

**1. Check OIDC provider of the cluster:**
```powershell
aws eks describe-cluster --name <CLUSTER_NAME> --query "cluster.identity.oidc.issuer" --output text
```

**2. Associate OIDC provider (if not done yet):**
```powershell
eksctl utils associate-iam-oidc-provider --cluster <CLUSTER_NAME> --approve
```

**3. Create IAM policy for Load Balancer management:**
```powershell
curl.exe -o elb-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy --policy-name NginxIngressELBPolicy --policy-document file://elb-policy.json
```

**4. Create IAM Role and Service Account linked via IRSA:**
```powershell
eksctl create iamserviceaccount `
  --cluster=<CLUSTER_NAME> `
  --namespace=ingress-nginx `
  --name=ingress-nginx `
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/NginxIngressELBPolicy `
  --approve `
  --override-existing-serviceaccounts
```

**5. Install Nginx via Helm using the service account:**
```powershell
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx `
  --create-namespace `
  --set controller.serviceAccount.create=false `
  --set controller.serviceAccount.name=ingress-nginx
```

---

**Both options — wait for controller then get NLB DNS:**
```powershell
kubectl wait --namespace ingress-nginx `
  --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller `
  --timeout=120s

kubectl get service ingress-nginx-controller -n ingress-nginx
```

The `EXTERNAL-IP` column is your NLB address. Save this — it is your public URL for everything.

---

## Step 5 — Allow EKS Nodes to Pull from ECR

```powershell
# get node role ARN
aws eks describe-nodegroup \
  --cluster-name <CLUSTER_NAME> \
  --nodegroup-name <NODEGROUP_NAME> \
  --query "nodegroup.nodeRole" \
  --output text

# attach ECR read policy (use only the role name, not the full ARN)
aws iam attach-role-policy \
  --role-name <NODE_ROLE_NAME> \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

---

## Step 6 — Fill Prod Secrets

Edit `k8s/overlays/prod/secrets.yaml`. Replace every `<base64_...>` placeholder with real base64-encoded values.

Generate base64 in PowerShell:
```powershell
[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("your-real-value"))
```

| Secret name | Key | Value to encode |
|-------------|-----|-----------------|
| auth-secrets | DATABASE_URL | `postgresql://postgres:<pw>@<RDS_AUTH_ENDPOINT>:5432/auth_db?sslmode=require` |
| auth-secrets | MASTER_KEY | your master key |
| flag-secrets | DATABASE_URL | `postgres://postgres:<pw>@<RDS_FLAGS_ENDPOINT>:5432/flags_db` |
| targeting-secrets | DATABASE_URL | `postgres://postgres:<pw>@<RDS_TARGETING_ENDPOINT>:5432/targeting_db` |
| evaluation-secrets | REDIS_URL | `redis://<ELASTICACHE_ENDPOINT>:6379` |
| evaluation-secrets | AWS_SQS_URL | full SQS queue URL |
| evaluation-secrets | SERVICE_API_KEY | fill after step 10 |
| analytics-secrets | AWS_ACCESS_KEY_ID | your AWS key |
| analytics-secrets | AWS_SECRET_ACCESS_KEY | your AWS secret |
| analytics-secrets | AWS_SESSION_TOKEN | your session token |
| analytics-secrets | AWS_SQS_URL | full SQS queue URL |

> **Do NOT add `AWS_ENDPOINT_URL` to prod secrets** — that is local only. Prod points to real AWS.

---

## Step 7 — Fill Prod Image URLs

Edit `k8s/overlays/prod/patch-images.yaml`. Replace `<ACCOUNT_ID>` and `<REGION>` in all 5 image lines.

Example:
```yaml
image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest
```

---

## Step 8 — Initialize RDS Schemas

RDS databases start empty. Run the init scripts once against each database.

```powershell
psql postgresql://postgres:<pw>@<RDS_AUTH_ENDPOINT>:5432/auth_db -f auth-service/db/init.sql
psql postgresql://postgres:<pw>@<RDS_FLAGS_ENDPOINT>:5432/flags_db -f flag-service/db/init.sql
psql postgresql://postgres:<pw>@<RDS_TARGETING_ENDPOINT>:5432/targeting_db -f targeting-service/db/init.sql
```

If you don't have psql locally, use the AWS RDS Query Editor in the Console.

---

## Step 9 — Apply Prod Manifests

```powershell
kubectl apply -k k8s/overlays/prod/
kubectl get pods -n toggle-master -w
```

Wait until all pods show `1/1 Running`.

---

## Step 10 — Create SERVICE_API_KEY for evaluation-service

Once auth-service is running, create the internal key evaluation-service uses to call flag-service and targeting-service:

```powershell
curl.exe -X POST http://<NLB_DNS>/auth/admin/keys `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer admin-secreto-123" `
  -d "{\"name\": \"evaluation-service-key\"}"
```

Copy the `tm_key_...` value. Base64 encode it and add it to `k8s/overlays/prod/secrets.yaml` under `evaluation-secrets.SERVICE_API_KEY`. Then reapply:

```powershell
kubectl apply -k k8s/overlays/prod/
kubectl rollout restart deployment/evaluation-service -n toggle-master
```

---

## Step 11 — Verify

```powershell
kubectl get pods -n toggle-master
kubectl get ingress -n toggle-master
```

Hit each health endpoint:
```powershell
curl.exe http://<NLB_DNS>/auth/health
curl.exe http://<NLB_DNS>/flags/health
curl.exe http://<NLB_DNS>/targeting/health
curl.exe http://<NLB_DNS>/evaluate/health
curl.exe http://<NLB_DNS>/analytics/health
```

All should return `{"status":"ok"}`.

Test the full flow in Postman using `<NLB_DNS>` instead of `127.0.0.1` — same steps as local testing.

---

## Quick Reference — Useful kubectl Commands

| Command | What it does |
|---------|-------------|
| `kubectl get pods -n toggle-master` | Check all pod statuses |
| `kubectl logs <pod-name> -n toggle-master` | See pod logs |
| `kubectl describe pod <pod-name> -n toggle-master` | Debug a failing pod |
| `kubectl rollout restart deployment/<name> -n toggle-master` | Restart a deployment |
| `kubectl apply -k k8s/overlays/prod/` | Apply/update prod manifests |
| `kubectl get ingress -n toggle-master` | Get NLB DNS address |
| `kubectl get service ingress-nginx-controller -n ingress-nginx` | Get NLB external IP |
