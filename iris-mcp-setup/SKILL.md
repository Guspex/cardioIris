# Skill: iris-mcp-setup
## Configuração do Ambiente iris-agentic-dev + Docker para IRIS-CardioFlow

---

## Propósito
Esta skill configura o ambiente completo: instala o binário `iris-agentic-dev`, sobe o IRIS via Docker, e valida a conexão MCP antes de qualquer geração de código.

---

## Fase 1: Instalação do iris-agentic-dev

### Linux (servidor/CI)
```bash
curl -fsSL https://github.com/intersystems-community/iris-agentic-dev/releases/latest/download/iris-agentic-dev-linux-x86_64 \
  -o /usr/local/bin/iris-agentic-dev && chmod +x /usr/local/bin/iris-agentic-dev

# Verificar
iris-agentic-dev --version
```

### Mac Apple Silicon
```bash
sudo mkdir -p /usr/local/bin
curl -fsSL https://github.com/intersystems-community/iris-agentic-dev/releases/latest/download/iris-agentic-dev-macos-arm64 \
  -o /usr/local/bin/iris-agentic-dev && chmod +x /usr/local/bin/iris-agentic-dev
xattr -d com.apple.quarantine /usr/local/bin/iris-agentic-dev 2>/dev/null
```

### Mac Intel
```bash
# Substituir arm64 por x86_64 no comando acima
```

---

## Fase 2: Docker — Dockerfile e Compose

### `docker/Dockerfile`
```dockerfile
# IRIS Community Edition 2026.1
FROM intersystems/iris-community:2026.1

# Copiar código fonte e installer
COPY --chown=irisowner:irisowner src/ /home/irisowner/src/
COPY --chown=irisowner:irisowner src/Installer.cls /home/irisowner/src/

# Executar setup do namespace
RUN iris start IRIS quietly && \
    iris session IRIS -U %SYS "##class(%SYSTEM.OBJ).Load(\"/home/irisowner/src/Installer.cls\",\"ck\")" && \
    iris session IRIS -U %SYS "do ##class(CardioFlow.Installer).Setup()" && \
    iris stop IRIS quietly

EXPOSE 52773 1972

HEALTHCHECK --interval=30s --timeout=10s --retries=5 \
  CMD iris qlist | grep -q "running" || exit 1
```

### `docker/docker-compose.yml`
```yaml
version: "3.8"

services:
  iris:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    container_name: cardioflow-iris
    ports:
      - "52773:52773"   # Web gateway / Atelier REST
      - "1972:1972"     # SuperServer
    volumes:
      - iris-data:/usr/irissys/mgr
      - ./src:/home/irisowner/src:ro
    environment:
      - ISC_DATA_DIRECTORY=/usr/irissys/mgr
    restart: unless-stopped

volumes:
  iris-data:
```

### Subir o container
```bash
cd docker
docker compose up -d --build

# Aguardar estar pronto
docker compose logs -f iris | grep -m1 "IRIS startup complete"
```

---

## Fase 3: Arquivo `.iris-agentic-dev.toml`

Criar na raiz do repositório:
```toml
# CardioFlow — iris-agentic-dev config
container = "cardioflow-iris"
namespace = "CARDIOFLOW"
```

Ou gerar automaticamente:
```bash
iris-agentic-dev init
# Selecionar o container "cardioflow-iris" quando solicitado
```

---

## Fase 4: Configuração do Claude Code / MCP Client

### `~/.claude/settings.json` (Claude Code)
```json
{
  "mcpServers": {
    "iris-agentic-dev": {
      "command": "iris-agentic-dev",
      "args": ["mcp"],
      "env": {
        "OBJECTSCRIPT_WORKSPACE": "${workspaceFolder}",
        "IRIS_CONTAINER": "cardioflow-iris",
        "IRIS_NAMESPACE": "CARDIOFLOW",
        "IRIS_USERNAME": "_SYSTEM",
        "IRIS_PASSWORD": "SYS"
      }
    }
  }
}
```

---

## Fase 5: Validação da Conexão MCP

Executar via MCP tool após setup:

```
# 1. Checar config ativa
check_config()
→ Deve retornar: container="cardioflow-iris", namespace="CARDIOFLOW"

# 2. Listar namespaces disponíveis
iris_admin(action="list_namespaces")
→ Deve listar CARDIOFLOW, USER, %SYS

# 3. Teste básico de execução
iris_execute(code="write $namespace", namespace="CARDIOFLOW")
→ Deve retornar: CARDIOFLOW

# 4. Verificar suporte a HealthShare/SDA
iris_execute(
  code="write ##class(%Dictionary.ClassDefinition).%ExistsId(\"HS.SDA3.Container\")",
  namespace="CARDIOFLOW"
)
→ Deve retornar: 1
```

Se `HS.SDA3.Container` não existir, o IRIS Community não tem o pacote HealthShare. Neste caso:
- Usar `intersystems/irishealth-community:2026.1` no Dockerfile
- Ou ativar o FHIR Server manualmente via terminal IRIS

---

## Fase 6: `Installer.cls` — Setup do Namespace

```objectscript
/// CardioFlow.Installer
/// Configura Namespace, WebApp FHIR, e carrega código fonte
Class CardioFlow.Installer Extends %RegisteredObject
{

ClassMethod Setup(namespace As %String = "CARDIOFLOW") As %Status
{
    set sc = $$$OK
    
    // 1. Criar namespace se não existir
    if '##class(Config.Namespaces).Exists(namespace) {
        set props("Globals") = "CARDIOFLOW"
        set props("Routines") = "CARDIOFLOW"
        set sc = ##class(Config.Namespaces).Create(namespace, .props)
        $$$ThrowOnError(sc)
        write "Namespace "_namespace_" criado.",!
    }
    
    // 2. Trocar para o namespace
    znspace namespace
    
    // 3. Ativar FHIR Server endpoint
    set sc = ##class(HS.FHIRServer.Installer).InstallInstance(
        "/fhir/r4",           // endpoint
        "HealthShare",        // strategy
        ""                    // metadata set
    )
    $$$ThrowOnError(sc)
    write "FHIR Server ativado em /fhir/r4",!
    
    // 4. Carregar código fonte
    set sc = ##class(%SYSTEM.OBJ).LoadDir("/home/irisowner/src/CardioFlow", "ck")
    $$$ThrowOnError(sc)
    write "Código fonte carregado e compilado.",!
    
    // 5. Criar WebApp para REST API dos Dashboards
    set webProps("NameSpace") = namespace
    set webProps("Enabled") = 1
    set webProps("DispatchClass") = "CardioFlow.API.DashboardDispatch"
    set webProps("AutheEnabled") = 32  // Password
    if '##class(Security.Applications).Exists("/api/cardio") {
        set sc = ##class(Security.Applications).Create("/api/cardio", .webProps)
        $$$ThrowOnError(sc)
        write "WebApp /api/cardio criada.",!
    }
    
    write "Setup CardioFlow concluído com sucesso!",!
    quit sc
}

}
```

---

## Troubleshooting Comum

| Problema | Causa | Solução |
|----------|-------|---------|
| `IRIS_UNREACHABLE` | Container não está rodando | `docker compose up -d iris` |
| `HS.SDA3.Container not found` | Imagem Community sem HealthShare | Trocar para `irishealth-community:2026.1` |
| Port 52773 refused | Web server desabilitado (Enterprise) | Adicionar serviço `webgateway` no compose |
| `check_config` mostra namespace errado | `.toml` desatualizado | `iris-agentic-dev init` novamente |
| Compile error `<UNDEFINED>` | Classe dependente não carregada | Carregar em ordem topológica com `iris_compile` |
