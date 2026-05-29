Class CardioFlow.FHIR.ResourceBuilder
{

ClassMethod BuildPatient(pRecord As CardioFlow.Analytics.SurgeryStatus) As %DynamicObject
{
    Set patient = {
        "resourceType": "Patient",
        "id": (pRecord.PatientId),
        "name": [{
            "use": "official",
            "text": (pRecord.PatientName)
        }],
        "meta": {
            "tag": [{
                "system": "http://cardioiris.local/tags",
                "code": (pRecord.HospitalCode)
            }]
        }
    }
    Return patient
}

ClassMethod BuildProcedure(pRecord As CardioFlow.Analytics.SurgeryStatus) As %DynamicObject
{
    Set fhirStatus = $Case(pRecord.Status,
        "IN_SURGERY": "in-progress",
        "POST_OP": "completed",
        : "preparation"
    )
    Set procedure = {
        "resourceType": "Procedure",
        "id": ("proc-" _ pRecord.PatientId),
        "status": (fhirStatus),
        "subject": {
            "reference": ("Patient/" _ pRecord.PatientId)
        },
        "code": {
            "coding": [{
                "system": "http://snomed.info/sct",
                "code": "81266008",
                "display": "Heart surgery"
            }]
        },
        "note": [{
            "text": (pRecord.ScenarioTag)
        }]
    }
    Return procedure
}

ClassMethod BuildObservation(pRecord As CardioFlow.Analytics.SurgeryStatus) As %DynamicObject
{
    Set obs = {
        "resourceType": "Observation",
        "id": ("obs-" _ pRecord.PatientId),
        "status": "final",
        "subject": {
            "reference": ("Patient/" _ pRecord.PatientId)
        },
        "code": {
            "coding": [{
                "system": "http://loinc.org",
                "code": "8716-3",
                "display": "Vital signs"
            }]
        },
        "valueString": (pRecord.Status),
        "component": [{
            "code": { "text": "Hospital" },
            "valueString": (pRecord.HospitalCode)
        }, {
            "code": { "text": "ScenarioTag" },
            "valueString": (pRecord.ScenarioTag)
        }]
    }
    Return obs
}

ClassMethod SyncToFHIR(pPatientId As %String) As %Status
{
    Set stmt = ##class(%SQL.Statement).%New()
    Set sc = stmt.%Prepare("SELECT TOP 1 PatientId, PatientName, Status, HospitalCode, ScenarioTag FROM CardioFlow_Analytics.SurgeryStatus WHERE PatientId = ? ORDER BY EventTime DESC")
    If $SYSTEM.Status.IsError(sc) { Return $$$OK }
    Set rs = stmt.%Execute(pPatientId)
    If 'rs.%Next() { Return $$$OK }

    Set record = ##class(CardioFlow.Analytics.SurgeryStatus).%New()
    Set record.PatientId   = rs.%Get("PatientId")
    Set record.PatientName = rs.%Get("PatientName")
    Set record.Status      = rs.%Get("Status")
    Set record.HospitalCode = rs.%Get("HospitalCode")
    Set record.ScenarioTag = rs.%Get("ScenarioTag")

    Do ..PostFHIRResource(..BuildPatient(record))
    Do ..PostFHIRResource(..BuildProcedure(record))
    Do ..PostFHIRResource(..BuildObservation(record))
    Return $$$OK
}

ClassMethod SyncAllToFHIR() As %Status
{
    Write "Syncing all patients to FHIR server...", !
    Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT DISTINCT PatientId FROM CardioFlow_Analytics.SurgeryStatus")
    Set count = 0
    While rs.%Next() {
        Do ..SyncToFHIR(rs.%Get("PatientId"))
        Set count = count + 1
    }
    Write "Synced ", count, " patient(s) to FHIR server.", !
    Return $$$OK
}

ClassMethod PostFHIRResource(pResource As %DynamicObject) As %Status
{
    Try {
        Set httpReq = ##class(%Net.HttpRequest).%New()
        Set httpReq.Server   = "localhost"
        Set httpReq.Port     = 52773
        Set httpReq.Username = $Get(^CardioFlow.Config("FHIR_USERNAME"), "cardioapi")
        Set httpReq.Password = $Get(^CardioFlow.Config("FHIR_PASSWORD"), "Cardio123!")
        Set httpReq.ContentType = "application/fhir+json"
        Do httpReq.SetHeader("Accept", "application/fhir+json")

        Set resourceType = pResource.%Get("resourceType")
        Set resourceId   = pResource.%Get("id")

        Set body = ##class(%Stream.TmpCharacter).%New()
        Do body.Write(pResource.%ToJSON())
        Do httpReq.EntityBody.CopyFrom(body)

        Do httpReq.Put("/fhir/r4/" _ resourceType _ "/" _ resourceId)
    } Catch {
        // FHIR server may not be running; sync is best-effort
    }
    Return $$$OK
}

}
