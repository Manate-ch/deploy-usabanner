# WindowsHealth.ps1 - a Windows host's health lines (docs/DECISIONS.md, D10):
# a problem for each thing wrong, the checks that ran, and the panel's
# services row, in the forms linux/facts.sh gives them on Linux. Each probe
# is a function of its own, so a test can stand in for it on any OS.

# Automatic services that stop by design, left out on every host, as today's
# banner leaves them out (windows/ManatechBanner.psm1). Most are started by a
# trigger, which the sweep leaves out anyway; InventorySvc is delayed-start
# and was stopped on every Server 2025 host checked, healthy lab nodes
# included (2026-10-03).
$script:UsaStopsByDesign = @('InventorySvc', 'gupdate', 'edgeupdate', 'sppsvc', 'RemoteRegistry', 'MapsBroker', 'CDPSvc', 'tiledatamodelsvc', 'WbioSrvc')

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

function Test-UsaBannerWinTriggerStart {
    <#
    .SYNOPSIS
    Whether a trigger starts a service: Windows starts it when the trigger
    fires, and may stop it again when it is idle.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Name)
    Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$Name\TriggerInfo"
}

function Get-UsaBannerWinTimeSource {
    <#
    .SYNOPSIS
    Where the Windows Time service takes the time from, as w32tm says.
    .DESCRIPTION
    Out: @{ Answered; Source }: whether the service answered
         w32tm /query /status, and the source it names, $null when no line
         names one (w32tm writes in the host's language). $null without
         w32tm.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $w32tm = @(Get-Command -Name w32tm.exe -CommandType Application -ErrorAction SilentlyContinue)
    if (-not $w32tm.Count) { return $null }
    $lines = @(& $w32tm[0].Source /query /status 2>$null)
    if ($LASTEXITCODE -ne 0) { return @{ Answered = $false; Source = $null } }
    $source = $null
    foreach ($line in $lines) {
        if ($line -match '^Source:\s*(.+)$') {
            $source = $Matches[1].Trim()
            break
        }
    }
    @{ Answered = $true; Source = $source }
}

function Add-UsaBannerWinHealth {
    <#
    .SYNOPSIS
    Fills in a Windows host's health: the problems, the checks that ran and
    the services row, as linux/facts.sh gives them.
    .DESCRIPTION
    In:  the facts, with their disks, memory and reboot; every service as
         Get-UsaBannerWinServiceList gives them, none when the service
         manager did not answer; the clock as Get-UsaBannerWinTimeSource
         gives it; -Services, the configuration's: default, or the names;
         whether the host is in a domain; and -Ignore, more services the
         sweep leaves out, the host's own list (D10).
    Out: nothing. Problems, Checked and Services join the facts, a check
         named only when it ran:
         - auto-start: the automatic services stopped, less those that stop
           by design, those a trigger starts, and -Ignore;
         - services: the services watched, D10's sshd and W32Time, and
           Netlogon in a domain, else the names: one stopped or not found is
           bad; one stopped that a trigger starts is on demand;
         - the disks from 85% full and the memory from 90% in use, each bad
           from 95%, the panel's levels;
         - clock: the Windows Time service not answering, or naming the CMOS
           clock or a free-running one as its source; not named when w32tm
           names no source in a language this reads;
         - reboot: one pending.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Facts,
        [AllowEmptyCollection()][System.Collections.IDictionary[]]$ServiceList = @(),
        [System.Collections.IDictionary]$TimeSource,
        [object]$Services = 'default',
        [bool]$PartOfDomain,
        [AllowEmptyCollection()][string[]]$Ignore = @()
    )
    $problems = [System.Collections.Generic.List[hashtable]]::new()
    $checks = [System.Collections.Generic.List[string]]::new()
    $byName = @{}
    foreach ($service in $ServiceList) { $byName[[string]$service.Name] = $service }

    if ($ServiceList.Count) {
        $skip = @($script:UsaStopsByDesign) + @($Ignore)
        $stopped = @(foreach ($service in $ServiceList) {
                if ($service.StartType -ne 'Automatic' -or $service.Status -eq 'Running' -or $skip -contains $service.Name) { continue }
                if (Test-UsaBannerWinTriggerStart -Name $service.Name) { continue }
                [string]$service.Name
            })
        if ($stopped.Count) {
            $plural = if ($stopped.Count -eq 1) { '' } else { 's' }
            $problems.Add(@{ Level = 'bad'; Text = "$($stopped.Count) automatic service$plural stopped: $($stopped -join ', ')" })
        }
        $checks.Add('auto-start')
    }

    $watch = @(if ($Services -is [System.Collections.IEnumerable] -and $Services -isnot [string]) { $Services }
        elseif ($Services -and [string]$Services -ne 'default') { [string]$Services }
        else { 'sshd'; 'W32Time'; if ($PartOfDomain) { 'Netlogon' } })
    if ($watch.Count -and $ServiceList.Count) {
        $up = [System.Collections.Generic.List[string]]::new()
        $idle = [System.Collections.Generic.List[string]]::new()
        $down = [System.Collections.Generic.List[string]]::new()
        foreach ($name in $watch) {
            $service = $byName[[string]$name]
            if (-not $service) {
                $down.Add("$name not found")
                $problems.Add(@{ Level = 'bad'; Text = "service $name not found" })
            }
            elseif ($service.Status -eq 'Running') { $up.Add($name) }
            elseif (Test-UsaBannerWinTriggerStart -Name $service.Name) { $idle.Add($name) }
            else {
                $state = ([string]$service.Status -creplace '(?<!^)(?=[A-Z])', ' ').ToLowerInvariant()
                $down.Add("$name $state")
                $problems.Add(@{ Level = 'bad'; Text = "$name is $state" })
            }
        }
        $parts = @(
            if ($down.Count) { $down -join ', ' }
            if ($up.Count) { ($up -join ', ') + ' running' }
            if ($idle.Count) { ($idle -join ', ') + ' on demand' }
        )
        $Facts['Services'] = @{ Text = $parts -join '; '; Level = $(if ($down.Count) { 'bad' } else { 'good' }) }
        $checks.Add('services')
    }

    $level = {
        # In:  a percentage, and the one it warns from
        # Out: bad from 95, warn from the one given, else nothing
        # Why: the disks and the memory share the panel's levels
        param([int]$Percent, [int]$WarnFrom)
        if ($Percent -ge 95) { 'bad' } elseif ($Percent -ge $WarnFrom) { 'warn' }
    }
    $disks = @(@($Facts['Disks']) | Where-Object { $_ -and $null -ne $_.Pct })
    foreach ($disk in $disks) {
        $diskLevel = & $level $disk.Pct 85
        if ($diskLevel) { $problems.Add(@{ Level = $diskLevel; Text = "$($disk.Name) is $($disk.Pct)% full" }) }
    }
    if ($disks.Count) { $checks.Add('disks <85%') }
    $memory = $Facts['Memory']
    if ($memory -and $null -ne $memory.Pct) {
        $memoryLevel = & $level $memory.Pct 90
        if ($memoryLevel) { $problems.Add(@{ Level = $memoryLevel; Text = "memory $($memory.Pct)% in use" }) }
        $checks.Add('memory')
    }

    if ($TimeSource) {
        if (-not $TimeSource.Answered) {
            $problems.Add(@{ Level = 'warn'; Text = 'Windows Time is not answering' })
            $checks.Add('clock')
        }
        elseif ($TimeSource.Source) {
            if ($TimeSource.Source -match 'Local CMOS Clock|Free-running System Clock') { $problems.Add(@{ Level = 'warn'; Text = "clock is not synchronised (source: $($TimeSource.Source))" }) }
            $checks.Add('clock')
        }
    }

    $reboot = $Facts['Reboot']
    if ($reboot) {
        if ([string]$reboot.Level -eq 'warn') { $problems.Add(@{ Level = 'warn'; Text = "reboot $($reboot.Text)" }) }
        $checks.Add('reboot')
    }

    if ($problems.Count) { $Facts['Problems'] = $problems.ToArray() }
    if ($checks.Count) { $Facts['Checked'] = $checks.ToArray() }
}
