# IRIS-CardioFlow — Master Skill Orchestrator
## Specification-Driven Development via iris-agentic-dev MCP

---

## Visão Geral

Este documento é o **ponto de entrada obrigatório** antes de qualquer ação de construção do projeto IRIS-CardioFlow. Ele orquestra três agentes especializados, cada um com seu próprio SKILL.md, que operam via **iris-agentic-dev MCP** (Model Context Protocol) contra uma instância live do InterSystems IRIS 2026.

### Stack Tecnológico
- **Runtime**: InterSystems IRIS 2026.1 (Community ou Enterprise)
- **MCP Server**: `iris-agentic-dev` v0.5.0+
- **Interoperabilidade**: HL7 v2 (ADT/ORM) + FHIR R4
- **Dados Clínicos**: SDA3 (HS.SDA3.Container)
- **Analytics**: IRIS BI / Columnar Storage
- **CI/CD**: GitHub Actions + Docker multi-stage

---

## Pré-Requisitos Globais (Verificar Antes de Qualquer Skill)

### 1. iris-agentic-dev instalado e conectado
```bash
# Verificar versão
iris-agentic-dev --version   # deve ser >= 0.5.0

# Verificar conexão com IRIS
iris-agentic-dev mcp  # deve iniciar sem erros
```

### 2. IRIS Container rodando
```bash
docker ps | grep iris   # deve mostrar container ativo
```
Se não: execute `docker compose up -d` no diretório `docker/` do projeto.

### 3. Namespace CARDIOFLOW existente
Usar `iris_admin` via MCP para verificar:
```
iris_admin(action="list_namespaces")
```
Se não existir: executar `Installer.cls` primeiro (ver skill DevOps).

### 4. GitHub CLI autenticado
```bash
gh auth status   # deve mostrar "Logged in to github.com"
```

---

## Fluxo de Execução dos Agentes

```
[MASTER SKILL]
      │
      ├─ 1º: iris-mcp-setup/SKILL.md    ← Setup do ambiente MCP + Docker
      │
      ├─ 2º: agent-builder/SKILL.md     ← Classes ObjectScript/BPL/DTL
      │         └─ Usa: iris_compile, iris_doc, iris_execute, iris_test
      │
      ├─ 3º: agent-data/SKILL.md        ← SQL, Cubos BI, REST API
      │         └─ Usa: iris_query, iris_execute, iris_doc, iris_compile
      │
      ├─ 4º: agent-devops/SKILL.md      ← Docker, GitHub Actions, UnitTest
      │         └─ Usa: iris_test, iris_production, github-cli
      │
      └─ 5º: github-cli/SKILL.md        ← Repositório, commits, PRs, CI
```

---

## Estrutura de Arquivos do Repositório

```
iris-cardioflow/
├── .github/
│   └── workflows/
│       └── iris-ci.yml
├── docker/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── webgateway-init.sh
├── src/
│   └── CardioFlow/
│       ├── Production.cls
│       ├── BS/
│       │   ├── HL7Inbound.cls
│       │   └── FHIRInbound.cls
│       ├── BP/
│       │   └── CardioOrchestrator.bpl
│       ├── BO/
│       │   ├── SDAPersist.cls
│       │   └── DashboardFeeder.cls
│       ├── DTL/
│       │   ├── HL7ToSDA3.dtl
│       │   └── FHIRToSDA3.dtl
│       ├── API/
│       │   └── DashboardDispatch.cls
│       └── Analytics/
│           ├── PreOpCube.cls
│           ├── IntraOpCube.cls
│           └── PostOpCube.cls
├── src/
│   └── Installer.cls
├── tests/
│   └── UnitTest/
│       └── Integration.cls
├── data/
│   ├── sample_hl7.txt
│   └── sample_fhir.json
├── .iris-agentic-dev.toml
└── README.md
```

---

## Convenções Globais de Código

### ObjectScript
- Package raiz: `CardioFlow`
- Compilar sempre com: `iris_compile("CardioFlow.*.cls")`
- Tratar erros com `$$$ThrowOnError(sc)` (não `If $$$ISERR(sc)` simples)
- Properties nullable: usar `%String(MAXLEN=256)` com valor default `""`

### BPL/DTL
- Todo BPL deve ter `<errorhandler>` configurado
- DTLs devem validar campos obrigatórios antes de mapear

### SDA3
- Container: `HS.SDA3.Container`
- Sempre usar `##class(HS.SDA3.Container).%New()` — nunca instanciar diretamente
- Processar via `##class(HS.HC.UniversalViewer.API).ProcessSDA()`

### Status do Paciente (Enum interno)
```objectscript
/// Constantes de status
Parameter AWAITING = "AWAITING";     // Aguardando Cirurgia
Parameter IN_SURGERY = "IN_SURGERY"; // Em Cirurgia  
Parameter POST_OP = "POST_OP";       // Pós-Cirúrgico
```

---

## Usando iris-agentic-dev MCP — Referência Rápida

| Ação | Ferramenta MCP | Exemplo |
|------|----------------|---------|
| Escrever/ler classe | `iris_doc` | `iris_doc(action="write", name="CardioFlow.BS.HL7Inbound.cls", content=...)` |
| Compilar | `iris_compile` | `iris_compile(documents="CardioFlow.*.cls")` |
| Executar ObjectScript | `iris_execute` | `iris_execute(code="do ##class(CardioFlow.Installer).Setup()")` |
| Query SQL | `iris_query` | `iris_query(sql="SELECT * FROM CardioFlow_Analytics.SurgeryStatus")` |
| Rodar testes | `iris_test` | `iris_test(spec="UnitTest/")` |
| Controlar produção | `iris_production` | `iris_production(action="start", production="CardioFlow.Production")` |
| Ver logs | `iris_interop_query` | `iris_interop_query(target="messages", production="CardioFlow.Production")` |
| Debug erros | `iris_debug` | `iris_debug(action="get_error_logs")` |
| Buscar classes | `iris_search` | `iris_search(query="SDA3", category="cls")` |

---

## Ordem de Leitura das Skills

**OBRIGATÓRIO**: Ler na sequência abaixo antes de qualquer geração de código:

1. `iris-mcp-setup/SKILL.md` — Configuração do ambiente
2. `agent-builder/SKILL.md` — Construção do código IRIS
3. `agent-data/SKILL.md` — Dados e analytics
4. `agent-devops/SKILL.md` — Docker, testes e CI/CD
5. `github-cli/SKILL.md` — Gestão do repositório

Cada skill contém instruções específicas e exemplos de código prontos para uso.
