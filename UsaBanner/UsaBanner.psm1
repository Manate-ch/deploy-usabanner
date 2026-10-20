# UsaBanner.psm1 - the loader.
#
# Windows PowerShell 5.1 parses a whole file before it runs any of it, so a
# single PowerShell 7 operator (??, ?:, &&, ||, ?.) anywhere in a file it
# loads stops the import. The files are split by who may load them:
#
#   +-----------------+------------------------+--------------------------+
#   | File            | Loaded by              | Syntax                   |
#   +-----------------+------------------------+--------------------------+
#   | UsaBanner.psm1  | every PowerShell       | 5.1                      |
#   | Bootstrap\*.ps1 | every PowerShell       | 5.1                      |
#   | Public\*.ps1    | every PowerShell       | 5.1; one command a file  |
#   | Private\*.ps1   | PowerShell 7 and later | any                      |
#   | Private\*.cs    | Add-Type, when first   | C#                       |
#   |                 | needed (ImageArt.ps1)  |                          |
#   +-----------------+------------------------+--------------------------+
#
# Under 5.1, each command's begin {} block hands the call to pwsh
# (Bootstrap\Handoff.ps1), and its other blocks then do nothing.
# tests\Loader.Tests.ps1 holds the first three rows to 5.1 syntax, with
# PSScriptAnalyzer's PSUseCompatibleSyntax rule.

Set-StrictMode -Version 3.0

$script:UsaBannerRoot = $PSScriptRoot
$script:UsaBannerManifest = Join-Path $PSScriptRoot 'UsaBanner.psd1'

function Get-UsaBannerLoadOrder {
    # In:  the version of the PowerShell loading the module
    # Out: the folders to dot-source, in order
    # Why: Private\ uses syntax Windows PowerShell 5.1 cannot parse
    param([version]$Version)
    if ($Version.Major -ge 7) { return @('Bootstrap', 'Private', 'Public') }
    @('Bootstrap', 'Public')
}

foreach ($folder in (Get-UsaBannerLoadOrder -Version $PSVersionTable.PSVersion)) {
    $files = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' -File | Sort-Object -Property Name)
    foreach ($file in $files) { . $file.FullName }
}
