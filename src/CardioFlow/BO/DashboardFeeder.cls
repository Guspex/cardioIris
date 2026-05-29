Class CardioFlow.BO.DashboardFeeder Extends Ens.BusinessOperation
{

Include %occStatus
Include EnsMacros

Parameter INVOCATION = "Queue";

Method OnFeed(pRequest As CardioFlow.Msg.SDAPersistRequest, Output pResponse As Ens.Response) As %Status
{
    set sc = $$$OK

    try {
        set patientId = ##class(CardioFlow.BO.SDAPersist).ResolvePatientId(pRequest.Container)
        $$$LOGINFO("DashboardFeeder recebeu evento para paciente: "_patientId_" / status: "_pRequest.PatientStatus)
    } catch ex {
        set sc = ex.AsStatus()
        $$$LOGERROR("Erro em DashboardFeeder: "_$system.Status.GetErrorText(sc))
    }

    quit sc
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="CardioFlow.Msg.SDAPersistRequest">
    <Method>OnFeed</Method>
  </MapItem>
</MapItems>
}

}
