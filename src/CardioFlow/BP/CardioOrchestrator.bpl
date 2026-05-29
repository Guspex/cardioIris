<?xml version="1.0" encoding="UTF-8"?>
<process language="objectscript"
         request="Ens.Request"
         response="Ens.Response"
         height="1800" width="1600"
         xmlns="http://www.intersystems.com/bpl">

  <context>
    <property name="Source" type="%String" instantiate="0"/>
    <property name="PatientStatus" type="%String" instantiate="0"/>
    <property name="SDAContainer" type="HS.SDA3.Container" instantiate="1"/>
  </context>

  <sequence xend="200" yend="1600">
    <if name="Mensagem HL7?" condition='request.%IsA("EnsLib.HL7.Message")' xpos="200" ypos="200">
      <true>
        <transform name="HL7 para SDA3"
                   class="CardioFlow.DTL.HL7ToSDA3"
                   source="request"
                   target="context.SDAContainer"
                   xpos="200" ypos="320"/>
        <assign name="Origem HL7" property="context.Source" value='"HL7"' action="set" xpos="200" ypos="420"/>
      </true>
      <false>
        <transform name="FHIR para SDA3"
                   class="CardioFlow.DTL.FHIRToSDA3"
                   source="request"
                   target="context.SDAContainer"
                   xpos="200" ypos="320"/>
        <assign name="Origem FHIR" property="context.Source" value='"FHIR"' action="set" xpos="200" ypos="420"/>
      </false>
    </if>

    <code name="Normalizar Status" xpos="200" ypos="560"><![CDATA[
      set encounter = ""
      set admCode = ""
      if $isobject(context.SDAContainer) && $isobject(context.SDAContainer.Encounters) {
          set encounter = context.SDAContainer.Encounters.GetAt(1)
      }
      if $isobject(encounter) && $isobject(encounter.AdmissionType) {
          set admCode = encounter.AdmissionType.Code
      }

      if admCode = "PRE" {
          set context.PatientStatus = "AWAITING"
      } elseif admCode = "SURG" {
          set context.PatientStatus = "IN_SURGERY"
      } elseif admCode = "REC" {
          set context.PatientStatus = "POST_OP"
      } else {
          set context.PatientStatus = "AWAITING"
      }
    ]]></code>

    <if name="Container válido?" condition='$isobject(context.SDAContainer) && (context.PatientStatus '= "")' xpos="200" ypos="760">
      <true>
        <call name="Persistir SDA" target="BO_SDA_Persist" async="0" xpos="200" ypos="920">
          <request type="CardioFlow.Msg.SDAPersistRequest">
            <assign property="callrequest.Container" value="context.SDAContainer" action="set"/>
            <assign property="callrequest.PatientStatus" value="context.PatientStatus" action="set"/>
            <assign property="callrequest.Source" value="context.Source" action="set"/>
          </request>
          <response type="Ens.Response"/>
        </call>

        <call name="Alimentar dashboard" target="BO_Dashboard_Feeder" async="1" xpos="200" ypos="1080">
          <request type="CardioFlow.Msg.SDAPersistRequest">
            <assign property="callrequest.Container" value="context.SDAContainer" action="set"/>
            <assign property="callrequest.PatientStatus" value="context.PatientStatus" action="set"/>
            <assign property="callrequest.Source" value="context.Source" action="set"/>
          </request>
        </call>
      </true>
      <false>
        <code name="Log erro" xpos="200" ypos="920"><![CDATA[
          $$$LOGERROR("CardioOrchestrator descartou mensagem por container invalido ou status vazio")
        ]]></code>
      </false>
    </if>
  </sequence>
</process>
