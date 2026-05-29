# Skill: agent-data (Data & Analytics Specialist)
## SQL · Columnar Storage · IRIS BI · REST API · Dashboards

---

## Identidade do Agente
Você é o **Data & Analytics Specialist** do IRIS-CardioFlow. Sua responsabilidade é: modelar tabelas de status cirúrgico com Columnar Storage (IRIS 2026), criar os três cubos analíticos do IRIS BI, e expor os dados via endpoints REST autenticados.

**Pré-requisito**: Este agente só age após o `agent-builder` ter completado a geração das classes de interoperabilidade e persistência SDA3.

---

## Bloco 1: Tabela de Status Cirúrgico (Columnar Storage)

### `CardioFlow.Analytics.SurgeryStatus.cls`

```objectscript
/// CardioFlow.Analytics.SurgeryStatus
/// Tabela de tracking de status cirúrgico otimizada com Columnar Storage (IRIS 2026)
/// Utilizada como base para os cubos de analytics e REST API
Class CardioFlow.Analytics.SurgeryStatus Extends %Persistent
{

/// ID do paciente no IRIS
Property PatientId As %String(MAXLEN=64) [ Required ];

/// Status cirúrgico: AWAITING | IN_SURGERY | POST_OP
Property Status As %String(MAXLEN=32, VALUELIST=",AWAITING,IN_SURGERY,POST_OP") [ Required ];

/// Origem da mensagem: HL7 | FHIR
Property Source As %String(MAXLEN=16);

/// Timestamp do evento (formato IRIS $ztimestamp)
Property EventTime As %TimeStamp;

/// Nome do paciente (desnormalizado para query rápida)
Property PatientName As %String(MAXLEN=256);

/// Hospital/unidade de origem
Property HospitalCode As %String(MAXLEN=64);

/// Tempo de espera em minutos (calculado para PRE-OP)
Property WaitingMinutes As %Integer;

/// Sala cirúrgica alocada
Property SurgeryRoom As %String(MAXLEN=32);

/// Equipe médica (JSON serializado)
Property MedicalTeam As %String(MAXLEN=512);

/// Alertas de sinais vitais pós-op (JSON)
Property VitalSignAlerts As %String(MAXLEN=1024);

// ---- Índices ----
Index StatusIdx On Status;
Index PatientIdx On PatientId;
Index EventTimeIdx On EventTime;

// ---- Columnar Index (IRIS 2026) ----
// Habilita agregação em milissegundos para os cubos de analytics
Index ColumnarIdx On (Status, EventTime, WaitingMinutes, HospitalCode) [ Type = columnar ];

// ---- SQL Mapping ----
Storage Default
{
<Data name="SurgeryStatusDefaultData">
<Value name="1"><Value>PatientId</Value></Value>
<Value name="2"><Value>Status</Value></Value>
<Value name="3"><Value>Source</Value></Value>
<Value name="4"><Value>EventTime</Value></Value>
<Value name="5"><Value>PatientName</Value></Value>
<Value name="6"><Value>HospitalCode</Value></Value>
<Value name="7"><Value>WaitingMinutes</Value></Value>
<Value name="8"><Value>SurgeryRoom</Value></Value>
<Value name="9"><Value>MedicalTeam</Value></Value>
<Value name="10"><Value>VitalSignAlerts</Value></Value>
</Data>
<DataLocation>^CardioFlow.Analytics.SurgeryStatusD</DataLocation>
<DefaultData>SurgeryStatusDefaultData</DefaultData>
<IdLocation>^CardioFlow.Analytics.SurgeryStatusD</IdLocation>
<IndexLocation>^CardioFlow.Analytics.SurgeryStatusI</IndexLocation>
<Type>%Storage.Persistent</Type>
</Storage>

}
```

### Ação MCP
```
iris_doc(action="write", name="CardioFlow.Analytics.SurgeryStatus.cls", content=..., namespace="CARDIOFLOW")
iris_compile(documents="CardioFlow.Analytics.SurgeryStatus.cls", namespace="CARDIOFLOW")

# Verificar que a tabela foi criada
iris_query(sql="SELECT TOP 1 * FROM CardioFlow_Analytics.SurgeryStatus", namespace="CARDIOFLOW")
```

---

## Bloco 2: Views SQL para os Três Painéis

### Criar as views via `iris_execute`

```objectscript
// Executar via iris_execute(code=..., namespace="CARDIOFLOW")

// View 1: Painel Pré-Op (fila de espera)
do ##class(%SQL.Manager.API).ExecDirect(,
    "CREATE OR REPLACE VIEW CardioFlow_Analytics.vPreOpPanel AS "_
    "SELECT PatientId, PatientName, HospitalCode, EventTime, "_
    "       WaitingMinutes, Source "_
    "FROM CardioFlow_Analytics.SurgeryStatus "_
    "WHERE Status = 'AWAITING' "_
    "ORDER BY WaitingMinutes DESC"
)

// View 2: Painel Intra-Op (cirurgias em andamento)
do ##class(%SQL.Manager.API).ExecDirect(,
    "CREATE OR REPLACE VIEW CardioFlow_Analytics.vIntraOpPanel AS "_
    "SELECT PatientId, PatientName, HospitalCode, EventTime, "_
    "       SurgeryRoom, MedicalTeam, Source "_
    "FROM CardioFlow_Analytics.SurgeryStatus "_
    "WHERE Status = 'IN_SURGERY' "_
    "ORDER BY EventTime ASC"
)

// View 3: Painel Pós-Op (recuperação)
do ##class(%SQL.Manager.API).ExecDirect(,
    "CREATE OR REPLACE VIEW CardioFlow_Analytics.vPostOpPanel AS "_
    "SELECT PatientId, PatientName, HospitalCode, EventTime, "_
    "       VitalSignAlerts, Source "_
    "FROM CardioFlow_Analytics.SurgeryStatus "_
    "WHERE Status = 'POST_OP' "_
    "ORDER BY EventTime DESC"
)
```

---

## Bloco 3: Cubos IRIS BI

### `CardioFlow.Analytics.PreOpCube.cls`
```objectscript
/// CardioFlow.Analytics.PreOpCube
/// Cubo analítico — Painel Pré-Operatório
Class CardioFlow.Analytics.PreOpCube Extends %DeepSee.Subject
{

Parameter DOMAIN = "CARDIOFLOW";
Parameter SUBJECTAREA = "CardioFlow/PreOp";
Parameter DSTIME = "AUTO";

XData Cube [ XMLNamespace = "http://www.intersystems.com/deepsee" ]
{
<cube name="PreOpCube" displayName="Painel Pré-Operatório"
      sourceClass="CardioFlow.Analytics.SurgeryStatus"
      sourceProperty=""
      nullReplacement="N/A"
      countMeasureName="Contagem">

  <measure name="Tempo de Espera" displayName="Tempo de Espera (min)"
           sourceProperty="WaitingMinutes" type="number" aggregate="AVG"/>
  
  <dimension name="Hospital" displayName="Hospital" hasAll="true">
    <hierarchy name="H1">
      <level name="Hospital" sourceProperty="HospitalCode" displayName="Hospital"/>
    </hierarchy>
  </dimension>

  <dimension name="Status" displayName="Status" hasAll="true">
    <hierarchy name="H1">
      <level name="Status" sourceProperty="Status" displayName="Status"/>
    </hierarchy>
  </dimension>

  <dimension name="Data" displayName="Data do Evento" type="time" hasAll="true">
    <hierarchy name="H1">
      <level name="Ano" sourceProperty="EventTime" timeFunction="Year"/>
      <level name="Mês" sourceProperty="EventTime" timeFunction="MonthYear"/>
      <level name="Dia" sourceProperty="EventTime" timeFunction="DayMonthYear"/>
    </hierarchy>
  </dimension>

  <filter name="Apenas Aguardando" sourceProperty="Status" value="AWAITING"/>

</cube>
}

}
```

### `CardioFlow.Analytics.IntraOpCube.cls`
```objectscript
/// CardioFlow.Analytics.IntraOpCube
/// Cubo analítico — Painel Intra-Operatório
Class CardioFlow.Analytics.IntraOpCube Extends %DeepSee.Subject
{

Parameter DOMAIN = "CARDIOFLOW";

XData Cube [ XMLNamespace = "http://www.intersystems.com/deepsee" ]
{
<cube name="IntraOpCube" displayName="Painel Intra-Operatório"
      sourceClass="CardioFlow.Analytics.SurgeryStatus"
      countMeasureName="Cirurgias em Andamento">

  <dimension name="Sala" displayName="Sala Cirúrgica" hasAll="true">
    <hierarchy name="H1">
      <level name="Sala" sourceProperty="SurgeryRoom" displayName="Sala"/>
    </hierarchy>
  </dimension>

  <dimension name="Hospital" displayName="Hospital" hasAll="true">
    <hierarchy name="H1">
      <level name="Hospital" sourceProperty="HospitalCode" displayName="Hospital"/>
    </hierarchy>
  </dimension>

  <filter name="Apenas Em Cirurgia" sourceProperty="Status" value="IN_SURGERY"/>

</cube>
}

}
```

### `CardioFlow.Analytics.PostOpCube.cls`
```objectscript
/// CardioFlow.Analytics.PostOpCube
/// Cubo analítico — Painel Pós-Operatório
Class CardioFlow.Analytics.PostOpCube Extends %DeepSee.Subject
{

Parameter DOMAIN = "CARDIOFLOW";

XData Cube [ XMLNamespace = "http://www.intersystems.com/deepsee" ]
{
<cube name="PostOpCube" displayName="Painel Pós-Operatório"
      sourceClass="CardioFlow.Analytics.SurgeryStatus"
      countMeasureName="Pacientes em Recuperação">

  <dimension name="Hospital" displayName="Hospital" hasAll="true">
    <hierarchy name="H1">
      <level name="Hospital" sourceProperty="HospitalCode" displayName="Hospital"/>
    </hierarchy>
  </dimension>

  <filter name="Apenas Pós-Op" sourceProperty="Status" value="POST_OP"/>

</cube>
}

}
```

### Build dos Cubos via MCP
```
# Compilar cubos
iris_compile(documents="CardioFlow.Analytics.*.cls", namespace="CARDIOFLOW")

# Sincronizar cubos com o IRIS BI engine
iris_execute(
  namespace="CARDIOFLOW",
  code='
    set sc = ##class(%DeepSee.Utils).%SynchronizeCube("PreOpCube")
    set sc = ##class(%DeepSee.Utils).%SynchronizeCube("IntraOpCube")
    set sc = ##class(%DeepSee.Utils).%SynchronizeCube("PostOpCube")
    write "Cubos sincronizados com sucesso",!
  '
)
```

---

## Bloco 4: REST API — DashboardDispatch

### `CardioFlow.API.DashboardDispatch.cls`
```objectscript
/// CardioFlow.API.DashboardDispatch
/// Despachante REST para endpoints /api/cardio/dashboards/...
Class CardioFlow.API.DashboardDispatch Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";
Parameter CHARSET = "utf-8";
Parameter HandleCorsRequest = 1;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
  <Route Url="/dashboards/preop"    Method="GET" Call="GetPreOp"   Cors="true"/>
  <Route Url="/dashboards/intraop"  Method="GET" Call="GetIntraOp" Cors="true"/>
  <Route Url="/dashboards/postop"   Method="GET" Call="GetPostOp"  Cors="true"/>
  <Route Url="/dashboards/summary"  Method="GET" Call="GetSummary" Cors="true"/>
  <Route Url="/patient/:id/status"  Method="GET" Call="GetPatient" Cors="true"/>
  <Route Url="/health"              Method="GET" Call="Health"     Cors="true"/>
</Routes>
}

/// GET /api/cardio/dashboards/preop
/// Retorna fila de espera pré-operatória
ClassMethod GetPreOp() As %Status
{
    set sc = $$$OK
    try {
        set rs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT PatientId, PatientName, HospitalCode, EventTime, WaitingMinutes "_
            "FROM CardioFlow_Analytics.vPreOpPanel"
        )
        set result = ..BuildJSONFromRS(rs, "preOp")
        write result.%ToJSON()
    } catch ex {
        set sc = ex.AsStatus()
        do ..ReportHttpStatusCode(500, $system.Status.GetErrorText(sc))
    }
    quit sc
}

/// GET /api/cardio/dashboards/intraop
ClassMethod GetIntraOp() As %Status
{
    set sc = $$$OK
    try {
        set rs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT PatientId, PatientName, HospitalCode, EventTime, SurgeryRoom, MedicalTeam "_
            "FROM CardioFlow_Analytics.vIntraOpPanel"
        )
        set result = ..BuildJSONFromRS(rs, "intraOp")
        write result.%ToJSON()
    } catch ex {
        set sc = ex.AsStatus()
        do ..ReportHttpStatusCode(500, $system.Status.GetErrorText(sc))
    }
    quit sc
}

/// GET /api/cardio/dashboards/postop
ClassMethod GetPostOp() As %Status
{
    set sc = $$$OK
    try {
        set rs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT PatientId, PatientName, HospitalCode, EventTime, VitalSignAlerts "_
            "FROM CardioFlow_Analytics.vPostOpPanel"
        )
        set result = ..BuildJSONFromRS(rs, "postOp")
        write result.%ToJSON()
    } catch ex {
        set sc = ex.AsStatus()
        do ..ReportHttpStatusCode(500, $system.Status.GetErrorText(sc))
    }
    quit sc
}

/// GET /api/cardio/dashboards/summary — contagens por status
ClassMethod GetSummary() As %Status
{
    set sc = $$$OK
    try {
        set rs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT Status, COUNT(*) AS Total "_
            "FROM CardioFlow_Analytics.SurgeryStatus "_
            "GROUP BY Status"
        )
        set result = {"summary": []}
        while rs.%Next() {
            do result.summary.%Push({
                "status": (rs.%Get("Status")),
                "total": (rs.%Get("Total"))
            })
        }
        write result.%ToJSON()
    } catch ex {
        set sc = ex.AsStatus()
        do ..ReportHttpStatusCode(500, $system.Status.GetErrorText(sc))
    }
    quit sc
}

/// GET /api/cardio/patient/:id/status
ClassMethod GetPatient(id As %String) As %Status
{
    set sc = $$$OK
    try {
        set rs = ##class(%SQL.Statement).%ExecDirect(,
            "SELECT TOP 1 PatientId, PatientName, Status, EventTime, HospitalCode "_
            "FROM CardioFlow_Analytics.SurgeryStatus "_
            "WHERE PatientId = ? "_
            "ORDER BY EventTime DESC",
            id
        )
        if rs.%Next() {
            set result = {
                "patientId": (rs.%Get("PatientId")),
                "patientName": (rs.%Get("PatientName")),
                "status": (rs.%Get("Status")),
                "eventTime": (rs.%Get("EventTime")),
                "hospitalCode": (rs.%Get("HospitalCode"))
            }
            write result.%ToJSON()
        } else {
            do ..ReportHttpStatusCode(404, "Paciente não encontrado")
        }
    } catch ex {
        set sc = ex.AsStatus()
        do ..ReportHttpStatusCode(500, $system.Status.GetErrorText(sc))
    }
    quit sc
}

/// GET /api/cardio/health
ClassMethod Health() As %Status
{
    write {"status": "ok", "namespace": ($namespace), "time": ($zdt($h, 3))}.%ToJSON()
    quit $$$OK
}

/// Helper: transforma ResultSet em JSON array
ClassMethod BuildJSONFromRS(rs As %SQL.StatementResult, key As %String) As %DynamicObject [ Private ]
{
    set result = {}
    set arr = []
    do result.%Set(key, arr)
    while rs.%Next() {
        set row = {}
        set colCount = rs.%ResultColumnCount
        for i = 1:1:colCount {
            set colName = rs.%Metadata.columns.GetAt(i).colName
            do row.%Set(colName, rs.%GetData(i))
        }
        do arr.%Push(row)
    }
    quit result
}

}
```

---

## Validação dos Endpoints REST

```
# Testar via iris_execute (simula HTTP GET interno)
iris_execute(
  namespace="CARDIOFLOW",
  code='
    set req = ##class(%Net.HttpRequest).%New()
    set req.Server = "localhost"
    set req.Port = 52773
    set req.Username = "_SYSTEM"
    set req.Password = "SYS"
    set sc = req.Get("/api/cardio/health")
    write req.HttpResponse.Data.Read()
  '
)

# Testar queries diretamente
iris_query(sql="SELECT Status, COUNT(*) AS Total FROM CardioFlow_Analytics.SurgeryStatus GROUP BY Status", namespace="CARDIOFLOW")

# Testar view pré-op
iris_query(sql="SELECT TOP 5 * FROM CardioFlow_Analytics.vPreOpPanel", namespace="CARDIOFLOW")
```
