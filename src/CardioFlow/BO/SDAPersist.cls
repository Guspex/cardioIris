Class CardioFlow.BO.SDAPersist Extends Ens.BusinessOperation
{

Include %occStatus
Include EnsMacros

Parameter INVOCATION = "Queue";

Method OnPersistSDA(pRequest As CardioFlow.Msg.SDAPersistRequest, Output pResponse As Ens.Response) As %Status
{
    set sc = $$$OK

    try {
        set patientId = ..ResolvePatientId(pRequest.Container)

        if ##class(%Dictionary.ClassDefinition).%ExistsId("HS.HC.UniversalViewer.API") {
            set sc = ##class(HS.HC.UniversalViewer.API).ProcessSDA(pRequest.Container, .patientId)
            $$$ThrowOnError(sc)
        }

        set tracker = ##class(CardioFlow.Analytics.SurgeryStatus).%New()
        set tracker.PatientId = patientId
        set tracker.Status = pRequest.PatientStatus
        set tracker.Source = pRequest.Source
        set tracker.EventTime = $zdt($h, 3)
        set tracker.PatientName = ..ResolvePatientName(pRequest.Container)
        set tracker.HospitalCode = ..ResolveHospitalCode(pRequest.Container)
        set tracker.SurgeryRoom = ..ResolveSurgeryRoom(pRequest.Container)
        set sc = tracker.%Save()
        $$$ThrowOnError(sc)
    } catch ex {
        set sc = ex.AsStatus()
        $$$LOGERROR("Erro em SDAPersist: "_$system.Status.GetErrorText(sc))
    }

    quit sc
}

ClassMethod ResolvePatientId(container As HS.SDA3.Container) As %String [ Private ]
{
    if '$isobject(container) {
        quit ""
    }
    if $isobject(container.Patient) && $isobject(container.Patient.PatientNumbers) {
        set patientNumber = container.Patient.PatientNumbers.GetAt(1)
        if $isobject(patientNumber) {
            quit patientNumber.Number
        }
    }
    quit ""
}

ClassMethod ResolvePatientName(container As HS.SDA3.Container) As %String [ Private ]
{
    if '$isobject(container) || '$isobject(container.Patient) || '$isobject(container.Patient.Name) {
        quit ""
    }
    quit container.Patient.Name.FamilyName_", "_container.Patient.Name.GivenName
}

ClassMethod ResolveHospitalCode(container As HS.SDA3.Container) As %String [ Private ]
{
    if '$isobject(container) || '$isobject(container.Encounters) {
        quit ""
    }
    set encounter = container.Encounters.GetAt(1)
    if '$isobject(encounter) || '$isobject(encounter.EnteredAt) {
        quit ""
    }
    quit encounter.EnteredAt.Code
}

ClassMethod ResolveSurgeryRoom(container As HS.SDA3.Container) As %String [ Private ]
{
    quit ..ResolveHospitalCode(container)
}

XData MessageMap
{
<MapItems>
  <MapItem MessageType="CardioFlow.Msg.SDAPersistRequest">
    <Method>OnPersistSDA</Method>
  </MapItem>
</MapItems>
}

}
