#Requires -Version 7.2
<#
.SYNOPSIS
Opens the service picker of the planned Set-UsaBannerService, as a prototype.

.DESCRIPTION
A prototype of the "built in" option of D11 in docs/DECISIONS.md: the
picker from the spec's walk-through (docs/SPEC.md, Appendix A), drawn with
plain VT escape sequences and no other module.

It writes nothing and changes nothing. Where the real cmdlet would save the
services you pick to the banner's config, this prints them and returns
their names.

.PARAMETER Demo
Uses the made-up services of the walk-through instead of this machine's.

.PARAMETER Monitored
The services monitored already when the picker opens. Default: Netlogon and
w32time, as in the walk-through; ssh and cron on Linux without -Demo.

.EXAMPLE
pwsh ./prototype/Select-UsaBannerService.ps1 -Demo

.EXAMPLE
$picked = ./prototype/Select-UsaBannerService.ps1 -Monitored WinRM, sshd
#>
[CmdletBinding()]
param(
    [switch]$Demo,
    [string[]]$Monitored
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or -not $Host.UI.SupportsVirtualTerminal) {
    throw 'The service picker needs an interactive terminal: it reads keys from the keyboard and redraws the screen with VT escape sequences. The planned cmdlet takes names instead (Set-UsaBannerService -Add, docs/SPEC.md 3.6).'
}

Import-Module (Join-Path $PSScriptRoot 'UsaBannerPicker.psm1') -Force

if (-not $PSBoundParameters.ContainsKey('Monitored')) {
    $Monitored = if ($Demo -or $IsWindows) { 'Netlogon', 'w32time' } else { 'ssh', 'cron' }
}

$last = @{ Frame = $null }
$render = {
    param($Frame)
    $last.Frame = $Frame
    # Over the last frame in place: home, each line erased to its end, then
    # the rest of the screen erased. Clearing the whole screen would flicker.
    $text = [System.Text.StringBuilder]::new("`e[H")
    for ($i = 0; $i -lt $Frame.Lines.Count; $i++) {
        $line = $Frame.Lines[$i]
        if ($i -eq $Frame.CursorLine) { $line = "`e[7m$line`e[27m" }
        [void]$text.Append($line).Append("`e[K").Append([Environment]::NewLine)
    }
    [void]$text.Append("`e[J")
    [Console]::Write($text.ToString())
}.GetNewClosure()

$source = Get-PickerServiceSource -Demo:$Demo
# The alternate screen leaves the terminal's scrollback as it was, and the
# cursor is hidden while the picker draws. Ctrl+C arrives as a key, which
# cancels: PowerShell cannot stop a script that is waiting in ReadKey.
$controlCWas = [Console]::TreatControlCAsInput
[Console]::Write("`e[?1049h`e[?25l")
try {
    [Console]::TreatControlCAsInput = $true
    $result = Invoke-ServicePicker -Monitored $Monitored -Source $source -ReadKey { [Console]::ReadKey($true) } -Render $render
} finally {
    [Console]::TreatControlCAsInput = $controlCWas
    [Console]::Write("`e[?25h`e[?1049l")
}

# The last frame, saved or cancelled, stays on the normal screen.
foreach ($line in $last.Frame.Lines) { [Console]::WriteLine($line) }
if ($result.Saved) {
    [Console]::WriteLine("(Prototype: nothing was written. Set-UsaBannerService would save this list to the banner's config.)")
    $result.Services
}
