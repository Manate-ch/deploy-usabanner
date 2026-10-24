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
    Test-Json's answer decides: text it calls not valid always has a
    problem here, named by Find-UsaBannerSchemaProblem when Test-Json's own
    records name none (ConfigSchema.ps1 says when).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Json)
    $schema = Get-Content -LiteralPath (Join-Path -Path $script:UsaBannerRoot -ChildPath 'config' -AdditionalChildPath 'usabanner.schema.json') -Raw
    $check = Invoke-UsaBannerSchemaCheck -Json $Json -Schema $schema
    if ($check.Valid) { return }
    $named = @(ConvertFrom-UsaBannerSchemaError -Records $check.Errors)
    # Records that are not about the schema say the text is not JSON at all: there is nothing to look into.
    if (@($named | Where-Object { $_ -notmatch '^(/[^:]*)?: ' }).Count) { return $named }
    $options = [System.Text.Json.JsonDocumentOptions]@{ CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip; AllowTrailingCommas = $true }
    $root = [System.Text.Json.Nodes.JsonNode]::Parse($schema)
    $value = $null
    try { $value = [System.Text.Json.Nodes.JsonNode]::Parse($Json, [System.Text.Json.Nodes.JsonNodeOptions]::new(), $options) }
    catch { return @($named) + @(if (-not $named.Count) { "/: not valid against the schema, though Test-Json does not say why" }) }
    Find-UsaBannerSchemaProblem -Value $value -Schema $root -Root $root
}

function ConvertTo-UsaBannerDataFile {
    <#
    .SYNOPSIS
    A configuration as a PowerShell data file, for the banner after a login
    on Windows to read fast (D2).
    .DESCRIPTION
    In:  a whole configuration, checked (Read-UsaBannerConfig, or
         New-UsaBannerDeployConfig).
    Out: the text of a .psd1: a comment saying where it comes from, then one
         hashtable literal, its keys in the configuration's order, each
         string in single quotes. Only what Import-PowerShellDataFile reads
         as data: strings, whole numbers, $true and $false, @() and @{}. LF
         line ends and a final newline, so the same configuration always
         gives the same bytes.
    Reading it takes no measurable time in a fresh pwsh, where the JSON and
    its schema check take about 100 ms [measured: 7 fresh pwsh 7.6.6 each,
    on a 16-core VM, 2026-10-22].
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $literal = {
        # In:  a value of the configuration, and the indent of its line
        # Out: the value as a data-file literal
        # Why: objects and lists nest, to any depth the schema allows
        param($Value, [string]$Indent)
        if ($Value -is [System.Collections.IDictionary]) {
            if ($Value.Count -eq 0) { return '@{}' }
            $inner = "$Indent    "
            $lines = foreach ($key in $Value.Keys) { "$inner'$(([string]$key).Replace("'", "''"))' = $(& $literal $Value[$key] $inner)" }
            return "@{`n$($lines -join "`n")`n$Indent}"
        }
        if ($Value -is [System.Collections.IList]) {
            if ($Value.Count -eq 0) { return '@()' }
            $inner = "$Indent    "
            $lines = foreach ($item in $Value) { "$inner$(& $literal $item $inner)" }
            return "@(`n$($lines -join "`n")`n$Indent)"
        }
        if ($Value -is [bool]) { if ($Value) { return '$true' } else { return '$false' } }
        if ($Value -is [int] -or $Value -is [long]) { return [string]$Value }
        "'$(([string]$Value).Replace("'", "''"))'"
    }
    "# UsaBanner: this host's configuration, read at each login. Deploy-UsaBanner writes it`n" +
    "# from usabanner.json beside it, and writes it anew at each run: change that one.`n" +
    (& $literal $Config '') + "`n"
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
    A .psd1 is one Deploy-UsaBanner wrote (ConvertTo-UsaBannerDataFile) from
    a configuration it had checked: it is read as data, as it is, without
    the defaults or the schema check, for speed at a login. Its keys come
    back in no set order.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param([Parameter(Mandatory)][string]$Path)
    $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "UsaBanner: there is no configuration file at $full." }
    if ([System.IO.Path]::GetExtension($full) -eq '.psd1') { return Import-PowerShellDataFile -LiteralPath $full }
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
