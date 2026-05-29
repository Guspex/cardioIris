$ErrorActionPreference = 'Stop'

# Helper: write ObjectScript to container and execute without BOM encoding issues
function Run-IRIS {
    param([string]$Script, [string]$Namespace = "USER")
    $tmpFile = [System.IO.Path]::GetTempFileName()
    # ASCII encoding: no BOM, avoids PowerShell 5.1 UTF-16 pipe corruption
    [System.IO.File]::WriteAllText($tmpFile, ($Script.TrimEnd() + "`nHalt"), [System.Text.Encoding]::ASCII)
    docker cp $tmpFile "cardioflow-iris:/tmp/iris_cmd.os" | Out-Null
    Remove-Item $tmpFile
    docker exec cardioflow-iris bash -c "iris session IRIS -U $Namespace < /tmp/iris_cmd.os"
}

docker compose -f docker/docker-compose.yml up -d

Write-Host "Waiting for IRIS to be healthy..." -ForegroundColor Cyan
$timeout = 120
$elapsed = 0
while ($elapsed -lt $timeout) {
    $health = docker inspect --format "{{.State.Health.Status}}" cardioflow-iris 2>$null
    if ($health -eq "healthy") { break }
    Start-Sleep -Seconds 5
    $elapsed += 5
    Write-Host "  ...still starting ($elapsed s)" -ForegroundColor DarkGray
}
if ($elapsed -ge $timeout) { throw "IRIS container did not become healthy in ${timeout}s" }
Write-Host "IRIS is healthy." -ForegroundColor Green

# Enable Ensemble in USER namespace
Write-Host "Enabling Ensemble..." -ForegroundColor Cyan
Run-IRIS -Namespace "%SYS" @'
Do ##class(%EnsembleMgr).EnableNamespace("USER", 1)
'@

# Load classes
Write-Host "Loading Analytics..." -ForegroundColor Cyan
Run-IRIS @'
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Analytics/SurgeryStatus.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
'@

Write-Host "Loading Sim.Runner..." -ForegroundColor Cyan
Run-IRIS @'
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Sim/Runner.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
'@

Write-Host "Loading FHIR classes..." -ForegroundColor Cyan
Run-IRIS @'
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/FHIR/ResourceBuilder.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Setup/FHIRSetup.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
'@

Write-Host "Loading API + UI..." -ForegroundColor Cyan
Run-IRIS @'
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/API/DashboardDispatch.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/UI/DashboardPage.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
'@

Write-Host "Loading Interop Production..." -ForegroundColor Cyan
Run-IRIS @'
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/AgentRequest.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/AgentResponse.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/AgentProcess.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/FHIROperation.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
Set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/Production.cls","ck")
Write $SYSTEM.Status.GetErrorText(sc),!
'@

Write-Host "Configuring security..." -ForegroundColor Cyan
Run-IRIS -Namespace "%SYS" @'
Set exists=##class(Security.Users).Exists("cardioapi")
If exists Do ##class(Security.Users).Delete("cardioapi")
Set userProps("Password")="Cardio123!"
Set userProps("Enabled")=1
Set userProps("Roles")="%All"
Set userProps("PasswordNeverExpires")=1
Set userProps("PasswordChangeRequired")=0
Set sc=##class(Security.Users).Create("cardioapi",.userProps)
Write $SYSTEM.Status.GetErrorText(sc),!

Set appExists=##class(Security.Applications).Exists("/api/cardio")
If appExists Do ##class(Security.Applications).Delete("/api/cardio")
Set webProps("NameSpace")="USER"
Set webProps("Enabled")=1
Set webProps("DispatchClass")="CardioFlow.API.DashboardDispatch"
Set webProps("AutheEnabled")=32
Set webProps("MatchRoles")="%All"
Set sc=##class(Security.Applications).Create("/api/cardio",.webProps)
Write $SYSTEM.Status.GetErrorText(sc),!

Set uiExists=##class(Security.Applications).Exists("/cardioflow")
If uiExists Do ##class(Security.Applications).Delete("/cardioflow")
Set uiProps("NameSpace")="USER"
Set uiProps("Enabled")=1
Set uiProps("AutheEnabled")=0
Set uiProps("UnknownUser")="cardioapi"
Set uiProps("MatchRoles")=""
Set uiProps("CSPZENEnabled")=0
Set sc=##class(Security.Applications).Create("/cardioflow",.uiProps)
Write $SYSTEM.Status.GetErrorText(sc),!
'@

Write-Host "Starting Interop Production..." -ForegroundColor Cyan
Run-IRIS @'
Set sc=##class(Ens.Director).GetProductionStatus(.pn,.st)
If st=1 {
    Write "Production already running: ",pn,!
} Else {
    Set sc=##class(Ens.Director).StartProduction("CardioFlow.Interop.Production")
    Write "StartProduction: ",$SYSTEM.Status.GetErrorText(sc),!
}
'@

Write-Host "Running simulation..." -ForegroundColor Cyan
Run-IRIS @'
Set sc=##class(CardioFlow.Sim.Runner).RunAll()
Write "STATUS=",$SYSTEM.Status.GetErrorText(sc),!
Write "SUMMARY=",##class(CardioFlow.Sim.Runner).SummaryText(),!
Set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT PatientId,Status,Source,HospitalCode,SurgeryRoom FROM CardioFlow_Analytics.SurgeryStatus ORDER BY %ID")
For { Quit:'rs.%Next() Write rs.%Get("PatientId"),"|",rs.%Get("Status"),"|",rs.%Get("Source"),"|",rs.%Get("HospitalCode"),"|",rs.%Get("SurgeryRoom"),! }
'@

Write-Host "Syncing FHIR..." -ForegroundColor Cyan
Run-IRIS @'
Try {
    Set sc=##class(CardioFlow.FHIR.ResourceBuilder).SyncAllToFHIR()
    Write $SYSTEM.Status.GetErrorText(sc),!
} Catch ex {
    Write "FHIR sync skipped: ",ex.DisplayString(),!
}
'@

Write-Host "Bootstrap complete." -ForegroundColor Green
