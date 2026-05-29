Class CardioFlow.Interop.AgentResponse Extends Ens.Response
{

Property RiskLevel As %String;
Property Recommendation As %String;
Property Reasoning As %String;
Property SuggestedNextStatus As %String;
Property Escalate As %Boolean;
Property RawJSON As %String(MAXLEN = 4096);

}
