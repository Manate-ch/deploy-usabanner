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
    Remove-Variable -Name UsaWinRoot, UsaWinCalls, UsaWinAnswers, UsaWinNotice, UsaWinShell, UsaWinTasks, UsaWinAcl -Scope Global -ErrorAction SilentlyContinue
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

    It 'gives UsagiTools the banner''s ACL when the deploy made it, on the folder alone, and once' {
        $parent = Join-Path $Root 'ProgramData/UsagiTools'
        $lines = @(Deploy-UsaBanner -Company Contoso)
        $global:UsaWinCalls | Should -Contain "icacls.exe $parent /setowner *S-1-5-32-544 /Q"
        $global:UsaWinCalls | Should -Contain "icacls.exe $parent /inheritance:r /grant:r *S-1-5-18:(OI)(CI)F *S-1-5-32-544:(OI)(CI)F *S-1-5-32-545:(OI)(CI)RX /Q"
        $lines | Should -Contain "set the ACL of ${parent}: Administrators and SYSTEM may change it, Users read it"
        $global:UsaWinCalls.Clear()
        $again = @(Deploy-UsaBanner -Company Contoso)
        @($global:UsaWinCalls | Where-Object { $_ -like "icacls.exe $parent *" }) | Should -BeNullOrEmpty
        $again | Should -Not -Contain "set the ACL of ${parent}: Administrators and SYSTEM may change it, Users read it"
    }

    It 'leaves the ACL of a UsagiTools it did not make as it is' {
        $parent = Join-Path $Root 'ProgramData/UsagiTools'
        $null = New-Item -ItemType Directory -Path $parent -Force
        $null = Deploy-UsaBanner -Company Contoso
        @($global:UsaWinCalls | Where-Object { $_ -like "icacls.exe $parent *" }) | Should -BeNullOrEmpty
        Join-Path $Data 'usabanner.json' | Should -Exist
    }

    It 'refuses a UsagiTools someone else could change, and changes nothing: <Case>' -ForEach @(
        @{ Case = 'a user made it, so owns it'; Owner = 'S-1-5-21-1-2-3-1104'; Extra = $null; Why = '*UsagiTools, the folder the banner''s own folder is in, is not safe*it is owned by CONTOSO\eve*' }
        @{ Case = 'a user may delete what is in it'; Owner = 'S-1-5-32-544'; Why = '*CONTOSO\eve may delete or rename what is in it*'
            Extra = @{ Sid = 'S-1-5-21-1-2-3-1104'; Name = 'CONTOSO\eve'; Allow = $true; Rights = 0x1301BF; InheritOnly = $false } }
        @{ Case = 'Everyone has full control'; Owner = 'S-1-5-32-544'; Why = '*Everyone may delete or rename what is in it*'
            Extra = @{ Sid = 'S-1-1-0'; Name = 'Everyone'; Allow = $true; Rights = 0x1F01FF; InheritOnly = $false } }
    ) {
        $parent = Join-Path $Root 'ProgramData/UsagiTools'
        $null = New-Item -ItemType Directory -Path $parent -Force
        $global:UsaWinSecurity[$parent] = @{
            Owner     = $Owner
            OwnerName = $(if ($Owner -eq 'S-1-5-32-544') { 'BUILTIN\Administrators' } else { 'CONTOSO\eve' })
            Rules     = @(@{ Sid = 'S-1-5-18'; Name = 'NT AUTHORITY\SYSTEM'; Allow = $true; Rights = 0x1F01FF; InheritOnly = $false }) + @(if ($Extra) { $Extra })
        }
        $before = @(Get-WindowsHostState $Root)
        { Deploy-UsaBanner -Company Contoso } | Should -Throw $Why
        @(Get-WindowsHostState $Root) | Should -Be $before
        @($global:UsaWinCalls) | Should -BeNullOrEmpty
    }

    It 'refuses a link where the banner''s folders are, and changes nothing: <Case>' -ForEach @(
        @{ Case = 'UsagiTools is a link'; Link = 'ProgramData/UsagiTools'; Why = '*UsagiTools, the folder the banner''s own folder is in, is not safe*it is a link*' }
        @{ Case = 'the banner''s folder is a link'; Link = 'ProgramData/UsagiTools/Banner'; Why = '*Banner, the banner''s own folder, is not safe*it is a link*' }
        @{ Case = 'the banner''s folder holds a link'; Link = 'ProgramData/UsagiTools/Banner/deep/x'; Why = '*Banner, the banner''s own folder, is not safe*it holds a link, which icacls /T would go through*deep/x*' }
    ) {
        # Where a link would send the deploy, as SYSTEM: a folder of the host's own that must stay as it is.
        $target = Join-Path $Root 'Windows/System32/config'
        $null = New-Item -ItemType Directory -Path $target -Force
        [System.IO.File]::WriteAllText((Join-Path $target 'SAM'), 'the host''s own')
        $at = Join-Path $Root $Link
        $null = New-Item -ItemType Directory -Path (Split-Path $at) -Force
        $null = New-Item -ItemType SymbolicLink -Path $at -Target $target
        $before = @(Get-WindowsHostState $Root)
        { Deploy-UsaBanner -Company Contoso } | Should -Throw $Why
        @(Get-WindowsHostState $Root) | Should -Be $before
        @($global:UsaWinCalls) | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $target -Force | ForEach-Object { $_.Name }) | Should -Be @('SAM')
    }

    It 'has the step that runs icacls /T refuse a link under the banner''s folder on its own' {
        # A link could appear after the deploy's first check: the step that sets the ACL checks again.
        $null = New-Item -ItemType Directory -Path (Join-Path $Data 'inner') -Force
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $Data 'inner/x') -Target (Join-Path $Root 'Windows')
        { InModuleScope UsaBanner -Parameters @{ Path = $Data } { param($Path) Set-UsaBannerDataFolder -Path $Path -Created ([System.Collections.Generic.List[string]]::new()) } } |
            Should -Throw '*it holds a link, which icacls /T would go through*inner/x*'
        @($global:UsaWinCalls) | Should -BeNullOrEmpty
    }

    It 'has Remove-UsaBanner refuse a UsagiTools a user owns, before it reads the record or deletes anything' {
        $null = Deploy-UsaBanner -Company Contoso
        $parent = Join-Path $Root 'ProgramData/UsagiTools'
        $global:UsaWinSecurity[$parent] = @{ Owner = 'S-1-5-21-1-2-3-1104'; OwnerName = 'CONTOSO\eve'; Rules = @() }
        $global:UsaWinCalls.Clear()
        { Remove-UsaBanner } | Should -Throw '*it is owned by CONTOSO\eve*'
        Join-Path $Data 'deploy.json' | Should -Exist
        $global:UsaWinTasks.Keys | Should -Contain 'UsaBanner sample'
        @($global:UsaWinCalls) | Should -BeNullOrEmpty
    }

    It 'deletes the copy an earlier deploy recorded, of another version, and leaves one no deploy recorded' {
        # The lab (2026-10-23): a deploy of another version left the earlier copy, so Import-Module loaded the
        # newer of the two and Remove-UsaBanner, which reads the record, never took the older.
        $null = Deploy-UsaBanner -Company Contoso
        $modules = Join-Path $Root 'ProgramFiles/WindowsPowerShell/Modules/UsaBanner'
        foreach ($old in '0.0.9', '0.0.5') {
            $null = New-Item -ItemType Directory -Path (Join-Path $modules $old) -Force
            [System.IO.File]::WriteAllText((Join-Path $modules "$old/UsaBanner.psd1"), "@{ ModuleVersion = '$old' }`n")
        }
        $recordPath = Join-Path $Data 'deploy.json'
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json -AsHashtable
        $record['module'] = Join-Path $modules '0.0.9'
        [System.IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 8))
        $lines = @(Deploy-UsaBanner -Company Contoso)
        $lines | Should -Contain "deleted $(Join-Path $modules '0.0.9') and the 1 file(s) in it: UsaBanner 0.0.9, the copy an earlier deploy installed"
        Join-Path $modules '0.0.9' | Should -Not -Exist
        Join-Path $modules '0.0.5' | Should -Exist
        $version = (Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'UsaBanner.psd1')).ModuleVersion
        (Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json -AsHashtable)['module'] | Should -BeExactly ([System.IO.Path]::Combine((Join-Path $Root 'ProgramFiles/WindowsPowerShell/Modules'), 'UsaBanner', $version))
    }

    It 'never asks to delete the copy it installs, recorded with the other separator by a deploy before 0.1.1' {
        # On Linux a path with \ is another path, so only a stand-in for the remover shows it is not asked.
        $null = Deploy-UsaBanner -Company Contoso
        $recordPath = Join-Path $Data 'deploy.json'
        $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Json -AsHashtable
        $installed = [string]$record['module']
        $record['module'] = $installed.Replace('/', '\')
        [System.IO.File]::WriteAllText($recordPath, ($record | ConvertTo-Json -Depth 8))
        Mock -ModuleName UsaBanner Remove-UsaBannerWindowsFolder { }
        $null = Deploy-UsaBanner -Company Contoso
        Should -Invoke Remove-UsaBannerWindowsFolder -ModuleName UsaBanner -Times 0 -Exactly
        $installed | Should -Exist
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

    It 'deletes the copy of sshd_config it made once sshd -t passes' {
        # The move-off and Remove-UsaBanner delete theirs; the deploy kept its own, and a test host
        # (2026-10-27) still held it.
        $null = Deploy-UsaBanner -Company Contoso
        [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config')) | Should -Match ([regex]::Escape('Banner __PROGRAMDATA__/UsagiTools/Banner/sshd-banner.txt'))
        Join-Path $Root 'ProgramData/ssh/sshd_config.usabanner-bak' | Should -Not -Exist
    }

    It 'keeps the copy of sshd_config beside it when sshd -t refuses, as the file was before the deploy' {
        Use-WindowsHost $Root @{ 'C:\Windows\System32\OpenSSH\sshd.exe -t' = @{ ExitCode = 1; Output = @('Bad configuration option') } }
        $null = Deploy-UsaBanner -Company Contoso -WarningAction SilentlyContinue
        [System.IO.File]::ReadAllText((Join-Path $Root 'ProgramData/ssh/sshd_config.usabanner-bak')) | Should -BeExactly $StockSshd
    }

    It 'copies again a file of the module''s copy that carries the internet mark, and says so' {
        # A test host, 2026-10-27: a copy made from a downloaded zip kept its mark on every file, a
        # deploy from the unblocked zip found each file the same and copied none, and the periodic
        # job, as SYSTEM, could not import the module.
        $null = Deploy-UsaBanner -Company Contoso
        $version = (Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'UsaBanner.psd1')).ModuleVersion
        $copy = Join-Path $Root "ProgramFiles/WindowsPowerShell/Modules/UsaBanner/$version"
        Set-WindowsMark (Join-Path $copy 'UsaBanner.psd1'), (Join-Path $copy 'UsaBanner.Format.ps1xml')
        @(Deploy-UsaBanner -Company Contoso) | Should -Be @("installed the module UsaBanner $version for every user: $copy (2 file(s) copied, 0 removed; 2 had the internet mark, which the copies do not)")
        @(Deploy-UsaBanner -Company Contoso) | Should -BeNullOrEmpty
    }

    It 'leaves a logon notice someone else set, and says so' {
        $global:UsaWinNotice = @{ Caption = 'NOTICE'; Text = 'Contoso policy applies.'; Exists = $true }
        $lines = @(Deploy-UsaBanner -Company Contoso)
        $global:UsaWinNotice.Caption | Should -BeExactly 'NOTICE'
        $lines | Should -Contain 'left the logon notice, the text before a console or RDP sign-in, as it is: it holds someone else''s text, set by hand or by a Group Policy'
    }

    It 'rewrites its own logon notice when the legal text changes' {
        $null = Deploy-UsaBanner -Company Contoso
        $null = Deploy-UsaBanner -Company Contoso -Legal L5
        $global:UsaWinNotice.Caption | Should -BeExactly 'ATTENTION'
    }

    It 'sets pwsh as sshd''s default shell where none is set, and Remove-UsaBanner takes it away again' {
        $global:UsaWinShell = ''
        $before = Get-WindowsHostState $Root
        $lines = @(Deploy-UsaBanner -Company Contoso)
        $lines | Should -Contain "set OpenSSH's default shell to C:\Program Files\PowerShell\7\pwsh.exe: sshd started cmd.exe at a login, whose banner after login never showed"
        $global:UsaWinShell | Should -BeExactly 'C:\Program Files\PowerShell\7\pwsh.exe'
        $record = Get-Content -LiteralPath (Join-Path $Data 'deploy.json') -Raw | ConvertFrom-Json -AsHashtable
        '{0} | {1}' -f $record.shell.path, $record.shell.before | Should -BeExactly 'C:\Program Files\PowerShell\7\pwsh.exe | '
        $lines = @(Remove-UsaBanner)
        $lines | Should -Contain 'put back OpenSSH''s default shell as it was before the deploy: none set, so sshd starts cmd.exe'
        $global:UsaWinCalls | Should -Contain 'default shell removed'
        Get-WindowsHostState $Root | Should -Be $before
    }

    It 'puts back the program it replaced, as the first deploy found it, after a second deploy' {
        $global:UsaWinShell = 'C:\Program Files\Git\bin\bash.exe'
        $null = Deploy-UsaBanner -Company Contoso
        $global:UsaWinShell | Should -BeExactly 'C:\Program Files\PowerShell\7\pwsh.exe'
        # Someone takes the value away; the next deploy sets pwsh again and keeps what the first one found.
        $global:UsaWinShell = ''
        $null = Deploy-UsaBanner -Company Contoso
        $global:UsaWinShell | Should -BeExactly 'C:\Program Files\PowerShell\7\pwsh.exe'
        @(Remove-UsaBanner) | Should -Contain 'put back OpenSSH''s default shell as it was before the deploy: C:\Program Files\Git\bin\bash.exe'
        $global:UsaWinShell | Should -BeExactly 'C:\Program Files\Git\bin\bash.exe'
    }

    It 'keeps a PowerShell already set as sshd''s default shell, and has nothing to put back' {
        $global:UsaWinShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        $null = Deploy-UsaBanner -Company Contoso
        $null = Remove-UsaBanner
        $global:UsaWinShell | Should -BeExactly 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        @($global:UsaWinCalls | Where-Object { $_ -like 'default shell *' }) | Should -BeNullOrEmpty
    }

    It 'sets Windows PowerShell as sshd''s default shell where PowerShell 7 is missing' {
        Mock -ModuleName UsaBanner Find-UsaBannerPwsh { }
        $global:UsaWinShell = ''
        $null = Deploy-UsaBanner -Company Contoso
        $global:UsaWinShell | Should -BeExactly ([System.IO.Path]::Combine("$Root/Windows", 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'))
    }

    It 'leaves a default shell changed since the deploy when the banner is removed' {
        $global:UsaWinShell = ''
        $null = Deploy-UsaBanner -Company Contoso
        $global:UsaWinShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        @(Remove-UsaBanner | Where-Object { $_ -like '*default shell*' }) | Should -BeNullOrEmpty
        $global:UsaWinShell | Should -BeExactly 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    It 'changes no default shell under -WhatIf' {
        $global:UsaWinShell = ''
        $before = Get-WindowsHostState $Root
        @(Deploy-UsaBanner -Company Contoso -WhatIf) | Should -BeNullOrEmpty
        Get-WindowsHostState $Root | Should -Be $before
        $global:UsaWinCalls | Should -BeNullOrEmpty
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

    It 'deletes the task folder \UsagiTools\ once its last task is gone, and keeps it while another tool''s task is in it (a lab host, 2026-10-28)' {
        $null = Deploy-UsaBanner -Company Contoso
        Join-Path $Root 'Windows/System32/Tasks/UsagiTools/UsaBanner sample' | Should -Exist
        $lines = @(Remove-UsaBanner)
        $lines | Should -Contain 'deleted the empty task folder \UsagiTools\'
        Join-Path $Root 'Windows/System32/Tasks/UsagiTools' | Should -Not -Exist

        $null = Deploy-UsaBanner -Company Contoso
        [System.IO.File]::WriteAllText((Join-Path $Root 'Windows/System32/Tasks/UsagiTools/Contoso check'), "<Task />`r`n")
        $global:UsaWinCalls.Clear()
        $lines = @(Remove-UsaBanner)
        $lines | Should -Not -Contain 'deleted the empty task folder \UsagiTools\'
        Join-Path $Root 'Windows/System32/Tasks/UsagiTools/Contoso check' | Should -Exist
        $global:UsaWinCalls | Should -Not -Contain 'task folder deleted: \UsagiTools\'
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

Describe 'who could swap the banner''s folders' {
    BeforeAll {
        function New-Rule {
            # In:  a SID, a name, the rights as Windows keeps them, and -Deny or -InheritOnly
            # Out: an ACL entry as Get-UsaBannerFolderSecurity gives it
            param([string]$Sid, [string]$Name, [int]$Rights, [switch]$Deny, [switch]$InheritOnly)
            @{ Sid = $Sid; Name = $Name; Allow = -not $Deny; Rights = $Rights; InheritOnly = [bool]$InheritOnly }
        }
        $script:System = New-Rule 'S-1-5-18' 'NT AUTHORITY\SYSTEM' 0x1F01FF
        $script:Admins = New-Rule 'S-1-5-32-544' 'BUILTIN\Administrators' 0x1F01FF
    }

    It 'finds no one in: <Case>' -ForEach @(
        @{ Case = 'the banner''s own ACL'; Owner = 'S-1-5-32-544'; Rules = @(@{ Sid = 'S-1-5-32-545'; Name = 'BUILTIN\Users'; Allow = $true; Rights = 0x1200A9; InheritOnly = $false }) }
        @{ Case = 'what ProgramData passes down: Users may add, not delete; CREATOR OWNER inherit-only'; Owner = 'S-1-5-32-544'; Rules = @(
                @{ Sid = 'S-1-5-32-545'; Name = 'BUILTIN\Users'; Allow = $true; Rights = 0x116; InheritOnly = $false }
                @{ Sid = 'S-1-3-0'; Name = 'CREATOR OWNER'; Allow = $true; Rights = 0x10000000; InheritOnly = $true }) }
        @{ Case = 'owned by SYSTEM'; Owner = 'S-1-5-18'; Rules = @() }
        @{ Case = 'owned by TrustedInstaller'; Owner = 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'; Rules = @() }
        @{ Case = 'a deny entry, which is not counted on either way'; Owner = 'S-1-5-32-544'; Rules = @(@{ Sid = 'S-1-1-0'; Name = 'Everyone'; Allow = $false; Rights = 0x1F01FF; InheritOnly = $false }) }
    ) {
        $security = @{ Owner = $Owner; OwnerName = 'the owner'; Rules = @($System, $Admins) + @($Rules) }
        @(InModuleScope UsaBanner -Parameters @{ Security = $security } { param($Security) Test-UsaBannerFolderRisk -Security $Security }) | Should -BeNullOrEmpty
    }

    It 'names who could, and how: <Case>' -ForEach @(
        @{ Case = 'a user who owns it'; Owner = 'S-1-5-21-1-2-3-1104'; Rules = @(); Expected = @('it is owned by CONTOSO\eve') }
        @{ Case = 'DELETE'; Owner = 'S-1-5-32-544'; Rules = @(@{ Sid = 'S-1-5-21-1-2-3-1104'; Name = 'CONTOSO\eve'; Allow = $true; Rights = 0x10000; InheritOnly = $false }); Expected = @('CONTOSO\eve may delete or rename what is in it, or change who may') }
        @{ Case = 'FILE_DELETE_CHILD'; Owner = 'S-1-5-32-544'; Rules = @(@{ Sid = 'S-1-5-21-1-2-3-1104'; Name = 'CONTOSO\eve'; Allow = $true; Rights = 0x40; InheritOnly = $false }); Expected = @('CONTOSO\eve may delete or rename what is in it, or change who may') }
        @{ Case = 'WRITE_DAC'; Owner = 'S-1-5-32-544'; Rules = @(@{ Sid = 'S-1-5-32-545'; Name = 'BUILTIN\Users'; Allow = $true; Rights = 0x40000; InheritOnly = $false }); Expected = @('BUILTIN\Users may delete or rename what is in it, or change who may') }
        @{ Case = 'WRITE_OWNER'; Owner = 'S-1-5-32-544'; Rules = @(@{ Sid = 'S-1-5-32-545'; Name = 'BUILTIN\Users'; Allow = $true; Rights = 0x80000; InheritOnly = $false }); Expected = @('BUILTIN\Users may delete or rename what is in it, or change who may') }
        @{ Case = 'GENERIC_ALL on the folder itself'; Owner = 'S-1-5-32-544'; Rules = @(@{ Sid = 'S-1-5-11'; Name = 'NT AUTHORITY\Authenticated Users'; Allow = $true; Rights = 0x10000000; InheritOnly = $false }); Expected = @('NT AUTHORITY\Authenticated Users may delete or rename what is in it, or change who may') }
        @{ Case = 'an owner and an entry both'; Owner = 'S-1-5-21-1-2-3-1104'; Rules = @(@{ Sid = 'S-1-1-0'; Name = 'Everyone'; Allow = $true; Rights = 0x1F01FF; InheritOnly = $false }); Expected = @('it is owned by CONTOSO\eve', 'Everyone may delete or rename what is in it, or change who may') }
    ) {
        $security = @{ Owner = $Owner; OwnerName = 'CONTOSO\eve'; Rules = @($System, $Admins) + @($Rules) }
        @(InModuleScope UsaBanner -Parameters @{ Security = $security } { param($Security) Test-UsaBannerFolderRisk -Security $Security }) | Should -Be $Expected
    }

    It 'finds each link under a folder, and does not go into one' {
        # No link leads back up: Pester's own clean-up of TestDrive follows links.
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $elsewhere = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $third = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'a/b'), (Join-Path $elsewhere 'c'), $third -Force
        [System.IO.File]::WriteAllText((Join-Path $third 'plain.txt'), '')
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $root 'a/b/to-elsewhere') -Target $elsewhere
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $root 'a/file-link') -Target (Join-Path $third 'plain.txt')
        # Inside the link's target: found only if the search went through the link.
        $null = New-Item -ItemType SymbolicLink -Path (Join-Path $elsewhere 'c/deeper') -Target $third
        $found = @(InModuleScope UsaBanner -Parameters @{ Path = $root } { param($Path) Find-UsaBannerFolderLink -Path $Path }) | Sort-Object
        $found | Should -Be @((Join-Path $root 'a/b/to-elsewhere'), (Join-Path $root 'a/file-link'))
        @(InModuleScope UsaBanner -Parameters @{ Path = (Join-Path $root 'a/b/to-elsewhere') } { param($Path) Find-UsaBannerFolderLink -Path $Path }) | Should -Be @((Join-Path $root 'a/b/to-elsewhere'))
        @(InModuleScope UsaBanner -Parameters @{ Path = $elsewhere } { param($Path) Find-UsaBannerFolderLink -Path $Path }) | Should -Be @((Join-Path $elsewhere 'c/deeper'))
    }
}

Describe 'the module''s copy for every user' {
    It 'copies each file''s contents, not the file: what else a file carries stays behind' {
        # A file copy carries more than the contents: on NTFS the file's streams, the internet mark of
        # a download among them, which kept the periodic job from importing the module on a test host
        # (2026-10-27); on Linux the file's mode. A module of one file with a mode of its own shows it.
        $source = Join-Path $TestDrive 'source/UsaBanner'
        $null = New-Item -ItemType Directory -Path $source -Force
        [System.IO.File]::WriteAllText((Join-Path $source 'UsaBanner.psd1'), "@{ ModuleVersion = '9.9.9'; FileList = @('UsaBanner.psd1', 'own.ps1') }")
        [System.IO.File]::WriteAllText((Join-Path $source 'own.ps1'), '1')
        [System.IO.File]::SetUnixFileMode((Join-Path $source 'own.ps1'), [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute')
        $modules = Join-Path $TestDrive 'modules'
        $lines = @(InModuleScope UsaBanner -Parameters @{ Source = $source; Modules = $modules } {
                param($Source, $Modules)
                $root, $manifest = $script:UsaBannerRoot, $script:UsaBannerManifest
                try {
                    $script:UsaBannerRoot = $Source
                    $script:UsaBannerManifest = Join-Path $Source 'UsaBanner.psd1'
                    Install-UsaBannerModuleCopy -Record @{} -Created $null -Modules $Modules -FileMode $null -FolderMode $null -Os windows
                }
                finally { $script:UsaBannerRoot, $script:UsaBannerManifest = $root, $manifest }
            })
        $lines | Should -Be @("installed the module UsaBanner 9.9.9 for every user: $modules/UsaBanner/9.9.9 (2 file(s) copied, 0 removed)")
        $copied = Join-Path $modules 'UsaBanner/9.9.9/own.ps1'
        [System.IO.File]::ReadAllText($copied) | Should -BeExactly '1'
        [System.IO.File]::GetUnixFileMode($copied) -band [System.IO.UnixFileMode]::UserExecute | Should -Be ([System.IO.UnixFileMode]::None)
    }

    It 'copies the files the manifest lists alone: another file in the module''s folder stays out of the copy, and goes from a copy that holds it (D32)' {
        # A production domain's publish (2026-10-28) took an admin's configuration file from the module's folder
        # to every host's copy.
        $source = Join-Path $TestDrive 'listed/UsaBanner'
        $null = New-Item -ItemType Directory -Path $source -Force
        [System.IO.File]::WriteAllText((Join-Path $source 'UsaBanner.psd1'), "@{ ModuleVersion = '9.9.8'; FileList = @('UsaBanner.psd1', 'own.ps1') }")
        [System.IO.File]::WriteAllText((Join-Path $source 'own.ps1'), '1')
        [System.IO.File]::WriteAllText((Join-Path $source 'usabanner-contoso.json'), '{}')
        $modules = Join-Path $TestDrive 'modules-listed'
        $null = New-Item -ItemType Directory -Path (Join-Path $modules 'UsaBanner/9.9.8') -Force
        [System.IO.File]::WriteAllText((Join-Path $modules 'UsaBanner/9.9.8/usabanner-contoso.json'), '{}')
        $lines = @(InModuleScope UsaBanner -Parameters @{ Source = $source; Modules = $modules } {
                param($Source, $Modules)
                $root, $manifest = $script:UsaBannerRoot, $script:UsaBannerManifest
                try {
                    $script:UsaBannerRoot = $Source
                    $script:UsaBannerManifest = Join-Path $Source 'UsaBanner.psd1'
                    Install-UsaBannerModuleCopy -Record @{} -Created $null -Modules $Modules -FileMode $null -FolderMode $null -Os windows
                }
                finally { $script:UsaBannerRoot, $script:UsaBannerManifest = $root, $manifest }
            })
        $lines | Should -Be @("installed the module UsaBanner 9.9.8 for every user: $modules/UsaBanner/9.9.8 (2 file(s) copied, 1 removed)")
        @(Get-ChildItem -LiteralPath (Join-Path $modules 'UsaBanner/9.9.8') -Name | Sort-Object) | Should -Be @('own.ps1', 'UsaBanner.psd1')
    }

    It 'finds no file with the internet mark off Windows, which has no stream to carry one' -Skip:$IsWindows {
        $folder = Join-Path $TestDrive 'plain'
        $null = New-Item -ItemType Directory -Path $folder -Force
        [System.IO.File]::WriteAllText((Join-Path $folder 'a.ps1'), '1')
        @(InModuleScope UsaBanner -Parameters @{ Folder = $folder } { param($Folder) Get-UsaBannerMarkedFile -Folder $Folder }) | Should -BeNullOrEmpty
    }
}
