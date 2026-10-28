# OldBanner.ps1 - the old banner, which this repository's install.sh and
# Install-ManatechBanner.ps1 install, taken off a host so that this banner
# takes its place (docs/DECISIONS.md, D23). Deploy-UsaBanner -ReplaceOldBanner
# does it after it has drawn every banner, and before it changes anything
# else:
#
#   +----------------+--------------------------------------------------------+
#   | On             | Taken off                                              |
#   +----------------+--------------------------------------------------------+
#   | Ubuntu         | its jobs (manatech-motd-update.timer, and              |
#   |                | manatech-motd-publish.path where Group Policy delivers |
#   |                | it): stopped with a run in progress, their units       |
#   |                | deleted, their failed state cleared; what --retire     |
#   |                | turned off, back on as Ubuntu ships it: four stock     |
#   |                | MOTD scripts, landscape-sysinfo, motd-news.timer; its  |
#   |                | sshd drop-in (ssh reloads); its MOTD scripts, console  |
#   |                | file and folders; the copy of its repository its timer |
#   |                | ran install.sh from (a git clone, as the README sets   |
#   |                | one up)                                                |
#   | Windows Server | its tasks; its block in both all-users profiles; its   |
#   |                | Banner line in sshd_config, with each Banner it turned |
#   |                | off back on, and the prototype banner's line (on, or   |
#   |                | behind this banner's note), checked with sshd -t; its  |
#   |                | SSH banner file; the git clone its update task pulled  |
#   |                | into; its folder                                       |
#   +----------------+--------------------------------------------------------+
#
# The old banner kept no record, so what it changed comes back as the OS ships
# it. The deploy that follows turns the same stock scripts off again, on its
# own record this time, so Remove-UsaBanner turns them back on. A clone's
# remote URL can hold a deploy token (the README's private-fork steps): the
# clone goes, and a warning says to revoke the token, which works until it is.
# Left as they are: the OpenSSH default shell where it is a PowerShell (this
# banner sets one where it is not, D21), and sshd_config.manatech-bak, the old
# installer's copy of sshd_config. A Group Policy that delivers the old banner
# delivers it again at the next boot or policy refresh, so its GPO comes off
# the host first (D23); Get-UsaBanner's "old banner" check says when the old
# banner is back.
#
# What the deploy's record holds of what --retire turns off, this banner
# turned off, and it stays off: on a host this banner is on already, turning
# it on would only have the deploy turn it off again, at every deploy.

# The stock MOTD scripts install.sh --retire turns off (chmod -x).
$script:UsaOldRetired = @('00-header', '10-help-text', '50-motd-news', '98-reboot-required')
# Its jobs, and every unit of them.
$script:UsaOldJobs = @('manatech-motd-update.timer', 'manatech-motd-publish.path')
$script:UsaOldUnits = @('manatech-motd-update.timer', 'manatech-motd-update.service', 'manatech-motd-publish.path', 'manatech-motd-publish.service')
# Its sshd drop-in, under the name it has, and the one it had.
$script:UsaOldDropIns = @('/etc/ssh/sshd_config.d/00-manatech-banner.conf', '/etc/ssh/sshd_config.d/10-manatech-banner.conf')
$script:UsaOldFiles = [ordered]@{
    '/etc/update-motd.d/05-manatech-banner' = 'the old banner after login'
    '/etc/update-motd.d/15-manatech-health' = 'the old banner''s health lines'
    '/etc/issue.d/50-manatech.issue'        = 'the old banner''s console banner'
}
$script:UsaOldFolders = [ordered]@{
    '/etc/manatech'             = 'the old banner''s settings and SSH banner'
    '/usr/local/share/manatech' = 'the old banner''s code and data'
    '/var/lib/manatech'         = 'the old banner''s cached facts'
}
# Where ADSys keeps the policy it applies, a folder for the machine and each
# user; and the startup script the old banner's GPO has it run, as
# Publish-ManatechMotd.ps1 sets it.
$script:UsaAdsysPolicies = '/var/cache/adsys/policies'
$script:UsaOldAdsysScript = 'MOTD/adsys-startup.sh'
# Where deb-systemd-helper records each timer a package enabled.
$script:UsaDebEnabledTimers = '/var/lib/systemd/deb-systemd-helper-enabled/timers.target.wants'

# Install-ManatechBanner.ps1's marks: its profile block, its Banner line, and
# the note it puts before a Banner it turns off.
$script:UsaOldProfileBegin = '# >>> Manatech banner (Install-ManatechBanner.ps1) >>>'
$script:UsaOldProfileEnd = '# <<< Manatech banner <<<'
$script:UsaOldSshdEntry = 'Banner __PROGRAMDATA__/ssh/manatech-banner.txt'
$script:UsaOldSshdNote = '^# replaced by Install-ManatechBanner\.ps1 on \d{4}-\d{2}-\d{2}: (.*)$'
# The prototype banner's Banner line: a banner set up by hand before
# Install-ManatechBanner.ps1, whose line a Group Policy's copy of sshd_config
# carried to servers that never had that banner. A deploy before 0.2.2 turned
# it off behind its note, which Remove-UsaBanner would turn back on.
$script:UsaPrototypeSshdEntry = 'Banner C:\ProgramData\ssh\banner.txt'
# Its tasks, in the task scheduler's root folder: its own update task, and the
# one the "Manatech MOTD" GPO makes.
$script:UsaOldTasks = @('Manatech banner update', 'Manatech MOTD sync')
$script:UsaOldGpoTask = 'Manatech MOTD sync'
$script:UsaOldUpdateTask = 'Manatech banner update'
# The unit whose ExecStart names the copy of the repository the old timer ran
# install.sh from (units_clone in units.sh); where Group Policy delivers it,
# the unit runs adsys-startup.sh from ADSys's copy of SYSVOL instead.
$script:UsaOldUpdateUnit = '/etc/systemd/system/manatech-motd-update.service'
# Two files every copy of the old banner's repository holds: a folder is
# deleted as one only when it has both.
$script:UsaOldRepoFiles = @('install.sh', 'windows/Install-ManatechBanner.ps1')

function Enable-UsaBannerExecutable {
    # In:  the host's root, a script's path on the host, and what it is
    # Out: a line when it was turned back on, its execute bits set as
    #      chmod +x sets them; nothing when it is missing, a link, or on
    #      already
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$What
    )
    $info = [System.IO.FileInfo]::new("$Root$Path")
    if ($info.LinkTarget -or -not $info.Exists) { return }
    $mode = [System.IO.File]::GetUnixFileMode($info.FullName)
    if (([int]$mode -band [int]$script:UsaExecBits) -ne 0) { return }
    if (-not $PSCmdlet.ShouldProcess($Path, "Turn $What back on (chmod +x)")) { return }
    [System.IO.File]::SetUnixFileMode($info.FullName, [System.IO.UnixFileMode]([int]$mode -bor [int]$script:UsaExecBits))
    "turned back on ${Path}: $What"
}

function Remove-UsaBannerLinuxOldInstall {
    <#
    .SYNOPSIS
    Takes the old banner, this repository's install.sh, off this Ubuntu host.
    .DESCRIPTION
    In:  the host's root, and the record of this banner's deploys
         (Read-UsaBannerDeployRecord).
    Out: a line for each change, in the order made. Under -WhatIf,
         PowerShell says each change instead, and nothing changes.
    Its jobs stop first, a run of each in progress too, so they install
    nothing more while it goes; their units are deleted, and each that is
    failed has its failed state cleared, so none stays in systemctl's failed
    list without its unit. Then
    what --retire turned off comes back on as Ubuntu ships it: the stock
    MOTD scripts; landscape-sysinfo, its statoverride removed (or, for a
    file no package owns, its execute bits set); motd-news.timer, unmasked,
    and started, or enabled again where its package enabled it and the
    first install.sh disabled it. Then its sshd drop-in (ssh reloads), its
    MOTD scripts and console file (and /etc/issue.d, when that leaves it
    empty: install.sh made it), its folders, and the copy of its repository
    its timer ran install.sh from, which the timer's unit names, so it is
    read before the unit goes. Where ADSys still applies a GPO that runs the
    old banner's startup script, a warning says it puts the old banner back
    at the next boot.
    What the record holds of what --retire turned off, this banner turned
    off, and it stays off: on a host this banner is on already, the deploy
    would only turn it off again.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [System.Collections.IDictionary]$Record = @{}
    )
    $repo = Get-UsaBannerOldLinuxRepo -Root $Root
    foreach ($unit in $script:UsaOldJobs) {
        $service = [System.IO.Path]::ChangeExtension($unit, 'service')
        if ([System.IO.File]::Exists("$Root/etc/systemd/system/$unit") -and
            $PSCmdlet.ShouldProcess($unit, "Stop and disable the old banner's job (systemctl disable --now), and stop a run of it in progress (systemctl stop $service)")) {
            $disable = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'disable', '--now', $unit
            if ($disable.ExitCode -eq 0) { "stopped ${unit}: the old banner's job" }
            else { Write-Warning "UsaBanner: systemctl could not disable ${unit}: $($disable.Output -join ' ')" }
            # The trigger stopped, a run it started goes on, and its unit is deleted under it: the
            # publish watcher's run, in its 30-second sleep, then had nothing left to start, and
            # systemd failed it ('resources', a production host, 2026-10-28).
            $stop = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'stop', $service
            if ($stop.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not stop ${service}: $($stop.Output -join ' ')" }
        }
    }
    $gone = @(foreach ($unit in $script:UsaOldUnits) { Remove-UsaBannerHostFile -Root $Root -Path "/etc/systemd/system/$unit" -What 'a unit of the old banner''s job' })
    $gone
    if ($gone.Count) {
        $reload = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'daemon-reload'
        if ($reload.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl daemon-reload failed: $($reload.Output -join ' ')" }
    }
    # A unit deleted while failed stays in systemctl's failed list, and in the "failed units" line
    # at each login, until it is reset: the old update job had failed before a move-off (a test
    # host, 2026-10-27), and a run stopped part way ends failed. Every unit of the old jobs, so a
    # host an earlier deploy moved off is cleared at its next one.
    foreach ($unit in $script:UsaOldUnits) {
        $state = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-failed', $unit).Output) + '')[0]
        if ($state -eq 'failed' -and $PSCmdlet.ShouldProcess($unit, 'Clear its failed state: its unit is gone, and it would stay in systemctl''s failed list (systemctl reset-failed)')) {
            $reset = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'reset-failed', $unit
            if ($reset.ExitCode -eq 0) { "cleared the failed state of ${unit}: a unit of the old banner's job" }
            else { Write-Warning "UsaBanner: systemctl could not reset ${unit}: $($reset.Output -join ' ')" }
        }
    }

    # What this banner's deploys turned off is on their record, and stays off (lab, 2026-10-25).
    $ours = @(@($Record['retired']) + @($Record['statoverride']) | Where-Object { $_ } | ForEach-Object { [string]$_['path'] })
    foreach ($name in $script:UsaOldRetired) {
        if ("/etc/update-motd.d/$name" -cin $ours) { continue }
        Enable-UsaBannerExecutable -Root $Root -Path "/etc/update-motd.d/$name" -What 'a stock MOTD script the old banner turned off'
    }
    $link = [System.IO.FileInfo]::new("$Root/etc/update-motd.d/50-landscape-sysinfo")
    $target = [string]$link.LinkTarget
    if ($target -and -not $target.StartsWith('/')) { $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine('/etc/update-motd.d', $target)) }
    if ($target -and $target -cnotin $ours) {
        $listed = Invoke-UsaBannerNative -FilePath 'dpkg-statoverride' -ArgumentList '--list', $target
        if ($listed.ExitCode -eq 0 -and [string](@($listed.Output) + '')[0] -match '^root root 0?644 ') {
            if ($PSCmdlet.ShouldProcess($target, 'Remove the dpkg statoverride the old banner put on it (root root 0644), and turn it back on')) {
                $removed = Invoke-UsaBannerNative -FilePath 'dpkg-statoverride' -ArgumentList '--remove', $target
                if ($removed.ExitCode -ne 0) { Write-Warning "UsaBanner: dpkg-statoverride could not remove the override of ${target}: $($removed.Output -join ' ')" }
                else {
                    $file = "$Root$target"
                    if ([System.IO.File]::Exists($file)) { [System.IO.File]::SetUnixFileMode($file, [System.IO.UnixFileMode]([int][System.IO.File]::GetUnixFileMode($file) -bor [int]$script:UsaExecBits)) }
                    "removed the dpkg statoverride the old banner put on ${target}: /etc/update-motd.d/50-landscape-sysinfo runs again"
                }
            }
        }
        elseif ((Invoke-UsaBannerNative -FilePath 'dpkg' -ArgumentList '-S', $target).ExitCode -ne 0) {
            Enable-UsaBannerExecutable -Root $Root -Path $target -What 'the landscape-sysinfo MOTD script, which the old banner turned off'
        }
    }
    $oursMasked = @(@($Record['masked']) | Where-Object { $_ -and [string]$_['unit'] -ceq 'motd-news.timer' }).Count -gt 0
    $state = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-enabled', 'motd-news.timer').Output) + '')[0]
    if ($state -eq 'masked' -and -not $oursMasked -and $PSCmdlet.ShouldProcess('motd-news.timer', 'Unmask it, which the old banner masked, and start it, enabling it again where its package enabled it (systemctl unmask)')) {
        $unmasked = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'unmask', 'motd-news.timer'
        if ($unmasked.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not unmask motd-news.timer: $($unmasked.Output -join ' ')" }
        else {
            # The first install.sh also ran systemctl disable --now, which a
            # later one's mask hid: its package enabled it, as
            # deb-systemd-helper's record says (lab, 2026-10-23).
            $enabled = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-enabled', 'motd-news.timer').Output) + '')[0]
            $verb = if ($enabled -eq 'enabled') { 'start' } elseif ([System.IO.File]::Exists("$Root$script:UsaDebEnabledTimers/motd-news.timer")) { 'enable' }
            if ($verb) {
                $arguments = if ($verb -eq 'enable') { @('enable', '--now', 'motd-news.timer') } else { @('start', 'motd-news.timer') }
                $result = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList $arguments
                if ($result.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not $verb motd-news.timer: $($result.Output -join ' ')" }
            }
            if ($verb -eq 'enable') { 'unmasked and enabled motd-news.timer: the old banner masked it, and its first install.sh disabled it' }
            else { 'unmasked motd-news.timer: the old banner masked it' }
        }
    }

    $dropIns = @(foreach ($path in $script:UsaOldDropIns) { Remove-UsaBannerHostFile -Root $Root -Path $path -What 'the old banner''s sshd Banner line' })
    $dropIns
    if ($dropIns.Count) {
        $reload = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'try-reload-or-restart', 'ssh'
        if ($reload.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not reload ssh: $($reload.Output -join ' ')" }
    }
    foreach ($path in $script:UsaOldFiles.Keys) { Remove-UsaBannerHostFile -Root $Root -Path $path -What $script:UsaOldFiles[$path] }
    # install.sh made /etc/issue.d where it was missing, and no package ships
    # it (dpkg -S, Ubuntu 24.04.5): empty once the old file goes, it goes too.
    $issueFolder = "$Root/etc/issue.d"
    if ([System.IO.Directory]::Exists($issueFolder) -and @([System.IO.Directory]::GetFileSystemEntries($issueFolder)).Count -eq 0 -and
        $PSCmdlet.ShouldProcess('/etc/issue.d', 'Delete the empty folder: install.sh made it, and no package ships it')) {
        [System.IO.Directory]::Delete($issueFolder)
        'deleted the empty folder /etc/issue.d: install.sh made it, and no package ships it'
    }
    foreach ($folder in $script:UsaOldFolders.Keys) { Remove-UsaBannerHostFolder -Root $Root -Path $folder -What $script:UsaOldFolders[$folder] }
    if ($repo) { Remove-UsaBannerOldRepo -Root $Root -Path $repo -What 'its timer ran install.sh from' }
    if (Test-UsaBannerOldAdsysPolicy -Root $Root) {
        Write-Warning "UsaBanner: a Group Policy that ADSys applies here runs the old banner's startup script ($script:UsaOldAdsysScript), which puts the old banner back at the next boot: take that GPO off this host (D23). Get-UsaBanner's old banner check says when it is back."
    }
}

function Test-UsaBannerOldAdsysPolicy {
    # In:  the host's root
    # Out: $true when the policy ADSys applies here runs the old banner's
    #      startup script
    # Why: ADSys's copy of SYSVOL keeps the old banner's files while any GPO
    #      applies, its GPO linked or not (lab, 2026-10-23); the policy it
    #      applies says whether one still runs them at the next boot
    param([AllowEmptyString()][string]$Root = '')
    $folder = "$Root$script:UsaAdsysPolicies"
    if (-not [System.IO.Directory]::Exists($folder)) { return $false }
    foreach ($file in [System.IO.Directory]::GetFiles($folder, 'policies', [System.IO.SearchOption]::AllDirectories)) {
        try { $lines = [System.IO.File]::ReadAllLines($file) }
        catch [System.UnauthorizedAccessException], [System.IO.IOException] { continue }
        if (@($lines | Where-Object { $_.Trim() -ceq $script:UsaOldAdsysScript }).Count) { return $true }
    }
    $false
}

function Remove-UsaBannerOldSshdBannerLine {
    <#
    .SYNOPSIS
    sshd_config's lines without the old banner's Banner line, or the
    prototype banner's.
    .DESCRIPTION
    Out: @{ Lines; Changed; Old; Prototype }. Old: Install-ManatechBanner.ps1's
         Banner line taken out, with the blank line it always put after it,
         and each Banner it turned off ("# replaced by
         Install-ManatechBanner.ps1 on <date>: ") back as it was. Prototype:
         the prototype banner's line taken out, whether it is on, behind this
         banner's note, or behind the old banner's. A line is the prototype's
         when, trimmed, it is that line in any case, as sshd reads the keyword
         and Windows the path; one naming another path stays. Changed: either.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyCollection()][string[]]$Lines = @())
    $new = [System.Collections.Generic.List[string]]::new()
    $old = $false
    $prototype = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq $script:UsaOldSshdEntry) {
            $old = $true
            if ($i + 1 -lt $Lines.Count -and $Lines[$i + 1] -eq '') { $i++ }
            continue
        }
        if ($Lines[$i] -match $script:UsaOldSshdNote) {
            $old = $true
            if ($Matches[1].Trim() -eq $script:UsaPrototypeSshdEntry) { $prototype = $true }
            else { $new.Add($Matches[1]) }
            continue
        }
        $line = $Lines[$i]
        if ($line.StartsWith($script:UsaSshdNote)) { $line = $line.Substring($script:UsaSshdNote.Length) }
        if ($line.Trim() -eq $script:UsaPrototypeSshdEntry) {
            $prototype = $true
            continue
        }
        $new.Add($Lines[$i])
    }
    @{ Lines = $new.ToArray(); Changed = $old -or $prototype; Old = $old; Prototype = $prototype }
}

function Remove-UsaBannerWindowsOldInstall {
    <#
    .SYNOPSIS
    Takes the old banner, this repository's Install-ManatechBanner.ps1, off
    this Windows host.
    .DESCRIPTION
    In:  the layout (Get-UsaBannerWindowsLayout).
    Out: a line for each change, in the order made. Under -WhatIf,
         PowerShell says each change instead, and nothing changes.
    Its tasks go first, so they install nothing more while it goes. Then its
    block in both all-users profiles; its Banner line in sshd_config, with
    each Banner it turned off back on, and the prototype banner's line, in one
    write (sshd -t checks the file, and one it refuses is put back; sshd is
    not restarted); its SSH banner file; the git
    clone its update task pulled into, which the task names, so it is read
    before the task goes (the README puts the clone in the old banner's
    folder); its folder. The task a Group Policy makes comes back at the
    next policy refresh while the GPO applies: a warning says so.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$Layout)
    $repo = Get-UsaBannerOldWindowsRepo
    foreach ($name in $script:UsaOldTasks) {
        if ((Get-UsaBannerTask -Path '\' -Name $name) -and $PSCmdlet.ShouldProcess("\$name", 'Unregister the old banner''s task')) {
            Unregister-UsaBannerTask -Path '\' -Name $name
            "unregistered the task \${name}: the old banner's"
            if ($name -eq $script:UsaOldGpoTask) {
                Write-Warning "UsaBanner: the Manatech MOTD GPO makes the task \$name, and makes it again at the next policy refresh while it applies to this host: take that GPO off this host (D23). Get-UsaBanner's old banner check says when the old banner is back."
            }
        }
    }
    foreach ($path in $Layout.Profiles) {
        if (-not [System.IO.File]::Exists($path)) { continue }
        $file = Read-UsaBannerWindowsText -Path $path
        $text = Remove-UsaBannerProfileText -Text $file.Text -Begin $script:UsaOldProfileBegin -End $script:UsaOldProfileEnd
        if ($text -ceq $file.Text) { continue }
        if ($PSCmdlet.ShouldProcess($path, 'Take out the old banner''s block')) {
            if ($text) { [System.IO.File]::WriteAllBytes($path, (ConvertTo-UsaBannerWindowsBytes -Text $text -Encoding $file.Encoding)) }
            else { [System.IO.File]::Delete($path) }
            "took the old banner's block out of $path"
        }
    }
    if ([System.IO.File]::Exists($Layout.SshdConfig)) {
        $file = Read-UsaBannerWindowsText -Path $Layout.SshdConfig
        $eol = if ($file.Text -match "`r`n") { "`r`n" } else { "`n" }
        $result = Remove-UsaBannerOldSshdBannerLine -Lines @($file.Text -split "\r?\n")
        $actions = @(
            if ($result.Old) { 'Take out the old banner''s Banner line, and turn back on any Banner it turned off' }
            if ($result.Prototype) { "Take out the prototype banner's Banner line: $script:UsaPrototypeSshdEntry" }
        )
        if ($result.Changed -and $PSCmdlet.ShouldProcess($Layout.SshdConfig, ($actions -join '; '))) {
            $backup = "$($Layout.SshdConfig).usabanner-bak"
            [System.IO.File]::Copy($Layout.SshdConfig, $backup, $true)
            [System.IO.File]::WriteAllBytes($Layout.SshdConfig, (ConvertTo-UsaBannerWindowsBytes -Text ($result.Lines -join $eol) -Encoding $file.Encoding))
            $sshd = Get-UsaBannerWindowsSshd
            $test = if ($sshd) { Invoke-UsaBannerNative -FilePath $sshd -ArgumentList '-t' } else { @{ ExitCode = 0; Output = @() } }
            if ($test.ExitCode -ne 0) {
                [System.IO.File]::Copy($backup, $Layout.SshdConfig, $true)
                $without = @(
                    if ($result.Old) { 'the old banner''s Banner line' }
                    if ($result.Prototype) { 'the prototype banner''s Banner line' }
                ) -join ' and '
                Write-Warning "UsaBanner: sshd -t refused sshd_config without $without, so it is put back: $(@($test.Output) -join ' ')"
            }
            else {
                [System.IO.File]::Delete($backup)
                if ($result.Old) { "took the old banner's Banner line out of $($Layout.SshdConfig)" }
                if ($result.Prototype) { "took the prototype banner's Banner line out of $($Layout.SshdConfig): $script:UsaPrototypeSshdEntry" }
            }
        }
    }
    Remove-UsaBannerHostFile -Root '' -Path $Layout.OldSshText -What 'the old banner''s SSH banner'
    if ($repo) { Remove-UsaBannerOldRepo -Path $repo -What 'its update task pulled into' -Windows }
    Remove-UsaBannerWindowsFolder -Path $Layout.OldData -Allowed $Layout.OldData -What 'the old banner: its module, data, settings and logs'
}

function Get-UsaBannerOldLinuxRepo {
    # In:  the host's root
    # Out: the copy of the old banner's repository its timer ran install.sh
    #      from, as the timer's unit names it (ExecStart=/bin/sh <copy>/
    #      install.sh); nothing without that unit, or where it runs
    #      adsys-startup.sh, as it does where Group Policy delivers the banner
    param([AllowEmptyString()][string]$Root = '')
    $unit = "$Root$script:UsaOldUpdateUnit"
    if (-not [System.IO.File]::Exists($unit)) { return }
    foreach ($line in [System.IO.File]::ReadAllLines($unit)) {
        if ($line -match '^ExecStart=/bin/sh (/\S+)/install\.sh(\s|$)') { return $Matches[1] }
    }
}

function Get-UsaBannerOldWindowsRepo {
    # Out: the git clone the old banner's update task pulled into, as the
    #      task names the script it runs (<clone>\windows\
    #      Update-ManatechBanner.ps1, Install-ManatechBanner.ps1 -UpdateTask);
    #      nothing without that task
    $task = Get-UsaBannerTask -Path '\' -Name $script:UsaOldUpdateTask
    if ($task -and [string]$task.Arguments -match '-File\s+"?(.+?)[\\/]windows[\\/]Update-ManatechBanner\.ps1"?(\s|$)') { $Matches[1] }
}

function Test-UsaBannerOldRepo {
    # In:  a folder
    # Out: $true when it holds a copy of the old banner's repository: both
    #      of its own files
    # Why: the folder's path comes from a unit or a task, which anyone who
    #      may change those could have pointed elsewhere
    param([Parameter(Mandatory)][string]$Path)
    @($script:UsaOldRepoFiles | Where-Object { -not [System.IO.File]::Exists([System.IO.Path]::Combine($Path, $_)) }).Count -eq 0
}

function Test-UsaBannerRepoSignIn {
    # In:  a copy of a repository
    # Out: $true when a remote URL in its .git/config holds sign-in details
    #      (https://user:token@host/...), as the README's private-fork steps
    #      clone it; $null when the file is there and cannot be read, so no
    #      one can say; $false otherwise. The URL itself is never returned
    # Why: Install-ManatechBanner.ps1 -UpdateTask sets the clone's ACL with
    #      icacls /T, which leaves each file already in it with no access for
    #      anyone, Administrators included (lab, 2026-10-23)
    param([Parameter(Mandatory)][string]$Path)
    $config = [System.IO.Path]::Combine($Path, '.git', 'config')
    if (-not [System.IO.File]::Exists($config)) { return $false }
    try { $lines = [System.IO.File]::ReadAllLines($config) }
    catch [System.UnauthorizedAccessException], [System.IO.IOException] { return $null }
    @($lines | Where-Object { $_ -match '^\s*url\s*=\s*https?://[^/@\s]+@' }).Count -gt 0
}

function Remove-UsaBannerOldRepo {
    <#
    .SYNOPSIS
    Deletes the copy of the old banner's repository its update job ran from.
    .DESCRIPTION
    In:  the host's root (Ubuntu; '' on Windows), the copy's path on the
         host, what the old banner's job did with it, and -Windows on a
         Windows host.
    Out: a line when it was deleted; a warning instead when the host
         refused, saying what is left. A folder without the repository's own
         files is left, with a warning: its path came from a unit or a task.
         Where a remote URL in it held sign-in details, a warning says to
         revoke the token: deleting the copy does not end it. On Windows, a
         .git/config no one may read is read once Administrators have taken
         the copy over; where it still cannot be read, a warning says so,
         and to revoke a token if the clone was made with one.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$What,
        [switch]$Windows
    )
    $full = "$Root$Path"
    if (-not [System.IO.Directory]::Exists($full)) { return }
    if (-not (Test-UsaBannerOldRepo -Path $full)) {
        Write-Warning "UsaBanner: $Path, which the old banner's job names, does not hold a copy of the old banner's repository, so it is left as it is."
        return
    }
    $files = @([System.IO.Directory]::GetFiles($full, '*', [System.IO.SearchOption]::AllDirectories))
    if (-not $PSCmdlet.ShouldProcess($Path, "Delete the folder and the $($files.Count) file(s) in it: the copy of the old banner's repository $What")) { return }
    $signIn = Test-UsaBannerRepoSignIn -Path $full
    if ($null -eq $signIn -and $Windows) {
        Grant-UsaBannerTreeAccess -Path $full
        $signIn = Test-UsaBannerRepoSignIn -Path $full
    }
    $refusal = Remove-UsaBannerTree -Path $full -Windows:$Windows
    if ($refusal) { Write-Warning "UsaBanner: could not delete ${Path}, the copy of the old banner's repository ${What}: $refusal" }
    else { "deleted $Path and the $($files.Count) file(s) in it: the copy of the old banner's repository $What" }
    if ($signIn) {
        Write-Warning "UsaBanner: a remote URL in $Path held sign-in details, as the README's private-fork steps put a deploy token there. Deleting the copy does not end the token: revoke it where it was issued."
    }
    elseif ($null -eq $signIn) {
        Write-Warning "UsaBanner: $([System.IO.Path]::Combine($Path, '.git', 'config')) could not be read (Install-ManatechBanner.ps1 -UpdateTask leaves the clone's files so), so whether a remote URL in it held a deploy token is not known. If it was cloned with a token, as the README's private-fork steps do, revoke it where it was issued."
    }
}

function Get-UsaBannerOldBannerCheck {
    # In:  what of the old banner is on the host (Find-UsaBannerLinuxOldInstall,
    #      Find-UsaBannerWindowsOldInstall)
    # Out: the old banner's check: none of it here; or what is, which a
    #      login shows beside this banner. A Group Policy that delivers the
    #      old banner puts it back after Deploy-UsaBanner -ReplaceOldBanner
    #      took it off (D23)
    param([AllowEmptyCollection()][string[]]$Found = @())
    if (-not $Found.Count) { return New-UsaBannerCheck -Check 'old banner' -State 'ok' -Detail 'none of it is on this host' }
    New-UsaBannerCheck -Check 'old banner' -State 'differs' -Detail "it is on this host beside this banner ($($Found -join ', ')), as a Group Policy that delivers it puts it back: take that GPO off this host, then run Deploy-UsaBanner -ReplaceOldBanner"
}
