# Get-UsaBanner (UsaBanner/Private/Status.ps1) on the fake hosts of FakeHosts.ps1: a deploy, then
# each part broken in turn, for each check to name what broke. Get-UsaBanner only reads: every
# answer here is taken through Get-ReadOnlyStatus, which also checks that the host is as it was
# and that no program that changes it ran.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $moduleRoot = Join-Path $repoRoot 'UsaBanner'
    Import-Module (Join-Path $moduleRoot 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'FakeHosts.ps1')
    . (Join-Path $PSScriptRoot 'Golden.ps1')
    $script:Version =(Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'UsaBanner.psd1')).ModuleVersion
    $script:Vlans = Join-Path $TestDrive 'vlans.csv'
    Set-Content -LiteralPath $Vlans -Value @('name,tag,cidr,color,short', 'Servers,40,10.20.40.0/24,Teal,SRV', 'User Devices,10,10.20.10.0/24,Blue,USR')

    function Get-Check {
        # In:  Get-UsaBanner's answer, and a check's name
        # Out: that check
        param($Status, [string]$Name)
        @($Status.Checks | Where-Object { $_.Check -eq $Name })[0]
    }

    function Get-ReadOnlyStatus {
        # Out: Get-UsaBanner's answer, once the host is shown to be as it was, and no program
        #      that changes it to have run
        if ($global:UsaWinRoot -and (Test-Path -LiteralPath $global:UsaWinRoot)) {
            $before = Get-WindowsHostState $global:UsaWinRoot
            $global:UsaWinCalls.Clear()
            $status = Get-UsaBanner
            Get-WindowsHostState $global:UsaWinRoot | Should -Be $before
            @($global:UsaWinCalls) | Should -BeNullOrEmpty
            return $status
        }
        $before = Get-HostState $global:UsaDeployRoot
        $global:UsaDeployCalls.Clear()
        $status = Get-UsaBanner
        Get-HostState $global:UsaDeployRoot | Should -Be $before
        Get-Calls -Changes | Should -BeNullOrEmpty
        $status
    }

    function Get-Problem {
        # In:  Get-UsaBanner's answer
        # Out: a line for each check that is not ok, for a failure to show
        param($Status)
        @($Status.Checks | Where-Object { $_.State -ne 'ok' } | ForEach-Object { "$($_.Check): $($_.State): $($_.Detail)" })
    }
}

AfterAll {
    Remove-Variable -Name UsaDeployCalls, UsaDeployAnswers, UsaDeployUnits, UsaDeployRoot -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name UsaWinRoot, UsaWinCalls, UsaWinAnswers, UsaWinNotice, UsaWinTasks, UsaWinAcl -Scope Global -ErrorAction SilentlyContinue
    Remove-Module UsaBanner -ErrorAction SilentlyContinue
}

Describe 'Get-UsaBanner on Ubuntu' -Skip:$IsWindows {
    BeforeEach {
        $global:UsaWinRoot = $null
        Use-LinuxHost -Root (New-StockHost)
        $null = Deploy-UsaBanner -Company Contoso -Environment PROD -VlanFile $Vlans
        $script:Json = Join-Path $global:UsaDeployRoot 'etc/usabanner/usabanner.json'
    }

    It 'finds every part of a deploy in place: healthy, SSH open, the settings chosen, and the VLAN this host is in' {
        $status = Get-ReadOnlyStatus
        $status.PSObject.TypeNames[0] | Should -BeExactly 'UsaBanner.Status'
        Get-Problem $status | Should -BeNullOrEmpty
        @($status.Checks | ForEach-Object { $_.Check }) | Should -Be @('configuration', 'drawn for this host', 'banner after login', 'console banner', 'ssh banner', 'stock motd off', 'periodic job', 'module copy', 'update channel', 'old banner')
        $status.Healthy | Should -BeTrue
        $status.Deployed | Should -BeTrue
        $status.HostName | Should -BeExactly 'h-vsl-web1.ad.example'
        $status.Os | Should -BeExactly 'ubuntu'
        $status.Version | Should -BeExactly $Version
        $status.Ssh | Should -BeExactly 'open'
        $status.Services | Should -BeExactly 'ssh, cron, chrony active'
        $status.Settings | Should -Be @('company: "Contoso"', 'environment: "PROD"', 'vlans: 2 entries')
        $status.Configuration['company'] | Should -BeExactly 'Contoso'
        @($status.Vlans | ForEach-Object { "$($_.Tag) $($_.Name) $($_.Cidr) $($_.Color) $($_.Short) $($_.ThisHost)" }) | Should -Be @(
            '40 Servers 10.20.40.0/24 Teal SRV True', '10 User Devices 10.20.10.0/24 Blue USR False')
        (Get-Check $status 'drawn for this host').Detail | Should -BeExactly 'drawn for h-vsl-web1.ad.example (10.20.40.80)'
        (Get-Check $status 'ssh banner').Detail | Should -BeExactly 'sshd sends /etc/usabanner/issue.net before authentication'
        (Get-Check $status 'module copy').Detail | Should -BeExactly "UsaBanner $Version, for every user and the periodic job: /usr/local/share/powershell/Modules/UsaBanner/$Version"
    }

    It 'prints as a list a person can read: a line for each check, VLAN and setting' {
        $text = @((Get-UsaBanner | Out-String -Width 250) -split "`r?`n")
        $text | Should -Contain 'Healthy  : True'
        $text | Should -Contain ('Checks   : {0,-8} {1,-20} {2}' -f 'ok', 'configuration', '/etc/usabanner/usabanner.json')
        $text | Should -Contain ('           {0,-8} {1,-20} {2}' -f 'ok', 'console banner', 'agetty prints /etc/issue.d/50-usabanner.issue before the login prompt')
        $text | Should -Contain ('Vlans    : {0,4} {1,-20} {2,-18} {3}{4}' -f 40, 'Servers', '10.20.40.0/24', 'Teal', '  (this host)')
        $text | Should -Contain ('           {0,4} {1,-20} {2,-18} {3}' -f 10, 'User Devices', '10.20.10.0/24', 'Blue')
        $text | Should -Contain 'Settings : company: "Contoso"'
        $text | Should -Contain '           environment: "PROD"'
    }

    It 'says when no banner is deployed here' {
        Use-LinuxHost -Root (New-StockHost)
        $status = Get-ReadOnlyStatus
        $status.Deployed | Should -BeFalse
        $status.Healthy | Should -BeFalse
        @($status.Checks).Count | Should -Be 1
        (Get-Check $status 'configuration').State | Should -BeExactly 'missing'
        (Get-Check $status 'configuration').Detail | Should -BeExactly 'there is no /etc/usabanner/usabanner.json: no banner is deployed here'
        $status.Version | Should -BeExactly ''
        $status.Settings | Should -BeNullOrEmpty
        $status.Vlans | Should -BeNullOrEmpty
        $status.Configuration | Should -BeNullOrEmpty
    }

    It 'names the banner of this repository''s install.sh on a host that has it' {
        Use-LinuxHost -Root (New-StockHost)
        Write-TestFile $global:UsaDeployRoot 'etc/update-motd.d/05-manatech-banner' "#!/bin/sh`n" -Mode '755'
        (Get-Check (Get-ReadOnlyStatus) 'configuration').Detail | Should -BeExactly ("there is no /etc/usabanner/usabanner.json: no banner is deployed here. " +
            "This host has the banner of this repository's install.sh (/etc/update-motd.d/05-manatech-banner), which Deploy-UsaBanner -ReplaceOldBanner takes off before it deploys this one")
    }

    It 'finds the banners drawn for the old name after a rename, until the periodic job draws them again' {
        Mock -ModuleName UsaBanner Get-UsaBannerHostFacts { @{ Name = 'h-vsl-web2.ad.example'; Ip = '10.20.40.80' } }
        $status = Get-ReadOnlyStatus
        $drawn = Get-Check $status 'drawn for this host'
        $drawn.State | Should -BeExactly 'stale'
        $drawn.Detail | Should -BeExactly 'drawn for h-vsl-web1.ad.example (10.20.40.80), and this host is h-vsl-web2.ad.example (10.20.40.80): the periodic job draws the banners again within 15 minutes'
        (Get-Check $status 'banner after login').State | Should -BeExactly 'stale'
        (Get-Check $status 'banner after login').Detail | Should -BeExactly '/var/lib/usabanner/postlogin.frame was drawn for another name, address or configuration'
        # agetty fills in the name, so the console's banner holds none to be out of date.
        (Get-Check $status 'console banner').State | Should -BeExactly 'ok'
        $status.Healthy | Should -BeFalse
        $null = InModuleScope UsaBanner { Update-UsaBannerDrawing }
        Get-Problem (Get-UsaBanner) | Should -BeNullOrEmpty
    }

    It 'finds the banners drawn from another configuration after an edit of usabanner.json' {
        [System.IO.File]::WriteAllText($Json, [System.IO.File]::ReadAllText($Json).Replace('"PROD"', '"LAB"'))
        $status = Get-ReadOnlyStatus
        (Get-Check $status 'drawn for this host').Detail | Should -BeExactly 'drawn from another configuration: the periodic job draws the banners again within 15 minutes'
        $status.Settings | Should -Contain 'environment: "LAB"'
        $status.Healthy | Should -BeFalse
    }

    It 'names what broke: <Case>' -ForEach @(
        @{ Case = '05-usabanner deleted'; Check = 'banner after login'; State = 'missing'; Detail = '/etc/update-motd.d/05-usabanner is missing'
            Break = { [System.IO.File]::Delete((Join-Path $global:UsaDeployRoot 'etc/update-motd.d/05-usabanner')) } }
        @{ Case = '05-usabanner not executable'; Check = 'banner after login'; State = 'differs'; Detail = '/etc/update-motd.d/05-usabanner is not executable, so pam_motd skips it'
            Break = { [System.IO.File]::SetUnixFileMode((Join-Path $global:UsaDeployRoot 'etc/update-motd.d/05-usabanner'), [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead') } }
        @{ Case = 'a script of the renderer edited'; Check = 'banner after login'; State = 'differs'; Detail = '/usr/local/share/usabanner/facts.sh is not the module''s'
            Break = { [System.IO.File]::AppendAllText((Join-Path $global:UsaDeployRoot 'usr/local/share/usabanner/facts.sh'), "# edited`n") } }
        @{ Case = 'the frame deleted'; Check = 'banner after login'; State = 'missing'; Detail = '/var/lib/usabanner/postlogin.frame is missing'
            Break = { [System.IO.File]::Delete((Join-Path $global:UsaDeployRoot 'var/lib/usabanner/postlogin.frame')) } }
        @{ Case = 'the console''s banner edited'; Check = 'console banner'; State = 'differs'; Detail = '/etc/issue.d/50-usabanner.issue is not what the configuration draws: changed by hand, or drawn by another version of the module'
            Break = { [System.IO.File]::AppendAllText((Join-Path $global:UsaDeployRoot 'etc/issue.d/50-usabanner.issue'), "edited`n") } }
        @{ Case = 'the SSH drop-in deleted'; Check = 'ssh banner'; State = 'missing'; Detail = '/etc/ssh/sshd_config.d/00-usabanner.conf is missing'
            Break = { [System.IO.File]::Delete((Join-Path $global:UsaDeployRoot 'etc/ssh/sshd_config.d/00-usabanner.conf')) } }
        @{ Case = 'the SSH banner deleted'; Check = 'ssh banner'; State = 'missing'; Detail = '/etc/usabanner/issue.net is missing'
            Break = { [System.IO.File]::Delete((Join-Path $global:UsaDeployRoot 'etc/usabanner/issue.net')) } }
        @{ Case = 'a stock script turned back on'; Check = 'stock motd off'; State = 'differs'; Detail = '/etc/update-motd.d/50-motd-news runs again: Deploy-UsaBanner turns each off again'
            Break = { [System.IO.File]::SetUnixFileMode((Join-Path $global:UsaDeployRoot 'etc/update-motd.d/50-motd-news'), [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute') } }
        @{ Case = 'landscape-sysinfo running again'; Check = 'stock motd off'; State = 'differs'; Detail = '/etc/update-motd.d/50-landscape-sysinfo runs again: Deploy-UsaBanner turns each off again'
            Break = { [System.IO.File]::SetUnixFileMode((Join-Path $global:UsaDeployRoot 'usr/share/landscape/landscape-sysinfo.wrapper'), [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute') } }
        @{ Case = 'motd-news.timer enabled again'; Check = 'stock motd off'; State = 'differs'; Detail = 'motd-news.timer is enabled again: Deploy-UsaBanner turns each off again'
            Break = { $global:UsaDeployUnits.Masked = @() } }
        @{ Case = 'a unit of the periodic job deleted'; Check = 'periodic job'; State = 'missing'; Detail = '/etc/systemd/system/usabanner-sample.timer is missing'
            Break = { [System.IO.File]::Delete((Join-Path $global:UsaDeployRoot 'etc/systemd/system/usabanner-sample.timer')) } }
        @{ Case = 'the timer stopped'; Check = 'periodic job'; State = 'differs'; Detail = 'usabanner-sample.timer is disabled, not enabled; usabanner-sample.timer is inactive, not active'
            Break = {
                $global:UsaDeployAnswers['systemctl is-enabled usabanner-sample.timer'] = @{ ExitCode = 1; Output = @('disabled') }
                $global:UsaDeployAnswers['systemctl is-active usabanner-sample.timer'] = @{ ExitCode = 3; Output = @('inactive') }
            } }
        @{ Case = 'no sample for an hour'; Check = 'periodic job'; State = 'stale'; Detail = 'the last sample is 60 minutes old: the periodic job samples every 15'
            Break = { [System.IO.File]::SetLastWriteTimeUtc((Join-Path $global:UsaDeployRoot 'var/lib/usabanner/samples.tsv'), [datetime]::UtcNow.AddHours(-1)) } }
        @{ Case = 'the module''s copy deleted'; Check = 'module copy'; State = 'missing'; Detail = 'there is no copy in /usr/local/share/powershell/Modules/UsaBanner, where the periodic job imports it from'
            Break = { [System.IO.Directory]::Delete((Join-Path $global:UsaDeployRoot 'usr/local/share/powershell/Modules/UsaBanner'), $true) } }
        @{ Case = 'the configuration broken'; Check = 'configuration'; State = 'invalid'; Detail = '*usabanner.json is not a valid configuration:*'
            Break = { [System.IO.File]::WriteAllText((Join-Path $global:UsaDeployRoot 'etc/usabanner/usabanner.json'), '{ "company": 5 }') } }
    ) {
        & $Break
        $status = Get-ReadOnlyStatus
        $found = Get-Check $status $Check
        $found.State | Should -BeExactly $State -Because ((Get-Problem $status) -join '; ')
        $found.Detail | Should -BeLike $Detail
        $status.Healthy | Should -BeFalse
    }

    It 'says what it cannot know from a configuration it cannot read, and draws nothing from it' {
        [System.IO.File]::WriteAllText($Json, '{ "company": 5 }')
        $status = Get-ReadOnlyStatus
        foreach ($name in 'drawn for this host', 'console banner') { (Get-Check $status $name).State | Should -BeExactly 'unknown' -Because $name }
        $status.Settings | Should -BeNullOrEmpty
        $status.Configuration | Should -BeNullOrEmpty
    }

    It 'finds sshd sending another banner, from a file it reads first' {
        $global:UsaDeployAnswers['/usr/sbin/sshd -T'] = @{ ExitCode = 0; Output = @('port 22', 'banner /etc/issue.net') }
        $check = Get-Check (Get-ReadOnlyStatus) 'ssh banner'
        $check.State | Should -BeExactly 'differs'
        $check.Detail | Should -BeExactly 'sshd sends the Banner /etc/issue.net, not /etc/usabanner/issue.net: a file sshd reads before /etc/ssh/sshd_config.d/00-usabanner.conf sets one, and sshd takes the first'
    }

    It 'leaves to root what only root can read, which banner sshd sends, and is healthy still' {
        Mock -ModuleName UsaBanner Test-UsaBannerPrivileged { $false }
        $status = Get-ReadOnlyStatus
        $check = Get-Check $status 'ssh banner'
        $check.State | Should -BeExactly 'unknown'
        $check.Detail | Should -BeExactly '/etc/ssh/sshd_config.d/00-usabanner.conf and /etc/usabanner/issue.net are in place; sshd -T, which needs root, says whether sshd sends it'
        $global:UsaDeployCalls | Should -Not -Contain '/usr/sbin/sshd -T'
        $status.Healthy | Should -BeTrue
    }

    It 'says SSH is not installed where OpenSSH''s server is not, and the host is healthy still' {
        Use-LinuxHost -Root (New-StockHost -NoSshd)
        $null = Deploy-UsaBanner -Company Contoso
        $status = Get-ReadOnlyStatus
        $status.Ssh | Should -BeExactly 'not installed'
        (Get-Check $status 'ssh banner').State | Should -BeExactly 'off'
        $status.Healthy | Should -BeTrue
    }

    It 'says SSH is closed where neither sshd nor its socket runs' {
        $global:UsaDeployAnswers['systemctl is-active ssh.service'] = @{ ExitCode = 3; Output = @('inactive') }
        $global:UsaDeployAnswers['systemctl is-active ssh.socket'] = @{ ExitCode = 3; Output = @('inactive') }
        (Get-ReadOnlyStatus).Ssh | Should -BeExactly 'closed'
    }

    It 'shows the SSH banner as sshd sends it' {
        $lines = @(Get-UsaBanner PreLogon)
        (($lines -join "`n") + "`n`n") | Should -BeExactly ([System.IO.File]::ReadAllText((Join-Path $global:UsaDeployRoot 'etc/usabanner/issue.net')))
        $lines | Should -Be @(Show-UsaBanner PreLogon -Path $Json -Os ubuntu -Facts @{ Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80' })
    }

    It 'shows the console''s banner as agetty prints it: the same as Show-UsaBanner draws, where it holds no name to fill in' {
        $null = Deploy-UsaBanner -Company Contoso -Environment PROD -VlanFile $Vlans -PreInit None
        Show-UsaBannerEscape @(Get-UsaBanner PreInit) | Should -BeExactly (Show-UsaBannerEscape @(Show-UsaBanner PreInit -Path $Json -Os ubuntu -ColorMode 16 -Facts @{ Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80' }))
    }

    It 'shows the console''s banner as agetty prints it: this host''s name and address filled in' {
        $null = Deploy-UsaBanner -Company Contoso -Environment PROD -VlanFile $Vlans -PreInit HostName, Ip
        $text = @(Get-UsaBanner PreInit) -join "`n"
        $text | Should -Match ([regex]::Escape("$([char]27)["))
        $text | Should -Not -Match '\\e\['
        ($text -replace "$([char]27)\[[0-9;]*m", '') | Should -Match 'h-vsl-web1   10\.20\.40\.80'
    }

    It 'shows the banner after login by running 05-usabanner, as pam_motd does' {
        $global:UsaDeployAnswers['sh /etc/update-motd.d/05-usabanner'] = @{ ExitCode = 0; Output = @('line one', 'line two') }
        @(Get-UsaBanner PostLogon) | Should -Be @('line one', 'line two')
        Get-Calls | Should -Contain 'sh /etc/update-motd.d/05-usabanner'
    }

    It 'runs the installed 05-usabanner for real: the frame drawn for this host, filled in by sh and awk' {
        Mock -ModuleName UsaBanner Invoke-UsaBannerNative -ParameterFilter { $FilePath -eq 'sh' } {
            $env:USABANNER_ROOT = $global:UsaDeployRoot
            try { $output = @(& sh "$global:UsaDeployRoot$($ArgumentList[0])" 2>&1 | ForEach-Object { "$_" }) }
            finally { Remove-Item -Path Env:USABANNER_ROOT }
            @{ ExitCode = $LASTEXITCODE; Output = $output }
        }
        $lines = @(Get-UsaBanner PostLogon)
        $lines.Count | Should -BeGreaterThan 5
        # The name's letters take the naming standard's colours: read it without them.
        (($lines -join "`n") -replace "$([char]27)\[[0-9;]*m", '') | Should -Match 'h-vsl-web1\.ad\.example'
    }

    It 'says when 05-usabanner fails' {
        $global:UsaDeployAnswers['sh /etc/update-motd.d/05-usabanner'] = @{ ExitCode = 2; Output = @('awk: syntax error') }
        { Get-UsaBanner PostLogon } | Should -Throw '*/etc/update-motd.d/05-usabanner failed (exit code 2): awk: syntax error*'
    }

    It 'says there is no banner to show where none is deployed' {
        Use-LinuxHost -Root (New-StockHost)
        { Get-UsaBanner PreLogon } | Should -Throw '*no banner is deployed here, so there is none to show*'
    }
}

Describe 'Get-UsaBanner on Windows Server' {
    BeforeEach {
        Use-WindowsHost (New-WindowsHost)
        $script:Data = Join-Path $global:UsaWinRoot 'ProgramData/UsagiTools/Banner'
        $null = Deploy-UsaBanner -Company Contoso -Environment PROD -VlanFile $Vlans
    }

    It 'finds every part of a deploy in place: healthy, SSH open, the settings chosen, and the VLAN this host is in' {
        $status = Get-ReadOnlyStatus
        Get-Problem $status | Should -BeNullOrEmpty
        @($status.Checks | ForEach-Object { $_.Check }) | Should -Be @('configuration', 'banner after login', 'ssh banner', 'ssh default shell', 'logon notice', 'periodic job', 'folder acl', 'module copy', 'update channel', 'old banner')
        $status.Healthy | Should -BeTrue
        $status.HostName | Should -BeExactly 'BEVSW-APP1.ad.example'
        $status.Os | Should -BeExactly 'windows'
        $status.Version | Should -BeExactly $Version
        $status.Ssh | Should -BeExactly 'open'
        $status.Services | Should -BeExactly 'sshd, W32Time running'
        $status.Settings | Should -Be @('company: "Contoso"', 'environment: "PROD"', 'vlans: 2 entries')
        @($status.Vlans | Where-Object { $_.ThisHost } | ForEach-Object { $_.Name }) | Should -Be @('Servers')
        (Get-Check $status 'logon notice').Detail | Should -BeExactly 'WARNING, before a console or RDP sign-in'
    }

    It 'says when no banner is deployed here' {
        Use-WindowsHost (New-WindowsHost)
        $status = Get-ReadOnlyStatus
        $status.Deployed | Should -BeFalse
        $status.Healthy | Should -BeFalse
        (Get-Check $status 'configuration').State | Should -BeExactly 'missing'
    }

    It 'names the banner of this repository''s Install-ManatechBanner.ps1 on a host that has it' {
        Use-WindowsHost (New-WindowsHost)
        $null = New-Item -ItemType Directory -Path (Join-Path $global:UsaWinRoot 'ProgramData/Manatech')
        (Get-Check (Get-ReadOnlyStatus) 'configuration').Detail | Should -BeLike "*This host has the banner of this repository's Install-ManatechBanner.ps1 (*ProgramData/Manatech), which Deploy-UsaBanner -ReplaceOldBanner takes off before it deploys this one"
    }

    It 'leaves a logon notice someone else set: off, and the host healthy still' {
        $global:UsaWinNotice = @{ Caption = 'Contoso IT'; Text = 'Authorized use only.'; Exists = $true }
        $status = Get-ReadOnlyStatus
        $check = Get-Check $status 'logon notice'
        $check.State | Should -BeExactly 'off'
        $check.Detail | Should -BeExactly 'it holds someone else''s text, set by hand or by a Group Policy: Contoso IT'
        $status.Healthy | Should -BeTrue
    }

    It 'says SSH logins show no banner where sshd starts cmd.exe: off, and the host healthy still' {
        Mock -ModuleName UsaBanner Get-UsaBannerSshDefaultShell { '' }
        $status = Get-ReadOnlyStatus
        $check = Get-Check $status 'ssh default shell'
        $check.State | Should -BeExactly 'off'
        $check.Detail | Should -BeExactly 'sshd starts cmd.exe at a login, so no banner shows after an SSH login: deploy-usawinssh sets pwsh.exe'
        $status.Healthy | Should -BeTrue
    }

    It 'names what broke: <Case>' -ForEach @(
        @{ Case = 'the folder''s ACL changed'; Check = 'folder acl'; State = 'differs'; Detail = '*does not have the banner''s ACL, so others may change the banners every login shows: Deploy-UsaBanner sets it again'
            Break = { $global:UsaWinAcl = $false } }
        @{ Case = 'a profile''s block taken out'; Check = 'banner after login'; State = 'missing'; Detail = '*Windows/System32/WindowsPowerShell/v1.0/profile.ps1 has no block'
            Break = { [System.IO.File]::WriteAllText((Join-Path $global:UsaWinRoot 'Windows/System32/WindowsPowerShell/v1.0/profile.ps1'), "Set-Location C:\`r`n") } }
        @{ Case = 'sshd_config''s Banner line taken out'; Check = 'ssh banner'; State = 'missing'; Detail = '*ProgramData/ssh/sshd_config has no Banner line for it'
            Break = { [System.IO.File]::WriteAllText((Join-Path $global:UsaWinRoot 'ProgramData/ssh/sshd_config'), $StockSshd) } }
        @{ Case = 'the SSH banner edited'; Check = 'ssh banner'; State = 'differs'; Detail = '*sshd-banner.txt is not what the configuration draws for *: Deploy-UsaBanner draws it again'
            Break = { [System.IO.File]::AppendAllText((Join-Path $global:UsaWinRoot 'ProgramData/UsagiTools/Banner/sshd-banner.txt'), "edited`n") } }
        @{ Case = 'the data file edited'; Check = 'configuration'; State = 'differs'; Detail = '*usabanner.psd1, which each login reads, does not hold the settings of usabanner.json: Deploy-UsaBanner writes it again'
            Break = { [System.IO.File]::AppendAllText((Join-Path $global:UsaWinRoot 'ProgramData/UsagiTools/Banner/usabanner.psd1'), "# edited`n") } }
        @{ Case = 'the logon notice cleared'; Check = 'logon notice'; State = 'missing'; Detail = 'no logon notice is set: Deploy-UsaBanner sets it where none is'
            Break = { $global:UsaWinNotice = @{ Caption = ''; Text = ''; Exists = $false } } }
        @{ Case = 'the task unregistered'; Check = 'periodic job'; State = 'missing'; Detail = 'there is no task \UsagiTools\UsaBanner sample'
            Break = { $global:UsaWinTasks.Remove('UsaBanner sample') } }
        @{ Case = 'the task changed'; Check = 'periodic job'; State = 'differs'; Detail = 'the task runs C:\Windows\System32\cmd.exe /c exit'
            Break = { $global:UsaWinTasks['UsaBanner sample'] = @{ Execute = 'C:\Windows\System32\cmd.exe'; Arguments = '/c exit' } } }
        @{ Case = 'the module''s copy deleted'; Check = 'module copy'; State = 'missing'; Detail = 'there is no copy in *ProgramFiles/WindowsPowerShell/Modules/UsaBanner, where every login and the periodic job import it from'
            Break = { [System.IO.Directory]::Delete((Join-Path $global:UsaWinRoot 'ProgramFiles/WindowsPowerShell/Modules/UsaBanner'), $true) } }
    ) {
        & $Break
        $status = Get-ReadOnlyStatus
        $found = Get-Check $status $Check
        $found.State | Should -BeExactly $State -Because ((Get-Problem $status) -join '; ')
        $found.Detail | Should -BeLike $Detail
        $status.Healthy | Should -BeFalse
    }

    It 'finds sshd not restarted since its Banner line went in: stale, with the command that restarts it' {
        Mock -ModuleName UsaBanner Get-UsaBannerServiceStart { [datetime]::UtcNow.AddHours(-1) }
        $status = Get-ReadOnlyStatus
        $check = Get-Check $status 'ssh banner'
        $check.State | Should -BeExactly 'stale'
        $check.Detail | Should -BeLike 'sshd started at *Z, before *ProgramData/ssh/sshd_config last changed at *Z: it reads the Banner line at its next start (Restart-Service sshd)'
        $status.Healthy | Should -BeFalse
    }

    It 'leaves to an administrator a task another user cannot see' {
        Mock -ModuleName UsaBanner Test-UsaBannerPrivileged { $false }
        $global:UsaWinTasks.Remove('UsaBanner sample')
        $status = Get-ReadOnlyStatus
        (Get-Check $status 'periodic job').State | Should -BeExactly 'unknown'
        $status.Healthy | Should -BeTrue
    }

    It 'says SSH is not installed where there is no sshd service, and closed where it is stopped' {
        Mock -ModuleName UsaBanner Get-UsaBannerServiceState { 'Stopped' }
        (Get-ReadOnlyStatus).Ssh | Should -BeExactly 'closed'
        Mock -ModuleName UsaBanner Get-UsaBannerWindowsSshd { '' }
        $status = Get-ReadOnlyStatus
        $status.Ssh | Should -BeExactly 'not installed'
        (Get-Check $status 'ssh banner').State | Should -BeExactly 'off'
        (Get-Check $status 'ssh default shell').State | Should -BeExactly 'off'
    }

    It 'shows the logon notice, the SSH banner and the banner after login as installed' {
        $json = Join-Path $Data 'usabanner.json'
        @(Get-UsaBanner PreInit) | Should -Be @(Show-UsaBanner PreInit -Path $json -Os windows)
        @(Get-UsaBanner PreLogon) | Should -Be @(Show-UsaBanner PreLogon -Path $json -Os windows -Facts @{ Name = [System.Environment]::MachineName; Ip = '' })
        @(Get-UsaBanner PostLogon) | Should -Be @(Show-UsaBanner -Path (Join-Path $Data 'usabanner.psd1'))
    }

    It 'says so when no logon notice is set, and shows none' {
        $global:UsaWinNotice = @{ Caption = ''; Text = ''; Exists = $false }
        @(Get-UsaBanner PreInit -WarningVariable warned -WarningAction SilentlyContinue) | Should -BeNullOrEmpty
        @($warned | ForEach-Object { $_.Message }) | Should -Be @('UsaBanner: no logon notice is set here.')
    }
}

Describe 'a check that covers several files' {
    It 'takes the worst state among them, and lists each that is not ok' {
        InModuleScope UsaBanner {
            $check = Join-UsaBannerFinding -Check 'a check' -Ok 'all well' -Found @(
                @{ State = 'ok'; Text = '' }, @{ State = 'stale'; Text = 'one is out of date' }, @{ State = 'missing'; Text = 'one is gone' })
            $check.State | Should -BeExactly 'missing'
            $check.Detail | Should -BeExactly 'one is out of date; one is gone'
        }
    }

    It 'reports a state it does not rank, rather than failing' {
        InModuleScope UsaBanner {
            (Join-UsaBannerFinding -Check 'a check' -Ok 'all well' -Found @(@{ State = 'odd'; Text = 'something' })).State | Should -BeExactly 'odd'
        }
    }
}

Describe 'ConvertFrom-UsaBannerIssueText' {
    It 'prints what agetty prints from ConvertTo-UsaBannerIssueLine''s line: the escapes back, the name and address filled in' {
        $both = InModuleScope UsaBanner {
            $line = "a\b $([char]27)[31mred$([char]27)[0m $script:UsaIssueHost $script:UsaIssueAddress \n"
            $issue = ConvertTo-UsaBannerIssueLine -Line $line
            @{
                Printed  = @(ConvertFrom-UsaBannerIssueText -Text "$issue`n`n" -HostName 'h-vsl-web1' -Ip '10.20.40.80')
                Expected = @($line.Replace($script:UsaIssueHost, 'h-vsl-web1').Replace($script:UsaIssueAddress, '10.20.40.80'))
            }
        }
        Show-UsaBannerEscape $both.Printed | Should -BeExactly (Show-UsaBannerEscape $both.Expected)
    }

    It 'prints the character after a backslash agetty does not know, and drops the backslash, as agetty does' {
        InModuleScope UsaBanner { ConvertFrom-UsaBannerIssueText -Text 'x\qy' } | Should -BeExactly 'xqy'
    }
}
