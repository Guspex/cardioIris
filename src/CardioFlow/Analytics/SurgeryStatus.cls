Class CardioFlow.Analytics.SurgeryStatus Extends %Persistent
{

Property PatientId As %String(MAXLEN = 64) [ Required ];

Property Status As %String(MAXLEN = 32, VALUELIST = ",AWAITING,IN_SURGERY,POST_OP") [ Required ];

Property Source As %String(MAXLEN = 16);

Property EventTime As %TimeStamp;

Property PatientName As %String(MAXLEN = 256);

Property HospitalCode As %String(MAXLEN = 64);

Property WaitingMinutes As %Integer;

Property SurgeryRoom As %String(MAXLEN = 32);

Property ScenarioTag As %String(MAXLEN = 64) [ InitialExpression = "STANDARD_FLOW" ];

Property MedicalTeam As %String(MAXLEN = 512) [ InitialExpression = "[]" ];

Property VitalSignAlerts As %String(MAXLEN = 1024) [ InitialExpression = "[]" ];

Index StatusIdx On Status;

Index PatientIdx On PatientId;

Index ScenarioIdx On ScenarioTag;

Index EventTimeIdx On EventTime;

Index StatusEventIdx On (Status, EventTime);

}

