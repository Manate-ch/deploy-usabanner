# WindowsHealth.Logged.ps1 - the functions of WindowsHealth.ps1 that PowerShell logs whole at each import (D30).

function Get-UsaBannerWinServiceList {
    <#
    .SYNOPSIS
    Every service on this Windows host, as the service manager lists it.
    .DESCRIPTION
    Out: @(@{ Name; Status; StartType }): the service's name, and its state
         and start type as words (Running, Stopped; Automatic, Manual). The
         start type only for a service not running: reading it asks the
         service manager once more for each service, and only a stopped one
         is judged by it. Through .NET, not Win32_Service, as today's banner
         reads them: in a third of the time. Nothing when the service
         manager cannot be asked.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    try {
        Add-Type -AssemblyName System.ServiceProcess -ErrorAction Stop
        $all = [System.ServiceProcess.ServiceController]::GetServices()
    }
    catch { return }
    foreach ($service in $all) {
        $status = [string]$service.Status
        @{ Name = $service.ServiceName; Status = $status; StartType = $(if ($status -ne 'Running') { [string]$service.StartType } else { '' }) }
    }
}
