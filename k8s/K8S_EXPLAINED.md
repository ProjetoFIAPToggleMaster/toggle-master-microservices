# Kubernetes Manifests — Full Explanation

---

## `k8s/base/namespace.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: toggle-master
```

| Field | Explanation |
|-------|-------------|
| `apiVersion: v1` | Namespace is a core resource so it uses `v1` |
| `kind: Namespace` | Tells kubernetes "create a namespace" |
| `name: toggle-master` | The name of the logical bucket. Every other resource says `namespace: toggle-master` to live inside it. Keeps your 5 services isolated from other things running in the cluster |

---

## `k8s/base/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: toggle-config
  namespace: toggle-master
data:
  AUTH_SERVICE_URL: "http://auth-service:8001"
  FLAG_SERVICE_URL: "http://flag-service:8002"
  TARGETING_SERVICE_URL: "http://targeting-service:8003"
  AWS_REGION: "us-east-1"
  AWS_DYNAMODB_TABLE: "ToggleMasterAnalytics"
```

| Field | Explanation |
|-------|-------------|
| `kind: ConfigMap` | A key-value store for non-sensitive config. Think of it as a shared `.env` file for the whole cluster |
| `data` | The actual values. Services reference these by key name instead of hardcoding URLs |
| `http://auth-service:8001` | Inside kubernetes, services talk using the Service name as hostname. Kubernetes internal DNS resolves `auth-service` to the right pod IP automatically |
| Missing passwords/credentials | Those go in Secrets, never in ConfigMap |

---

## `k8s/base/auth-service.yaml` (same pattern for all 5 services)

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: toggle-master
spec:
  replicas: 1
  selector:
    matchLabels:
      app: auth-service
  template:
    metadata:
      labels:
        app: auth-service
    spec:
      containers:
        - name: auth-service
          image: toggle-master/auth-service:latest
          ports:
            - containerPort: 8001
          env:
            - name: PORT
              value: "8001"
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: auth-secrets
                  key: DATABASE_URL
            - name: MASTER_KEY
              valueFrom:
                secretKeyRef:
                  name: auth-secrets
                  key: MASTER_KEY
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "250m"
              memory: "256Mi"
          readinessProbe:
            httpGet:
              path: /health
              port: 8001
            initialDelaySeconds: 10
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /health
              port: 8001
            initialDelaySeconds: 15
            periodSeconds: 20
```

| Field | Explanation |
|-------|-------------|
| `apiVersion: apps/v1` | Deployment is not a core resource, it lives under the `apps` group |
| `kind: Deployment` | Tells kubernetes "keep N copies of this pod running always". If a pod crashes, Deployment restarts it automatically |
| `replicas: 1` | Run exactly 1 copy of this pod. Change to 2 or 3 for high availability |
| `selector.matchLabels` | How the Deployment finds its own pods. It looks for pods with label `app: auth-service` |
| `template` | The blueprint for every pod this Deployment creates |
| `template.metadata.labels` | Stamps every pod with `app: auth-service`. Must match `selector.matchLabels` or kubernetes throws an error |
| `image: toggle-master/auth-service:latest` | Placeholder image name. Overridden by overlays (local uses `auth-service:local`, prod uses ECR URL) |
| `containerPort: 8001` | Documents which port the container listens on. Informational only, does not actually open anything |
| `env` with `value:` | Plain text env var injected directly. PORT is not sensitive so fine to hardcode |
| `env` with `valueFrom.secretKeyRef` | Pulls value from a Secret. `name: auth-secrets` is the Secret name, `key: DATABASE_URL` is the key inside it. The actual value never appears in this file |
| `resources.requests` | The minimum resources kubernetes *reserves* for this pod on a node. `100m` cpu = 0.1 of one CPU core. `128Mi` = 128 megabytes RAM |
| `resources.limits` | The maximum the pod is allowed to use. If it exceeds this, kubernetes kills and restarts it. Prevents one bad pod from eating the whole node |
| `readinessProbe` | Kubernetes calls `/health` every 10 seconds. If it fails, kubernetes stops sending traffic to this pod but keeps it running. `initialDelaySeconds: 10` gives the app time to boot before first check |
| `livenessProbe` | Kubernetes calls `/health` every 20 seconds. If it fails, kubernetes **kills and restarts** the pod. Catches cases where the app is frozen or deadlocked |

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: auth-service
  namespace: toggle-master
spec:
  selector:
    app: auth-service
  ports:
    - port: 8001
      targetPort: 8001
  type: ClusterIP
```

| Field | Explanation |
|-------|-------------|
| `kind: Service` | A stable internal endpoint that sits in front of pods. Pods come and go (crash, restart, scale) and their IPs change. Service IP never changes |
| `selector: app: auth-service` | The Service finds pods by this label and forwards traffic to them |
| `port: 8001` | The port OTHER services use to talk to this service (e.g. `http://auth-service:8001`) |
| `targetPort: 8001` | The port on the actual pod container to forward to. Usually same as port |
| `type: ClusterIP` | Only reachable from inside the cluster. Not exposed to internet. All 5 app services use ClusterIP because only the Ingress should be public |

---

## `k8s/base/ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: toggle-ingress
  namespace: toggle-master
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /auth(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: auth-service
                port:
                  number: 8001
```

| Field | Explanation |
|-------|-------------|
| `kind: Ingress` | The single entry point from the internet into the cluster. Like a reverse proxy / router |
| `annotations` | Extra instructions to the nginx controller |
| `rewrite-target: /$2` | Strips the path prefix before forwarding. Example: `/auth/login` arrives → rewritten to `/login` → forwarded to auth-service. Without this the service receives `/auth/login` and doesn't know what to do with the `/auth` prefix |
| `ingressClassName: nginx` | Tells kubernetes to use the nginx ingress controller, not AWS ALB or others |
| `path: /auth(/|$)(.*)` | Regex. `(/|$)` matches a slash or end of string. `(.*)` captures everything after. `$2` in rewrite-target refers to this second capture group |
| `pathType: ImplementationSpecific` | Required when using regex paths with nginx |
| `backend` | Where to forward matching traffic. Name is the Service name, number is the Service port |

---

## `k8s/base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - configmap.yaml
  - auth-service.yaml
  - flag-service.yaml
  - targeting-service.yaml
  - evaluation-service.yaml
  - analytics-service.yaml
  - ingress.yaml
```

| Field | Explanation |
|-------|-------------|
| `kind: Kustomization` | Not a kubernetes resource. It is a kustomize instruction file |
| `resources` | The list of files that belong to this base. When you run `kubectl apply -k`, kustomize reads this, loads all resources, applies overlay patches on top, then sends everything to kubernetes as one batch |

---

## `k8s/overlays/local/localstack.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: localstack
  namespace: toggle-master
spec:
  containers:
    - name: localstack
      image: localstack/localstack:latest
      env:
        - name: SERVICES
          value: "sqs,dynamodb"
      ports:
        - containerPort: 4566
---
apiVersion: v1
kind: Service
metadata:
  name: localstack
spec:
  ports:
    - port: 4566
      targetPort: 4566
```

| Field | Explanation |
|-------|-------------|
| Only in local overlay | Prod uses real AWS SQS and DynamoDB, no need for this file there |
| `localstack/localstack:latest` | Official LocalStack image that fakes AWS services locally |
| `SERVICES: "sqs,dynamodb"` | Tells LocalStack to only start SQS and DynamoDB mocks, not all 50+ AWS services. Keeps it lean |
| `port 4566` | LocalStack's default port for all services. analytics-service points `AWS_SQS_URL` at `http://localstack:4566` and boto3 talks to it exactly like real AWS |

---

## `k8s/overlays/local/secrets.yaml`

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: auth-secrets
  namespace: toggle-master
type: Opaque
stringData:
  DATABASE_URL: "postgresql://postgres:postgres123@postgres-auth:5432/auth_db"
  MASTER_KEY: "admin-secreto-123"
```

| Field | Explanation |
|-------|-------------|
| `kind: Secret` | Like ConfigMap but kubernetes stores it encoded and treats it more carefully |
| `type: Opaque` | Generic secret, as opposed to special types like `kubernetes.io/tls` |
| `stringData` | You write plain text, kubernetes automatically base64 encodes it before storing. Used in local overlay because values are fake |
| prod uses `data:` instead | Where YOU must provide already base64-encoded values. Kubernetes does not encode twice |

---

## `k8s/overlays/local/patch-images.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: auth-service
  namespace: toggle-master
spec:
  template:
    spec:
      containers:
        - name: auth-service
          image: auth-service:local
          imagePullPolicy: Never
```

| Field | Explanation |
|-------|-------------|
| This is a patch, not a full manifest | Kustomize merges this on top of `base/auth-service.yaml`. Only fields specified here get overridden, everything else stays from base |
| `image: auth-service:local` | Overrides the placeholder image from base with the locally built one |
| `imagePullPolicy: Never` | Tells kubernetes "do not try to pull this image from a registry". Use only what is already loaded inside minikube. Without this, kubernetes tries to pull `auth-service:local` from Docker Hub and fails |

---

## `k8s/overlays/local/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
  - localstack.yaml
  - secrets.yaml
patches:
  - path: patch-images.yaml
```

| Field | Explanation |
|-------|-------------|
| `resources: ../../base` | Include everything from base first |
| `resources: localstack.yaml, secrets.yaml` | Add these extra resources on top (they don't exist in base) |
| `patches` | Apply patch-images.yaml on top of matching base resources. Kustomize matches by `kind` + `name` + `namespace` |

---

## `k8s/overlays/prod/` — differences from local

| Thing | Local | Prod |
|-------|-------|------|
| `localstack.yaml` | Present — mocks AWS | Absent — uses real AWS |
| `secrets.yaml` | Uses `stringData:` (plain text, fake values) | Uses `data:` (base64, real credentials) |
| `patch-images.yaml` | `image: auth-service:local` + `imagePullPolicy: Never` | Real ECR URLs, no imagePullPolicy override |
| `kustomization.yaml` | Includes localstack in resources | No localstack |
