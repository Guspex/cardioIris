Class CardioFlow.Sim.Runner Extends %RegisteredObject
{

ClassMethod Reset() As %Status
{
    set sc = 1
    try {
        do ##class(%SQL.Statement).%ExecDirect(, "DELETE FROM CardioFlow_Analytics.SurgeryStatus")
    } catch ex {
        set sc = ex.AsStatus()
    }
    quit sc
}

ClassMethod RunAll() As %Status
{
    set sc = ..Reset()
    if $SYSTEM.Status.IsError(sc) quit sc

    set sc = ..InsertSample("PAT001", "AWAITING", "HL7", "James Wilson", "BOSTON-HEART", "HOLD-01", 45, "EMERGENCY_ESCALATION", "[]", "[]")
    if $SYSTEM.Status.IsError(sc) quit sc

    set sc = ..InsertSample("PAT002", "AWAITING", "HL7", "Emma Carter", "CHICAGO-CARDIAC", "TRIAGE-02", 80, "DELAYED_SURGERY", "[]", "[]")
    if $SYSTEM.Status.IsError(sc) quit sc

    set sc = ..InsertSample("PAT003", "AWAITING", "FHIR", "Noah Brooks", "SEATTLE-MED", "TRIAGE-05", 15, "RECOVERY_ESCALATION", "[]", "[]")
    if $SYSTEM.Status.IsError(sc) quit sc

    set sc = ..InsertSample("FHIR-TEST-001", "IN_SURGERY", "FHIR", "Olivia Stone", "BOSTON-HEART", "VALVE-REPAIR", 10, "EMERGENCY_ESCALATION", "[""Dr. Harper"",""Nurse Cole""]", "[]")
    if $SYSTEM.Status.IsError(sc) quit sc

    set sc = ..InsertSample("PAT010", "IN_SURGERY", "SIM", "Ethan Clark", "CHICAGO-CARDIAC", "OR-03", 5, "DELAYED_SURGERY", "[""Dr. Bennett"",""Nurse Flores""]", "[]")
    if $SYSTEM.Status.IsError(sc) quit sc

    set sc = ..InsertSample("PAT011", "IN_SURGERY", "HL7", "Sophia Reed", "SEATTLE-MED", "OR-07", 0, "RECOVERY_ESCALATION", "[""Dr. Warren"",""Perfusionist Hayes""]", "[]")
    if $SYSTEM.Status.IsError(sc) quit sc

    set sc = ..InsertSample("FHIR-TEST-001", "POST_OP", "SIM", "Olivia Stone", "BOSTON-HEART", "RECOVERY", 0, "EMERGENCY_ESCALATION", "[]", "[""Blood pressure unstable"",""SpO2 under observation""]")
    if $SYSTEM.Status.IsError(sc) quit sc

    set sc = ..InsertSample("PAT020", "POST_OP", "FHIR", "Ava Morgan", "CHICAGO-CARDIAC", "RECOVERY-04", 0, "DELAYED_SURGERY", "[]", "[""Mild chest pain""]")
    if $SYSTEM.Status.IsError(sc) quit sc

    set sc = ..InsertSample("PAT021", "POST_OP", "HL7", "Liam Turner", "SEATTLE-MED", "ICU-02", 0, "RECOVERY_ESCALATION", "[]", "[""Escalated neuro checks""]")
    quit sc
}

ClassMethod InsertSample(patientId As %String, status As %String, source As %String, patientName As %String, hospitalCode As %String, surgeryRoom As %String, waitingMinutes As %Integer = 0, scenarioTag As %String = "STANDARD_FLOW", medicalTeam As %String = "[]", vitalSignAlerts As %String = "[]") As %Status
{
    set sc = 1
    try {
        set row = ##class(CardioFlow.Analytics.SurgeryStatus).%New()
        set row.PatientId = patientId
        set row.Status = status
        set row.Source = source
        set row.EventTime = $zdt($h, 3)
        set row.PatientName = patientName
        set row.HospitalCode = hospitalCode
        set row.WaitingMinutes = waitingMinutes
        set row.SurgeryRoom = surgeryRoom
        set row.ScenarioTag = scenarioTag
        set row.MedicalTeam = medicalTeam
        set row.VitalSignAlerts = vitalSignAlerts
        set sc = row.%Save()
    } catch ex {
        set sc = ex.AsStatus()
    }
    quit sc
}

ClassMethod SummaryText() As %String
{
    set output = ""
    set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status, COUNT(*) AS Total FROM CardioFlow_Analytics.SurgeryStatus GROUP BY Status ORDER BY Status")
    while rs.%Next() {
        set output = output _ rs.%Get("Status") _ ": " _ rs.%Get("Total") _ "; "
    }
    quit output
}

}