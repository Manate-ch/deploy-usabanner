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
        #      Match with a blank line after; its SSH banner file; its two tasks
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
        $global:UsaWinTasks['Manatech banner update'] = @{ Execute = 'powershell.exe'; Arguments = '-File Update-ManatechBanner.ps1'; Schedule = 'daily' }
        $global:UsaWinTasks['Manatech MOTD sync'] = @{ Execute = 'powershell.exe'; Arguments = '-File Sync-ManatechBanner.ps1'; Schedule = 'gpo' }
    }

    function Add-AdminBanner {
        # In:  the host folder
        # Out: nothing; sshd_config has the admin's own Banner line above the first Match, as before any banner came
        param([string]$Root)
        $sshd = Join-Path $Root 'ProgramData/ssh/sshd_config'
        [System.IO.File]::WriteAllText($sshd, [System.IO.File]::ReadAllText($sshd).Replace("#Port 22`r`n", "#Port 22`r`nBanner __PROGRAMDATA__/ssh/contoso.txt`r`n"))
    }
}

AfterAll {
    Remove-Variable -Name UsaDeployCalls, UsaDeployAnswers, UsaDeployUnits, UsaDeployRoot -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name UsaWinRoot, UsaWinCalls, UsaWinAnswers, UsaWinNotice, UsaWinTasks, UsaWinAcl -Scope Global -ErrorAction SilentlyContinue
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
}
