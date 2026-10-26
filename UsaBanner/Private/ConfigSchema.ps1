# ConfigSchema.ps1 - naming each problem the schema check finds in a
# configuration, by where it is (Test-UsaBannerConfig, in Config.ps1).
#
# Test-Json's answer decides whether a configuration is valid. Its error
# records name the problems, but not always every one: PowerShell 7.6.8's
# Test-Json answers false for a problem below the top of the schema (under a
# $ref, inside a list, in an object within an object) and writes no record
# for it, where 7.6.6 named every one (measured 2026-10-24). So where it names
# nothing, each part of the configuration is checked again against its own
# part of the schema, from the top down, until it does.
#
# Find-UsaBannerSchemaProblem, which PowerShell logs whole at each import, is
# in ConfigSchema.Logged.ps1 (docs/DECISIONS.md, D30).

function Invoke-UsaBannerSchemaCheck {
    # In:  JSON text, and a schema's text
    # Out: @{ Valid; Errors }: Test-Json's answer, and the error records it
    #      wrote
    # Why: the one place Test-Json runs, so the tests can stand in for
    #      another PowerShell's
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Json, [Parameter(Mandatory)][string]$Schema)
    $records = @()
    $valid = Test-Json -Json $Json -Schema $Schema -ErrorVariable records -ErrorAction SilentlyContinue
    @{ Valid = [bool]$valid; Errors = @($records) }
}

function ConvertFrom-UsaBannerSchemaError {
    <#
    .SYNOPSIS
    Test-Json's error records as '<where>: <what is wrong>'.
    .DESCRIPTION
    In:  the records, and the JSON pointer of the part that was checked:
         '' for a whole configuration, /vlans/0 for one VLAN.
    Out: a line each. <where> is the pointer of the problem in the whole
         configuration. "All values fail against the false schema", which is
         how Test-Json words a key the schema does not have, becomes "not a
         setting UsaBanner knows". A record in any other shape, as for text
         that is not JSON, is its own message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyCollection()][object[]]$Records = @(), [string]$At = '')
    foreach ($record in $Records) {
        $text = $record.ToString()
        if ($text -match "^The JSON is not valid with the schema: (?<what>.*) at '(?<where>[^']*)'$") {
            $what = if ($Matches.what -like 'All values fail against the false schema*') { 'not a setting UsaBanner knows' } else { $Matches.what }
            "$At$($Matches.where): $what"
        }
        else { $text }
    }
}

function Resolve-UsaBannerSchemaRef {
    <#
    .SYNOPSIS
    A part of the schema with the $ref at its top taken in.
    .DESCRIPTION
    In:  the part (a JSON object node), and the whole schema.
    Out: a copy of the part: what its $ref points at in the schema's $defs,
         with the part's own keywords over it, as company's maxLength over
         the ascii definition. A $ref that is not into $defs stays as it is.
    #>
    [CmdletBinding()]
    [OutputType([System.Text.Json.Nodes.JsonObject])]
    param(
        [Parameter(Mandatory)][System.Text.Json.Nodes.JsonObject]$Node,
        [Parameter(Mandatory)][System.Text.Json.Nodes.JsonObject]$Root
    )
    $result = $Node.DeepClone()
    # A definition may point at another; eight steps is far more than the schema uses.
    for ($step = 0; $step -lt 8 -and $result.ContainsKey('$ref'); $step++) {
        $ref = $result['$ref'].GetValue[string]()
        if ($ref -notmatch '^#/\$defs/(?<name>[^/]+)$' -or -not $Root['$defs'] -or -not $Root['$defs'][$Matches.name]) { break }
        $merged = $Root['$defs'][$Matches.name].DeepClone()
        foreach ($pair in $result) {
            if ($pair.Key -ne '$ref') { $merged[$pair.Key] = $(if ($null -eq $pair.Value) { $null } else { $pair.Value.DeepClone() }) }
        }
        $result = $merged
    }
    # A JSON object is a list of its fields to PowerShell: the comma returns it whole.
    , $result
}
