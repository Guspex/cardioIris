# cardioIris — AI Agent for Cardiovascular Surgical Flow Monitoring

**cardioIris** is a cardiovascular surgical flow monitoring system built on InterSystems IRIS for Health. It combines an AI clinical reasoning agent (powered by Claude) with FHIR R4 interoperability and an IRIS Interoperability Production.

Submitted to the **InterSystems AI Agent + FHIR Interoperability Contest 2026**.

---

## What the AI Agent does

Each patient in the surgical flow can be analyzed on demand. The agent:

1. Reads the patient's current record from the IRIS database
2. Builds a **FHIR R4 Bundle** containing `Patient`, `Procedure` (SNOMED `81266008` — Heart surgery), and `Observation` resources
3. Sends the bundle to **Claude** (`claude-sonnet-4-6`) via the Anthropic API
4. Returns a structured clinical assessment:
   - `riskLevel`: `LOW | MEDIUM | HIGH | CRITICAL`
   - `recommendation`: one actionable sentence
   - `reasoning`: 2–3 sentence clinical rationale
   - `suggestedNextStatus`: next expected surgical phase
   - `escalate`: boolean flag

---

## FHIR Resources

| Resource | Mapping |
|---|---|
| `Patient` | `patientId`, `patientName`, hospital tag |
| `Procedure` | status mapped to FHIR (`preparation` / `in-progress` / `completed`), SNOMED `81266008` |
| `Observation` | surgical phase, hospital code, scenario tag (LOINC `8716-3`) |

`CardioFlow.FHIR.ResourceBuilder` handles all conversions from the `SurgeryStatus` persistent model to FHIR R4 JSON.

---

## IRIS Interoperability Production

```
REST endpoint  /api/cardio/ai/analyze/:patientId
      │
      ▼
DashboardDispatch.AnalyzePatient  (ObjectScript)
      │
      ├── Builds FHIR Bundle from SurgeryStatus
      └── CallAIAgent  (EmbeddedPython)
                └── python/Agent.py → Claude API → structured JSON

IRIS Production  CardioFlow.Interop.Production
  ├── AgentProcess    (Ens.BusinessProcess)  — orchestrates AI call
  └── FHIROperation   (Ens.BusinessOperation) — writes FHIR resources
```

Visible in IRIS Management Portal under **Interoperability › Productions**.

---

## Quick start — Docker

### Prerequisites

| Requirement | Notes |
|---|---|
| Docker Desktop | Running before startup |
| Python 3.x | For the local proxy |
| PowerShell | Windows built-in |
| `ANTHROPIC_API_KEY` | Required for AI analysis |

### Start

```powershell
$env:ANTHROPIC_API_KEY = "sk-ant-..."
powershell -ExecutionPolicy Bypass -File bin/start-product.ps1
```

This script:

1. Starts the IRIS for Health 2026.1 Docker container
2. Waits for the container to become healthy
3. Enables Ensemble/Interoperability in the `USER` namespace
4. Compiles all CardioFlow classes (ObjectScript + EmbeddedPython)
5. Configures the REST web application and API user
6. Starts the `CardioFlow.Interop.Production`
7. Seeds 9 patients across 3 hospitals and 3 scenario packs
8. Syncs patient data to the FHIR R4 server
9. Stores the `ANTHROPIC_API_KEY` in the IRIS global config
10. Starts the local browser-facing proxy on `http://127.0.0.1:8787`

Keep the terminal open while using the product.

### Open the dashboard

```
http://127.0.0.1:8787/
```

### Stop

```powershell
# Ctrl+C in the proxy terminal, then:
docker compose -f docker/docker-compose.yml down
```

---

## Quick start — IPM

### Prerequisites

- InterSystems IRIS for Health 2024.1+
- IPM 0.7+ installed ([install guide](https://github.com/intersystems/ipm))
- `ANTHROPIC_API_KEY` set in the environment

### Install from a local clone

```objectscript
zpm "load /path/to/cardioIris"
```

### Install from Open Exchange (after publication)

```objectscript
zpm "install cardioflow"
```

The `CardioFlow.Installer` class runs automatically during the `Configure` phase and:

- Enables Interoperability in the current namespace
- Creates the `/api/cardio` REST web application
- Starts `CardioFlow.Interop.Production`
- Registers `python/Agent.py` path via `^CardioFlow.Config("PYTHON_PATH")`
- Picks up `ANTHROPIC_API_KEY` from the environment if set

After install, set the API key if it was not in the environment:

```objectscript
Set ^CardioFlow.Config("ANTHROPIC_API_KEY") = "sk-ant-..."
```

Then open the dashboard via the IRIS web gateway (port 52773 by default):

```
http://localhost:52773/api/cardio/dashboard
```

---

## Main URLs

| URL | Description |
|---|---|
| `http://127.0.0.1:8787/` | Live dashboard (Docker + proxy) |
| `http://127.0.0.1:8787/api/cardio/health` | API health check |
| `http://127.0.0.1:8787/api/cardio/dashboards/overview` | All patients (JSON) |
| `http://127.0.0.1:8787/api/cardio/ai/analyze/PAT001` | AI analysis for one patient |
| `http://localhost:52773/fhir/r4/Patient` | FHIR Patient endpoint |
| `http://localhost:52773/csp/sys/EnsPortal.ProductionConfig.zen` | IRIS Production portal |

---

## Scenario packs

Three scenario packs are seeded at startup:

| Scenario | Hospital | Description |
|---|---|---|
| `EMERGENCY_ESCALATION` | BOSTON-HEART | Critical pre-op, active valve repair, unstable post-op vitals |
| `DELAYED_SURGERY` | CHICAGO-CARDIAC | Backlog pressure, extended queue, slower recovery |
| `RECOVERY_ESCALATION` | SEATTLE-MED | Smooth intake, active OR load, escalated post-op neuro checks |

Each scenario contributes 1 waiting, 1 in-surgery, and 1 post-op case (9 patients total).

---

## Using the AI Analysis feature

1. Open the dashboard and click **Refresh live board** to load patient cards
2. Click **AI Analysis** on any patient card
3. The agent builds the patient's FHIR Bundle, calls Claude, and displays the result inline

Risk badge colors: green (LOW) → yellow (MEDIUM) → orange (HIGH) → red (CRITICAL).

---

## Architecture

```
Browser Dashboard
      │
      ▼
Python Proxy  :8787
      │
      ├──► GET /api/cardio/*
      │         DashboardDispatch.cls  (ObjectScript)
      │              └── CardioFlow_Analytics.SurgeryStatus  (SQL)
      │
      └──► GET /api/cardio/ai/analyze/:patientId
                │
                ▼
         CardioFlow.FHIR.ResourceBuilder
                │  FHIR R4 Bundle
                ▼
         EmbeddedPython  (python/Agent.py)
                │  Anthropic API
                ▼
         Claude claude-sonnet-4-6
                │  structured JSON
                ▼
         IRIS Interop Production
           └── AgentProcess → FHIROperation → IRIS FHIR Server
```

---

## Project structure

```
python/
  Agent.py                    Python AI agent — calls Claude via Anthropic API

src/
  CardioFlow/
    Analytics/
      SurgeryStatus.cls       Persistent data model (FHIR-mapped SQL table)
    API/
      DashboardDispatch.cls   REST API + /ai/analyze/:patientId endpoint
    FHIR/
      ResourceBuilder.cls     SurgeryStatus → FHIR R4 Patient/Procedure/Observation
    Interop/
      Production.cls          IRIS Interoperability Production definition
      AgentProcess.cls        Business Process — orchestrates AI via EmbeddedPython
      FHIROperation.cls       Business Operation — writes FHIR resources to server
      AgentRequest.cls        Ens.Request message
      AgentResponse.cls       Ens.Response message
    Setup/
      FHIRSetup.cls           Installs the FHIR R4 endpoint
    Installer.cls             IPM Configure/Unconfigure lifecycle handler
    Sim/
      Runner.cls              Simulation data seeder
    UI/
      DashboardPage.cls       CSP page (legacy portal)

dashboard/
  index.html                  Single-page dashboard with AI Analysis panels

bin/
  start-product.ps1           One-command startup (Docker + API key + proxy)
  run-simulation.ps1          IRIS bootstrap, class loading, data seeding
  setup-fhir.ps1              FHIR endpoint installer
  cardioflow_proxy.py         Local proxy — serves dashboard and proxies API calls

docker/
  docker-compose.yml          IRIS for Health 2026.1 container definition
  Dockerfile

module.xml                    IPM package manifest (cardioflow 1.0.0)
```

---

## Technologies

| Layer | Technology |
|---|---|
| IRIS platform | InterSystems IRIS for Health 2026.1 |
| Data model | ObjectScript persistent classes + SQL |
| REST API | `%CSP.REST` dispatch class |
| FHIR | IRIS FHIR R4 server, `Patient` / `Procedure` / `Observation` |
| Interoperability | IRIS Production — Business Process + Business Operation |
| AI agent | EmbeddedPython + `python/Agent.py` |
| LLM | Claude `claude-sonnet-4-6` via Anthropic API |
| Package manager | IPM 0.10.7 (`zpm "load"` / `zpm "install"`) |
| Dashboard | Vanilla HTML/CSS/JS, served via Python proxy |
