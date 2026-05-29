Class CardioFlow.UI.DashboardPage Extends %CSP.Page
{

ClassMethod OnPage() As %Status
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
        write "<html><body><h1>Dashboard unavailable</h1><pre>"_$system.Status.GetErrorText(sc)_"</pre></body></html>"
    }
    quit sc
}

}