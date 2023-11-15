# Create the event log source. Log messages will be written to the Windows Event Log
$Source = "ControlUp-PromMetrics"
$logName = "Application"

# Check if the source already exists
if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
    # Create a new source
    [System.Diagnostics.EventLog]::CreateEventSource($source, $logName)
    Write-Host "Event source $source created."
} else {
    Write-Host "Event source $source already exists."
}

# Function to log messages to the Windows Event Log
function Log-Event {
    param(
        [string]$Message,
        [System.Diagnostics.EventLogEntryType]$EntryType = [System.Diagnostics.EventLogEntryType]::Information,
        [int]$EventId = 1000
    )
    Write-EventLog -LogName Application -Source $Source -EntryType $EntryType -EventId $EventId -Message $Message
}

# Set the output encoding to ASCII to avoid encoding issues
[Console]::OutputEncoding = [System.Text.Encoding]::ASCII

# Install ControlUp cmdlets
try {
    # ... ControlUp cmdlets installation ...
    $pathToUserModule = (Get-ChildItem "C:\Program Files\Smart-X\ControlUpMonitor\*ControlUp.PowerShell.User.dll" -Recurse | Sort-Object LastWriteTime -Descending)[0]
    $pathToMonitorModule = (Get-ChildItem "C:\Program Files\Smart-X\ControlUpMonitor\*ControlUp.PowerShell.Monitor.dll" -Recurse | Sort-Object LastWriteTime -Descending)[0]
    Import-Module $pathToUserModule, $pathToMonitorModule
    Log-Event -Message "ControlUp cmdlets loaded successfully."
} catch {
    Log-Event -Message "Error loading ControlUp cmdlets: $_" -EntryType Error
}

# Define the port to listen on
$port = 9182
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://*:$port/metrics/")
$listener.Start()

function Get-MetricsForSession($session) {
    try {
        $sessionName = $session.sSessionName
        $serverName = $session.sServerName

        # Log the start of data retrieval for the session
        # Log-Event -Message "Starting data retrieval for Session: $sessionName, Server: $serverName"

        # Make a single Invoke-CUQuery call requesting multiple fields
        $whereClause = "sSessionName like '%$sessionName%' AND sServerName like '%$serverName%'"
        $queryResult = (Invoke-CUQuery -Scheme main -table SessionsView -where $whereClause -Fields SessionLatencyAvg, UserInputDelay, SessionBandwidth -TranslateEnums | Select-Object -ExpandProperty data)

        # Check if queryResult is valid
        if ($queryResult) {
            # Assuming $queryResult returns a PSObject with properties for each metric
            $SessionLatencyAvg = $queryResult.SessionLatencyAvg
            $UserInputDelay = $queryResult.UserInputDelay
            $SessionBandwidth = $queryResult.SessionBandwidth

            # Log successful data retrieval
            # Log-Event -Message "Successfully retrieved data for Session: $sessionName, Server: $serverName"

            # Construct and return the metrics string
            return @"
# HELP UserInputDelay User Input Delay in milliseconds for $serverName .
# TYPE UserInputDelay gauge
UserInputDelay{sServerName="$serverName"} $UserInputDelay

# HELP SessionBandwidth Session Bandwidth in mbps for $serverName .
# TYPE SessionBandwidth gauge
SessionBandwidth{sServerName="$serverName"} $SessionBandwidth

# HELP SessionLatencyAvg Average Session Latency in milliseconds for $serverName .
# TYPE SessionLatencyAvg gauge
SessionLatencyAvg{sServerName="$serverName"} $SessionLatencyAvg

# END

"@ -replace "`r", ""
        } else {
            # Log warning if no data is returned
            Log-Event -Message "No data returned for Session: $sessionName, Server: $serverName" -EntryType Warning
        }
    } catch {
        # Log any exceptions that occur
        Log-Event -Message "Error occurred in Get-MetricsForSession for Session: $sessionName, Server: $serverName. Error: $_" -EntryType Error
    }
}


# Start the listener
Log-Event -Message "Listening on port $port for Prometheus scrapes..."
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $response = $context.Response
	
        # Gather session names
        $whereClause = "sSessionName like '%RDP%'"
        $queryResult = (Invoke-CUQuery -Scheme main -table SessionsView -where $whereClause -Fields sSessionName, sServerName -TranslateEnums | select -ExpandProperty data)

        # Create a StringBuilder object
        $stringBuilder = New-Object System.Text.StringBuilder

        # Iterate through each row of the query result
        foreach ($row in $queryResult) {
            # Gather the metrics for each session and format the data as Prometheus metrics
            $sessionMetrics = Get-MetricsForSession($row)
            [void]$stringBuilder.Append($sessionMetrics)  
        }

        # Convert the StringBuilder to a string
        $metrics = $stringBuilder.ToString()

        # Write the data to the response
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($metrics)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)

        # Close the response to send it to the client
        $response.Close()
    }

} catch {
    Log-Event -Message "Error occurred in listener loop: $_" -EntryType Error
} finally {
    # Clean up by stopping the listener if it's not already closed.
    if ($listener) {
        try {
            $listener.Stop()
            Log-Event -Message "Listener stopped."
        } catch {
            Log-Event -Message "Error stopping listener: $_" -EntryType Error
        }
        try {
            $listener.Close()
            Log-Event -Message "Listener closed."
        } catch {
            Log-Event -Message "Error closing listener: $_" -EntryType Error
        }
    }
}
