# Pester 5 tests for adsys-startup.sh (the ADSys startup script), run with sh
# against a copy that sits next to a stub install.sh. Linux only: they need sh.
# Output is not a terminal here, so the script takes its boot path (output to
# logger with the manatech-motd tag).

BeforeAll {
    $script:Startup = Join-Path $PSScriptRoot '../../adsys-startup.sh'

    # New-StartupCopy [INSTALL_SH] - a copy of adsys-startup.sh in a new folder,
    # with install.sh holding INSTALL_SH next to it; no INSTALL_SH, no install.sh.
    # (A [string] parameter turns $null into '', so "absent" is the empty string.)
    function New-StartupCopy {
        param([string]$InstallSh = '')
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        Copy-Item -LiteralPath $Startup -Destination (Join-Path $dir 'adsys-startup.sh')
        if ($InstallSh) { [System.IO.File]::WriteAllText((Join-Path $dir 'install.sh'), $InstallSh) }
        Join-Path $dir 'adsys-startup.sh'
    }
}

Describe 'adsys-startup.sh --if-new-version (the publish watcher)' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    BeforeAll {
        # New-AdsysCopy VERSION - a fake ADSys copy of SYSVOL: GPT.INI with
        # VERSION (CRLF, as SYSVOL writes it), this adsys-startup.sh in
        # scripts/MOTD, and an install.sh stub there that counts its runs in
        # ROOT/runs and exits with the code in ROOT/exitcode.
        function New-AdsysCopy {
            param([int]$Version)
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            $motd = Join-Path $root 'assets/scripts/MOTD'
            New-Item -ItemType Directory -Path $motd -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'state') | Out-Null
            Set-AdsysVersion $root $Version
            Copy-Item -LiteralPath $Startup -Destination (Join-Path $motd 'adsys-startup.sh')
            [System.IO.File]::WriteAllText((Join-Path $motd 'install.sh'), @'
#!/bin/sh
top=$(dirname "$0")/../../..
echo run >>"$top/runs"
exit "$(cat "$top/exitcode")"
'@)
            [System.IO.File]::WriteAllText((Join-Path $root 'exitcode'), "0`n")
            $root
        }
        function Set-AdsysVersion {
            param([string]$Root, [int]$Version)
            [System.IO.File]::WriteAllText((Join-Path $Root 'assets/GPT.INI'), "[General]`r`nVersion=$Version`r`n")
        }
        # Invoke-Startup ROOT [ARGS] - run the copy's adsys-startup.sh against
        # ROOT's fake copy and state folder; returns its exit code.
        function Invoke-Startup {
            param([string]$Root, [string[]]$Arguments = @())
            & env "MANATECH_ADSYS_ASSETS=$Root/assets" "MANATECH_STATE_DIR=$Root/state" `
                sh (Join-Path $Root 'assets/scripts/MOTD/adsys-startup.sh') @Arguments 2>&1 | Out-Null
            $LASTEXITCODE
        }
        function Get-Runs {
            param([string]$Root)
            $f = Join-Path $Root 'runs'
            if (Test-Path -LiteralPath $f) { @(Get-Content -LiteralPath $f).Count } else { 0 }
        }
        function Get-Installed {
            param([string]$Root)
            $f = Join-Path $Root 'state/installed-version'
            if (Test-Path -LiteralPath $f) { (Get-Content -LiteralPath $f -Raw).Trim() } else { '' }
        }
    }

    It 'installs a Version not installed yet, and records it' {
        $root = New-AdsysCopy 7
        Invoke-Startup $root @('--if-new-version') | Should -Be 0
        Get-Runs $root | Should -Be 1
        Get-Installed $root | Should -Be '7'
    }
    It 'does nothing when the watcher fires again for the same Version' {
        $root = New-AdsysCopy 7
        Invoke-Startup $root @('--if-new-version') | Out-Null
        Invoke-Startup $root @('--if-new-version') | Should -Be 0
        Get-Runs $root | Should -Be 1
    }
    It 'installs again when a publish raises the Version' {
        $root = New-AdsysCopy 7
        Invoke-Startup $root @('--if-new-version') | Out-Null
        Set-AdsysVersion $root 8
        Invoke-Startup $root @('--if-new-version') | Out-Null
        Get-Runs $root | Should -Be 2
        Get-Installed $root | Should -Be '8'
    }
    It 'always installs without --if-new-version (the boot and timer runs)' {
        $root = New-AdsysCopy 7
        Invoke-Startup $root | Out-Null
        Invoke-Startup $root | Out-Null
        Get-Runs $root | Should -Be 2
    }
    It 'keeps the recorded Version when an install fails, so the next trigger tries again' {
        $root = New-AdsysCopy 7
        Invoke-Startup $root @('--if-new-version') | Out-Null
        Set-AdsysVersion $root 8
        [System.IO.File]::WriteAllText((Join-Path $root 'exitcode'), "1`n")
        Invoke-Startup $root @('--if-new-version') | Should -Be 1
        Get-Installed $root | Should -Be '7'
        Invoke-Startup $root @('--if-new-version') | Out-Null
        Get-Runs $root | Should -Be 3
    }
}

Describe 'adsys-startup.sh' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'runs install.sh with --retire --ssh --timer --ad and returns its exit status' {
        $copy = New-StartupCopy "#!/bin/sh`necho `"`$*`" > `"`$(dirname `"`$0`")/args`"`nexit 3`n"
        & sh $copy 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 3
        [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $copy) 'args')).Trim() | Should -Be '--retire --ssh --timer --ad'
    }
    It 'refuses an install.sh with CRLF line endings and says to publish again' {
        $copy = New-StartupCopy "#!/bin/sh`r`nexit 0`r`n"
        $err = & sh $copy 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $err | Should -Match 'CRLF line endings; publish again'
    }
    It 'says where it looked when install.sh is missing' {
        $copy = New-StartupCopy
        $err = & sh $copy 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 1
        $err | Should -Match 'neither in the ADSys cache nor next to'
    }
    It 'logs which install.sh it runs, then that run''s output line by line, in order' {
        $copy = New-StartupCopy "#!/bin/sh`necho first`necho second >&2`nexit 4`n"
        # A logger stub: a message argument, or else each line of its input,
        # appended to BIN/journal.
        $bin = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $bin | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $bin 'logger'), @'
#!/bin/sh
j=$(dirname "$0")/journal
while [ $# -gt 0 ]; do
	case $1 in -t) shift 2 ;; --) shift; break ;; *) break ;; esac
done
if [ $# -gt 0 ]; then echo "$*" >>"$j"; else while IFS= read -r l; do echo "$l" >>"$j"; done; fi
'@)
        & chmod +x (Join-Path $bin 'logger')
        & env "PATH=${bin}:$($env:PATH)" sh $copy 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 4
        $journal = @(Get-Content -LiteralPath (Join-Path $bin 'journal'))
        $journal[0] | Should -Match '^manatech-motd: running .*/install\.sh$'
        $journal[1..2] | Should -Be @('first', 'second')
    }
}
