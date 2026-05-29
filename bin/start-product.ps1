$ErrorActionPreference = 'Stop'

# Check for ANTHROPIC_API_KEY
if (-not $env:ANTHROPIC_API_KEY) {
    Write-Host "WARNING: ANTHROPIC_API_KEY is not set. AI agent analysis will return a config error." -ForegroundColor Yellow
    Write-Host "Set it with: `$env:ANTHROPIC_API_KEY = 'sk-ant-...' and re-run this script." -ForegroundColor Yellow
} else {
    Write-Host "ANTHROPIC_API_KEY detected." -ForegroundColor Green
}

# Bootstrap IRIS, load classes, seed simulation data
powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-simulation.ps1')

# Store API key in IRIS global config for EmbeddedPython access
if ($env:ANTHROPIC_API_KEY) {
    $apiKeyValue = $env:ANTHROPIC_API_KEY
    $setApiKey = @"
set ^CardioFlow.Config("ANTHROPIC_API_KEY")="$apiKeyValue"
write "API key stored in IRIS global config",!
halt
"@
    $setApiKey | docker exec -i cardioflow-iris iris session IRIS -U USER
}

# Try FHIR server setup (optional — requires HS.FHIRServer.Installer)
Write-Host "Attempting FHIR server setup..." -ForegroundColor Cyan
try {
    powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'setup-fhir.ps1') -ErrorAction SilentlyContinue
} catch {
    Write-Host "FHIR setup skipped (not critical for core demo)." -ForegroundColor Yellow
}

# Start local product proxy (keeps running until Ctrl+C)
python (Join-Path $PSScriptRoot 'cardioflow_proxy.py')
