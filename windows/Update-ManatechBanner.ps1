<#
.SYNOPSIS
Pulls the banner repo and reinstalls the banner files if the commit changed.
What the "Manatech banner update" scheduled task runs, as SYSTEM, daily.

.DESCRIPTION
git pull --ff-only in the checkout this script sits in. If HEAD moved, the
new module is imported from the checkout and rendered with this host's
facts and config first; only if that succeeds does Install-ManatechBanner.ps1
copy the files (never motd.psd1, never the shell or sshd settings). A
failing commit leaves the installed banner as it was. Output goes to
C:\ProgramData\Manatech\update.log.
#>
[CmdletBinding()]
param([string]$Destination = (Join-Path $env:ProgramData 'Manatech'))
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$logFile = Join-Path $Destination 'update.log'
function Write-UpdateLog {
    param([string]$Message)
    $line = '{0:yyyy-MM-dd HH:mm:ss zzz}  {1}' -f (Get-Date), $Message
    Add-Content -LiteralPath $logFile -Value $line
    Write-Output $line
}

$old = (& git.exe -C $repo rev-parse HEAD).Trim()
& git.exe -C $repo pull --ff-only --quiet
if ($LASTEXITCODE -ne 0) { Write-UpdateLog "git pull failed (exit $LASTEXITCODE); nothing changed"; exit 1 }
$new = (& git.exe -C $repo rev-parse HEAD).Trim()
if ($old -eq $new) { Write-UpdateLog "up to date at $new"; exit 0 }

try {
    $share = Join-Path $repo 'rootfs\usr\local\share\manatech'
    $candidate = Import-Module (Join-Path $PSScriptRoot 'ManatechBanner.psm1') -Force -PassThru
    $config = & $candidate { param($d) Get-ManatechConfig -DataPath $d } $Destination
    $fact = & $candidate { param($c) Get-ManatechHostFact -Config $c } $config
    $null = & $candidate { param($f, $c, $s) Format-ManatechBanner -Fact $f -Config $c -DataPath $s } $fact $config $share
} catch {
    Write-UpdateLog "pulled $old -> $new, but it fails to render ($($_.Exception.Message)); installed banner left unchanged"
    exit 1
}

& (Join-Path $PSScriptRoot 'Install-ManatechBanner.ps1') -RepoPath $repo -Destination $Destination
Write-UpdateLog "pulled $old -> $new and installed it"
