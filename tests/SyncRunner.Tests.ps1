# Tests for UsaBanner/windows/Sync-UsaBanner.ps1, the script the UsaBanner Group Policy's scheduled
# task runs as SYSTEM from NETLOGON (docs/DECISIONS.md, D29), and for SyncDeploy.ps1 beside it, the
# deploy it reads when one is due. Each test runs a copy of them the way the
# task does, as a new process with -File, from a stand-in NETLOGON share: the module folder it sits in,
# holding the real Bootstrap\Handoff.ps1 and a stand-in module whose Deploy-UsaBanner has the real
# one's parameters and says what it was given, and the package beside it. SystemRoot, ProgramData
# and ProgramFiles are scratch folders; the banner's record, which the stand-in deploy does not write,
# a test puts in ProgramData itself where it needs one. The pwsh the script runs is the real one: PowerShell puts its own
# folder first on the PATH of the process it starts, so no stand-in can win the search of the PATH, and
# the stand-in module records the command line pwsh was started with instead. Two tests need a host
# without pwsh on its PATH (none, and one in Program Files): their copy of Handoff.ps1 looks for a
# name no PATH holds. The process that runs the script is PowerShell 7 here; what only Windows
# PowerShell 5.1 as SYSTEM on a Windows Server shows is for a lab, and the last Describe holds the
# file to the syntax 5.1 parses.

BeforeDiscovery {
    $hasAnalyzer = [bool](Get-Module -ListAvailable -Name PSScriptAnalyzer)
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:ModuleRoot = Join-Path $repoRoot 'UsaBanner'
    $script:RunnerSrc = Join-Path $ModuleRoot 'windows' 'Sync-UsaBanner.ps1'
    $script:DeployPartSrc = Join-Path $ModuleRoot 'windows' 'SyncDeploy.ps1'
    $script:HandoffSrc = Join-Path $ModuleRoot 'Bootstrap' 'Handoff.ps1'
}

Describe 'Sync-UsaBanner.ps1' -Skip:$IsWindows {
    BeforeAll {
        $script:Pwsh = (Get-Process -Id $PID).Path
        $script:EnvTool = (Get-Command -Name env -CommandType Application)[0].Source
        $script:MutexName = 'Global\UsaBanner-Sync'

        # The stand-in module's Deploy-UsaBanner takes the real one's parameters, with their checks
        # (a renamed -Path or -ReplaceOldBanner fails these tests), and says what it was given, and
        # how pwsh was started. What it prints comes from says.txt in its module folder, and what it
        # writes to standard error from stderr.txt; fails.txt makes it throw; exits.txt makes it end
        # pwsh with that exit code, without a word.
        Import-Module (Join-Path $ModuleRoot 'UsaBanner.psd1') -Force
        $meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Module UsaBanner -Name Deploy-UsaBanner))
        # Where the module writes the banner's record and finds the old banner, under ProgramData: the
        # script looks there without the module, which needs PowerShell 7, so these tests put things
        # where the module says, and a move in the module fails them.
        $savedProgramData = $env:ProgramData
        try {
            $env:ProgramData = 'PROGRAMDATA'
            $layout = & (Get-Module UsaBanner) { Get-UsaBannerWindowsLayout }
        }
        finally { $env:ProgramData = $savedProgramData }
        $script:RecordInProgramData = [System.IO.Path]::GetRelativePath('PROGRAMDATA', [System.IO.Path]::Combine($layout.Data, 'deploy.json'))
        $script:OldBannerInProgramData = @($layout.Old | ForEach-Object { [System.IO.Path]::GetRelativePath('PROGRAMDATA', $_) })
        $script:OldBannerInProgramData.Count | Should -Be 2 -Because 'the old banner leaves a folder and an SSH banner file'
        Remove-Module UsaBanner
        $script:StubModule = @(
            'function Deploy-UsaBanner {'
            [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($meta)
            "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($meta)))"
            '$base = $MyInvocation.MyCommand.Module.ModuleBase'
            '[System.Environment]::GetCommandLineArgs() | Set-Content -LiteralPath $env:STUB_ARGS'
            'Add-Content -LiteralPath $env:STUB_RECORD -Value "Path=$Path ReplaceOldBanner=$ReplaceOldBanner Module=$base"'
            '$says = Join-Path $base ''says.txt'''
            'if (Test-Path -LiteralPath $says) { Get-Content -LiteralPath $says }'
            '$stderr = Join-Path $base ''stderr.txt'''
            'if (Test-Path -LiteralPath $stderr) { [System.Console]::Error.WriteLine((Get-Content -LiteralPath $stderr -Raw).TrimEnd()) }'
            '$fails = Join-Path $base ''fails.txt'''
            'if (Test-Path -LiteralPath $fails) { throw (Get-Content -LiteralPath $fails -Raw).TrimEnd() }'
            '$exits = Join-Path $base ''exits.txt'''
            'if (Test-Path -LiteralPath $exits) { exit ([int](Get-Content -LiteralPath $exits -Raw)) }'
            '}'
        ) -join "`n"

        # A stand-in for the pwsh.exe the MSI puts in Program Files: it notes that it ran, then runs
        # the real pwsh with the same arguments.
        $script:StandInMsiPwsh = @(
            '#!/bin/sh'
            'echo ran >"$STUB_WRAPPED"'
            'exec "$STUB_REAL_PWSH" "$@"'
        ) -join "`n"

        function Write-StandIn {
            # In:  a path and the text of a program
            # Out: nothing; the file is there, executable, with its parent folders
            param([string]$Path, [string]$Text)
            $null = New-Item -ItemType File -Path $Path -Force
            $full = (Get-Item -LiteralPath $Path).FullName
            [System.IO.File]::WriteAllText($full, "$Text`n")
            [System.IO.File]::SetUnixFileMode($full, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute')
        }

        function New-SyncShare {
            # In:  -NoPathLookup for a host with no pwsh on its PATH: the share's Handoff.ps1 looks
            #      for a pwsh by a name that no PATH holds, and so finds one only in Program Files;
            #      the name of the folder that stands for NETLOGON, which by default holds a space
            #      and an apostrophe, since a path breaks a command string at either
            # Out: the share's parts: Runner (the script, in <Module>\windows), DeployPart (SyncDeploy.ps1
            #      beside it), Module, Package (the configuration file beside the module folder),
            #      SystemRoot, ProgramData, ProgramFiles, Log (where the script writes), Stamp (its
            #      record of the last deploy), BannerRecord (the banner's record, which the real deploy
            #      writes), OldBanner (what the old banner leaves), Record (what the stand-in deploy was
            #      given), Args (how pwsh was started) and Wrapped (written by the stand-in pwsh.exe in
            #      Program Files)
            param([switch]$NoPathLookup, [string]$Netlogon = "net logon's copy")
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $packageFolder = Join-Path (Join-Path $root $Netlogon) 'UsaBanner'
            $module = Join-Path $packageFolder 'UsaBanner'
            $programData = Join-Path $root 'ProgramData'
            foreach ($folder in (Join-Path $module 'windows'), (Join-Path $module 'Bootstrap'), $programData, (Join-Path $root 'ProgramFiles')) {
                $null = New-Item -ItemType Directory -Path $folder -Force
            }
            Copy-Item -LiteralPath $RunnerSrc, $DeployPartSrc -Destination (Join-Path $module 'windows')
            $handoff = [System.IO.File]::ReadAllText($HandoffSrc)
            if ($NoPathLookup) {
                $lookup = "-Name 'pwsh' "
                if (-not $handoff.Contains($lookup)) { throw "Handoff.ps1 no longer searches the PATH with $lookup : change this test's stand-in" }
                $handoff = $handoff.Replace($lookup, "-Name 'pwsh-that-is-not-installed' ")
            }
            [System.IO.File]::WriteAllText((Join-Path (Join-Path $module 'Bootstrap') 'Handoff.ps1'), $handoff)
            [System.IO.File]::WriteAllText((Join-Path $module 'UsaBanner.psm1'), "$StubModule`n")
            [System.IO.File]::WriteAllText((Join-Path $module 'UsaBanner.psd1'), "@{ RootModule = 'UsaBanner.psm1'; ModuleVersion = '0.0.1'; FunctionsToExport = @('Deploy-UsaBanner') }`n")
            [System.IO.File]::WriteAllText((Join-Path $packageFolder 'usabanner.json'), "{ `"company`": `"Contoso`" }`n")
            [pscustomobject]@{
                Runner       = Join-Path (Join-Path $module 'windows') 'Sync-UsaBanner.ps1'
                DeployPart   = Join-Path (Join-Path $module 'windows') 'SyncDeploy.ps1'
                Module       = $module
                Package      = Join-Path $packageFolder 'usabanner.json'
                SystemRoot   = Join-Path $root 'Windows'
                ProgramData  = $programData
                ProgramFiles = Join-Path $root 'ProgramFiles'
                Log          = Join-Path $root 'Windows' 'Logs' 'UsaBanner' 'sync.log'
                Stamp        = Join-Path $root 'Windows' 'Logs' 'UsaBanner' 'sync.stamp'
                BannerRecord = Join-Path $programData $RecordInProgramData
                OldBanner    = @($OldBannerInProgramData | ForEach-Object { Join-Path $programData $_ })
                Record       = Join-Path $root 'deploy-record.txt'
                Args         = Join-Path $root 'pwsh-args.txt'
                Wrapped      = Join-Path $root 'wrapped.txt'
            }
        }

        function Invoke-SyncRunner {
            # In:  a share (New-SyncShare); -Before for PowerShell to run in the same process first,
            #      where the script is then run with & rather than -File
            # Out: @{ ExitCode; Output }: the script's exit code, and what it printed
            param($Share, [string]$Before)
            $start = @('-NoProfile', '-NonInteractive', '-File', $Share.Runner)
            if ($Before) {
                $text = "$Before`n& '$($Share.Runner.Replace("'", "''"))'`nexit `$LASTEXITCODE"
                $start = @('-NoProfile', '-NonInteractive', '-EncodedCommand', [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($text)))
            }
            $output = @(& $EnvTool "SystemRoot=$($Share.SystemRoot)" "ProgramData=$($Share.ProgramData)" "ProgramFiles=$($Share.ProgramFiles)" "STUB_ARGS=$($Share.Args)" "STUB_RECORD=$($Share.Record)" "STUB_WRAPPED=$($Share.Wrapped)" "STUB_REAL_PWSH=$Pwsh" $Pwsh @start 2>&1 | ForEach-Object { "$_" })
            @{ ExitCode = $LASTEXITCODE; Output = $output }
        }

        function Get-SyncLogMessage {
            # In:  a share
            # Out: each line of its log without the time stamp; nothing where there is no log
            param($Share)
            if (Test-Path -LiteralPath $Share.Log) {
                @(Get-Content -LiteralPath $Share.Log) -replace '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{2}:\d{2}  ', ''
            }
        }

        function Set-SyncLog {
            # In:  a share, and the lines its log holds from an earlier run
            param($Share, [string[]]$Line)
            $null = New-Item -ItemType Directory -Path (Split-Path $Share.Log) -Force
            [System.IO.File]::WriteAllLines($Share.Log, $Line)
        }

        function Set-BannerRecord {
            # In:  a share
            # Out: nothing; the banner's record is where the real deploy writes it, as after one
            param($Share)
            $null = New-Item -ItemType Directory -Path (Split-Path $Share.BannerRecord) -Force
            [System.IO.File]::WriteAllText($Share.BannerRecord, "{}`n")
        }

        function Set-StampTime {
            # In:  a share, and the time its record of the last deploy should give
            # Out: nothing; the record's first line says that time, the rest as it was
            param($Share, [datetime]$When)
            $lines = @(Get-Content -LiteralPath $Share.Stamp)
            $lines[0] = 'deployed ' + $When.ToUniversalTime().ToString('o', [cultureinfo]::InvariantCulture)
            [System.IO.File]::WriteAllLines($Share.Stamp, [string[]]$lines)
        }
    }

    Context 'the deploy' {
        It 'runs Deploy-UsaBanner in pwsh with the package beside the module folder and -ReplaceOldBanner, after importing the module folder it sits in; a space and an apostrophe in the path arrive whole' {
            $c = New-SyncShare
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            @(Get-Content -LiteralPath $c.Record) | Should -Be @("Path=$($c.Package) ReplaceOldBanner=True Module=$($c.Module)")
        }

        It 'starts pwsh with no profile, not interactive, the execution policy Bypass (the module is on a share) and text output, and hands it the script as -EncodedCommand: no command string' {
            $c = New-SyncShare
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            # What pwsh was started with, after the program's own name.
            $all = @(Get-Content -LiteralPath $c.Args)
            $first = [array]::IndexOf($all, '-NoProfile')
            $first | Should -BeGreaterThan -1 -Because ($all -join ' ')
            $called = @($all[$first..($all.Count - 1)])
            $called.Count | Should -Be 8
            $called[0..6] | Should -Be @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-OutputFormat', 'Text', '-EncodedCommand')
            $script = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($called[7]))
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, [ref]$errors)
            @($errors) | Should -BeNullOrEmpty
            $manifest = Join-Path $c.Module 'UsaBanner.psd1'
            $script | Should -Match ([regex]::Escape("Import-Module -Name '$($manifest.Replace("'", "''"))'"))
            $script | Should -Match '(?m)^Deploy-UsaBanner @parameters$'
        }

        It 'finds pwsh in Program Files\PowerShell\7 when the PATH has none: a task started before the MSI installed it still has the old PATH' {
            $c = New-SyncShare -NoPathLookup
            Write-StandIn (Join-Path $c.ProgramFiles 'PowerShell\7\pwsh.exe') $StandInMsiPwsh
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            Test-Path -LiteralPath $c.Wrapped | Should -BeTrue -Because 'the pwsh.exe in Program Files did not run'
            @(Get-Content -LiteralPath $c.Record) | Should -Be @("Path=$($c.Package) ReplaceOldBanner=True Module=$($c.Module)")
        }

        It 'logs what the deploy printed, a line each, between its own first and last lines, and prints nothing itself' {
            $c = New-SyncShare
            [System.IO.File]::WriteAllLines((Join-Path $c.Module 'says.txt'), [string[]]@(
                    'installed the module UsaBanner 0.1.0 for every user: C:\Program Files\WindowsPowerShell\Modules\UsaBanner\0.1.0 (85 file(s) copied, 0 removed)'
                    'wrote C:\ProgramData\UsagiTools\Banner\usabanner.json: the configuration'))
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            $result.Output | Should -BeNullOrEmpty
            @(Get-SyncLogMessage $c) | Should -Be @(
                "sync from $($c.Module), package $($c.Package): no deploy is recorded here yet"
                'installed the module UsaBanner 0.1.0 for every user: C:\Program Files\WindowsPowerShell\Modules\UsaBanner\0.1.0 (85 file(s) copied, 0 removed)'
                'wrote C:\ProgramData\UsagiTools\Banner\usabanner.json: the configuration'
                'sync done')
        }

        It 'logs what pwsh writes to standard error too, and prints nothing itself' {
            $c = New-SyncShare
            [System.IO.File]::WriteAllText((Join-Path $c.Module 'says.txt'), "to standard output`n")
            [System.IO.File]::WriteAllText((Join-Path $c.Module 'stderr.txt'), "to standard error`n")
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            $result.Output | Should -BeNullOrEmpty
            $log = @(Get-SyncLogMessage $c)
            $log.Count | Should -Be 4
            $log | Should -Contain 'to standard output'
            $log | Should -Contain 'to standard error'
        }

        It 'adds its own two lines and no more when the deploy changes nothing' {
            $c = New-SyncShare
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            @(Get-SyncLogMessage $c) | Should -Be @("sync from $($c.Module), package $($c.Package): no deploy is recorded here yet", 'sync done')
        }

        It 'starts each line of the log with the date, the time and the UTC offset: the log says which clock it keeps' {
            $c = New-SyncShare
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            $lines = @(Get-Content -LiteralPath $c.Log)
            $lines.Count | Should -Be 2
            foreach ($line in $lines) { $line | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{2}:\d{2}  \S' }
        }
    }

    Context 'when a deploy is due' {
        It 'records a deploy that succeeded beside the log: its time in UTC, then the SHA-256 of the package and of each module file with its path, in ordinal order of the path' {
            $c = New-SyncShare
            $before = [datetime]::UtcNow
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            $after = [datetime]::UtcNow
            $lines = @(Get-Content -LiteralPath $c.Stamp)
            $lines[0] -match '^deployed (\S+)$' | Should -BeTrue -Because $lines[0]
            $when = [datetime]::ParseExact($Matches[1], 'o', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
            $when.Kind | Should -Be 'Utc'
            $when | Should -BeGreaterOrEqual $before.AddSeconds(-1)
            $when | Should -BeLessOrEqual $after
            $lines[1] | Should -Be "package $((Get-FileHash -LiteralPath $c.Package -Algorithm SHA256).Hash)"
            $names = [string[]]@(Get-ChildItem -LiteralPath $c.Module -Recurse -File | ForEach-Object { [System.IO.Path]::GetRelativePath($c.Module, $_.FullName) })
            [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
            $names | Should -Contain ([System.IO.Path]::Combine('windows', 'SyncDeploy.ps1'))
            @($lines | Select-Object -Skip 2) | Should -Be @($names | ForEach-Object { "$((Get-FileHash -LiteralPath (Join-Path $c.Module $_) -Algorithm SHA256).Hash) $_" })
        }

        It 'deploys nothing at a refresh that finds the package and the module folder as a deploy <Age> left them, and the banner in place: one line in the log, and no pwsh starts' -ForEach @(
            @{ Age = 'just now'; Hours = 0 }
            @{ Age = '23 hours ago'; Hours = 23 }
        ) {
            $c = New-SyncShare
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            Set-BannerRecord $c
            if ($Hours) { Set-StampTime $c ([datetime]::UtcNow.AddHours(-$Hours)) }
            Remove-Item -LiteralPath $c.Args
            $kept = Get-Content -LiteralPath $c.Stamp -Raw
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            $result.Output | Should -BeNullOrEmpty
            Test-Path -LiteralPath $c.Args | Should -BeFalse -Because 'a deploy ran in pwsh'
            @(Get-Content -LiteralPath $c.Record).Count | Should -Be 1
            Get-Content -LiteralPath $c.Stamp -Raw | Should -Be $kept -Because 'a refresh that deploys nothing records nothing'
            $log = @(Get-SyncLogMessage $c)
            $log.Count | Should -Be 3
            $log[2] | Should -Match '^nothing to deploy: the package and the module folder are as the deploy of \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC left them, and the banner is in place$'
        }

        It 'deploys again, and says why, when <Case>' -ForEach @(
            @{ Case = 'the package changed'; Reason = 'the package changed'; Before = $null; Change = { param($c) Add-Content -LiteralPath $c.Package -Value ' ' } }
            @{ Case = 'a module file changed'; Reason = 'a file in the module folder changed'; Before = $null; Change = { param($c) Add-Content -LiteralPath (Join-Path $c.Module 'UsaBanner.psm1') -Value '# changed' } }
            @{ Case = 'a file is added to the module folder'; Reason = 'a file in the module folder changed'; Before = $null; Change = { param($c) Set-Content -LiteralPath (Join-Path $c.Module 'added.txt') -Value 'new' } }
            @{ Case = 'a file is taken from the module folder'; Reason = 'a file in the module folder changed'; Before = { param($c) Set-Content -LiteralPath (Join-Path $c.Module 'going.txt') -Value 'old' }; Change = { param($c) Remove-Item -LiteralPath (Join-Path $c.Module 'going.txt') } }
            @{ Case = 'the last deploy was a day ago'; Reason = 'the last deploy was a day ago or more'; Before = $null; Change = { param($c) Set-StampTime $c ([datetime]::UtcNow.AddHours(-24).AddMinutes(-1)) } }
            @{ Case = 'the last deploy is recorded at a time still to come'; Reason = 'the last deploy is recorded at a time still to come'; Before = $null; Change = { param($c) Set-StampTime $c ([datetime]::UtcNow.AddHours(1)) } }
            @{ Case = 'the record of the last deploy cannot be read'; Reason = 'the record of the last deploy cannot be read: {Stamp}'; Before = $null; Change = { param($c) [System.IO.File]::WriteAllText($c.Stamp, "not a record`n") } }
            @{ Case = 'the banner''s record is gone, as after Remove-UsaBanner'; Reason = 'the banner''s record is gone: {BannerRecord}'; Before = $null; Change = { param($c) Remove-Item -LiteralPath $c.BannerRecord } }
            @{ Case = 'the old banner''s folder is on the host'; Reason = 'the old banner is on this host: {Old0}'; Before = $null; Change = { param($c) $null = New-Item -ItemType Directory -Path $c.OldBanner[0] -Force } }
            @{ Case = 'the old banner''s SSH banner file is on the host'; Reason = 'the old banner is on this host: {Old1}'; Before = $null; Change = { param($c) $null = New-Item -ItemType File -Path $c.OldBanner[1] -Force } }
        ) {
            $c = New-SyncShare
            if ($Before) { & $Before $c }
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            Set-BannerRecord $c
            & $Change $c
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            @(Get-Content -LiteralPath $c.Record).Count | Should -Be 2 -Because 'the second refresh deploys too'
            $why = $Reason.Replace('{Stamp}', $c.Stamp).Replace('{BannerRecord}', $c.BannerRecord).Replace('{Old0}', $c.OldBanner[0]).Replace('{Old1}', $c.OldBanner[1])
            @(Get-SyncLogMessage $c) | Should -Contain "sync from $($c.Module), package $($c.Package): $why"
        }

        It 'leaves the record of the last deploy as it was when a deploy fails, so each refresh deploys again until one succeeds' {
            $c = New-SyncShare
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            Set-BannerRecord $c
            $kept = Get-Content -LiteralPath $c.Stamp -Raw
            [System.IO.File]::WriteAllText((Join-Path $c.Module 'fails.txt'), "render failed`n")
            (Invoke-SyncRunner $c).ExitCode | Should -Be 1
            Get-Content -LiteralPath $c.Stamp -Raw | Should -Be $kept
            (Invoke-SyncRunner $c).ExitCode | Should -Be 1
            @(Get-Content -LiteralPath $c.Record).Count | Should -Be 3 -Because 'each refresh after the failure deploys again'
        }
    }

    Context 'the log''s place' {
        It 'is %SystemRoot%\Logs\UsaBanner\sync.log, made on the first run, where only SYSTEM and Administrators may write, and the record of the last deploy is sync.stamp beside it: nothing of either in ProgramData, where any user may make files and folders' {
            $c = New-SyncShare
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            Test-Path -LiteralPath $c.Log -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $c.Stamp -PathType Leaf | Should -BeTrue
            @(Get-ChildItem -LiteralPath $c.ProgramData -Force) | Should -BeNullOrEmpty
        }
    }

    Context 'without PowerShell 7' {
        It 'logs that deploy-usawinssh''s policy installs it, runs no deploy, records none, and ends with exit code 0' {
            $c = New-SyncShare -NoPathLookup
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            Test-Path -LiteralPath $c.Args | Should -BeFalse
            Test-Path -LiteralPath $c.Record | Should -BeFalse
            Test-Path -LiteralPath $c.Stamp | Should -BeFalse -Because 'the next refresh must try again'
            $log = @(Get-SyncLogMessage $c)
            $log.Count | Should -Be 2
            $log[1] | Should -Match 'PowerShell 7 is not installed on this host.*nothing is deployed.*deploy-usawinssh''s policy installs it'
        }
    }

    Context 'one run at a time' {
        It 'ends with 0 and runs no deploy while another run holds the mutex, says so, and leaves the log as it was but for that line' {
            $c = New-SyncShare
            Set-SyncLog $c ([string[]](1..1000 | ForEach-Object { "old line $_" }))
            $held = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, $MutexName
            try {
                $held.WaitOne(0) | Should -BeTrue -Because "something else holds $MutexName"
                $result = Invoke-SyncRunner $c
            }
            finally {
                $held.ReleaseMutex()
                $held.Dispose()
            }
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            Test-Path -LiteralPath $c.Args | Should -BeFalse
            Test-Path -LiteralPath $c.Record | Should -BeFalse
            $lines = @(Get-Content -LiteralPath $c.Log)
            $lines.Count | Should -Be 1001
            $lines[0] | Should -Be 'old line 1'
            $lines[999] | Should -Be 'old line 1000'
            $lines[1000] | Should -Match 'another run of this sync holds the mutex Global\\UsaBanner-Sync: this run ends, and the next policy refresh runs it again$'
        }

        It 'takes over a mutex that a stopped run left abandoned, says so, and deploys: it does not fail on every run from then on' {
            $c = New-SyncShare
            # Windows reports a mutex abandoned when the process that held it was killed, as the task
            # scheduler kills a run that outlives its time limit; Linux does not, across processes. A
            # thread that ends holding it is abandoned alike on both, so the script runs in a process
            # where one has just done that.
            $abandon = @'
Add-Type -TypeDefinition @"
public static class MutexAbandoner {
    static System.Threading.Mutex kept;
    public static void Abandon(string name) {
        var thread = new System.Threading.Thread(() => { kept = new System.Threading.Mutex(false, name); kept.WaitOne(); });
        thread.Start();
        thread.Join();
    }
}
"@
[MutexAbandoner]::Abandon('Global\UsaBanner-Sync')
'@
            $result = Invoke-SyncRunner $c -Before $abandon
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            @(Get-Content -LiteralPath $c.Record) | Should -Be @("Path=$($c.Package) ReplaceOldBanner=True Module=$($c.Module)")
            $log = @(Get-SyncLogMessage $c)
            $log.Count | Should -Be 3
            $log[0] | Should -Match 'the last run of this sync was stopped before it finished, and left the mutex Global\\UsaBanner-Sync abandoned: this run took it over$'
            $log[1] | Should -Match '^sync from '
            $log[2] | Should -Be 'sync done'
        }
    }

    Context 'the log''s length' {
        It 'keeps the last 500 lines of earlier runs, drops the older ones, and adds this run''s' {
            $c = New-SyncShare
            Set-SyncLog $c ([string[]](1..1000 | ForEach-Object { "old line $_" }))
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            $lines = @(Get-Content -LiteralPath $c.Log)
            $lines.Count | Should -Be 502
            $lines[0] | Should -Be 'old line 501'
            $lines[499] | Should -Be 'old line 1000'
            $lines[501] | Should -Match ' sync done$'
        }

        It 'leaves a log of fewer than 500 lines whole' {
            $c = New-SyncShare
            Set-SyncLog $c ([string[]](1..499 | ForEach-Object { "old line $_" }))
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            $lines = @(Get-Content -LiteralPath $c.Log)
            $lines.Count | Should -Be 501
            $lines[0] | Should -Be 'old line 1'
            $lines[498] | Should -Be 'old line 499'
        }
    }

    Context 'a failure' {
        It 'ends with exit code 1 when the deploy fails, and the log names the pwsh, its exit code, the cause and the script line' {
            $c = New-SyncShare
            [System.IO.File]::WriteAllText((Join-Path $c.Module 'fails.txt'), "render failed: No User exists for *`n")
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 1 -Because ($result.Output -join "`n")
            Test-Path -LiteralPath $c.Stamp | Should -BeFalse -Because 'a deploy that failed is not recorded'
            $log = @(Get-SyncLogMessage $c)
            $log | Should -Contain 'render failed: No User exists for *'
            $log[-1] -match '^sync FAILED: Deploy-UsaBanner failed in PowerShell 7 \(.+pwsh\), exit code 1: render failed: No User exists for \* \(at SyncDeploy\.ps1:(\d+)\)$' | Should -BeTrue -Because $log[-1]
            # The line it names is the one that reports the deploy's failure.
            @(Get-Content -LiteralPath $c.DeployPart)[[int]$Matches[1] - 1] | Should -Match 'throw .*Deploy-UsaBanner failed in PowerShell 7'
        }

        It 'puts a cause of several lines on the one line' {
            $c = New-SyncShare
            [System.IO.File]::WriteAllText((Join-Path $c.Module 'fails.txt'), "UsaBanner: usabanner.json is not a valid configuration:`n  border.set: not one of the sets`n  legal.template: unknown`n")
            (Invoke-SyncRunner $c).ExitCode | Should -Be 1
            @(Get-SyncLogMessage $c)[-1] | Should -Match 'exit code 1: UsaBanner: usabanner\.json is not a valid configuration: border\.set: not one of the sets legal\.template: unknown \(at '
        }

        It 'reports a pwsh that ends without a word by its exit code alone' {
            $c = New-SyncShare
            [System.IO.File]::WriteAllText((Join-Path $c.Module 'exits.txt'), "3`n")
            (Invoke-SyncRunner $c).ExitCode | Should -Be 1
            @(Get-SyncLogMessage $c)[-1] | Should -Match '^sync FAILED: Deploy-UsaBanner failed in PowerShell 7 \(.+pwsh\), exit code 3 \(at SyncDeploy\.ps1:\d+\)$'
        }

        It 'ends with exit code 1 on a failure of its own, and names the cause and the script line' {
            $c = New-SyncShare
            Remove-Item -LiteralPath (Join-Path (Join-Path $c.Module 'Bootstrap') 'Handoff.ps1')
            (Invoke-SyncRunner $c).ExitCode | Should -Be 1
            @(Get-SyncLogMessage $c)[-1] | Should -Match '^sync FAILED: .*Handoff\.ps1.* \(at SyncDeploy\.ps1:\d+\)$'
            Test-Path -LiteralPath $c.Args | Should -BeFalse
        }

        It 'ends with exit code 1 when the package is not on the share, naming it and the script line, and starts no deploy' {
            $c = New-SyncShare
            Remove-Item -LiteralPath $c.Package
            (Invoke-SyncRunner $c).ExitCode | Should -Be 1
            @(Get-SyncLogMessage $c)[-1] | Should -Match ('^sync FAILED: .*' + [regex]::Escape($c.Package) + '.* \(at Sync-UsaBanner\.ps1:\d+\)$')
            Test-Path -LiteralPath $c.Args | Should -BeFalse
            Test-Path -LiteralPath $c.Stamp | Should -BeFalse
        }

        It 'ends with exit code 1 when it cannot write its log, though it cannot say why' {
            $c = New-SyncShare
            $blocked = Join-Path $TestDrive 'a-file-where-SystemRoot-should-be'
            [System.IO.File]::WriteAllText($blocked, 'x')
            $c.SystemRoot = $blocked
            (Invoke-SyncRunner $c).ExitCode | Should -Be 1
            Test-Path -LiteralPath $c.Record | Should -BeFalse
        }
    }
}

Describe 'Sync-UsaBanner.ps1 and SyncDeploy.ps1 as files for Windows PowerShell 5.1' {
    BeforeAll {
        # PowerShell's own check for suspicious content, an internal method of ScriptBlock: a script it
        # flags, PowerShell writes whole to its Operational log as event 4104 with no logging policy set.
        # This is PowerShell 7's list; what Windows PowerShell 5.1's flags is for a lab.
        $flags = [System.Reflection.BindingFlags]'NonPublic, Static'
        $script:SuspiciousCheck = [System.Management.Automation.ScriptBlock].GetMethods($flags) | Where-Object { $_.Name -eq 'CheckSuspiciousContent' } | Select-Object -First 1

        $script:Settings51 = @{
            IncludeRules = @('PSUseCompatibleSyntax')
            Rules        = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } }
        }

        function Get-Ps51Problem {
            # In:  a script's path
            # Out: a line for each thing in it that Windows PowerShell 5.1 lacks and the syntax rule
            #      does not see: Join-Path with more than two arguments, ForEach-Object -Parallel, and
            #      the automatic variables of PowerShell 7, which under strict mode stop a 5.1 script
            param([string]$Path)
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
            $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
            foreach ($command in $commands) {
                $name = $command.GetCommandName()
                $elements = @($command.CommandElements | Select-Object -Skip 1)
                $parameters = @($elements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
                $values = @($elements | Where-Object { $_ -isnot [System.Management.Automation.Language.CommandParameterAst] })
                if ($name -eq 'Join-Path' -and ($values.Count -gt 2 -or $parameters -contains 'AdditionalChildPath')) {
                    "line $($command.Extent.StartLineNumber): Join-Path with more than two arguments"
                }
                if ($name -in 'ForEach-Object', 'foreach', '%' -and $parameters -contains 'Parallel') {
                    "line $($command.Extent.StartLineNumber): ForEach-Object -Parallel"
                }
            }
            $variables = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
            foreach ($variable in $variables) {
                if ($variable.VariablePath.UserPath -in 'IsWindows', 'IsLinux', 'IsMacOS', 'IsCoreCLR', 'PSStyle') {
                    "line $($variable.Extent.StartLineNumber): `$$($variable.VariablePath.UserPath)"
                }
            }
        }

        function Get-PreferenceAssignment {
            # In:  a script's path
            # Out: a line for each assignment to a preference variable in its top-level code
            param([string]$Path)
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
            $assignments = $ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $node.Left.VariablePath.UserPath -match 'Preference$'
                }, $false)
            foreach ($assignment in $assignments) { "line $($assignment.Extent.StartLineNumber): $($assignment.Extent.Text)" }
        }
    }

    It '<File> is ASCII with LF line ends and no byte order mark: Windows PowerShell 5.1 reads a file without one in the ANSI code page' -ForEach @(
        @{ File = 'Sync-UsaBanner.ps1' }
        @{ File = 'SyncDeploy.ps1' }
    ) {
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $ModuleRoot 'windows' $File))
        $bytes.Count | Should -BeGreaterThan 0
        # 9 tab, 10 LF; anything else below 32, CR (13) and anything above 126 is out.
        @($bytes | Where-Object { $_ -gt 126 -or ($_ -lt 32 -and $_ -ne 9 -and $_ -ne 10) }) | Should -BeNullOrEmpty
    }

    It 'has a syntax check that catches PowerShell 7 syntax (else a pass proves nothing)' -Skip:(-not $hasAnalyzer) {
        $sample = Join-Path $TestDrive 'Sample.ps1'
        Set-Content -LiteralPath $sample -Value '$a = $b ?? ''c'''
        @(Invoke-ScriptAnalyzer -Path $sample -Settings $Settings51).Count | Should -BeGreaterThan 0
    }

    It '<File> uses no syntax that Windows PowerShell 5.1 lacks' -Skip:(-not $hasAnalyzer) -ForEach @(
        @{ File = 'Sync-UsaBanner.ps1' }
        @{ File = 'SyncDeploy.ps1' }
    ) {
        $found = @(Invoke-ScriptAnalyzer -Path (Join-Path $ModuleRoot 'windows' $File) -Settings $Settings51)
        @($found | ForEach-Object { "line $($_.Line): $($_.Message)" }) | Should -BeNullOrEmpty
    }

    It 'has a check for the commands and variables 5.1 lacks that catches each (else a pass proves nothing)' {
        $sample = Join-Path $TestDrive 'Sample.ps1'
        Set-Content -LiteralPath $sample -Value @('$a = Join-Path ''a'' ''b'' ''c''', '1..2 | ForEach-Object -Parallel { $_ }', 'if ($IsWindows) { 1 }')
        @(Get-Ps51Problem $sample) | Should -Be @('line 1: Join-Path with more than two arguments', 'line 2: ForEach-Object -Parallel', 'line 3: $IsWindows')
    }

    It '<File> uses no command form or variable that Windows PowerShell 5.1 lacks' -ForEach @(
        @{ File = 'Sync-UsaBanner.ps1' }
        @{ File = 'SyncDeploy.ps1' }
    ) {
        @(Get-Ps51Problem (Join-Path $ModuleRoot 'windows' $File)) | Should -BeNullOrEmpty
    }

    It 'has a check for a preference variable set at the top level that catches one (else a pass proves nothing)' {
        $sample = Join-Path $TestDrive 'Sample.ps1'
        Set-Content -LiteralPath $sample -Value @('function f { $WarningPreference = ''Stop'' }', 'try { $ErrorActionPreference = ''Stop'' } catch { }')
        @(Get-PreferenceAssignment $sample) | Should -Be @('line 2: $ErrorActionPreference = ''Stop''')
    }

    It '<File> sets no preference variable at its top level: under Stop, 5.1 throws at the first line pwsh writes to standard error, before it is logged' -ForEach @(
        @{ File = 'Sync-UsaBanner.ps1' }
        @{ File = 'SyncDeploy.ps1' }
    ) {
        @(Get-PreferenceAssignment (Join-Path $ModuleRoot 'windows' $File)) | Should -BeNullOrEmpty
    }

    It 'finds PowerShell''s own check for suspicious content' {
        $SuspiciousCheck | Should -Not -BeNullOrEmpty -Because 'the check is an internal method of ScriptBlock: where a PowerShell has none, find what took its place'
    }

    It 'has a check for suspicious content that catches some (else a pass proves nothing): SyncDeploy.ps1, which needs -ExecutionPolicy Bypass and -EncodedCommand, is flagged' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($DeployPartSrc, [ref]$null, [ref]$null)
        $SuspiciousCheck.Invoke($null, @($ast)) | Should -Not -BeNullOrEmpty
    }

    It 'leaves nothing in Sync-UsaBanner.ps1, code or comments, that PowerShell logs as suspicious: a refresh with nothing to deploy adds nothing to its log' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($RunnerSrc, [ref]$null, [ref]$null)
        $SuspiciousCheck.Invoke($null, @($ast)) | Should -BeNullOrEmpty
    }
}
