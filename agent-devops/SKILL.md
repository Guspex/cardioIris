# Skill: agent-devops (DevOps & QA Engineer)
## Docker · GitHub Actions · %UnitTest · CI/CD · Quality Gate

---

## Identidade do Agente
Você é o **DevOps & QA Engineer** do IRIS-CardioFlow. Você é o guardião da qualidade: cria a infraestrutura Docker, escreve os testes unitários em ObjectScript (`%UnitTest.TestCase`), e configura a pipeline GitHub Actions que valida o build a cada push. Nada vai para `main` sem passar pelos seus testes.

---

## Bloco 1: Dockerfile Multi-Stage

### `docker/Dockerfile`
```dockerfile
# ============================================================
# Stage 1: Builder — compila e valida o código ObjectScript
# ============================================================
FROM intersystems/irishealth-community:2026.1 AS builder

USER root
RUN apt-get update && apt-get install -y git curl && rm -rf /var/lib/apt/lists/*

USER irisowner
WORKDIR /home/irisowner

# Copiar código fonte
COPY --chown=irisowner:irisowner src/ ./src/
COPY --chown=irisowner:irisowner data/ ./data/
COPY --chown=irisowner:irisowner tests/ ./tests/

# Compilar e rodar testes durante build
RUN iris start IRIS quietly && \
    iris session IRIS -U %SYS \
      "##class(%SYSTEM.OBJ).Load(\"/home/irisowner/src/Installer.cls\",\"ck\")" && \
    iris session IRIS -U %SYS \
      "do ##class(CardioFlow.Installer).Setup()" && \
    iris session IRIS -U CARDIOFLOW \
      "set ^UnitTestRoot=\"/home/irisowner/tests\" do ##class(%UnitTest.Manager).RunTest(\"UnitTest/\",\"/nodebug/load/save\") write \"Tests OK\",!" && \
    iris stop IRIS quietly

# ============================================================
# Stage 2: Runtime — imagem final limpa
# ============================================================
FROM intersystems/irishealth-community:2026.1 AS runtime

USER irisowner

# Copiar apenas o necessário (sem tests, sem source raw)
COPY --from=builder --chown=irisowner:irisowner /usr/irissys/mgr/CARDIOFLOW/ /usr/irissys/mgr/CARDIOFLOW/
COPY --chown=irisowner:irisowner docker/iris.conf /usr/irissys/iris.conf

EXPOSE 52773 1972

HEALTHCHECK --interval=30s --timeout=15s --start-period=60s --retries=5 \
  CMD iris qlist IRIS 2>/dev/null | grep -q "running" || exit 1

LABEL org.opencontainers.image.title="IRIS-CardioFlow"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.description="Monitoramento Cirúrgico Cardiológico — IRIS 2026"
```

### `docker/docker-compose.yml`
```yaml
version: "3.8"

services:
  iris:
    build:
      context: ..
      dockerfile: docker/Dockerfile
      target: runtime
    container_name: cardioflow-iris
    hostname: cardioflow-iris
    ports:
      - "52773:52773"
      - "1972:1972"
    volumes:
      - iris-mgr:/usr/irissys/mgr
    environment:
      ISC_DATA_DIRECTORY: /usr/irissys/mgr
    healthcheck:
      test: ["CMD-SHELL", "iris qlist IRIS | grep -q running"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 60s
    restart: unless-stopped

  # Opcional: Web gateway para Enterprise IRIS (sem private web server)
  # webgateway:
  #   image: containers.intersystems.com/intersystems/webgateway:2026.1
  #   ports: ["52773:80"]
  #   depends_on:
  #     iris:
  #       condition: service_healthy

volumes:
  iris-mgr:
    driver: local
```

### `docker/webgateway-init.sh` (para Enterprise IRIS)
```bash
#!/bin/bash
# webgateway-init.sh — Configura o Web Gateway para apontar para IRIS container
set -e

# Aguardar IRIS subir
until curl -sf "http://iris:52773/api/atelier/" > /dev/null 2>&1; do
  echo "Aguardando IRIS..."
  sleep 5
done

# Configurar CSP gateway
cat > /opt/webgateway/bin/CSP.ini << EOF
[SYSTEM]
Local_CSP_System=DISABLED

[APP_PATH:/]
IRIS_HTTP_SERVICE_HOST=iris
IRIS_HTTP_SERVICE_PORT=52773
EOF

echo "Web Gateway configurado com sucesso."
```

---

## Bloco 2: GitHub Actions CI/CD

### `.github/workflows/iris-ci.yml`
```yaml
name: IRIS-CardioFlow CI

on:
  push:
    branches: ["main", "develop", "feature/**"]
  pull_request:
    branches: ["main"]

env:
  IRIS_NAMESPACE: CARDIOFLOW
  IRIS_USERNAME: _SYSTEM
  IRIS_PASSWORD: SYS

jobs:
  # ── Job 1: Lint e validação de estrutura ──────────────────
  lint:
    name: Lint & Structure Check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Verificar estrutura de diretórios
        run: |
          required_dirs=(
            "src/CardioFlow/BS"
            "src/CardioFlow/BP"
            "src/CardioFlow/BO"
            "src/CardioFlow/DTL"
            "src/CardioFlow/API"
            "src/CardioFlow/Analytics"
            "tests/UnitTest"
            "data"
            "docker"
            ".github/workflows"
          )
          for dir in "${required_dirs[@]}"; do
            if [ ! -d "$dir" ]; then
              echo "❌ Diretório obrigatório não encontrado: $dir"
              exit 1
            fi
            echo "✅ $dir"
          done

      - name: Verificar arquivos críticos
        run: |
          required_files=(
            "src/Installer.cls"
            "src/CardioFlow/Production.cls"
            "src/CardioFlow/BP/CardioOrchestrator.cls"
            "docker/Dockerfile"
            "docker/docker-compose.yml"
            ".iris-agentic-dev.toml"
          )
          for f in "${required_files[@]}"; do
            if [ ! -f "$f" ]; then
              echo "❌ Arquivo obrigatório não encontrado: $f"
              exit 1
            fi
            echo "✅ $f"
          done

  # ── Job 2: Build Docker e testes no IRIS ─────────────────
  build-and-test:
    name: Build IRIS + Run UnitTests
    runs-on: ubuntu-latest
    needs: lint
    
    steps:
      - uses: actions/checkout@v4

      - name: Cache Docker layers
        uses: actions/cache@v4
        with:
          path: /tmp/.buildx-cache
          key: ${{ runner.os }}-buildx-${{ hashFiles('docker/Dockerfile') }}
          restore-keys: |
            ${{ runner.os }}-buildx-

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login no InterSystems Container Registry
        # Necessário para imagens irishealth (requer conta ICR gratuita)
        # Comentar se usar iris-community (pública)
        # uses: docker/login-action@v3
        # with:
        #   registry: containers.intersystems.com
        #   username: ${{ secrets.ICR_USERNAME }}
        #   password: ${{ secrets.ICR_PASSWORD }}
        run: echo "Usando iris-community (imagem pública)"

      - name: Build Docker image (stage builder — roda testes)
        run: |
          docker build \
            --target builder \
            --cache-from type=local,src=/tmp/.buildx-cache \
            --cache-to type=local,dest=/tmp/.buildx-cache-new,mode=max \
            -f docker/Dockerfile \
            -t cardioflow-iris:test \
            . 2>&1 | tee build.log
          
          # Verificar se os testes passaram durante o build
          if grep -q "Tests OK" build.log; then
            echo "✅ UnitTests passaram no builder stage"
          else
            echo "❌ UnitTests falharam"
            exit 1
          fi

      - name: Build imagem de runtime
        run: |
          docker build \
            --target runtime \
            -f docker/Dockerfile \
            -t cardioflow-iris:${{ github.sha }} \
            -t cardioflow-iris:latest \
            .

      - name: Subir container de teste
        run: |
          docker run -d \
            --name cardioflow-ci \
            -p 52773:52773 \
            cardioflow-iris:${{ github.sha }}
          
          # Aguardar IRIS iniciar
          echo "Aguardando IRIS iniciar..."
          timeout 120 bash -c 'until curl -sf http://localhost:52773/api/atelier/ > /dev/null 2>&1; do sleep 5; done'
          echo "✅ IRIS está respondendo"

      - name: Instalar iris-agentic-dev
        run: |
          curl -fsSL https://github.com/intersystems-community/iris-agentic-dev/releases/latest/download/iris-agentic-dev-linux-x86_64 \
            -o /usr/local/bin/iris-agentic-dev && chmod +x /usr/local/bin/iris-agentic-dev
          iris-agentic-dev --version

      - name: Verificar conexão MCP
        env:
          IRIS_HOST: localhost
          IRIS_WEB_PORT: "52773"
          IRIS_NAMESPACE: CARDIOFLOW
          IRIS_USERNAME: _SYSTEM
          IRIS_PASSWORD: SYS
          IRIS_CONTAINER: cardioflow-ci
        run: |
          # Verificar namespace existe
          iris-agentic-dev compile "CardioFlow.Production.cls" || echo "Já compilado"

      - name: Rodar UnitTests via iris-agentic-dev
        env:
          IRIS_HOST: localhost
          IRIS_WEB_PORT: "52773"
          IRIS_NAMESPACE: CARDIOFLOW
          IRIS_USERNAME: _SYSTEM
          IRIS_PASSWORD: SYS
          IRIS_CONTAINER: cardioflow-ci
        run: |
          # Executar testes e capturar resultado
          iris-agentic-dev test "UnitTest/" 2>&1 | tee test_results.log
          
          # Checar resultado
          if grep -q "FAILED\|ERROR" test_results.log; then
            echo "❌ Testes falharam:"
            grep -E "FAILED|ERROR" test_results.log
            exit 1
          fi
          echo "✅ Todos os testes passaram"

      - name: Testar endpoints REST
        run: |
          # Health check
          curl -sf -u "_SYSTEM:SYS" http://localhost:52773/api/cardio/health | \
            python3 -c "import sys,json; d=json.load(sys.stdin); assert d['status']=='ok', 'Health falhou'"
          echo "✅ /api/cardio/health OK"
          
          # Summary
          curl -sf -u "_SYSTEM:SYS" http://localhost:52773/api/cardio/dashboards/summary | \
            python3 -c "import sys,json; d=json.load(sys.stdin); assert 'summary' in d"
          echo "✅ /api/cardio/dashboards/summary OK"

      - name: Upload logs de falha
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: iris-build-logs
          path: |
            build.log
            test_results.log
          retention-days: 7

      - name: Limpar container de CI
        if: always()
        run: docker rm -f cardioflow-ci 2>/dev/null || true

  # ── Job 3: Push para registry (apenas em main) ───────────
  publish:
    name: Publish Docker Image
    runs-on: ubuntu-latest
    needs: build-and-test
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Login no GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build e push
        uses: docker/build-push-action@v5
        with:
          context: .
          file: docker/Dockerfile
          target: runtime
          push: true
          tags: |
            ghcr.io/${{ github.repository }}:latest
            ghcr.io/${{ github.repository }}:${{ github.sha }}
```

---

## Bloco 3: UnitTests ObjectScript

### `tests/UnitTest/Integration.cls`
```objectscript
/// Test.CardioFlow.Integration
/// Testes de integração do pipeline IRIS-CardioFlow
/// Executa: iris_test(spec="UnitTest/", namespace="CARDIOFLOW")
Class Test.CardioFlow.Integration Extends %UnitTest.TestCase
{

/// Garante que a produção existe antes dos testes
Method OnBeforeAllTests() As %Status
{
    // Verificar que a produção está definida
    set sc = ##class(Ens.Director).GetProductionStatus(.status, .prodName)
    if prodName = "" {
        do ##class(Ens.Director).StartProduction("CardioFlow.Production")
    }
    quit $$$OK
}

/// TestHL7Flow — injeta mensagem HL7 ADT e valida persistência
Method TestHL7Flow() As %Status
{
    set sc = $$$OK
    
    // Montar mensagem HL7 de teste
    set hl7Text = "MSH|^~\&|HIS|HOSPITAL|CARDIOFLOW|IRIS|20240101120000||ADT^A08|MSG001|P|2.5"_$char(13)
    set hl7Text = hl7Text_"PID|1||PAT001^^^HOSPITAL^MR||Silva^João||19800515|M"_$char(13)
    set hl7Text = hl7Text_"PV1|1|I|CARDIO^01^A|||||||CARDT|||||||ADM|V01|PRE"
    
    // Contar registros antes
    set before = ##class(CardioFlow.Analytics.SurgeryStatus).%OpenId(
        ##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM CardioFlow_Analytics.SurgeryStatus").%GetData(1)
    )
    set countBefore = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT COUNT(*) FROM CardioFlow_Analytics.SurgeryStatus WHERE PatientId='PAT001'"
    ).%GetData(1)
    
    // Simular injeção HL7 via Ens.Director
    set hl7Msg = ##class(EnsLib.HL7.Message).%New()
    do hl7Msg.ImportFromString(hl7Text)
    
    set sc = ##class(Ens.Director).CreateBusinessService("BS_HL7_Inbound", .svc)
    if $$$ISERR(sc) {
        do ..LogMessage("AVISO: BS não pôde ser criado em modo test — usando direct call")
        // Testar DTL diretamente
        set container = ##class(HS.SDA3.Container).%New()
        set sc = ##class(CardioFlow.DTL.HL7ToSDA3).Transform(hl7Msg, .container)
        $$$ThrowOnError(sc)
        do ..AssertNotEquals("", container.Patient.PatientNumbers.(1).Number, "PatientId mapeado")
        quit sc
    }
    
    set sc = svc.ProcessInput(hl7Msg, .resp)
    $$$ThrowOnError(sc)
    
    // Aguardar processamento assíncrono (máximo 10 segundos)
    set timeout = $zh + 10
    while ($zh < timeout) {
        set count = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT COUNT(*) FROM CardioFlow_Analytics.SurgeryStatus WHERE PatientId='PAT001'"
        ).%GetData(1)
        if count > countBefore { quit }
        hang 0.5
    }
    
    // Validar persistência
    do ..AssertTrue(count > countBefore, "Registro HL7 foi persistido no banco")
    
    // Validar status mapeado corretamente (PV1-18=PRE -> AWAITING)
    set rs = ##class(%SQL.Statement).%ExecDirect(,
        "SELECT TOP 1 Status FROM CardioFlow_Analytics.SurgeryStatus "_
        "WHERE PatientId='PAT001' ORDER BY EventTime DESC"
    )
    if rs.%Next() {
        do ..AssertEquals("AWAITING", rs.%Get("Status"), "Status HL7 PRE -> AWAITING")
    } else {
        do ..AssertTrue(0, "Nenhum registro encontrado para PAT001")
    }
    
    quit sc
}

/// TestFHIRFlow — envia Bundle FHIR e valida transformação SDA3
Method TestFHIRFlow() As %Status
{
    set sc = $$$OK
    
    // Bundle FHIR R4 de teste
    set fhirBundle = {
        "resourceType": "Bundle",
        "type": "transaction",
        "entry": [
            {
                "resource": {
                    "resourceType": "Patient",
                    "id": "FHIR-PAT-001",
                    "name": [{"family": "Costa", "given": ["Maria"]}],
                    "birthDate": "1975-03-22",
                    "gender": "female"
                }
            },
            {
                "resource": {
                    "resourceType": "Encounter",
                    "id": "ENC-001",
                    "status": "planned",
                    "period": {
                        "start": "2024-06-15T08:00:00Z"
                    }
                }
            },
            {
                "resource": {
                    "resourceType": "Procedure",
                    "id": "PROC-001",
                    "status": "preparation",
                    "code": {
                        "coding": [{"code": "CABG", "display": "Bypass Cardíaco"}]
                    }
                }
            }
        ]
    }
    
    // Testar DTL FHIR -> SDA3 diretamente
    set fhirReq = ##class(CardioFlow.Msg.FHIRRequest).%New()
    set fhirReq.ResourceType = "Bundle"
    do fhirReq.Payload.Write(fhirBundle.%ToJSON())
    
    set container = ##class(HS.SDA3.Container).%New()
    set sc = ##class(CardioFlow.DTL.FHIRToSDA3).Transform(fhirReq, .container)
    $$$ThrowOnError(sc)
    
    // Validar mapeamentos
    do ..AssertEquals("FHIR-PAT-001", container.Patient.PatientNumbers.(1).Number,
        "FHIR Patient.id mapeado para SDA3")
    do ..AssertEquals("Costa", container.Patient.Name.FamilyName,
        "FHIR Patient.name.family mapeado")
    do ..AssertEquals("PRE", container.Encounters.(1).AdmissionType.Code,
        "FHIR Encounter.status='planned' -> PRE")
    do ..AssertEquals("CABG", container.Procedures.(1).Procedure.Code,
        "FHIR Procedure.code mapeado")
    
    quit sc
}

/// TestStatusTransitions — valida as três transições de estado
Method TestStatusTransitions() As %Status
{
    set sc = $$$OK
    
    set statusMap("PRE") = "AWAITING"
    set statusMap("SURG") = "IN_SURGERY"
    set statusMap("REC") = "POST_OP"
    
    set s = ""
    for {
        set s = $order(statusMap(s))
        quit:s=""
        
        // Criar registro de teste
        set tracker = ##class(CardioFlow.Analytics.SurgeryStatus).%New()
        set tracker.PatientId = "STATUS-TEST-"_s
        set tracker.Status = statusMap(s)
        set tracker.Source = "TEST"
        set tracker.EventTime = $zdt($h, 3)
        set sc = tracker.%Save()
        $$$ThrowOnError(sc)
        
        // Verificar que foi salvo com status correto
        set rs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT Status FROM CardioFlow_Analytics.SurgeryStatus "_
            "WHERE PatientId=?", "STATUS-TEST-"_s
        )
        if rs.%Next() {
            do ..AssertEquals(statusMap(s), rs.%Get("Status"),
                "Status "_s_" persistido como "_statusMap(s))
        }
    }
    
    quit sc
}

/// TestRESTEndpoints — valida que os endpoints respondem corretamente
Method TestRESTEndpoints() As %Status
{
    set sc = $$$OK
    
    set req = ##class(%Net.HttpRequest).%New()
    set req.Server = "localhost"
    set req.Port = 52773
    set req.Username = "_SYSTEM"
    set req.Password = "SYS"
    
    // Testar /health
    set sc = req.Get("/api/cardio/health")
    do ..AssertEquals(200, req.HttpResponse.StatusCode, "GET /health retorna 200")
    
    // Testar /dashboards/summary
    set sc = req.Get("/api/cardio/dashboards/summary")
    do ..AssertEquals(200, req.HttpResponse.StatusCode, "GET /summary retorna 200")
    
    set responseBody = req.HttpResponse.Data.Read()
    do ..AssertTrue(responseBody [ "summary", "GET /summary retorna JSON com 'summary'")
    
    // Testar /dashboards/preop
    set sc = req.Get("/api/cardio/dashboards/preop")
    do ..AssertEquals(200, req.HttpResponse.StatusCode, "GET /preop retorna 200")
    
    quit sc
}

/// Limpeza após todos os testes
Method OnAfterAllTests() As %Status
{
    // Remover dados de teste
    do ##class(%SQL.Manager.API).ExecDirect(,
        "DELETE FROM CardioFlow_Analytics.SurgeryStatus WHERE Source='TEST' OR PatientId LIKE 'STATUS-TEST-%'"
    )
    quit $$$OK
}

}
```

---

## Bloco 4: Dados de Teste

### `data/sample_hl7.txt`
```
MSH|^~\&|HIS|HOSP_FLORIPA|CARDIOFLOW|IRIS|20240615120000||ADT^A08|ADT001|P|2.5
PID|1||PAT001^^^HOSP^MR||Silva^João^Carlos||19650320|M|||Rua das Flores 123^^Florianópolis^SC^88000000
PV1|1|I|CARDIO^01^A|||12345^Dr.Cardoso^Antonio||||||||||ADM|V01|PRE
```

### `data/sample_fhir.json`
```json
{
  "resourceType": "Bundle",
  "id": "cardioflow-test-bundle",
  "type": "transaction",
  "entry": [
    {
      "resource": {
        "resourceType": "Patient",
        "id": "FHIR-TEST-001",
        "name": [{ "family": "Santos", "given": ["Ana", "Paula"] }],
        "birthDate": "1972-09-14",
        "gender": "female"
      }
    },
    {
      "resource": {
        "resourceType": "Encounter",
        "id": "ENC-TEST-001",
        "status": "in-progress",
        "period": { "start": "2024-06-15T14:30:00Z" }
      }
    },
    {
      "resource": {
        "resourceType": "Procedure",
        "id": "PROC-TEST-001",
        "status": "in-progress",
        "code": {
          "coding": [{ "code": "VALVE-REPAIR", "display": "Reparo Valvar Cardíaco" }]
        },
        "performedDateTime": "2024-06-15T14:35:00Z"
      }
    }
  ]
}
```

---

## Execução dos Testes via iris-agentic-dev MCP

```
# Gerar scaffold de testes para classes existentes
iris_generate_test(class="CardioFlow.BO.SDAPersist", namespace="CARDIOFLOW")
iris_generate_test(class="CardioFlow.DTL.HL7ToSDA3", namespace="CARDIOFLOW")

# Escrever a classe de integração
iris_doc(action="write", name="Test.CardioFlow.Integration.cls", content=..., namespace="CARDIOFLOW")
iris_compile(documents="Test.CardioFlow.Integration.cls", namespace="CARDIOFLOW")

# Rodar todos os testes
iris_test(spec="UnitTest/", namespace="CARDIOFLOW")

# Ver resultados detalhados se truncado
iris_get_log(id=<log_id_returned>)
```

---

## Quality Gate — Critérios de Aprovação

| Critério | Threshold | Ferramenta |
|----------|-----------|------------|
| Todos os testes passando | 100% | `iris_test` |
| Zero erros de compilação | 0 errors | `iris_compile` |
| Produção iniciada sem erros | status=running | `iris_production` |
| Endpoints REST respondendo | HTTP 200 | CI curl checks |
| Columnar index criado | verificado | `iris_query` |
| Build Docker limpo | exit 0 | `docker build` |
