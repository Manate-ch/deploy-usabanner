# WindowsFacts.ps1 - a Windows host's facts for its banners (docs/DECISIONS.md,
# D26): the facts hashtable PostLogin.ps1 draws, with the facts linux/facts.sh
# gives a Linux host, in the same forms. Each probe is a function of its own,
# so a test can stand in for it on any OS. The probes are today's
# (windows/ManatechBanner.psm1), each chosen there by timing a fresh process
# on a lab Server 2025 node, which is what every login is.
#
# Get-UsaBannerWinSystem and Get-UsaBannerWinInterface, which PowerShell logs
# whole at each import, are in WindowsFacts.Logged.ps1 (docs/DECISIONS.md, D30).

function Get-UsaBannerWinCpuSample {
    <#
    .SYNOPSIS
    The raw counters behind the processors' busy percentage.
    .DESCRIPTION
    Out: @{ Idle; Clock; Own }, in 100 ns units: the processors' idle time
         (PERF_100NSEC_TIMER_INV, averaged over all of them for _Total), the
         counter's clock, and this process's own processor time. $null when
         the performance counters cannot be read.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $sample = Get-CimInstance -ClassName Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
    if (-not $sample) { return $null }
    @{
        Idle  = [double]$sample.PercentProcessorTime
        Clock = [double]$sample.Timestamp_Sys100NS
        Own   = [double][System.Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.Ticks
    }
}

function Get-UsaBannerWinCpuPercent {
    <#
    .SYNOPSIS
    How busy the processors were between two samples, in whole percent.
    .DESCRIPTION
    Less what this process used meanwhile: it should be idle in the window,
    and this keeps a stray .NET background thread from counting. $null
    without two samples, a clock that moved, or a core count.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([System.Collections.IDictionary]$From, [System.Collections.IDictionary]$To, [int]$Cores)
    if ($null -eq $From -or $null -eq $To -or $Cores -lt 1) { return $null }
    $span = $To.Clock - $From.Clock
    if ($span -le 0) { return $null }
    $busy = 1 - ($To.Idle - $From.Idle) / $span
    $own = ($To.Own - $From.Own) / ($span * $Cores)
    # 1.0 and 0.0, not 1 and 0: an integer first argument makes PowerShell
    # pick Math.Min(int, int), which truncates 0.016 to 0.
    [int][Math]::Round(100 * [Math]::Min(1.0, [Math]::Max(0.0, $busy - $own)))
}

function ConvertFrom-UsaBannerQuser {
    <#
    .SYNOPSIS
    Whose each session is that quser lists.
    .DESCRIPTION
    In:  quser's lines, its header first.
    Out: a user's name per session, in quser's order. The current session's
         line starts with >, and a disconnected one has no session name: the
         name is the first word either way.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string[]]$Line = @())
    foreach ($session in @($Line | Select-Object -Skip 1)) {
        $user = (($session.Trim() -replace '^>', '') -split '\s+')[0]
        if ($user) { $user }
    }
}

function Get-UsaBannerWinSession {
    <#
    .SYNOPSIS
    The sessions quser lists: console and Remote Desktop logons.
    .DESCRIPTION
    Out: a user's name per session. An SSH logon is not a Remote Desktop
         session, so quser does not list it. None when quser is missing, or
         lists no one: it says "No User exists for *" and exits 1.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $quser = @(Get-Command -Name quser.exe -CommandType Application -ErrorAction SilentlyContinue)
    if (-not $quser.Count) { return }
    ConvertFrom-UsaBannerQuser -Line @(& $quser[0].Source 2>$null)
}

function Select-UsaBannerInterface {
    <#
    .SYNOPSIS
    The adapters the banner lists.
    .DESCRIPTION
    In:  adapters as Get-UsaBannerWinInterface gives them, and -Hide, a regex
         of adapter names to leave out.
    Out: @{ Name; Address = 'a.b.c.d/n ...' } for each adapter that is up and
         keeps an address. Loopback, tunnel and PPP adapters (dial-up VPNs)
         are left out, and so are loopback and link-local addresses.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([System.Collections.IDictionary[]]$Interface = @(), [string]$Hide)
    foreach ($nic in $Interface) {
        if (-not $nic.Up -or $nic.Type -in 'Loopback', 'Tunnel', 'Ppp') { continue }
        if ($Hide -and $nic.Name -match $Hide) { continue }
        $addresses = @($nic.Addresses | Where-Object { $_ -notmatch '^(127\.|169\.254\.)' })
        if ($addresses.Count) { @{ Name = $nic.Name; Address = $addresses -join ' ' } }
    }
}

function Get-UsaBannerPrimaryIp {
    <#
    .SYNOPSIS
    The IPv4 address this host sends from on its default route.
    .DESCRIPTION
    A UDP socket asked to "connect" consults the routing table and sends
    nothing (192.0.2.1 is a documentation address). '' with no route.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $socket = [System.Net.Sockets.Socket]::new([System.Net.Sockets.AddressFamily]::InterNetwork, [System.Net.Sockets.SocketType]::Dgram, [System.Net.Sockets.ProtocolType]::Udp)
    try {
        $socket.Connect('192.0.2.1', 9)
        [string]$socket.LocalEndPoint.Address
    }
    catch { '' }
    finally { $socket.Dispose() }
}

function Get-UsaBannerWinDrive {
    <#
    .SYNOPSIS
    This host's drives, as .NET sees them.
    .DESCRIPTION
    Out: @(@{ Name = 'C:'; Type; Ready; Size; Free }), Size and Free in
         bytes; 0 for a drive that is not ready, whose size cannot be read.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        $ready = $drive.IsReady
        @{
            Name  = $drive.Name.TrimEnd('\')
            Type  = [string]$drive.DriveType
            Ready = $ready
            Size  = $(if ($ready) { [double]$drive.TotalSize } else { 0 })
            Free  = $(if ($ready) { [double]$drive.TotalFreeSpace } else { 0 })
        }
    }
}

function Format-UsaBannerUptime {
    <#
    .SYNOPSIS
    An uptime as the banner shows it.
    .DESCRIPTION
    In whole minutes, cut, as linux/facts.sh gives it: 12d 6h 40m, or 10h 23m
    under a day. $null for a span below zero, after a clock was set back.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][timespan]$Span)
    if ($Span -lt [timespan]::Zero) { return $null }
    $text = '{0}h {1}m' -f $Span.Hours, $Span.Minutes
    if ($Span.Days -ge 1) { $text = '{0}d {1}' -f $Span.Days, $text }
    $text
}

function Format-UsaBannerSize {
    <#
    .SYNOPSIS
    Space in use against a size, as the banner shows it.
    .DESCRIPTION
    In bytes. From 1 TiB in TiB to a tenth, from 10 GiB in whole GiB, below
    that in GiB to a tenth, as linux/facts.sh gives it; in the invariant
    culture, so no decimal comma appears.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][double]$Used, [Parameter(Mandatory)][double]$Size)
    $invariant = [cultureinfo]::InvariantCulture
    if ($Size -ge 1TB) { return [string]::Format($invariant, '{0:0.0} of {1:0.0} TiB', $Used / 1TB, $Size / 1TB) }
    if ($Size -ge 10GB) { return [string]::Format($invariant, '{0:0} of {1:0} GiB', [Math]::Floor($Used / 1GB + 0.5), [Math]::Floor($Size / 1GB + 0.5)) }
    [string]::Format($invariant, '{0:0.0} of {1:0.0} GiB', $Used / 1GB, $Size / 1GB)
}

function Read-UsaBannerNotice {
    # In:  the file of the update channel's notice (D14)
    # Out: its lines as linux/facts.sh gives them: a tab as a space, no
    #      control character, an empty line passed over; nothing without
    #      the file
    # Why: the update job leaves the notice the banner after login shows,
    #      and its text must not reach a terminal as an escape
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $text = $line.Replace("`t", ' ') -replace '[\x00-\x1F\x7F]', ''
        if ($text) { $text }
    }
}

function Get-UsaBannerWindowsFacts {
    <#
    .SYNOPSIS
    This Windows host's facts, as the banners draw them.
    .DESCRIPTION
    Out: the facts hashtable described at the top of PostLogin.ps1, with the
         facts linux/facts.sh gives a Linux host, in the same forms, but two:
         - Cpu.Now is the processors' busy percentage over a quiet window of
           -CpuWindowMs, 200 ms as today, read after the other probes, whose
           work would count otherwise;
         - Time carries its UTC offset (-05:00), where Linux gives the
           zone's abbreviation.
    The name is the DNS host name in the case the host gives it, with its
    domain in lower case when it is in one. The CPU, the memory and the
    disks take their 24-hour range from the periodic job's samples, in
    -SamplePath (Samples.ps1); the CPU's speed, the memory's and disks'
    kinds and the updates waiting come from its slow facts, in -SlowPath
    (WindowsSlowFacts.ps1); a reboot pending and a restart set are read
    live. The health
    lines and the services row come from WindowsHealth.ps1: -Services is
    the configuration's, default or the names, and -Ignore the services the
    sweep of automatic ones leaves out. -Hide is a regex of adapter names to
    leave out: by default the NAT adapters of WSL, the Default Switch and
    containers. The notices are the lines of the update channel's notice
    (D14), in -NoticePath. -Now is the moment the facts describe, for tests.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string]$Hide = '^vEthernet \((WSL|Default Switch|nat)\b',
        [int]$CpuWindowMs = 200,
        [datetimeoffset]$Now = [datetimeoffset]::Now,
        [string]$SamplePath = (Get-UsaBannerDataPath -Name 'samples.tsv' -OnWindows $true),
        [string]$SlowPath = (Get-UsaBannerDataPath -Name 'slow.tsv' -OnWindows $true),
        [string]$NoticePath = (Get-UsaBannerDataPath -Name 'notice' -OnWindows $true),
        [object]$Services = 'default',
        [AllowEmptyCollection()][string[]]$Ignore = @()
    )
    $system = Get-UsaBannerWinSystem
    $facts = @{}

    $name = $system.DnsHostName
    if (-not $name) { $name = [Environment]::MachineName }
    if ($system.PartOfDomain -and $system.Domain) { $name = '{0}.{1}' -f $name, $system.Domain.ToLowerInvariant() }
    $facts['Name'] = $name

    # The primary address: the one the default route sends from, else the
    # first listed.
    $adapters = @(Select-UsaBannerInterface -Interface @(Get-UsaBannerWinInterface) -Hide $Hide)
    $primary = Get-UsaBannerPrimaryIp
    if (-not $primary -and $adapters.Count) { $primary = ($adapters[0].Address -split '[/ ]')[0] }
    if ($primary) { $facts['Ip'] = $primary }

    $os = $system.Caption -replace '^Microsoft ', ''
    if ($system.Build) { $os += ', build {0}{1}' -f $system.Build, $(if ($system.Ubr) { ".$($system.Ubr)" }) }
    if ($os) { $facts['Os'] = $os }
    if ($system.BootTime) {
        $uptime = Format-UsaBannerUptime -Span ($Now - $system.BootTime)
        if ($uptime) { $facts['Uptime'] = $uptime }
    }

    if ($system.MemoryKiB -gt 0) {
        $memoryUsed = $system.MemoryKiB - $system.FreeKiB
        $facts['Memory'] = @{
            Pct = [int][Math]::Floor(100 * $memoryUsed / $system.MemoryKiB); Min = $null; Max = $null; Kind = $null
            Text = [string]::Format([cultureinfo]::InvariantCulture, '{0:0.0} of {1:0.0} GiB', $memoryUsed / 1MB, $system.MemoryKiB / 1MB)
        }
    }

    # Fixed drives, the system drive first, then by name.
    $disks = foreach ($drive in Get-UsaBannerWinDrive) {
        if ($drive.Type -ne 'Fixed' -or -not $drive.Ready -or $drive.Size -le 0) { continue }
        $diskUsed = $drive.Size - $drive.Free
        @{ Name = $drive.Name; Pct = [int][Math]::Floor(100 * $diskUsed / $drive.Size); Min = $null; Max = $null; Text = Format-UsaBannerSize -Used $diskUsed -Size $drive.Size; Kind = $null }
    }
    $disks = @($disks | Sort-Object { $_.Name -ne $system.SystemDrive }, { $_.Name })
    if ($disks.Count) { $facts['Disks'] = $disks }

    # As Linux counts who's lines: each session, and each user once.
    $sessions = @(Get-UsaBannerWinSession)
    $users = @($sessions | Sort-Object -Unique)
    $facts['Sessions'] = if ($users.Count) { '{0}  ({1})' -f $sessions.Count, ($users -join ' ') } else { '0' }

    if ($adapters.Count) { $facts['Ipv4'] = $adapters }
    $facts['Time'] = $Now.ToString('ddd yyyy-MM-dd HH:mm zzz', [cultureinfo]::InvariantCulture)
    # A restart set, live: the newest of User32's events 1074 and 1075 since
    # the boot (D17). A System log this account cannot read says nothing of
    # a schedule, so the row does not either.
    $restart = $null
    $restartRead = $false
    if ($system.BootTime) {
        try {
            $restart = Get-UsaBannerWinRestartEvent -Since $system.BootTime
            $restartRead = $true
        }
        catch { $restart = $null }
    }
    $facts['Reboot'] = Format-UsaBannerReboot -Reason @(Get-UsaBannerWinRebootPending) -Restart $restart -RestartRead:$restartRead
    $serviceList = @(Get-UsaBannerWinServiceList)
    $timeSource = Get-UsaBannerWinTimeSource

    # The CPU last, over a quiet window: the probes above make WMI, the
    # service manager, quser and w32tm work in processes of their own, which
    # the subtraction of this process's time cannot see. Across them an idle
    # 4-core node read 24%; a quiet window read 3% (lab, 2026-10-03).
    $cpuFrom = Get-UsaBannerWinCpuSample
    if ($CpuWindowMs -gt 0) { Start-Sleep -Milliseconds $CpuWindowMs }
    $busy = Get-UsaBannerWinCpuPercent -From $cpuFrom -To (Get-UsaBannerWinCpuSample) -Cores $system.Cores
    if ($null -ne $busy) {
        $unit = if ($system.Cores -eq 1) { 'core' } else { 'cores' }
        $facts['Cpu'] = @{ Now = $busy; Min = $null; Max = $null; Text = '{0} {1}' -f $system.Cores, $unit }
    }
    Add-UsaBannerSampleRange -Facts $facts -Path $SamplePath -Now $Now
    Add-UsaBannerSlowFacts -Facts $facts -Path $SlowPath -Now $Now
    Add-UsaBannerWinHealth -Facts $facts -ServiceList $serviceList -TimeSource $timeSource -Services $Services -PartOfDomain $system.PartOfDomain -Ignore $Ignore
    $notices = @(Read-UsaBannerNotice -Path $NoticePath)
    if ($notices.Count) { $facts['Notices'] = $notices }
    $facts
}
