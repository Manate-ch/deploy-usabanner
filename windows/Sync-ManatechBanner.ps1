<#
.SYNOPSIS
What the "Manatech MOTD" GPO's scheduled task runs, as SYSTEM, from NETLOGON.

.DESCRIPTION
Runs Install-ManatechBanner.ps1 from the published copy it sits in
(\\<domain>\NETLOGON\MOTD\windows\, written by Publish-ManatechMotd.ps1)
with the settings every domain Windows host gets: the AD Description
refreshed, the render check, files and profile block, and - where the
OpenSSH Server is set up - a PowerShell as its default shell and the
pre-login banner. A host without OpenSSH gets the rest and one line saying
so; that is not a failure.

The default shell is -DefaultShell any: a PowerShell already set there
(Windows PowerShell or PowerShell 7) is kept, and only another shell
(cmd.exe) becomes Windows PowerShell. So where the OpenSSH Server GPO sets
pwsh, this sync leaves it, and the two never take turns.

Everything it prints is appended to C:\ProgramData\Manatech\sync.log. A
failure ends with a "sync FAILED:" line naming the cause and the script line
it came from, and exit code 1 - which Task Scheduler shows as 0x1 (Last Run
Result) or 2147942401 (0x80070001, the "return code" in the task's History).

The task repeats every 4 hours, so a publish or an edited AD Description
shows up without a reboot. A new banner only replaces the old one after it
has rendered on this host.

sshd is not restarted here: a changed pre-login banner takes effect at the
next sshd restart (reboot, or Restart-Service sshd).

No preference variable is set at this script's top level: powershell.exe
-File runs a script in the session's global scope, so a top-level
$ErrorActionPreference = 'Stop' here would also become the preference of
every module function the install calls.
#>
[CmdletBinding()]
param([ValidateSet('keep', 'any', 'powershell', 'pwsh')][string]$DefaultShell = 'any')
Set-StrictMode -Version 3.0

$dest = Join-Path $env:ProgramData 'Manatech'
$log = Join-Path $dest 'sync.log'
$repo = Split-Path -Parent $PSScriptRoot

# Write-SyncLog TEXT - one time-stamped line in sync.log.
function Write-SyncLog {
    param([string]$Text)
    Add-Content -LiteralPath $log -Value ('{0:yyyy-MM-dd HH:mm:ss zzz}  {1}' -f (Get-Date), $Text) -ErrorAction Stop
}

try {
    if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -ErrorAction Stop | Out-Null }
    Write-SyncLog "sync from $repo"

    # sshd writes sshd_config the first time it starts; until then there is
    # no OpenSSH Server here to give a default shell or a banner.
    $ssh = @{ DefaultShell = $DefaultShell; SshBanner = $true }
    $sshdConfig = Join-Path (Join-Path $env:ProgramData 'ssh') 'sshd_config'
    if (-not (Test-Path -LiteralPath $sshdConfig)) {
        $ssh = @{ DefaultShell = 'keep'; SshBanner = $false }
        Write-SyncLog "OpenSSH Server is not set up on this host (no $sshdConfig): default shell and pre-login banner skipped"
    }

    & (Join-Path $PSScriptRoot 'Install-ManatechBanner.ps1') -RepoPath $repo -AdDescription @ssh *>&1 |
        ForEach-Object { Write-SyncLog "$_" }
    Write-SyncLog 'sync done'
} catch {
    $at = $_.InvocationInfo
    $where = if ($at -and $at.ScriptName) { " (at $(Split-Path -Leaf $at.ScriptName):$($at.ScriptLineNumber))" } else { '' }
    try { Write-SyncLog "sync FAILED: $($_.Exception.Message)$where" } catch { }
    exit 1
}
