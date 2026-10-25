<#
.SYNOPSIS
What the "UsaBanner" GPO's scheduled task runs on a Windows Server, as SYSTEM,
from NETLOGON: the hand-over from Windows PowerShell 5.1 to pwsh that deploys
the banner from the package beside the module.

.DESCRIPTION
The policy (docs/DECISIONS.md, D29) makes an immediate task on the servers it
applies to, run at each policy refresh:

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File
        \\<domain>\NETLOGON\UsaBanner\UsaBanner\windows\Sync-UsaBanner.ps1

Windows PowerShell 5.1 is the one PowerShell every server has, and the
banner's module needs PowerShell 7: this script finds pwsh and runs the deploy
in it. On NETLOGON, beside this file, are the module folder it sits in
(UsaBanner\UsaBanner) and the package (UsaBanner\usabanner.json), a
configuration file of the kind Deploy-UsaBanner -Path reads. It finds both from
its own folder, so it names no domain.

In pwsh it runs

    Import-Module <the module folder>
    Deploy-UsaBanner -Path <the package> -ReplaceOldBanner

-ReplaceOldBanner on every run: a host with today's banner moves off it at the
first refresh after today's GPO is taken off the host (D23). The script pwsh
runs is the module's own hand-over script (ConvertTo-UsaBannerHandoffScript, in
Bootstrap\Handoff.ps1): the paths and the switch travel inside it as data, so a
space or a quote in a path cannot break the call. pwsh gets -ExecutionPolicy
Bypass, as this script's own process does: the module's files are on a share,
and a policy of RemoteSigned would refuse them.

Everything the deploy prints is written to the log. A deploy that changes
nothing prints nothing, so a refresh adds two lines.

With no PowerShell 7 on the host (the PATH, then %ProgramFiles%\PowerShell\7),
the log says so and the run ends with exit code 0: deploy-usawinssh's policy
installs PowerShell 7, and a later refresh deploys.

One run at a time: the named mutex Global\UsaBanner-Sync. A run that finds
another one going says so in the log and ends with 0; the next refresh runs it
again. A run that finds the mutex abandoned (the last run was stopped before it
finished) takes it over, says so, and goes on.

The log is %SystemRoot%\Logs\UsaBanner\sync.log: the last 500 lines of
earlier runs, then this run's. SYSTEM writes it, so it is where no one else
may write: Windows\Logs gives Users read only, while in ProgramData any user
may make files and folders, and could make the log, or a folder of its, before
the first run (both read on a lab Server 2025, 2026-10-23). It is not in the
banner's own folder, UsagiTools\Banner, either: Remove-UsaBanner deletes that
folder whole, so a log there would go with the banner it describes.

Exit codes. 0: the deploy ran, or there is no PowerShell 7, or another run holds
the mutex. 1: anything failed, and the log ends with a "sync FAILED:" line that
names the cause and the script line it came from - which Task Scheduler shows
as 0x1 (Last Run Result) or 2147942401 (0x80070001, the "return code" in the
task's History). A failing deploy is reported with the pwsh it ran in, its exit
code and the last line it printed, which is its error's message on one line.

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
$keepLines = 500
$mutexName = 'Global\UsaBanner-Sync'
$utf8 = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false

# What pwsh runs: the hand-over script inside a catch. Left to itself, pwsh
# prints an error over several lines, in a layout that changes with its version;
# this prints the message on one line, the last the deploy prints, and ends with
# exit code 1.
$guard = @'
try {
__HANDOVER__
}
catch {
    Write-Output (($_.Exception.Message -replace '\s*\r?\n\s*', ' ').Trim())
    exit 1
}
'@

# Write-SyncLog TEXT - one time-stamped line at the end of the log.
function Write-SyncLog {
    param([string]$Text)
    $line = '{0:yyyy-MM-dd HH:mm:ss zzz}  {1}{2}' -f (Get-Date), $Text, [System.Environment]::NewLine
    [System.IO.File]::AppendAllText($log, $line, $utf8)
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
        Write-SyncLog "sync from $moduleRoot, package $package"
        if ($abandoned) {
            Write-SyncLog "the last run of this sync was stopped before it finished, and left the mutex ${mutexName} abandoned: this run took it over"
        }

        . (Join-Path (Join-Path $moduleRoot 'Bootstrap') 'Handoff.ps1')
        $pwsh = Find-UsaBannerPwsh
        if (-not $pwsh) {
            Write-SyncLog 'PowerShell 7 is not installed on this host, so nothing is deployed: deploy-usawinssh''s policy installs it, and a later policy refresh deploys the banner'
        }
        else {
            # Invoke-UsaBannerHandoff, which this mirrors, would not do here: it starts pwsh without
            # -ExecutionPolicy Bypass (the module's files are on a share), and its error does not
            # carry the deploy's message, which the "sync FAILED" line needs.
            $handover = ConvertTo-UsaBannerHandoffScript -Command 'Deploy-UsaBanner' -Parameters @{ Path = $package; ReplaceOldBanner = $true } -Manifest $manifest -Pwsh $pwsh
            $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($guard.Replace('__HANDOVER__', $handover)))   # -EncodedCommand takes UTF-16LE

            # pwsh writes UTF-8 (the hand-over script sets it), and Windows PowerShell
            # decodes a program's output in the console's encoding, the OEM code page: as
            # Invoke-UsaBannerHandoff does, the console reads UTF-8 for the call. A
            # process without a console keeps its encoding.
            $consoleEncoding = $null
            try {
                $consoleEncoding = [Console]::OutputEncoding
                [Console]::OutputEncoding = $utf8
            }
            catch { $consoleEncoding = $null }
            $lastLine = ''
            try {
                # 2>&1: what pwsh writes to standard error (as text: -OutputFormat Text) reaches the log too.
                & $pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat Text -EncodedCommand $encoded 2>&1 | ForEach-Object {
                    $text = "$_".TrimEnd()
                    if ($text.Trim()) { Write-SyncLog $text; $lastLine = $text.Trim() }
                }
                $pwshExit = $LASTEXITCODE
            }
            finally {
                if ($null -ne $consoleEncoding) { [Console]::OutputEncoding = $consoleEncoding }
            }
            if ($pwshExit -ne 0) {
                $because = if ($lastLine) { ": $lastLine" } else { '' }
                throw "Deploy-UsaBanner failed in PowerShell 7 ($pwsh), exit code ${pwshExit}$because"
            }
            Write-SyncLog 'sync done'
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
