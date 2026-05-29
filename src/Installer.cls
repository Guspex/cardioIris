Class CardioFlow.Installer Extends %RegisteredObject
{

Include %occStatus

ClassMethod Setup(namespace As %String = "CARDIOFLOW") As %Status
{
    set sc = $$$OK

    try {
        if '##class(Config.Namespaces).Exists(namespace) {
            set props("Globals") = namespace
            set props("Routines") = namespace
            set sc = ##class(Config.Namespaces).Create(namespace, .props)
            $$$ThrowOnError(sc)
        }

        znspace namespace

        if ##class(%Dictionary.ClassDefinition).%ExistsId("HS.FHIRServer.Installer") {
            set sc = ##class(HS.FHIRServer.Installer).InstallInstance("/fhir/r4", "HealthShare", "")
            if $$$ISERR(sc) {
                set sc = $$$OK
            }
        }

        set sc = ##class(%SYSTEM.OBJ).LoadDir("/home/irisowner/src/CardioFlow", "ck")
        $$$ThrowOnError(sc)

        if ##class(%Dictionary.ClassDefinition).%ExistsId("Security.Applications") {
            set webProps("NameSpace") = namespace
            set webProps("Enabled") = 1
            set webProps("DispatchClass") = "CardioFlow.API.DashboardDispatch"
            set webProps("AutheEnabled") = 32
            if '##class(Security.Applications).Exists("/api/cardio") {
                set sc = ##class(Security.Applications).Create("/api/cardio", .webProps)
                $$$ThrowOnError(sc)
            }
        }
    } catch ex {
        set sc = ex.AsStatus()
    }

    quit sc
}

}
