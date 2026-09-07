# Local & EKS Runbook

---

## Prerequisites (one time only)

```powershell
# install minikube if not installed
winget install Kubernetes.minikube

# make sure PATH has minikube (restart terminal or run this)
$env:PATH += ";C:\Program Files\Kubernetes\Minikube"
```

---

## Running Locally (every time)

### Step 1 — Start minikube

```powershell
minikube start --driver=docker --memory=4096 --cpus=2
minikube addons enable ingress
```

### Step 2 — Build all images with regular Docker

Run from `E:\toggle-master-microservices\`:

```powershell
docker build -t auth-service:local ./auth-service
docker build -t flag-service:local ./flag-service
docker build -t targeting-service:local ./targeting-service
docker build -t evaluation-service:local ./evaluation-service
docker build -t analytics-service:local ./analytics-service
```

### Step 3 — Load images into minikube

```powershell
minikube image load auth-service:local
minikube image load flag-service:local
minikube image load targeting-service:local
minikube image load evaluation-service:local
minikube image load analytics-service:local
```

Verify all 5 loaded:
```powershell
minikube image ls
```

### Step 4 — Apply manifests

```powershell
kubectl apply -k k8s/overlays/local/
```

### Step 5 — Watch pods come up

```powershell
kubectl get pods -n toggle-master -w
```

Wait until all pods show `1/1 Running`. Postgres and Redis come up first, then app services recover on their own.

### Step 6 — Test it

Open a separate terminal and run the tunnel so ingress works:
```powershell
minikube tunnel
```

Then hit the services:
```powershell
curl http://127.0.0.1/auth/health
curl http://127.0.0.1/flags/health
curl http://127.0.0.1/targeting/health
curl http://127.0.0.1/evaluate/health
curl http://127.0.0.1/analytics/health
```

All should return `{"status":"ok"}`.

---

## Rebuilding a Single Image (after code change)

```powershell
# example for analytics-service — repeat pattern for any service
docker build --no-cache -t analytics-service:local ./analytics-service
kubectl delete deployment analytics-service -n toggle-master
minikube image rm --force analytics-service:local
minikube image load analytics-service:local
kubectl apply -k k8s/overlays/local/
```

---

## Stopping for the Day

```powershell
minikube stop
```

This saves the cluster state. Next time just `minikube start` — no need to rebuild images or reapply manifests unless something changed.

---

## Deploying to EKS (prod)

### Step 1 — Fill real values in prod secrets

Edit `k8s/overlays/prod/secrets.yaml` and replace all `<base64_...>` placeholders.

Generate base64 values with:
```powershell
[Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("your-value-here"))
```

Secrets needed:
| Secret | Key | Value |
|--------|-----|-------|
| auth-secrets | DATABASE_URL | RDS connection string for auth_db |
| auth-secrets | MASTER_KEY | your master key |
| flag-secrets | DATABASE_URL | RDS connection string for flags_db |
| targeting-secrets | DATABASE_URL | RDS connection string for targeting_db |
| evaluation-secrets | REDIS_URL | ElastiCache Redis URL |
| analytics-secrets | AWS_ACCESS_KEY_ID | AWS key |
| analytics-secrets | AWS_SECRET_ACCESS_KEY | AWS secret |
| analytics-secrets | AWS_SESSION_TOKEN | AWS session token |
| analytics-secrets | AWS_SQS_URL | full SQS queue URL |

> **NEVER commit this file to git.** It is in `.gitignore`.

### Step 2 — Fill real ECR image URLs

Edit `k8s/overlays/prod/patch-images.yaml` and replace `<ACCOUNT_ID>` and `<REGION>` with your real values.

### Step 3 — Install cluster components (one time only)

```powershell
# point kubectl at EKS
aws eks update-kubeconfig --region us-east-1 --name <CLUSTER_NAME>

# metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# nginx ingress controller (AWS Academy)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/aws/deploy.yaml

# wait for nginx to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### Step 4 — Apply prod manifests

```powershell
kubectl apply -k k8s/overlays/prod/
```

### Step 5 — Verify

```powershell
# check all pods are running
kubectl get pods -n toggle-master

# get the NLB DNS address
kubectl get ingress -n toggle-master

# hit the services using the NLB DNS
curl http://<NLB_DNS>/auth/health
curl http://<NLB_DNS>/flags/health
curl http://<NLB_DNS>/targeting/health
curl http://<NLB_DNS>/evaluate/health
curl http://<NLB_DNS>/analytics/health
```

---

## Quick Reference

| Command | What it does |
|---------|-------------|
| `minikube start --driver=docker --memory=4096 --cpus=2` | Start local cluster |
| `minikube stop` | Stop cluster, save state |
| `minikube delete` | Destroy cluster completely |
| `minikube tunnel` | Expose ingress on 127.0.0.1 |
| `minikube image ls` | List images loaded in minikube |
| `kubectl get pods -n toggle-master` | Check pod status |
| `kubectl logs <pod-name> -n toggle-master` | See pod logs |
| `kubectl describe pod <pod-name> -n toggle-master` | Debug a failing pod |
| `kubectl apply -k k8s/overlays/local/` | Apply local manifests |
| `kubectl apply -k k8s/overlays/prod/` | Apply prod manifests |
| `kubectl delete namespace toggle-master` | Wipe everything and start fresh |
