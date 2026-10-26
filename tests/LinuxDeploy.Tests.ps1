# Deploy-UsaBanner and Remove-UsaBanner on Ubuntu (UsaBanner/Private/LinuxDeploy.ps1), on a
# folder laid out as a stock Ubuntu 24.04 host. Every program a deploy runs goes through
# Invoke-UsaBannerNative, which these tests answer as such a host would, remembering what
# each call changed; nothing runs on the host the tests run on. run-parts and
# systemd-analyze, which change nothing, run for real. What systemctl, sshd and dpkg do on a
# real host is the lab's to show.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $moduleRoot = Join-Path $repoRoot 'UsaBanner'
    Import-Module (Join-Path $moduleRoot 'UsaBanner.psd1') -Force
    $script:Tab = "`t"
    . (Join-Path $PSScriptRoot 'FakeHosts.ps1')
}

AfterAll {
    Remove-Variable -Name UsaDeployCalls, UsaDeployAnswers, UsaDeployUnits, UsaDeployRoot -Scope Global -ErrorAction SilentlyContinue
    Remove-Module UsaBanner -ErrorAction SilentlyContinue
}

Describe 'Deploy-UsaBanner on a stock Ubuntu host' -Skip:$IsWindows {
    BeforeEach {
        $global:UsaDeployRoot = New-StockHost
        Use-StockAnswers
        Mock -ModuleName UsaBanner Get-UsaBannerHostRoot { $global:UsaDeployRoot }
        Mock -ModuleName UsaBanner Test-UsaBannerPrivileged { $true }
        Mock -ModuleName UsaBanner Get-UsaBannerHostFacts { @{ Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80' } }
    }

    It 'puts each file in place with its mode' {
        $null = Deploy-UsaBanner -Company Contoso -Environment LAB
        $root = $global:UsaDeployRoot
        $expected = [ordered]@{
            'etc/usabanner/usabanner.json'             = '644'
            'etc/usabanner/issue.net'                  = '644'
            'etc/issue.d/50-usabanner.issue'           = '644'
            'etc/ssh/sshd_config.d/00-usabanner.conf'  = '644'
            'etc/update-motd.d/05-usabanner'           = '755'
            'usr/local/share/usabanner/ad-description.sh' = '644'
            'usr/local/share/usabanner/facts.sh'       = '644'
            'usr/local/share/usabanner/postlogin.awk'  = '644'
            'usr/local/share/usabanner/postlogin.sh'   = '644'
            'usr/local/share/usabanner/redraw.sh'      = '644'
            'usr/local/share/usabanner/sample.sh'      = '644'
            'var/lib/usabanner/postlogin.frame'        = '644'
            'var/lib/usabanner/login.env'              = '644'
            'var/lib/usabanner/drawn'                  = '644'
            'var/lib/usabanner/deploy.json'            = '644'
            'etc/systemd/system/usabanner-sample.service' = '644'
            'etc/systemd/system/usabanner-sample.timer'   = '644'
        }
        foreach ($path in $expected.Keys) { Get-Mode $root $path | Should -Be $expected[$path] -Because $path }
        foreach ($file in 'ad-description.sh', 'facts.sh', 'postlogin.awk', 'postlogin.sh', 'redraw.sh', 'sample.sh') {
            (Get-FileHash -LiteralPath (Join-Path $root "usr/local/share/usabanner/$file")).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $moduleRoot 'linux' $file)).Hash -Because $file
        }
        (Get-FileHash -LiteralPath (Join-Path $root 'etc/update-motd.d/05-usabanner')).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $moduleRoot 'linux' '05-usabanner')).Hash
        Get-Content -LiteralPath (Join-Path $root 'etc/ssh/sshd_config.d/00-usabanner.conf') | Select-Object -Last 1 | Should -BeExactly 'Banner /etc/usabanner/issue.net'
        Get-Content -LiteralPath (Join-Path $root 'var/lib/usabanner/login.env') -Raw | Should -BeExactly "USABANNER_SERVICES=default`n"
        (Get-Content -LiteralPath (Join-Path $root 'etc/usabanner/usabanner.json') -Raw | ConvertFrom-Json).company | Should -BeExactly 'Contoso'
    }

    It 'draws the banners before login as the module draws them, ending in a blank line' {
        $null = Deploy-UsaBanner -Company Contoso -PreLogon HostName
        $root = $global:UsaDeployRoot
        $expected = InModuleScope UsaBanner -Parameters @{ Path = (Join-Path $root 'etc/usabanner/usabanner.json') } {
            param($Path)
            $config = Read-UsaBannerConfig -Path $Path
            @{
                Issue = (@(Get-UsaBannerPreInit -Config $config -Os ubuntu) -join "`n") + "`n`n"
                Net   = (@(Get-UsaBannerPreLogon -Config $config -Os ubuntu -Facts @{ HostName = 'h-vsl-web1'; Ip = '10.20.40.80' }) -join "`n") + "`n`n"
            }
        }
        [System.IO.File]::ReadAllText((Join-Path $root 'etc/issue.d/50-usabanner.issue')) | Should -BeExactly $expected.Issue
        $net = [System.IO.File]::ReadAllText((Join-Path $root 'etc/usabanner/issue.net'))
        $net | Should -BeExactly $expected.Net
        $net | Should -Match 'h-vsl-web1'
        $net | Should -Not -Match '[^\x0A\x20-\x7E]'
    }

    It 'shows after login what the module draws for the same facts, in 256 colours and ASCII for auto, with the services the configuration names' {
        $null = Deploy-UsaBanner -Company Contoso -Environment LAB -Services ssh, postgresql
        $root = $global:UsaDeployRoot
        # facts.sh stood in for by fixed records, and the services it was handed.
        Write-TestFile $root 'usr/local/share/usabanner/facts.sh' (@(
                '#!/bin/sh'
                "printf 'name\th-vsl-web1.ad.example\nip\t10.20.40.80\nos\tUbuntu 24.04.3 LTS, kernel 6.8.0-87-generic\nuptime\t12d 6h 40m\n'"
                "printf 'services\t%s\tgood\ncheck\tservices\n' `"`$USABANNER_SERVICES`""
            ) -join "`n")
        $shown = @(& env "USABANNER_ROOT=$root" sh (Join-Path $root 'etc/update-motd.d/05-usabanner'))
        $LASTEXITCODE | Should -Be 0
        $drawn = @(InModuleScope UsaBanner -Parameters @{ Path = (Join-Path $root 'etc/usabanner/usabanner.json') } {
                param($Path)
                $facts = ConvertFrom-UsaBannerFactRecord -Line @(
                    "name`th-vsl-web1.ad.example", "ip`t10.20.40.80", "os`tUbuntu 24.04.3 LTS, kernel 6.8.0-87-generic",
                    "uptime`t12d 6h 40m", "services`tssh postgresql`tgood", "check`tservices")
                Get-UsaBannerPostLogon -Config (Read-UsaBannerConfig -Path $Path) -Os ubuntu -Facts $facts -Mode '256' -AsciiOnly
            })
        ($shown -join "`n") | Should -BeExactly ($drawn -join "`n")
        ($shown -join "`n") | Should -Match ([regex]::Escape("$([char]27)[38;5;"))
        ($shown -join "`n") | Should -Not -Match '[^\x00-\x7F]'
    }

    It 'draws in the colours and glyphs the flags give' {
        $null = Deploy-UsaBanner -Company Contoso -ColorMode truecolor -Glyphs unicode
        $frame = [System.IO.File]::ReadAllText((Join-Path $global:UsaDeployRoot 'var/lib/usabanner/postlogin.frame'))
        $frame | Should -Match ([regex]::Escape("$([char]27)[38;2;"))
        $frame | Should -Match ([string][char]0x2501)
    }

    It 'leaves pam_motd running the banner and the stock scripts it keeps, and none it turned off' {
        $root = $global:UsaDeployRoot
        $runParts = { @(& run-parts --lsbsysinit --test (Join-Path $root 'etc/update-motd.d') | ForEach-Object { Split-Path $_ -Leaf }) }
        & $runParts | Should -Be @('00-header', '10-help-text', '50-landscape-sysinfo', '50-motd-news', '85-fwupd', '90-updates-available', '91-release-upgrade', '95-hwe-eol', '98-reboot-required')
        $null = Deploy-UsaBanner -Company Contoso
        & $runParts | Should -Be @('05-usabanner', '85-fwupd', '91-release-upgrade', '95-hwe-eol')
    }

    It 'turns the stock scripts off with chmod -x, never deleting one, and records the mode each had' {
        $null = Deploy-UsaBanner -Company Contoso
        $root = $global:UsaDeployRoot
        foreach ($name in '00-header', '10-help-text', '50-motd-news', '90-updates-available', '98-reboot-required') {
            Get-Mode $root "etc/update-motd.d/$name" | Should -Be '644' -Because $name
        }
        Get-Mode $root 'etc/update-motd.d/91-release-upgrade' | Should -Be '755'
        @((Get-Record)['retired'] | ForEach-Object { "$($_['path']) $($_['mode'])" }) | Should -Be @(
            '/etc/update-motd.d/00-header 755', '/etc/update-motd.d/10-help-text 755', '/etc/update-motd.d/50-motd-news 755',
            '/etc/update-motd.d/90-updates-available 755', '/etc/update-motd.d/98-reboot-required 755')
    }

    It 'keeps landscape-sysinfo off with a dpkg statoverride on landscape-common''s file, the link''s target (<Form>)' -ForEach @(
        @{ Form = 'a relative link'; Absolute = $false }
        @{ Form = 'an absolute link, as Ubuntu ships it'; Absolute = $true }
    ) {
        $global:UsaDeployRoot = New-StockHost -AbsoluteLink:$Absolute
        $null = Deploy-UsaBanner -Company Contoso
        Get-Calls | Should -Contain 'dpkg -S /usr/share/landscape/landscape-sysinfo.wrapper'
        Get-Calls | Should -Contain 'dpkg-statoverride --update --add root root 0644 /usr/share/landscape/landscape-sysinfo.wrapper'
        (Get-Record)['statoverride'][0]['path'] | Should -BeExactly '/usr/share/landscape/landscape-sysinfo.wrapper'
        (Get-Record)['statoverride'][0]['mode'] | Should -BeExactly '755'
    }

    It 'masks motd-news.timer rather than changing /etc/default/motd-news, and records that it was running' {
        $null = Deploy-UsaBanner -Company Contoso
        Get-Calls -Changes | Should -Contain 'systemctl mask motd-news.timer'
        (Get-Record)['masked'][0]['unit'] | Should -BeExactly 'motd-news.timer'
        (Get-Record)['masked'][0]['active'] | Should -BeTrue
    }

    It 'stops motd-news.timer before it masks it, so the timer is not left failed for every login to list' {
        # The lab (2026-10-23): mask --now on the running timer left it "Failed with result 'resources'".
        $null = Deploy-UsaBanner -Company Contoso
        @(Get-Calls -Changes | Where-Object { $_ -like 'systemctl * motd-news.timer' }) | Should -Be @('systemctl stop motd-news.timer', 'systemctl mask motd-news.timer')
        $global:UsaDeployUnits.Failed | Should -Not -Contain 'motd-news.timer'
    }

    It 'checks sshd''s configuration with the Banner line, then reloads ssh, then reads what sshd sends' {
        $null = Deploy-UsaBanner -Company Contoso
        @(Get-Calls | Where-Object { $_ -match 'sshd|ssh$' }) | Should -Be @('/usr/sbin/sshd -t', 'systemctl try-reload-or-restart ssh', '/usr/sbin/sshd -T')
    }

    It 'takes the Banner line out again when sshd -t refuses it, and says so' {
        Use-StockAnswers @{ '/usr/sbin/sshd -t' = @{ ExitCode = 255; Output = @('/etc/ssh/sshd_config.d/00-usabanner.conf line 4: Bad configuration option') } }
        $lines = @(Deploy-UsaBanner -Company Contoso -WarningVariable warned -WarningAction SilentlyContinue)
        Test-Path -LiteralPath (Join-Path $global:UsaDeployRoot 'etc/ssh/sshd_config.d/00-usabanner.conf') | Should -BeFalse
        Get-Calls | Should -Not -Contain 'systemctl try-reload-or-restart ssh'
        "$warned" | Should -BeLike '*sshd -t refused the configuration*so it is out again*Bad configuration option*'
        $lines | Should -Not -Contain 'reloaded ssh: sessions already open carry on'
    }

    It 'warns when sshd sends another Banner, set before its own line' {
        Use-StockAnswers @{ '/usr/sbin/sshd -T' = @{ ExitCode = 0; Output = @('banner /etc/issue.net') } }
        $null = Deploy-UsaBanner -Company Contoso -WarningVariable warned -WarningAction SilentlyContinue
        "$warned" | Should -BeLike '*sshd sends the Banner /etc/issue.net, not /etc/usabanner/issue.net*'
    }

    It 'makes /run/sshd before it asks sshd -T, as after a boot before any connection, and warns of nothing' {
        # The lab (2026-10-25): a deploy at boot, before any connection had started sshd, warned "sshd sends the
        # Banner none". sshd -T, like -t, will not run without /run/sshd, which sshd makes when it starts.
        $null = Deploy-UsaBanner -Company Contoso
        [System.IO.Directory]::Delete((Join-Path $global:UsaDeployRoot 'run/sshd'))
        Mock -ModuleName UsaBanner Invoke-UsaBannerNative -ParameterFilter { $FilePath -eq '/usr/sbin/sshd' -and "$ArgumentList" -ceq '-T' } {
            $global:UsaDeployCalls.Add('/usr/sbin/sshd -T')
            if ([System.IO.Directory]::Exists((Join-Path $global:UsaDeployRoot 'run/sshd'))) { return @{ ExitCode = 0; Output = @('port 22', 'banner /etc/usabanner/issue.net') } }
            @{ ExitCode = 255; Output = @('Missing privilege separation directory: /run/sshd') }
        }
        $lines = @(Deploy-UsaBanner -Company Contoso -WarningVariable warned -WarningAction SilentlyContinue)
        "$warned" | Should -BeNullOrEmpty
        $lines | Should -BeNullOrEmpty
        Join-Path $global:UsaDeployRoot 'run/sshd' | Should -Exist
        Get-Calls | Should -Contain '/usr/sbin/sshd -T'
    }

    It 'warns in sshd''s own words when sshd -T fails, and names no Banner' {
        Use-StockAnswers @{ '/usr/sbin/sshd -T' = @{ ExitCode = 255; Output = @('/etc/ssh/sshd_config line 7: Bad configuration option: Bogus') } }
        $null = Deploy-UsaBanner -Company Contoso -WarningVariable warned -WarningAction SilentlyContinue
        "$warned" | Should -BeLike '*sshd -T could not read the configuration, so which Banner sshd sends is not known: /etc/ssh/sshd_config line 7: Bad configuration option: Bogus*'
        "$warned" | Should -Not -BeLike '*sends the Banner*'
    }

    It 'adds no SSH banner where OpenSSH''s server is not installed, and says so' {
        $global:UsaDeployRoot = New-StockHost -NoSshd
        $lines = @(Deploy-UsaBanner -Company Contoso)
        Test-Path -LiteralPath (Join-Path $global:UsaDeployRoot 'etc/ssh/sshd_config.d/00-usabanner.conf') | Should -BeFalse
        @(Get-Calls | Where-Object { $_ -match 'sshd|ssh$' }) | Should -BeNullOrEmpty
        $lines | Should -Contain 'no SSH banner: OpenSSH''s server is not installed here; run Deploy-UsaBanner again once it is'
    }

    It 'installs the periodic job, enables it, and takes a first sample in the background' {
        $null = Deploy-UsaBanner -Company Contoso
        $root = $global:UsaDeployRoot
        @(Get-Calls -Changes | Where-Object { $_ -like 'systemctl*usabanner*' -or $_ -eq 'systemctl daemon-reload' }) |
            Should -Be @('systemctl daemon-reload', 'systemctl enable --now usabanner-sample.timer', 'systemctl start --no-block usabanner-sample.service')
        Get-Content -LiteralPath (Join-Path $root 'etc/systemd/system/usabanner-sample.service') | Should -Contain 'ExecStart=/bin/sh /usr/local/share/usabanner/sample.sh'
        Get-Content -LiteralPath (Join-Path $root 'etc/systemd/system/usabanner-sample.service') | Should -Contain 'ExecStartPost=/bin/sh /usr/local/share/usabanner/redraw.sh'
        Get-Content -LiteralPath (Join-Path $root 'etc/systemd/system/usabanner-sample.timer') | Should -Contain 'OnUnitActiveSec=15min'
    }

    It 'writes units that systemd-analyze verify accepts, where a broken one fails (else a pass proves nothing)' -Skip:(-not (Get-Command systemd-analyze -ErrorAction SilentlyContinue)) {
        $null = Deploy-UsaBanner -Company Contoso
        $units = Join-Path $global:UsaDeployRoot 'etc/systemd/system'
        $out = & systemd-analyze verify (Join-Path $units 'usabanner-sample.service') (Join-Path $units 'usabanner-sample.timer') 2>&1 | Out-String
        "$out`nexit=$LASTEXITCODE" | Should -Match 'exit=0$'
        $broken = Join-Path $TestDrive 'broken.service'
        [System.IO.File]::WriteAllText($broken, "[Service]`nType=oneshot`nExecStart=/nonexistent/usabanner-probe`n")
        $null = & systemd-analyze verify $broken 2>&1
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'copies the module where every user''s PowerShell finds it, byte for byte, its files 644 and folders 755' {
        $null = Deploy-UsaBanner -Company Contoso
        $version = (Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'UsaBanner.psd1')).ModuleVersion
        $copy = Join-Path $global:UsaDeployRoot "usr/local/share/powershell/Modules/UsaBanner/$version"
        # Each line without its mode: the worktree's files have whatever the umask gave them.
        $contents = { param($Folder) @(Get-HostState $Folder | ForEach-Object { $_ -replace '^(\S+) [0-7]+', '$1' }) }
        (& $contents $copy) | Should -Be (& $contents $moduleRoot)
        @(Get-HostState $copy | Where-Object { $_ -notmatch '^\S+/ 755$' -and $_ -notmatch '^\S+ 644 [0-9A-F]{64}$' }) | Should -BeNullOrEmpty
        (Get-Record)['module'] | Should -BeExactly "/usr/local/share/powershell/Modules/UsaBanner/$version"
    }

    It 'deletes the copy an earlier deploy recorded, of another version, and leaves one no deploy recorded' {
        # The lab (2026-10-23): a deploy of another version left the earlier copy, so Import-Module loaded the
        # newer of the two and Remove-UsaBanner, which reads the record, never took the older.
        $null = Deploy-UsaBanner -Company Contoso
        $version = (Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'UsaBanner.psd1')).ModuleVersion
        foreach ($old in '0.0.9', '0.0.5') { Write-TestFile $global:UsaDeployRoot "usr/local/share/powershell/Modules/UsaBanner/$old/UsaBanner.psd1" "@{ ModuleVersion = '$old' }`n" }
        $record = Get-Record
        $record['module'] = '/usr/local/share/powershell/Modules/UsaBanner/0.0.9'
        Write-TestFile $global:UsaDeployRoot 'var/lib/usabanner/deploy.json' ($record | ConvertTo-Json -Depth 8)
        $lines = @(Deploy-UsaBanner -Company Contoso)
        $lines | Should -Contain 'deleted /usr/local/share/powershell/Modules/UsaBanner/0.0.9 and the 1 file(s) in it: UsaBanner 0.0.9, the copy an earlier deploy installed'
        Join-Path $global:UsaDeployRoot 'usr/local/share/powershell/Modules/UsaBanner/0.0.9' | Should -Not -Exist
        Join-Path $global:UsaDeployRoot 'usr/local/share/powershell/Modules/UsaBanner/0.0.5' | Should -Exist
        (Get-Record)['module'] | Should -BeExactly "/usr/local/share/powershell/Modules/UsaBanner/$version"
    }

    It 'deletes no earlier copy under -WhatIf' {
        $null = Deploy-UsaBanner -Company Contoso
        Write-TestFile $global:UsaDeployRoot 'usr/local/share/powershell/Modules/UsaBanner/0.0.9/UsaBanner.psd1' "@{ ModuleVersion = '0.0.9' }`n"
        $record = Get-Record
        $record['module'] = '/usr/local/share/powershell/Modules/UsaBanner/0.0.9'
        Write-TestFile $global:UsaDeployRoot 'var/lib/usabanner/deploy.json' ($record | ConvertTo-Json -Depth 8)
        $null = Deploy-UsaBanner -Company Contoso -WhatIf
        Join-Path $global:UsaDeployRoot 'usr/local/share/powershell/Modules/UsaBanner/0.0.9/UsaBanner.psd1' | Should -Exist
        (Get-Record)['module'] | Should -BeExactly '/usr/local/share/powershell/Modules/UsaBanner/0.0.9'
    }

    It 'changes nothing on a second run with the same flags, and runs only what reads the host' {
        $null = Deploy-UsaBanner -Company Contoso -Environment LAB
        $before = Get-HostState $global:UsaDeployRoot
        $global:UsaDeployCalls.Clear()
        $lines = @(Deploy-UsaBanner -Company Contoso -Environment LAB)
        $lines | Should -BeNullOrEmpty
        Get-HostState $global:UsaDeployRoot | Should -Be $before
        Get-Calls -Changes | Should -BeNullOrEmpty
    }

    It 'says which settings a run changes, and rewrites only what they change' {
        $null = Deploy-UsaBanner -Company Contoso -Environment LAB
        $root = $global:UsaDeployRoot
        $kept = @('usr/local/share/usabanner/facts.sh', 'etc/update-motd.d/05-usabanner', 'etc/systemd/system/usabanner-sample.timer') | ForEach-Object { (Get-Item -LiteralPath (Join-Path $root $_)).LastWriteTimeUtc }
        $lines = @(Deploy-UsaBanner -Company Contoso -Environment PROD)
        $lines | Should -Contain 'rewrote /etc/usabanner/usabanner.json: the configuration (environment: "LAB" -> "PROD")'
        $lines | Should -Contain 'rewrote /var/lib/usabanner/postlogin.frame: the banner after login, drawn for the login renderer'
        @(@('usr/local/share/usabanner/facts.sh', 'etc/update-motd.d/05-usabanner', 'etc/systemd/system/usabanner-sample.timer') | ForEach-Object { (Get-Item -LiteralPath (Join-Path $root $_)).LastWriteTimeUtc }) | Should -Be $kept
    }

    It 'changes nothing under -WhatIf, and runs only what reads the host' {
        $before = Get-HostState $global:UsaDeployRoot
        $lines = @(Deploy-UsaBanner -Company Contoso -WhatIf)
        $lines | Should -BeNullOrEmpty
        Get-HostState $global:UsaDeployRoot | Should -Be $before
        Get-Calls -Changes | Should -BeNullOrEmpty
    }

    It 'changes nothing when a script run with -WhatIf calls it: the -WhatIf crosses into the module' {
        $before = Get-HostState $global:UsaDeployRoot
        $caller = Join-Path $TestDrive 'Deploy-Contoso.ps1'
        Set-Content -LiteralPath $caller -Value @('[CmdletBinding(SupportsShouldProcess)]', 'param()', 'Deploy-UsaBanner -Company Contoso')
        $null = & $caller -WhatIf
        Get-HostState $global:UsaDeployRoot | Should -Be $before
        Get-Calls -Changes | Should -BeNullOrEmpty
    }

    It 'runs as root only, and lets anyone look with -WhatIf' {
        Mock -ModuleName UsaBanner Test-UsaBannerPrivileged { $false }
        { Deploy-UsaBanner -Company Contoso } | Should -Throw '*Deploy-UsaBanner changes files under /etc, /usr/local and /var/lib, so it runs as root*'
        { $null = Deploy-UsaBanner -Company Contoso -WhatIf } | Should -Not -Throw
    }

    It 'refuses a host with the banner of this repository''s install.sh, naming what it found, and changes nothing' {
        $root = $global:UsaDeployRoot
        Write-TestFile $root 'etc/update-motd.d/05-manatech-banner' "#!/bin/sh`n" -Mode '755'
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'etc/manatech')
        $before = Get-HostState $root
        { Deploy-UsaBanner -Company Contoso } | Should -Throw "*this host has the banner of this repository's install.sh (/etc/update-motd.d/05-manatech-banner, /etc/manatech)*Deploy-UsaBanner -ReplaceOldBanner takes that banner off first*"
        Get-HostState $root | Should -Be $before
    }

    It 'refuses a host that is not Ubuntu' {
        Write-TestFile $global:UsaDeployRoot 'etc/os-release' "NAME=`"Debian GNU/Linux`"`nID=debian`n"
        { Deploy-UsaBanner -Company Contoso } | Should -Throw '*works on Ubuntu (24.04 and later) and Windows Server (2022 and later)*'
    }

    It 'changes nothing when a banner cannot be drawn' {
        Mock -ModuleName UsaBanner New-UsaBannerLoginFrame { throw 'the art broke' }
        $before = Get-HostState $global:UsaDeployRoot
        { Deploy-UsaBanner -Company Contoso } | Should -Throw '*the art broke*'
        Get-HostState $global:UsaDeployRoot | Should -Be $before
        Get-Calls | Should -BeNullOrEmpty
    }

    It 'draws the banners again when the host is renamed, and only those' {
        $null = Deploy-UsaBanner -Company Contoso -PreLogon HostName
        Mock -ModuleName UsaBanner Get-UsaBannerHostFacts { @{ Name = 'cw-vsl-web2.ad.example'; Ip = '10.20.40.81' } }
        $lines = @(InModuleScope UsaBanner { Update-UsaBannerDrawing })
        @($lines | ForEach-Object { ($_ -split ':')[0] }) | Should -Be @(
            'rewrote /var/lib/usabanner/postlogin.frame', 'rewrote /etc/usabanner/issue.net', 'rewrote /var/lib/usabanner/drawn')
        $root = $global:UsaDeployRoot
        [System.IO.File]::ReadAllText((Join-Path $root 'var/lib/usabanner/drawn')) | Should -BeLike "cw-vsl-web2.ad.example$($script:Tab)10.20.40.81$($script:Tab)*"
        [System.IO.File]::ReadAllText((Join-Path $root 'etc/usabanner/issue.net')) | Should -Match 'cw-vsl-web2'
    }

    It 'records the SHA-256 of the configuration as sha256sum prints it, for redraw.sh to compare, and none for an AD Description where none is cached' {
        $null = Deploy-UsaBanner -Company Contoso
        $root = $global:UsaDeployRoot
        $sum = (@(& sha256sum (Join-Path $root 'etc/usabanner/usabanner.json')) -split ' ')[0]
        [System.IO.File]::ReadAllText((Join-Path $root 'var/lib/usabanner/drawn')) | Should -BeExactly "h-vsl-web1.ad.example$($script:Tab)10.20.40.80$($script:Tab)$sum$($script:Tab)`n"
    }

    It 'records the SHA-256 of the cached AD Description as sha256sum prints it, for redraw.sh to compare' {
        $root = $global:UsaDeployRoot
        Write-TestFile $root 'var/lib/usabanner/ad-description' "PROD : Web front end`n"
        $null = Deploy-UsaBanner -Company Contoso
        $sum = (@(& sha256sum (Join-Path $root 'etc/usabanner/usabanner.json')) -split ' ')[0]
        $adSum = (@(& sha256sum (Join-Path $root 'var/lib/usabanner/ad-description')) -split ' ')[0]
        [System.IO.File]::ReadAllText((Join-Path $root 'var/lib/usabanner/drawn')) | Should -BeExactly "h-vsl-web1.ad.example$($script:Tab)10.20.40.80$($script:Tab)$sum$($script:Tab)$adSum`n"
    }

    It 'draws the tier and the role the cached AD Description gives, where the configuration leaves them unset' {
        $root = $global:UsaDeployRoot
        Write-TestFile $root 'var/lib/usabanner/ad-description' "PROD : Web front end`n"
        $null = Deploy-UsaBanner -Company Contoso -ColorMode none -Glyphs ascii
        $frame = [System.IO.File]::ReadAllText((Join-Path $root 'var/lib/usabanner/postlogin.frame'))
        $frame | Should -Match "(?m)^H`t +P R O D +$"
        $frame | Should -Match "(?m)^H`t\|  role      Web front end +\|$"
    }

    It 'draws the configuration''s own tier and role over the AD Description''s' {
        $root = $global:UsaDeployRoot
        Write-TestFile $root 'var/lib/usabanner/ad-description' "PROD : Web front end`n"
        $null = Deploy-UsaBanner -Company Contoso -Environment LAB -Role 'Build agents' -ColorMode none -Glyphs ascii
        $frame = [System.IO.File]::ReadAllText((Join-Path $root 'var/lib/usabanner/postlogin.frame'))
        $frame | Should -Match "(?m)^H`t +L A B +$"
        $frame | Should -Match "(?m)^H`t\|  role      Build agents +\|$"
        $frame | Should -Not -Match 'P R O D|Web front end'
    }

    It 'draws the banners again when the cached AD Description changes, and only those it is in' {
        $root = $global:UsaDeployRoot
        Write-TestFile $root 'var/lib/usabanner/ad-description' "PROD : Web front end`n"
        $null = Deploy-UsaBanner -Company Contoso -PreLogon HostName
        Write-TestFile $root 'var/lib/usabanner/ad-description' "LAB : Web front end`n"
        $lines = @(InModuleScope UsaBanner { Update-UsaBannerDrawing })
        @($lines | ForEach-Object { ($_ -split ':')[0] }) | Should -Be @('rewrote /var/lib/usabanner/postlogin.frame', 'rewrote /var/lib/usabanner/drawn')
        [System.IO.File]::ReadAllText((Join-Path $root 'var/lib/usabanner/postlogin.frame')) | Should -Match 'L A B'
    }
}

Describe 'Remove-UsaBanner on Ubuntu' -Skip:$IsWindows {
    BeforeEach {
        $global:UsaDeployRoot = New-StockHost
        Use-StockAnswers
        Mock -ModuleName UsaBanner Get-UsaBannerHostRoot { $global:UsaDeployRoot }
        Mock -ModuleName UsaBanner Test-UsaBannerPrivileged { $true }
        Mock -ModuleName UsaBanner Get-UsaBannerHostFacts { @{ Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80' } }
    }

    It 'leaves the host as it was before the deploy' {
        $before = Get-HostState $global:UsaDeployRoot
        $null = Deploy-UsaBanner -Company Contoso
        $global:UsaDeployCalls.Clear()
        $lines = @(Remove-UsaBanner)
        Get-HostState $global:UsaDeployRoot | Should -Be $before
        Get-Calls -Changes | Should -Be @(
            'systemctl disable --now usabanner-sample.timer'
            'systemctl stop usabanner-sample.service'
            'systemctl daemon-reload'
            'systemctl reset-failed usabanner-sample.service'
            'dpkg-statoverride --remove /usr/share/landscape/landscape-sysinfo.wrapper'
            'systemctl unmask motd-news.timer'
            'systemctl start motd-news.timer'
            'systemctl try-reload-or-restart ssh'
        )
        $lines | Should -Contain 'turned back on /etc/update-motd.d/10-help-text'
        $lines | Should -Contain 'deleted /etc/update-motd.d/05-usabanner: the banner after login'
    }

    It 'stops a sample still running before the banner''s folders go, so it cannot write them again' {
        # The lab (2026-10-23): a Remove-UsaBanner 9 s after a deploy, while the deploy's first sample still ran,
        # and the sample made the banner's folder again 4 s after it went.
        $before = Get-HostState $global:UsaDeployRoot
        $null = Deploy-UsaBanner -Company Contoso
        $null = Remove-UsaBanner
        # A run still in progress ends now, writing what sample.sh writes.
        if ('usabanner-sample.service' -in $global:UsaDeployUnits.Running) {
            Write-TestFile $global:UsaDeployRoot 'var/lib/usabanner/samples.tsv' "1`tcpu`t5`n"
        }
        Get-HostState $global:UsaDeployRoot | Should -Be $before
    }

    It 'leaves no failed unit behind when it stops a sample part way' {
        # The lab (Ubuntu 24.04.5, 2026-10-23): the sample Remove-UsaBanner stopped ended "Failed with result
        # 'signal'", and with its unit file gone it stayed in systemctl's failed list.
        $null = Deploy-UsaBanner -Company Contoso
        $lines = @(Remove-UsaBanner)
        $global:UsaDeployUnits.Failed | Should -BeNullOrEmpty
        $lines | Should -Contain 'cleared the failed state of usabanner-sample.service: a run stopped part way, or one that failed, ends so'
    }

    It 'stops and deletes the Group Policy runner''s publish watcher where the runner wrote one' {
        $root = $global:UsaDeployRoot
        $null = Deploy-UsaBanner -Company Contoso
        # As linux/adsys-startup.sh writes them, the path unit enabled.
        Write-TestFile $root 'etc/systemd/system/usabanner-publish.path' "[Path]`nPathChanged=/var/cache/adsys/sysvol/assets/GPT.INI`nUnit=usabanner-publish.service`n"
        Write-TestFile $root 'etc/systemd/system/usabanner-publish.service' "[Service]`nType=oneshot`n"
        $global:UsaDeployUnits.Enabled += 'usabanner-publish.path'
        $global:UsaDeployCalls.Clear()
        $lines = @(Remove-UsaBanner)
        Get-Calls -Changes | Should -Contain 'systemctl disable --now usabanner-publish.path'
        Get-Calls -Changes | Should -Contain 'systemctl stop usabanner-publish.service'
        foreach ($unit in 'usabanner-publish.path', 'usabanner-publish.service') { Join-Path $root "etc/systemd/system/$unit" | Should -Not -Exist }
        $lines | Should -Contain 'stopped usabanner-publish.path'
        $lines | Should -Contain 'deleted /etc/systemd/system/usabanner-publish.path: a unit of the Group Policy publish watcher'
    }

    It 'clears no failed state where no run was stopped' {
        $null = Deploy-UsaBanner -Company Contoso
        # The first sample has ended.
        $global:UsaDeployUnits.Running = @()
        $global:UsaDeployCalls.Clear()
        $null = Remove-UsaBanner
        @(Get-Calls -Changes) | Should -Not -Contain 'systemctl reset-failed usabanner-sample.service'
        @(Get-Calls) | Should -Contain 'systemctl is-failed usabanner-sample.service'
    }

    It 'turns back on only what the deploy turned off' {
        $root = $global:UsaDeployRoot
        [System.IO.File]::SetUnixFileMode((Join-Path $root 'etc/update-motd.d/10-help-text'), [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead')
        $null = Deploy-UsaBanner -Company Contoso
        $null = Remove-UsaBanner
        Get-Mode $root 'etc/update-motd.d/10-help-text' | Should -Be '644'
        Get-Mode $root 'etc/update-motd.d/00-header' | Should -Be '755'
    }

    It 'changes nothing under -WhatIf' {
        $null = Deploy-UsaBanner -Company Contoso
        $before = Get-HostState $global:UsaDeployRoot
        $global:UsaDeployCalls.Clear()
        $lines = @(Remove-UsaBanner -WhatIf)
        $lines | Should -BeNullOrEmpty
        Get-HostState $global:UsaDeployRoot | Should -Be $before
        Get-Calls -Changes | Should -BeNullOrEmpty
    }

    It 'does nothing, and says nothing, on a host without the banner' {
        $before = Get-HostState $global:UsaDeployRoot
        @(Remove-UsaBanner) | Should -BeNullOrEmpty
        Get-HostState $global:UsaDeployRoot | Should -Be $before
        Get-Calls | Should -BeNullOrEmpty
    }

    It 'deletes whole only the banner''s own folders' {
        { InModuleScope UsaBanner { Remove-UsaBannerHostFolder -Root '/nonexistent' -Path '/etc' -What 'a test' } } | Should -Throw '*/etc is not one of the banner''s own folders*'
    }
}

Describe 'the scripts a deploy installs' -Skip:$IsWindows {
    BeforeAll {
        $script:Redraw = Join-Path $moduleRoot 'linux' 'redraw.sh'
        $script:Bin = Join-Path $TestDrive 'bin'
        $null = New-Item -ItemType Directory -Path $Bin -Force
        # pwsh stood in for: it logs what it was asked to run.
        [System.IO.File]::WriteAllText((Join-Path $Bin 'pwsh'), "#!/bin/sh`nprintf '%s\n' `"`$@`" >`"`$STUB_LOG`"`n")
        & chmod 755 (Join-Path $Bin 'pwsh')

        function Invoke-Redraw {
            # In:  a host folder, and the facts records to stand in for facts.sh
            # Out: what the stand-in pwsh was asked to run; nothing when it was not run
            param([string]$Root, [string[]]$Records)
            # Not $records: PowerShell's names ignore case, and that one is the parameter.
            $recordFile = Join-Path $TestDrive 'records.tsv'
            [System.IO.File]::WriteAllText($recordFile, ($Records -join "`n") + "`n")
            $log = Join-Path $TestDrive 'pwsh.log'
            if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log }
            $null = & env "PATH=$Bin`:$env:PATH" "STUB_LOG=$log" "USABANNER_ROOT=$Root" sh $Redraw $recordFile
            if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log) }
        }

        function New-DrawnHost {
            # In:  the name and address the banners were drawn with, and the
            #      AD Description cached then (none by default)
            # Out: a host folder with a configuration, and the drawn record that matches it
            param([string]$Name = 'h-vsl-web1.ad.example', [string]$Ip = '10.20.40.80', [string]$Description)
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            Write-TestFile $root 'etc/usabanner/usabanner.json' "{`"version`":1,`"company`":`"Contoso`"}`n"
            $sum = (@(& sha256sum (Join-Path $root 'etc/usabanner/usabanner.json')) -split ' ')[0]
            $adSum = ''
            if ($Description) {
                Write-TestFile $root 'var/lib/usabanner/ad-description' "$Description`n"
                $adSum = (@(& sha256sum (Join-Path $root 'var/lib/usabanner/ad-description')) -split ' ')[0]
            }
            Write-TestFile $root 'var/lib/usabanner/drawn' "$Name`t$Ip`t$sum`t$adSum`n"
            $root
        }
    }

    It '<Name> parses under sh -n' -ForEach @(@{ Name = '05-usabanner' }, @{ Name = 'redraw.sh' }) {
        $out = & sh -n (Join-Path $moduleRoot 'linux' $Name) 2>&1 | Out-String
        "$out`nexit=$LASTEXITCODE" | Should -Match 'exit=0$'
    }

    It 'redraw.sh does nothing while the name, address and configuration are the ones drawn' {
        Invoke-Redraw (New-DrawnHost) @("name`th-vsl-web1.ad.example", "ip`t10.20.40.80", "os`tUbuntu") | Should -BeNullOrEmpty
    }

    It 'redraw.sh has the module draw the banners again when <Case>' -ForEach @(
        @{ Case = 'the host is renamed'; Records = @("name`tcw-vsl-web2.ad.example", "ip`t10.20.40.80") }
        @{ Case = 'its address moves'; Records = @("name`th-vsl-web1.ad.example", "ip`t10.20.40.81") }
    ) {
        Invoke-Redraw (New-DrawnHost) $Records | Should -Be @('-NoProfile', '-NonInteractive', '-Command', '& (Import-Module UsaBanner -PassThru) { Update-UsaBannerDrawing }')
    }

    It 'redraw.sh has the module draw the banners again when the configuration is edited' {
        $root = New-DrawnHost
        Write-TestFile $root 'etc/usabanner/usabanner.json' "{`"version`":1,`"company`":`"Contoso LLC`"}`n"
        Invoke-Redraw $root @("name`th-vsl-web1.ad.example", "ip`t10.20.40.80") | Should -Not -BeNullOrEmpty
    }

    It 'redraw.sh does nothing while the cached AD Description is the one drawn' {
        Invoke-Redraw (New-DrawnHost -Description 'PROD : Web front end') @("name`th-vsl-web1.ad.example", "ip`t10.20.40.80") | Should -BeNullOrEmpty
    }

    It 'redraw.sh has the module draw the banners again when the cached AD Description <Case>' -ForEach @(
        @{ Case = 'changes'; Before = 'PROD : Web front end'; After = 'LAB : Web front end' }
        @{ Case = 'is first cached'; Before = ''; After = 'PROD : Web front end' }
        @{ Case = 'is gone'; Before = 'PROD : Web front end'; After = $null }
    ) {
        $root = New-DrawnHost -Description $Before
        $cache = Join-Path $root 'var/lib/usabanner/ad-description'
        if ($null -eq $After) { Remove-Item -LiteralPath $cache }
        else { Write-TestFile $root 'var/lib/usabanner/ad-description' "$After`n" }
        Invoke-Redraw $root @("name`th-vsl-web1.ad.example", "ip`t10.20.40.80") | Should -Be @('-NoProfile', '-NonInteractive', '-Command', '& (Import-Module UsaBanner -PassThru) { Update-UsaBannerDrawing }')
    }

    It 'redraw.sh does nothing on a host whose banners were never drawn' {
        $root = Join-Path $TestDrive 'never'
        $null = New-Item -ItemType Directory -Path $root -Force
        Invoke-Redraw $root @("name`th-vsl-web1.ad.example") | Should -BeNullOrEmpty
    }
}
