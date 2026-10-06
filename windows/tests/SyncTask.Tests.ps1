# Pester 5 tests for Sync-ManatechBanner.ps1, the GPO task's script. Each test
# runs it the way the task does - a new PowerShell process with -File - next to
# an Install-ManatechBanner.ps1 stub, with ProgramData pointed at a scratch
# folder. (In the lab the real thing ran as SYSTEM on Server 2025.)

BeforeAll {
    $script:SyncSrc = Join-Path $PSScriptRoot '../Sync-ManatechBanner.ps1'
    $script:Pwsh = (Get-Process -Id $PID).Path

    # New-SyncCopy INSTALL [-Sshd] - a published copy: MOTD/windows holding
    # this Sync-ManatechBanner.ps1 and an Install-ManatechBanner.ps1 whose text
    # is INSTALL, and an empty ProgramData (with ssh/sshd_config for -Sshd).
    function New-SyncCopy {
        param([string]$Install, [switch]$Sshd)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $win = Join-Path (Join-Path $root 'MOTD') 'windows'
        New-Item -ItemType Directory -Path $win -Force | Out-Null
        Copy-Item -LiteralPath $SyncSrc -Destination (Join-Path $win 'Sync-ManatechBanner.ps1')
        [System.IO.File]::WriteAllText((Join-Path $win 'Install-ManatechBanner.ps1'), $Install)
        $pd = Join-Path $root 'ProgramData'
        New-Item -ItemType Directory -Path $pd | Out-Null
        if ($Sshd) {
            New-Item -ItemType Directory -Path (Join-Path $pd 'ssh') | Out-Null
            [System.IO.File]::WriteAllText((Join-Path (Join-Path $pd 'ssh') 'sshd_config'), "# sshd`n")
        }
        [pscustomobject]@{
            Sync        = Join-Path $win 'Sync-ManatechBanner.ps1'
            ProgramData = $pd
            Log         = Join-Path (Join-Path $pd 'Manatech') 'sync.log'
            Record      = Join-Path $pd 'install-record.txt'
        }
    }
    # Invoke-Sync COPY - run the copy's Sync-ManatechBanner.ps1 as the task
    # does; its exit code.
    function Invoke-Sync {
        param($Copy)
        & env "ProgramData=$($Copy.ProgramData)" $Pwsh -NoProfile -NonInteractive -File $Copy.Sync *>&1 | Out-Null
        $LASTEXITCODE
    }

    # An install stub that records how it was called, and what preference a
    # module function sees inside it.
    $script:Recorder = @'
param([string]$RepoPath, [string]$DefaultShell, [switch]$SshBanner, [switch]$AdDescription)
New-Module -Name RecorderProbe -ScriptBlock { function Get-ProbePreference { $ErrorActionPreference } } | Import-Module
"DefaultShell=$DefaultShell SshBanner=$SshBanner AdDescription=$AdDescription ModuleSees=$(Get-ProbePreference)" |
    Set-Content -LiteralPath (Join-Path $env:ProgramData 'install-record.txt')
Write-Host 'stub install ran'
'@
}

Describe 'Sync-ManatechBanner.ps1' {
    It 'logs the run and hands the install the OpenSSH settings where OpenSSH Server is set up' {
        $c = New-SyncCopy $Recorder -Sshd
        Invoke-Sync $c | Should -Be 0
        (Get-Content -LiteralPath $c.Record -Raw) | Should -Match 'DefaultShell=any SshBanner=True AdDescription=True'
        $log = Get-Content -LiteralPath $c.Log -Raw
        $log | Should -Match 'sync from .*MOTD'
        $log | Should -Match 'stub install ran'
        $log | Should -Match 'sync done'
    }
    It 'skips the OpenSSH settings where OpenSSH Server is not set up, and says so - not a failure' {
        $c = New-SyncCopy $Recorder
        Invoke-Sync $c | Should -Be 0
        (Get-Content -LiteralPath $c.Record -Raw) | Should -Match 'DefaultShell=keep SshBanner=False AdDescription=True'
        Get-Content -LiteralPath $c.Log -Raw | Should -Match 'OpenSSH Server is not set up on this host'
    }
    It 'exits 1, and names the cause and the script line, when the install fails' {
        $c = New-SyncCopy "param([string]`$RepoPath, [string]`$DefaultShell, [switch]`$SshBanner, [switch]`$AdDescription)`n`nthrow 'render failed: No User exists for *'`n" -Sshd
        Invoke-Sync $c | Should -Be 1
        Get-Content -LiteralPath $c.Log -Raw | Should -Match 'sync FAILED: render failed: No User exists for \* \(at Install-ManatechBanner\.ps1:3\)'
    }
    It 'leaves the preference module functions see at the session default (Continue)' {
        $c = New-SyncCopy $Recorder -Sshd
        Invoke-Sync $c | Should -Be 0
        (Get-Content -LiteralPath $c.Record -Raw) | Should -Match 'ModuleSees=Continue'
    }
    It 'positive control: a -File script that sets Stop at its top level hands it to every module function' {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        $probe = Join-Path $dir 'probe.ps1'
        $out = Join-Path $dir 'seen.txt'
        [System.IO.File]::WriteAllText($probe, @"
`$ErrorActionPreference = 'Stop'
New-Module -Name FileScopeProbe -ScriptBlock { function Get-ProbePreference { `$ErrorActionPreference } } | Import-Module
Get-ProbePreference | Set-Content -LiteralPath '$out'
"@)
        & $Pwsh -NoProfile -NonInteractive -File $probe *>&1 | Out-Null
        (Get-Content -LiteralPath $out -Raw).Trim() | Should -Be 'Stop'
    }
}
