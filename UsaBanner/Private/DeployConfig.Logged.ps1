# DeployConfig.Logged.ps1 - the functions of DeployConfig.ps1 that PowerShell logs whole at each import (D30).

function Get-UsaBannerSchemaEnum {
    <#
    .SYNOPSIS
    The values the schema allows a setting, when it lists them.
    .DESCRIPTION
    In:  a setting's path, such as color.mode.
    Out: the schema's enum for it, in the schema's own spelling; nothing for
         a setting that is not one of a list.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Setting)
    $schema = Get-Content -LiteralPath (Join-Path -Path $script:UsaBannerRoot -ChildPath 'config' -AdditionalChildPath 'usabanner.schema.json') -Raw | ConvertFrom-Json -AsHashtable
    $node = $schema
    foreach ($part in $Setting.Split('.')) {
        if (-not ($node.Contains('properties') -and $node['properties'].Contains($part))) { return }
        $node = $node['properties'][$part]
    }
    if ($node.Contains('enum')) { [string[]]$node['enum'] }
}

function Read-UsaBannerVlanFile {
    <#
    .SYNOPSIS
    The VLAN table from a CSV or TSV file.
    .DESCRIPTION
    In:  a path; a relative one is taken from PowerShell's location. The
         first line names the columns: name, tag and cidr, then color and
         short (the VLAN's name in the badge) where wanted, in any order and
         any case. Fields are separated by tabs when the first line holds
         one, else by commas, and may be quoted as in CSV. Spaces around a
         field are dropped, as a file written by hand has them after its
         commas.
    Out: a row each, as the configuration's vlans hold it: name, tag (a
         number), cidr, then color and short where the row gives them.
    Throws when the file is missing or holds no rows, when a column the
    table needs is missing or one it does not know is there, and on a tag
    that is not a whole number. The schema check of the configuration names
    anything else wrong, by row.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)][string]$Path)
    $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "UsaBanner: there is no VLAN file at $full." }
    $header = @(Get-Content -LiteralPath $full -TotalCount 1)
    $delimiter = if ($header.Count -and $header[0].Contains("`t")) { "`t" } else { ',' }
    $rows = @(Import-Csv -LiteralPath $full -Delimiter $delimiter)
    if ($rows.Count -eq 0) { throw "UsaBanner: $full holds no VLANs: its first line names the columns (name, tag, cidr; color and short where wanted), and each line after it is a VLAN." }
    # The column each name is under, whatever its case and the spaces around it.
    $columns = @{}
    foreach ($column in $rows[0].PSObject.Properties.Name) { $columns[$column.Trim()] = $column }
    $unknown = @($columns.Keys | Where-Object { $_ -notin $script:UsaVlanColumns } | Sort-Object)
    if ($unknown.Count) { throw "UsaBanner: $full has a column UsaBanner does not know: $($unknown -join ', '). The columns are $($script:UsaVlanColumns -join ', ')." }
    $missing = @('name', 'tag', 'cidr' | Where-Object { -not $columns.ContainsKey($_) })
    if ($missing.Count) { throw "UsaBanner: $full has no $($missing -join ', ') column: each VLAN needs a name, a tag and a cidr." }
    $line = 1
    foreach ($row in $rows) {
        $line++
        $field = @{}
        foreach ($name in $script:UsaVlanColumns) {
            $field[$name] = if ($columns.ContainsKey($name)) { ([string]$row.($columns[$name])).Trim() } else { '' }
        }
        $tag = 0
        if (-not [int]::TryParse($field['tag'], [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$tag)) {
            throw "UsaBanner: $full, line ${line}: the tag '$($field['tag'])' is not a whole number."
        }
        $vlan = [ordered]@{ name = $field['name']; tag = $tag; cidr = $field['cidr'] }
        foreach ($optional in 'color', 'short') {
            if ($field[$optional]) { $vlan[$optional] = $field[$optional] }
        }
        $vlan
    }
}
