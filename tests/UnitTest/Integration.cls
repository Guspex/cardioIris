Class Test.CardioFlow.Integration Extends %UnitTest.TestCase
{

Include %occStatus

Method TestFHIRFlow() As %Status
{
    set sc = $$$OK
    try {
        set req = ##class(CardioFlow.Msg.FHIRRequest).%New()
        do req.Payload.Write("{""resourceType"":""Bundle"",""entry"":[{""resource"":{""resourceType"":""Patient"",""id"":""FHIR-PAT-001"",""name"":[{""family"":""Costa"",""given"":[""Maria""]}],""birthDate"":""1975-03-22"",""gender"":""female""}},{""resource"":{""resourceType"":""Encounter"",""status"":""planned""}},{""resource"":{""resourceType"":""Procedure"",""id"":""PROC-001"",""code"":{""coding"":[{""code"":""CABG"",""display"":""Bypass Cardiaco""}]}}}]")
        set container = ##class(HS.SDA3.Container).%New()
        set sc = ##class(CardioFlow.DTL.FHIRToSDA3).Transform(req, .container)
        $$$ThrowOnError(sc)
        do ..AssertEquals("FHIR-PAT-001", container.Patient.PatientNumbers.GetAt(1).Number)
        do ..AssertEquals("PRE", container.Encounters.GetAt(1).AdmissionType.Code)
        do ..AssertEquals("CABG", container.Procedures.GetAt(1).Procedure.Code)
    } catch ex {
        set sc = ex.AsStatus()
    }
    quit sc
}

Method TestHL7Flow() As %Status
{
    set sc = $$$OK
    try {
        set hl7 = ##class(EnsLib.HL7.Message).%New()
        do hl7.ImportFromString("MSH|^~\&|HIS|HOSPITAL|CARDIOFLOW|IRIS|20240101120000||ADT^A08|MSG001|P|2.5"_$c(13)_"PID|1||PAT001^^^HOSPITAL^MR||Silva^Joao||19800515|M"_$c(13)_"PV1|1|I|CARDIO^01^A|||||||CARDT|||||||ADM|V01|PRE")
        set container = ##class(HS.SDA3.Container).%New()
        set sc = ##class(CardioFlow.DTL.HL7ToSDA3).Transform(hl7, .container)
        $$$ThrowOnError(sc)
        do ..AssertEquals("PAT001", container.Patient.PatientNumbers.GetAt(1).Number)
        do ..AssertEquals("PRE", container.Encounters.GetAt(1).AdmissionType.Code)
    } catch ex {
        set sc = ex.AsStatus()
    }
    quit sc
}

Method TestStatusPersistence() As %Status
{
    set sc = $$$OK
    try {
        set tracker = ##class(CardioFlow.Analytics.SurgeryStatus).%New()
        set tracker.PatientId = "STATUS-TEST-001"
        set tracker.Status = "AWAITING"
        set tracker.Source = "TEST"
        set tracker.EventTime = $zdt($h, 3)
        set sc = tracker.%Save()
        $$$ThrowOnError(sc)
        set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT TOP 1 Status FROM CardioFlow_Analytics.SurgeryStatus WHERE PatientId='STATUS-TEST-001'")
        do ..AssertTrue(rs.%Next())
        do ..AssertEquals("AWAITING", rs.%Get("Status"))
    } catch ex {
        set sc = ex.AsStatus()
    }
    quit sc
}

}
