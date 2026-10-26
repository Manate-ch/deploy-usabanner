# ConfigSchema.Logged.ps1 - the functions of ConfigSchema.ps1 that PowerShell logs whole at each import (D30).

function Find-UsaBannerSchemaProblem {
    <#
    .SYNOPSIS
    The problems Test-Json finds in a part of a configuration, each named by
    where it is, looking further in where Test-Json names none.
    .DESCRIPTION
    In:  the part (a JSON node, or $null for JSON's null), the part of the
         schema that describes it, the whole schema (for its $schema and
         $defs), and where the part is, as a JSON pointer ('' for the whole).
    Out: '<where>: <what is wrong>' each, nothing when the part is valid.
         The part is checked against its schema, a $ref at the top taken in.
         Each problem named is kept. Each field of an object and each item
         of a list that has its own schema, and no problem named at or under
         it, is checked the same way. A part that is not valid, where nothing
         is named all the way down, is named by where it is: no problem goes
         unreported.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][System.Text.Json.Nodes.JsonNode]$Value,
        [Parameter(Mandatory)][System.Text.Json.Nodes.JsonObject]$Schema,
        [Parameter(Mandatory)][System.Text.Json.Nodes.JsonObject]$Root,
        [string]$At = ''
    )
    $part = Resolve-UsaBannerSchemaRef -Node $Schema -Root $Root
    foreach ($key in '$schema', '$defs') {
        if ($Root.ContainsKey($key) -and -not $part.ContainsKey($key)) { $part[$key] = $Root[$key].DeepClone() }
    }
    $text = if ($null -eq $Value) { 'null' } else { $Value.ToJsonString() }
    $check = Invoke-UsaBannerSchemaCheck -Json $text -Schema $part.ToJsonString()
    if ($check.Valid) { return }
    $named = @(ConvertFrom-UsaBannerSchemaError -Records $check.Errors -At $At)
    $named

    $children = @(
        if ($Value -is [System.Text.Json.Nodes.JsonObject] -and $part['properties'] -is [System.Text.Json.Nodes.JsonObject]) {
            foreach ($pair in $Value) {
                $own = $part['properties'][$pair.Key]
                if ($own -is [System.Text.Json.Nodes.JsonObject]) { @{ Value = $pair.Value; Schema = $own; At = "$At/$($pair.Key)" } }
            }
        }
        elseif ($Value -is [System.Text.Json.Nodes.JsonArray] -and $part['items'] -is [System.Text.Json.Nodes.JsonObject]) {
            for ($i = 0; $i -lt $Value.Count; $i++) { @{ Value = $Value[$i]; Schema = $part['items']; At = "$At/$i" } }
        }
    )
    $deeper = @(foreach ($child in $children) {
        $covered = @($named | Where-Object { $_.StartsWith("$($child.At):") -or $_.StartsWith("$($child.At)/") }).Count
        if (-not $covered) { Find-UsaBannerSchemaProblem -Value $child.Value -Schema $child.Schema -Root $Root -At $child.At }
    })
    $deeper
    if (-not $named.Count -and -not $deeper.Count) {
        "$(if ($At) { $At } else { '/' }): not valid against the schema, though Test-Json does not say why"
    }
}
