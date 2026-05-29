Class CardioFlow.Setup.FHIRSetup
{

ClassMethod Enable() As %Status
{
    Set sc = ##class(HS.FHIRServer.Installer).InstallInstance(
        "/fhir/r4",
        "HS.FHIRServer.Storage.Json.InteractionsStrategy",
        ""
    )
    If $SYSTEM.Status.IsError(sc) {
        Write "FHIR setup error: ", $SYSTEM.Status.GetErrorText(sc), !
    } Else {
        Write "FHIR R4 endpoint installed at /fhir/r4", !
    }
    Return sc
}

}
