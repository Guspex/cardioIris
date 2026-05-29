/// IPM installer for CardioFlow.
/// Called during zpm "load" or zpm "install" configure phase.
Class CardioFlow.Installer
{

ClassMethod Setup() As %Status
{
    Write "CardioFlow: starting IPM setup...", !

    Set sc = ..EnableEnsemble()
    If $System.Status.IsError(sc) {
        Write "  WARNING Ensemble: ", $System.Status.GetErrorText(sc), !
    }

    Set sc = ..RegisterPythonPath()
    If $System.Status.IsError(sc) {
        Write "  WARNING Python path: ", $System.Status.GetErrorText(sc), !
    }

    Set sc = ..ConfigureWebApp()
    If $System.Status.IsError(sc) { Return sc }

    Set sc = ..StartProduction()
    If $System.Status.IsError(sc) {
        Write "  WARNING Production: ", $System.Status.GetErrorText(sc), !
    }

    Set envKey = ##class(%SYSTEM.Util).GetEnviron("ANTHROPIC_API_KEY")
    If envKey '= "" {
        Set ^CardioFlow.Config("ANTHROPIC_API_KEY") = envKey
        Write "  ANTHROPIC_API_KEY loaded from environment.", !
    }

    Write "CardioFlow: setup complete.", !
    Return $$$OK
}

ClassMethod Teardown() As %Status
{
    Set sc = ##class(Ens.Director).GetProductionStatus(.pn, .st)
    If st = 1 { Do ##class(Ens.Director).StopProduction() }

    New $namespace
    Set $namespace = "%SYS"
    If ##class(Security.Applications).Exists("/api/cardio") {
        Do ##class(Security.Applications).Delete("/api/cardio")
    }

    Set $namespace = "USER"
    Kill ^CardioFlow.Config
    Return $$$OK
}

ClassMethod EnableEnsemble() As %Status [ Private ]
{
    Return ##class(%EnsembleMgr).EnableNamespace($namespace, 1)
}

ClassMethod ConfigureWebApp() As %Status [ Private ]
{
    Set appNS = $namespace
    New $namespace
    Set $namespace = "%SYS"
    If ##class(Security.Applications).Exists("/api/cardio") {
        Do ##class(Security.Applications).Delete("/api/cardio")
    }
    Set props("NameSpace")     = appNS
    Set props("Enabled")       = 1
    Set props("DispatchClass") = "CardioFlow.API.DashboardDispatch"
    Set props("AutheEnabled")  = 32
    Set props("MatchRoles")    = "%All"
    Set sc = ##class(Security.Applications).Create("/api/cardio", .props)
    If $System.Status.IsOK(sc) { Write "  /api/cardio web app created.", ! }
    Return sc
}

ClassMethod StartProduction() As %Status [ Private ]
{
    Set sc = ##class(Ens.Director).GetProductionStatus(.pn, .st)
    If st = 1 {
        Write "  Production already running: ", pn, !
        Return $$$OK
    }
    Set sc = ##class(Ens.Director).StartProduction("CardioFlow.Interop.Production")
    If $System.Status.IsOK(sc) { Write "  Production started.", ! }
    Return sc
}

/// Finds Agent.py and stores its directory in ^CardioFlow.Config("PYTHON_PATH").
/// Search order: IPM module root → mgr/CardioFlow/AI → Docker default.
ClassMethod RegisterPythonPath() As %Status [ Private ]
{
    // 1. Try IPM module root (works for both zpm "load" and zpm "install")
    Try {
        Set module = ##class(%IPM.PackageManager.Developer.Module).NameOpen("cardioflow", .sc)
        If $IsObject(module) {
            Set candidate = module.Root _ "python"
            If ##class(%File).Exists(candidate _ "/Agent.py") {
                Set ^CardioFlow.Config("PYTHON_PATH") = candidate
                Write "  Python path (IPM): ", candidate, !
                Return $$$OK
            }
        }
    } Catch { }

    // 2. Try manager directory (set by a prior install)
    Set mgrPath = ##class(%File).ManagerDirectory() _ "CardioFlow/AI"
    If ##class(%File).Exists(mgrPath _ "/Agent.py") {
        Set ^CardioFlow.Config("PYTHON_PATH") = mgrPath
        Write "  Python path (mgr): ", mgrPath, !
        Return $$$OK
    }

    // 3. Docker default path
    Set dockerPath = "/home/irisowner/python"
    If ##class(%File).Exists(dockerPath _ "/Agent.py") {
        Set ^CardioFlow.Config("PYTHON_PATH") = dockerPath
        Write "  Python path (Docker): ", dockerPath, !
        Return $$$OK
    }

    Write "  WARNING: Agent.py not found. Set ^CardioFlow.Config(""PYTHON_PATH"") manually.", !
    Return $$$OK
}

}
