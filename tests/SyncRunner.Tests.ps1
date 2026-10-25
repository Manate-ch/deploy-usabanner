# Tests for UsaBanner/windows/Sync-UsaBanner.ps1, the script the UsaBanner Group Policy's scheduled
# task runs as SYSTEM from NETLOGON (docs/DECISIONS.md, D29). Each test runs a copy of it the way the
# task does, as a new process with -File, from a stand-in NETLOGON share: the module folder it sits in,
# holding the real Bootstrap\Handoff.ps1 and a stand-in module whose Deploy-UsaBanner has the real
# one's parameters and says what it was given, and the package beside it. SystemRoot, ProgramData
# and ProgramFiles are scratch folders. The pwsh the script runs is the real one: PowerShell puts its own
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
            # Out: the share's parts: Runner (the script, in <Module>\windows), Module, Package (the
            #      configuration file beside the module folder), SystemRoot, ProgramData, ProgramFiles,
            #      Log (where the script writes), Record (what the stand-in deploy was given), Args
            #      (how pwsh was started) and Wrapped (written by the stand-in pwsh.exe in Program Files)
            param([switch]$NoPathLookup, [string]$Netlogon = "net logon's copy")
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
            $packageFolder = Join-Path (Join-Path $root $Netlogon) 'UsaBanner'
            $module = Join-Path $packageFolder 'UsaBanner'
            $programData = Join-Path $root 'ProgramData'
            foreach ($folder in (Join-Path $module 'windows'), (Join-Path $module 'Bootstrap'), $programData, (Join-Path $root 'ProgramFiles')) {
                $null = New-Item -ItemType Directory -Path $folder -Force
            }
            Copy-Item -LiteralPath $RunnerSrc -Destination (Join-Path $module 'windows')
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
                Module       = $module
                Package      = Join-Path $packageFolder 'usabanner.json'
                SystemRoot   = Join-Path $root 'Windows'
                ProgramData  = $programData
                ProgramFiles = Join-Path $root 'ProgramFiles'
                Log          = Join-Path $root 'Windows' 'Logs' 'UsaBanner' 'sync.log'
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
                "sync from $($c.Module), package $($c.Package)"
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

        It 'adds its own two lines and no more when the deploy changes nothing: a refresh costs little' {
            $c = New-SyncShare
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            @(Get-SyncLogMessage $c) | Should -Be @("sync from $($c.Module), package $($c.Package)", 'sync done')
        }

        It 'starts each line of the log with the date, the time and the UTC offset: the log says which clock it keeps' {
            $c = New-SyncShare
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            $lines = @(Get-Content -LiteralPath $c.Log)
            $lines.Count | Should -Be 2
            foreach ($line in $lines) { $line | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{2}:\d{2}  \S' }
        }
    }

    Context 'the log''s place' {
        It 'is %SystemRoot%\Logs\UsaBanner\sync.log, made on the first run, where only SYSTEM and Administrators may write: nothing of it in ProgramData, where any user may make files and folders' {
            $c = New-SyncShare
            (Invoke-SyncRunner $c).ExitCode | Should -Be 0
            Test-Path -LiteralPath $c.Log -PathType Leaf | Should -BeTrue
            @(Get-ChildItem -LiteralPath $c.ProgramData -Force) | Should -BeNullOrEmpty
        }
    }

    Context 'without PowerShell 7' {
        It 'logs that deploy-usawinssh''s policy installs it, runs no deploy, and ends with exit code 0' {
            $c = New-SyncShare -NoPathLookup
            $result = Invoke-SyncRunner $c
            $result.ExitCode | Should -Be 0 -Because ($result.Output -join "`n")
            Test-Path -LiteralPath $c.Args | Should -BeFalse
            Test-Path -LiteralPath $c.Record | Should -BeFalse
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
            $log[1] | Should -Match 'the last run of this sync was stopped before it finished, and left the mutex Global\\UsaBanner-Sync abandoned: this run took it over$'
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
            $log = @(Get-SyncLogMessage $c)
            $log | Should -Contain 'render failed: No User exists for *'
            $log[-1] -match '^sync FAILED: Deploy-UsaBanner failed in PowerShell 7 \(.+pwsh\), exit code 1: render failed: No User exists for \* \(at Sync-UsaBanner\.ps1:(\d+)\)$' | Should -BeTrue -Because $log[-1]
            # The line it names is the one that reports the deploy's failure.
            @(Get-Content -LiteralPath $c.Runner)[[int]$Matches[1] - 1] | Should -Match 'throw .*Deploy-UsaBanner failed in PowerShell 7'
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
            @(Get-SyncLogMessage $c)[-1] | Should -Match '^sync FAILED: Deploy-UsaBanner failed in PowerShell 7 \(.+pwsh\), exit code 3 \(at Sync-UsaBanner\.ps1:\d+\)$'
        }

        It 'ends with exit code 1 on a failure of its own, and names the cause and the script line' {
            $c = New-SyncShare
            Remove-Item -LiteralPath (Join-Path (Join-Path $c.Module 'Bootstrap') 'Handoff.ps1')
            (Invoke-SyncRunner $c).ExitCode | Should -Be 1
            @(Get-SyncLogMessage $c)[-1] | Should -Match '^sync FAILED: .*Handoff\.ps1.* \(at Sync-UsaBanner\.ps1:\d+\)$'
            Test-Path -LiteralPath $c.Args | Should -BeFalse
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

Describe 'Sync-UsaBanner.ps1 as a file for Windows PowerShell 5.1' {
    BeforeAll {
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

    It 'is ASCII with LF line ends and no byte order mark: Windows PowerShell 5.1 reads a file without one in the ANSI code page' {
        $bytes = [System.IO.File]::ReadAllBytes($RunnerSrc)
        $bytes.Count | Should -BeGreaterThan 0
        # 9 tab, 10 LF; anything else below 32, CR (13) and anything above 126 is out.
        @($bytes | Where-Object { $_ -gt 126 -or ($_ -lt 32 -and $_ -ne 9 -and $_ -ne 10) }) | Should -BeNullOrEmpty
    }

    It 'has a syntax check that catches PowerShell 7 syntax (else a pass proves nothing)' -Skip:(-not $hasAnalyzer) {
        $sample = Join-Path $TestDrive 'Sample.ps1'
        Set-Content -LiteralPath $sample -Value '$a = $b ?? ''c'''
        @(Invoke-ScriptAnalyzer -Path $sample -Settings $Settings51).Count | Should -BeGreaterThan 0
    }

    It 'uses no syntax that Windows PowerShell 5.1 lacks' -Skip:(-not $hasAnalyzer) {
        $found = @(Invoke-ScriptAnalyzer -Path $RunnerSrc -Settings $Settings51)
        @($found | ForEach-Object { "line $($_.Line): $($_.Message)" }) | Should -BeNullOrEmpty
    }

    It 'has a check for the commands and variables 5.1 lacks that catches each (else a pass proves nothing)' {
        $sample = Join-Path $TestDrive 'Sample.ps1'
        Set-Content -LiteralPath $sample -Value @('$a = Join-Path ''a'' ''b'' ''c''', '1..2 | ForEach-Object -Parallel { $_ }', 'if ($IsWindows) { 1 }')
        @(Get-Ps51Problem $sample) | Should -Be @('line 1: Join-Path with more than two arguments', 'line 2: ForEach-Object -Parallel', 'line 3: $IsWindows')
    }

    It 'uses no command form or variable that Windows PowerShell 5.1 lacks' {
        @(Get-Ps51Problem $RunnerSrc) | Should -BeNullOrEmpty
    }

    It 'has a check for a preference variable set at the top level that catches one (else a pass proves nothing)' {
        $sample = Join-Path $TestDrive 'Sample.ps1'
        Set-Content -LiteralPath $sample -Value @('function f { $WarningPreference = ''Stop'' }', 'try { $ErrorActionPreference = ''Stop'' } catch { }')
        @(Get-PreferenceAssignment $sample) | Should -Be @('line 2: $ErrorActionPreference = ''Stop''')
    }

    It 'sets no preference variable at its top level: under Stop, 5.1 throws at the first line pwsh writes to standard error, before it is logged' {
        @(Get-PreferenceAssignment $RunnerSrc) | Should -BeNullOrEmpty
    }
}
