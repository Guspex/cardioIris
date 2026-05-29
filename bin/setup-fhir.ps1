$ErrorActionPreference = 'Stop'

Write-Host "Setting up FHIR R4 endpoint in IRIS..." -ForegroundColor Cyan

$setupFHIR = @'
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Setup/FHIRSetup.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
set sc=##class(CardioFlow.Setup.FHIRSetup).Enable()
write $SYSTEM.Status.GetErrorText(sc),!
halt
'@

$setupFHIR | docker exec -i cardioflow-iris iris session IRIS -U USER

Write-Host "FHIR setup complete. Endpoint available at http://localhost:52773/fhir/r4" -ForegroundColor Green
