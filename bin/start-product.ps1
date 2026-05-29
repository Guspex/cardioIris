$ErrorActionPreference = 'Stop'

powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'run-simulation.ps1')
python (Join-Path $PSScriptRoot 'cardioflow_proxy.py')
