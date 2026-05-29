Class CardioFlow.Production Extends Ens.Production
{

Parameter AWAITING = "AWAITING";

Parameter IN_SURGERY = "IN_SURGERY";

Parameter POST_OP = "POST_OP";

XData ProductionDefinition
{
<Production Name="CardioFlow.Production" TestingEnabled="true" LogGeneralTraceEvents="true">
  <Description>IRIS-CardioFlow</Description>
  <ActorPoolSize>2</ActorPoolSize>

  <Item Name="BS_HL7_Inbound" Category="BS" ClassName="CardioFlow.BS.HL7Inbound"
    PoolSize="1" Enabled="true" Foreground="false">
    <Setting Target="Adapter" Name="Port">6661</Setting>
    <Setting Target="Adapter" Name="StayConnected">-1</Setting>
  </Item>

  <Item Name="BS_FHIR_Inbound" Category="BS" ClassName="CardioFlow.BS.FHIRInbound"
    PoolSize="1" Enabled="true" Foreground="false">
  </Item>

  <Item Name="BP_Cardio_Orchestrator" Category="BP" ClassName="CardioFlow.BP.CardioOrchestrator"
    PoolSize="2" Enabled="true" Foreground="false">
  </Item>

  <Item Name="BO_SDA_Persist" Category="BO" ClassName="CardioFlow.BO.SDAPersist"
    PoolSize="1" Enabled="true" Foreground="false">
  </Item>

  <Item Name="BO_Dashboard_Feeder" Category="BO" ClassName="CardioFlow.BO.DashboardFeeder"
    PoolSize="1" Enabled="true" Foreground="false">
  </Item>
</Production>
}

}
