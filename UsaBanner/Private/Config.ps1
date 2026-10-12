# Config.ps1 - a host's configuration: one JSON file, checked against
# config\usabanner.schema.json, with config\defaults.json for every key the
# file leaves out.

function Get-UsaBannerConfigDefault {
    <#
    .SYNOPSIS
    The default configuration, config\defaults.json, as an ordered hashtable.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param()
    Get-Content -LiteralPath (Join-Path -Path $script:UsaBannerRoot -ChildPath 'config' -AdditionalChildPath 'defaults.json') -Raw | ConvertFrom-Json -AsHashtable
}

function Merge-UsaBannerConfig {
    <#
    .SYNOPSIS
    A configuration with every key a file leaves out taken from the defaults.
    .DESCRIPTION
    In:  the defaults, and the settings a file holds.
    Out: a new ordered dictionary: the defaults' keys in their order, then
         any other keys of the file in its order.
    Objects merge key by key, at any depth; a list or a single value
    replaces the default whole. Keys compare by exact character code, as in
    JSON: "IP" is not "ip", so a mistyped key reaches the schema check
    instead of quietly replacing a default.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Default,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Value
    )
    $merged = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    foreach ($key in $Default.Keys) {
        if (-not $Value.Contains($key)) { $merged[$key] = $Default[$key] }
        elseif ($Default[$key] -is [System.Collections.IDictionary] -and $Value[$key] -is [System.Collections.IDictionary]) {
            $merged[$key] = Merge-UsaBannerConfig -Default $Default[$key] -Value $Value[$key]
        }
        else { $merged[$key] = $Value[$key] }
    }
    foreach ($key in $Value.Keys) {
        if (-not $merged.Contains($key)) { $merged[$key] = $Value[$key] }
    }
    $merged
}

function ConvertTo-UsaBannerConfigJson {
    <#
    .SYNOPSIS
    A configuration as the text of its file.
    .DESCRIPTION
    JSON indented by two spaces, LF line ends, and a final newline: the same
    configuration always gives the same bytes, so a file diffs cleanly.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    # -Depth 10: the default of 2 would flatten the VLAN rows into strings.
    ((ConvertTo-Json -InputObject $Config -Depth 10) -replace "`r`n", "`n") + "`n"
}

function Test-UsaBannerConfig {
    <#
    .SYNOPSIS
    Checks configuration text against config\usabanner.schema.json; returns
    each problem as '<where>: <what is wrong>'.
    .DESCRIPTION
    Out: nothing when it is valid. <where> is a JSON pointer, such as
    /vlans/0/tag. Test-Json words a key the schema does not have as "All
    values fail against the false schema"; that one becomes "not a setting
    UsaBanner knows". Text that is not JSON gives Test-Json's own message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Json)
    $schema = Get-Content -LiteralPath (Join-Path -Path $script:UsaBannerRoot -ChildPath 'config' -AdditionalChildPath 'usabanner.schema.json') -Raw
    $found = @()
    $null = Test-Json -Json $Json -Schema $schema -ErrorVariable found -ErrorAction SilentlyContinue
    foreach ($record in $found) {
        $text = $record.ToString()
        if ($text -match "^The JSON is not valid with the schema: (?<what>.*) at '(?<where>[^']*)'$") {
            $what = if ($Matches.what -like 'All values fail against the false schema*') { 'not a setting UsaBanner knows' } else { $Matches.what }
            "$($Matches.where): $what"
        }
        else { $text }
    }
}

function Read-UsaBannerConfig {
    <#
    .SYNOPSIS
    Reads a configuration file: its settings over the defaults, checked.
    .DESCRIPTION
    In:  a path; a relative one is taken from PowerShell's location.
    Out: the whole configuration, as an ordered dictionary.
    Throws when the file is missing, is not JSON, holds no JSON object, or
    when the merged configuration breaks the schema; the message lists every
    problem.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)][string]$Path)
    $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "UsaBanner: there is no configuration file at $full." }
    try { $value = Get-Content -LiteralPath $full -Raw | ConvertFrom-Json -AsHashtable }
    catch { throw "UsaBanner: $full is not JSON: $($_.Exception.Message)" }
    if ($value -isnot [System.Collections.IDictionary]) { throw "UsaBanner: $full holds no JSON object." }
    $config = Merge-UsaBannerConfig -Default (Get-UsaBannerConfigDefault) -Value $value
    $problems = @(Test-UsaBannerConfig -Json (ConvertTo-UsaBannerConfigJson -Config $config))
    if ($problems.Count -gt 0) { throw ("UsaBanner: $full is not a valid configuration:`n  " + ($problems -join "`n  ")) }
    $config
}

function Write-UsaBannerConfig {
    <#
    .SYNOPSIS
    Checks a configuration, then writes it to a file.
    .DESCRIPTION
    In:  the configuration, and a path; a relative one is taken from
         PowerShell's location, not the process's current directory, which
         .NET would use and which PowerShell does not move.
    The text is ConvertTo-UsaBannerConfigJson's, in UTF-8 without a byte
    order mark. The file is written whole or not at all: <path>.tmp first,
    then moved over the old file. Throws on a configuration that breaks the
    schema, and writes nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][string]$Path
    )
    $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    $json = ConvertTo-UsaBannerConfigJson -Config $Config
    $problems = @(Test-UsaBannerConfig -Json $json)
    if ($problems.Count -gt 0) { throw ("UsaBanner: not writing $full, the configuration is not valid:`n  " + ($problems -join "`n  ")) }
    $temp = "$full.tmp"
    [System.IO.File]::WriteAllText($temp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temp -Destination $full -Force
}
