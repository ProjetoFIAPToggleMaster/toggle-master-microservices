# ArgoCD — Runbook local (minikube)

Guia para subir o cluster local completo **com ArgoCD** e demonstrar o fluxo
GitOps: um commit no GitHub → ArgoCD detecta → sincroniza a nova versão no
cluster automaticamente.

> Este documento cobre a lacuna do `RUNBOOK.md`, que sobe os serviços com
> `kubectl apply -k` (imperativo) mas não instala nem configura o ArgoCD.

---

## Visão geral do fluxo

```
 você edita k8s/overlays/local/  →  git push (master)
                                          │
                                          ▼
                          ArgoCD faz polling do GitHub
                                          │
                                          ▼
                    detecta OutOfSync → aplica no cluster
                                          │
                                          ▼
                            novo pod sobe (rolling update)
```

O ArgoCD lê **do GitHub**, nunca do seu disco. Uma alteração só é detectada
depois de `git push`. Isso é essencial entender para a demo não falhar.

---

## Passo 0 — Desbloquear o Docker (WSL2)

O Docker Desktop precisa do WSL2. A virtualização da BIOS já está habilitada,
mas faltam os recursos opcionais do Windows.

Abra o **PowerShell como Administrador**:

```powershell
wsl --install
```

**Reinicie a máquina.** Depois do reboot, abra o Docker Desktop e confirme:

```powershell
docker run --rm hello-world
```

Se imprimir "Hello from Docker!", está pronto. Se o Docker Desktop reclamar de
WSL, rode `wsl --update` e reinicie o Docker Desktop.

---

## Passo 1 — Instalar minikube

```powershell
winget install Kubernetes.minikube
```

Feche e reabra o terminal (para o PATH atualizar) e confirme:

```powershell
minikube version
```

---

## Passo 2 — Preparar o repositório

Os 5 serviços são submódulos git. Sem inicializá-los, as pastas ficam vazias e
o `docker build` falha.

```powershell
git submodule update --init --recursive
```

Confirme que os 5 têm Dockerfile:

```powershell
Get-ChildItem *-service\Dockerfile | Select-Object Directory, Name
```

---

## Passo 3 — Subir o cluster

O minikube não pode pedir mais memória do que o backend WSL2 oferece. Confira
quanto o Docker tem disponível:

```powershell
docker info --format "{{.MemTotal}}"
```

Por padrão o WSL2 reserva ~50% da RAM física. Numa máquina de 16GB isso dá
~7,7GiB — apertado para ArgoCD + 10 pods da aplicação. Para a apresentação,
suba esse teto criando `C:\Users\<seu-usuario>\.wslconfig` com:

```ini
[wsl2]
memory=12GB
processors=6
```

Aplique reiniciando o WSL (feche o Docker Desktop antes):

```powershell
wsl --shutdown
```

Reabra o Docker Desktop e então suba o cluster:

```powershell
minikube start --driver=docker --memory=8192 --cpus=4
```

```powershell
minikube addons enable ingress
```

> **Sem mexer no `.wslconfig`?** Use `--memory=6144` em vez de 8192. Funciona,
> mas com pouca folga: se algum pod ficar em `Pending` por falta de recurso, é
> este o motivo.
>
> O `RUNBOOK.md` sugere 4096MB, o que basta para os serviços sozinhos. Com o
> ArgoCD (~6 pods a mais) isso não é suficiente.

---

## Passo 4 — Build e load das imagens

O overlay local usa `imagePullPolicy: Never`, ou seja, as imagens têm que estar
**dentro** do minikube — ele não busca em registry nenhum.

```powershell
docker build -t auth-service:local ./auth-service
docker build -t flag-service:local ./flag-service
docker build -t targeting-service:local ./targeting-service
docker build -t evaluation-service:local ./evaluation-service
docker build -t analytics-service:local ./analytics-service
```

```powershell
minikube image load auth-service:local
minikube image load flag-service:local
minikube image load targeting-service:local
minikube image load evaluation-service:local
minikube image load analytics-service:local
```

Confirme que as 5 entraram:

```powershell
minikube image ls | Select-String "service:local"
```

---

## Passo 5 — Instalar o ArgoCD

```powershell
kubectl create namespace argocd
```

```powershell
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Espere tudo ficar pronto (leva 1–3 min na primeira vez):

```powershell
kubectl wait --for=condition=available deployment --all -n argocd --timeout=300s
```

Confira os pods:

```powershell
kubectl get pods -n argocd
```

---

## Passo 6 — Acelerar o polling (importante para a demo)

Por padrão o ArgoCD checa o git a cada **3 minutos** — uma eternidade numa
apresentação ao vivo. Reduza para 30 segundos:

```powershell
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"timeout.reconciliation":"30s"}}'
```

```powershell
kubectl -n argocd rollout restart statefulset argocd-application-controller
```

> Se o `patch` acima falhar por causa de aspas no PowerShell, use
> `kubectl -n argocd edit configmap argocd-cm` e adicione manualmente sob `data:`
> a linha `timeout.reconciliation: 30s`.

---

## Passo 7 — Acessar a interface do ArgoCD

### 7a. Pegar a senha do admin

```powershell
$b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"
[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64))
```

Guarde essa senha. O usuário é `admin`.

### 7b. Port-forward (jeito recomendado para a demo)

Em um **terminal separado**, deixe rodando:

```powershell
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Acesse **https://localhost:8080** e aceite o aviso de certificado
(auto-assinado — normal).

> Deixe esse terminal aberto durante toda a apresentação. Se fechar, a UI cai.

### 7c. Ingress (alternativa ao port-forward)

Se preferir acessar por um hostname em vez de `localhost:8080`:

**1.** Coloque o argocd-server em modo HTTP (sem isso o nginx e o TLS do ArgoCD
brigam e você toma erro 502 ou redirect infinito):

```powershell
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true"}}'
```

```powershell
kubectl -n argocd rollout restart deployment argocd-server
```

**2.** Aplique o Ingress:

```powershell
kubectl apply -f argocd/ingress-argocd.yaml
```

**3.** Adicione ao arquivo `C:\Windows\System32\drivers\etc\hosts` (como Admin):

```
127.0.0.1 argocd.local
```

**4.** Em um terminal separado, deixe o túnel rodando:

```powershell
minikube tunnel
```

Acesse **http://argocd.local**.

---

## Passo 8 — Conectar a Application (o GitOps de fato)

Este é o passo que entrega o controle dos manifests ao ArgoCD:

```powershell
kubectl apply -f argocd/application-local.yaml
```

O que esse arquivo declara:

| Campo | Valor | Significado |
|---|---|---|
| `repoURL` | `.../toggle-master-microservices.git` | repositório observado |
| `targetRevision` | `master` | branch observada |
| `path` | `k8s/overlays/local` | pasta observada |
| `automated.prune` | `true` | removeu do git → remove do cluster |
| `automated.selfHeal` | `true` | mexeu no cluster na mão → reverte para o git |

Acompanhe a sincronização inicial:

```powershell
kubectl get pods -n toggle-master -w
```

Na UI, o app `toggle-master-local` deve ficar **Healthy / Synced** (verde).

Teste os serviços (com `minikube tunnel` rodando):

```powershell
curl http://127.0.0.1/auth/health
curl http://127.0.0.1/flags/health
```

---

## Passo 9 — A demonstração

> **Requisito da fase 3:** "Mostre o ArgoCD detectando a mudança e sincronizando
> a nova versão no cluster automaticamente."

### Preparação (faça ANTES de apresentar)

Construa uma segunda versão de um serviço — o `flag-service` é uma boa escolha
por ser o núcleo do produto:

```powershell
docker build -t flag-service:v2 ./flag-service
```

```powershell
minikube image load flag-service:v2
```

Confirme que as duas tags estão no cluster:

```powershell
minikube image ls | Select-String "flag-service"
```

### Durante a apresentação

**1.** Deixe a UI do ArgoCD aberta em `toggle-master-local`, e num terminal ao lado:

```powershell
kubectl get pods -n toggle-master -w
```

**2.** Edite `k8s/overlays/local/patch-images.yaml` e troque a imagem do
`flag-service`:

```yaml
image: flag-service:v2   # era flag-service:local
```

**3.** Commite e envie:

```powershell
git add k8s/overlays/local/patch-images.yaml
```

```powershell
git commit -m "demo: nova versao do flag-service"
```

```powershell
git push
```

**4.** Narre enquanto acontece (~30s):

- O app fica **OutOfSync** (amarelo) — o ArgoCD detectou a divergência.
- Ele sincroniza sozinho, sem ninguém rodar `kubectl`.
- No terminal, o pod antigo termina e o novo sobe (rolling update).
- O app volta a **Synced / Healthy** (verde).

**5.** Bônus — demonstrar o `selfHeal`, que costuma impressionar:

```powershell
kubectl scale deployment flag-service -n toggle-master --replicas=5
```

Em segundos o ArgoCD reverte para o valor declarado no git. Mostra que o git é
a fonte da verdade, não o cluster.

### Depois da demo

Reverta o commit para deixar o repositório limpo:

```powershell
git revert --no-edit HEAD
```

```powershell
git push
```

---

## Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| Pod em `ErrImageNeverPull` | imagem não foi carregada no minikube | `minikube image load <img>` |
| App preso em `OutOfSync` | polling ainda não rodou | clique em **REFRESH** na UI |
| `Unknown` / erro de repo | repositório privado | adicione credencial em Settings → Repositories |
| UI não abre | port-forward caiu | rode o `kubectl port-forward` de novo |
| Ingress dá 502 | argocd-server em HTTPS | aplique o `server.insecure` do passo 7c |
| Pods `Pending` sem recurso | memória insuficiente | recrie com `--memory=8192` |
| `curl` nos serviços falha | túnel parado | rode `minikube tunnel` |

Logs úteis:

```powershell
kubectl logs -n argocd statefulset/argocd-application-controller --tail=50
```

---

## Encerrar

```powershell
minikube stop
```

O estado é preservado. Na próxima vez, `minikube start` já volta com ArgoCD,
imagens e aplicação no lugar — não precisa refazer os passos 1 a 8.

Para destruir tudo e começar do zero:

```powershell
minikube delete
```
