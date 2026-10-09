<#
.SYNOPSIS
Times the Windows banner on this host, probe by probe. Changes nothing.

.DESCRIPTION
Answers "why does a login take seconds here?". Run it on the host:

    powershell -NoProfile -ExecutionPolicy Bypass -File Measure-ManatechBanner.ps1

It loads ManatechBanner.psm1 (-ModulePath; default the installed copy in
C:\ProgramData\Manatech) and times each step -Runs times (default 3). The
first run pays for cold caches (the WMI providers, modules loaded on first
use, the data files); a login is always a first run, in a new process. The
others show what stays once those are warm. In this order:

- the module's own calls, end to end, as a login makes them:
  Import-Module, Get-ManatechConfig, Get-ManatechHostFact,
  Format-ManatechBanner;
- each probe Get-ManatechHostFact makes ("probe:"), when the module has
  them as functions of their own (from 2026-10-03);
- the calls an older module made instead ("old:"), so one run on a host
  shows what an update saves there.

Prints the host's size (cores, services, interfaces), one row per step with
the first run, the median of the others and the slowest, then this host's
stopped Auto services: whether each is trigger-start or delayed, ignored,
and so reported by the banner.

.PARAMETER DataPath
Where the art and data files are; default beside the module, which is
where Install-ManatechBanner.ps1 puts them. For a clone of the repo:
<clone>\rootfs\usr\local\share\manatech.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File \\ad.example\NETLOGON\MOTD\windows\Measure-ManatechBanner.ps1
#>
[CmdletBinding()]
param(
    [string]$ModulePath = (Join-Path $env:ProgramData 'Manatech\ManatechBanner.psm1'),
    [string]$DataPath,
    [ValidateRange(1, 20)][int]$Runs = 3
)
Set-StrictMode -Version 3.0

$ModulePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($ModulePath)
if (-not (Test-Path -LiteralPath $ModulePath)) { throw "$ModulePath not found: pass -ModulePath (and -DataPath for a clone)" }
if (-not $DataPath) { $DataPath = Split-Path -Parent $ModulePath }
$DataPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($DataPath)

$results = [System.Collections.Generic.List[object]]::new()

# Measure-Step NAME BLOCK - run BLOCK $Runs times and keep a row: the first
# run, the median of the later ones, the slowest, and the last error.
function Measure-Step {
    param([string]$Name, [scriptblock]$Block)
    $times = [System.Collections.Generic.List[double]]::new()
    $err = ''
    for ($i = 0; $i -lt $Runs; $i++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try { $null = & $Block } catch { $err = $_.Exception.Message }
        $sw.Stop()
        $times.Add($sw.Elapsed.TotalMilliseconds)
    }
    $later = @($times | Select-Object -Skip 1 | Sort-Object)
    $median = if ($later.Count) { $later[[int][math]::Floor(($later.Count - 1) / 2)] } else { $times[0] }
    $results.Add([pscustomobject]@{ Step = $Name; First = $times[0]; Median = $median; Max = ($times | Measure-Object -Maximum).Maximum; Note = $err })
}

# Native tools write to stderr in ordinary cases (quser with nobody logged
# on); that is not an error for this purpose.
function Invoke-Quiet { param([string]$FilePath, [string[]]$ArgumentList = @()) $ErrorActionPreference = 'Continue'; & $FilePath @ArgumentList 2>$null }

# ---- the module, end to end, as a login runs it (cold first) ----
Measure-Step 'module: Import-Module' { Import-Module -Name $ModulePath -Force }
$module = Import-Module -Name $ModulePath -Force -PassThru
Measure-Step 'module: Get-ManatechConfig' { Get-ManatechConfig -DataPath $DataPath }
$config = Get-ManatechConfig -DataPath $DataPath
Measure-Step 'module: Get-ManatechHostFact (every probe below)' { Get-ManatechHostFact -Config $config }
$fact = Get-ManatechHostFact -Config $config
Measure-Step 'module: Format-ManatechBanner (drawing only)' { Format-ManatechBanner -Fact $fact -Config $config -DataPath $DataPath }

# ---- each probe the module makes; they run inside the module, where they live ----
$hasProbes = [bool](& $module { Get-Command -Name Get-ManatechInterface -CommandType Function -ErrorAction SilentlyContinue })
Measure-Step 'probe: CIM Win32_OperatingSystem' { Get-CimInstance -ClassName Win32_OperatingSystem }
Measure-Step 'probe: CIM Win32_ComputerSystem' { Get-CimInstance -ClassName Win32_ComputerSystem }
Measure-Step 'probe: quser.exe (sessions)' { Invoke-Quiet quser.exe }
Measure-Step "probe: Get-Service, Watch ($(@($config.Watch) -join ' '))" { foreach ($s in $config.Watch) { Get-Service -Name $s -ErrorAction SilentlyContinue } }
Measure-Step 'probe: w32tm /query /status' { Invoke-Quiet w32tm.exe '/query', '/status' }
Measure-Step 'probe: registry, build revision and reboot-pending keys' {
    Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
}
if ($hasProbes) {
    Measure-Step 'probe: cpu, one raw counter sample (a login takes two)' { & $module { Get-ManatechCpuSample } }
    Measure-Step 'probe: disks, .NET DriveInfo' { [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } }
    Measure-Step 'probe: interfaces, .NET (Get-ManatechInterface)' { & $module { param($c) Get-ManatechInterface -Hide $c.IfaceHide } $config }
    Measure-Step 'probe: primary IPv4, UDP route lookup (Get-ManatechPrimaryIp)' { & $module { Get-ManatechPrimaryIp } }
    Measure-Step 'probe: stopped services, .NET (Get-ManatechStoppedService)' { & $module { param($c) Get-ManatechStoppedService -Ignore $c.ServiceIgnore } $config }
}

# ---- what a module from before 2026-10-03 called instead ----
Measure-Step 'old: cpu %, Win32_Processor LoadPercentage' { Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property LoadPercentage -Average }
Measure-Step 'old: disks, CIM Win32_LogicalDisk twice' {
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'"
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3'
}
Measure-Step 'old: interfaces, Get-NetIPAddress and Get-NetRoute' {
    Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue
    $r = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object -Property { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
    if ($r) { Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $r.InterfaceIndex -ErrorAction SilentlyContinue }
}
Measure-Step 'old: stopped services, CIM Win32_Service' { Get-CimInstance -ClassName Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" }

# ---- report ----
Add-Type -AssemblyName System.ServiceProcess
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
$services = @([System.ServiceProcess.ServiceController]::GetServices())
$ifaces = @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Where-Object { $_.OperationalStatus -eq 'Up' })
''
"host {0}: {1}, build {2}; {3} logical cores; {4} services; {5} interfaces up; PowerShell {6}; {7} runs per step; module probes: {8}" -f $env:COMPUTERNAME, ($os.Caption -replace '^Microsoft ', ''), $os.BuildNumber, $cs.NumberOfLogicalProcessors, $services.Count, $ifaces.Count, $PSVersionTable.PSVersion, $Runs, $(if ($hasProbes) { 'yes' } else { 'no (an older module: only the old: rows apply to it)' })
''
'{0,-66} {1,9} {2,9} {3,9}  {4}' -f 'step (ms)', 'first', 'median', 'max', 'error'
foreach ($r in ($results | Sort-Object -Property Median -Descending)) {
    '{0,-66} {1,9:N0} {2,9:N0} {3,9:N0}  {4}' -f $r.Step, $r.First, $r.Median, $r.Max, $r.Note
}

''
'Stopped Auto services here, and whether the banner reports them:'
$byDesign = @(& $module { if (Get-Variable -Name ServiceStopsByDesign -Scope Script -ErrorAction SilentlyContinue) { $script:ServiceStopsByDesign } })
$any = $false
foreach ($s in ($services | Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } | Sort-Object -Property ServiceName)) {
    $any = $true
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.ServiceName)"
    $trigger = Test-Path -LiteralPath (Join-Path $key 'TriggerInfo')
    $delayed = $false
    $item = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    if ($item -and $item.PSObject.Properties['DelayedAutostart']) { $delayed = [int]$item.DelayedAutostart -eq 1 }
    $ignored = if ($byDesign -contains $s.ServiceName) { 'by design' } elseif (@($config.ServiceIgnore) -contains $s.ServiceName) { 'ServiceIgnore' } else { 'no' }
    $reported = if ($hasProbes) { -not $trigger -and $ignored -eq 'no' } else { $ignored -eq 'no' }
    '  {0,-26} reported: {1,-5}  trigger-start: {2,-5}  delayed: {3,-5}  ignored: {4,-13} {5}' -f $s.ServiceName, $reported, $trigger, $delayed, $ignored, $s.DisplayName
}
if (-not $any) { '  (none)' }
