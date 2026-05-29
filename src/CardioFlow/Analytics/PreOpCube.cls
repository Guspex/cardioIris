Class CardioFlow.Analytics.PreOpCube Extends %DeepSee.Subject
{

Parameter DOMAIN = "CARDIOFLOW";

Parameter SUBJECTAREA = "CardioFlow/PreOp";

XData Cube [ XMLNamespace = "http://www.intersystems.com/deepsee" ]
{
<cube name="PreOpCube" displayName="Painel Pré-Operatório" sourceClass="CardioFlow.Analytics.SurgeryStatus" countMeasureName="Contagem">
  <measure name="TempoEspera" displayName="Tempo de Espera" sourceProperty="WaitingMinutes" type="number" aggregate="AVG"/>
  <dimension name="Hospital" displayName="Hospital" hasAll="true">
    <hierarchy name="H1">
      <level name="Hospital" sourceProperty="HospitalCode" displayName="Hospital"/>
    </hierarchy>
  </dimension>
  <filter name="SomenteAguardando" sourceProperty="Status" value="AWAITING"/>
</cube>
}

}
