# Toggle Master

**Toggle Master** é uma plataforma de **feature flags** (feature toggles) construída como um conjunto de microsserviços independentes. Ela permite criar, segmentar e avaliar flags em tempo real, com trilha de auditoria assíncrona dos eventos de avaliação — o mesmo tipo de capacidade oferecida por ferramentas como LaunchDarkly ou Unleash, implementada aqui como projeto de estudo de arquitetura distribuída.

Este repositório raiz é um repositório Git pai que agrupa cinco microsserviços como **submodules**, cada um em sua própria linguagem, com seu próprio histórico e ciclo de deploy.

## Arquitetura

```
cliente final
     │
     ▼
┌─────────────────────┐   valida chave    ┌──────────────┐
│ evaluation-service   │ ────────────────▶ │ auth-service │
│ (Go, hot path)       │                   │ (Go)         │
└─────────┬────────────┘                   └──────────────┘
          │ cache miss                            ▲
          ▼                                        │ valida chave
   ┌─────────────┐        ┌────────────────────┐   │
   │ flag-service │        │ targeting-service   │──┘
   │ (Python)     │        │ (Python)            │
   └─────────────┘        └────────────────────┘
          │
          ▼ (cache) Redis        ▼ (evento) AWS SQS
                                      │
                                      ▼
                            ┌────────────────────┐
                            │ analytics-service   │
                            │ (Python, worker)    │──▶ AWS DynamoDB
                            └────────────────────┘
```

- **[auth-service](auth-service)** (Go) — emite e valida chaves de API usadas por todos os demais serviços.
- **[flag-service](flag-service)** (Python/Flask) — CRUD das definições de feature flags. Protegido por API key.
- **[targeting-service](targeting-service)** (Python/Flask) — regras de segmentação por flag (ex: rollout percentual, atributos de usuário). Protegido por API key.
- **[evaluation-service](evaluation-service)** (Go) — o "caminho quente": único endpoint chamado pelos clientes finais. Resolve flag + regra, decide `true/false` com hashing determinístico, cacheia o resultado em **Redis** e publica o evento da decisão de forma assíncrona em uma fila **AWS SQS**.
- **[analytics-service](analytics-service)** (Python) — worker que consome a fila **SQS** e persiste os eventos de avaliação no **AWS DynamoDB** para análise posterior.

## Áreas de conhecimento e ferramentas

| Área | Tecnologias / práticas aplicadas |
|---|---|
| Arquitetura de software | Microsserviços poliglotas, comunicação síncrona via REST, comunicação assíncrona via fila de mensagens (padrão produtor/consumidor), cache-aside |
| Backend — Go | `net/http`, `go-redis`, `aws-sdk-go`, driver `pgx` para PostgreSQL |
| Backend — Python | Flask, Gunicorn, `psycopg2`, `boto3` |
| Bancos de dados | PostgreSQL (um banco por serviço: `auth_db`, `flags_db`, `targeting_db`) |
| Cache | Redis, com TTL curto para o resultado de avaliação de flags |
| Mensageria / eventos | AWS SQS (arquitetura orientada a eventos entre `evaluation-service` e `analytics-service`) |
| Persistência analítica | AWS DynamoDB |
| Segurança | Autenticação via API key (`Authorization: Bearer`), serviço de autenticação dedicado e centralizado |
| Containerização | Docker (builds multi-stage para imagens enxutas), Docker Compose para orquestração local |
| Versionamento e organização de código | Git submodules — cada microsserviço é um repositório independente, versionado e deployado separadamente |
| Infraestrutura (em evolução) | Manifests Kubernetes por serviço (em estruturação) |

## Estrutura do repositório

Cada pasta de microsserviço (`analytics-service`, `auth-service`, `evaluation-service`, `flag-service`, `targeting-service`) é um repositório Git independente, referenciado como submodule.

- O repositório raiz não contém o histórico completo de cada microsserviço.
- Ele armazena apenas um ponteiro para um commit específico de cada submodule.
- Os submodules funcionam como dependências versionadas: o root repo escolhe qual commit de cada serviço está "travado".

Isso significa que:

- `cd auth-service && git status` mostra o estado real do repositório do serviço.
- Commits feitos dentro de um serviço vão para o repositório remoto desse serviço.
- O repositório raiz precisa de um commit adicional (`git add <serviço> && git commit`) para atualizar o ponteiro após uma mudança no submodule.

### Como clonar este repositório corretamente

```bash
git clone --recurse-submodules https://github.com/ProjetoFIAPToggleMaster/toggle-master-microservices.git
```

Se você já clonou sem `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

### Fluxo recomendado para alterar um microsserviço

```bash
cd analytics-service
# editar código
git add .
git commit -m "Minha alteração no analytics"
git push

cd ..
git add analytics-service
git commit -m "Atualiza submodule analytics-service"
git push
```

### Quando trabalhar no repositório raiz

- Adicionar ou editar `docker-compose.yml` ou manifests de infraestrutura.
- Documentar o conjunto geral dos serviços.
- Atualizar o ponteiro de um submodule depois de um commit no serviço.

## Rodando localmente

O `docker-compose.yml` na raiz sobe todos os serviços e seus bancos PostgreSQL/Redis com um único comando:

```bash
docker compose up --build
```

Cada serviço também pode ser executado isoladamente — consulte o README de cada submodule para pré-requisitos e variáveis de ambiente específicas.

## Roadmap

Os próximos passos do projeto são focados em produção e automação:

- **Infraestrutura como código com Terraform**: provisionamento da infraestrutura gerenciada (rede, bancos, filas, tabelas DynamoDB e cluster de execução) deixará de ser manual/console e passará a ser declarativo e versionado.
- **Pipeline de CI/CD por microsserviço**: cada um dos cinco serviços terá sua própria pipeline em **GitHub Actions**, independente das demais, cobrindo build, testes e deploy — coerente com o modelo de submodules, em que cada serviço já é versionado e liberado de forma autônoma.
