# Skill: agent-builder (Interoperability Architect)
## ObjectScript · BPL · DTL · HL7 v2 · FHIR → SDA3

---

## Identidade do Agente
Você é o **Interoperability Architect** do projeto IRIS-CardioFlow. Seu papel é construir todas as classes de interoperabilidade: Business Services, Business Process, Business Operations e transformações DTL. Use exclusivamente as ferramentas `iris_doc`, `iris_compile`, `iris_execute` do MCP iris-agentic-dev.

**Regra de Ouro**: Nunca assuma que uma classe compilou corretamente — sempre confirme com `iris_compile` e corrija erros antes de avançar.

---

## Workflow de Construção

```
1. iris_doc(write) → salva a classe no IRIS
2. iris_compile()  → compila e verifica erros
3. iris_execute()  → testa execução básica
4. iris_test()     → roda UnitTest relacionado
5. git commit      → apenas após todos os passos acima passarem
```

---

## Bloco 1: Production.cls

### Código
```objectscript
/// CardioFlow.Production
/// Produção principal do sistema de monitoramento cardiológico
Class CardioFlow.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="CardioFlow.Production" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description>IRIS-CardioFlow — Monitoramento Cirúrgico Cardiológico</Description>
  <ActorPoolSize>2</ActorPoolSize>
  
  <Item Name="BS_HL7_Inbound" Category="BS" ClassName="CardioFlow.BS.HL7Inbound"
        PoolSize="1" Enabled="true" Foreground="false" Comment="Entrada HL7 v2 via TCP">
    <Setting Target="Adapter" Name="Port">6661</Setting>
    <Setting Target="Adapter" Name="StayConnected">-1</Setting>
  </Item>
  
  <Item Name="BS_FHIR_Inbound" Category="BS" ClassName="CardioFlow.BS.FHIRInbound"
        PoolSize="1" Enabled="true" Foreground="false" Comment="Entrada FHIR R4 via REST">
  </Item>
  
  <Item Name="BP_Cardio_Orchestrator" Category="BP" ClassName="CardioFlow.BP.CardioOrchestrator"
        PoolSize="2" Enabled="true" Foreground="false" Comment="Orquestrador BPL central">
  </Item>
  
  <Item Name="BO_SDA_Persist" Category="BO" ClassName="CardioFlow.BO.SDAPersist"
        PoolSize="1" Enabled="true" Foreground="false" Comment="Persistência SDA3 no IRIS DB">
  </Item>
  
  <Item Name="BO_Dashboard_Feeder" Category="BO" ClassName="CardioFlow.BO.DashboardFeeder"
        PoolSize="1" Enabled="true" Foreground="false" Comment="Alimentador de tabelas de staging">
  </Item>
</Production>
}

}
```

### Ação MCP
```
iris_doc(action="write", name="CardioFlow.Production.cls", content=<código acima>, namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.Production.cls", namespace="CARDIOFLOW")
```

---

## Bloco 2: Business Services

### `CardioFlow.BS.HL7Inbound.cls`
```objectscript
/// CardioFlow.BS.HL7Inbound
/// Business Service para receber mensagens HL7 v2 via TCP (ADT/ORM)
Class CardioFlow.BS.HL7Inbound Extends EnsLib.HL7.Service.TCP
{

Parameter SETTINGS = "TargetConfigName:Basic,MessageSchemaCategory:Basic";

Property TargetConfigName As %String [ InitialExpression = "BP_Cardio_Orchestrator" ];

/// Override para adicionar logging de diagnóstico
Method OnProcessInput(pMsgIn As EnsLib.HL7.Message, Output pMsgOut As %RegisteredObject) As %Status
{
    set sc = $$$OK
    try {
        $$$LOGINFO("HL7 recebido: "_pMsgIn.Name_" / Tipo: "_pMsgIn.GetValueAt("MSH:9"))
        set sc = ##super(pMsgIn, .pMsgOut)
    } catch ex {
        set sc = ex.AsStatus()
        $$$LOGERROR("Erro em HL7Inbound: "_$system.Status.GetErrorText(sc))
    }
    quit sc
}

}
```

### `CardioFlow.BS.FHIRInbound.cls`
```objectscript
/// CardioFlow.BS.FHIRInbound
/// Business Service FHIR R4 — delega ao BP via mensagem %String
Class CardioFlow.BS.FHIRInbound Extends Ens.BusinessService
{

Parameter ADAPTER = "Ens.InboundAdapter";

Property TargetConfigName As %String [ InitialExpression = "BP_Cardio_Orchestrator" ];

/// Recebe payload FHIR serializado como JSON e encaminha ao orquestrador
Method OnProcessInput(pFHIRJson As %Stream.GlobalCharacter, Output pMsgOut As %RegisteredObject) As %Status
{
    set sc = $$$OK
    try {
        set request = ##class(CardioFlow.Msg.FHIRRequest).%New()
        set request.ResourceType = "Bundle"
        do request.Payload.CopyFrom(pFHIRJson)
        set sc = ..SendRequestAsync(..TargetConfigName, request)
        $$$ThrowOnError(sc)
    } catch ex {
        set sc = ex.AsStatus()
        $$$LOGERROR("Erro em FHIRInbound: "_$system.Status.GetErrorText(sc))
    }
    quit sc
}

}
```

### Ação MCP
```
iris_doc(action="write", name="CardioFlow.BS.HL7Inbound.cls", content=..., namespace="CARDIOFLOW")
iris_doc(action="write", name="CardioFlow.BS.FHIRInbound.cls", content=..., namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.BS.*.cls", namespace="CARDIOFLOW")
```

---

## Bloco 3: Mensagens

### `CardioFlow.Msg.FHIRRequest.cls`
```objectscript
Class CardioFlow.Msg.FHIRRequest Extends Ens.Request
{

Property ResourceType As %String(MAXLEN=64);
Property Payload As %Stream.GlobalCharacter;

Storage Default
{
<Data name="FHIRRequestDefaultData">
<Subscript>"FHIRRequest"</Subscript>
<Value name="1"><Value>ResourceType</Value></Value>
<Value name="2"><Value>Payload</Value></Value>
</Data>
<DefaultData>FHIRRequestDefaultData</DefaultData>
<Type>%Storage.Persistent</Type>
}

}
```

---

## Bloco 4: Business Process (BPL)

### Por que `.bpl` e não `.cls`

O IRIS armazena Business Processes em **dois documentos separados**:

| Documento | Papel |
|-----------|-------|
| `CardioFlow.BP.CardioOrchestrator.bpl` | Fonte nativa BPL — XML puro que o BPL Editor lê/escreve. É este que o `iris_doc` deve gravar. |
| `CardioFlow.BP.CardioOrchestrator.cls` | Gerado automaticamente pelo compilador BPL — **nunca editar à mão**. |

Gravar como `.cls` com XData BPL embutido funciona para compilação pontual, mas perde a fidelidade do documento BPL: o editor visual do Portal não consegue abrir, o source control não rastreia corretamente, e `iris_doc(action="read")` retorna o `.cls` gerado em vez da fonte BPL real.

**Regra**: sempre gravar `NomeClasse.bpl` via `iris_doc`, depois compilar. O `.cls` é produto da compilação.

---

### `CardioFlow.BP.CardioOrchestrator.bpl` — Documento BPL completo

O documento `.bpl` é **XML puro**, sem wrapper de classe ObjectScript. O elemento raiz é `<process>`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<process language="objectscript"
         request="Ens.Request"
         response="Ens.Response"
         height="2000" width="2000"
         xmlns="http://www.intersystems.com/bpl" >

  <!-- ═══════════════════════════════════════════════
       Contexto do processo (variáveis de instância)
       Equivalente às Properties da classe gerada
       ═══════════════════════════════════════════════ -->
  <context>
    <property name="Source"        type="%String"          instantiate="0"/>
    <property name="PatientStatus" type="%String"          instantiate="0"/>
    <property name="SDAContainer"  type="HS.SDA3.Container" instantiate="1"/>
  </context>

  <sequence xend="200" yend="1800">

    <!-- ─── Passo 1: Identificar tipo de mensagem ─── -->
    <if name="É HL7?"
        condition='request.%IsA("EnsLib.HL7.Message")'
        xpos="200" ypos="250">

      <true>
        <!-- Transformar HL7 v2 → SDA3 via DTL -->
        <transform name="HL7 para SDA3"
                   class="CardioFlow.DTL.HL7ToSDA3"
                   source="request"
                   target="context.SDAContainer"
                   xpos="200" ypos="400"/>

        <assign name="Marcar Origem HL7"
                property="context.Source"
                value='"HL7"'
                action="set"
                xpos="200" ypos="500"/>
      </true>

      <false>
        <!-- Transformar FHIR R4 Bundle → SDA3 via DTL -->
        <transform name="FHIR para SDA3"
                   class="CardioFlow.DTL.FHIRToSDA3"
                   source="request"
                   target="context.SDAContainer"
                   xpos="200" ypos="400"/>

        <assign name="Marcar Origem FHIR"
                property="context.Source"
                value='"FHIR"'
                action="set"
                xpos="200" ypos="500"/>
      </false>
    </if>

    <!-- ─── Passo 2: Validar e normalizar status cirúrgico ─── -->
    <code name="Normalizar Status" xpos="200" ypos="650">
      <![CDATA[
        // Ler código de admissão do Encounter SDA3
        // PRE = Aguardando, SURG = Em Cirurgia, REC = Pós-Op
        set encounter = context.SDAContainer.Encounters.GetAt(1)
        set admCode = $select($isobject(encounter): encounter.AdmissionType.Code, 1: "")

        if admCode = "PRE" {
            set context.PatientStatus = "AWAITING"
        } elseif admCode = "SURG" {
            set context.PatientStatus = "IN_SURGERY"
        } elseif admCode = "REC" {
            set context.PatientStatus = "POST_OP"
        } else {
            $$$LOGWARNING("Status desconhecido: '"_admCode_"'. Defaultando para AWAITING. Origem: "_context.Source)
            set context.PatientStatus = "AWAITING"
        }
      ]]>
    </code>

    <!-- ─── Passo 3: Validação de segurança (guard) ─── -->
    <if name="Container Válido?"
        condition='$isobject(context.SDAContainer) && (context.PatientStatus '= "")'
        xpos="200" ypos="800">

      <true>

        <!-- ─── Passo 4: Persistir SDA3 (síncrono — aguardar confirmação) ─── -->
        <call name="Persistir SDA"
              target="BO_SDA_Persist"
              async="0"
              xpos="200" ypos="950">
          <request type="CardioFlow.Msg.SDAPersistRequest">
            <assign property="callrequest.Container"     value="context.SDAContainer"  action="set"/>
            <assign property="callrequest.PatientStatus" value="context.PatientStatus" action="set"/>
            <assign property="callrequest.Source"        value="context.Source"        action="set"/>
          </request>
          <response type="Ens.Response"/>
        </call>

        <!-- ─── Passo 5: Alimentar staging de dashboard (assíncrono) ─── -->
        <call name="Feeder Dashboard"
              target="BO_Dashboard_Feeder"
              async="1"
              xpos="200" ypos="1100">
          <request type="CardioFlow.Msg.SDAPersistRequest">
            <assign property="callrequest.Container"     value="context.SDAContainer"  action="set"/>
            <assign property="callrequest.PatientStatus" value="context.PatientStatus" action="set"/>
            <assign property="callrequest.Source"        value="context.Source"        action="set"/>
          </request>
        </call>

      </true>

      <false>
        <!-- Container inválido — logar e encerrar sem persistir -->
        <code name="Log Container Inválido" xpos="200" ypos="950">
          <![CDATA[
            $$$LOGERROR("BPL CardioOrchestrator: SDAContainer inválido ou PatientStatus vazio. Mensagem descartada. Origem: "_context.Source)
          ]]>
        </code>
      </false>
    </if>

  </sequence>
</process>
```

---

### Ação MCP — gravar e compilar o `.bpl`

```
# 1. Gravar o documento BPL nativo (NÃO .cls)
iris_doc(
  action="write",
  name="CardioFlow.BP.CardioOrchestrator.bpl",
  content=<xml acima>,
  namespace="CARDIOFLOW"
)

# 2. Compilar o .bpl — isso gera o .cls automaticamente
iris_compile(
  documents="CardioFlow.BP.CardioOrchestrator.bpl",
  namespace="CARDIOFLOW"
)
# Saída esperada:
#   Compiling CardioFlow.BP.CardioOrchestrator.bpl
#   Compiling class CardioFlow.BP.CardioOrchestrator
#   Compilation finished successfully.

# 3. Verificar que o .cls foi gerado pelo compilador
iris_doc(
  action="exists",
  name="CardioFlow.BP.CardioOrchestrator.cls",
  namespace="CARDIOFLOW"
)
# → deve retornar true

# 4. NUNCA escrever o .cls gerado de volta — apenas ler para inspeção
iris_doc(
  action="read",
  name="CardioFlow.BP.CardioOrchestrator.cls",
  namespace="CARDIOFLOW"
)
```

---

### Estrutura no repositório Git

```
src/CardioFlow/BP/
└── CardioOrchestrator.bpl    ← commitar este (fonte BPL)
                               # O .cls gerado NÃO vai para o Git
```

Adicionar ao `.gitignore`:
```gitignore
# Classes geradas pela compilação BPL/DTL — não commitar
src/CardioFlow/BP/*.cls
src/CardioFlow/DTL/*.cls
```

> **Atenção para DTLs**: a mesma regra se aplica — arquivos `.dtl` são a fonte; o `.cls` é gerado. Ver Bloco 6.

---

## Bloco 5: Business Operations

### `CardioFlow.BO.SDAPersist.cls`
```objectscript
/// CardioFlow.BO.SDAPersist
/// Persiste o container SDA3 no banco de dados IRIS
Class CardioFlow.BO.SDAPersist Extends Ens.BusinessOperation
{

Parameter INVOCATION = "Queue";

Method OnPersistSDA(pRequest As CardioFlow.Msg.SDAPersistRequest, Output pResponse As Ens.Response) As %Status
{
    set sc = $$$OK
    try {
        // Processar SDA3 via HealthShare API
        set sc = ##class(HS.HC.UniversalViewer.API).ProcessSDA(
            pRequest.Container, .patientId
        )
        $$$ThrowOnError(sc)
        
        // Registrar em tabela de tracking de status cirúrgico
        set tracker = ##class(CardioFlow.Analytics.SurgeryStatus).%New()
        set tracker.PatientId = patientId
        set tracker.Status = pRequest.PatientStatus
        set tracker.Source = pRequest.Source
        set tracker.EventTime = $ztimestamp
        set sc = tracker.%Save()
        $$$ThrowOnError(sc)
        
        $$$LOGINFO("Paciente "_patientId_" persistido. Status: "_pRequest.PatientStatus)
    } catch ex {
        set sc = ex.AsStatus()
        $$$LOGERROR("Erro em SDAPersist: "_$system.Status.GetErrorText(sc))
    }
    quit sc
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="CardioFlow.Msg.SDAPersistRequest">
    <Method>OnPersistSDA</Method>
  </MapItem>
</MapItems>
}

}
```

---

## Bloco 6: DTL — HL7 v2 para SDA3

### Por que `.dtl` e não `.cls`

Assim como o BPL, a DTL tem seu próprio tipo de documento nativo no IRIS. O `iris_doc` deve receber `CardioFlow.DTL.HL7ToSDA3.dtl` — o `.cls` correspondente é gerado automaticamente pela compilação e **nunca deve ser editado**.

### `CardioFlow.DTL.HL7ToSDA3.dtl` — documento DTL nativo

O arquivo `.dtl` é **XML puro** com elemento raiz `<transform>` (sem wrapper de classe):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<transform sourceClass="EnsLib.HL7.Message"
           targetClass="HS.SDA3.Container"
           sourceDocType=""
           create="new"
           language="objectscript"
           ignoreMissing="1"
           reportErrors="1"
           xmlns="http://www.intersystems.com/dtl">

  <!-- ══ PATIENT ══════════════════════════════════════════ -->
  <!-- PID-3.1: número do paciente no hospital -->
  <assign value="source.GetValueAt(&quot;PID:3.1&quot;)"
          property="target.Patient.PatientNumbers.(1).Number"
          action="set"/>
  <assign value="source.GetValueAt(&quot;PID:3.4&quot;)"
          property="target.Patient.PatientNumbers.(1).Organization.Code"
          action="set"/>

  <!-- PID-5: nome (sobrenome ^ nome) -->
  <assign value="source.GetValueAt(&quot;PID:5.1&quot;)"
          property="target.Patient.Name.FamilyName"
          action="set"/>
  <assign value="source.GetValueAt(&quot;PID:5.2&quot;)"
          property="target.Patient.Name.GivenName"
          action="set"/>

  <!-- PID-7: data de nascimento | PID-8: sexo -->
  <assign value="source.GetValueAt(&quot;PID:7&quot;)"
          property="target.Patient.BirthTime"
          action="set"/>
  <assign value="source.GetValueAt(&quot;PID:8&quot;)"
          property="target.Patient.Gender.Code"
          action="set"/>

  <!-- ══ ENCOUNTER / STATUS CIRÚRGICO ════════════════════ -->
  <!-- PV1-18: Patient Type — mapeado para AdmissionType.Code
       Valores esperados: PRE (Aguardando), SURG (Em Cirurgia), REC (Pós-Op) -->
  <assign value="source.GetValueAt(&quot;PV1:18&quot;)"
          property="target.Encounters.(1).AdmissionType.Code"
          action="set"/>

  <!-- PV1-3.1: localização/unidade -->
  <assign value="source.GetValueAt(&quot;PV1:3.1&quot;)"
          property="target.Encounters.(1).EnteredAt.Code"
          action="set"/>

  <!-- PV1-44/45: horários de admissão e alta -->
  <assign value="source.GetValueAt(&quot;PV1:44&quot;)"
          property="target.Encounters.(1).StartTime"
          action="set"/>
  <assign value="source.GetValueAt(&quot;PV1:45&quot;)"
          property="target.Encounters.(1).EndTime"
          action="set"/>

  <!-- PV1-7: médico responsável -->
  <assign value="source.GetValueAt(&quot;PV1:7.1&quot;)"
          property="target.Encounters.(1).AttendingClinicians.(1).Code"
          action="set"/>
  <assign value="source.GetValueAt(&quot;PV1:7.2&quot;)"
          property="target.Encounters.(1).AttendingClinicians.(1).Description"
          action="set"/>

  <!-- ══ PROCEDURE — apenas para ORM^O01 ═════════════════ -->
  <if condition='source.GetValueAt("MSH:9.2") = "O01"'>
    <true>
      <!-- ORC-2: identificador do pedido -->
      <assign value="source.GetValueAt(&quot;ORC:2&quot;)"
              property="target.Procedures.(1).ExternalId"
              action="set"/>

      <!-- OBR-4: código e descrição do procedimento -->
      <assign value="source.GetValueAt(&quot;OBR:4.1&quot;)"
              property="target.Procedures.(1).Procedure.Code"
              action="set"/>
      <assign value="source.GetValueAt(&quot;OBR:4.2&quot;)"
              property="target.Procedures.(1).Procedure.Description"
              action="set"/>

      <!-- OBR-36: horário planejado do procedimento -->
      <assign value="source.GetValueAt(&quot;OBR:36&quot;)"
              property="target.Procedures.(1).ProcedureTime"
              action="set"/>
    </true>
  </if>

</transform>
```

### Ação MCP para HL7ToSDA3
```
iris_doc(
  action="write",
  name="CardioFlow.DTL.HL7ToSDA3.dtl",
  content=<xml acima>,
  namespace="CARDIOFLOW"
)
iris_compile(documents="CardioFlow.DTL.HL7ToSDA3.dtl", namespace="CARDIOFLOW")
# Gera CardioFlow.DTL.HL7ToSDA3.cls automaticamente
```

---

## Bloco 7: DTL — FHIR R4 para SDA3

### `CardioFlow.DTL.FHIRToSDA3.dtl` — documento DTL nativo

A DTL FHIR usa um bloco `<code>` porque o parsing de JSON dinâmico exige ObjectScript imperativo — não há elementos DTL declarativos para iterar arrays JSON. Isso é o padrão correto para transformações complexas no IRIS.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<transform sourceClass="CardioFlow.Msg.FHIRRequest"
           targetClass="HS.SDA3.Container"
           create="new"
           language="objectscript"
           ignoreMissing="1"
           reportErrors="1"
           xmlns="http://www.intersystems.com/dtl">

  <!-- Parsing imperativo do Bundle FHIR R4 via bloco <code>
       Necessário porque JSON arrays não têm mapeamento DTL declarativo -->
  <code>
    <![CDATA[
      // Deserializar JSON do stream de payload
      set fhirJson = {}
      do fhirJson.%FromJSON(source.Payload)

      // Iterar sobre todas as entries do Bundle
      set entries = fhirJson.entry
      if '$isobject(entries) { quit }

      set iter = entries.%GetIterator()
      while iter.%GetNext(.idx, .entry) {
          set resource = entry.resource
          if '$isobject(resource) { continue }
          set resourceType = resource.resourceType

          // ── Patient ──────────────────────────────────────
          if resourceType = "Patient" {
              set target.Patient.PatientNumbers.(1).Number = resource.id

              set nameArr = resource.name
              if $isobject(nameArr) {
                  set nameObj = nameArr.%Get(0)
                  if $isobject(nameObj) {
                      set target.Patient.Name.FamilyName = nameObj.family
                      set givenArr = nameObj.given
                      if $isobject(givenArr) {
                          set target.Patient.Name.GivenName = givenArr.%Get(0)
                      }
                  }
              }
              set target.Patient.BirthTime = resource.birthDate
              set target.Patient.Gender.Code = resource.gender
          }

          // ── Encounter ────────────────────────────────────
          // Mapeamento de status FHIR → código interno SDA3
          // planned      → PRE   (Aguardando Cirurgia)
          // in-progress  → SURG  (Em Cirurgia)
          // finished     → REC   (Pós-Cirúrgico)
          if resourceType = "Encounter" {
              set fhirStatus = resource.status
              set code = $case(fhirStatus,
                  "planned":     "PRE",
                  "in-progress": "SURG",
                  "finished":    "REC",
                  :              "PRE")    // default seguro
              set target.Encounters.(1).AdmissionType.Code = code

              set period = resource.period
              if $isobject(period) {
                  set target.Encounters.(1).StartTime = period.start
                  set target.Encounters.(1).EndTime   = period.end
              }
          }

          // ── Procedure ────────────────────────────────────
          if resourceType = "Procedure" {
              set target.Procedures.(1).ExternalId = resource.id

              set codeObj = resource.code
              if $isobject(codeObj) {
                  set codingArr = codeObj.coding
                  if $isobject(codingArr) {
                      set coding = codingArr.%Get(0)
                      if $isobject(coding) {
                          set target.Procedures.(1).Procedure.Code        = coding.code
                          set target.Procedures.(1).Procedure.Description = coding.display
                      }
                  }
              }
              set target.Procedures.(1).ProcedureTime = resource.performedDateTime
          }
      }
    ]]>
  </code>

</transform>
```

### Ação MCP para FHIRToSDA3
```
iris_doc(
  action="write",
  name="CardioFlow.DTL.FHIRToSDA3.dtl",
  content=<xml acima>,
  namespace="CARDIOFLOW"
)
iris_compile(documents="CardioFlow.DTL.FHIRToSDA3.dtl", namespace="CARDIOFLOW")
```

### Estrutura Git para BPL e DTL

```
src/CardioFlow/
├── BP/
│   └── CardioOrchestrator.bpl   ← commitar (fonte)
└── DTL/
    ├── HL7ToSDA3.dtl             ← commitar (fonte)
    └── FHIRToSDA3.dtl            ← commitar (fonte)
```

Adicionar ao `.gitignore` para não commitar os `.cls` gerados:
```gitignore
# Gerados automaticamente pela compilação BPL/DTL — não editar nem commitar
src/CardioFlow/BP/*.cls
src/CardioFlow/DTL/*.cls
```

---

## Sequência de Compilação Obrigatória

Execute nesta ordem via MCP — dependências primeiro. Note os tipos de documento corretos:

```
# 1. Mensagens (.cls — ObjectScript puro, sem dependências)
iris_compile(documents="CardioFlow.Msg.*.cls", namespace="CARDIOFLOW")

# 2. DTLs (.dtl — documentos nativos, geram .cls automaticamente)
iris_compile(documents="CardioFlow.DTL.HL7ToSDA3.dtl", namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.DTL.FHIRToSDA3.dtl", namespace="CARDIOFLOW")

# 3. Analytics (.cls — para SDAPersist referenciar)
iris_compile(documents="CardioFlow.Analytics.*.cls", namespace="CARDIOFLOW")

# 4. Business Services e Operations (.cls)
iris_compile(documents="CardioFlow.BS.*.cls", namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.BO.*.cls", namespace="CARDIOFLOW")

# 5. Business Process (.bpl — documento nativo, gera .cls automaticamente)
iris_compile(documents="CardioFlow.BP.CardioOrchestrator.bpl", namespace="CARDIOFLOW")

# 6. Production (.cls — por último, referencia todos os itens acima)
iris_compile(documents="CardioFlow.Production.cls", namespace="CARDIOFLOW")

# 7. Verificação final — compilar TUDO (inclui .bpl e .dtl)
# O wildcard *.cls não pega .bpl e .dtl — listar explicitamente:
iris_compile(documents="CardioFlow.Msg.*.cls", namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.DTL.HL7ToSDA3.dtl", namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.DTL.FHIRToSDA3.dtl", namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.Analytics.*.cls", namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.BS.*.cls", namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.BO.*.cls", namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.BP.CardioOrchestrator.bpl", namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.Production.cls", namespace="CARDIOFLOW")
```

> **Atenção**: `iris_compile(documents="CardioFlow.*.cls")` não compila `.bpl` nem `.dtl`. Sempre especificar esses documentos pelo nome completo com a extensão correta.

---

## Validação Pós-Build

```
# Iniciar produção
iris_production(action="start", production="CardioFlow.Production", namespace="CARDIOFLOW")

# Verificar status
iris_production(action="check", production="CardioFlow.Production", namespace="CARDIOFLOW")

# Injetar mensagem HL7 de teste
iris_execute(
  namespace="CARDIOFLOW",
  code='
    set hl7 = ##class(EnsLib.HL7.Message).ImportFromFile("/home/irisowner/data/sample_hl7.txt")
    set sc = ##class(Ens.Director).CreateBusinessService("BS_HL7_Inbound", .svc)
    set sc = svc.ProcessInput(hl7, .resp)
    write $system.Status.GetErrorText(sc)
  '
)

# Verificar mensagens processadas
iris_interop_query(
  target="messages",
  production="CardioFlow.Production",
  namespace="CARDIOFLOW"
)
```
