Class CardioFlow.Analytics.IntraOpCube Extends %DeepSee.Subject
{

Parameter DOMAIN = "CARDIOFLOW";

XData Cube [ XMLNamespace = "http://www.intersystems.com/deepsee" ]
{
<cube name="IntraOpCube" displayName="Painel Intra-Operatório" sourceClass="CardioFlow.Analytics.SurgeryStatus" countMeasureName="Cirurgias em Andamento">
  <dimension name="Sala" displayName="Sala" hasAll="true">
    <hierarchy name="H1">
      <level name="Sala" sourceProperty="SurgeryRoom" displayName="Sala"/>
    </hierarchy>
  </dimension>
  <dimension name="Hospital" displayName="Hospital" hasAll="true">
    <hierarchy name="H1">
      <level name="Hospital" sourceProperty="HospitalCode" displayName="Hospital"/>
    </hierarchy>
  </dimension>
  <filter name="SomenteCirurgia" sourceProperty="Status" value="IN_SURGERY"/>
</cube>
}

}
