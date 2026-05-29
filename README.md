# IRIS-CardioFlow

IRIS-CardioFlow is a streamlined cardiovascular surgical flow monitoring demo built on top of InterSystems IRIS 2026.

This repository now contains only the files required to run the product:

- Docker runtime for IRIS
- IRIS classes used by the current demo
- Seeded simulation data logic
- Browser dashboard
- Local proxy that removes direct browser authentication against IRIS
- Startup scripts

## Runtime architecture

- Docker runs the IRIS container.
- PowerShell bootstrap scripts compile the IRIS classes, publish the REST API, create the technical API user, and seed the simulation dataset.
- A local Python gateway serves the product UI and proxies API requests to IRIS.
- The browser talks only to the local product URL.

## Main URLs

- Product UI: `http://127.0.0.1:8787/`
- Product API proxy: `http://127.0.0.1:8787/api/cardio/...`
- IRIS API direct: `http://localhost:52773/api/cardio/...`

## Prerequisites

Before starting, make sure you have:

1. Docker Desktop running
2. Python available on PATH
3. PowerShell available

## Start the product

### One-command startup

Run:

```powershell
powershell -ExecutionPolicy Bypass -File bin/start-product.ps1
```

What this command does:

1. Starts or reuses the IRIS container from [docker/docker-compose.yml](docker/docker-compose.yml)
2. Loads and compiles the IRIS classes that power the demo
3. Recreates the technical API user and republishes the REST application
4. Seeds the scenario-pack data into IRIS
5. Starts the local browser-facing proxy on `http://127.0.0.1:8787`

Keep that terminal open while using the product because it runs the proxy server.

### Step-by-step startup

#### 1. Start Docker

```powershell
docker compose -f docker/docker-compose.yml up -d --build
```

#### 2. Bootstrap IRIS and seed the product data

```powershell
powershell -ExecutionPolicy Bypass -File bin/run-simulation.ps1
```

This script compiles the active demo classes and seeds the product data.

#### 3. Start the local product proxy

```powershell
python bin/cardioflow_proxy.py
```

Expected startup output:

```text
CardioFlow proxy running on http://127.0.0.1:8787
Proxying IRIS API from http://localhost:52773
```

## Scenario packs

The demo seeds three scenario packs:

- Emergency escalation
- Delayed surgery
- Recovery escalation

Each scenario pack contributes:

- 1 waiting case
- 1 in-surgery case
- 1 post-op case

Expected totals:

- `AWAITING = 3`
- `IN_SURGERY = 3`
- `POST_OP = 3`

## How to test

### 1. Verify the IRIS container is running

```powershell
docker ps --filter name=cardioflow-iris
```

Expected result:

- The container `cardioflow-iris` is up

### 2. Verify the product UI is served by the proxy

```powershell
curl http://127.0.0.1:8787/
```

Expected result:

- HTML output beginning with `<!DOCTYPE html>`

### 3. Verify the summary API through the proxy

```powershell
curl http://127.0.0.1:8787/api/cardio/dashboards/summary
```

Expected result:

```json
{"summary":[{"status":"AWAITING","total":3},{"status":"IN_SURGERY","total":3},{"status":"POST_OP","total":3}]}
```

### 4. Verify the overview dataset

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

Expected fields include:

- `patientName = Olivia Stone`
- `hospitalCode = BOSTON-HEART`
- `scenarioTag = EMERGENCY_ESCALATION`

### 6. Verify the dashboard manually

Open:

```text
http://127.0.0.1:8787/
```

Expected UI state:

1. Counters show `3 waiting`, `3 in surgery`, `3 post-op`
2. Hospital filter shows:
	`BOSTON-HEART`, `CHICAGO-CARDIAC`, `SEATTLE-MED`
3. Scenario filter shows:
	`Emergency escalation`, `Delayed surgery`, `Recovery escalation`
4. Waiting cases:
	`James Wilson`, `Emma Carter`, `Noah Brooks`
5. In-surgery cases:
	`Olivia Stone`, `Ethan Clark`, `Sophia Reed`
6. Post-op cases:
	`Olivia Stone`, `Ava Morgan`, `Liam Turner`

### 7. Verify filters and search

Suggested checks:

1. Choose hospital `BOSTON-HEART`
	Expected: only Boston Heart cases remain visible
2. Choose scenario pack `Delayed surgery`
	Expected: only Chicago Cardiac cases remain visible
3. Search for `Olivia`
	Expected: only Olivia Stone records remain visible
4. Choose status `POST_OP`
	Expected: only post-op records remain visible

## Stop the product

### Stop the local proxy

Press `Ctrl+C` in the terminal running `python bin/cardioflow_proxy.py` or `bin/start-product.ps1`.

### Stop Docker

```powershell
docker compose -f docker/docker-compose.yml down
```

## Kept runtime files

- Product UI: [dashboard/index.html](dashboard/index.html)
- Local product proxy: [bin/cardioflow_proxy.py](bin/cardioflow_proxy.py)
- One-command startup: [bin/start-product.ps1](bin/start-product.ps1)
- IRIS bootstrap and seeding: [bin/run-simulation.ps1](bin/run-simulation.ps1)
- REST API: [src/CardioFlow/API/DashboardDispatch.cls](src/CardioFlow/API/DashboardDispatch.cls)
- Simulation logic: [src/CardioFlow/Sim/Runner.cls](src/CardioFlow/Sim/Runner.cls)
- IRIS persistence model: [src/CardioFlow/Analytics/SurgeryStatus.cls](src/CardioFlow/Analytics/SurgeryStatus.cls)
