Class CardioFlow.Interop.Production Extends Ens.Production
{

XData ProductionDefinition
{
<Production Name="CardioFlow.Interop.Production" LogGeneralTraceEvents="false">
  <Description>CardioFlow AI Agent Production for FHIR interoperability</Description>
  <ActorPoolSize>2</ActorPoolSize>
  <Item Name="CardioFlow.Interop.AgentProcess" Category="" ClassName="CardioFlow.Interop.AgentProcess" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
  <Item Name="CardioFlow.Interop.FHIROperation" Category="" ClassName="CardioFlow.Interop.FHIROperation" PoolSize="1" Enabled="true" Foreground="false" Comment="" LogTraceEvents="false" Schedule="">
  </Item>
</Production>
}

}
