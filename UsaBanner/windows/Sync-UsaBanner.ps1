<#
.SYNOPSIS
What the "UsaBanner" GPO's scheduled task runs on a Windows Server, as SYSTEM,
from NETLOGON: when a deploy is due, the hand-over from Windows PowerShell 5.1
to pwsh that deploys the banner from the package beside the module.

.DESCRIPTION
The policy (docs/DECISIONS.md, D29) makes an immediate task on the servers it
applies to, run at each policy refresh: every 90 to 120 minutes on a member
server, every 5 minutes on a domain controller. The task's Windows PowerShell
5.1 runs this file:

    \\<domain>\NETLOGON\UsaBanner\UsaBanner\windows\Sync-UsaBanner.ps1

Windows PowerShell 5.1 is the one PowerShell every server has, and the
banner's module needs PowerShell 7. On NETLOGON, beside this file, are the
module folder it sits in (UsaBanner\UsaBanner) and the package
(UsaBanner\usabanner.json), a configuration file of the kind
Deploy-UsaBanner -Path reads. It finds both from its own folder, so it names no
domain.

A deploy is due, and the run's first line in the log says why, when
- no deploy is recorded here yet;
- the package, or a file in the module folder, is not what the last deploy was
  made from (by SHA-256);
- the last deploy was a day ago or more, or is recorded at a time still to
  come: a change made by hand on the host is put right within a day;
- the banner's record (%ProgramData%\UsagiTools\Banner\deploy.json) is gone,
  as after Remove-UsaBanner;
- the old banner is on the host (%ProgramData%\Manatech, or
  %ProgramData%\ssh\manatech-banner.txt): the deploy moves the host off it.
The deploy is SyncDeploy.ps1's, beside this file. When none is due, the run
adds one line to the log and ends, and no pwsh starts.

Why not a deploy at every refresh: with no logging policy set, PowerShell
writes the whole text of a script that holds a word on its list of suspicious
content to its Operational log (event 4104, at Warning). Files of the module
hold such words, and pwsh compiles every one of them at each import, so a
deploy at every refresh would leave a domain controller hours of PowerShell
history, not days (D29). This file holds none of those words, in its code or
its comments (tests\SyncRunner.Tests.ps1 checks it with PowerShell's own
check), so a refresh with nothing to deploy adds nothing to PowerShell's log.
SyncDeploy.ps1 holds them: it is read only for a deploy, and logged then.

The record of the last deploy is sync.stamp, beside the log: the time of the
deploy (UTC), the package's SHA-256, then each module file's with its path in
the module folder. Only a deploy that succeeded writes it, so the refresh after
a failure deploys again.

One run at a time: the named mutex Global\UsaBanner-Sync. A run that finds
another one going says so in the log and ends with 0; the next refresh runs it
again. A run that finds the mutex abandoned (the last run was stopped before it
finished) takes it over, says so, and goes on.

The log is %SystemRoot%\Logs\UsaBanner\sync.log: the last 500 lines of
earlier runs, then this run's. SYSTEM writes it, so it is where no one else
may write: Windows\Logs gives Users read only, while in ProgramData any user
may make files and folders, and could make the log, or a folder of its, before
the first run (both read on a lab Server 2025, 2026-10-23). The record of the
last deploy is there for the same reason: a record any user could write would
let them stop the deploys. Neither is in the banner's own folder,
UsagiTools\Banner: Remove-UsaBanner deletes that folder whole, so a log there
would go with the banner it describes.

Exit codes. 0: the deploy ran, or none was due, or there is no PowerShell 7, or
another run holds the mutex. 1: anything failed, and the log ends with a
"sync FAILED:" line that names the cause and the script line it came from -
which Task Scheduler shows as 0x1 (Last Run Result) or 2147942401 (0x80070001,
the "return code" in the task's History). A failing deploy is reported with the
pwsh it ran in, its exit code and the last line it printed, which is its
error's message on one line.

No preference variable is set at this script's top level: powershell.exe -File
runs a script in the session's global scope, so a top-level
$ErrorActionPreference = 'Stop' would be every function's preference here, and
under Stop, Windows PowerShell 5.1 throws at the first line pwsh writes to
standard error, before this script can log it.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version 3.0

$moduleRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path $moduleRoot 'UsaBanner.psd1'
$package = Join-Path (Split-Path -Parent $moduleRoot) 'usabanner.json'
$dest = Join-Path (Join-Path $env:SystemRoot 'Logs') 'UsaBanner'
$log = Join-Path $dest 'sync.log'
$stamp = Join-Path $dest 'sync.stamp'
$record = Join-Path (Join-Path (Join-Path $env:ProgramData 'UsagiTools') 'Banner') 'deploy.json'
$oldBanner = @((Join-Path $env:ProgramData 'Manatech'), (Join-Path (Join-Path $env:ProgramData 'ssh') 'manatech-banner.txt'))
$keepLines = 500
$mutexName = 'Global\UsaBanner-Sync'
$utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

# Write-SyncLog TEXT - one time-stamped line at the end of the log.
function Write-SyncLog {
    param([string]$Text)
    $line = '{0:yyyy-MM-dd HH:mm:ss zzz}  {1}{2}' -f (Get-Date), $Text, [System.Environment]::NewLine
    [System.IO.File]::AppendAllText($log, $line, $utf8)
}

# Get-SyncFingerprint - what a deploy is made from, as the record's lines: the package's SHA-256,
# then each module file's with its path in the module folder, in ordinal order of the path.
function Get-SyncFingerprint {
    $lines = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $lines.Add('package ' + (Get-FileHash -LiteralPath $package -Algorithm SHA256 -ErrorAction Stop).Hash)
    $skip = $moduleRoot.TrimEnd('\', '/').Length + 1
    $names = [string[]]@(Get-ChildItem -LiteralPath $moduleRoot -Recurse -File -ErrorAction Stop | ForEach-Object { $_.FullName.Substring($skip) })
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
    foreach ($name in $names) {
        $lines.Add((Get-FileHash -LiteralPath (Join-Path $moduleRoot $name) -Algorithm SHA256 -ErrorAction Stop).Hash + ' ' + $name)
    }
    $lines.ToArray()
}

# Read-SyncStamp - the record of the last deploy, as @{ When; Lines }: its time (UTC) and what it was
# made from. Nothing where there is no record; When is empty where its first line cannot be read.
function Read-SyncStamp {
    if (-not [System.IO.File]::Exists($stamp)) { return $null }
    $lines = @([System.IO.File]::ReadAllLines($stamp, $utf8))
    $when = $null
    if ($lines.Count -ge 2 -and $lines[0] -match '^deployed (\S+)$') {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact($Matches[1], 'o', $invariant, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
            $when = $parsed.ToUniversalTime()
        }
    }
    @{ When = $when; Lines = @($lines | Select-Object -Skip 1) }
}

# Get-SyncReason FINGERPRINT LAST - why a deploy is due, in words for the log; nothing when none is.
function Get-SyncReason {
    param([string[]]$Fingerprint, [hashtable]$Last)
    if ($null -eq $Last) { return 'no deploy is recorded here yet' }
    if ($null -eq $Last.When) { return "the record of the last deploy cannot be read: $stamp" }
    $age = [datetime]::UtcNow - $Last.When
    if ($age -lt [timespan]::Zero) { return 'the last deploy is recorded at a time still to come' }
    if ($age -ge [timespan]::FromDays(1)) { return 'the last deploy was a day ago or more' }
    if ($Last.Lines[0] -cne $Fingerprint[0]) { return 'the package changed' }
    if (($Last.Lines -join "`n") -cne ($Fingerprint -join "`n")) { return 'a file in the module folder changed' }
    if (-not [System.IO.File]::Exists($record)) { return "the banner's record is gone: $record" }
    foreach ($old in $oldBanner) {
        if ([System.IO.File]::Exists($old) -or [System.IO.Directory]::Exists($old)) { return "the old banner is on this host: $old" }
    }
}

$exitCode = 0
$mutex = $null
$owned = $false
try {
    # The folder comes before the mutex: a run that finds another one going logs that.
    $null = [System.IO.Directory]::CreateDirectory($dest)
    $mutex = New-Object -TypeName System.Threading.Mutex -ArgumentList $false, $mutexName
    $abandoned = $false
    # An abandoned mutex is thrown as an exception, and this run holds it all the same.
    try { $owned = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $owned = $true; $abandoned = $true }

    if (-not $owned) {
        Write-SyncLog "another run of this sync holds the mutex ${mutexName}: this run ends, and the next policy refresh runs it again"
    }
    else {
        # Only the newest lines stay. Done under the mutex: no other run rewrites the log meanwhile.
        if ([System.IO.File]::Exists($log)) {
            $earlier = @(Get-Content -LiteralPath $log -Encoding UTF8)
            if ($earlier.Count -gt $keepLines) {
                [System.IO.File]::WriteAllLines($log, [string[]]$earlier[($earlier.Count - $keepLines)..($earlier.Count - 1)], $utf8)
            }
        }
        if ($abandoned) {
            Write-SyncLog "the last run of this sync was stopped before it finished, and left the mutex ${mutexName} abandoned: this run took it over"
        }

        $fingerprint = @(Get-SyncFingerprint)
        $last = Read-SyncStamp
        $reason = Get-SyncReason -Fingerprint $fingerprint -Last $last
        if (-not $reason) {
            Write-SyncLog ('nothing to deploy: the package and the module folder are as the deploy of {0} UTC left them, and the banner is in place' -f $last.When.ToString('yyyy-MM-dd HH:mm:ss', $invariant))
        }
        else {
            Write-SyncLog "sync from $moduleRoot, package ${package}: $reason"
            . (Join-Path $PSScriptRoot 'SyncDeploy.ps1')
            if (Invoke-UsaBannerSyncDeploy -Manifest $manifest -Package $package) {
                $made = @('deployed ' + [datetime]::UtcNow.ToString('o', $invariant)) + $fingerprint
                [System.IO.File]::WriteAllLines($stamp, [string[]]$made, $utf8)
                Write-SyncLog 'sync done'
            }
        }
    }
}
catch {
    $at = $_.InvocationInfo
    $where = if ($at -and $at.ScriptName) { " (at $(Split-Path -Leaf $at.ScriptName):$($at.ScriptLineNumber))" } else { '' }
    $why = $_.Exception.Message -replace '\s*\r?\n\s*', ' '
    try { Write-SyncLog "sync FAILED: $why$where" } catch { }
    $exitCode = 1
}
finally {
    if ($owned) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
}
exit $exitCode
