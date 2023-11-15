# controlup-prom-metrics

ControlUp-PromMetrics is a PowerShell script that reads ControUp metrics from the ‘ControlUp Monitor’ service running on the local host and serves the metrics in Prometheus format. The metrics can be viewed at ‘http://<hostname>:9182/metrics’. 
In the current version, the script gathers “SessionLatencyAvg”, “UserInputDelay”, and “SessionBandwidth” fields for all the active RDP sessions. 

The query format for gathering sessions:
“Invoke-CUQuery -Scheme main -table SessionsView -where sSessionName like '%RDP%' -Fields sSessionName, sServerName …”

The query format for gathering metrics from each RDP session:
 “Invoke-CUQuery -Scheme main -table SessionsView -where sSessionName like '%$sessionName%' AND sServerName like '%$serverName%' -Fields …”

Log messages are written to the Windows Event log. The script creates a source, “ControlUp-PromMetrics”, in the “Application” channel.

Once a Prometheus server scrapes the metrics from the above endpoint, the user can run PromQL queries to aggregate or display ControUp metric data. For example, avg(SessionBandwidth{sServerName=~".*VDI.*"})
gets an average ‘SessionBandwidth’ value for all active RDP sessions of servers containing “VDI” in their names.
