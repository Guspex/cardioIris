Class CardioFlow.Interop.FHIROperation Extends Ens.BusinessOperation
{

Parameter ADAPTER = "EnsLib.HTTP.OutboundAdapter";

Property Adapter As EnsLib.HTTP.OutboundAdapter;

Parameter INVOCATION = "Queue";

Method PostFHIRResource(pRequest As Ens.StringRequest, Output pResponse As Ens.StringResponse) As %Status
{
    Set pResponse = ##class(Ens.StringResponse).%New()
    Set sc = ..Adapter.Post(.httpResponse, "/fhir/r4/Patient", pRequest.StringValue)
    If $$$ISERR(sc) { Return sc }
    Set pResponse.StringValue = httpResponse.Data.Read()
    Return $$$OK
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="Ens.StringRequest">
    <Method>PostFHIRResource</Method>
  </MapItem>
</MapItems>
}

}
