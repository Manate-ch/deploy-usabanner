<#
.SYNOPSIS
The deploy Sync-UsaBanner.ps1 runs when one is due: the hand-over from Windows
PowerShell 5.1 to pwsh that runs Deploy-UsaBanner with the package. Read by
Sync-UsaBanner.ps1 with a dot, for Invoke-UsaBannerSyncDeploy; on its own it
does nothing.

.DESCRIPTION
In pwsh it runs

    Import-Module <the module folder>
    Deploy-UsaBanner -Path <the package> -ReplaceOldBanner

-ReplaceOldBanner on every deploy: a host with today's banner moves off it at
the first refresh after today's GPO is taken off the host (D23). The script pwsh
runs is the module's own hand-over script (ConvertTo-UsaBannerHandoffScript, in
Bootstrap\Handoff.ps1): the paths and the switch travel inside it as data, so a
space or a quote in a path cannot break the call. pwsh gets -ExecutionPolicy
Bypass, as the task's own process does: the module's files are on a share, and
a policy of RemoteSigned would refuse them.

Everything the deploy prints is written to the log, with Sync-UsaBanner.ps1's
Write-SyncLog. A deploy that changes nothing prints nothing.

With no PowerShell 7 on the host (%ProgramFiles%\PowerShell\7, then the PATH),
the log says so and the run ends with exit code 0: deploy-usawinssh's policy
installs PowerShell 7, and a later refresh deploys.

This is a file apart from Sync-UsaBanner.ps1 because it holds words on
PowerShell's list of suspicious content (Bypass, EncodedCommand), so Windows
PowerShell writes its whole text to its Operational log (event 4104) each time
it is read: at a deploy, not at every refresh.
#>

. (Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'Bootstrap') 'Handoff.ps1')

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

function Invoke-UsaBannerSyncDeploy {
    # In:  the module's manifest and the package, on the share
    # Out: $true when the deploy ran and succeeded; $false when this host has no PowerShell 7, which
    #      it logs. Throws when the deploy failed, with the deploy's own message.
    param([string]$Manifest, [string]$Package)
    $pwsh = Find-UsaBannerPwsh
    if (-not $pwsh) {
        Write-SyncLog 'PowerShell 7 is not installed on this host, so nothing is deployed: deploy-usawinssh''s policy installs it, and a later policy refresh deploys the banner'
        return $false
    }
    # Invoke-UsaBannerHandoff, which this mirrors, would not do here: it starts pwsh without
    # -ExecutionPolicy Bypass (the module's files are on a share), and its error does not
    # carry the deploy's message, which the "sync FAILED" line needs.
    $handover = ConvertTo-UsaBannerHandoffScript -Command 'Deploy-UsaBanner' -Parameters @{ Path = $Package; ReplaceOldBanner = $true } -Manifest $Manifest -Pwsh $pwsh
    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($guard.Replace('__HANDOVER__', $handover)))   # -EncodedCommand takes UTF-16LE

    # pwsh writes UTF-8 (the hand-over script sets it), and Windows PowerShell
    # decodes a program's output in the console's encoding, the OEM code page: as
    # Invoke-UsaBannerHandoff does, the console reads UTF-8 for the call. A
    # process without a console keeps its encoding.
    $consoleEncoding = $null
    try {
        $consoleEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    }
    catch { $consoleEncoding = $null }
    $lastLine = ''
    $pwshExit = 0
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
    $true
}
