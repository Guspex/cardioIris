# CLAUDE CODE — Implementation Plan for cardioIris Contest Compliance

> **Contest deadline:** June 7, 2026 (23:59 EST)  
> **Repo:** https://github.com/Guspex/cardioIris  
> **Goal:** Transform cardioIris into a compliant submission for the InterSystems AI Agent + FHIR Interoperability Contest

---

## Context

cardioIris is a cardiovascular surgical flow monitoring dashboard running on InterSystems IRIS. It currently has:
- A custom REST API in ObjectScript (`DashboardDispatch.cls`)
- A persistent data model (`SurgeryStatus.cls`)
- A simulation seeder (`Runner.cls`)
- A browser dashboard (`dashboard/index.html`)
- Docker + PowerShell bootstrap

**What it is missing (contest requirements):**
1. An **AI Agent** with reasoning capability
2. **FHIR-native data** (Patient, Procedure, Observation, Condition resources)
3. An **IRIS Interoperability Production** (Business Process / Business Operation)
4. A **video demo**
5. **IPM package** (open to adding)
6. **GitHub topics** and **Open Exchange** listing

---

## Architecture to Build

```
Browser Dashboard
      │
      ▼
Python Proxy (existing, port 8787)
      │
      ├──► IRIS REST API (existing DashboardDispatch)
      │         └── SurgeryStatus (persistent, FHIR-mapped)
      │
      └──► AI Agent endpoint  ◄── NEW
                │
                ▼
         IRIS Production  ◄── NEW
           ├── Business Service (REST inbound)
           ├── Business Process (orchestration)
           │       └── calls Python AI Agent via EmbeddedPython
           └── Business Operation (FHIR outbound to IRIS FHIR Server)
                       └── Stores/Reads FHIR R4 resources
```

---

## Step-by-Step Implementation

---

### STEP 1 — Enable IRIS FHIR Server (Namespace: CARDIOFLOW)

**File to create:** `bin/setup-fhir.ps1`

```powershell
# Runs inside IRIS to enable FHIR endpoint
docker exec cardioflow-iris iris session IRIS -U CARDIOFLOW "##class(CardioFlow.Setup.FHIRSetup).Enable()"
```

**File to create:** `src/CardioFlow/Setup/FHIRSetup.cls`

```objectscript
Class CardioFlow.Setup.FHIRSetup
{

ClassMethod Enable() As %Status
{
    // Install FHIR endpoint at /fhir/r4
    Set sc = ##class(HS.FHIRServer.Installer).InstallInstance(
        "/fhir/r4",
        "HS.FHIRServer.Storage.Json.InteractionsStrategy",
        ""
    )
    Return sc
}

}
```

**Goal:** Have a local FHIR R4 server at `http://localhost:52773/fhir/r4`

---

### STEP 2 — FHIR Data Mapper

Map existing `SurgeryStatus` persistent data to FHIR R4 resources.

**File to create:** `src/CardioFlow/FHIR/ResourceBuilder.cls`

This class must produce:
- `Patient` resource — from `patientName`, `patientId`
- `Procedure` resource — status `in-progress` / `completed` / `preparation`, code SNOMED `81266008` (Heart surgery)
- `Observation` resource — surgical phase, hospital code, scenario tag
- `Condition` resource — cardiovascular condition

```objectscript
Class CardioFlow.FHIR.ResourceBuilder
{

/// Builds a FHIR Patient resource from a SurgeryStatus record
ClassMethod BuildPatient(pRecord As CardioFlow.Analytics.SurgeryStatus) As %DynamicObject
{
    Set patient = {
        "resourceType": "Patient",
        "id": (pRecord.PatientId),
        "name": [{
            "use": "official",
            "text": (pRecord.PatientName)
        }],
        "meta": {
            "tag": [{
                "system": "http://cardioiris.local/tags",
                "code": (pRecord.HospitalCode)
            }]
        }
    }
    Return patient
}

/// Builds a FHIR Procedure resource from a SurgeryStatus record
ClassMethod BuildProcedure(pRecord As CardioFlow.Analytics.SurgeryStatus) As %DynamicObject
{
    // Map internal status to FHIR Procedure status
    Set fhirStatus = $Case(pRecord.Status,
        "IN_SURGERY": "in-progress",
        "POST_OP": "completed",
        : "preparation"
    )

    Set procedure = {
        "resourceType": "Procedure",
        "id": ("proc-" _ pRecord.PatientId),
        "status": (fhirStatus),
        "subject": {
            "reference": ("Patient/" _ pRecord.PatientId)
        },
        "code": {
            "coding": [{
                "system": "http://snomed.info/sct",
                "code": "81266008",
                "display": "Heart surgery"
            }]
        },
        "note": [{
            "text": (pRecord.ScenarioTag)
        }]
    }
    Return procedure
}

/// Builds a FHIR Observation resource for surgical phase
ClassMethod BuildObservation(pRecord As CardioFlow.Analytics.SurgeryStatus) As %DynamicObject
{
    Set obs = {
        "resourceType": "Observation",
        "id": ("obs-" _ pRecord.PatientId),
        "status": "final",
        "subject": {
            "reference": ("Patient/" _ pRecord.PatientId)
        },
        "code": {
            "coding": [{
                "system": "http://loinc.org",
                "code": "8716-3",
                "display": "Vital signs"
            }]
        },
        "valueString": (pRecord.Status),
        "component": [{
            "code": { "text": "Hospital" },
            "valueString": (pRecord.HospitalCode)
        }, {
            "code": { "text": "ScenarioTag" },
            "valueString": (pRecord.ScenarioTag)
        }]
    }
    Return obs
}

/// Pushes all resources for one patient into the FHIR server
ClassMethod SyncToFHIR(pPatientId As %String) As %Status
{
    Set record = ##class(CardioFlow.Analytics.SurgeryStatus).PatientIdIndex
    // ... query by PatientId and POST each resource to /fhir/r4
    // Use %Net.HttpRequest to POST JSON to http://localhost:52773/fhir/r4/Patient etc.
    Return $$$OK
}

}
```

---

### STEP 3 — AI Agent (Python, EmbeddedPython)

**File to create:** `src/CardioFlow/AI/Agent.py`

This is the core AI agent. It receives a FHIR Bundle (set of Patient + Procedure + Observation resources for one patient) and returns a structured clinical recommendation.

```python
# CardioFlow AI Agent
# Called by IRIS via EmbeddedPython or HTTP subprocess

import json
import urllib.request
import urllib.error

ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_API_KEY = ""  # Set via environment variable ANTHROPIC_API_KEY or IRIS config

SYSTEM_PROMPT = """
You are a cardiovascular surgical flow AI agent embedded in an IRIS interoperability pipeline.

You receive a FHIR Bundle containing Patient, Procedure, and Observation resources 
for one patient. Your job is to:

1. Identify the patient's current surgical phase (AWAITING, IN_SURGERY, POST_OP)
2. Detect risk signals from scenario tags (EMERGENCY_ESCALATION, DELAYED_SURGERY, RECOVERY_ESCALATION)
3. Return a structured JSON recommendation with:
   - riskLevel: LOW | MEDIUM | HIGH | CRITICAL
   - recommendation: one clear action sentence
   - reasoning: brief clinical rationale (2-3 sentences)
   - suggestedNextStatus: the next expected phase
   - escalate: true/false

Respond ONLY with valid JSON. No markdown, no explanation outside the JSON object.
"""


def analyze_patient_bundle(fhir_bundle: dict, api_key: str) -> dict:
    """
    Sends a FHIR bundle to Claude and returns structured agent output.
    """
    user_message = f"Analyze this FHIR Bundle and return your assessment:\n\n{json.dumps(fhir_bundle, indent=2)}"

    payload = {
        "model": "claude-sonnet-4-20250514",
        "max_tokens": 1024,
        "system": SYSTEM_PROMPT,
        "messages": [
            {"role": "user", "content": user_message}
        ]
    }

    req = urllib.request.Request(
        ANTHROPIC_API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01"
        },
        method="POST"
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        response_data = json.loads(resp.read().decode("utf-8"))

    raw_text = response_data["content"][0]["text"]
    return json.loads(raw_text)


def run_agent(patient_id: str, iris_api_base: str, api_key: str) -> dict:
    """
    Fetches FHIR resources for a patient from IRIS FHIR server,
    builds a bundle, and calls the AI agent.
    """
    resources = []
    for resource_type in ["Patient", "Procedure", "Observation"]:
        url = f"{iris_api_base}/fhir/r4/{resource_type}?patient={patient_id}"
        try:
            req = urllib.request.Request(url, headers={"Accept": "application/fhir+json"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if data.get("entry"):
                    resources.extend([e["resource"] for e in data["entry"]])
        except urllib.error.URLError:
            pass

    bundle = {
        "resourceType": "Bundle",
        "type": "collection",
        "entry": [{"resource": r} for r in resources]
    }

    return analyze_patient_bundle(bundle, api_key)


if __name__ == "__main__":
    import sys
    import os

    patient_id = sys.argv[1] if len(sys.argv) > 1 else "FHIR-TEST-001"
    iris_base = sys.argv[2] if len(sys.argv) > 2 else "http://localhost:52773"
    key = os.environ.get("ANTHROPIC_API_KEY", "")

    result = run_agent(patient_id, iris_base, key)
    print(json.dumps(result, indent=2))
```

---

### STEP 4 — IRIS Interoperability Production

Create a minimal but real IRIS Production that:
- Receives a REST request asking for AI analysis of a patient
- Calls the Python agent
- Returns the result

**File to create:** `src/CardioFlow/Interop/Production.cls`

```objectscript
Class CardioFlow.Interop.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="CardioFlow.Interop.Production" LogGeneralTraceEvents="false">
  <Description>CardioFlow AI Agent Production for FHIR interoperability</Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="CardioFlow.Interop.AgentService" Category="" ClassName="CardioFlow.Interop.AgentService" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="CardioFlow.Interop.AgentProcess" Category="" ClassName="CardioFlow.Interop.AgentProcess" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="CardioFlow.Interop.FHIROperation" Category="" ClassName="CardioFlow.Interop.FHIROperation" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
</Production>
}

}
```

**File to create:** `src/CardioFlow/Interop/AgentRequest.cls`

```objectscript
Class CardioFlow.Interop.AgentRequest Extends Ens.Request
{

Property PatientId As %String;
Property IRISBase As %String [ InitialExpression = "http://localhost:52773" ];

}
```

**File to create:** `src/CardioFlow/Interop/AgentResponse.cls`

```objectscript
Class CardioFlow.Interop.AgentResponse Extends Ens.Response
{

Property RiskLevel As %String;
Property Recommendation As %String;
Property Reasoning As %String;
Property SuggestedNextStatus As %String;
Property Escalate As %Boolean;
Property RawJSON As %String(MAXLEN = 4096);

}
```

**File to create:** `src/CardioFlow/Interop/AgentProcess.cls`

```objectscript
Class CardioFlow.Interop.AgentProcess Extends Ens.BusinessProcess [ ClassType = persistent ]
{

Method OnRequest(pRequest As CardioFlow.Interop.AgentRequest, Output pResponse As CardioFlow.Interop.AgentResponse) As %Status
{
    Set pResponse = ##class(CardioFlow.Interop.AgentResponse).%New()

    // Call Python AI Agent via EmbeddedPython
    Set pyResult = ..CallPythonAgent(pRequest.PatientId, pRequest.IRISBase)

    Set pResponse.RiskLevel         = $Get(pyResult("riskLevel"), "UNKNOWN")
    Set pResponse.Recommendation    = $Get(pyResult("recommendation"), "")
    Set pResponse.Reasoning         = $Get(pyResult("reasoning"), "")
    Set pResponse.SuggestedNextStatus = $Get(pyResult("suggestedNextStatus"), "")
    Set pResponse.Escalate          = $Get(pyResult("escalate"), 0)
    Set pResponse.RawJSON           = {}.%ToJSON()

    Return $$$OK
}

Method CallPythonAgent(pPatientId As %String, pIRISBase As %String) As %String [ Language = python ]
{
    import sys, os, json
    sys.path.insert(0, '/home/irisowner/cardioflow')

    from CardioFlow.AI.Agent import run_agent

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    result = run_agent(pPatientId, pIRISBase, api_key)
    return result
}

}
```

**File to create:** `src/CardioFlow/Interop/FHIROperation.cls`

```objectscript
/// Business Operation that writes FHIR resources back to the IRIS FHIR Server
Class CardioFlow.Interop.FHIROperation Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

Parameter INVOCATION = "Queue";

Method PostFHIRResource(pRequest As Ens.StringRequest, Output pResponse As Ens.StringResponse) As %Status
{
    // POST FHIR resource JSON to /fhir/r4/{resourceType}
    Set sc = ..Adapter.Post(.httpResponse, "/fhir/r4/Patient", pRequest.StringValue)
    Return sc
}

}
```

---

### STEP 5 — New AI Agent REST Endpoint

Extend `DashboardDispatch.cls` to expose an `/ai/analyze/{patientId}` route that triggers the Production.

**Add to `src/CardioFlow/API/DashboardDispatch.cls`:**

```objectscript
/// Route map addition
<Route Url="/ai/analyze/:patientId" Method="GET" Call="AnalyzePatient"/>

/// New method
ClassMethod AnalyzePatient(pPatientId As %String) As %Status
{
    Set request = ##class(CardioFlow.Interop.AgentRequest).%New()
    Set request.PatientId = pPatientId

    // Send to production synchronously
    Set sc = ##class(Ens.Director).CreateBusinessService("CardioFlow.Interop.AgentService", .service)
    // Alternatively: direct process call for demo simplicity
    Set process = ##class(CardioFlow.Interop.AgentProcess).%New()
    Set sc = process.OnRequest(request, .response)

    If $$$ISERR(sc) {
        Set %response.Status = "500 Internal Server Error"
        Write {"error": "Agent call failed"}.%ToJSON()
        Return sc
    }

    Set result = {
        "patientId": (pPatientId),
        "riskLevel": (response.RiskLevel),
        "recommendation": (response.Recommendation),
        "reasoning": (response.Reasoning),
        "suggestedNextStatus": (response.SuggestedNextStatus),
        "escalate": (response.Escalate)
    }

    Write result.%ToJSON()
    Return $$$OK
}
```

---

### STEP 6 — Dashboard: Add AI Agent Panel

**Modify `dashboard/index.html`** to add an "AI Analysis" button per patient card.

When clicked, it calls `GET /api/cardio/ai/analyze/{patientId}` and displays the agent's recommendation inline.

UI elements to add per patient card:
```html
<button class="ai-btn" onclick="analyzePatient('{{patientId}}')">🤖 AI Analysis</button>
<div class="ai-result" id="ai-{{patientId}}" style="display:none">
  <span class="risk-badge"></span>
  <p class="recommendation"></p>
  <p class="reasoning"></p>
</div>
```

JavaScript to add:
```javascript
async function analyzePatient(patientId) {
    const el = document.getElementById(`ai-${patientId}`);
    el.style.display = 'block';
    el.innerHTML = '<em>Analyzing...</em>';

    const res = await fetch(`/api/cardio/ai/analyze/${patientId}`);
    const data = await res.json();

    el.innerHTML = `
        <span class="risk-badge risk-${data.riskLevel}">${data.riskLevel}</span>
        <strong>${data.recommendation}</strong>
        <p>${data.reasoning}</p>
        <small>Suggested next: ${data.suggestedNextStatus} | Escalate: ${data.escalate}</small>
    `;
}
```

---

### STEP 7 — Environment Setup

**Modify `bin/start-product.ps1`** to:
1. Ask for / load `ANTHROPIC_API_KEY` from environment
2. Pass it into the IRIS container: `docker exec cardioflow-iris iris session IRIS -U CARDIOFLOW "set ^CardioFlow.Config(""ANTHROPIC_API_KEY"")=""$env:ANTHROPIC_API_KEY"""`
3. Start the FHIR setup step
4. Sync simulation data to FHIR after seeding

**Add to `bin/run-simulation.ps1`** after seeding:
```powershell
# Sync seeded data to FHIR server
docker exec cardioflow-iris iris session IRIS -U CARDIOFLOW "##class(CardioFlow.FHIR.ResourceBuilder).SyncAllToFHIR()"
```

---

### STEP 8 — README Updates (Critical)

Rewrite `README.md` to clearly state:

1. **What is the AI Agent** — explain the reasoning loop: FHIR Bundle → Claude → risk assessment → recommendation
2. **What FHIR resources are used** — Patient, Procedure, Observation
3. **How the IRIS Production works** — diagram of BS → BP → BO
4. **Prerequisites** — add `ANTHROPIC_API_KEY` environment variable requirement
5. **Add a video demo section** — record a 2-3 min Loom or YouTube demo showing:
   - Starting the product
   - The dashboard with patient cards
   - Clicking "AI Analysis" and seeing the agent response
   - IRIS Management Portal showing the Production running
6. **Add IPM section** (if time allows)

---

### STEP 9 — GitHub Repository Hygiene

Do this manually on GitHub:

1. Go to the repo → Settings → Topics → add:
   - `intersystems-iris`
   - `iris-for-health`
   - `fhir`
   - `fhir-r4`
   - `ai-agent`
   - `interoperability`
   - `objectscript`
   - `healthcare`
   - `cardiovascular`

2. Add a repo description: `"AI agent for cardiovascular surgical flow monitoring using FHIR R4 on InterSystems IRIS"`

3. Publish on **Open Exchange**: https://openexchange.intersystems.com/

---

### STEP 10 — IPM Package (Optional but recommended)

**File to create:** `module.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Export generator="Cache" version="25">
  <Document name="CardioFlow.ZPM">
    <Module>
      <Name>cardioflow</Name>
      <Version>1.0.0</Version>
      <Packaging>module</Packaging>
      <Description>AI agent for cardiovascular surgical flow monitoring using FHIR R4 on InterSystems IRIS</Description>
      <Keywords>FHIR,AI,Cardiovascular,Interoperability</Keywords>
      <SourcesRoot>src</SourcesRoot>
      <Resource Name="CardioFlow.PKG"/>
    </Module>
  </Document>
</Export>
```

---

## File Checklist

```
src/
  CardioFlow/
    Setup/
      FHIRSetup.cls              ← NEW: enables FHIR endpoint
    FHIR/
      ResourceBuilder.cls        ← NEW: maps SurgeryStatus → FHIR resources
    AI/
      Agent.py                   ← NEW: Python AI agent calling Claude
    Interop/
      Production.cls             ← NEW: IRIS Production definition
      AgentRequest.cls           ← NEW: Ens.Request message
      AgentResponse.cls          ← NEW: Ens.Response message
      AgentProcess.cls           ← NEW: Business Process (orchestrates AI call)
      FHIROperation.cls          ← NEW: Business Operation (writes to FHIR server)
    API/
      DashboardDispatch.cls      ← MODIFY: add /ai/analyze/:patientId route
    Analytics/
      SurgeryStatus.cls          ← EXISTING: no changes needed
    Sim/
      Runner.cls                 ← EXISTING: no changes needed

dashboard/
  index.html                     ← MODIFY: add AI Analysis button + panel

bin/
  start-product.ps1              ← MODIFY: add ANTHROPIC_API_KEY handling + FHIR setup
  run-simulation.ps1             ← MODIFY: add FHIR sync after seed
  setup-fhir.ps1                 ← NEW: standalone FHIR setup script

module.xml                       ← NEW: IPM package definition
README.md                        ← REWRITE: full contest-compliant README
```

---

## Priority Order (given time constraint)

| Priority | Item | Why |
|---|---|---|
| 🔴 P0 | FHIR ResourceBuilder + sync | Without FHIR data, the contest topic is not addressed |
| 🔴 P0 | Python AI Agent (Agent.py) | The contest requires an AI agent |
| 🔴 P0 | AgentProcess + API route | The agent must be callable in the pipeline |
| 🟠 P1 | Production.cls (BP/BO/BS) | Makes the IRIS Interoperability requirement real |
| 🟠 P1 | Dashboard AI panel | Makes the agent visible in the demo |
| 🟡 P2 | README rewrite | Required for approval |
| 🟡 P2 | Video demo | Strong recommendation from contest rules |
| 🟢 P3 | IPM module.xml | Differentiator, not mandatory |
| 🟢 P3 | GitHub topics | Helps community voting |

---

## Notes for Claude Code

- The IRIS container name is `cardioflow-iris` (from docker-compose)
- The IRIS namespace is `CARDIOFLOW`
- The REST API is published at `/api/cardio` in namespace `CARDIOFLOW`
- ObjectScript classes use the package `CardioFlow.*`
- PowerShell scripts bootstrap everything; add new steps at the end of `run-simulation.ps1`
- Python is available via EmbeddedPython inside IRIS — `import iris` works
- The existing proxy (`cardioflow_proxy.py`) forwards `/api/cardio/*` to IRIS — no changes needed there
- For the FHIR server, use `HS.FHIRServer.Installer` — it is available in IRIS for Health Community Edition
- If using plain IRIS Community (not Health), use `irishealth-community` image in docker-compose instead
- The `ANTHROPIC_API_KEY` must be available as an environment variable inside the IRIS container or stored in a global like `^CardioFlow.Config("ANTHROPIC_API_KEY")`
