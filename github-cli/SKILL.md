# Skill: github-cli
## GitHub CLI Completo — Repositório, Branches, Commits, PRs, Secrets

---

## Propósito
Esta skill cobre todo o ciclo de vida do repositório GitHub do projeto IRIS-CardioFlow usando `gh` CLI e `git`. Inclui criação do repositório, estratégia de branches, commits semânticos, pull requests e configuração de secrets para o CI/CD.

---

## Fase 1: Setup Inicial do Repositório

### Autenticar GitHub CLI
```bash
gh auth login
# Selecionar: GitHub.com → HTTPS → Login with a web browser
# Ou com token: gh auth login --with-token <<< "ghp_SEU_TOKEN"

# Verificar
gh auth status
```

### Criar repositório
```bash
# Criar repositório público (ou --private se preferir)
gh repo create iris-cardioflow \
  --public \
  --description "IRIS-CardioFlow: Monitoramento Cirúrgico Cardiológico — InterSystems IRIS 2026" \
  --clone

cd iris-cardioflow
```

### Estrutura inicial de branches
```bash
# Já estamos em main (padrão do GitHub)
git checkout -b develop
git push -u origin develop

# Proteger main (requer merge via PR)
gh api repos/{owner}/iris-cardioflow/branches/main/protection \
  --method PUT \
  --field required_status_checks='{"strict":true,"contexts":["build-and-test"]}' \
  --field enforce_admins=false \
  --field required_pull_request_reviews='{"required_approving_review_count":1}' \
  --field restrictions=null
```

---

## Fase 2: Estrutura de Diretórios e Commit Inicial

```bash
# Criar estrutura completa do projeto
mkdir -p .github/workflows
mkdir -p docker
mkdir -p src/CardioFlow/{BS,BP,BO,DTL,API,Analytics}
mkdir -p tests/UnitTest
mkdir -p data

# .gitignore para projetos IRIS
cat > .gitignore << 'EOF'
# IRIS runtime files
*.lck
*.pid
*.log
*.journal
mgr/
iris.cpf.bak

# Build artifacts
*.int
*.obj

# Editor
.DS_Store
.vscode/settings.json

# Secrets
*.env
.env.local
iris-agentic-dev.toml.local
EOF

# README inicial
cat > README.md << 'EOF'
# IRIS-CardioFlow 🫀

Sistema de Monitoramento Cirúrgico Cardiológico construído sobre InterSystems IRIS 2026.

## Stack
- **Interoperabilidade**: HL7 v2 (ADT/ORM) + FHIR R4 → SDA3
- **Runtime**: InterSystems IRIS 2026.1 (irishealth-community)
- **Analytics**: IRIS BI (DeepSee) + Columnar Storage
- **API**: REST `/api/cardio/dashboards/...`
- **DevOps**: Docker + GitHub Actions

## Quick Start

```bash
# Subir IRIS com Docker
docker compose -f docker/docker-compose.yml up -d

# Verificar saúde
curl -u _SYSTEM:SYS http://localhost:52773/api/cardio/health
```

## Fluxo de Desenvolvimento

Ler `CARDIOFLOW-MASTER.md` para instruções completas dos agentes.

## Testes

```bash
# Via iris-agentic-dev
iris-agentic-dev test "UnitTest/" --namespace CARDIOFLOW
```
EOF

# .iris-agentic-dev.toml
cat > .iris-agentic-dev.toml << 'EOF'
container = "cardioflow-iris"
namespace = "CARDIOFLOW"
EOF

# Commit inicial
git add .
git commit -m "feat: initial project structure for IRIS-CardioFlow

- Create directory skeleton (BS, BP, BO, DTL, API, Analytics)
- Add .gitignore for IRIS artifacts
- Add README with quick start
- Add .iris-agentic-dev.toml for MCP connection"

git push -u origin develop
```

---

## Fase 3: Workflow de Features (por agente)

### Estratégia de branches
```
main         ← produção (protegida, só via PR)
  └─ develop ← integração
       ├─ feature/agent-builder-interop   ← Agent 1
       ├─ feature/agent-data-analytics    ← Agent 2
       └─ feature/agent-devops-cicd       ← Agent 3
```

### Criar branch por agente
```bash
# Agent Builder
git checkout develop
git checkout -b feature/agent-builder-interop
git push -u origin feature/agent-builder-interop

# Agent Data
git checkout develop
git checkout -b feature/agent-data-analytics
git push -u origin feature/agent-data-analytics

# Agent DevOps
git checkout develop
git checkout -b feature/agent-devops-cicd
git push -u origin feature/agent-devops-cicd
```

---

## Fase 4: Commits Semânticos por Tipo de Arquivo

### Padrão de commit (Conventional Commits)
```
<tipo>(<escopo>): <descrição curta>

[corpo opcional]

[rodapé opcional]
```

| Tipo | Quando usar |
|------|-------------|
| `feat` | Nova classe, nova funcionalidade |
| `fix` | Correção de bug |
| `test` | Adicionar/corrigir testes |
| `refactor` | Refatoração sem mudança de comportamento |
| `docs` | Documentação |
| `ci` | GitHub Actions, Docker |
| `chore` | Tarefas auxiliares |

### Exemplos de commits por agente

**Agent Builder:**
```bash
# Após criar Production.cls via iris_doc + iris_compile
git add src/CardioFlow/Production.cls
git commit -m "feat(interop): add CardioFlow.Production with BS/BP/BO items

- HL7 Inbound on port 6661
- FHIR REST endpoint
- BP_Cardio_Orchestrator pool=2
- BO_SDA_Persist and BO_Dashboard_Feeder"

# DTL HL7
git add src/CardioFlow/DTL/HL7ToSDA3.cls
git commit -m "feat(dtl): implement HL7 ADT/ORM to SDA3 transformation

- Maps PID segments to Patient container
- Maps PV1-18 to Encounter.AdmissionType (PRE/SURG/REC)
- Maps ORM OBR segments to Procedures
- Handles both ADT^A08 and ORM^O01 message types"

# DTL FHIR
git add src/CardioFlow/DTL/FHIRToSDA3.cls
git commit -m "feat(dtl): implement FHIR R4 Bundle to SDA3 transformation

- Parses JSON Bundle entries
- Maps Patient/Encounter/Procedure resources
- Maps Encounter.status planned->PRE, in-progress->SURG, finished->REC"
```

**Agent Data:**
```bash
git add src/CardioFlow/Analytics/
git commit -m "feat(analytics): add Columnar Storage table and IRIS BI cubes

- SurgeryStatus with columnar index on (Status, EventTime, HospitalCode)
- PreOpCube: waiting time by hospital
- IntraOpCube: surgery room occupancy
- PostOpCube: recovery tracking with vital sign alerts"

git add src/CardioFlow/API/DashboardDispatch.cls
git commit -m "feat(api): add REST dispatcher for dashboard endpoints

- GET /api/cardio/dashboards/preop
- GET /api/cardio/dashboards/intraop
- GET /api/cardio/dashboards/postop
- GET /api/cardio/dashboards/summary
- GET /api/cardio/patient/:id/status
- GET /api/cardio/health"
```

**Agent DevOps:**
```bash
git add docker/
git commit -m "ci(docker): add multi-stage Dockerfile and compose

- Stage builder: compiles and runs UnitTests
- Stage runtime: clean production image
- Health check configured
- irishealth-community:2026.1 base"

git add .github/workflows/iris-ci.yml
git commit -m "ci(github-actions): add full CI/CD pipeline

- Job lint: validates directory structure and critical files
- Job build-and-test: builds IRIS, runs UnitTests, tests REST endpoints
- Job publish: pushes to GHCR on main branch
- iris-agentic-dev integrated for test execution"

git add tests/
git commit -m "test: add integration test suite (Test.CardioFlow.Integration)

- TestHL7Flow: injects HL7 ADT message, validates persistence
- TestFHIRFlow: validates FHIR -> SDA3 transformation
- TestStatusTransitions: validates all 3 surgical states
- TestRESTEndpoints: validates REST API responses"
```

---

## Fase 5: Pull Requests

### Criar PR do Agent Builder → develop
```bash
git checkout feature/agent-builder-interop

gh pr create \
  --title "feat(interop): Agent Builder — Production, BS, BP, BO, DTL" \
  --body "## O que foi feito

### Classes criadas
- \`CardioFlow.Production\` — Configuração da produção
- \`CardioFlow.BS.HL7Inbound\` — Business Service HL7 v2 TCP
- \`CardioFlow.BS.FHIRInbound\` — Business Service FHIR REST  
- \`CardioFlow.BP.CardioOrchestrator\` — BPL orquestrador
- \`CardioFlow.BO.SDAPersist\` — Persistência SDA3
- \`CardioFlow.BO.DashboardFeeder\` — Alimentador de staging
- \`CardioFlow.DTL.HL7ToSDA3\` — Transformação HL7 → SDA3
- \`CardioFlow.DTL.FHIRToSDA3\` — Transformação FHIR → SDA3

### Validação
- [x] Compilação limpa (zero errors, zero warnings críticos)
- [x] Produção inicia sem erros
- [x] Mensagem HL7 de teste processada com sucesso
- [x] Bundle FHIR de teste processado com sucesso

### Checklist
- [x] Código compilado via \`iris_compile\`
- [x] Testado via \`iris_execute\`
- [x] Logs verificados via \`iris_interop_query\`" \
  --base develop \
  --head feature/agent-builder-interop \
  --label "agent:builder" \
  --label "interoperability"
```

### Criar PR do Agent Data → develop
```bash
gh pr create \
  --title "feat(analytics): Agent Data — Columnar Storage, Cubos BI, REST API" \
  --body "## O que foi feito

### Tabelas e Views
- \`CardioFlow.Analytics.SurgeryStatus\` com Columnar Index (IRIS 2026)
- Views SQL: vPreOpPanel, vIntraOpPanel, vPostOpPanel

### Cubos IRIS BI
- \`PreOpCube\` — Fila de espera pré-operatória
- \`IntraOpCube\` — Ocupação de salas cirúrgicas
- \`PostOpCube\` — Monitoramento pós-operatório

### REST API
- 6 endpoints em \`/api/cardio/...\`
- WebApp criada via Installer.cls

### Validação
- [x] Columnar index verificado via \`iris_query\`
- [x] Cubos sincronizados com IRIS BI
- [x] Todos endpoints retornam HTTP 200" \
  --base develop \
  --head feature/agent-data-analytics \
  --label "agent:data" \
  --label "analytics"
```

### Criar PR do develop → main (release)
```bash
# Após merge dos PRs de features em develop
gh pr create \
  --title "release: v1.0.0 — IRIS-CardioFlow MVP" \
  --body "## Release 1.0.0

Primeiro release do sistema de monitoramento cirúrgico cardiológico.

### Funcionalidades
- Pipeline HL7 v2 + FHIR R4 → SDA3 → IRIS DB
- Três painéis analíticos com Columnar Storage
- REST API para dashboards
- CI/CD completo com GitHub Actions
- UnitTests %UnitTest.TestCase

### Quality Gate
- ✅ Todos os testes passando
- ✅ Docker build limpo
- ✅ Endpoints REST validados no CI" \
  --base main \
  --head develop \
  --label "release"
```

---

## Fase 6: Configurar Secrets no GitHub

```bash
# Secrets para o CI/CD (GitHub Actions)

# Credenciais do ICR (InterSystems Container Registry) — se usar Enterprise IRIS
gh secret set ICR_USERNAME --body "seu-usuario-icr"
gh secret set ICR_PASSWORD --body "seu-password-icr"

# Para publicação no GHCR (GitHub Container Registry)
# GITHUB_TOKEN é automático — não precisa configurar

# Credenciais IRIS para ambiente de staging (opcional)
gh secret set IRIS_STAGING_HOST --body "iris-staging.suaempresa.com"
gh secret set IRIS_STAGING_PASSWORD --body "SenhaSegura123"
```

---

## Fase 7: Comandos Úteis do Dia a Dia

```bash
# Ver status da pipeline mais recente
gh run list --limit 5

# Ver logs de uma run específica
gh run view <run-id> --log

# Ver PRs abertos
gh pr list

# Ver PRs que precisam de review
gh pr list --search "review:required"

# Fazer merge de um PR após aprovação
gh pr merge <pr-number> --squash --delete-branch

# Criar tag de release
git tag -a v1.0.0 -m "Release 1.0.0 — IRIS-CardioFlow MVP"
git push origin v1.0.0

# Criar GitHub Release
gh release create v1.0.0 \
  --title "IRIS-CardioFlow v1.0.0" \
  --notes "Primeiro release do sistema de monitoramento cardiológico" \
  --target main

# Checar saúde do repositório
gh repo view --json name,defaultBranchRef,isPrivate,pushedAt
```

---

## Integração: gh CLI + iris-agentic-dev no Loop de Desenvolvimento

```bash
# Loop completo de desenvolvimento:
# 1. Criar branch
git checkout -b feature/nova-funcionalidade develop

# 2. Usar MCP para escrever/compilar código
# (no Claude Code ou terminal com iris-agentic-dev)
iris-agentic-dev compile "CardioFlow.NovaClasse.cls"

# 3. Verificar que testes passam
iris-agentic-dev test "UnitTest/"

# 4. Commitar
git add src/
git commit -m "feat: adicionar nova funcionalidade"

# 5. Push e criar PR
git push -u origin feature/nova-funcionalidade
gh pr create --fill --base develop

# 6. Aguardar CI passar
gh run watch

# 7. Fazer merge após aprovação
gh pr merge --squash --delete-branch
```
