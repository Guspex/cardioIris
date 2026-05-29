Class CardioFlow.Analytics.PostOpCube Extends %DeepSee.Subject
{

Parameter DOMAIN = "CARDIOFLOW";

XData Cube [ XMLNamespace = "http://www.intersystems.com/deepsee" ]
{
<cube name="PostOpCube" displayName="Painel Pós-Operatório" sourceClass="CardioFlow.Analytics.SurgeryStatus" countMeasureName="Pacientes em Recuperação">
  <dimension name="Hospital" displayName="Hospital" hasAll="true">
    <hierarchy name="H1">
      <level name="Hospital" sourceProperty="HospitalCode" displayName="Hospital"/>
    </hierarchy>
  </dimension>
  <filter name="SomentePosOp" sourceProperty="Status" value="POST_OP"/>
</cube>
}

}
