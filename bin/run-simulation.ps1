$ErrorActionPreference = 'Stop'

docker compose -f docker/docker-compose.yml up -d

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

$loadAnalytics | docker exec -i cardioflow-iris iris session IRIS -U USER
$loadRunner | docker exec -i cardioflow-iris iris session IRIS -U USER
$loadApi | docker exec -i cardioflow-iris iris session IRIS -U USER
$loadUi | docker exec -i cardioflow-iris iris session IRIS -U USER
$configureSecurity | docker exec -i cardioflow-iris iris session IRIS -U %SYS
$runSimulation | docker exec -i cardioflow-iris iris session IRIS -U USER
