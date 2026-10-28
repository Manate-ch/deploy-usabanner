# Deploy-UsaBanner -ReplaceOldBanner (UsaBanner/Private/OldBanner.ps1, docs/DECISIONS.md D23) on the fake hosts of
# FakeHosts.ps1. The old banner is laid onto a stock host as install.sh --all and Install-ManatechBanner.ps1 leave one,
# then taken off. The strongest check is the round trip: the old banner, a deploy that replaces it, Remove-UsaBanner,
# and the host is as it was before the old banner came.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'FakeHosts.ps1')

    function Add-OldUbuntuBanner {
        # In:  the host folder Use-LinuxHost works on
        # Out: nothing; the host has the old banner as install.sh --all leaves it where Group Policy delivers it: its
        #      files and folders, its sshd drop-in, its two jobs enabled, four stock scripts turned off,
        #      landscape-sysinfo's statoverride, and motd-news.timer masked
        param([string]$Root)
        Write-TestFile $Root 'etc/update-motd.d/05-manatech-banner' "#!/bin/sh`necho old banner`n" -Mode '755'
        Write-TestFile $Root 'etc/update-motd.d/15-manatech-health' "#!/bin/sh`necho old health`n" -Mode '755'
        Write-TestFile $Root 'etc/manatech/motd.conf' "ENV_NAME=LAB`n"
        Write-TestFile $Root 'etc/manatech/issue.net' "old ssh banner`n"
        Write-TestFile $Root 'usr/local/share/manatech/motd-lib.sh' "# old`n"
        Write-TestFile $Root 'var/lib/manatech/fqdn' "h-vsl-web1.ad.example`n"
        Write-TestFile $Root 'etc/issue.d/50-manatech.issue' "old console banner`n"
        Write-TestFile $Root 'etc/ssh/sshd_config.d/00-manatech-banner.conf' "Banner /etc/manatech/issue.net`n"
        foreach ($unit in 'manatech-motd-update.timer', 'manatech-motd-update.service', 'manatech-motd-publish.path', 'manatech-motd-publish.service') {
            Write-TestFile $Root "etc/systemd/system/$unit" "[Unit]`nDescription=$unit`n"
        }
        $global:UsaDeployUnits.Enabled += 'manatech-motd-update.timer', 'manatech-motd-publish.path'
        foreach ($name in '00-header', '10-help-text', '50-motd-news', '98-reboot-required') {
            [System.IO.File]::SetUnixFileMode((Join-Path $Root "etc/update-motd.d/$name"), [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead')
        }
        $wrapper = '/usr/share/landscape/landscape-sysinfo.wrapper'
        $global:UsaDeployUnits.Overrides += $wrapper
        [System.IO.File]::SetUnixFileMode((Join-Path $Root $wrapper), [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead')
        $global:UsaDeployUnits.Masked += 'motd-news.timer'
    }

    function New-AdsysPolicies {
        # In:  the startup script a GPO has ADSys run
        # Out: ADSys's cache of the policy it applies to the machine, with that GPO, in the form ADSys
        #      writes it (Ubuntu 24.04.5, 2026-10-23)
        param([string]$Script)
        @(
            'gpos:'
            "    - id: '{0F0E0D0C-0B0A-0908-0706-050403020100}'"
            '      name: Contoso startup'
            '      rules:'
            '        scripts:'
            '            - key: startup'
            '              value: |'
            "                $Script"
            '              disabled: false'
            '              strategy: append'
        ) -join "`n"
    }

    # Install-ManatechBanner.ps1's profile block, as it writes it.
    $script:OldBlock = @(
        '# >>> Manatech banner (Install-ManatechBanner.ps1) >>>'
        "if (Test-Path -LiteralPath 'C:\ProgramData\Manatech\ManatechBanner.psm1') {"
        "    Import-Module 'C:\ProgramData\Manatech\ManatechBanner.psm1'"
        '    Show-ManatechBanner -SshOnly'
        '}'
        '# <<< Manatech banner <<<'
    ) -join "`r`n"

    function Add-OldWindowsBanner {
        # In:  the host folder Use-WindowsHost works on
        # Out: nothing; the host has the old banner as Install-ManatechBanner.ps1 -SshBanner -UpdateTask and the
        #      Manatech MOTD GPO's task leave it, Windows PowerShell 5.1 having written the files: its folder; its
        #      block after Windows PowerShell's own profile, and alone in PowerShell 7's; sshd_config's copy, then
        #      every Banner above the first Match turned off behind its dated note, and its own line before the
        #      Match with a blank line after; its SSH banner file; its two tasks, with their definition files
        param([string]$Root)
        foreach ($name in 'ManatechBanner.psm1', 'motd.psd1', 'sync.log') {
            $null = New-Item -ItemType Directory -Path (Join-Path $Root 'ProgramData/Manatech') -Force
            [System.IO.File]::WriteAllText((Join-Path $Root "ProgramData/Manatech/$name"), "old $name`r`n")
        }
        [System.IO.File]::WriteAllText((Join-Path $Root 'ProgramData/ssh/manatech-banner.txt'), "old ssh banner`r`n")
        $bom = [System.Text.UTF8Encoding]::new($true)
        $own = Join-Path $Root 'Windows/System32/WindowsPowerShell/v1.0/profile.ps1'
        [System.IO.File]::WriteAllText($own, [System.IO.File]::ReadAllText($own).TrimEnd() + "`r`n`r`n" + $OldBlock + "`r`n", $bom)
        [System.IO.File]::WriteAllText((Join-Path $Root 'ProgramFiles/PowerShell/7/profile.ps1'), $OldBlock + "`r`n", $bom)
        $sshd = Join-Path $Root 'ProgramData/ssh/sshd_config'
        [System.IO.File]::Copy($sshd, "$sshd.manatech-bak")
        $lines = [System.Collections.Generic.List[string]]::new([string[]]([System.IO.File]::ReadAllText($sshd).TrimEnd("`r", "`n") -split "`r`n"))
        $first = $lines.FindIndex([Predicate[string]] { param($l) $l -match '^\s*Match\s' })
        $end = if ($first -lt 0) { $lines.Count } else { $first }
        for ($i = 0; $i -lt $end; $i++) { if ($lines[$i] -match '^\s*Banner\s') { $lines[$i] = '# replaced by Install-ManatechBanner.ps1 on 2026-10-01: ' + $lines[$i].Trim() } }
        $lines.Insert($end, 'Banner __PROGRAMDATA__/ssh/manatech-banner.txt')
        $lines.Insert($end + 1, '')
        [System.IO.File]::WriteAllText($sshd, ($lines -join "`r`n") + "`r`n")
        Add-WindowsOldTask -Name 'Manatech banner update' -Arguments '-File Update-ManatechBanner.ps1' -Schedule 'daily'
        Add-WindowsOldTask -Name 'Manatech MOTD sync' -Arguments '-File Sync-ManatechBanner.ps1' -Schedule 'gpo'
    }

    function Add-OldRepoCopy {
        # In:  a host folder, the copy's path in it, and its remote URL
        # Out: nothing; a copy of the old banner's repository is there as git clone leaves one: the repository's
        #      own files, and .git with its remote and an object written read-only, as git writes them (5 files)
        param([string]$Root, [string]$Path, [string]$Url = 'https://gitlab.example.com/contoso/deploy-usamotd.git')
        $full = Join-Path $Root $Path
        foreach ($file in 'install.sh', 'windows/Install-ManatechBanner.ps1', 'windows/Update-ManatechBanner.ps1') {
            $null = New-Item -ItemType Directory -Path (Split-Path (Join-Path $full $file)) -Force
            [System.IO.File]::WriteAllText((Join-Path $full $file), "# $file`n")
        }
        $null = New-Item -ItemType Directory -Path (Join-Path $full '.git/objects/pack') -Force
        [System.IO.File]::WriteAllText((Join-Path $full '.git/config'), "[remote `"origin`"]`n`turl = $Url`n`tfetch = +refs/heads/*:refs/remotes/origin/*`n")
        $pack = Join-Path $full '.git/objects/pack/pack-0.pack'
        [System.IO.File]::WriteAllText($pack, 'PACK')
        [System.IO.File]::SetAttributes($pack, [System.IO.FileAttributes]::ReadOnly)
    }

    function Add-AdminBanner {
        # In:  the host folder
        # Out: nothing; sshd_config has the admin's own Banner line above the first Match, as before any banner came
        param([string]$Root)
        $sshd = Join-Path $Root 'ProgramData/ssh/sshd_config'
        [System.IO.File]::WriteAllText($sshd, [System.IO.File]::ReadAllText($sshd).Replace("#Port 22`r`n", "#Port 22`r`nBanner __PROGRAMDATA__/ssh/contoso.txt`r`n"))
    }

    function Add-PrototypeLine {
        # In:  the host folder
        # Out: nothing; sshd_config has the prototype banner's Banner line above the first Match, as a Group
        #      Policy's copy of sshd_config carried it to servers (a production host, 2026-10-27)
        param([string]$Root)
        $sshd = Join-Path $Root 'ProgramData/ssh/sshd_config'
        [System.IO.File]::WriteAllText($sshd, [System.IO.File]::ReadAllText($sshd).Replace("#Port 22`r`n", "#Port 22`r`nBanner C:\ProgramData\ssh\banner.txt`r`n"))
    }
}

AfterAll {
    Remove-Variable -Name UsaDeployCalls, UsaDeployAnswers, UsaDeployUnits, UsaDeployRoot -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name UsaWinRoot, UsaWinCalls, UsaWinAnswers, UsaWinNotice, UsaWinShell, UsaWinTasks, UsaWinAcl, UsaWinOnCall, UsaWinStuck -Scope Global -ErrorAction SilentlyContinue
    Remove-Module UsaBanner -ErrorAction SilentlyContinue
}

Describe 'Deploy-UsaBanner -ReplaceOldBanner on Ubuntu' -Skip:$IsWindows {
    BeforeEach {
        Use-LinuxHost -Root (New-StockHost)
        $script:Root = $global:UsaDeployRoot
    }

    It 'is refused without the switch, and the refusal names it' {
        Add-OldUbuntuBanner $Root
        $before = Get-HostState $Root
        { Deploy-UsaBanner -Company Contoso } | Should -Throw '*Deploy-UsaBanner does not install beside it: Deploy-UsaBanner -ReplaceOldBanner takes that banner off first, then deploys this one*'
        Get-HostState $Root | Should -Be $before
    }

    It 'takes the old banner off first: its jobs, what it turned off back on, its drop-in, files and folders, in that order' {
        Add-OldUbuntuBanner $Root
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines[0..19] | Should -Be @(
            "stopped manatech-motd-update.timer: the old banner's job"
            "stopped manatech-motd-publish.path: the old banner's job"
            "deleted /etc/systemd/system/manatech-motd-update.timer: a unit of the old banner's job"
            "deleted /etc/systemd/system/manatech-motd-update.service: a unit of the old banner's job"
            "deleted /etc/systemd/system/manatech-motd-publish.path: a unit of the old banner's job"
            "deleted /etc/systemd/system/manatech-motd-publish.service: a unit of the old banner's job"
            'turned back on /etc/update-motd.d/00-header: a stock MOTD script the old banner turned off'
            'turned back on /etc/update-motd.d/10-help-text: a stock MOTD script the old banner turned off'
            'turned back on /etc/update-motd.d/50-motd-news: a stock MOTD script the old banner turned off'
            'turned back on /etc/update-motd.d/98-reboot-required: a stock MOTD script the old banner turned off'
            'removed the dpkg statoverride the old banner put on /usr/share/landscape/landscape-sysinfo.wrapper: /etc/update-motd.d/50-landscape-sysinfo runs again'
            'unmasked motd-news.timer: the old banner masked it'
            "deleted /etc/ssh/sshd_config.d/00-manatech-banner.conf: the old banner's sshd Banner line"
            'deleted /etc/update-motd.d/05-manatech-banner: the old banner after login'
            "deleted /etc/update-motd.d/15-manatech-health: the old banner's health lines"
            "deleted /etc/issue.d/50-manatech.issue: the old banner's console banner"
            'deleted the empty folder /etc/issue.d: install.sh made it, and no package ships it'
            "deleted /etc/manatech and the 2 file(s) in it: the old banner's settings and SSH banner"
            "deleted /usr/local/share/manatech and the 1 file(s) in it: the old banner's code and data"
            "deleted /var/lib/manatech and the 1 file(s) in it: the old banner's cached facts"
        )
        Get-Calls -Changes | Should -Contain 'systemctl try-reload-or-restart ssh'
        InModuleScope UsaBanner -Parameters @{ Root = $Root } { param($Root) @(Find-UsaBannerLinuxOldInstall -Root $Root) } | Should -BeNullOrEmpty
        Join-Path $Root 'etc/update-motd.d/05-usabanner' | Should -Exist
    }

    It 'stops a run of the old job in progress before it deletes the unit, and leaves no old unit failed (a production host, 2026-10-28)' {
        # The publish watcher had just started its service, a oneshot in its 30-second sleep: stopping the path unit
        # left the run going, the unit was deleted under it, and systemd failed it ('resources').
        Add-OldUbuntuBanner $Root
        $global:UsaDeployUnits.Running += 'manatech-motd-publish.service'
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $calls = @(Get-Calls)
        $calls | Should -Contain 'systemctl stop manatech-motd-publish.service'
        $calls.IndexOf('systemctl stop manatech-motd-publish.service') | Should -BeLessThan $calls.IndexOf('systemctl daemon-reload')
        $lines | Should -Contain "cleared the failed state of manatech-motd-publish.service: a unit of the old banner's job"
        $global:UsaDeployUnits.Failed | Should -BeNullOrEmpty
    }

    It 'clears the failed state of an old unit that failed before the move-off, and only says so under -WhatIf (a test host, 2026-10-27)' {
        Add-OldUbuntuBanner $Root
        $global:UsaDeployUnits.Failed += 'manatech-motd-update.service'
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WhatIf
        Get-Calls -Changes | Should -BeNullOrEmpty
        $global:UsaDeployUnits.Failed | Should -Be @('manatech-motd-update.service')
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines | Should -Contain "cleared the failed state of manatech-motd-update.service: a unit of the old banner's job"
        $global:UsaDeployUnits.Failed | Should -BeNullOrEmpty
    }

    It 'clears a failed old unit on a host an earlier deploy moved off, at its next deploy, and changes nothing else' {
        $null = Deploy-UsaBanner -Company Contoso
        $global:UsaDeployUnits.Failed += 'manatech-motd-publish.service'
        $before = Get-HostState $Root
        $global:UsaDeployCalls.Clear()
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines | Should -Be @("cleared the failed state of manatech-motd-publish.service: a unit of the old banner's job")
        Get-Calls -Changes | Should -Be @('systemctl reset-failed manatech-motd-publish.service')
        Get-HostState $Root | Should -Be $before
        $global:UsaDeployUnits.Failed | Should -BeNullOrEmpty
    }

    It 'leaves what the old banner turned off on the deploy''s own record, as it was before the old banner came' {
        Add-OldUbuntuBanner $Root
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner
        $record = Get-Record
        @($record.retired | ForEach-Object { '{0} {1}' -f $_.path, $_.mode }) | Should -Be @(
            '/etc/update-motd.d/00-header 755', '/etc/update-motd.d/10-help-text 755', '/etc/update-motd.d/50-motd-news 755'
            '/etc/update-motd.d/90-updates-available 755', '/etc/update-motd.d/98-reboot-required 755'
        )
        @($record.statoverride | ForEach-Object { '{0} {1}' -f $_.path, $_.mode }) | Should -Be @('/usr/share/landscape/landscape-sysinfo.wrapper 755')
        @($record.masked | ForEach-Object { '{0} {1}' -f $_.unit, $_.active }) | Should -Be @('motd-news.timer True')
    }

    It 'leaves the host as it was before the old banner came, after Remove-UsaBanner' {
        $before = Get-HostState $Root
        Add-OldUbuntuBanner $Root
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner
        $null = Remove-UsaBanner
        Get-HostState $Root | Should -Be $before
        $global:UsaDeployUnits.Masked | Should -BeNullOrEmpty
        $global:UsaDeployUnits.Overrides | Should -BeNullOrEmpty
        $global:UsaDeployUnits.Enabled | Should -BeNullOrEmpty
    }

    It 'changes nothing on a host this banner is on already, and runs only what reads the host' {
        # The lab (the Group Policy window, 2026-10-25): the Ubuntu runner passes -ReplaceOldBanner at every deploy
        # (D29), and the move off turned the stock scripts, landscape-sysinfo and motd-news back on at each one, for
        # the deploy to turn them off again a second later.
        $null = Deploy-UsaBanner -Company Contoso
        $before = Get-HostState $Root
        $global:UsaDeployCalls.Clear()
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines | Should -BeNullOrEmpty
        Get-HostState $Root | Should -Be $before
        Get-Calls -Changes | Should -BeNullOrEmpty
    }

    It 'leaves what this banner turned off as it is where the old banner came back over it, and Remove-UsaBanner leaves the host stock' {
        # As the old banner's GPO puts it back at the next boot (D23). Its install.sh finds the stock scripts off
        # already: dpkg-statoverride and systemctl mask add nothing a second time.
        $before = Get-HostState $Root
        $null = Deploy-UsaBanner -Company Contoso
        Add-OldUbuntuBanner $Root
        $units = $global:UsaDeployUnits
        $units.Overrides = @($units.Overrides | Select-Object -Unique)
        $units.Masked = @($units.Masked | Select-Object -Unique)
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines | Should -Contain 'deleted /etc/update-motd.d/05-manatech-banner: the old banner after login'
        @($lines | Where-Object { $_ -like 'turned back on *' -or $_ -like 'removed the dpkg statoverride *' -or $_ -like 'unmasked *' -or $_ -like 'turned off *' -or $_ -like 'masked *' }) | Should -BeNullOrEmpty
        $null = Remove-UsaBanner
        Get-HostState $Root | Should -Be $before
        $units.Masked | Should -BeNullOrEmpty
        $units.Overrides | Should -BeNullOrEmpty
    }

    It 'changes nothing under -WhatIf, and runs only what reads the host' {
        Add-OldUbuntuBanner $Root
        $before = Get-HostState $Root
        @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WhatIf) | Should -BeNullOrEmpty
        Get-HostState $Root | Should -Be $before
        Get-Calls -Changes | Should -BeNullOrEmpty
    }

    It 'leaves the old banner as it was when a banner fails to draw' {
        Add-OldUbuntuBanner $Root
        $before = Get-HostState $Root
        Mock -ModuleName UsaBanner New-UsaBannerLinuxDrawing { throw 'the art broke' }
        { Deploy-UsaBanner -Company Contoso -ReplaceOldBanner } | Should -Throw '*the art broke*'
        Get-HostState $Root | Should -Be $before
        Get-Calls -Changes | Should -BeNullOrEmpty
    }

    It 'turns landscape-sysinfo back on with chmod +x where no package owns its file' {
        Use-LinuxHost -Root $Root -Answers @{ 'dpkg -S /usr/share/landscape/landscape-sysinfo.wrapper' = @{ ExitCode = 1; Output = @('dpkg-query: no path found matching pattern') } }
        Add-OldUbuntuBanner $Root
        $global:UsaDeployUnits.Overrides = @()
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines | Should -Contain 'turned back on /usr/share/landscape/landscape-sysinfo.wrapper: the landscape-sysinfo MOTD script, which the old banner turned off'
        Get-Calls -Changes | Should -Not -Contain 'dpkg-statoverride --remove /usr/share/landscape/landscape-sysinfo.wrapper'
    }

    It 'keeps /etc/issue.d where it holds another file' {
        Add-OldUbuntuBanner $Root
        Write-TestFile $Root 'etc/issue.d/40-contoso.issue' "Contoso`n"
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines | Should -Not -Contain 'deleted the empty folder /etc/issue.d: install.sh made it, and no package ships it'
        Join-Path $Root 'etc/issue.d/40-contoso.issue' | Should -Exist
    }

    It 'warns where ADSys applies a Group Policy that runs the old banner, which puts it back at the next boot' {
        Add-OldUbuntuBanner $Root
        Write-TestFile $Root 'var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh' "#!/bin/sh`n"
        Write-TestFile $Root 'var/cache/adsys/policies/H-VSL-WEB1/policies' (New-AdsysPolicies 'MOTD/adsys-startup.sh')
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue
        "$warned" | Should -BeLike "*a Group Policy that ADSys applies here runs the old banner's startup script (MOTD/adsys-startup.sh), which puts the old banner back at the next boot: take that GPO off this host (D23)*"
    }

    It 'says nothing of ADSys where its copy of SYSVOL keeps the old banner but no GPO it applies runs it' {
        # The lab (2026-10-23): with the GPO's link off and ADSys refreshed, its copy of SYSVOL still held the old
        # banner's files, as other GPOs applied.
        Add-OldUbuntuBanner $Root
        Write-TestFile $Root 'var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh' "#!/bin/sh`n"
        Write-TestFile $Root 'var/cache/adsys/policies/H-VSL-WEB1/policies' (New-AdsysPolicies 'contoso/agent-startup.sh')
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue
        "$warned" | Should -Not -BeLike '*ADSys*'
    }

    It 'enables motd-news.timer again where its package enabled it and the first install.sh disabled it' {
        # The lab (2026-10-23): the first install.sh ran systemctl disable --now on it, and a later one masked it;
        # deb-systemd-helper's record says its package enabled it.
        Add-OldUbuntuBanner $Root
        $global:UsaDeployUnits.Disabled += 'motd-news.timer'
        Write-TestFile $Root 'var/lib/systemd/deb-systemd-helper-enabled/timers.target.wants/motd-news.timer' ''
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines | Should -Contain 'unmasked and enabled motd-news.timer: the old banner masked it, and its first install.sh disabled it'
        Get-Calls -Changes | Should -Contain 'systemctl enable --now motd-news.timer'
        $null = Remove-UsaBanner
        $global:UsaDeployUnits.Disabled | Should -BeNullOrEmpty
        $global:UsaDeployUnits.Masked | Should -BeNullOrEmpty
    }

    It 'leaves motd-news.timer disabled where no package''s record says it enabled it' {
        Add-OldUbuntuBanner $Root
        $global:UsaDeployUnits.Disabled += 'motd-news.timer'
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines | Should -Contain 'unmasked motd-news.timer: the old banner masked it'
        Get-Calls -Changes | Should -Not -Contain 'systemctl enable --now motd-news.timer'
    }

    It 'deletes the copy of its repository the old timer ran install.sh from, as the timer''s unit names it, last' {
        Add-OldUbuntuBanner $Root
        Write-TestFile $Root 'etc/systemd/system/manatech-motd-update.service' "[Service]`nType=oneshot`nExecStart=/bin/sh /opt/manatech-motd/install.sh --update`n"
        Add-OldRepoCopy $Root 'opt/manatech-motd'
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue)
        $deleted = "deleted /opt/manatech-motd and the 5 file(s) in it: the copy of the old banner's repository its timer ran install.sh from"
        $lines | Should -Contain $deleted
        [array]::IndexOf($lines, $deleted) | Should -BeGreaterThan ([array]::IndexOf($lines, "deleted /var/lib/manatech and the 1 file(s) in it: the old banner's cached facts"))
        Join-Path $Root 'opt/manatech-motd' | Should -Not -Exist
        "$warned" | Should -Not -BeLike '*sign-in*'
    }

    It 'warns to revoke the token where a remote URL in the copy held sign-in details, and never shows the URL' {
        Add-OldUbuntuBanner $Root
        Write-TestFile $Root 'etc/systemd/system/manatech-motd-update.service' "[Service]`nExecStart=/bin/sh /opt/manatech-motd/install.sh --update --ad`n"
        Add-OldRepoCopy $Root 'opt/manatech-motd' -Url 'https://deploy:not-a-real-token@gitlab.example.com/contoso/motd.git'
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue)
        Join-Path $Root 'opt/manatech-motd' | Should -Not -Exist
        "$warned" | Should -BeLike '*a remote URL in /opt/manatech-motd held sign-in details*revoke it where it was issued*'
        "$warned $lines" | Should -Not -BeLike '*not-a-real-token*'
    }

    It 'leaves a folder the unit names that holds no copy of the repository, and says so' {
        Add-OldUbuntuBanner $Root
        Write-TestFile $Root 'etc/systemd/system/manatech-motd-update.service' "[Service]`nExecStart=/bin/sh /srv/tools/install.sh`n"
        Write-TestFile $Root 'srv/tools/install.sh' "#!/bin/sh`n"
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue
        Join-Path $Root 'srv/tools/install.sh' | Should -Exist
        "$warned" | Should -BeLike "*/srv/tools, which the old banner's job names, does not hold a copy of the old banner's repository, so it is left as it is*"
    }

    It 'reads no copy where Group Policy delivers the old banner, whose unit runs adsys-startup.sh from ADSys''s copy' {
        Add-OldUbuntuBanner $Root
        Write-TestFile $Root 'etc/systemd/system/manatech-motd-update.service' "[Service]`nExecStart=/bin/sh /var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh`n"
        Add-OldRepoCopy $Root 'var/cache/adsys/sysvol/assets/scripts/MOTD'
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningAction SilentlyContinue)
        Join-Path $Root 'var/cache/adsys/sysvol/assets/scripts/MOTD/install.sh' | Should -Exist
        @($lines | Where-Object { $_ -like '*repository*' }) | Should -BeNullOrEmpty
    }

    It 'leaves the host as it was before the old banner came, its copy of the repository included, after Remove-UsaBanner' {
        $null = New-Item -ItemType Directory -Path (Join-Path $Root 'opt')
        $before = Get-HostState $Root
        Add-OldUbuntuBanner $Root
        Write-TestFile $Root 'etc/systemd/system/manatech-motd-update.service' "[Service]`nExecStart=/bin/sh /opt/manatech-motd/install.sh --update`n"
        Add-OldRepoCopy $Root 'opt/manatech-motd'
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner
        $null = Remove-UsaBanner
        Get-HostState $Root | Should -Be $before
    }

    It 'has Get-UsaBanner''s old banner check ok after it, and differs when the old banner is back' {
        Add-OldUbuntuBanner $Root
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner
        $check = @((Get-UsaBanner).Checks | Where-Object { $_.Check -eq 'old banner' })[0]
        '{0}: {1}' -f $check.State, $check.Detail | Should -BeExactly 'ok: none of it is on this host'
        Write-TestFile $Root 'etc/update-motd.d/05-manatech-banner' "#!/bin/sh`n" -Mode '755'
        $status = Get-UsaBanner
        $check = @($status.Checks | Where-Object { $_.Check -eq 'old banner' })[0]
        '{0}: {1}' -f $check.State, $check.Detail | Should -BeExactly 'differs: it is on this host beside this banner (/etc/update-motd.d/05-manatech-banner), as a Group Policy that delivers it puts it back: take that GPO off this host, then run Deploy-UsaBanner -ReplaceOldBanner'
        $status.Healthy | Should -BeFalse
    }
}

Describe 'Deploy-UsaBanner -ReplaceOldBanner on Windows Server' {
    BeforeEach {
        Use-WindowsHost (New-WindowsHost)
        $script:Root = $global:UsaWinRoot
    }

    It 'is refused without the switch, and the refusal names it' {
        Add-OldWindowsBanner $Root
        $before = Get-WindowsHostState $Root
        { Deploy-UsaBanner -Company Contoso } | Should -Throw '*Deploy-UsaBanner does not install beside it: Deploy-UsaBanner -ReplaceOldBanner takes that banner off first, then deploys this one*'
        Get-WindowsHostState $Root | Should -Be $before
    }

    It 'takes the old banner off first: its tasks, its profile blocks, its Banner line, its files, in that order' {
        Add-AdminBanner $Root
        Add-OldWindowsBanner $Root
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue)
        $lines[0..6] | Should -Be @(
            "unregistered the task \Manatech banner update: the old banner's"
            "unregistered the task \Manatech MOTD sync: the old banner's"
            "took the old banner's block out of $Root/Windows/System32/WindowsPowerShell/v1.0/profile.ps1"
            "took the old banner's block out of $Root/ProgramFiles/PowerShell/7/profile.ps1"
            "took the old banner's Banner line out of $Root/ProgramData/ssh/sshd_config"
            "deleted $Root/ProgramData/ssh/manatech-banner.txt: the old banner's SSH banner"
            "deleted $Root/ProgramData/Manatech and the 3 file(s) in it: the old banner: its module, data, settings and logs"
        )
        "$warned" | Should -BeLike '*the Manatech MOTD GPO makes the task \Manatech MOTD sync, and makes it again at the next policy refresh*take that GPO off this host (D23)*'
        @($global:UsaWinTasks.Keys) | Should -Be @('UsaBanner sample')
        $sshd = [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config'))
        $sshd | Should -Not -Match 'manatech'
        $sshd | Should -Match '(?m)^# Turned off by Deploy-UsaBanner, which put its own Banner above: Banner __PROGRAMDATA__/ssh/contoso\.txt\r$'
        InModuleScope UsaBanner { @(Find-UsaBannerWindowsOldInstall -Layout (Get-UsaBannerWindowsLayout)) } | Should -BeNullOrEmpty
    }

    It 'leaves the host as it was before the old banner came, after Remove-UsaBanner, but for the old installer''s copy of sshd_config' {
        Add-AdminBanner $Root
        $before = Get-WindowsHostState $Root
        Add-OldWindowsBanner $Root
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningAction SilentlyContinue
        $null = Remove-UsaBanner
        @(Get-WindowsHostState $Root | Where-Object { $_ -notlike 'ProgramData/ssh/sshd_config.manatech-bak *' }) | Should -Be $before
        Join-Path $Root 'ProgramData/ssh/sshd_config.manatech-bak' | Should -Exist
    }

    It 'deletes the git clone its update task pulled into, read-only objects too, before the folder the README puts it in' {
        Add-OldWindowsBanner $Root
        Add-OldRepoCopy $Root 'ProgramData/Manatech/repo'
        $global:UsaWinTasks['Manatech banner update'].Arguments = "-NoProfile -NonInteractive -File `"$Root/ProgramData/Manatech/repo/windows/Update-ManatechBanner.ps1`""
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue)
        $lines[5..7] | Should -Be @(
            "deleted $Root/ProgramData/ssh/manatech-banner.txt: the old banner's SSH banner"
            "deleted $Root/ProgramData/Manatech/repo and the 5 file(s) in it: the copy of the old banner's repository its update task pulled into"
            "deleted $Root/ProgramData/Manatech and the 3 file(s) in it: the old banner: its module, data, settings and logs"
        )
        Join-Path $Root 'ProgramData/Manatech' | Should -Not -Exist
        "$warned" | Should -Not -BeLike '*sign-in*'
    }

    It 'deletes a clone the task names outside the old folder, and warns to revoke a token its remote URL held' {
        Add-OldWindowsBanner $Root
        Add-OldRepoCopy $Root 'Tools/deploy-usamotd' -Url 'https://deploy:not-a-real-token@gitlab.example.com/contoso/motd.git'
        $global:UsaWinTasks['Manatech banner update'].Arguments = "-NoProfile -NonInteractive -File `"$Root/Tools/deploy-usamotd/windows/Update-ManatechBanner.ps1`""
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue)
        $lines | Should -Contain "deleted $Root/Tools/deploy-usamotd and the 5 file(s) in it: the copy of the old banner's repository its update task pulled into"
        Join-Path $Root 'Tools/deploy-usamotd' | Should -Not -Exist
        "$warned" | Should -BeLike "*a remote URL in $Root/Tools/deploy-usamotd held sign-in details*revoke it where it was issued*"
        "$warned $lines" | Should -Not -BeLike '*not-a-real-token*'
    }

    It 'says whether a token was in the clone could not be told where its .git/config cannot be read, and deletes it still' {
        # The lab (Server 2022, 2026-10-23): -UpdateTask's icacls /T leaves the clone's files with no access for
        # anyone, so a sign-in in .git/config cannot be seen.
        Add-OldWindowsBanner $Root
        Add-OldRepoCopy $Root 'ProgramData/Manatech/repo' -Url 'https://deploy:not-a-real-token@gitlab.example.com/contoso/motd.git'
        [System.IO.File]::SetUnixFileMode((Join-Path $Root 'ProgramData/Manatech/repo/.git/config'), [System.IO.UnixFileMode]::None)
        $global:UsaWinTasks['Manatech banner update'].Arguments = "-File `"$Root/ProgramData/Manatech/repo/windows/Update-ManatechBanner.ps1`""
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue
        Join-Path $Root 'ProgramData/Manatech/repo' | Should -Not -Exist
        "$warned" | Should -BeLike "*$Root/ProgramData/Manatech/repo/.git/config could not be read*whether a remote URL in it held a deploy token is not known*revoke it where it was issued*"
    }

    It 'leaves the host as it was before the old banner came, its clone included, after Remove-UsaBanner, but for the old installer''s copy of sshd_config' {
        $before = Get-WindowsHostState $Root
        Add-OldWindowsBanner $Root
        Add-OldRepoCopy $Root 'ProgramData/Manatech/repo'
        $global:UsaWinTasks['Manatech banner update'].Arguments = "-File `"$Root/ProgramData/Manatech/repo/windows/Update-ManatechBanner.ps1`""
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningAction SilentlyContinue
        $null = Remove-UsaBanner
        @(Get-WindowsHostState $Root | Where-Object { $_ -notlike 'ProgramData/ssh/sshd_config.manatech-bak *' }) | Should -Be $before
    }

    It 'changes nothing under -WhatIf' {
        Add-OldWindowsBanner $Root
        $before = Get-WindowsHostState $Root
        @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WhatIf) | Should -BeNullOrEmpty
        Get-WindowsHostState $Root | Should -Be $before
        $global:UsaWinCalls | Should -BeNullOrEmpty
    }

    It 'leaves the old banner as it was when a banner fails to draw' {
        Add-OldWindowsBanner $Root
        $before = Get-WindowsHostState $Root
        Mock -ModuleName UsaBanner Get-UsaBannerPreLogon { throw 'the art broke' }
        { Deploy-UsaBanner -Company Contoso -ReplaceOldBanner } | Should -Throw '*the art broke*'
        Get-WindowsHostState $Root | Should -Be $before
        $global:UsaWinCalls | Should -BeNullOrEmpty
    }

    It 'takes the prototype banner''s Banner line out before it puts its own in, so it turns nothing off behind a note' {
        Add-PrototypeLine $Root
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner)
        $lines | Should -Contain "took the prototype banner's Banner line out of $Root/ProgramData/ssh/sshd_config: Banner C:\ProgramData\ssh\banner.txt"
        $sshd = [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config'))
        $sshd | Should -Not -Match ([regex]::Escape('C:\ProgramData\ssh\banner.txt'))
        $sshd | Should -Not -Match 'Turned off by Deploy-UsaBanner'
        $sshd | Should -Match '(?m)^Banner __PROGRAMDATA__/UsagiTools/Banner/sshd-banner\.txt\r$'
        Join-Path $Root 'ProgramData/ssh/sshd_config.usabanner-bak' | Should -Not -Exist
    }

    It 'takes out the note a deploy before 0.2.2 turned the prototype banner''s line off behind, so Remove-UsaBanner turns nothing back on' {
        Add-PrototypeLine $Root
        $config = Join-Path $Root 'ProgramData/ssh/sshd_config'
        $null = Deploy-UsaBanner -Company Contoso
        [System.IO.File]::ReadAllText($config) | Should -Match ([regex]::Escape('# Turned off by Deploy-UsaBanner, which put its own Banner above: Banner C:\ProgramData\ssh\banner.txt'))
        @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner) | Should -Be @("took the prototype banner's Banner line out of $config`: Banner C:\ProgramData\ssh\banner.txt")
        [System.IO.File]::ReadAllText($config) | Should -Not -Match ([regex]::Escape('C:\ProgramData\ssh\banner.txt'))
        $null = Remove-UsaBanner
        @([System.IO.File]::ReadAllLines($config) | Where-Object { $_ -match '^\s*Banner\s' }) | Should -BeNullOrEmpty
    }

    It 'takes both out in one write where the old banner turned the prototype banner''s line off behind its note' {
        Add-PrototypeLine $Root
        Add-OldWindowsBanner $Root
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningAction SilentlyContinue)
        $lines | Should -Contain "took the old banner's Banner line out of $Root/ProgramData/ssh/sshd_config"
        $lines | Should -Contain "took the prototype banner's Banner line out of $Root/ProgramData/ssh/sshd_config: Banner C:\ProgramData\ssh\banner.txt"
        @($global:UsaWinCalls | Where-Object { $_ -eq 'C:\Windows\System32\OpenSSH\sshd.exe -t' }).Count | Should -Be 2 -Because 'one sshd -t for the move off, one for the deploy''s own line'
        $sshd = [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config'))
        $sshd | Should -Not -Match ([regex]::Escape('C:\ProgramData\ssh\banner.txt'))
        $sshd | Should -Not -Match 'manatech|Turned off by Deploy-UsaBanner'
    }

    It 'says under -WhatIf that it would take the prototype banner''s Banner line out' {
        Add-PrototypeLine $Root
        $transcript = Join-Path $TestDrive "whatif-$([guid]::NewGuid().ToString('n')).txt"
        $null = Start-Transcript -LiteralPath $transcript
        try { $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WhatIf }
        finally { $null = Stop-Transcript }
        @(Get-Content -LiteralPath $transcript | Where-Object { $_ -like 'What if: *' }) | Should -Contain "What if: Performing the operation `"Take out the prototype banner's Banner line: Banner C:\ProgramData\ssh\banner.txt`" on target `"$Root/ProgramData/ssh/sshd_config`"."
    }

    It 'puts sshd_config back when sshd -t refuses it without the prototype banner''s line, and says so' {
        Use-WindowsHost $Root @{ 'C:\Windows\System32\OpenSSH\sshd.exe -t' = @{ ExitCode = 1; Output = @('Bad configuration option') } }
        Add-PrototypeLine $Root
        $kept = [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config'))
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue
        [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config')) | Should -BeExactly $kept
        "$warned" | Should -BeLike "*sshd -t refused sshd_config without the prototype banner's Banner line, so it is put back*"
    }

    It 'puts sshd_config back when sshd -t refuses it without the old banner''s line, and says so' {
        Use-WindowsHost $Root @{ 'C:\Windows\System32\OpenSSH\sshd.exe -t' = @{ ExitCode = 1; Output = @('Bad configuration option') } }
        Add-OldWindowsBanner $Root
        $kept = [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config'))
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue
        [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config')) | Should -BeExactly $kept
        "$warned" | Should -BeLike "*sshd -t refused sshd_config without the old banner's Banner line, so it is put back*"
    }

    It 'has Get-UsaBanner''s old banner check ok after it, and differs when the old banner is back' {
        Add-OldWindowsBanner $Root
        $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningAction SilentlyContinue
        $check = @((Get-UsaBanner).Checks | Where-Object { $_.Check -eq 'old banner' })[0]
        '{0}: {1}' -f $check.State, $check.Detail | Should -BeExactly 'ok: none of it is on this host'
        $null = New-Item -ItemType Directory -Path (Join-Path $Root 'ProgramData/Manatech')
        $status = Get-UsaBanner
        $check = @($status.Checks | Where-Object { $_.Check -eq 'old banner' })[0]
        $check.State | Should -BeExactly 'differs'
        $check.Detail | Should -BeLike "it is on this host beside this banner (*ProgramData/Manatech), as a Group Policy that delivers it puts it back*"
        $status.Healthy | Should -BeFalse
    }

    It 'refuses a deploy without the switch where only the old banner''s task is left, names it, and takes it off with the switch' {
        # A production host, 2026-10-27: the task the old banner's GPO made put it back at its midnight run, half an
        # hour after Get-UsaBanner had found none of it; and the task stays when the GPO stops applying.
        Add-WindowsOldTask -Name 'Manatech MOTD sync' -Arguments '-File Sync-ManatechBanner.ps1' -Schedule 'gpo'
        { Deploy-UsaBanner -Company Contoso } | Should -Throw "*Install-ManatechBanner.ps1 (the task \Manatech MOTD sync)*"
        $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningAction SilentlyContinue)
        $lines[0] | Should -BeExactly "unregistered the task \Manatech MOTD sync: the old banner's"
        Join-Path $Root 'Windows/System32/Tasks/Manatech MOTD sync' | Should -Not -Exist
        InModuleScope UsaBanner { @(Find-UsaBannerWindowsOldInstall -Layout (Get-UsaBannerWindowsLayout)) } | Should -BeNullOrEmpty
    }

    Context 'where Windows refuses the delete at first (a host the old banner was on for long, 2026-10-26)' {
        # There an administrator could neither clear the old clone's read-only pack files nor delete them: they
        # had no access for anyone. Linux stands in for that with a folder no one may write in, so nothing in it
        # can be deleted; the stand-in icacls gives it back at its grant on a folder above it, as Administrators'
        # ownership and full control do on Windows, where a test says so.
        BeforeEach {
            $global:UsaWinStuck = Join-Path $Root 'ProgramData/Manatech/repo/.git/objects/pack'
            $script:Shut = [System.IO.UnixFileMode]'UserRead, UserExecute'
            $script:Repair = {
                param($File, $Arguments)
                if ($File -eq 'icacls.exe' -and $Arguments -contains '/grant:r' -and $global:UsaWinStuck.StartsWith([string]$Arguments[0]) -and [System.IO.Directory]::Exists($global:UsaWinStuck)) {
                    [System.IO.File]::SetUnixFileMode($global:UsaWinStuck, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute')
                }
            }
        }
        AfterEach {
            if ([System.IO.Directory]::Exists($global:UsaWinStuck)) { [System.IO.File]::SetUnixFileMode($global:UsaWinStuck, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute') }
        }

        It 'deletes the old banner''s folder once Administrators have taken it over, and says deleted only then' {
            # The second run there: the old update task was gone, so its clone went with the folder it is in.
            Add-OldWindowsBanner $Root
            Add-OldRepoCopy $Root 'ProgramData/Manatech/repo'
            [System.IO.File]::SetUnixFileMode($global:UsaWinStuck, $Shut)
            $global:UsaWinOnCall = $Repair
            $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue)
            $lines | Should -Contain "deleted $Root/ProgramData/Manatech and the 8 file(s) in it: the old banner: its module, data, settings and logs"
            Join-Path $Root 'ProgramData/Manatech' | Should -Not -Exist
            @($global:UsaWinCalls | Where-Object { $_ -like "* $Root/ProgramData/Manatech*" }) | Should -Be @(
                "takeown.exe /F $Root/ProgramData/Manatech /R /A /D Y"
                "icacls.exe $Root/ProgramData/Manatech /grant:r *S-1-5-32-544:F /T /C /Q"
            )
            "$warned" | Should -Not -BeLike '*could not delete*'
        }

        It 'deletes the clone its update task names once Administrators have taken it over, then the old folder' {
            # The first run there: the task named the clone.
            Add-OldWindowsBanner $Root
            Add-OldRepoCopy $Root 'ProgramData/Manatech/repo'
            $global:UsaWinTasks['Manatech banner update'].Arguments = "-File `"$Root/ProgramData/Manatech/repo/windows/Update-ManatechBanner.ps1`""
            [System.IO.File]::SetUnixFileMode($global:UsaWinStuck, $Shut)
            $global:UsaWinOnCall = $Repair
            $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue)
            $lines | Should -Contain "deleted $Root/ProgramData/Manatech/repo and the 5 file(s) in it: the copy of the old banner's repository its update task pulled into"
            $lines | Should -Contain "deleted $Root/ProgramData/Manatech and the 3 file(s) in it: the old banner: its module, data, settings and logs"
            @($global:UsaWinCalls | Where-Object { $_ -like "* $Root/ProgramData/Manatech*" }) | Should -Be @(
                "takeown.exe /F $Root/ProgramData/Manatech/repo /R /A /D Y"
                "icacls.exe $Root/ProgramData/Manatech/repo /grant:r *S-1-5-32-544:F /T /C /Q"
            )
            "$warned" | Should -Not -BeLike '*could not delete*'
        }

        It 'says it could not delete the old folder, and what is left, never that it did, when Windows refuses after the takeover too' {
            Add-OldWindowsBanner $Root
            Add-OldRepoCopy $Root 'ProgramData/Manatech/repo'
            [System.IO.File]::SetUnixFileMode($global:UsaWinStuck, $Shut)
            $lines = @(Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue)
            @($lines | Where-Object { $_ -like 'deleted *ProgramData/Manatech*' }) | Should -BeNullOrEmpty
            "$warned" | Should -BeLike "*could not delete $Root/ProgramData/Manatech, the old banner: its module, data, settings and logs: * file(s) are left in it. Access to the path*denied*"
            Join-Path $global:UsaWinStuck 'pack-0.pack' | Should -Exist
            # The deploy goes on, and Get-UsaBanner's old banner check shows what is left.
            "$lines" | Should -BeLike '*registered the task*UsaBanner sample*'
            InModuleScope UsaBanner { @(Find-UsaBannerWindowsOldInstall -Layout (Get-UsaBannerWindowsLayout)) } | Should -Contain "$Root/ProgramData/Manatech"
        }

        It 'reads the clone''s .git/config once Administrators have taken the clone over, and says whether it held a token' {
            Add-OldWindowsBanner $Root
            Add-OldRepoCopy $Root 'ProgramData/Manatech/repo' -Url 'https://deploy:not-a-real-token@gitlab.example.com/contoso/motd.git'
            [System.IO.File]::SetUnixFileMode((Join-Path $Root 'ProgramData/Manatech/repo/.git/config'), [System.IO.UnixFileMode]::None)
            $global:UsaWinTasks['Manatech banner update'].Arguments = "-File `"$Root/ProgramData/Manatech/repo/windows/Update-ManatechBanner.ps1`""
            $global:UsaWinOnCall = {
                param($File, $Arguments)
                $config = Join-Path $global:UsaWinRoot 'ProgramData/Manatech/repo/.git/config'
                if ($File -eq 'icacls.exe' -and $Arguments -contains '/grant:r' -and [System.IO.File]::Exists($config)) { [System.IO.File]::SetUnixFileMode($config, [System.IO.UnixFileMode]'UserRead, UserWrite') }
            }
            $null = Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WarningVariable warned -WarningAction SilentlyContinue
            "$warned" | Should -BeLike "*a remote URL in $Root/ProgramData/Manatech/repo held sign-in details*revoke it where it was issued*"
            "$warned" | Should -Not -BeLike '*could not be read*'
            "$warned" | Should -Not -BeLike '*not-a-real-token*'
            Join-Path $Root 'ProgramData/Manatech/repo' | Should -Not -Exist
        }
    }
}

Describe 'a delete the host refuses' -Skip:$IsWindows {
    # Linux stands in for the refusal with a folder no one may write in: nothing in it can be deleted.
    BeforeEach {
        $script:Box = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Shut = Join-Path $Box 'var/lib/usabanner/shut'
        $null = New-Item -ItemType Directory -Path $Shut -Force
        [System.IO.File]::WriteAllText((Join-Path $Shut 'kept'), "kept`n")
        [System.IO.File]::SetUnixFileMode($Shut, [System.IO.UnixFileMode]'UserRead, UserExecute')
        $global:UsaTreeCalls = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName UsaBanner Invoke-UsaBannerNative { $global:UsaTreeCalls.Add((@($FilePath) + @($ArgumentList)) -join ' '); @{ ExitCode = 0; Output = @() } }
    }
    AfterEach {
        if ([System.IO.Directory]::Exists($Shut)) { [System.IO.File]::SetUnixFileMode($Shut, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute') }
        Remove-Variable -Name UsaTreeCalls -Scope Global -ErrorAction SilentlyContinue
    }

    It 'has Remove-UsaBannerHostFile warn that it could not delete a file, and not say it did' {
        $result = InModuleScope UsaBanner -Parameters @{ Root = $Box } {
            param($Root)
            $lines = @(Remove-UsaBannerHostFile -Root $Root -Path '/var/lib/usabanner/shut/kept' -What 'a test file' -WarningVariable warned -WarningAction SilentlyContinue)
            @{ Lines = $lines; Warned = "$warned" }
        }
        $result.Lines | Should -BeNullOrEmpty
        $result.Warned | Should -BeLike '*could not delete /var/lib/usabanner/shut/kept, a test file: Access to the path*denied*'
        Join-Path $Shut 'kept' | Should -Exist
    }

    It 'has Remove-UsaBannerHostFolder warn that it could not delete a folder, with what is left, and not say it did' {
        $result = InModuleScope UsaBanner -Parameters @{ Root = $Box } {
            param($Root)
            $lines = @(Remove-UsaBannerHostFolder -Root $Root -Path '/var/lib/usabanner' -What 'the banner''s state' -WarningVariable warned -WarningAction SilentlyContinue)
            @{ Lines = $lines; Warned = "$warned" }
        }
        $result.Lines | Should -BeNullOrEmpty
        $result.Warned | Should -BeLike '*could not delete /var/lib/usabanner, the banner''s state: 1 file(s) are left in it. Access to the path*denied*'
        $global:UsaTreeCalls | Should -BeNullOrEmpty
    }

    It 'has Remove-UsaBannerTree, on Windows, have Administrators take the folder over before it tries again: takeown, then icacls' {
        $refusal = InModuleScope UsaBanner -Parameters @{ Path = (Join-Path $Box 'var') } { param($Path) Remove-UsaBannerTree -Path $Path -Windows }
        $refusal | Should -BeLike '1 file(s) are left in it. Access to the path*denied*'
        $global:UsaTreeCalls | Should -Be @(
            "takeown.exe /F $Box/var /R /A /D Y"
            "icacls.exe $Box/var /grant:r *S-1-5-32-544:F /T /C /Q"
        )
    }

    It 'has Remove-UsaBannerTree delete a folder with a read-only file in it, taking nothing over' {
        [System.IO.File]::SetUnixFileMode($Shut, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute')
        [System.IO.File]::SetAttributes((Join-Path $Shut 'kept'), [System.IO.FileAttributes]::ReadOnly)
        $refusal = InModuleScope UsaBanner -Parameters @{ Path = (Join-Path $Box 'var') } { param($Path) Remove-UsaBannerTree -Path $Path -Windows }
        $refusal | Should -BeExactly ''
        Join-Path $Box 'var' | Should -Not -Exist
        $global:UsaTreeCalls | Should -BeNullOrEmpty
    }
}

Describe 'the old banner''s tasks, found without the task scheduler''s module' {
    # The ScheduledTasks module is logged whole at each import (DECISIONS D30): the old banner's tasks are found by
    # their definition files, and nothing the periodic job runs every 15 minutes may reach that module. Read from
    # the module's own functions, following each call into the module, at any depth.
    BeforeAll {
        $script:Bodies = & (Get-Module UsaBanner) {
            $found = @{}
            foreach ($function in @(Get-ChildItem -Path function: | Where-Object { $_.ModuleName -eq 'UsaBanner' })) { $found[$function.Name] = $function.ScriptBlock.Ast }
            $found
        }

        function Get-ReachedCommand {
            # In:  a function of the module
            # Out: the name of every command it calls, and those the module's functions it calls call, at any depth
            param([string]$Name)
            $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $todo = [System.Collections.Generic.Queue[string]]::new()
            $todo.Enqueue($Name)
            while ($todo.Count) {
                $next = $todo.Dequeue()
                if (-not $script:Bodies.ContainsKey($next)) { continue }
                foreach ($call in $script:Bodies[$next].FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                    $called = $call.GetCommandName()
                    if ($called -and $seen.Add($called)) { $todo.Enqueue($called) }
                }
            }
            @($seen)
        }

        function Test-TaskCommand {
            # In:  a command's name
            # Out: $true for the module's task commands and those of the task scheduler's module
            param([string]$Name)
            $Name -like '*-UsaBannerTask' -or $Name -like '*-ScheduledTask*'
        }
    }

    It 'has Find-UsaBannerWindowsOldInstall call no task command' {
        $reached = Get-ReachedCommand 'Find-UsaBannerWindowsOldInstall'
        $reached | Should -Contain 'Read-UsaBannerWindowsText' -Because 'the walk reads the function (else it proves nothing)'
        @($reached | Where-Object { Test-TaskCommand $_ }) | Should -BeNullOrEmpty
    }

    It 'leaves the periodic job on Windows no path to a task command' {
        $reached = Get-ReachedCommand 'Update-UsaBannerSample'
        $reached | Should -Contain 'Get-UsaBannerWindowsFacts' -Because 'the walk follows the job into the module (else it proves nothing)'
        @($reached | Where-Object { Test-TaskCommand $_ }) | Should -BeNullOrEmpty
    }

    It 'sees a task command where one is called (positive control)' {
        @(Get-ReachedCommand 'Remove-UsaBannerWindowsOldInstall' | Where-Object { Test-TaskCommand $_ }) | Should -Contain 'Unregister-UsaBannerTask'
    }
}

Describe 'Remove-UsaBannerOldSshdBannerLine' {
    It 'takes out <Case>' -ForEach @(
        @{ Case = 'the line before the first Match, with its blank line, and turns the Banner it turned off back on'
            Before = @('#Port 22', 'Banner __PROGRAMDATA__/ssh/contoso.txt', '', 'Match Group administrators', '  AuthorizedKeysFile x', '')
            Old = @('#Port 22', '# replaced by Install-ManatechBanner.ps1 on 2026-10-01: Banner __PROGRAMDATA__/ssh/contoso.txt', '', 'Banner __PROGRAMDATA__/ssh/manatech-banner.txt', '', 'Match Group administrators', '  AuthorizedKeysFile x', '') }
        @{ Case = 'the line at the end, with no Match block, and the blank line after it'
            Before = @('#Port 22', 'Subsystem sftp sftp-server.exe', '')
            Old = @('#Port 22', 'Subsystem sftp sftp-server.exe', 'Banner __PROGRAMDATA__/ssh/manatech-banner.txt', '', '') }
        @{ Case = 'two Banners it turned off on different days, each back'
            Before = @('Banner a.txt', 'Banner b.txt', '')
            Old = @('# replaced by Install-ManatechBanner.ps1 on 2026-09-01: Banner a.txt', '# replaced by Install-ManatechBanner.ps1 on 2026-10-01: Banner b.txt', 'Banner __PROGRAMDATA__/ssh/manatech-banner.txt', '', '') }
    ) {
        $result = InModuleScope UsaBanner -Parameters @{ Lines = $Old } { param($Lines) Remove-UsaBannerOldSshdBannerLine -Lines $Lines }
        $result.Lines | Should -Be $Before
        $result.Changed | Should -BeTrue
    }

    It 'leaves a file without the old banner''s line as it is, a Banner inside a Match block included' {
        $lines = @('#Port 22', 'Match Group administrators', '  Banner __PROGRAMDATA__/ssh/admins.txt', '')
        $result = InModuleScope UsaBanner -Parameters @{ Lines = $lines } { param($Lines) Remove-UsaBannerOldSshdBannerLine -Lines $Lines }
        $result.Lines | Should -Be $lines
        $result.Changed | Should -BeFalse
    }

    It 'takes out the prototype banner''s line <Case>' -ForEach @(
        @{ Case = 'where it is on'; FromOld = $false
            Lines = @('#Port 22', 'Banner C:\ProgramData\ssh\banner.txt', 'Subsystem sftp sftp-server.exe', '') }
        @{ Case = 'behind the note a deploy before 0.2.2 turned it off behind'; FromOld = $false
            Lines = @('#Port 22', '# Turned off by Deploy-UsaBanner, which put its own Banner above: Banner C:\ProgramData\ssh\banner.txt', 'Subsystem sftp sftp-server.exe', '') }
        @{ Case = 'behind the old banner''s note, which it does not turn back on'; FromOld = $true
            Lines = @('#Port 22', '# replaced by Install-ManatechBanner.ps1 on 2026-09-02: Banner C:\ProgramData\ssh\banner.txt', 'Subsystem sftp sftp-server.exe', 'Banner __PROGRAMDATA__/ssh/manatech-banner.txt', '', '') }
        @{ Case = 'trimmed, in any case'; FromOld = $false
            Lines = @('#Port 22', '  banner c:\programdata\ssh\BANNER.TXT  ', 'Subsystem sftp sftp-server.exe', '') }
    ) {
        $result = InModuleScope UsaBanner -Parameters @{ Lines = $Lines } { param($Lines) Remove-UsaBannerOldSshdBannerLine -Lines $Lines }
        $result.Lines | Should -Be @('#Port 22', 'Subsystem sftp sftp-server.exe', '')
        $result.Prototype | Should -BeTrue
        $result.Old | Should -Be $FromOld
        $result.Changed | Should -BeTrue
    }

    It 'leaves a Banner naming another path, or the same one written another way: <Case>' -ForEach @(
        @{ Case = 'another file'; Line = 'Banner C:\ProgramData\ssh\other.txt' }
        @{ Case = 'forward slashes'; Line = 'Banner C:/ProgramData/ssh/banner.txt' }
        @{ Case = 'ProgramData by the name sshd gives it'; Line = 'Banner __PROGRAMDATA__/ssh/banner.txt' }
    ) {
        $lines = @('#Port 22', $Line, '')
        $result = InModuleScope UsaBanner -Parameters @{ Lines = $lines } { param($Lines) Remove-UsaBannerOldSshdBannerLine -Lines $Lines }
        $result.Lines | Should -Be $lines
        $result.Changed | Should -BeFalse
    }
}
