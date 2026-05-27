# Toggle Master Microservices

Este repositório raiz é um repositório Git pai que agrupa cinco microsserviços como submodules.

## Como funcionam os submodules

Cada pasta de microsserviço aqui (`analytics-service`, `auth-service`, `evaluation-service`, `flag-service`, `targeting-service`) é um repositório Git independente.

- O repositório raiz não contém o histórico completo de cada microsserviço.
- Ele armazena apenas um ponteiro para um commit específico de cada submodule.
- Os submodules funcionam como dependências versionadas: o root repo escolhe qual commit de cada serviço está "travado".

### Isso significa que...

- Sim: você pode trabalhar dentro de cada pasta de serviço individualmente.
- Sim: `cd auth-service && git status` mostra o estado real do repositório do serviço.
- Se você fizer commit e push dentro do serviço, as alterações irão para o repositório remoto desse serviço.

## Fluxo recomendado

### 1. Alterar um microserviço

```bash
cd analytics-service
# editar código
git add .
git commit -m "Minha alteração no analytics"
git push
```

### 2. Atualizar o ponteiro no repositório raiz

Depois que o serviço foi commitado e pushado, volte ao repositório raiz:

```bash
cd ..
git status
git add analytics-service
git commit -m "Atualiza submodule analytics-service"
git push
```

O commit do repositório raiz registra a nova revisão exata do submodule.

## Quando criar mudanças no repositório raiz

No repositório raiz você deve trabalhar quando:

- quiser adicionar ou editar `docker-compose.yml`
- quiser criar `Dockerfile` na raiz ou fora dos submodules
- quiser documentar o conjunto geral dos serviços
- quiser atualizar o ponteiro de um submodule depois de um commit no serviço

## Como clonar este repositório corretamente

Ao clonar o repositório raiz, use:

```bash
git clone --recurse-submodules https://github.com/ProjetoFIAPToggleMaster/toggle-master-microservices.git
```

Se você já clonou sem `--recurse-submodules`, execute:

```bash
git submodule update --init --recursive
```

## Resumo rápido

- Os submodules são repositórios reais, não apenas arquivos de link.
- Alterações feitas dentro de um serviço podem ser commitadas e pushadas no repositório desse serviço.
- O repositório raiz precisa de um commit adicional para atualizar o ponteiro do submodule.
- O histórico de cada serviço permanece separado e intacto.
