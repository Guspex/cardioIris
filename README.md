# IRIS-CardioFlow

IRIS-CardioFlow is a cardiovascular surgical flow monitoring demo built on top of InterSystems IRIS 2026.

The current runtime model is:

- Docker runs the IRIS container.
- PowerShell bootstrap scripts compile the classes, publish the REST applications, create the technical API user, and seed the simulation data.
- A local gateway serves the browser UI without direct browser authentication against IRIS.
- The browser connects only to the local product URL.

## Architecture in this workspace

- IRIS container: `cardioflow-iris`
- IRIS API base: `http://localhost:52773/api/cardio`
- Local product gateway: `http://127.0.0.1:8787`
- Technical API user: `cardioapi`
- Technical API password: `Cardio123!`

## Scenario packs

The seeded demo includes three scenario packs:

- Emergency escalation
- Delayed surgery
- Recovery escalation

Each scenario pack creates:

- 1 waiting case
- 1 in-surgery case
- 1 post-op case

Expected seeded totals:

- `AWAITING = 3`
- `IN_SURGERY = 3`
- `POST_OP = 3`

## Prerequisites

Before starting, make sure you have:

1. Docker Desktop running
2. Python available on PATH
3. PowerShell available

## How to start Docker and the IRIS runtime

### Option A: Full product startup in one command

Run:

```powershell
powershell -ExecutionPolicy Bypass -File bin/start-product.ps1
```

What this does:

1. Starts or reuses the Docker container defined in [docker/docker-compose.yml](docker/docker-compose.yml)
2. Loads and compiles the analytics, simulation, API, and UI classes into IRIS
3. Recreates the technical API user and publishes the IRIS applications
4. Seeds the database with the U.S. scenario-pack data
5. Starts the local product gateway on `http://127.0.0.1:8787`

Keep that terminal open while using the product, because it runs the local gateway.

### Option B: Step-by-step startup

#### 1. Build and start Docker

```powershell
docker compose -f docker/docker-compose.yml up -d --build
```

#### 2. Bootstrap the IRIS runtime and seed the data

```powershell
powershell -ExecutionPolicy Bypass -File bin/run-simulation.ps1
```

This script:

1. Loads [src/CardioFlow/Analytics/SurgeryStatus.cls](src/CardioFlow/Analytics/SurgeryStatus.cls)
2. Loads [src/CardioFlow/Sim/Runner.cls](src/CardioFlow/Sim/Runner.cls)
3. Loads [src/CardioFlow/API/DashboardDispatch.cls](src/CardioFlow/API/DashboardDispatch.cls)
4. Loads [src/CardioFlow/UI/DashboardPage.cls](src/CardioFlow/UI/DashboardPage.cls)
5. Creates the `cardioapi` user
6. Publishes `/api/cardio`
7. Seeds the simulation records in IRIS

#### 3. Start the local gateway

```powershell
python bin/cardioflow_proxy.py
```

When it starts, you should see output like:

```text
CardioFlow proxy running on http://127.0.0.1:8787
Proxying IRIS API from http://localhost:52773
```

## How to open the product

Open this URL in your browser:

```text
http://127.0.0.1:8787/
```

This is the recommended entry point for the product.

The browser-facing app does not require you to type IRIS credentials.

## How to test the product

### 1. Verify Docker and IRIS are running

```powershell
docker ps --filter name=cardioflow-iris
```

You should see the container up and healthy.

### 2. Verify the product gateway is running

```powershell
curl http://127.0.0.1:8787/
```

Expected result:

- HTML content starting with `<!DOCTYPE html>`

### 3. Verify the summary API through the local gateway

```powershell
curl http://127.0.0.1:8787/api/cardio/dashboards/summary
```

Expected result:

```json
{"summary":[{"status":"AWAITING","total":3},{"status":"IN_SURGERY","total":3},{"status":"POST_OP","total":3}]}
```

### 4. Verify the full overview dataset

```powershell
curl http://127.0.0.1:8787/api/cardio/dashboards/overview
```

Expected result:

- 9 total records
- 3 hospitals
- 3 scenario packs

### 5. Verify a single patient record

```powershell
curl http://127.0.0.1:8787/api/cardio/patient/FHIR-TEST-001/status
```

Expected result includes:

- `patientName = Olivia Stone`
- `hospitalCode = BOSTON-HEART`
- `scenarioTag = EMERGENCY_ESCALATION`

### 6. Verify the dashboard UI manually

Open:

```text
http://127.0.0.1:8787/
```

Then confirm that:

1. The counters show `3 waiting`, `3 in surgery`, and `3 post-op`
2. The hospital filter shows:
	`BOSTON-HEART`, `CHICAGO-CARDIAC`, `SEATTLE-MED`
3. The scenario filter shows:
	`Emergency escalation`, `Delayed surgery`, `Recovery escalation`
4. The pre-op board shows:
	`James Wilson`, `Emma Carter`, `Noah Brooks`
5. The in-surgery board shows:
	`Olivia Stone`, `Ethan Clark`, `Sophia Reed`
6. The recovery board shows:
	`Olivia Stone`, `Ava Morgan`, `Liam Turner`

### 7. Verify filters and search

Try these UI checks:

1. Choose hospital `BOSTON-HEART`
	Expected: only Boston Heart cases remain visible
2. Choose scenario pack `Delayed surgery`
	Expected: only Chicago Cardiac cases remain visible
3. Search for `Olivia`
	Expected: only Olivia Stone records remain visible
4. Choose status `POST_OP`
	Expected: only post-op cards remain visible

## How to stop the product

### Stop only the local gateway

Press `Ctrl+C` in the terminal where `python bin/cardioflow_proxy.py` or `bin/start-product.ps1` is running.

### Stop the Docker container

```powershell
docker compose -f docker/docker-compose.yml down
```

## Useful files

- Product UI: [dashboard/index.html](dashboard/index.html)
- Local gateway: [bin/cardioflow_proxy.py](bin/cardioflow_proxy.py)
- One-command product startup: [bin/start-product.ps1](bin/start-product.ps1)
- IRIS bootstrap and seeding: [bin/run-simulation.ps1](bin/run-simulation.ps1)
- REST API: [src/CardioFlow/API/DashboardDispatch.cls](src/CardioFlow/API/DashboardDispatch.cls)
- Seeded simulation data: [src/CardioFlow/Sim/Runner.cls](src/CardioFlow/Sim/Runner.cls)

## Original design references

The original design and orchestration documents are still available here:

- [CARDIOFLOW-MASTER.md](CARDIOFLOW-MASTER.md)
- [SDD.md](SDD.md)
