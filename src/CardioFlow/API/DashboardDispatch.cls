Class CardioFlow.API.DashboardDispatch Extends %CSP.REST
{

Parameter CONTENTTYPE = "application/json";

Parameter CHARSET = "utf-8";

Parameter HandleCorsRequest = 1;

XData UrlMap [ XMLNamespace = "http://www.intersystems.com/urlmap" ]
{
<Routes>
    <Route Url="/dashboard" Method="GET" Call="GetDashboard" Cors="true" />
    <Route Url="/dashboards/overview" Method="GET" Call="GetOverview" Cors="true" />
  <Route Url="/dashboards/preop" Method="GET" Call="GetPreOp" Cors="true" />
  <Route Url="/dashboards/intraop" Method="GET" Call="GetIntraOp" Cors="true" />
  <Route Url="/dashboards/postop" Method="GET" Call="GetPostOp" Cors="true" />
  <Route Url="/dashboards/summary" Method="GET" Call="GetSummary" Cors="true" />
  <Route Url="/patient/:id/status" Method="GET" Call="GetPatient" Cors="true" />
  <Route Url="/health" Method="GET" Call="Health" Cors="true" />
</Routes>
}

ClassMethod GetDashboard() As %Status
{
    set sc = 1
    try {
        set stream = ##class(%Stream.FileCharacter).%New()
        set stream.Filename = "/home/irisowner/dashboard/index.html"
        do stream.Rewind()
        set %response.ContentType = "text/html; charset=utf-8"
        while 'stream.AtEnd {
            write stream.Read(32000)
        }
    } catch ex {
        set sc = ex.AsStatus()
        do ..ReportHttpStatusCode(500, $system.Status.GetErrorText(sc))
    }
    quit sc
}

ClassMethod GetPreOp() As %Status
{
    quit ..WriteQueryAsJson("SELECT PatientId, PatientName, HospitalCode, EventTime, WaitingMinutes, ScenarioTag FROM CardioFlow_Analytics.SurgeryStatus WHERE Status = 'AWAITING' ORDER BY EventTime DESC", "preOp")
}

ClassMethod GetIntraOp() As %Status
{
    quit ..WriteQueryAsJson("SELECT PatientId, PatientName, HospitalCode, EventTime, SurgeryRoom, MedicalTeam, ScenarioTag FROM CardioFlow_Analytics.SurgeryStatus WHERE Status = 'IN_SURGERY' ORDER BY EventTime DESC", "intraOp")
}

ClassMethod GetPostOp() As %Status
{
    quit ..WriteQueryAsJson("SELECT PatientId, PatientName, HospitalCode, EventTime, VitalSignAlerts, ScenarioTag FROM CardioFlow_Analytics.SurgeryStatus WHERE Status = 'POST_OP' ORDER BY EventTime DESC", "postOp")
}

ClassMethod GetOverview() As %Status
{
    quit ..WriteQueryAsJson("SELECT PatientId, PatientName, Status, Source, HospitalCode, EventTime, WaitingMinutes, SurgeryRoom, MedicalTeam, VitalSignAlerts, ScenarioTag FROM CardioFlow_Analytics.SurgeryStatus ORDER BY EventTime DESC", "overview")
}

ClassMethod GetSummary() As %Status
{
    set sc = 1
    try {
        set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT Status, COUNT(*) AS Total FROM CardioFlow_Analytics.SurgeryStatus GROUP BY Status")
        set obj = ##class(%DynamicObject).%New()
        set summary = ##class(%DynamicArray).%New()
        do obj.%Set("summary", summary)
        while rs.%Next() {
            set row = ##class(%DynamicObject).%New()
            do row.%Set("status", rs.%Get("Status"))
            do row.%Set("total", rs.%Get("Total"))
            do summary.%Push(row)
        }
        write obj.%ToJSON()
    } catch ex {
        set sc = ex.AsStatus()
        do ..ReportHttpStatusCode(500, $system.Status.GetErrorText(sc))
    }
    quit sc
}

ClassMethod GetPatient(id As %String) As %Status
{
    set sc = 1
    try {
        set stmt = ##class(%SQL.Statement).%New()
        set status = stmt.%Prepare("SELECT TOP 1 PatientId, PatientName, Status, EventTime, HospitalCode, ScenarioTag FROM CardioFlow_Analytics.SurgeryStatus WHERE PatientId = ? ORDER BY EventTime DESC")
        if $SYSTEM.Status.IsError(status) {
            do ..ReportHttpStatusCode(500, $SYSTEM.Status.GetErrorText(status))
            set sc = status
        } else {
            set rs = stmt.%Execute(id)
            if rs.%Next() {
                set obj = ##class(%DynamicObject).%New()
                do obj.%Set("patientId", rs.%Get("PatientId"))
                do obj.%Set("patientName", rs.%Get("PatientName"))
                do obj.%Set("status", rs.%Get("Status"))
                do obj.%Set("eventTime", rs.%Get("EventTime"))
                do obj.%Set("hospitalCode", rs.%Get("HospitalCode"))
                do obj.%Set("scenarioTag", rs.%Get("ScenarioTag"))
                write obj.%ToJSON()
            } else {
                do ..ReportHttpStatusCode(404, "Patient not found")
            }
        }
    } catch ex {
        set sc = ex.AsStatus()
        do ..ReportHttpStatusCode(500, $system.Status.GetErrorText(sc))
    }
    quit sc
}

ClassMethod Health() As %Status
{
    set obj = ##class(%DynamicObject).%New()
    do obj.%Set("status", "ok")
    do obj.%Set("namespace", $namespace)
    write obj.%ToJSON()
    quit 1
}

ClassMethod WriteQueryAsJson(sql As %String, key As %String) As %Status [ Private ]
{
    set sc = 1
    try {
        set rs = ##class(%SQL.Statement).%ExecDirect(, sql)
        set obj = ##class(%DynamicObject).%New()
        set arr = ##class(%DynamicArray).%New()
        do obj.%Set(key, arr)
        set metadata = rs.%GetMetadata()
        while rs.%Next() {
            set row = ##class(%DynamicObject).%New()
            for i = 1:1:rs.%ResultColumnCount {
                set colName = metadata.columns.GetAt(i).colName
                do row.%Set(colName, rs.%GetData(i))
            }
            do arr.%Push(row)
        }
        write obj.%ToJSON()
    } catch ex {
        set sc = ex.AsStatus()
        do ..ReportHttpStatusCode(500, $system.Status.GetErrorText(sc))
    }
    quit sc
}

}
