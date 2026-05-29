Class CardioFlow.BS.FHIRInbound Extends Ens.BusinessService
{

Include %occStatus
Include EnsMacros

Parameter ADAPTER = "Ens.InboundAdapter";

Property TargetConfigName As %String [ InitialExpression = "BP_Cardio_Orchestrator" ];

Method OnProcessInput(pFHIRJson As %Stream.GlobalCharacter, Output pMsgOut As %RegisteredObject) As %Status
{
    set sc = $$$OK

    try {
        set request = ##class(CardioFlow.Msg.FHIRRequest).%New()
        do request.Payload.CopyFrom(pFHIRJson)
        set sc = ..SendRequestAsync(..TargetConfigName, request)
        $$$ThrowOnError(sc)
    } catch ex {
        set sc = ex.AsStatus()
        $$$LOGERROR("Erro em FHIRInbound: "_$system.Status.GetErrorText(sc))
    }

    quit sc
}

}
