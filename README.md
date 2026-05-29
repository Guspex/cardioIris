# cardioIris — AI Agent for Cardiovascular Surgical Flow Monitoring

**cardioIris** is a cardiovascular surgical flow monitoring system built on InterSystems IRIS for Health. It combines an AI clinical reasoning agent (powered by Claude) with FHIR R4 interoperability and an IRIS Production pipeline.

Submitted to the **InterSystems AI Agent + FHIR Interoperability Contest 2026**.

---

## What the AI Agent does

Each patient in the surgical flow can be analyzed on demand. The agent:

1. Reads the patient's current record from the IRIS database
2. Builds a **FHIR R4 Bundle** containing `Patient`, `Procedure` (SNOMED `81266008` — Heart surgery), and `Observation` resources
3. Sends the bundle to **Claude** (Anthropic) via the Anthropic API
4. Claude returns a structured clinical assessment:
   - `riskLevel`: `LOW | MEDIUM | HIGH | CRITICAL`
   - `recommendation`: one actionable sentence
   - `reasoning`: 2-3 sentence clinical rationale
   - `suggestedNextStatus`: next expected surgical phase
   - `escalate`: boolean flag

5. The result is displayed inline on the dashboard and stored as FHIR resources on the IRIS FHIR Server

---

## FHIR Resources Used

| Resource | Mapping |
|---|---|
| `Patient` | `patientId`, `patientName`, hospital tag |
| `Procedure` | status mapped to FHIR (`preparation` / `in-progress` / `completed`), SNOMED `81266008` |
| `Observation` | surgical phase, hospital code, scenario tag (LOINC `8716-3`) |

The `CardioFlow.FHIR.ResourceBuilder` class handles all conversions from the `SurgeryStatus` persistent model to FHIR R4 JSON.

---

## IRIS Interoperability Production

```
REST endpoint (/api/cardio/ai/analyze/:patientId)
        │
        ▼
DashboardDispatch.AnalyzePatient (ObjectScript)
        │
        ├── Builds FHIR Bundle from SurgeryStatus
        ├── Calls CallAIAgent (EmbeddedPython)
        │         └── Agent.py → Claude API → structured JSON
        └── Returns risk assessment to browser

IRIS Production (CardioFlow.Interop.Production):
  ├── AgentProcess   (Ens.BusinessProcess) — orchestrates AI call
  └── FHIROperation  (Ens.BusinessOperation) — writes FHIR resources back to server
```

The production is visible in the IRIS Management Portal under **Interoperability > Productions**.

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Docker Desktop | Running before startup |
| Python 3.x | Available on PATH |
| PowerShell | Available on PATH |
| `ANTHROPIC_API_KEY` | Required for AI analysis |

Set the API key before starting:

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
```

---

## Start the product

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
powershell -ExecutionPolicy Bypass -File bin/start-product.ps1
```

This script:

1. Starts the IRIS for Health Docker container
2. Enables Ensemble/Interoperability in the USER namespace
3. Compiles all CardioFlow ObjectScript and EmbeddedPython classes
4. Creates the API user and registers the REST application
5. Seeds 9 patients across 3 hospitals and 3 scenario packs
6. Syncs patient data to the FHIR R4 server (if available)
7. Stores the `ANTHROPIC_API_KEY` in the IRIS global config
8. Starts the local browser-facing proxy on `http://127.0.0.1:8787`

Keep the terminal open while using the product.

---

## Main URLs

| URL | Description |
|---|---|
| `http://127.0.0.1:8787/` | Live dashboard |
| `http://127.0.0.1:8787/api/cardio/dashboards/overview` | All patients JSON |
| `http://127.0.0.1:8787/api/cardio/ai/analyze/FHIR-TEST-001` | AI analysis for one patient |
| `http://localhost:52773/fhir/r4/Patient/FHIR-TEST-001` | FHIR Patient resource |
| `http://localhost:52773/csp/sys/EnsPortal.ProductionConfig.zen` | IRIS Production |

---

## Architecture

```
Browser Dashboard
      │
      ▼
Python Proxy (port 8787)
      │
      ├──► IRIS REST API (/api/cardio/*)
      │         DashboardDispatch.cls
      │              └── SurgeryStatus (persistent, FHIR-mapped)
      │
      └──► /ai/analyze/:patientId
                │
                ▼
         CardioFlow.FHIR.ResourceBuilder
                │  builds FHIR Bundle
                ▼
         EmbeddedPython (Agent.py)
                │  calls Claude API
                ▼
         IRIS Interop Production
           └── AgentProcess → FHIROperation → IRIS FHIR Server
```

---

## Scenario packs

Three scenario packs are seeded at startup:

| Scenario | Hospital | Description |
|---|---|---|
| `EMERGENCY_ESCALATION` | BOSTON-HEART | Critical pre-op, active valve repair, unstable post-op vitals |
| `DELAYED_SURGERY` | CHICAGO-CARDIAC | Backlog pressure, extended queue, slower recovery |
| `RECOVERY_ESCALATION` | SEATTLE-MED | Smooth intake, active OR load, escalated post-op neuro checks |

Each scenario contributes 1 waiting, 1 in-surgery, and 1 post-op case (9 total).

---

## Using the AI Analysis feature

1. Open `http://127.0.0.1:8787/`
2. Click **Refresh live board** to load patient cards
3. Click **AI Analysis** on any patient card
4. The agent fetches the patient's FHIR bundle, calls Claude, and displays the result inline

The risk badge color indicates severity: green (LOW) → yellow (MEDIUM) → orange (HIGH) → red (CRITICAL).

---

## FHIR Server setup (optional)

The FHIR R4 server endpoint can be installed separately:

```powershell
powershell -ExecutionPolicy Bypass -File bin/setup-fhir.ps1
```

This installs the endpoint at `http://localhost:52773/fhir/r4` using `HS.FHIRServer.Storage.Json.InteractionsStrategy`. Patient data is synced automatically after each simulation run.

---

## Step-by-step startup

### 1. Start Docker

```powershell
docker compose -f docker/docker-compose.yml up -d --build
```

### 2. Bootstrap IRIS, load classes, seed data

```powershell
powershell -ExecutionPolicy Bypass -File bin/run-simulation.ps1
```

### 3. Store API key in IRIS

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
```

(Or paste it interactively — `start-product.ps1` handles this automatically.)

### 4. Start the proxy

```powershell
python bin/cardioflow_proxy.py
```

---

## Project structure

```
src/
  CardioFlow/
    Analytics/
      SurgeryStatus.cls       Persistent data model (FHIR-mapped)
    API/
      DashboardDispatch.cls   REST API + /ai/analyze/:patientId endpoint
    FHIR/
      ResourceBuilder.cls     Converts SurgeryStatus → FHIR R4 resources
    AI/
      Agent.py                Python AI agent calling Claude via Anthropic API
    Interop/
      Production.cls          IRIS Interoperability Production definition
      AgentProcess.cls        Business Process — orchestrates AI via EmbeddedPython
      FHIROperation.cls       Business Operation — writes FHIR resources to server
      AgentRequest.cls        Ens.Request message
      AgentResponse.cls       Ens.Response message
    Setup/
      FHIRSetup.cls           Installs the FHIR R4 endpoint
    Sim/
      Runner.cls              Simulation seeder
    UI/
      DashboardPage.cls       CSP dashboard page

dashboard/
  index.html                  Browser dashboard with AI Analysis panel

bin/
  start-product.ps1           One-command startup (API key + FHIR + proxy)
  run-simulation.ps1          IRIS bootstrap + class loading + data seeding
  setup-fhir.ps1              FHIR endpoint installer
  cardioflow_proxy.py         Local browser-facing proxy

docker/
  docker-compose.yml          IRIS for Health 2026.1 container
  Dockerfile

module.xml                    IPM package definition
```

---

## Stop the product

```powershell
# Ctrl+C in the proxy terminal, then:
docker compose -f docker/docker-compose.yml down
```

---

## IPM install (coming soon)

```
zpm "install cardioflow"
```

---

## Technologies

- **InterSystems IRIS for Health 2026.1** — persistent storage, REST API, FHIR R4 server
- **IRIS Interoperability** — Production with Business Process and Business Operation
- **EmbeddedPython** — Python code running inside IRIS calling the Anthropic API
- **Claude (claude-sonnet-4-6)** — AI reasoning for clinical risk assessment
- **FHIR R4** — Patient, Procedure, Observation resources with SNOMED and LOINC codes
- **ObjectScript** — REST dispatch, FHIR builder, interop message classes
