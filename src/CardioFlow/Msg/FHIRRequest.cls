Class CardioFlow.Msg.FHIRRequest Extends Ens.Request
{

Property ResourceType As %String(MAXLEN = 64) [ InitialExpression = "Bundle" ];

Property Payload As %Stream.GlobalCharacter;

}
