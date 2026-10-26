# Pester 5 tests for UsaBanner/linux/adsys-startup.sh, the Ubuntu runner of the Group Policy delivery
# (docs/DECISIONS.md, D29). The script runs under sh against a fake host in the test's own folder: ADSys's
# copy of SYSVOL, the banner's state folder, the folder of systemd units and the lock are moved there by the
# variables the script reads for the tests, and its PATH holds stand-ins alone, so nothing reaches the real
# systemd. systemctl, systemd-run and flock log their calls, a line each with the arguments separated by
# tabs; logger writes the journal's lines to a file; id and cp answer as the real ones do unless a test says
# otherwise. The stand-in systemd-run does what the unit would: it runs the command it was given, to its end,
# in an environment of nothing but the PATH; the module's stand-in bootstrap.sh logs how it was called. Linux
# only: they need sh.

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:Runner = Join-Path $RepoRoot 'UsaBanner' 'linux' 'adsys-startup.sh'
    $script:Tab = "`t"
    # The old banner's name, in two parts, so that no file of the new banner holds it (D23), this one included.
    $script:OldName = 'mana' + 'tech'
    $script:Mode644 = [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead'
    $script:Mode700 = [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute'
    $script:Mode755 = [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute'
}

Describe 'adsys-startup.sh' -Skip:$IsWindows {
    BeforeAll {
        $script:EnvTool = (Get-Command -Name env -CommandType Application)[0].Source
        $script:RealId = (Get-Command -Name id -CommandType Application)[0].Source
        $script:RealCp = (Get-Command -Name cp -CommandType Application)[0].Source
        # What every logging stand-in starts with: its name and its arguments, tab-separated, as a line of STUB_LOG.
        $script:Prelude = @'
t=$(printf '\t')
(IFS=$t; printf '%s\n' "${0##*/}$t$*") >>"$STUB_LOG"
'@

        function Write-Text {
            # In:  a path, and its text; the folders above it are made
            param([string]$Path, [string]$Text)
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
            [System.IO.File]::WriteAllText($Path, $Text)
        }

        function Write-Program {
            # In:  a path, and the program's text after its shebang, where @@NAME@@ marks stand for this test's paths
            # Out: nothing; the program is there, executable
            param([string]$Path, [string]$Text)
            $body = $Text.Replace('@@PRELUDE@@', $Prelude).Replace('@@LOG@@', $Log).Replace('@@WORK@@', $Work).Replace('@@CACHE@@', $Cache)
            $body = $body.Replace('@@REAL_ID@@', $RealId).Replace('@@REAL_CP@@', $RealCp).Replace('@@REAL_ENV@@', $EnvTool)
            Write-Text $Path ("#!/bin/sh`n" + $body.Replace("`r`n", "`n").TrimEnd("`n") + "`n")
            [System.IO.File]::SetUnixFileMode($Path, $Mode755)
        }

        function Set-TreeMode {
            # In:  a folder; Out: nothing; it and its folders are 755, its files 644, as a root-only copy would be
            param([string]$Path)
            foreach ($item in @(Get-Item -LiteralPath $Path -Force) + @(Get-ChildItem -LiteralPath $Path -Recurse -Force)) {
                [System.IO.File]::SetUnixFileMode($item.FullName, $(if ($item.PSIsContainer) { $Mode755 } else { $Mode644 }))
            }
        }

        function Set-Version {
            # In:  the Version= ADSys's copy of GPT.INI holds, written with CRLF as SYSVOL writes it
            param([int]$Version)
            Write-Text (Join-Path $Assets 'GPT.INI') "[General]`r`nVersion=$Version`r`n"
            [System.IO.File]::SetUnixFileMode((Join-Path $Assets 'GPT.INI'), $Mode644)
        }

        function Initialize-Host {
            # Out: nothing; $Bin holds the stand-ins and the real tools the script uses, $Cache is ADSys's copy of the
            #      GPO's folder at Version 7, with the runner, a package and a module whose bootstrap.sh is a stand-in
            foreach ($folder in $Bin, $Units) { $null = New-Item -ItemType Directory -Path $folder -Force }
            foreach ($tool in 'cat', 'chmod', 'dirname', 'find', 'grep', 'head', 'mkdir', 'mv', 'rm', 'sed', 'sh') {
                $null = New-Item -ItemType SymbolicLink -Path (Join-Path $Bin $tool) -Target (Get-Command -Name $tool -CommandType Application)[0].Source
            }
            Write-Program (Join-Path $Bin 'systemctl') @'
@@PRELUDE@@
case $1 in
list-units) [ -z "${STUB_BUSY:-}" ] || echo 'usabanner-gpo.service loaded active running UsaBanner: deploy the Group Policy package' ;;
daemon-reload) [ -z "${STUB_FAIL_RELOAD:-}" ] || { echo 'Failed to reload: stand-in failure' >&2; exit 1; } ;;
enable) [ -z "${STUB_FAIL_ENABLE:-}" ] || { echo 'Failed to enable unit: stand-in failure' >&2; exit 1; } ;;
esac
exit 0
'@
            Write-Program (Join-Path $Bin 'systemd-run') @'
@@PRELUDE@@
[ -z "${STUB_FAIL_SYSTEMD_RUN:-}" ] || { echo 'Failed to start transient service unit: stand-in failure' >&2; exit 1; }
while [ $# -gt 0 ]; do
	case $1 in -*) shift ;; *) break ;; esac
done
[ $# -gt 0 ] || exit 0
@@REAL_ENV@@ -i "PATH=$PATH" "$@" >>"@@WORK@@/unit.out" 2>&1
exit 0
'@
            # The lock is free at once, but for a file named during-lock.sh: that is what another run does while
            # this one waits for the lock, and the stand-in plays it before it returns.
            Write-Program (Join-Path $Bin 'flock') @'
@@PRELUDE@@
[ ! -f "@@WORK@@/during-lock.sh" ] || . "@@WORK@@/during-lock.sh"
exit 0
'@
            Write-Program (Join-Path $Bin 'logger') @'
tag=
while [ $# -gt 0 ]; do
	case $1 in
	-t) tag=$2; shift 2 ;;
	--) shift; break ;;
	*) break ;;
	esac
done
t=$(printf '\t')
printf '%s%s%s\n' "$tag" "$t" "$*" >>"$STUB_JOURNAL"
'@
            Write-Program (Join-Path $Bin 'id') @'
case ${1:-} in
-u) if [ -n "${STUB_UID:-}" ]; then echo "$STUB_UID"; exit 0; fi ;;
-g) if [ -n "${STUB_GID:-}" ]; then echo "$STUB_GID"; exit 0; fi ;;
esac
exec @@REAL_ID@@ "$@"
'@
            Write-Program (Join-Path $Bin 'cp') @'
if [ -n "${STUB_FAIL_CP:-}" ]; then
	echo 'cp: stand-in failure' >&2
	exit 1
fi
exec @@REAL_CP@@ "$@"
'@

            Set-Version 7
            $null = New-Item -ItemType Directory -Path $Cache -Force
            Copy-Item -LiteralPath $Runner -Destination $Installed
            Write-Text (Join-Path $Cache 'usabanner.json') "{`"version`":1,`"company`":`"Contoso`"}`n"
            Write-Text (Join-Path $Cache 'UsaBanner/UsaBanner.psd1') "@{ ModuleVersion = '0.0.1' }`n"
            Write-Text (Join-Path $Cache 'UsaBanner/linux/facts.sh') "#!/bin/sh`nexit 0`n"
            Write-Text (Join-Path $Cache 'UsaBanner/art/base/rabbit.json') "{}`n"
            # The module's bootstrap.sh logs its call and the package it was given; a file named refresh makes it
            # change ADSys's copy first, as a refresh of the copy would while a deploy runs, and a file named
            # bootstrap-exit gives its exit code.
            Write-Program (Join-Path $Cache 'UsaBanner/linux/bootstrap.sh') @'
t=$(printf '\t')
(IFS=$t; printf '%s\n' "bootstrap.sh$t$0$t$*") >>"@@LOG@@"
if [ -e "@@WORK@@/refresh" ]; then
	printf 'refreshed\n' >"@@CACHE@@/usabanner.json"
	printf 'refreshed\n' >"@@CACHE@@/UsaBanner/linux/facts.sh"
fi
printf 'package%s%s\n' "$t" "$(cat "$2")" >>"@@LOG@@"
exit "$(cat "@@WORK@@/bootstrap-exit" 2>/dev/null || echo 0)"
'@
            Set-TreeMode $Assets
        }

        function Invoke-Runner {
            # In:  the script's arguments; variables for the script and the stand-ins, as NAME=value (a later one
            #      wins over the fake host's own); the script to run, ADSys's copy of it unless another is given;
            #      the umask it starts with, which ADSys does not promise
            # Out: @{ ExitCode; Output; Calls; Journal }: how it ended, what it said, every logged call so far, and
            #      the lines it sent to the journal, tag and text
            param([string[]]$Arguments = @(), [string[]]$Variables = @(), [string]$Path = $Installed, [string]$Umask = '022')
            $output = @(& $EnvTool -i "PATH=$Bin" "USABANNER_ADSYS_ASSETS=$Assets" "USABANNER_STATE_DIR=$State" "USABANNER_UNIT_DIR=$Units" "USABANNER_LOCK_FILE=$Lock" "STUB_LOG=$Log" "STUB_JOURNAL=$JournalFile" @Variables /bin/sh -c 'umask "$1" && shift && exec /bin/sh "$@"' sh $Umask $Path @Arguments 2>&1 | ForEach-Object { "$_" })
            @{
                ExitCode = $LASTEXITCODE
                Output   = $output
                Calls    = @(if (Test-Path -LiteralPath $Log) { Get-Content -LiteralPath $Log })
                Journal  = @(if (Test-Path -LiteralPath $JournalFile) { Get-Content -LiteralPath $JournalFile })
            }
        }

        function Get-Calls {
            # In:  a program's name; Out: its logged calls, a line each, from every run so far
            param([string]$Name)
            @(if (Test-Path -LiteralPath $Log) { Get-Content -LiteralPath $Log | Where-Object { $_ -like "$Name$Tab*" } })
        }

        function Get-Record {
            # Out: the Version the unit recorded as deployed, or '' for none
            if (Test-Path -LiteralPath $Record) { (Get-Content -LiteralPath $Record -Raw).Trim() } else { '' }
        }

        function Get-Said {
            # In:  a run's result; Out: what it said, as one text, and what the unit said after it
            param($Result)
            ($Result.Output -join "`n") + "`n--- the unit:`n" + $(if (Test-Path -LiteralPath $UnitOut) { Get-Content -LiteralPath $UnitOut -Raw })
        }

        function Assert-NothingChanged {
            # A refused run starts no deploy, and leaves nothing of its own on the host
            @(Get-Calls 'systemd-run') | Should -BeNullOrEmpty
            $Stage | Should -Not -Exist
            @(Get-ChildItem -LiteralPath $Units -Force) | Should -BeNullOrEmpty
            $Record | Should -Not -Exist
        }
    }

    BeforeEach {
        $script:Work = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Bin = Join-Path $Work 'bin'
        $script:Assets = Join-Path $Work 'assets'
        $script:Cache = Join-Path $Assets 'scripts/UsaBanner'
        $script:State = Join-Path $Work 'state'
        $script:Units = Join-Path $Work 'units'
        $script:Lock = Join-Path $Work 'lock'
        $script:Log = Join-Path $Work 'calls.log'
        $script:JournalFile = Join-Path $Work 'journal.log'
        $script:UnitOut = Join-Path $Work 'unit.out'
        $script:Installed = Join-Path $Cache 'adsys-startup.sh'
        $script:Stage = Join-Path $State 'gpo'
        $script:Record = Join-Path $State 'gpo-installed-version'
        Initialize-Host
    }

    Context 'the file' {
        It 'parses under sh -n' {
            $out = & sh -n $Runner 2>&1 | Out-String
            "$out`nexit=$LASTEXITCODE" | Should -Match 'exit=0$'
        }
        It 'has a sh -n here that rejects a broken script (else the parse check proves nothing)' {
            $broken = Join-Path $Work 'broken.sh'
            [System.IO.File]::WriteAllText($broken, "if true; then`necho unterminated`n")
            & sh -n $broken 2>&1 | Out-Null
            $LASTEXITCODE | Should -Not -Be 0
        }
        It 'is ASCII with LF line endings, and never names the old banner (D23)' {
            $bytes = [System.IO.File]::ReadAllBytes($Runner)
            @($bytes | Where-Object { $_ -gt 126 -or ($_ -lt 32 -and $_ -ne 10 -and $_ -ne 9) }).Count | Should -Be 0
            [System.Text.Encoding]::ASCII.GetString($bytes) | Should -Not -Match $OldName
        }
        It 'defaults to the paths of a real host when nothing moves them' {
            $text = Get-Content -LiteralPath $Runner -Raw
            foreach ($default in 'USABANNER_ADSYS_ASSETS:-/var/cache/adsys/sysvol/assets', 'USABANNER_STATE_DIR:-/var/lib/usabanner', 'USABANNER_UNIT_DIR:-/etc/systemd/system', 'USABANNER_LOCK_FILE:-/run/usabanner-gpo.lock') {
                $text | Should -Match ([regex]::Escape($default))
            }
        }
        It 'refuses an argument it does not know, and does nothing' {
            $result = Invoke-Runner @('--if-new-versoin')
            $result.ExitCode | Should -Be 2
            ($result.Output -join "`n") | Should -Match 'usage: sh .*\[--if-new-version\]'
            $result.Calls | Should -BeNullOrEmpty
            $State | Should -Not -Exist
        }
    }

    Context 'the Version gate (--if-new-version)' {
        It 'deploys a Version not deployed yet, and the unit records it' {
            $result = Invoke-Runner @('--if-new-version')
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            @(Get-Calls 'systemd-run').Count | Should -Be 1
            Get-Record | Should -Be '7' -Because (Get-Said $result)
        }
        It 'does nothing when the watcher fires again for the Version deployed' {
            Invoke-Runner @('--if-new-version') | Out-Null
            $result = Invoke-Runner @('--if-new-version')
            $result.ExitCode | Should -Be 0
            @(Get-Calls 'systemd-run').Count | Should -Be 1
            ($result.Output -join "`n") | Should -Match 'publish Version 7 is deployed already; nothing to do'
        }
        It 'deploys again when a publish raises the Version' {
            Invoke-Runner @('--if-new-version') | Out-Null
            Set-Version 8
            Invoke-Runner @('--if-new-version') | Out-Null
            @(Get-Calls 'systemd-run').Count | Should -Be 2
            Get-Record | Should -Be '8'
        }
        It 'always deploys without --if-new-version, as the boot run does' {
            Invoke-Runner | Out-Null
            Invoke-Runner | Out-Null
            @(Get-Calls 'systemd-run').Count | Should -Be 2
        }
        It 'keeps the recorded Version when a deploy fails, so the next run tries again' {
            Invoke-Runner @('--if-new-version') | Out-Null
            Set-Version 8
            Write-Text (Join-Path $Work 'bootstrap-exit') "1`n"
            $failed = Invoke-Runner @('--if-new-version')
            $failed.ExitCode | Should -Be 0 -Because 'the script hands the deploy over and ends; the unit is what fails'
            @(Get-Calls 'bootstrap.sh').Count | Should -Be 2
            Get-Record | Should -Be '7'
            Remove-Item -LiteralPath (Join-Path $Work 'bootstrap-exit')
            Invoke-Runner @('--if-new-version') | Out-Null
            @(Get-Calls 'bootstrap.sh').Count | Should -Be 3
            Get-Record | Should -Be '8'
        }
        It 'reads the Version after taking the lock, so a run that waited sees what the other one deployed' {
            # While this run waits for the lock, a publish lands (Version 8) and the run that holds the lock deploys it.
            $null = New-Item -ItemType Directory -Path $State
            Write-Text (Join-Path $Work 'during-lock.sh') "printf '[General]\r\nVersion=8\r\n' >'$Assets/GPT.INI'`nprintf '8\n' >'$Record'`n"
            $result = Invoke-Runner @('--if-new-version')
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            @(Get-Calls 'systemd-run') | Should -BeNullOrEmpty
            ($result.Output -join "`n") | Should -Match 'publish Version 8 is deployed already'
        }
        It 'deploys, and records nothing, where GPT.INI holds no Version' {
            Remove-Item -LiteralPath (Join-Path $Assets 'GPT.INI')
            $result = Invoke-Runner @('--if-new-version')
            $result.ExitCode | Should -Be 0
            @(Get-Calls 'systemd-run').Count | Should -Be 1
            $Record | Should -Not -Exist
        }
    }

    Context 'the copy it deploys from' {
        It 'copies the module and the package into the state folder, and runs bootstrap.sh from the copy with -Path and -ReplaceOldBanner' {
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            Get-Calls 'bootstrap.sh' | Should -Be @("bootstrap.sh${Tab}$Stage/UsaBanner/linux/bootstrap.sh${Tab}-Path${Tab}$Stage/usabanner.json${Tab}-ReplaceOldBanner") -Because (Get-Said $result)
            foreach ($file in @(Get-ChildItem -LiteralPath $Cache -Recurse -File | Where-Object { $_.Name -ne 'adsys-startup.sh' })) {
                $relative = [System.IO.Path]::GetRelativePath($Cache, $file.FullName)
                (Get-FileHash -LiteralPath (Join-Path $Stage $relative)).Hash | Should -Be (Get-FileHash -LiteralPath $file.FullName).Hash -Because $relative
            }
        }
        It 'makes the copy before anything runs: a refresh of ADSys''s copy during the deploy changes nothing it runs' {
            Write-Text (Join-Path $Work 'refresh') "yes`n"
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 0
            # The refresh happened (else this proves nothing) ...
            (Get-Content -LiteralPath (Join-Path $Cache 'usabanner.json') -Raw).Trim() | Should -Be 'refreshed'
            # ... and the deploy was given the package as it was, from the copy.
            Get-Calls 'package' | Should -Be @("package${Tab}{`"version`":1,`"company`":`"Contoso`"}")
            (Get-Content -LiteralPath (Join-Path $Stage 'usabanner.json') -Raw).Trim() | Should -Be '{"version":1,"company":"Contoso"}'
            (Get-Content -LiteralPath (Join-Path $Stage 'UsaBanner/linux/facts.sh') -Raw) | Should -Be "#!/bin/sh`nexit 0`n"
        }
        It 'keeps the copy where only root can change it, in a state folder others can read' {
            Invoke-Runner | Out-Null
            [System.IO.File]::GetUnixFileMode($Stage) | Should -Be $Mode700
            [System.IO.File]::GetUnixFileMode($State) | Should -Be $Mode755
        }
        It 'sets the modes itself, whatever umask it is started with' {
            $result = Invoke-Runner -Umask '077'
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            [System.IO.File]::GetUnixFileMode($State) | Should -Be $Mode755
            [System.IO.File]::GetUnixFileMode($Stage) | Should -Be $Mode700
            foreach ($name in 'usabanner-publish.path', 'usabanner-publish.service') {
                [System.IO.File]::GetUnixFileMode((Join-Path $Units $name)) | Should -Be $Mode644 -Because $name
            }
        }
        It 'replaces an earlier copy whole, and starts from nothing after a run that was cut short' {
            Write-Text (Join-Path $Stage 'UsaBanner/dropped-by-the-new-publish.ps1') "old`n"
            Write-Text (Join-Path $Stage 'old-package.json') "old`n"
            Write-Text (Join-Path $State 'gpo.new/left-by-a-killed-run') "old`n"
            Set-TreeMode $State
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            (Join-Path $Stage 'UsaBanner/dropped-by-the-new-publish.ps1') | Should -Not -Exist
            (Join-Path $Stage 'old-package.json') | Should -Not -Exist
            (Join-Path $Stage 'usabanner.json') | Should -Exist
            (Join-Path $State 'gpo.new') | Should -Not -Exist
        }
        It 'leaves the copy it had, and starts no deploy, when the new one cannot be made' {
            Write-Text (Join-Path $Stage 'earlier') "earlier`n"
            Set-TreeMode $State
            $result = Invoke-Runner @() @('STUB_FAIL_CP=1')
            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match 'could not copy the module and the package'
            (Get-Content -LiteralPath (Join-Path $Stage 'earlier') -Raw) | Should -Be "earlier`n"
            (Join-Path $State 'gpo.new') | Should -Not -Exist
            @(Get-Calls 'systemd-run') | Should -BeNullOrEmpty
            @(Get-ChildItem -LiteralPath $Units -Force) | Should -BeNullOrEmpty
        }
        It 'deploys from ADSys''s copy even when it was started from the folder ADSys staged it in at boot, so the Version and the files agree' {
            $staged = Join-Path $Work 'run/adsys/machine/scripts/scripts/UsaBanner'
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $staged) -Force
            Copy-Item -LiteralPath $Cache -Destination $staged -Recurse
            [System.IO.File]::WriteAllText((Join-Path $staged 'usabanner.json'), "{`"version`":1,`"company`":`"Staged`"}`n")
            Set-TreeMode (Join-Path $Work 'run')
            $result = Invoke-Runner @() @() (Join-Path $staged 'adsys-startup.sh')
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            (Get-Content -LiteralPath (Join-Path $Stage 'usabanner.json') -Raw).Trim() | Should -Be '{"version":1,"company":"Contoso"}'
            ($result.Output -join "`n") | Should -Match ([regex]::Escape("from $Cache (published Version 7)"))
            Get-Record | Should -Be '7'
        }
        It 'deploys from the folder next to the script where ADSys''s copy holds none, and records no Version for it' {
            $other = Join-Path $Work 'other'
            Copy-Item -LiteralPath $Cache -Destination $other -Recurse
            Set-TreeMode $other
            Remove-Item -LiteralPath $Cache -Recurse -Force
            $result = Invoke-Runner @('--if-new-version') -Path (Join-Path $other 'adsys-startup.sh')
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            Get-Calls 'bootstrap.sh' | Should -Be @("bootstrap.sh${Tab}$Stage/UsaBanner/linux/bootstrap.sh${Tab}-Path${Tab}$Stage/usabanner.json${Tab}-ReplaceOldBanner")
            ($result.Output -join "`n") | Should -Match ([regex]::Escape("from $other"))
            $Record | Should -Not -Exist
        }
        It 'says where it looked when neither folder holds the module and the package, and does nothing' {
            Remove-Item -LiteralPath (Join-Path $Cache 'UsaBanner/linux/bootstrap.sh')
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match 'neither in the ADSys copy .* nor next to '
            Assert-NothingChanged
        }
    }

    Context 'a copy it refuses' {
        It 'refuses a copy whose <File> has CRLF line endings, and says to publish again' -ForEach @(@{ File = 'bootstrap.sh' }, @{ File = 'facts.sh' }) {
            $path = Join-Path $Cache "UsaBanner/linux/$File"
            [System.IO.File]::WriteAllText($path, "#!/bin/sh`r`nexit 0`r`n")
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match ([regex]::Escape("$path has CRLF line endings"))
            ($result.Output -join "`n") | Should -Match 'publish again'
            Assert-NothingChanged
        }
        It 'does not mind CRLF in the package, which PowerShell reads' {
            [System.IO.File]::WriteAllText((Join-Path $Cache 'usabanner.json'), "{`r`n  `"version`": 1`r`n}`r`n")
            (Invoke-Runner).ExitCode | Should -Be 0
            @(Get-Calls 'systemd-run').Count | Should -Be 1
        }
        It 'refuses a copy with <Case>, names it, and changes nothing' -ForEach @(
            @{ Case = 'a script anyone can write'; Item = 'UsaBanner/linux/facts.sh'; Mode = 'UserRead, UserWrite, GroupRead, OtherRead, OtherWrite' }
            @{ Case = 'a package anyone can write'; Item = 'usabanner.json'; Mode = 'UserRead, UserWrite, GroupRead, OtherRead, OtherWrite' }
            @{ Case = 'a folder in it anyone can write'; Item = 'UsaBanner/art'; Mode = 'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherWrite, OtherExecute' }
            @{ Case = 'a file a group other than root''s can write'; Item = 'UsaBanner/UsaBanner.psd1'; Mode = 'UserRead, UserWrite, GroupRead, GroupWrite, OtherRead'; OtherGroup = $true }
        ) {
            $full = Join-Path $Cache $Item
            [System.IO.File]::SetUnixFileMode($full, [System.IO.UnixFileMode]$Mode)
            $variables = @()
            if ($OtherGroup) { $variables = @("STUB_GID=$([int](& stat -c '%g' $full) + 1)") }
            $result = Invoke-Runner @() $variables
            $result.ExitCode | Should -Be 1 -Because (Get-Said $result)
            ($result.Output -join "`n") | Should -Match ([regex]::Escape("$full is not a plain file or folder, or can be changed by someone other than root"))
            Assert-NothingChanged
        }
        It 'accepts a file its group can write where the group is root''s' {
            $full = Join-Path $Cache 'UsaBanner/UsaBanner.psd1'
            [System.IO.File]::SetUnixFileMode($full, [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, GroupWrite, OtherRead')
            $result = Invoke-Runner @() @("STUB_GID=$(& stat -c '%g' $full)")
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            @(Get-Calls 'systemd-run').Count | Should -Be 1
        }
        It 'refuses a copy owned by someone other than root, and changes nothing' {
            # The stand-in id says the script runs as another user than the one who owns the copy.
            $result = Invoke-Runner @() @("STUB_UID=$([int](& id -u) + 1)")
            $result.ExitCode | Should -Be 1 -Because (Get-Said $result)
            ($result.Output -join "`n") | Should -Match ([regex]::Escape("someone other than root; not running the copy in $Cache"))
            Assert-NothingChanged
        }
        It 'refuses a copy that holds a link, which could point anywhere, and changes nothing' {
            $link = Join-Path $Cache 'UsaBanner/linux/shortcut.sh'
            $null = New-Item -ItemType SymbolicLink -Path $link -Target (Join-Path $Cache 'UsaBanner/linux/facts.sh')
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 1 -Because (Get-Said $result)
            ($result.Output -join "`n") | Should -Match ([regex]::Escape("$link is not a plain file or folder"))
            Assert-NothingChanged
        }
        It 'refuses a copy that holds a pipe, or any other file that is not a plain one, and changes nothing' -Skip:(-not (Get-Command -Name mkfifo -ErrorAction SilentlyContinue)) {
            # A link is mode 777 on Linux, so the rule about writable files catches it first; a pipe has an
            # ordinary mode, and only the rule about the kind of file stops it.
            $fifo = Join-Path $Cache 'UsaBanner/linux/pipe'
            & mkfifo $fifo
            [System.IO.File]::SetUnixFileMode($fifo, $Mode644)
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 1 -Because (Get-Said $result)
            ($result.Output -join "`n") | Should -Match ([regex]::Escape("$fifo is not a plain file or folder"))
            Assert-NothingChanged
        }
        It 'refuses to copy into a state folder anyone can write, and starts no deploy' {
            $null = New-Item -ItemType Directory -Path $State
            [System.IO.File]::SetUnixFileMode($State, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupWrite, GroupExecute, OtherRead, OtherWrite, OtherExecute')
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 1 -Because (Get-Said $result)
            ($result.Output -join "`n") | Should -Match ([regex]::Escape("$State can be changed by someone other than root; not copying into it"))
            Assert-NothingChanged
        }
    }

    Context 'the publish watcher' {
        It 'writes a path unit on the copy''s GPT.INI, and a service that waits 30 seconds, then runs this script with --if-new-version' {
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            @(Get-ChildItem -LiteralPath $Units -File | ForEach-Object { $_.Name } | Sort-Object) | Should -Be @('usabanner-publish.path', 'usabanner-publish.service')
            $path = @(Get-Content -LiteralPath (Join-Path $Units 'usabanner-publish.path'))
            $path | Should -Contain "PathChanged=$Assets/GPT.INI"
            $path | Should -Contain 'Unit=usabanner-publish.service'
            $path | Should -Contain 'WantedBy=paths.target'
            $service = @(Get-Content -LiteralPath (Join-Path $Units 'usabanner-publish.service'))
            $service | Should -Contain 'Type=oneshot'
            $service | Should -Contain 'ExecStartPre=/bin/sleep 30'
            $service | Should -Contain "ExecStart=/bin/sh $Cache/adsys-startup.sh --if-new-version"
            $service | Should -Contain "ConditionPathExists=$Cache/adsys-startup.sh"
            $service | Should -Contain 'SyslogIdentifier=usabanner'
            $service | Should -Contain 'Environment=USABANNER_STDERR_JOURNAL=1'
            foreach ($name in 'usabanner-publish.path', 'usabanner-publish.service') {
                (Get-Content -LiteralPath (Join-Path $Units $name) -Raw) | Should -Not -Match $OldName
                [System.IO.File]::GetUnixFileMode((Join-Path $Units $name)) | Should -Be $Mode644
            }
        }
        It 'has a systemd-analyze verify here that rejects a broken unit (else a pass proves nothing)' -Skip:(-not (Get-Command -Name systemd-analyze -ErrorAction SilentlyContinue)) {
            $broken = Join-Path $Work 'broken.service'
            [System.IO.File]::WriteAllText($broken, "[Service]`nType=oneshot`nExecStart=/nonexistent/usabanner-probe`n")
            $out = & systemd-analyze verify $broken 2>&1 | Out-String
            "$out`nexit=$LASTEXITCODE" | Should -Not -Match 'exit=0$'
        }
        It 'writes units that pass systemd-analyze verify' -Skip:(-not (Get-Command -Name systemd-analyze -ErrorAction SilentlyContinue)) {
            Invoke-Runner | Out-Null
            $out = & systemd-analyze verify (Join-Path $Units 'usabanner-publish.path') (Join-Path $Units 'usabanner-publish.service') 2>&1 | Out-String
            "$out`nexit=$LASTEXITCODE" | Should -Match 'exit=0$'
        }
        It 'reloads systemd, then enables and starts the path unit, and only then hands the deploy over' {
            Invoke-Runner | Out-Null
            $calls = @(Get-Calls 'systemctl' | ForEach-Object { ($_ -split $Tab)[1] })
            $calls | Should -Be @('list-units', 'daemon-reload', 'enable')
            Get-Calls 'systemctl' | Select-Object -Last 1 | Should -Be "systemctl${Tab}enable${Tab}--now${Tab}usabanner-publish.path"
            $names = @((Get-Content -LiteralPath $Log) | ForEach-Object { ($_ -split $Tab)[0] })
            $names | Should -Be @('flock', 'systemctl', 'systemctl', 'systemctl', 'systemd-run', 'bootstrap.sh', 'package')
        }
        It 'writes each unit once, and not again while it is as it should be' {
            Invoke-Runner | Out-Null
            $old = [datetime]'2001-01-01'
            foreach ($name in 'usabanner-publish.path', 'usabanner-publish.service') { (Get-Item -LiteralPath (Join-Path $Units $name)).LastWriteTimeUtc = $old }
            Invoke-Runner | Out-Null
            foreach ($name in 'usabanner-publish.path', 'usabanner-publish.service') { (Get-Item -LiteralPath (Join-Path $Units $name)).LastWriteTimeUtc | Should -Be $old -Because $name }
            @(Get-Calls 'systemctl' | Where-Object { $_ -like "*${Tab}daemon-reload" }).Count | Should -Be 1
            # The path unit is enabled and started on every run, which puts a watcher back that someone stopped.
            @(Get-Calls 'systemctl' | Where-Object { $_ -like "*${Tab}enable${Tab}*" }).Count | Should -Be 2
        }
        It 'writes a unit that is missing or differs, and only that one, then reloads systemd' {
            Invoke-Runner | Out-Null
            $path = Join-Path $Units 'usabanner-publish.path'
            $service = Join-Path $Units 'usabanner-publish.service'
            $good = Get-Content -LiteralPath $service -Raw
            $old = [datetime]'2001-01-01'
            (Get-Item -LiteralPath $service).LastWriteTimeUtc = $old
            Add-Content -LiteralPath $service -Value 'ExecStartPre=/bin/false'
            Invoke-Runner | Out-Null
            Get-Content -LiteralPath $service -Raw | Should -Be $good
            @(Get-Calls 'systemctl' | Where-Object { $_ -like "*${Tab}daemon-reload" }).Count | Should -Be 2
            Remove-Item -LiteralPath $path
            (Get-Item -LiteralPath $service).LastWriteTimeUtc = $old
            Invoke-Runner | Out-Null
            $path | Should -Exist
            (Get-Item -LiteralPath $service).LastWriteTimeUtc | Should -Be $old
            @(Get-Calls 'systemctl' | Where-Object { $_ -like "*${Tab}daemon-reload" }).Count | Should -Be 3
        }
        It 'deploys all the same when systemctl cannot enable the path unit, and says so in its exit status' {
            $result = Invoke-Runner @() @('STUB_FAIL_ENABLE=1')
            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match 'systemctl could not enable usabanner-publish.path'
            @(Get-Calls 'systemd-run').Count | Should -Be 1
            @(Get-Calls 'bootstrap.sh').Count | Should -Be 1
        }
        It 'deploys all the same when systemctl cannot reload, and says so in its exit status' {
            $result = Invoke-Runner @() @('STUB_FAIL_RELOAD=1')
            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match 'systemctl daemon-reload failed'
            @(Get-Calls 'systemd-run').Count | Should -Be 1
            @(Get-Calls 'bootstrap.sh').Count | Should -Be 1
        }
        It 'deploys all the same when a unit cannot be written, and says so in its exit status' {
            $result = Invoke-Runner @() @("USABANNER_UNIT_DIR=$Work/no-such-folder")
            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match 'could not write .*usabanner-publish.path'
            @(Get-Calls 'bootstrap.sh').Count | Should -Be 1
        }
    }

    Context 'the deploy''s unit' {
        It 'hands the deploy to usabanner-gpo with systemd-run, ordered after the network, in the journal under the tag, and does not wait' {
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            $calls = @(Get-Calls 'systemd-run')
            $calls.Count | Should -Be 1
            $arguments = @($calls[0] -split $Tab | Select-Object -Skip 1)
            $arguments | Should -Contain '--unit=usabanner-gpo'
            $arguments | Should -Contain '--collect'
            $arguments | Should -Contain '--no-block'
            $arguments | Should -Not -Contain '--wait'
            $arguments | Should -Contain '--property=After=network-online.target'
            $arguments | Should -Contain '--property=Wants=network-online.target'
            $arguments | Should -Contain '--property=SyslogIdentifier=usabanner'
            $arguments | Should -Contain '--property=RuntimeMaxSec=1800'
        }
        It 'gives the unit one command that needs none of the script''s variables: bootstrap.sh from the copy, then the Version recorded' {
            Invoke-Runner | Out-Null
            $arguments = @(@(Get-Calls 'systemd-run')[0] -split $Tab | Select-Object -Skip 1)
            $arguments[-3] | Should -Be '/bin/sh'
            $arguments[-2] | Should -Be '-c'
            $arguments[-1] | Should -Be "sh '$Stage/UsaBanner/linux/bootstrap.sh' -Path '$Stage/usabanner.json' -ReplaceOldBanner && echo '7' >'$Record'"
            Get-Record | Should -Be '7'
        }
        It 'records no Version for a deploy whose files did not come from ADSys''s copy' {
            $other = Join-Path $Work 'other'
            Copy-Item -LiteralPath $Cache -Destination $other -Recurse
            Set-TreeMode $other
            Remove-Item -LiteralPath $Cache -Recurse -Force
            Invoke-Runner @() @() (Join-Path $other 'adsys-startup.sh') | Out-Null
            $arguments = @(@(Get-Calls 'systemd-run')[0] -split $Tab | Select-Object -Skip 1)
            $arguments[-1] | Should -Be "sh '$Stage/UsaBanner/linux/bootstrap.sh' -Path '$Stage/usabanner.json' -ReplaceOldBanner"
        }
        It 'fails, and says so, when systemd-run cannot start the unit' {
            $result = Invoke-Runner @() @('STUB_FAIL_SYSTEMD_RUN=1')
            $result.ExitCode | Should -Be 1
            ($result.Output -join "`n") | Should -Match 'systemd-run could not start usabanner-gpo.service'
            $Record | Should -Not -Exist
        }
        It 'leaves alone a copy that the unit of an earlier run is still deploying, and starts no second unit' {
            Write-Text (Join-Path $Stage 'marker') "earlier`n"
            Set-TreeMode $State
            $result = Invoke-Runner @() @('STUB_BUSY=1')
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            ($result.Output -join "`n") | Should -Match 'usabanner-gpo.service is still deploying an earlier run'
            @(Get-Calls 'systemd-run') | Should -BeNullOrEmpty
            (Get-Content -LiteralPath (Join-Path $Stage 'marker') -Raw) | Should -Be "earlier`n"
            @(Get-ChildItem -LiteralPath $Units -Force) | Should -BeNullOrEmpty
        }
    }

    Context 'what the unit calls' {
        It 'has bootstrap.ps1 give Deploy-UsaBanner the package by -Path and -ReplaceOldBanner as a switch, as the unit passes them' {
            # bootstrap.ps1 runs in a real pwsh against a stand-in module whose Deploy-UsaBanner has the real one's
            # parameters, with their checks, and says what it was given (as Bootstrap.Tests.ps1 does).
            $mod = Join-Path $Work 'module'
            $null = New-Item -ItemType Directory -Path (Join-Path $mod 'linux') -Force
            Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $Runner) 'bootstrap.ps1') -Destination (Join-Path $mod 'linux')
            Import-Module (Join-Path $RepoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
            try {
                $meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Module UsaBanner -Name Deploy-UsaBanner))
            }
            finally { Remove-Module UsaBanner -ErrorAction SilentlyContinue }
            $standIn = @(
                'function Deploy-UsaBanner {'
                [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($meta)
                "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($meta)))"
                "foreach (`$key in @(`$PSBoundParameters.Keys | Sort-Object)) { '{0}={1}' -f `$key, (@(`$PSBoundParameters[`$key]) -join '|') }"
                '}'
            ) -join "`n"
            [System.IO.File]::WriteAllText((Join-Path $mod 'UsaBanner.psm1'), "$standIn`n")
            [System.IO.File]::WriteAllText((Join-Path $mod 'UsaBanner.psd1'), "@{ RootModule = 'UsaBanner.psm1'; ModuleVersion = '0.0.1'; FunctionsToExport = @('Deploy-UsaBanner') }`n")
            $pwsh = (Get-Process -Id $PID).Path
            $output = @(& $pwsh -NoProfile -NonInteractive -File (Join-Path $mod 'linux' 'bootstrap.ps1') -Path "$Stage/usabanner.json" -ReplaceOldBanner 2>&1 | ForEach-Object { "$_" })
            $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
            $output | Should -Be @("Path=$Stage/usabanner.json", 'ReplaceOldBanner=True')
        }
    }

    Context 'one run at a time, and the journal' {
        It 'takes the lock on its lock file before it reads the Version or changes anything' {
            $result = Invoke-Runner
            Get-Calls 'flock' | Should -Be @("flock${Tab}9")
            $Lock | Should -Exist
            ($result.Calls[0] -split $Tab)[0] | Should -Be 'flock'
        }
        It 'goes ahead without the lock where there is no flock' {
            Remove-Item -LiteralPath (Join-Path $Bin 'flock')
            $result = Invoke-Runner
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            @(Get-Calls 'systemd-run').Count | Should -Be 1
        }
        It 'says each step to stderr and to the journal, under the tag usabanner' {
            $result = Invoke-Runner
            $said = @($result.Output | Where-Object { $_ -like 'usabanner: *' })
            $result.Output.Count | Should -Be $said.Count -Because (Get-Said $result)
            $result.Journal.Count | Should -Be $said.Count
            for ($i = 0; $i -lt $said.Count; $i++) {
                $fields = $result.Journal[$i] -split $Tab, 2
                $fields[0] | Should -BeExactly 'usabanner'
                $fields[1] | Should -Be $said[$i]
            }
            $said[-1] | Should -Be 'usabanner: handed the deploy over to usabanner-gpo.service; follow it with: journalctl -t usabanner -f'
        }
        It 'says each step once under usabanner-publish.service, whose stderr the journal takes under the tag: to stderr alone' {
            # A boot run writes the units, and sends its steps to the journal itself.
            Invoke-Runner | Out-Null
            $before = @(Get-Content -LiteralPath $JournalFile)
            $before | Should -Not -BeNullOrEmpty
            # The publish watcher's run, with the variables its service sets.
            $environment = @(Get-Content -LiteralPath (Join-Path $Units 'usabanner-publish.service') | Where-Object { $_ -like 'Environment=*' } | ForEach-Object { $_.Substring('Environment='.Length) })
            $environment | Should -Not -BeNullOrEmpty
            Set-Version 8
            $result = Invoke-Runner @('--if-new-version') $environment
            $result.ExitCode | Should -Be 0 -Because (Get-Said $result)
            @(Get-Calls 'systemd-run').Count | Should -Be 2
            $said = @($result.Output | Where-Object { $_ -like 'usabanner: *' })
            $result.Output.Count | Should -Be $said.Count -Because (Get-Said $result)
            $said[-1] | Should -Match '^usabanner: handed the deploy over'
            $result.Journal.Count | Should -Be $before.Count
        }
    }
}
