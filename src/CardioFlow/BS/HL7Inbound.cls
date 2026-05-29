Class CardioFlow.BS.HL7Inbound Extends EnsLib.HL7.Service.TCP
{

Include %occStatus
Include EnsMacros

Parameter SETTINGS = "TargetConfigName:Basic,MessageSchemaCategory:Basic";

Property TargetConfigName As %String [ InitialExpression = "BP_Cardio_Orchestrator" ];

Method OnProcessInput(pMsgIn As EnsLib.HL7.Message, Output pMsgOut As %RegisteredObject) As %Status
{
    set sc = $$$OK

    try {
        $$$LOGINFO("HL7 recebido: "_pMsgIn.Name_" / Tipo: "_pMsgIn.GetValueAt("MSH:9"))
        set sc = ..SendRequestAsync(..TargetConfigName, pMsgIn)
        $$$ThrowOnError(sc)
    } catch ex {
        set sc = ex.AsStatus()
        $$$LOGERROR("Erro em HL7Inbound: "_$system.Status.GetErrorText(sc))
    }

    quit sc
}

}
