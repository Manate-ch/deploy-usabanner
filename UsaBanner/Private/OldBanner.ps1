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
#   |                | it): stopped, their units deleted; what --retire       |
#   |                | turned off, back on as Ubuntu ships it: four stock     |
#   |                | MOTD scripts, landscape-sysinfo, motd-news.timer; its  |
#   |                | sshd drop-in (ssh reloads); its MOTD scripts, console  |
#   |                | file and folders                                       |
#   | Windows Server | its tasks; its block in both all-users profiles; its   |
#   |                | Banner line in sshd_config, with each Banner it turned |
#   |                | off back on, checked with sshd -t; its SSH banner file |
#   |                | and its folder                                         |
#   +----------------+--------------------------------------------------------+
#
# The old banner kept no record, so what it changed comes back as the OS ships
# it. The deploy that follows turns the same stock scripts off again, on its
# own record this time, so Remove-UsaBanner turns them back on. Left as they
# are: a git clone the old timer pulled into, the OpenSSH default shell (this
# banner needs a PowerShell there too, D21), and sshd_config.manatech-bak, the
# old installer's copy of sshd_config. A Group Policy that delivers the old
# banner delivers it again at the next boot or policy refresh, so its GPO comes
# off the host first (D23); Get-UsaBanner's "old banner" check says when the
# old banner is back.

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
# Where ADSys keeps its copy of the old banner, on a host Group Policy delivers it to.
$script:UsaOldAdsysCopy = '/var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh'

# Install-ManatechBanner.ps1's marks: its profile block, its Banner line, and
# the note it puts before a Banner it turns off.
$script:UsaOldProfileBegin = '# >>> Manatech banner (Install-ManatechBanner.ps1) >>>'
$script:UsaOldProfileEnd = '# <<< Manatech banner <<<'
$script:UsaOldSshdEntry = 'Banner __PROGRAMDATA__/ssh/manatech-banner.txt'
$script:UsaOldSshdNote = '^# replaced by Install-ManatechBanner\.ps1 on \d{4}-\d{2}-\d{2}: (.*)$'
# Its tasks, in the task scheduler's root folder: its own update task, and the
# one the "Manatech MOTD" GPO makes.
$script:UsaOldTasks = @('Manatech banner update', 'Manatech MOTD sync')
$script:UsaOldGpoTask = 'Manatech MOTD sync'

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
    In:  the host's root.
    Out: a line for each change, in the order made. Under -WhatIf,
         PowerShell says each change instead, and nothing changes.
    Its jobs stop first, so they install nothing more while it goes. Then
    what --retire turned off comes back on as Ubuntu ships it: the stock
    MOTD scripts; landscape-sysinfo, its statoverride removed (or, for a
    file no package owns, its execute bits set); motd-news.timer, unmasked
    and started where it is enabled. Then its sshd drop-in (ssh reloads),
    its MOTD scripts and console file (and /etc/issue.d, when that leaves it
    empty: install.sh made it), and its folders. Where the host keeps
    ADSys's copy of the old banner, a warning says that a Group Policy still
    running it puts it back at the next boot.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Root = '')
    foreach ($unit in $script:UsaOldJobs) {
        if ([System.IO.File]::Exists("$Root/etc/systemd/system/$unit") -and
            $PSCmdlet.ShouldProcess($unit, 'Stop and disable the old banner''s job (systemctl disable --now)')) {
            $disable = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'disable', '--now', $unit
            if ($disable.ExitCode -eq 0) { "stopped ${unit}: the old banner's job" }
            else { Write-Warning "UsaBanner: systemctl could not disable ${unit}: $($disable.Output -join ' ')" }
        }
    }
    $gone = @(foreach ($unit in $script:UsaOldUnits) { Remove-UsaBannerHostFile -Root $Root -Path "/etc/systemd/system/$unit" -What 'a unit of the old banner''s job' })
    $gone
    if ($gone.Count) {
        $reload = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'daemon-reload'
        if ($reload.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl daemon-reload failed: $($reload.Output -join ' ')" }
    }

    foreach ($name in $script:UsaOldRetired) {
        Enable-UsaBannerExecutable -Root $Root -Path "/etc/update-motd.d/$name" -What 'a stock MOTD script the old banner turned off'
    }
    $link = [System.IO.FileInfo]::new("$Root/etc/update-motd.d/50-landscape-sysinfo")
    if ($link.LinkTarget) {
        $target = $link.LinkTarget
        if (-not $target.StartsWith('/')) { $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine('/etc/update-motd.d', $target)) }
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
    $state = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-enabled', 'motd-news.timer').Output) + '')[0]
    if ($state -eq 'masked' -and $PSCmdlet.ShouldProcess('motd-news.timer', 'Unmask it, which the old banner masked, and start it where it is enabled (systemctl unmask)')) {
        $unmasked = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'unmask', 'motd-news.timer'
        if ($unmasked.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not unmask motd-news.timer: $($unmasked.Output -join ' ')" }
        else {
            if ([string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-enabled', 'motd-news.timer').Output) + '')[0] -eq 'enabled') {
                $started = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'start', 'motd-news.timer'
                if ($started.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not start motd-news.timer: $($started.Output -join ' ')" }
            }
            'unmasked motd-news.timer: the old banner masked it'
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
    if ([System.IO.File]::Exists("$Root$script:UsaOldAdsysCopy")) {
        Write-Warning "UsaBanner: this host keeps ADSys's copy of the old banner ($script:UsaOldAdsysCopy). A Group Policy that runs it puts the old banner back at the next boot: take that GPO off this host (D23). Get-UsaBanner's old banner check says when it is back."
    }
}

function Remove-UsaBannerOldSshdBannerLine {
    <#
    .SYNOPSIS
    sshd_config's lines without the old banner's Banner line.
    .DESCRIPTION
    Out: @{ Lines; Changed }: Install-ManatechBanner.ps1's Banner line taken
         out, with the blank line it always put after it, and each Banner it
         turned off ("# replaced by Install-ManatechBanner.ps1 on <date>: ")
         back as it was.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyCollection()][string[]]$Lines = @())
    $new = [System.Collections.Generic.List[string]]::new()
    $changed = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq $script:UsaOldSshdEntry) {
            $changed = $true
            if ($i + 1 -lt $Lines.Count -and $Lines[$i + 1] -eq '') { $i++ }
            continue
        }
        if ($Lines[$i] -match $script:UsaOldSshdNote) {
            $new.Add($Matches[1])
            $changed = $true
            continue
        }
        $new.Add($Lines[$i])
    }
    @{ Lines = $new.ToArray(); Changed = $changed }
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
    each Banner it turned off back on (sshd -t checks the file, and one it
    refuses is put back; sshd is not restarted); its SSH banner file and its
    folder. The task a Group Policy makes comes back at the next policy
    refresh while the GPO applies: a warning says so.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$Layout)
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
        if ($result.Changed -and $PSCmdlet.ShouldProcess($Layout.SshdConfig, 'Take out the old banner''s Banner line, and turn back on any Banner it turned off')) {
            $backup = "$($Layout.SshdConfig).usabanner-bak"
            [System.IO.File]::Copy($Layout.SshdConfig, $backup, $true)
            [System.IO.File]::WriteAllBytes($Layout.SshdConfig, (ConvertTo-UsaBannerWindowsBytes -Text ($result.Lines -join $eol) -Encoding $file.Encoding))
            $sshd = Get-UsaBannerWindowsSshd
            $test = if ($sshd) { Invoke-UsaBannerNative -FilePath $sshd -ArgumentList '-t' } else { @{ ExitCode = 0; Output = @() } }
            if ($test.ExitCode -ne 0) {
                [System.IO.File]::Copy($backup, $Layout.SshdConfig, $true)
                Write-Warning "UsaBanner: sshd -t refused sshd_config without the old banner's Banner line, so it is put back: $(@($test.Output) -join ' ')"
            }
            else {
                [System.IO.File]::Delete($backup)
                "took the old banner's Banner line out of $($Layout.SshdConfig)"
            }
        }
    }
    Remove-UsaBannerHostFile -Root '' -Path $Layout.OldSshText -What 'the old banner''s SSH banner'
    Remove-UsaBannerWindowsFolder -Path $Layout.OldData -Allowed $Layout.OldData -What 'the old banner: its module, data, settings and logs'
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
