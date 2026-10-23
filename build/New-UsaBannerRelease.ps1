<#
.SYNOPSIS
Builds a release of the module for the update channel (docs/DECISIONS.md, D14).
.DESCRIPTION
Writes UsaBanner-<version>.zip, the module's folder UsaBanner at its root, and
SHA256SUMS beside it, a line for the archive as sha256sum writes it, so
`sha256sum --check SHA256SUMS` passes in that folder. The version is the
manifest's. Upload both files to the release; a host's update channel
downloads them from the address Deploy-UsaBanner -UpdateSource gives it.

An archive already there is not written over: a release, once published,
does not change under the same name.
.PARAMETER OutDir
The folder to write them in; made when missing.
.PARAMETER ModulePath
The module's folder; the repository's UsaBanner by default.
.EXAMPLE
pwsh -NoProfile -File build/New-UsaBannerRelease.ps1 -OutDir ./dist
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutDir,
    [string]$ModulePath = (Join-Path $PSScriptRoot '..' 'UsaBanner')
)
$ErrorActionPreference = 'Stop'
$module = (Resolve-Path -LiteralPath $ModulePath).ProviderPath
if ([System.IO.Path]::GetFileName($module.TrimEnd('/', '\')) -cne 'UsaBanner') { throw "New-UsaBannerRelease: $module is not a folder named UsaBanner: the archive's root folder takes its name." }
$version = (Import-PowerShellDataFile -LiteralPath (Join-Path $module 'UsaBanner.psd1')).ModuleVersion
$out = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutDir)
$null = New-Item -ItemType Directory -Path $out -Force
$name = "UsaBanner-$version.zip"
$zip = Join-Path $out $name
if (Test-Path -LiteralPath $zip) { throw "New-UsaBannerRelease: $zip is there already, and a release does not change under the same name." }
Add-Type -AssemblyName System.IO.Compression.ZipFile
# $true: the archive holds the folder UsaBanner itself, which the update job looks for.
[System.IO.Compression.ZipFile]::CreateFromDirectory($module, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
$sha = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($zip))).ToLowerInvariant()
[System.IO.File]::WriteAllText((Join-Path $out 'SHA256SUMS'), "$sha  $name`n")
$zip
Join-Path $out 'SHA256SUMS'
