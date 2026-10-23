# Deploy-UsaBanner and Remove-UsaBanner on Windows Server (UsaBanner/Private/WindowsDeploy.ps1),
# run on Linux: folders stand in for a host's ProgramData, Program Files and Windows folders,
# and the registry, Task Scheduler, icacls and sshd -t are answered from stores that keep what
# was written. The text the deploy writes (the profiles' block, sshd_config) is checked as text,
# and the block also runs in a real pwsh. What Windows itself does with each is the lab's to
# show.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $moduleRoot = Join-Path $repoRoot 'UsaBanner'
    Import-Module (Join-Path $moduleRoot 'UsaBanner.psd1') -Force
    $script:Pwsh = (Get-Process -Id $PID).Path
    . (Join-Path $PSScriptRoot 'FakeHosts.ps1')
}

AfterAll {
    Remove-Variable -Name UsaWinRoot, UsaWinCalls, UsaWinAnswers, UsaWinNotice, UsaWinTasks, UsaWinAcl -Scope Global -ErrorAction SilentlyContinue
    Remove-Module UsaBanner -ErrorAction SilentlyContinue
}

Describe 'Deploy-UsaBanner on Windows Server' {
    BeforeEach {
        $script:Root = New-WindowsHost
        Use-WindowsHost $Root
        $script:Data = Join-Path $Root 'ProgramData/UsagiTools/Banner'
    }

    It 'puts each piece in place: the module, the folder and its ACL, the configuration, the profiles, SSH, the logon notice and the task' {
        $null = Deploy-UsaBanner -Company Contoso -Environment PROD
        foreach ($file in 'usabanner.json', 'usabanner.psd1', 'sshd-banner.txt', 'deploy.json') { Join-Path $Data $file | Should -Exist }
        $global:UsaWinCalls | Should -Contain "icacls.exe $Data /setowner *S-1-5-32-544 /T /Q"
        $global:UsaWinCalls | Should -Contain "icacls.exe $Data /inheritance:r /grant:r *S-1-5-18:(OI)(CI)F *S-1-5-32-544:(OI)(CI)F *S-1-5-32-545:(OI)(CI)RX /Q"
        $global:UsaWinCalls | Should -Not -Contain 'ACL SET AFTER A FILE'
        foreach ($profileFile in 'Windows/System32/WindowsPowerShell/v1.0/profile.ps1', 'ProgramFiles/PowerShell/7/profile.ps1') {
            [System.IO.File]::ReadAllText((Join-Path $Root $profileFile)) | Should -Match ([regex]::Escape("Show-UsaBanner -Path '$Data/usabanner.psd1'"))
        }
        $sshd = @([System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config')) -split "`r`n")
        [array]::IndexOf($sshd, 'Banner __PROGRAMDATA__/UsagiTools/Banner/sshd-banner.txt') | Should -Be ([array]::IndexOf($sshd, 'Match Group administrators') - 2)
        $global:UsaWinCalls | Should -Contain 'C:\Windows\System32\OpenSSH\sshd.exe -t'
        $global:UsaWinNotice.Caption | Should -BeExactly 'WARNING'
        $global:UsaWinNotice.Text | Should -BeLike 'This system is for authorized use only.*'
        $global:UsaWinTasks['UsaBanner sample'].Execute | Should -BeExactly 'C:\Program Files\PowerShell\7\pwsh.exe'
        $global:UsaWinTasks['UsaBanner sample'].Arguments | Should -BeExactly '-NoProfile -NonInteractive -Command "& (Import-Module UsaBanner -PassThru) { Update-UsaBannerSample }"'
        $global:UsaWinCalls | Should -Contain 'task started: UsaBanner sample'
        # The update channel is off unless a flag turns it on: no update task.
        @($global:UsaWinTasks.Keys) | Should -Be @('UsaBanner sample')
        $version = (Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'UsaBanner.psd1')).ModuleVersion
        $copy = Join-Path $Root "ProgramFiles/WindowsPowerShell/Modules/UsaBanner/$version"
        $files = { param($Folder) @(Get-WindowsHostState $Folder | Where-Object { $_ -notmatch '^(notice: |task )' }) }
        (& $files $copy) | Should -Be (& $files $moduleRoot)
    }

    It 'lets a file already in its folder inherit the folder''s ACL, and gives it no ACE meant for a folder' {
        # The lab (Server 2022, 2026-10-23): a sample made the folder and a file in it before the deploy set the
        # ACL; with /T, icacls left the file an empty ACL, which no one could read, and said it succeeded.
        $null = New-Item -ItemType Directory -Path $Data -Force
        [System.IO.File]::WriteAllText((Join-Path $Data 'slow.tsv'), '')
        $null = Deploy-UsaBanner -Company Contoso
        $acl = @($global:UsaWinCalls | Where-Object { $_ -like 'icacls.exe *' })
        $acl | Should -Contain "icacls.exe $Data /inheritance:r /grant:r *S-1-5-18:(OI)(CI)F *S-1-5-32-544:(OI)(CI)F *S-1-5-32-545:(OI)(CI)RX /Q"
        $acl | Should -Contain "icacls.exe $([System.IO.Path]::Combine($Data, '*')) /reset /T /Q"
        @($acl | Where-Object { $_ -match '/grant' -and $_ -match ' /T ' }) | Should -BeNullOrEmpty
    }

    It 'writes the configuration as data that reads back as the same settings, and draws the same banner' {
        $null = Deploy-UsaBanner -Company Contoso -Environment LAB -Services sshd, W32Time -PreInit HostName
        $read = InModuleScope UsaBanner -Parameters @{ Data = $Data } {
            param($Data)
            # Import-PowerShellDataFile gives a Hashtable, whose key order .NET varies from one
            # process to the next: the settings compare with their keys sorted.
            function ConvertTo-Sorted {
                param($Value)
                if ($Value -is [System.Collections.IDictionary]) {
                    $sorted = [ordered]@{}
                    foreach ($key in @($Value.Keys | Sort-Object)) { $sorted[$key] = ConvertTo-Sorted $Value[$key] }
                    return $sorted
                }
                if ($Value -is [System.Collections.IList]) { return , @(foreach ($item in $Value) { ConvertTo-Sorted $item }) }
                $Value
            }
            $json = Read-UsaBannerConfig -Path "$Data/usabanner.json"
            $data = Read-UsaBannerConfig -Path "$Data/usabanner.psd1"
            $facts = @{ Name = 'BEVSW-APP1.ad.example'; Ip = '10.20.40.80'; Uptime = '3d 4h 5m'; Services = @{ Text = 'sshd, W32Time running'; Level = 'good' } }
            @{
                Json      = ConvertTo-Json -InputObject (ConvertTo-Sorted $json) -Depth 10
                Data      = ConvertTo-Json -InputObject (ConvertTo-Sorted $data) -Depth 10
                JsonDrawn = @(Get-UsaBannerPostLogon -Config $json -Os windows -Facts $facts -Mode truecolor) -join "`n"
                DataDrawn = @(Get-UsaBannerPostLogon -Config $data -Os windows -Facts $facts -Mode truecolor) -join "`n"
            }
        }
        $read.Data | Should -BeExactly $read.Json
        $read.DataDrawn | Should -BeExactly $read.JsonDrawn
        [System.IO.File]::ReadAllBytes("$Data/usabanner.psd1") | Where-Object { $_ -gt 126 } | Should -BeNullOrEmpty
    }

    It 'writes the SSH banner as the module draws it: plain ASCII, ending in a blank line' {
        $null = Deploy-UsaBanner -Company Contoso
        $expected = InModuleScope UsaBanner -Parameters @{ Data = $Data } {
            param($Data)
            (@(Get-UsaBannerPreLogon -Config (Read-UsaBannerConfig -Path "$Data/usabanner.json") -Os windows -Facts @{ HostName = 'x'; Ip = '' }) -join "`n") + "`n`n"
        }
        [System.IO.File]::ReadAllText("$Data/sshd-banner.txt") | Should -BeExactly $expected
    }

    It 'keeps what a profile held, its line ends and its encoding, and writes the block once however often it runs' {
        $profileFile = Join-Path $Root 'Windows/System32/WindowsPowerShell/v1.0/profile.ps1'
        $null = Deploy-UsaBanner -Company Contoso
        $null = Deploy-UsaBanner -Company Contoso -Environment LAB
        $bytes = [System.IO.File]::ReadAllBytes($profileFile)
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Count - 3)
        $text | Should -BeLike "# Contoso's own profile`r`nSet-Location C:\`r`n`r`n# >>> UsaBanner*"
        $text | Should -Not -Match "[^`r]`n"
        ([regex]::Matches($text, [regex]::Escape('# >>> UsaBanner'))).Count | Should -Be 1
    }

    It 'shows the banner from the block once a session, at an interactive SSH login only' -Skip:$IsWindows {
        # The block as a fresh profile holds it, dot-sourced twice as a session's profile is
        # loaded, into a session where Show-UsaBanner only says what it was asked.
        $profileFile = Join-Path $TestDrive 'profile.ps1'
        [System.IO.File]::WriteAllText($profileFile, (InModuleScope UsaBanner { Set-UsaBannerProfileText -Text '' -Block @(New-UsaBannerProfileBlock -DataFile 'C:\ProgramData\UsagiTools\Banner\usabanner.psd1') }))
        $profileText = @(
            'function Show-UsaBanner { param($Path) if ($env:SHOW_FAILS) { throw ''the art broke'' } "SHOWN $Path" }'
            ". '$profileFile'"
            ". '$profileFile'"
            '"AFTER"'
            ''
        ) -join "`n"
        # Fed on standard input, pwsh runs as an interactive session would, a line at a time,
        # and its own command line holds no -Command, as at a login. It writes a prompt and a
        # terminal escape before each line; the escapes are dropped. SSH_CONNECTION is cleared
        # first: this test may itself run under SSH.
        $run = {
            param([hashtable]$Variables)
            $assignments = @(foreach ($name in $Variables.Keys) { "$name=$($Variables[$name])" })
            @($profileText | & env -u SSH_CONNECTION -u USABANNER_SHOWN @assignments $Pwsh -NoProfile -NoLogo 2>&1 |
                    ForEach-Object { "$_" -replace "$([char]27)\[[0-9;?]*[A-Za-z]", '' })
        }
        $ssh = & $run @{ SSH_CONNECTION = '10.20.40.9 51234 10.20.40.80 22' }
        @($ssh | Where-Object { $_ -match '^SHOWN ' }) | Should -Be @('SHOWN C:\ProgramData\UsagiTools\Banner\usabanner.psd1')
        $ssh | Should -Contain 'AFTER'
        $console = & $run @{ TERM = 'xterm' }
        @($console | Where-Object { $_ -match '^SHOWN ' }) | Should -BeNullOrEmpty
        $failed = & $run @{ SSH_CONNECTION = '10.20.40.9 51234 10.20.40.80 22'; SHOW_FAILS = '1' }
        ($failed -join "`n") | Should -Match 'UsaBanner: the art broke'
        $failed | Should -Contain 'AFTER'
    }

    It 'writes a block Windows PowerShell 5.1 can read: its profile holds the block too' -Skip:(-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
        $file = Join-Path $TestDrive 'block51.ps1'
        [System.IO.File]::WriteAllText($file, (InModuleScope UsaBanner { @(New-UsaBannerProfileBlock -DataFile 'C:\ProgramData\UsagiTools\Banner\usabanner.psd1') -join "`r`n" }))
        $settings = @{ IncludeRules = @('PSUseCompatibleSyntax'); Rules = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } } }
        @(Invoke-ScriptAnalyzer -Path $file -Settings $settings | ForEach-Object { "line $($_.Line): $($_.Message)" }) | Should -BeNullOrEmpty
        # The same check finds PowerShell 7 syntax (else a pass proves nothing).
        [System.IO.File]::WriteAllText($file, '$a = $b ?? ''c''')
        @(Invoke-ScriptAnalyzer -Path $file -Settings $settings).Count | Should -BeGreaterThan 0
    }

    It 'turns off another Banner above the first Match, and leaves one inside a Match block, saying so' {
        $lines = @('Port 22', 'Banner C:\old\banner.txt', '', 'Match Group administrators', '  Banner C:\admins.txt', '')
        $result = InModuleScope UsaBanner -Parameters @{ Lines = $lines } { param($Lines) Set-UsaBannerSshdBannerLine -Lines $Lines }
        $result.Changed | Should -BeTrue
        $result.Lines | Should -Be @('Port 22', '# Turned off by Deploy-UsaBanner, which put its own Banner above: Banner C:\old\banner.txt', '', 'Banner __PROGRAMDATA__/UsagiTools/Banner/sshd-banner.txt', '', 'Match Group administrators', '  Banner C:\admins.txt', '')
        $result.Scoped | Should -Be @('Banner C:\admins.txt')
    }

    It 'gives sshd_config back to the byte when the line comes out again: <Case>' -ForEach @(
        @{ Case = 'Windows'' own file'; Lines = @($StockSshd -split "`r`n") }
        @{ Case = 'a file with another Banner'; Lines = @('Port 22', 'Banner C:\old\banner.txt', '', 'Match User backup', '  X11Forwarding no', '') }
        @{ Case = 'a file without a Match block'; Lines = @('Port 22', 'PasswordAuthentication no', '') }
        @{ Case = 'a file without a final newline'; Lines = @('Port 22') }
    ) {
        $back = InModuleScope UsaBanner -Parameters @{ Lines = $Lines } {
            param($Lines)
            $set = Set-UsaBannerSshdBannerLine -Lines $Lines
            (Remove-UsaBannerSshdBannerLine -Lines $set.Lines).Lines
        }
        ($back -join "`n") | Should -BeExactly ($Lines -join "`n")
    }

    It 'leaves sshd_config as it is when it has the banner''s line already' {
        $lines = @('Banner __PROGRAMDATA__/UsagiTools/Banner/sshd-banner.txt', '', 'Match Group administrators')
        (InModuleScope UsaBanner -Parameters @{ Lines = $lines } { param($Lines) Set-UsaBannerSshdBannerLine -Lines $Lines }).Changed | Should -BeFalse
    }

    It 'puts sshd_config back when sshd -t refuses it, and says so' {
        Use-WindowsHost $Root @{ 'C:\Windows\System32\OpenSSH\sshd.exe -t' = @{ ExitCode = 1; Output = @('Bad configuration option') } }
        $null = Deploy-UsaBanner -Company Contoso -WarningVariable warned -WarningAction SilentlyContinue
        [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config')) | Should -BeExactly $StockSshd
        "$warned" | Should -BeLike '*sshd -t refused sshd_config with the Banner line, so it is put back as it was*'
    }

    It 'leaves a logon notice someone else set, and says so' {
        $global:UsaWinNotice = @{ Caption = 'NOTICE'; Text = 'Contoso policy applies.'; Exists = $true }
        $lines = @(Deploy-UsaBanner -Company Contoso)
        $global:UsaWinNotice.Caption | Should -BeExactly 'NOTICE'
        $lines | Should -Contain 'left the logon notice as it is: it holds someone else''s text, set by hand or by a Group Policy'
    }

    It 'rewrites its own logon notice when the legal text changes' {
        $null = Deploy-UsaBanner -Company Contoso
        $null = Deploy-UsaBanner -Company Contoso -Legal L5
        $global:UsaWinNotice.Caption | Should -BeExactly 'ATTENTION'
    }

    It 'warns when sshd''s default shell is not a PowerShell, as no banner would show after login' {
        Mock -ModuleName UsaBanner Get-UsaBannerSshDefaultShell { '' }
        $null = Deploy-UsaBanner -Company Contoso -WarningVariable warned -WarningAction SilentlyContinue
        "$warned" | Should -BeLike '*sshd starts cmd.exe at a login, so no banner shows after an SSH login*'
    }

    It 'adds no SSH banner where OpenSSH''s server is not installed, says so, and still writes the profiles' {
        Mock -ModuleName UsaBanner Get-UsaBannerWindowsSshd { }
        $lines = @(Deploy-UsaBanner -Company Contoso)
        $lines | Should -Contain 'no SSH banner, and no banner after login: OpenSSH''s server is not installed here (deploy-usawinssh installs it); run Deploy-UsaBanner again once it is'
        [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config')) | Should -BeExactly $StockSshd
        Join-Path $Root 'ProgramFiles/PowerShell/7/profile.ps1' | Should -Exist
    }

    It 'changes nothing on a second run with the same flags' {
        $null = Deploy-UsaBanner -Company Contoso -Environment LAB
        $before = Get-WindowsHostState $Root
        $global:UsaWinCalls.Clear()
        @(Deploy-UsaBanner -Company Contoso -Environment LAB) | Should -BeNullOrEmpty
        Get-WindowsHostState $Root | Should -Be $before
        $global:UsaWinCalls | Should -BeNullOrEmpty
    }

    It 'changes nothing under -WhatIf' {
        $before = Get-WindowsHostState $Root
        @(Deploy-UsaBanner -Company Contoso -WhatIf) | Should -BeNullOrEmpty
        Get-WindowsHostState $Root | Should -Be $before
        $global:UsaWinCalls | Should -BeNullOrEmpty
    }

    It 'runs as an administrator only, and lets anyone look with -WhatIf' {
        Mock -ModuleName UsaBanner Test-UsaBannerPrivileged { $false }
        { Deploy-UsaBanner -Company Contoso } | Should -Throw '*runs in an elevated PowerShell*'
        { $null = Deploy-UsaBanner -Company Contoso -WhatIf } | Should -Not -Throw
    }

    It 'refuses a Windows older than Server 2022' {
        Mock -ModuleName UsaBanner Get-UsaBannerWindowsBuild { 17763 }
        { Deploy-UsaBanner -Company Contoso } | Should -Throw '*works on Windows Server 2022 and later*'
    }

    It 'refuses a host with the banner of this repository''s Install-ManatechBanner.ps1, naming what it found' {
        $null = New-Item -ItemType Directory -Path (Join-Path $Root 'ProgramData/Manatech')
        [System.IO.File]::WriteAllText((Join-Path $Root 'ProgramFiles/PowerShell/7/profile.ps1'), "# >>> Manatech banner (Install-ManatechBanner.ps1) >>>`r`n# <<< Manatech banner <<<`r`n")
        $before = Get-WindowsHostState $Root
        { Deploy-UsaBanner -Company Contoso } | Should -Throw "*this host has the banner of this repository's Install-ManatechBanner.ps1 (*ProgramData/Manatech, *PowerShell/7/profile.ps1)*"
        Get-WindowsHostState $Root | Should -Be $before
    }
}

Describe 'Remove-UsaBanner on Windows Server' {
    BeforeEach {
        $script:Root = New-WindowsHost
        Use-WindowsHost $Root
    }

    It 'leaves the host as it was before the deploy: files, profiles, sshd_config, the logon notice and the task' {
        $before = Get-WindowsHostState $Root
        $null = Deploy-UsaBanner -Company Contoso -Environment PROD
        $lines = @(Remove-UsaBanner)
        Get-WindowsHostState $Root | Should -Be $before
        $lines | Should -Contain 'unregistered the task \UsagiTools\UsaBanner sample'
        $lines | Should -Contain 'put back the logon notice as it was before the deploy'
    }

    It 'stops a sample still running before the banner''s folder goes, so it cannot write it again' {
        # The lab (Server 2022, 2026-10-23): a Remove-UsaBanner 9 s after a deploy, while the deploy's first
        # sample still ran, and the sample made the banner's folder again 4 s after it went.
        $before = Get-WindowsHostState $Root
        $null = Deploy-UsaBanner -Company Contoso -Environment PROD
        $null = Remove-UsaBanner
        # A run still in progress ends now, writing what Update-UsaBannerSample writes.
        if ($global:UsaWinRunning['UsaBanner sample']) {
            $null = New-Item -ItemType Directory -Path (Join-Path $Root 'ProgramData/UsagiTools/Banner') -Force
            [System.IO.File]::WriteAllText((Join-Path $Root 'ProgramData/UsagiTools/Banner/samples.tsv'), "1`tcpu`t5`n")
        }
        Get-WindowsHostState $Root | Should -Be $before
    }

    It 'leaves a logon notice someone else set after the deploy' {
        $null = Deploy-UsaBanner -Company Contoso
        $global:UsaWinNotice = @{ Caption = 'NOTICE'; Text = 'Contoso policy applies.'; Exists = $true }
        $null = Remove-UsaBanner
        $global:UsaWinNotice.Caption | Should -BeExactly 'NOTICE'
    }

    It 'changes nothing under -WhatIf' {
        $null = Deploy-UsaBanner -Company Contoso
        $before = Get-WindowsHostState $Root
        $global:UsaWinCalls.Clear()
        @(Remove-UsaBanner -WhatIf) | Should -BeNullOrEmpty
        Get-WindowsHostState $Root | Should -Be $before
        $global:UsaWinCalls | Should -BeNullOrEmpty
    }

    It 'takes the module''s copy whichever separators its path was recorded with, and refuses any other module' {
        # On Windows Server 2022 and 2025 (lab, 2026-10-23) a deploy recorded the copy as
        # C:\Program Files\WindowsPowerShell\Modules/UsaBanner/0.1.0, and Remove-UsaBanner refused it.
        InModuleScope UsaBanner {
            Mock Get-UsaBannerWindowsLayout { @{ Modules = 'C:\Program Files\WindowsPowerShell\Modules'; Data = 'C:\ProgramData\UsagiTools\Banner'; OldData = 'C:\ProgramData\Manatech' } }
            foreach ($path in 'C:\Program Files\WindowsPowerShell\Modules/UsaBanner/0.1.0', 'C:\Program Files\WindowsPowerShell\Modules\UsaBanner\0.1.0') {
                { Remove-UsaBannerWindowsFolder -Path $path -Allowed $path -What 'the module''s copy for every user' } | Should -Not -Throw
            }
            $other = 'C:\Program Files\WindowsPowerShell\Modules\UsaBannerOther\0.1.0'
            { Remove-UsaBannerWindowsFolder -Path $other -Allowed $other -What 'another module' } | Should -Throw '*is not one of the banner''s own folders*'
        }
    }
}
