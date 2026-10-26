# WindowsSlowFacts.ps1 - a Windows host's slow facts (docs/DECISIONS.md, D17):
# what the periodic job reads for the logins of the next 24 hours, in the
# slow.tsv form linux/sample.sh writes on Linux, and the reboot a login reads
# live. Each probe is a function of its own, so a test can stand in for it on
# any OS.
#
# Get-UsaBannerWinRestartEvent, which PowerShell logs whole at each import, is
# in WindowsSlowFacts.Logged.ps1 (docs/DECISIONS.md, D30).

# The SMBIOS memory types, by the code Win32_PhysicalMemory.SMBIOSMemoryType
# gives, named as dmidecode names them.
$script:UsaMemoryTypes = @{
    18 = 'DDR'; 19 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 27 = 'LPDDR'; 28 = 'LPDDR2'
    29 = 'LPDDR3'; 30 = 'LPDDR4'; 34 = 'DDR5'; 35 = 'LPDDR5'
}

# A virtual machine's maker or model: Hyper-V's guests are Microsoft
# Corporation's Virtual Machine (measured, Server 2022 and 2025); QEMU's,
# KVM's, Xen's, VMware's, VirtualBox's and the large clouds' name themselves
# in one or the other.
$script:UsaVirtualHardware = '^Virtual Machine$|QEMU|KVM|^Standard PC \(|^Xen$|HVM domU|VMware|VirtualBox|innotek|Amazon EC2|Google Compute Engine|Parallels'

function Get-UsaBannerWinHardware {
    <#
    .SYNOPSIS
    What the periodic job reads about this Windows host's hardware.
    .DESCRIPTION
    Out: @{ Manufacturer; Model; CpuName; CpuMhz; Memory; Disks }: the
         computer's maker and model; the first processor's name and highest
         speed in MHz; each memory module as @{ Type; Configured; Rated },
         its SMBIOS type and speeds in MT/s; and each fixed drive's physical
         disk as @{ Name = 'C:'; MediaType; BusType }, a drive on no single
         physical disk left out. $null when CIM cannot be read. The storage
         cmdlets' first call is slow: the job's to pay, never a login's.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $cpu = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)[0]
        $modules = @(foreach ($module in Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop) {
                @{ Type = [int]$module.SMBIOSMemoryType; Configured = [int]$module.ConfiguredClockSpeed; Rated = [int]$module.Speed }
            })
    }
    catch { return $null }
    $physical = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $disks = @(foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
            if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) { continue }
            $name = $drive.Name.TrimEnd('\')
            $partition = Get-Partition -DriveLetter $name[0] -ErrorAction SilentlyContinue
            if (-not $partition) { continue }
            $under = @($physical | Where-Object { $_.DeviceId -eq [string]$partition.DiskNumber })
            if ($under.Count -ne 1) { continue }
            @{ Name = $name; MediaType = [string]$under[0].MediaType; BusType = [string]$under[0].BusType }
        })
    @{
        Manufacturer = [string]$cs.Manufacturer; Model = [string]$cs.Model
        CpuName = [string]$cpu.Name; CpuMhz = [int]$cpu.MaxClockSpeed; Memory = $modules; Disks = $disks
    }
}

function Get-UsaBannerWinUpdates {
    <#
    .SYNOPSIS
    The updates waiting, as the Windows Update agent last found them.
    .DESCRIPTION
    Out: @{ Waiting; Security }: the software updates neither installed,
         hidden nor optional, and how many of them are in the Security
         Updates classification, found by its id, which no language changes.
         $null when the agent cannot answer. With Online off the searcher
         does not go online, so it answers from what the agent already holds,
         its own last scan, as apt-check answers from apt's lists: the job
         neither waits on a network nor adds a scan to an update server.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $searcher.Online = $false
        $found = @($searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software' and BrowseOnly=0").Updates)
    }
    catch { return $null }
    # SecurityUpdates, in Microsoft's table of WSUS classification GUIDs.
    $security = @($found | Where-Object { @($_.Categories | Where-Object { $_.CategoryID -eq '0fa1201d-4330-4fa8-8ae9-b877473b6441' }).Count })
    @{ Waiting = $found.Count; Security = $security.Count }
}

function Get-UsaBannerWinRebootPending {
    <#
    .SYNOPSIS
    Why this Windows host waits for a reboot, read live at login.
    .DESCRIPTION
    Out: 'servicing' when Component Based Servicing's RebootPending key is
         there, and 'Windows Update' when Windows Update's RebootRequired key
         is: the two today's banner reads. Nothing when neither is.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { 'servicing' }
    if (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { 'Windows Update' }
}

function Test-UsaBannerVirtualHardware {
    <#
    .SYNOPSIS
    Whether a computer's maker and model are a virtual machine's.
    .DESCRIPTION
    By $script:UsaVirtualHardware. HypervisorPresent cannot tell: a Hyper-V
    host, and any host with virtualization-based security on, runs on the
    hypervisor too. Microsoft Corporation alone cannot either: it makes
    Surface devices.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([AllowEmptyString()][string]$Manufacturer, [AllowEmptyString()][string]$Model)
    $Manufacturer -match $script:UsaVirtualHardware -or $Model -match $script:UsaVirtualHardware
}

function ConvertTo-UsaBannerCpuGhz {
    <#
    .SYNOPSIS
    A CPU's rated speed in GHz, to a tenth.
    .DESCRIPTION
    From the name's "@ 3.10GHz" where it has one, as Intel's do, else from
    the highest speed Windows gives, as linux/facts.sh reads it: a Hyper-V
    guest gave 2195 MHz for a CPU named @ 3.10GHz. $null with neither.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Name, [int]$Mhz)
    $invariant = [cultureinfo]::InvariantCulture
    if ($Name -match '@\s*([0-9]+(\.[0-9]+)?)\s*GHz') { return ([double]::Parse($Matches[1], $invariant)).ToString('0.0', $invariant) }
    if ($Mhz -gt 0) { return ($Mhz / 1000).ToString('0.0', $invariant) }
    $null
}

function ConvertTo-UsaBannerMemoryKind {
    <#
    .SYNOPSIS
    The memory's kind and speed, as DDR4-3200.
    .DESCRIPTION
    In:  memory modules as Get-UsaBannerWinHardware gives them.
    Out: the first module with a type in $script:UsaMemoryTypes, at its
         configured speed, else its rated one, as linux/sample.sh reads
         dmidecode; $null when none has such a type, as in a virtual machine
         (Hyper-V: type 2, Unknown).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([System.Collections.IDictionary[]]$Module = @())
    foreach ($stick in $Module) {
        $type = $script:UsaMemoryTypes[[int]$stick.Type]
        if (-not $type) { continue }
        $speed = if ($stick.Configured -gt 0) { $stick.Configured } elseif ($stick.Rated -gt 0) { $stick.Rated } else { 0 }
        if ($speed) { return '{0}-{1}' -f $type, $speed }
        return $type
    }
    $null
}

function ConvertTo-UsaBannerDiskKind {
    <#
    .SYNOPSIS
    A disk's kind: removable, NVMe, SSD or HDD.
    .DESCRIPTION
    In:  a disk as Get-UsaBannerWinHardware gives it.
    Out: removable or NVMe by its bus, else SSD or HDD by its media, in
         linux/sample.sh's order; $null when Windows does not say, as for a
         virtual disk (Hyper-V: Unspecified, on a SAS bus).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([System.Collections.IDictionary]$Disk)
    if ($Disk.BusType -in 'USB', 'SD', 'MMC') { return 'removable' }
    if ($Disk.BusType -eq 'NVMe') { return 'NVMe' }
    if ($Disk.MediaType -eq 'SSD') { return 'SSD' }
    if ($Disk.MediaType -eq 'HDD') { return 'HDD' }
    $null
}

function Format-UsaBannerUpdates {
    <#
    .SYNOPSIS
    The Updates row: the updates waiting, as text and a level.
    .DESCRIPTION
    As linux/facts.sh gives it: none pending, N pending, or N pending, M
    security, a warning while security updates wait (D17).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([long]$Waiting, [long]$Security)
    if ($Waiting -eq 0) { return @{ Text = 'none pending'; Level = 'good' } }
    if ($Security -eq 0) { return @{ Text = "$Waiting pending"; Level = 'good' } }
    @{ Text = "$Waiting pending, $Security security"; Level = 'warn' }
}

function Format-UsaBannerReboot {
    <#
    .SYNOPSIS
    The Reboot row on Windows: why a reboot is pending, and a restart set, as
    text and a level.
    .DESCRIPTION
    In:  the reasons Get-UsaBannerWinRebootPending gives; -RestartRead when
         the System log was read, -Restart the newest restart event since the
         boot that Get-UsaBannerWinRestartEvent gave, if any.
    Out: as linux/facts.sh gives it: "pending: " and the reasons, then, when
         the newest event is 1074, the restart set with when and by whom,
         each a warning; else none pending, and none scheduled only when the
         log was read: an account that cannot read it is told nothing of a
         schedule (D17).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()][string[]]$Reason = @(),
        [System.Collections.IDictionary]$Restart,
        [switch]$RestartRead
    )
    $set = $null
    if ($RestartRead -and $Restart -and $Restart.Id -eq 1074) {
        $type = if ($Restart.Type) { $Restart.Type } else { 'restart' }
        $set = '{0} set {1}' -f $type, $Restart.Time.ToString('ddd HH:mm', [cultureinfo]::InvariantCulture)
        $user = [string]$Restart.User -replace '^.*\\', ''
        if ($user) { $set += " by $user" }
    }
    if ($Reason.Count) {
        $text = 'pending: ' + ($Reason -join ', ')
        if ($set) { $text += "; $set" }
        return @{ Text = $text; Level = 'warn' }
    }
    if ($set) { return @{ Text = "none pending; $set"; Level = 'warn' } }
    if ($RestartRead) { return @{ Text = 'none pending, none scheduled'; Level = 'good' } }
    @{ Text = 'none pending'; Level = 'good' }
}

function Write-UsaBannerSlowFacts {
    <#
    .SYNOPSIS
    The periodic job's slow facts on Windows, written to slow.tsv.
    .DESCRIPTION
    In:  the file and the time.
    Out: nothing. The file is written anew, whole, beside itself and moved
         into place, in the form linux/sample.sh writes, with one kind more:
         a line each for the CPU's speed (cpu-speed, in GHz: Linux reads its
         own at login), the memory's kind, each fixed drive's kind, and the
         updates waiting. A virtual machine's memory and drives get no kind:
         what its hypervisor presents says nothing of the hardware under it.
         A fact that cannot be read gets no line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )
    $time = $Now.ToUnixTimeSeconds()
    $lines = [System.Collections.Generic.List[string]]::new()
    $hardware = Get-UsaBannerWinHardware
    if ($hardware) {
        $ghz = ConvertTo-UsaBannerCpuGhz -Name $hardware.CpuName -Mhz $hardware.CpuMhz
        if ($ghz) { $lines.Add("$time`tcpu-speed`t$ghz") }
        if (-not (Test-UsaBannerVirtualHardware -Manufacturer $hardware.Manufacturer -Model $hardware.Model)) {
            $memoryKind = ConvertTo-UsaBannerMemoryKind -Module @($hardware.Memory)
            if ($memoryKind) { $lines.Add("$time`tmemory-kind`t$memoryKind") }
            foreach ($disk in @($hardware.Disks)) {
                $diskKind = ConvertTo-UsaBannerDiskKind -Disk $disk
                if ($diskKind) { $lines.Add("$time`tdisk-kind`t$($disk.Name)`t$diskKind") }
            }
        }
    }
    $updates = Get-UsaBannerWinUpdates
    if ($updates) { $lines.Add("$time`tupdates`t$($updates.Waiting)`t$($updates.Security)") }
    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    Save-UsaBannerJobFile -Path $Path -Text (-join @(foreach ($line in $lines) { "$line`n" }))
}

function Add-UsaBannerSlowFacts {
    <#
    .SYNOPSIS
    Fills in the facts from the periodic job's slow.tsv.
    .DESCRIPTION
    In:  the facts, the file and the time.
    Out: nothing. From its lines less than 24 hours old, the last of each
         kind counting, as linux/facts.sh takes them: the memory and each
         disk get their kinds, the facts an Updates row, and the CPU's text
         its speed. A line that is not one is passed over. The times compare
         as awk compares them, as numbers no length of digits overflows.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Facts,
        [Parameter(Mandatory)][string]$Path,
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    # A file this user cannot read gives no facts: the banner draws without
    # them, and Get-UsaBanner's periodic job check names the file (lab,
    # 2026-10-23: a login drew no banner at all).
    try { $lines = [System.IO.File]::ReadAllLines($Path) }
    catch [System.UnauthorizedAccessException], [System.IO.IOException] { return }
    $cut = $Now.ToUnixTimeSeconds() - 86400
    $speed = ''
    $memoryKind = ''
    $diskKinds = @{}
    $counts = $null
    foreach ($line in $lines) {
        $f = $line -split "`t"
        if ($f.Count -lt 3 -or $f[0] -notmatch '^[0-9]+$' -or [double]$f[0] -le $cut) { continue }
        switch -CaseSensitive ($f[1]) {
            'cpu-speed' { $speed = $f[2] }
            'memory-kind' { $memoryKind = $f[2] }
            'disk-kind' { if ($f.Count -ge 4) { $diskKinds[$f[2]] = $f[3] } }
            'updates' { if ($f.Count -ge 4 -and $f[2] -match '^[0-9]{1,18}$' -and $f[3] -match '^[0-9]{1,18}$') { $counts = $f[2], $f[3] } }
        }
    }
    if ($speed -match '^[0-9]+\.[0-9]$' -and $Facts['Cpu']) { $Facts['Cpu'].Text = '{0} @ {1} GHz' -f $Facts['Cpu'].Text, $speed }
    if ($memoryKind -and $Facts['Memory']) { $Facts['Memory'].Kind = $memoryKind }
    foreach ($disk in @($Facts['Disks'])) {
        if ($disk -and $diskKinds[$disk.Name]) { $disk.Kind = $diskKinds[$disk.Name] }
    }
    if ($counts) { $Facts['Updates'] = Format-UsaBannerUpdates -Waiting $counts[0] -Security $counts[1] }
}
