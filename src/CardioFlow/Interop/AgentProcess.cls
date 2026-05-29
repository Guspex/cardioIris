Class CardioFlow.Interop.AgentProcess Extends Ens.BusinessProcess [ ClassType = persistent ]
{

Method OnRequest(pRequest As CardioFlow.Interop.AgentRequest, Output pResponse As CardioFlow.Interop.AgentResponse) As %Status
{
    Set pResponse = ##class(CardioFlow.Interop.AgentResponse).%New()

    Set resultJson = ..CallPythonAgent(pRequest.PatientId, pRequest.IRISBase)

    Set result = ##class(%DynamicAbstractObject).%FromJSON(resultJson)
    Set pResponse.RiskLevel           = result.%Get("riskLevel")
    Set pResponse.Recommendation      = result.%Get("recommendation")
    Set pResponse.Reasoning           = result.%Get("reasoning")
    Set pResponse.SuggestedNextStatus = result.%Get("suggestedNextStatus")
    Set pResponse.Escalate            = result.%Get("escalate")
    Set pResponse.RawJSON             = resultJson

    Return $$$OK
}

Method CallPythonAgent(pPatientId As %String, pIRISBase As %String) As %String [ Language = python ]
{
    import sys, os, json
    sys.path.insert(0, '/home/irisowner/src/CardioFlow/AI')
    try:
        from Agent import run_agent
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        result = run_agent(pPatientId, pIRISBase, api_key)
        return json.dumps(result)
    except Exception as e:
        return json.dumps({
            "riskLevel": "UNKNOWN",
            "recommendation": "AI agent error",
            "reasoning": str(e),
            "suggestedNextStatus": "",
            "escalate": False
        })
}

}
