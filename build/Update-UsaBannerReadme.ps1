<#
.SYNOPSIS
Writes README.md's command reference from the commands' own help (docs/DECISIONS.md, D27).
.DESCRIPTION
The reference is in the style of learn.microsoft.com's: a jump list, then each command's
synopsis, syntax, description and examples, and each of its parameters with its type, accepted
values, default, and whether it is required, positional or taken from the pipeline. It replaces
what README.md holds between the reference's two markers, and writes only when that differs.

Edit a command's help, not the README, then run this: tests/Docs.Tests.ps1 fails when the two
differ, as -Check does.
.PARAMETER Check
Writes nothing, and stops with an error naming the first line where README.md's reference is
not what the help gives.
.EXAMPLE
pwsh -NoProfile -File build/Update-UsaBannerReadme.ps1
#>
[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $repo 'UsaBanner' 'UsaBanner.psd1') -Force
. (Join-Path $PSScriptRoot 'ReadmeReference.ps1')
$path = Join-Path $repo 'README.md'
$lines = [System.IO.File]::ReadAllLines($path)
$begin = [array]::IndexOf($lines, $ReferenceBegin)
$end = [array]::IndexOf($lines, $ReferenceEnd)
if ($begin -lt 0 -or $end -lt $begin) {
    throw "Update-UsaBannerReadme: README.md has no command reference. Put these two lines where it goes, and run this again:`n$ReferenceBegin`n$ReferenceEnd"
}
$before = @($lines | Select-Object -First $begin)
$after = @($lines | Select-Object -Skip ($end + 1))
$reference = @(New-UsaBannerReference -Preceding $before)
$current = @($lines[$begin..$end])
$differs = $current.Count -ne $reference.Count
for ($i = 0; -not $differs -and $i -lt $reference.Count; $i++) { $differs = $current[$i] -cne $reference[$i] }
if (-not $differs) { return 'README.md''s command reference is what the help gives' }
if ($Check) {
    for ($i = 0; $i -lt [Math]::Max($current.Count, $reference.Count); $i++) {
        if ($i -ge $current.Count -or $i -ge $reference.Count -or $current[$i] -cne $reference[$i]) { break }
    }
    $has = if ($i -lt $current.Count) { "'$($current[$i])'" } else { 'nothing more' }
    $gives = if ($i -lt $reference.Count) { "'$($reference[$i])'" } else { 'nothing more' }
    throw "Update-UsaBannerReadme: README.md's command reference is not what the commands' help gives, first at README.md line $($begin + $i + 1): README.md has $has, the help gives $gives. Run pwsh -NoProfile -File build/Update-UsaBannerReadme.ps1."
}
[System.IO.File]::WriteAllText($path, ((@($before) + $reference + @($after)) -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
"wrote README.md's command reference: $($reference.Count) lines"
