$ErrorActionPreference = 'Stop'

docker compose -f docker/docker-compose.yml up -d

# Enable Interoperability (Ensemble) in USER namespace
$enableEnsemble = @'
try {
    do ##class(%EnsembleMgr).EnableNamespace("USER", 1)
    write "Ensemble enabled in USER",!
} catch ex {
    write "Ensemble already enabled or unavailable: ", ex.DisplayString(),!
}
halt
'@

$loadAnalytics = @'
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Analytics/SurgeryStatus.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
halt
'@

$loadRunner = @'
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Sim/Runner.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
halt
'@

$loadFHIRBuilder = @'
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/FHIR/ResourceBuilder.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
halt
'@

$loadFHIRSetup = @'
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Setup/FHIRSetup.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
halt
'@

$loadApi = @'
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/API/DashboardDispatch.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
halt
'@

$loadUi = @'
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/UI/DashboardPage.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
halt
'@

$loadInterop = @'
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/AgentRequest.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/AgentResponse.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/AgentProcess.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/FHIROperation.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
set sc=##class(%SYSTEM.OBJ).Load("/home/irisowner/src/CardioFlow/Interop/Production.cls","ck")
write $SYSTEM.Status.GetErrorText(sc),!
halt
'@

$configureSecurity = @'
set exists = ##class(Security.Users).Exists("cardioapi")
if exists do ##class(Security.Users).Delete("cardioapi")
set userProps("Password") = "Cardio123!"
set userProps("Enabled") = 1
set userProps("Roles") = "%All"
set userProps("PasswordNeverExpires") = 1
set userProps("PasswordChangeRequired") = 0
set sc = ##class(Security.Users).Create("cardioapi", .userProps)
write $SYSTEM.Status.GetErrorText(sc),!

set appExists = ##class(Security.Applications).Exists("/api/cardio")
if appExists do ##class(Security.Applications).Delete("/api/cardio")
set webProps("NameSpace") = "USER"
set webProps("Enabled") = 1
set webProps("DispatchClass") = "CardioFlow.API.DashboardDispatch"
set webProps("AutheEnabled") = 32
set webProps("MatchRoles") = "%All"
set sc = ##class(Security.Applications).Create("/api/cardio", .webProps)
write $SYSTEM.Status.GetErrorText(sc),!

set uiExists = ##class(Security.Applications).Exists("/cardioflow")
if uiExists do ##class(Security.Applications).Delete("/cardioflow")
set uiProps("NameSpace") = "USER"
set uiProps("Enabled") = 1
set uiProps("AutheEnabled") = 0
set uiProps("UnknownUser") = "cardioapi"
set uiProps("MatchRoles") = ""
set uiProps("CSPZENEnabled") = 0
set sc = ##class(Security.Applications).Create("/cardioflow", .uiProps)
write $SYSTEM.Status.GetErrorText(sc),!
halt
'@

$runSimulation = @'
set sc=##class(CardioFlow.Sim.Runner).RunAll()
write "STATUS=",$SYSTEM.Status.GetErrorText(sc),!,"SUMMARY=",##class(CardioFlow.Sim.Runner).SummaryText(),!
set rs=##class(%SQL.Statement).%ExecDirect(, "SELECT PatientId, Status, Source, HospitalCode, SurgeryRoom FROM CardioFlow_Analytics.SurgeryStatus ORDER BY %ID")
for { quit:'rs.%Next()  write rs.%Get("PatientId"),"|",rs.%Get("Status"),"|",rs.%Get("Source"),"|",rs.%Get("HospitalCode"),"|",rs.%Get("SurgeryRoom"),! }
halt
'@

$syncFHIR = @'
try {
    set sc=##class(CardioFlow.FHIR.ResourceBuilder).SyncAllToFHIR()
    write $SYSTEM.Status.GetErrorText(sc),!
} catch ex {
    write "FHIR sync skipped: ", ex.DisplayString(),!
}
halt
'@

$enableEnsemble | docker exec -i cardioflow-iris iris session IRIS -U %SYS
$loadAnalytics  | docker exec -i cardioflow-iris iris session IRIS -U USER
$loadRunner     | docker exec -i cardioflow-iris iris session IRIS -U USER
$loadFHIRBuilder | docker exec -i cardioflow-iris iris session IRIS -U USER
$loadFHIRSetup  | docker exec -i cardioflow-iris iris session IRIS -U USER
$loadApi        | docker exec -i cardioflow-iris iris session IRIS -U USER
$loadUi         | docker exec -i cardioflow-iris iris session IRIS -U USER
$loadInterop    | docker exec -i cardioflow-iris iris session IRIS -U USER
$configureSecurity | docker exec -i cardioflow-iris iris session IRIS -U %SYS
$runSimulation  | docker exec -i cardioflow-iris iris session IRIS -U USER
$syncFHIR       | docker exec -i cardioflow-iris iris session IRIS -U USER
