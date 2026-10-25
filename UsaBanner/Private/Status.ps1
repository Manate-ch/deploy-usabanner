# Status.ps1 - Get-UsaBanner (docs/SPEC.md, 3.3): what a deploy put on this
# host, each part checked against what a deploy would put there now, and the
# banners as they are installed. Each check ends in one state:
#
#   +---------+-------------------------------------------------------------+
#   | State   | Means                                                       |
#   +---------+-------------------------------------------------------------+
#   | ok      | in place, as a deploy leaves it                             |
#   | off     | not in place for a reason outside the banner: no OpenSSH    |
#   |         | server, a logon notice someone else set, another SSH shell  |
#   | missing | a part a deploy puts in place is not there                  |
#   | differs | there, but not as a deploy leaves it                        |
#   | stale   | out of date: drawn for another name, address or             |
#   |         | configuration; no sample for 20 minutes; an sshd started    |
#   |         | before sshd_config last changed                             |
#   | invalid | the configuration cannot be read                            |
#   | unknown | this session cannot tell: the check needs root, or an       |
#   |         | administrator                                               |
#   +---------+-------------------------------------------------------------+
#
# A host is healthy when a banner is deployed and no check is missing,
# differs, stale or invalid. Nothing here changes the host: the programs it
# runs only read (systemctl is-enabled and is-active, sshd -T, and the login
# renderer for -Moment PostLogon).

$script:UsaFaultStates = @('invalid', 'missing', 'differs', 'stale')

# The states from worst to best: a check that covers several files takes the
# worst of their states. A list of its own, so the states that count against
# a healthy host can change without changing it.
$script:UsaStateOrder = @('invalid', 'missing', 'differs', 'stale', 'unknown', 'off', 'ok')

function New-UsaBannerCheck {
    # In:  the check's name, its state, and what it found
    # Out: one row of Get-UsaBanner's checks
    param([string]$Check, [string]$State, [string]$Detail)
    [pscustomobject]@{ PSTypeName = 'UsaBanner.Check'; State = $State; Check = $Check; Detail = $Detail }
}

function Join-UsaBannerFinding {
    # In:  a check's name, what it says when all is well, and its findings,
    #      each @{ State; Text }
    # Out: the check: ok when every finding is; else the worst state found,
    #      with the text of each finding that is not ok
    # Why: one check covers several files, and a file missing outweighs one
    #      out of date
    param([string]$Check, [string]$Ok, [object[]]$Found = @())
    $bad = @($Found | Where-Object { $_ -and $_.State -ne 'ok' })
    if (-not $bad.Count) { return New-UsaBannerCheck -Check $Check -State 'ok' -Detail $Ok }
    $states = @($bad | ForEach-Object { $_.State })
    # A state the order lacks still reports: the first one found.
    $worst = @(@($script:UsaStateOrder | Where-Object { $_ -in $states }) + $states)[0]
    New-UsaBannerCheck -Check $Check -State $worst -Detail (@($bad | ForEach-Object { $_.Text }) -join '; ')
}

function Get-UsaBannerModuleVersion {
    # In:  a modules folder for all users, as this process reads it
    # Out: the newest version of the module in it, the one Import-Module
    #      UsaBanner loads; nothing when there is none
    param([Parameter(Mandatory)][string]$Folder)
    $base = [System.IO.Path]::Combine($Folder, 'UsaBanner')
    if (-not [System.IO.Directory]::Exists($base)) { return }
    $newest = $null
    foreach ($dir in [System.IO.Directory]::GetDirectories($base)) {
        $version = $null
        if (-not [version]::TryParse([System.IO.Path]::GetFileName($dir), [ref]$version)) { continue }
        if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($dir, 'UsaBanner.psd1'))) { continue }
        if ($null -eq $newest -or $version -gt $newest) { $newest = $version }
    }
    $newest
}

function Get-UsaBannerSampleFinding {
    # In:  the samples file, and the record of the deploy
    # Out: a finding on the periodic job's last sample: ok within 20
    #      minutes; stale when older, or when there is none 20 minutes
    #      after the deploy
    # Why: the job samples every 15 minutes; one that stopped leaves the
    #      24-hour range and the slow facts to age
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Record)
    $now = [datetime]::UtcNow
    # A login reads the samples and slow.tsv beside them: one it cannot read
    # draws its banner without what is in it (lab, 2026-10-23).
    foreach ($file in $Path, [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($Path), 'slow.tsv')) {
        if (-not [System.IO.File]::Exists($file)) { continue }
        try { [System.IO.File]::OpenRead($file).Dispose() }
        catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            return @{ State = 'invalid'; Text = "$file cannot be read, so a login draws its banner without what is in it: $($_.Exception.Message)" }
        }
    }
    if ([System.IO.File]::Exists($Path)) {
        $minutes = [int][Math]::Floor(($now - [System.IO.File]::GetLastWriteTimeUtc($Path)).TotalMinutes)
        if ($minutes -gt 20) { return @{ State = 'stale'; Text = "the last sample is $minutes minutes old: the periodic job samples every 15" } }
        $ago = if ($minutes -lt 1) { 'under a minute' } elseif ($minutes -eq 1) { '1 minute' } else { "$minutes minutes" }
        return @{ State = 'ok'; Text = "the last sample was $ago ago" }
    }
    if ([System.IO.File]::Exists($Record) -and ($now - [System.IO.File]::GetLastWriteTimeUtc($Record)).TotalMinutes -le 20) {
        return @{ State = 'ok'; Text = 'no sample yet: the first comes within minutes of the deploy' }
    }
    @{ State = 'stale'; Text = 'no sample yet, 20 minutes after the deploy' }
}

function New-UsaBannerStatus {
    # In:  what a host's checks found
    # Out: Get-UsaBanner's answer (Public\Get-UsaBanner.ps1 says what each
    #      property holds). The settings are those the configuration sets
    #      otherwise than the defaults
    param(
        [string]$HostName,
        [string]$Ip,
        [string]$Os,
        [AllowNull()][version]$Version,
        [bool]$Deployed,
        [object[]]$Checks = @(),
        [string]$Ssh,
        [string]$Services,
        [AllowNull()][System.Collections.IDictionary]$Config
    )
    $vlans = @()
    $settings = @()
    if ($Config) {
        $here = Find-UsaBannerVlan -Address $Ip -Vlans @($Config['vlans'])
        $vlans = @(foreach ($vlan in @($Config['vlans'])) {
                if (-not $vlan) { continue }
                [pscustomobject]@{
                    PSTypeName = 'UsaBanner.Vlan'
                    Tag        = $vlan['tag']
                    Name       = [string]$vlan['name']
                    Cidr       = [string]$vlan['cidr']
                    Color      = [string]$vlan['color']
                    Short      = [string]$vlan['short']
                    ThisHost   = [object]::ReferenceEquals($vlan, $here)
                }
            })
        $settings = @(Compare-UsaBannerConfig -Old (Get-UsaBannerConfigDefault) -New $Config -NewOnly)
    }
    $faults = @($Checks | Where-Object { $_.State -in $script:UsaFaultStates })
    [pscustomobject]@{
        PSTypeName    = 'UsaBanner.Status'
        HostName      = $HostName
        Os            = $Os
        Version       = $(if ($Version) { [string]$Version } else { '' })
        Deployed      = $Deployed
        Healthy       = ($Deployed -and $faults.Count -eq 0)
        Ssh           = $Ssh
        Services      = $Services
        Checks        = @($Checks)
        Vlans         = $vlans
        Settings      = $settings
        Configuration = $Config
    }
}

function Get-UsaBannerServicesText {
    # In:  the host's facts
    # Out: the services row of the banner after login: what is watched, and
    #      in what state; '' when no service is watched
    param([System.Collections.IDictionary]$Facts)
    if ($Facts -and $Facts['Services']) { [string]$Facts['Services']['Text'] } else { '' }
}

function Read-UsaBannerHostText {
    # In:  the host's root, and a file's path on the host
    # Out: the file's text; $null when it is not there
    param([AllowEmptyString()][string]$Root = '', [Parameter(Mandatory)][string]$Path)
    if ([System.IO.File]::Exists("$Root$Path")) { [System.IO.File]::ReadAllText("$Root$Path") } else { $null }
}

function Test-UsaBannerDrawnFile {
    # In:  the host's root, a drawn file's path on the host, its text as
    #      drawn now ($null when that cannot be known), and whether what was
    #      drawn here is out of date
    # Out: a finding
    # Why: a file that differs from a drawing that is itself out of date is
    #      the periodic job's to fix; one that differs from a current
    #      drawing was changed
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][object]$Want,
        [bool]$Stale
    )
    $have = Read-UsaBannerHostText -Root $Root -Path $Path
    if ($null -eq $have) { return @{ State = 'missing'; Text = "$Path is missing" } }
    if ($null -eq $Want) { return @{ State = 'unknown'; Text = "${Path}: what the configuration draws is not known" } }
    if ($have -ceq [string]$Want) { return @{ State = 'ok'; Text = '' } }
    if ($Stale) { return @{ State = 'stale'; Text = "$Path was drawn for another name, address or configuration" } }
    @{ State = 'differs'; Text = "$Path is not what the configuration draws: changed by hand, or drawn by another version of the module" }
}

function Test-UsaBannerModuleFile {
    # In:  the host's root, a file's path on the host, the module's own copy,
    #      and whether it must run (pam_motd runs only executable scripts)
    # Out: a finding: the file as the module ships it, or not
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Source,
        [switch]$Executable
    )
    $full = "$Root$Path"
    if (-not [System.IO.File]::Exists($full)) { return @{ State = 'missing'; Text = "$Path is missing" } }
    if (-not [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($full), [byte[]][System.IO.File]::ReadAllBytes($Source))) {
        return @{ State = 'differs'; Text = "$Path is not the module's" }
    }
    if ($Executable -and ([int][System.IO.File]::GetUnixFileMode($full) -band [int]$script:UsaExecBits) -eq 0) {
        return @{ State = 'differs'; Text = "$Path is not executable, so pam_motd skips it" }
    }
    @{ State = 'ok'; Text = '' }
}

function Get-UsaBannerLinuxSshState {
    # In:  the host's root
    # Out: open when sshd runs or systemd listens for it (ssh.socket);
    #      closed when it does neither; not installed without OpenSSH's
    #      server
    param([AllowEmptyString()][string]$Root = '')
    if (-not [System.IO.File]::Exists("$Root$script:UsaLinuxSshd")) { return 'not installed' }
    foreach ($unit in 'ssh.service', 'ssh.socket') {
        if ([string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-active', $unit).Output) + '')[0] -eq 'active') { return 'open' }
    }
    'closed'
}

function Get-UsaBannerLinuxSshCheck {
    # In:  the host's root, the drawing, and whether what was drawn is out
    #      of date
    # Out: the SSH banner's check: the drop-in and issue.net in place, and,
    #      as root, the Banner sshd -T says sshd sends. sshd -T reads files
    #      only root may read (cloud-init's drop-in is mode 600), so another
    #      user's answer is unknown
    param(
        [AllowEmptyString()][string]$Root = '',
        [AllowNull()][System.Collections.IDictionary]$Drawing,
        [bool]$Stale
    )
    $want = "$script:UsaLinuxEtc/issue.net"
    if (-not [System.IO.File]::Exists("$Root$script:UsaLinuxSshd")) {
        return New-UsaBannerCheck -Check 'ssh banner' -State 'off' -Detail 'OpenSSH''s server is not installed here: run Deploy-UsaBanner again once it is'
    }
    $found = @(
        Test-UsaBannerDrawnFile -Root $Root -Path $script:UsaLinuxDropIn -Want (Get-UsaBannerSshDropIn) -Stale $false
        Test-UsaBannerDrawnFile -Root $Root -Path $want -Want $(if ($Drawing) { $Drawing['IssueNet'] }) -Stale $Stale
    )
    if (@($found | Where-Object { $_.State -ne 'ok' }).Count -eq 0) {
        if (Test-UsaBannerPrivileged) {
            $test = Invoke-UsaBannerNative -FilePath $script:UsaLinuxSshd -ArgumentList '-T'
            $uses = @(@($test.Output) | Where-Object { $_ -match '^banner\s' } | ForEach-Object { ($_ -split '\s+', 2)[1] })
            $banner = if ($uses.Count) { $uses[0] } else { 'none' }
            if ($test.ExitCode -ne 0) { $found += @{ State = 'differs'; Text = "sshd -T refused the configuration: $(@($test.Output) -join ' ')" } }
            elseif ($banner -ne $want) { $found += @{ State = 'differs'; Text = "sshd sends the Banner $banner, not ${want}: a file sshd reads before $script:UsaLinuxDropIn sets one, and sshd takes the first" } }
        }
        else { $found += @{ State = 'unknown'; Text = "$script:UsaLinuxDropIn and $want are in place; sshd -T, which needs root, says whether sshd sends it" } }
    }
    Join-UsaBannerFinding -Check 'ssh banner' -Ok "sshd sends $want before authentication" -Found $found
}

function Get-UsaBannerLinuxMotdCheck {
    # In:  the host's root
    # Out: the check that Ubuntu's own MOTD scripts the banner replaces stay
    #      off (D16): none of them executable, and motd-news.timer not
    #      enabled again
    param([AllowEmptyString()][string]$Root = '')
    $found = @(
        foreach ($name in $script:UsaRetiredScripts) {
            $path = "/etc/update-motd.d/$name"
            $info = [System.IO.FileInfo]::new("$Root$path")
            if ($info.Exists -and -not $info.LinkTarget -and ([int][System.IO.File]::GetUnixFileMode($info.FullName) -band [int]$script:UsaExecBits) -ne 0) {
                @{ State = 'differs'; Text = "$path runs again" }
            }
        }
        $link = [System.IO.FileInfo]::new("$Root/etc/update-motd.d/50-landscape-sysinfo")
        if ($link.LinkTarget) {
            $target = $link.LinkTarget
            if (-not $target.StartsWith('/')) { $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine('/etc/update-motd.d', $target)) }
            if ([System.IO.File]::Exists("$Root$target") -and ([int][System.IO.File]::GetUnixFileMode("$Root$target") -band [int]$script:UsaExecBits) -ne 0) {
                @{ State = 'differs'; Text = '/etc/update-motd.d/50-landscape-sysinfo runs again' }
            }
        }
        $news = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-enabled', 'motd-news.timer').Output) + '')[0]
        if ($news -like 'enabled*') { @{ State = 'differs'; Text = 'motd-news.timer is enabled again' } }
    )
    $check = Join-UsaBannerFinding -Check 'stock motd off' -Ok 'the stock MOTD scripts the banner replaces stay off' -Found $found
    if ($check.State -ne 'ok') { $check.Detail += ': Deploy-UsaBanner turns each off again' }
    $check
}

function Get-UsaBannerLinuxJobCheck {
    # In:  the host's root
    # Out: the periodic job's check: its units as a deploy writes them, the
    #      timer enabled and active, and a sample within 20 minutes
    param([AllowEmptyString()][string]$Root = '')
    $units = Get-UsaBannerSystemdUnits
    $found = @(
        foreach ($unit in $units.Keys) {
            Test-UsaBannerDrawnFile -Root $Root -Path "/etc/systemd/system/$unit" -Want $units[$unit] -Stale $false
        }
        foreach ($ask in @(@('is-enabled', 'enabled'), @('is-active', 'active'))) {
            $state = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList $ask[0], 'usabanner-sample.timer').Output) + '')[0]
            if ($state -ne $ask[1]) { @{ State = 'differs'; Text = "usabanner-sample.timer is $(if ($state) { $state } else { 'not known to systemd' }), not $($ask[1])" } }
        }
    )
    $sample = Get-UsaBannerSampleFinding -Path "$Root$script:UsaLinuxState/samples.tsv" -Record "$Root$script:UsaLinuxState/deploy.json"
    Join-UsaBannerFinding -Check 'periodic job' -Ok "usabanner-sample.timer samples every 15 minutes; $($sample.Text)" -Found ($found + @($sample))
}

function Get-UsaBannerUpdateCheck {
    <#
    .SYNOPSIS
    The update channel's check (D14).
    .DESCRIPTION
    In:  the configuration ($null when it cannot be read), the banner's own
         folder, where the update job keeps update.json, and the findings on
         the job itself: its units, or its task.
    Out: the check. ok when the channel is off. Else the job's findings, and
         its last look as update.json holds it: stale when that failed or is
         two days old; ok, with what it found, when not.
    #>
    param(
        [AllowNull()][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][string]$State,
        [object[]]$Found = @()
    )
    if (-not $Config) { return New-UsaBannerCheck -Check 'update channel' -State 'unknown' -Detail 'what the configuration sets is not known' }
    $mode = [string]$Config['update']['mode']
    if ($mode -eq 'off') { return New-UsaBannerCheck -Check 'update channel' -State 'ok' -Detail 'off: no release is looked for' }
    $findings = @($Found)
    $look = 'no look yet: the job looks within a day of the deploy'
    $path = [System.IO.Path]::Combine($State, 'update.json')
    if ([System.IO.File]::Exists($path)) {
        $last = $null
        try { $last = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable }
        catch { $findings += @{ State = 'differs'; Text = "$path cannot be read: $($_.Exception.Message)" } }
        if ($last) {
            $checked = [System.DateTimeOffset]::FromUnixTimeSeconds([long]$last['checked']).UtcDateTime
            $days = [int][Math]::Floor(([datetime]::UtcNow - $checked).TotalDays)
            if ([string]$last['error']) { $findings += @{ State = 'stale'; Text = "the last look, at $($checked.ToString('u')), failed: $($last['error'])" } }
            elseif ($days -ge 2) { $findings += @{ State = 'stale'; Text = "the last look was at $($checked.ToString('u')), $days days ago: the job looks once a day" } }
            elseif ([string]$last['latest'] -and [string]$last['installed'] -and [version][string]$last['latest'] -gt [version][string]$last['installed']) {
                $look = "UsaBanner $($last['latest']) is out, and this host has $($last['installed']): the banner after login says so"
            }
            else { $look = "UsaBanner $($last['installed']) is the newest release, at the last look ($($checked.ToString('u')))" }
        }
    }
    Join-UsaBannerFinding -Check 'update channel' -Ok "$mode, from $([string]$Config['update']['source']); $look" -Found $findings
}

function Get-UsaBannerLinuxStatus {
    <#
    .SYNOPSIS
    Get-UsaBanner's answer on Ubuntu.
    .DESCRIPTION
    Out: the status (New-UsaBannerStatus). The banners are drawn again from
    the host's own configuration and facts, as the periodic job would draw
    them, and each installed file is compared with its drawing; systemd and
    sshd say what they run.
    #>
    [CmdletBinding()]
    param()
    $root = Get-UsaBannerHostRoot
    $os = Get-UsaBannerHostOs -OnWindows $false -OsReleasePath "$root/etc/os-release"
    $configPath = "$script:UsaLinuxEtc/usabanner.json"
    $common = @{
        Os      = $os
        Version = (Get-UsaBannerModuleVersion -Folder "$root$script:UsaLinuxModules")
        Ssh     = (Get-UsaBannerLinuxSshState -Root $root)
    }
    if (-not [System.IO.File]::Exists("$root$configPath")) {
        $facts = Get-UsaBannerHostFacts -Services @()
        $detail = "there is no ${configPath}: no banner is deployed here"
        $old = @(Find-UsaBannerLinuxOldInstall -Root $root)
        if ($old.Count) { $detail += ". This host has the banner of this repository's install.sh ($($old -join ', ')), which Deploy-UsaBanner -ReplaceOldBanner takes off before it deploys this one" }
        return New-UsaBannerStatus @common -HostName ([string]$facts['Name']) -Ip ([string]$facts['Ip']) -Deployed $false -Checks @(New-UsaBannerCheck -Check 'configuration' -State 'missing' -Detail $detail)
    }

    $checks = [System.Collections.Generic.List[object]]::new()
    $config = $null
    try {
        $config = Read-UsaBannerConfig -Path "$root$configPath"
        $checks.Add((New-UsaBannerCheck -Check 'configuration' -State 'ok' -Detail $configPath))
    }
    catch { $checks.Add((New-UsaBannerCheck -Check 'configuration' -State 'invalid' -Detail $_.Exception.Message)) }
    $facts = Get-UsaBannerHostFacts -Services $(if ($config) { $config['services'] } else { @() })
    $name = [string]$facts['Name']
    $ip = [string]$facts['Ip']
    $drawing = $null
    $sum = ''
    if ($config) {
        $sum = Get-UsaBannerSha256 -Bytes ([System.IO.File]::ReadAllBytes("$root$configPath"))
        $drawing = New-UsaBannerLinuxDrawing -Config $config -Os $os -Name $name -Ip $ip -ConfigSum $sum
    }

    # What was drawn: the name, address and configuration redraw.sh compares.
    $drawn = Read-UsaBannerHostText -Root $root -Path "$script:UsaLinuxState/drawn"
    $stale = $false
    if ($null -eq $drawn) { $checks.Add((New-UsaBannerCheck -Check 'drawn for this host' -State 'missing' -Detail "$script:UsaLinuxState/drawn is missing: the banners were never drawn here")) }
    elseif ($null -eq $drawing) { $checks.Add((New-UsaBannerCheck -Check 'drawn for this host' -State 'unknown' -Detail 'what the configuration draws is not known')) }
    elseif ($drawn -ceq $drawing['Drawn']) { $checks.Add((New-UsaBannerCheck -Check 'drawn for this host' -State 'ok' -Detail "drawn for $name ($ip)")) }
    else {
        $stale = $true
        $was = @($drawn.TrimEnd("`n") -split "`t") + @('', '', '')
        $why = @(
            if ($was[0] -cne $name -or $was[1] -cne $ip) { "drawn for $($was[0]) ($($was[1])), and this host is $name ($ip)" }
            if ($was[2] -cne $sum) { 'drawn from another configuration' }
        )
        if (-not $why.Count) { $why = @('drawn otherwise') }
        $checks.Add((New-UsaBannerCheck -Check 'drawn for this host' -State 'stale' -Detail "$($why -join '; '): the periodic job draws the banners again within 15 minutes"))
    }

    $linux = Join-Path $script:UsaBannerRoot 'linux'
    $after = @(
        Test-UsaBannerModuleFile -Root $root -Path $script:UsaLinuxMotd -Source (Join-Path $linux '05-usabanner') -Executable
        foreach ($file in $script:UsaLinuxScripts) { Test-UsaBannerModuleFile -Root $root -Path "$script:UsaLinuxShare/$file" -Source (Join-Path $linux $file) }
        Test-UsaBannerDrawnFile -Root $root -Path "$script:UsaLinuxState/postlogin.frame" -Want $(if ($drawing) { $drawing['Frame'] }) -Stale $stale
        Test-UsaBannerDrawnFile -Root $root -Path "$script:UsaLinuxState/login.env" -Want $(if ($drawing) { $drawing['LoginEnv'] }) -Stale $stale
    )
    $checks.Add((Join-UsaBannerFinding -Check 'banner after login' -Ok "pam_motd runs $script:UsaLinuxMotd at each login" -Found $after))
    $console = Test-UsaBannerDrawnFile -Root $root -Path $script:UsaLinuxIssue -Want $(if ($drawing) { $drawing['Issue'] }) -Stale $stale
    $checks.Add((Join-UsaBannerFinding -Check 'console banner' -Ok "agetty prints $script:UsaLinuxIssue before the login prompt" -Found @($console)))
    $checks.Add((Get-UsaBannerLinuxSshCheck -Root $root -Drawing $drawing -Stale $stale))
    $checks.Add((Get-UsaBannerLinuxMotdCheck -Root $root))
    $checks.Add((Get-UsaBannerLinuxJobCheck -Root $root))
    if ($common.Version) { $checks.Add((New-UsaBannerCheck -Check 'module copy' -State 'ok' -Detail "UsaBanner $($common.Version), for every user and the periodic job: $script:UsaLinuxModules/UsaBanner/$($common.Version)")) }
    else { $checks.Add((New-UsaBannerCheck -Check 'module copy' -State 'missing' -Detail "there is no copy in $script:UsaLinuxModules/UsaBanner, where the periodic job imports it from")) }
    $job = @()
    if ($config -and [string]$config['update']['mode'] -ne 'off') {
        $units = Get-UsaBannerUpdateUnits
        $job = @(
            foreach ($unit in $units.Keys) { Test-UsaBannerDrawnFile -Root $root -Path "/etc/systemd/system/$unit" -Want $units[$unit] -Stale $false }
            $timer = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-enabled', 'usabanner-update.timer').Output) + '')[0]
            if ($timer -ne 'enabled') { @{ State = 'differs'; Text = "usabanner-update.timer is $(if ($timer) { $timer } else { 'not known to systemd' }), not enabled" } }
        )
    }
    $checks.Add((Get-UsaBannerUpdateCheck -Config $config -State "$root$script:UsaLinuxState" -Found $job))
    $checks.Add((Get-UsaBannerOldBannerCheck -Found @(Find-UsaBannerLinuxOldInstall -Root $root)))

    New-UsaBannerStatus @common -HostName $name -Ip $ip -Deployed $true -Checks $checks.ToArray() -Services (Get-UsaBannerServicesText -Facts $facts) -Config $config
}

function Get-UsaBannerWindowsSshCheck {
    # In:  the layout, the configuration ($null when it cannot be read), and
    #      sshd.exe's path ('' when there is no sshd service)
    # Out: the SSH banner's check: sshd-banner.txt as the configuration draws
    #      it, sshd_config's Banner line in place, and sshd started since
    #      sshd_config last changed: it reads the file at its start, and a
    #      deploy leaves the restart to the admin
    param(
        [Parameter(Mandatory)][hashtable]$Layout,
        [AllowNull()][System.Collections.IDictionary]$Config,
        [AllowEmptyString()][string]$Sshd
    )
    if (-not $Sshd) {
        return New-UsaBannerCheck -Check 'ssh banner' -State 'off' -Detail 'OpenSSH''s server is not installed here (deploy-usawinssh installs it): run Deploy-UsaBanner again once it is'
    }
    $text = [System.IO.Path]::Combine($Layout.Data, 'sshd-banner.txt')
    $found = @(Test-UsaBannerDrawnFile -Path $text -Want $(if ($Config) { Get-UsaBannerWindowsSshText -Config $Config }) -Stale $false)
    if ($found[0].State -eq 'differs') { $found[0].Text = "$text is not what the configuration draws for $([System.Environment]::MachineName): Deploy-UsaBanner draws it again" }
    $note = ''
    if (-not [System.IO.File]::Exists($Layout.SshdConfig)) {
        $found += @{ State = 'missing'; Text = "there is no $($Layout.SshdConfig) yet: sshd writes it at its first start, then Deploy-UsaBanner adds the Banner line" }
    }
    else {
        $lines = $null
        try { $lines = @((Read-UsaBannerWindowsText -Path $Layout.SshdConfig).Text -split "\r?\n") }
        catch { $found += @{ State = 'unknown'; Text = "$($Layout.SshdConfig) cannot be read here: an administrator can read it" } }
        if ($null -ne $lines) {
            $result = Set-UsaBannerSshdBannerLine -Lines $lines
            if ($result.Changed) {
                if (@($lines | Where-Object { $_.Trim() -eq $script:UsaSshdEntry }).Count) { $found += @{ State = 'differs'; Text = "another Banner in $($Layout.SshdConfig) comes before the banner's, and sshd takes the first" } }
                else { $found += @{ State = 'missing'; Text = "$($Layout.SshdConfig) has no Banner line for it" } }
            }
            elseif ((Get-UsaBannerServiceState -Name 'sshd') -eq 'Running') {
                $started = Get-UsaBannerServiceStart -Name 'sshd'
                $changed = [System.IO.File]::GetLastWriteTimeUtc($Layout.SshdConfig)
                if ($started -and $started -lt $changed) {
                    $found += @{ State = 'stale'; Text = "sshd started at $($started.ToString('u')), before $($Layout.SshdConfig) last changed at $($changed.ToString('u')): it reads the Banner line at its next start (Restart-Service sshd)" }
                }
            }
            if (@($result.Scoped).Count) { $note = "; a Banner inside a Match block shows instead to the sessions it matches: $(@($result.Scoped) -join ', ')" }
        }
    }
    Join-UsaBannerFinding -Check 'ssh banner' -Ok "sshd sends $text before authentication$note" -Found $found
}

function Get-UsaBannerWindowsNoticeCheck {
    # In:  the configuration ($null when it cannot be read), and the record
    # Out: the logon notice's check. The banner sets it only where none is
    #      set, so one someone else set is off, not a fault
    param([AllowNull()][System.Collections.IDictionary]$Config, [System.Collections.IDictionary]$Record)
    $have = Read-UsaBannerLogonNoticeValue
    $ours = $Record['notice']
    $isOurs = $ours -and $have.Caption -ceq [string]$ours['caption'] -and $have.Text -ceq [string]$ours['text']
    if (-not ($have.Caption -or $have.Text)) {
        return New-UsaBannerCheck -Check 'logon notice' -State 'missing' -Detail 'no logon notice is set: Deploy-UsaBanner sets it where none is'
    }
    if (-not $isOurs) {
        return New-UsaBannerCheck -Check 'logon notice' -State 'off' -Detail "it holds someone else's text, set by hand or by a Group Policy: $($have.Caption)"
    }
    if (-not $Config) { return New-UsaBannerCheck -Check 'logon notice' -State 'unknown' -Detail 'what the configuration sets is not known' }
    $want = Get-UsaBannerLogonNotice -Config $Config
    if ($have.Caption -ceq $want.Caption -and $have.Text -ceq $want.Text) {
        return New-UsaBannerCheck -Check 'logon notice' -State 'ok' -Detail "$($have.Caption), before a console or RDP sign-in"
    }
    New-UsaBannerCheck -Check 'logon notice' -State 'differs' -Detail 'it holds the legal text of another configuration: Deploy-UsaBanner sets it again'
}

function Get-UsaBannerWindowsJobCheck {
    # In:  the banner's folder
    # Out: the periodic job's check: the task runs what a deploy registers,
    #      and a sample came within 20 minutes. Another user may not see a
    #      task SYSTEM runs: without an administrator, a task not found is
    #      unknown
    param([Parameter(Mandatory)][string]$Data)
    $pwsh = Find-UsaBannerPwsh
    if (-not $pwsh) { $pwsh = (Get-Process -Id $PID).Path }
    $spec = New-UsaBannerSampleTaskSpec -Pwsh $pwsh
    $task = Get-UsaBannerTask -Name $spec.Name
    $found = @()
    if (-not $task) {
        if (Test-UsaBannerPrivileged) { $found += @{ State = 'missing'; Text = "there is no task $($spec.Path)$($spec.Name)" } }
        else { $found += @{ State = 'unknown'; Text = "the task $($spec.Path)$($spec.Name) is not found: an administrator sees every task" } }
    }
    elseif ($task.Execute -ne $spec.Execute -or $task.Arguments -ne $spec.Arguments) {
        $found += @{ State = 'differs'; Text = "the task runs $($task.Execute) $($task.Arguments)" }
    }
    $sample = Get-UsaBannerSampleFinding -Path ([System.IO.Path]::Combine($Data, 'samples.tsv')) -Record ([System.IO.Path]::Combine($Data, 'deploy.json'))
    Join-UsaBannerFinding -Check 'periodic job' -Ok "the task $($spec.Path)$($spec.Name) samples every 15 minutes, as SYSTEM; $($sample.Text)" -Found ($found + @($sample))
}

function Get-UsaBannerWindowsStatus {
    <#
    .SYNOPSIS
    Get-UsaBanner's answer on Windows Server.
    .DESCRIPTION
    Out: the status (New-UsaBannerStatus). Each part a deploy writes is
    compared with what it would write from the host's configuration now;
    the registry, the task scheduler and the service manager say the rest.
    #>
    [CmdletBinding()]
    param()
    $layout = Get-UsaBannerWindowsLayout
    $jsonPath = [System.IO.Path]::Combine($layout.Data, 'usabanner.json')
    $dataPath = [System.IO.Path]::Combine($layout.Data, 'usabanner.psd1')
    $sshd = [string](Get-UsaBannerWindowsSshd)
    $ssh = if (-not $sshd) { 'not installed' } elseif ((Get-UsaBannerServiceState -Name 'sshd') -eq 'Running') { 'open' } else { 'closed' }
    $common = @{ Os = 'windows'; Version = (Get-UsaBannerModuleVersion -Folder $layout.Modules); Ssh = $ssh }
    if (-not [System.IO.File]::Exists($jsonPath)) {
        $facts = Get-UsaBannerHostFacts -Services @()
        $detail = "there is no ${jsonPath}: no banner is deployed here"
        $old = @(Find-UsaBannerWindowsOldInstall -Layout $layout)
        if ($old.Count) { $detail += ". This host has the banner of this repository's Install-ManatechBanner.ps1 ($($old -join ', ')), which Deploy-UsaBanner -ReplaceOldBanner takes off before it deploys this one" }
        return New-UsaBannerStatus @common -HostName ([string]$facts['Name']) -Ip ([string]$facts['Ip']) -Deployed $false -Checks @(New-UsaBannerCheck -Check 'configuration' -State 'missing' -Detail $detail)
    }

    $checks = [System.Collections.Generic.List[object]]::new()
    $config = $null
    try { $config = Read-UsaBannerConfig -Path $jsonPath }
    catch { $checks.Add((New-UsaBannerCheck -Check 'configuration' -State 'invalid' -Detail $_.Exception.Message)) }
    if ($config) {
        $data = Test-UsaBannerDrawnFile -Path $dataPath -Want (ConvertTo-UsaBannerDataFile -Config $config) -Stale $false
        if ($data.State -eq 'differs') { $data.Text = "$dataPath, which each login reads, does not hold the settings of usabanner.json: Deploy-UsaBanner writes it again" }
        $checks.Add((Join-UsaBannerFinding -Check 'configuration' -Ok "$jsonPath, and the same as data for each login: usabanner.psd1" -Found @($data)))
    }
    $facts = Get-UsaBannerHostFacts -Services $(if ($config) { $config['services'] } else { @() })

    $block = @(New-UsaBannerProfileBlock -DataFile $dataPath)
    $profiles = @(foreach ($path in $layout.Profiles) {
            $text = (Read-UsaBannerWindowsText -Path $path).Text
            if ((Set-UsaBannerProfileText -Text $text -Block $block) -ceq $text) { continue }
            if ($text.Contains($script:UsaProfileBegin)) { @{ State = 'differs'; Text = "$path holds another block than a deploy writes" } }
            else { @{ State = 'missing'; Text = "$path has no block" } }
        })
    $checks.Add((Join-UsaBannerFinding -Check 'banner after login' -Ok "a block in each PowerShell's all-users profile shows it at an SSH login: $($layout.Profiles -join ', ')" -Found $profiles))
    $checks.Add((Get-UsaBannerWindowsSshCheck -Layout $layout -Config $config -Sshd $sshd))

    if (-not $sshd) { $checks.Add((New-UsaBannerCheck -Check 'ssh default shell' -State 'off' -Detail 'OpenSSH''s server is not installed here')) }
    else {
        $leaf = Get-UsaBannerSshShellName
        if ($leaf -in 'pwsh.exe', 'powershell.exe') { $checks.Add((New-UsaBannerCheck -Check 'ssh default shell' -State 'ok' -Detail "sshd starts $leaf at a login, whose profile shows the banner")) }
        else { $checks.Add((New-UsaBannerCheck -Check 'ssh default shell' -State 'differs' -Detail "sshd starts $leaf at a login, so no banner shows after an SSH login: Deploy-UsaBanner sets a PowerShell there")) }
    }

    $record = Read-UsaBannerDeployRecord -Path ([System.IO.Path]::Combine($layout.Data, 'deploy.json'))
    $checks.Add((Get-UsaBannerWindowsNoticeCheck -Config $config -Record $record))
    $checks.Add((Get-UsaBannerWindowsJobCheck -Data $layout.Data))
    $danger = @(foreach ($place in [System.IO.Path]::GetDirectoryName($layout.Data), $layout.Data) {
            if (-not [System.IO.Directory]::Exists($place)) { continue }
            foreach ($why in @(Get-UsaBannerFolderDanger -Path $place -Tree:($place -eq $layout.Data))) { "${place}: $why" }
        })
    if ($danger.Count) { $checks.Add((New-UsaBannerCheck -Check 'folder acl' -State 'invalid' -Detail "$($danger -join '; '). Whoever that is could have the periodic job, as SYSTEM, write wherever a link points; Deploy-UsaBanner refuses this folder until someone looks")) }
    elseif (Test-UsaBannerFolderAcl -Path $layout.Data) { $checks.Add((New-UsaBannerCheck -Check 'folder acl' -State 'ok' -Detail "$($layout.Data) is owned by Administrators: Administrators and SYSTEM may change it, Users read it")) }
    else { $checks.Add((New-UsaBannerCheck -Check 'folder acl' -State 'differs' -Detail "$($layout.Data) does not have the banner's ACL, so others may change the banners every login shows: Deploy-UsaBanner sets it again")) }
    if ($common.Version) { $checks.Add((New-UsaBannerCheck -Check 'module copy' -State 'ok' -Detail "UsaBanner $($common.Version), for every user and the periodic job: $([System.IO.Path]::Combine($layout.Modules, 'UsaBanner', [string]$common.Version))")) }
    else { $checks.Add((New-UsaBannerCheck -Check 'module copy' -State 'missing' -Detail "there is no copy in $([System.IO.Path]::Combine($layout.Modules, 'UsaBanner')), where every login and the periodic job import it from")) }
    $job = @()
    if ($config -and [string]$config['update']['mode'] -ne 'off') {
        $pwsh = Find-UsaBannerPwsh
        if (-not $pwsh) { $pwsh = (Get-Process -Id $PID).Path }
        $spec = New-UsaBannerUpdateTaskSpec -Pwsh $pwsh
        $task = Get-UsaBannerTask -Name $spec.Name
        if (-not $task) {
            if (Test-UsaBannerPrivileged) { $job += @{ State = 'missing'; Text = "there is no task $($spec.Path)$($spec.Name)" } }
            else { $job += @{ State = 'unknown'; Text = "the task $($spec.Path)$($spec.Name) is not found: an administrator sees every task" } }
        }
        elseif ($task.Execute -ne $spec.Execute -or $task.Arguments -ne $spec.Arguments) { $job += @{ State = 'differs'; Text = "the task $($spec.Name) runs $($task.Execute) $($task.Arguments)" } }
    }
    $checks.Add((Get-UsaBannerUpdateCheck -Config $config -State $layout.Data -Found $job))
    $checks.Add((Get-UsaBannerOldBannerCheck -Found @(Find-UsaBannerWindowsOldInstall -Layout $layout)))

    New-UsaBannerStatus @common -HostName ([string]$facts['Name']) -Ip ([string]$facts['Ip']) -Deployed $true -Checks $checks.ToArray() -Services (Get-UsaBannerServicesText -Facts $facts) -Config $config
}

function ConvertFrom-UsaBannerIssueText {
    <#
    .SYNOPSIS
    An issue file's text as agetty prints it.
    .DESCRIPTION
    In:  the file's text, and the host's name and IPv4 address.
    Out: its lines, the blank ones at its end left out. \\ prints a
         backslash, \e the escape character, \n the host's name and \4 its
         address; for any other escape agetty prints the character after
         the backslash (util-linux 2.39, term-utils/agetty.c,
         output_special_char), and so does this. The reverse of
         ConvertTo-UsaBannerIssueLine.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [AllowEmptyString()][string]$HostName = '',
        [AllowEmptyString()][string]$Ip = ''
    )
    $printed = $Text -replace '\\(.)', {
        switch -CaseSensitive ($_.Groups[1].Value) {
            'e' { [string][char]27 }
            'n' { $HostName }
            '4' { $Ip }
            default { $_ }
        }
    }
    ($printed -replace '\n+$', '') -split "`n"
}

function Get-UsaBannerInstalled {
    <#
    .SYNOPSIS
    One of this host's banners, as it is installed: Get-UsaBanner -Moment.
    .DESCRIPTION
    In:  the moment: PostLogon, PreLogon or PreInit.
    Out: its lines. Throws when no banner is deployed here, or the file that
         holds the moment's banner is missing.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][ValidateSet('PostLogon', 'PreLogon', 'PreInit')][string]$Moment)
    $none = 'UsaBanner: no banner is deployed here, so there is none to show. Deploy-UsaBanner deploys one; Show-UsaBanner draws one from a configuration.'
    $lines = {
        # In:  a file's text, or $null
        # Out: its lines, the blank ones at its end left out
        # Why: the banners before login end in a blank line, so the prompt
        #      does not touch the box; Show-UsaBanner leaves it out too
        param($Text, [string]$Path)
        if ($null -eq $Text) { throw "UsaBanner: $Path is missing: Deploy-UsaBanner writes it." }
        ([string]$Text -replace '\n+$', '') -split "`n"
    }
    if ((Get-UsaBannerHostOs) -eq 'windows') {
        $layout = Get-UsaBannerWindowsLayout
        $data = [System.IO.Path]::Combine($layout.Data, 'usabanner.psd1')
        if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($layout.Data, 'usabanner.json'))) { throw $none }
        switch ($Moment) {
            'PreInit' {
                $notice = Read-UsaBannerLogonNoticeValue
                if (-not ($notice.Caption -or $notice.Text)) { Write-Warning 'UsaBanner: no logon notice is set here.'; return }
                ConvertTo-UsaBannerNoticeText -Notice $notice
            }
            'PreLogon' {
                $path = [System.IO.Path]::Combine($layout.Data, 'sshd-banner.txt')
                & $lines (Read-UsaBannerHostText -Path $path) $path
            }
            'PostLogon' { Show-UsaBanner -Path $data }
        }
        return
    }
    $root = Get-UsaBannerHostRoot
    if (-not [System.IO.File]::Exists("$root$script:UsaLinuxEtc/usabanner.json")) { throw $none }
    switch ($Moment) {
        'PreInit' {
            $issue = Read-UsaBannerHostText -Root $root -Path $script:UsaLinuxIssue
            if ($null -eq $issue) { throw "UsaBanner: $script:UsaLinuxIssue is missing: Deploy-UsaBanner writes it." }
            $facts = Get-UsaBannerHostFacts -Services @()
            # agetty's \n is the kernel's name for the host, without a domain.
            $short = ([string]$facts['Name'] -split '\.')[0]
            ConvertFrom-UsaBannerIssueText -Text $issue -HostName $short -Ip ([string]$facts['Ip'])
        }
        'PreLogon' { & $lines (Read-UsaBannerHostText -Root $root -Path "$script:UsaLinuxEtc/issue.net") "$script:UsaLinuxEtc/issue.net" }
        'PostLogon' {
            $run = Invoke-UsaBannerNative -FilePath 'sh' -ArgumentList $script:UsaLinuxMotd
            if ($run.ExitCode -ne 0) { throw "UsaBanner: $script:UsaLinuxMotd failed (exit code $($run.ExitCode)): $(@($run.Output) -join ' ')" }
            $run.Output
        }
    }
}
