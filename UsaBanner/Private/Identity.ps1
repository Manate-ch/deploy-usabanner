# Identity.ps1 - who a host is, as the banner after login shows it: its name
# decoded by the naming standard (docs/DECISIONS.md, D20), the VLAN its
# address is in, and its tier (SPEC 5.4), each drawn in a named colour.
#
#   +---------+----------------------------------------------------------+
#   | Table   | Where it is                                              |
#   +---------+----------------------------------------------------------+
#   | naming  | the configuration: sites, types, subtypes and os, each a |
#   |         | list of rows with a code, a name and a colour            |
#   | vlans   | the configuration: name, tag and network, and a colour   |
#   |         | and a short name for the badge                           |
#   | colours | here: the names a row may give, as today's colors.tsv    |
#   | tiers   | here: each tier's colour, as today's envs.tsv, and what  |
#   |         | the tier is for                                          |
#   +---------+----------------------------------------------------------+

# Each named colour in 24-bit, and as the nearest of the 16 basic colours.
# Black is drawn as charcoal: true black vanishes on a dark terminal.
$script:UsaNamedColors = [ordered]@{
    'Pink'    = @{ Hex = '#F082B4'; Basic = 'bright-magenta' }
    'White'   = @{ Hex = '#EBEBEB'; Basic = 'bright-white' }
    'Beige'   = @{ Hex = '#DCC8A0'; Basic = 'white' }
    'Grey'    = @{ Hex = '#8C919B'; Basic = 'bright-black' }
    'Black'   = @{ Hex = '#46464E'; Basic = 'bright-black' }
    'Red'     = @{ Hex = '#E14646'; Basic = 'red' }
    'Green'   = @{ Hex = '#5ABE6E'; Basic = 'green' }
    'Blue'    = @{ Hex = '#508CE6'; Basic = 'blue' }
    'Yellow'  = @{ Hex = '#F0D246'; Basic = 'bright-yellow' }
    'Orange'  = @{ Hex = '#F08C32'; Basic = 'yellow' }
    'Purple'  = @{ Hex = '#966EDC'; Basic = 'magenta' }
    'L.Green' = @{ Hex = '#96D25A'; Basic = 'bright-green' }
    'Teal'    = @{ Hex = '#28B4B4'; Basic = 'cyan' }
    'Gold'    = @{ Hex = '#DCAA28'; Basic = 'yellow' }
    'Brown'   = @{ Hex = '#A06E46'; Basic = 'yellow' }
}

# The tiers in the schema's order, each with its colour and the few words
# SPEC 5.4 gives for what it holds.
$script:UsaTiers = [ordered]@{
    'UNSET'    = @{ Color = 'Grey'; Meaning = 'not set yet' }
    'DEV-TEST' = @{ Color = 'Black'; Meaning = 'sandbox and development' }
    'LAB'      = @{ Color = 'Orange'; Meaning = 'larger-scale testing' }
    'PROD'     = @{ Color = 'Blue'; Meaning = 'production' }
    'PUB'      = @{ Color = 'Pink'; Meaning = 'public-facing' }
}

function Get-UsaBannerNamedColor {
    <#
    .SYNOPSIS
    A named colour, in 24-bit and as its nearest basic colour.
    .DESCRIPTION
    In:  a name from the schema's colour list, such as Teal.
    Out: @{ Hex; Basic }. Throws on a name that is not one, listing them.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:UsaNamedColors.Contains($Name)) { throw "UsaBanner: '$Name' is not a named colour; there is $($script:UsaNamedColors.Keys -join ', ')." }
    $script:UsaNamedColors[$Name]
}

function Get-UsaBannerTier {
    <#
    .SYNOPSIS
    A tier's colour, and what the tier holds.
    .DESCRIPTION
    In:  a tier from the schema's environment list, such as PROD.
    Out: @{ Color; Meaning }: a named colour, and a few words such as
         'production'. Throws on a tier that is not one, listing them.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Name)
    if (-not $script:UsaTiers.Contains($Name)) { throw "UsaBanner: '$Name' is not a tier; there is $($script:UsaTiers.Keys -join ', ')." }
    $script:UsaTiers[$Name]
}

function Resolve-UsaBannerHostName {
    <#
    .SYNOPSIS
    A host name decoded by the naming standard (D20).
    .DESCRIPTION
    In:  a host name, short or fully qualified, in any case, and the
         configuration's naming table.
    Out: @{ Codes; Rows; Decoded; Site }, or $null for a name outside the
         standard:
         - Codes: the site, type, subtype and os codes, as the name has
           them, in lower case;
         - Rows: each code's row in the table, the site's $null when the
           table lacks it;
         - Decoded: the rows' names joined by ' / ', as
           'HQ / Virtual / Server / Linux', with ? for a site the table
           lacks;
         - Site: the site's name, or '' when the table lacks it.
    A name is in the standard when it is <site:2><type><subtype><os>-, then
    anything, then a digit, and its type, subtype and OS are all in the
    table. A name with only the shape, such as proxy-01, is not decoded:
    most names a public tool meets follow some other standard. Where a list
    has a code twice, its first row counts.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Naming
    )
    $short = ($Name -split '\.')[0].ToLowerInvariant()
    if ($short -cnotmatch '^([a-z0-9][a-z0-9-])([a-z0-9])([a-z0-9])([a-z0-9])-.*[0-9]$') { return $null }
    $codes = [ordered]@{ site = $Matches[1]; type = $Matches[2]; subtype = $Matches[3]; os = $Matches[4] }
    $lists = @{ site = 'sites'; type = 'types'; subtype = 'subtypes'; os = 'os' }
    $rows = [ordered]@{}
    foreach ($field in $codes.Keys) {
        $rows[$field] = $null
        foreach ($row in @($Naming[$lists[$field]])) {
            if ($row -and [string]$row['code'] -ceq $codes[$field]) { $rows[$field] = $row; break }
        }
    }
    if (-not ($rows['type'] -and $rows['subtype'] -and $rows['os'])) { return $null }
    $names = foreach ($field in $codes.Keys) { if ($rows[$field]) { [string]$rows[$field]['name'] } else { '?' } }
    @{
        Codes   = $codes
        Rows    = $rows
        Decoded = $names -join ' / '
        Site    = $(if ($rows['site']) { [string]$rows['site']['name'] } else { '' })
    }
}

function Find-UsaBannerVlan {
    <#
    .SYNOPSIS
    The VLAN an IPv4 address is in.
    .DESCRIPTION
    In:  an address, as 10.20.40.80, and the configuration's VLAN rows.
    Out: the row whose network holds the address, the longest prefix
         winning where networks nest; $null for none, and for an address
         that is not four dotted numbers.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [AllowEmptyString()][string]$Address,
        [object[]]$Vlans = @()
    )
    $toNumber = {
        # In:  text
        # Out: the IPv4 address it spells, as one number, or $null
        # Why: a network holds an address when the two agree above its
        #      prefix: each divided by the network's size, rounded down
        param([string]$Text)
        $ip = $null
        # .NET also reads short forms: 10.20.10320 as 10.20.40.80.
        if ($Text -notmatch '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' -or -not [System.Net.IPAddress]::TryParse($Text, [ref]$ip)) { return $null }
        $b = $ip.GetAddressBytes()
        [uint64]$b[0] * 16777216 + [uint64]$b[1] * 65536 + [uint64]$b[2] * 256 + [uint64]$b[3]
    }
    $number = & $toNumber $Address
    if ($null -eq $number) { return $null }
    $best = $null
    $bestBits = -1
    foreach ($vlan in @($Vlans)) {
        if (-not $vlan) { continue }
        $network, $bits = ([string]$vlan['cidr']) -split '/'
        $prefix = 0
        if (-not [int]::TryParse([string]$bits, [ref]$prefix) -or $prefix -gt 32) { continue }
        $start = & $toNumber $network
        if ($null -eq $start) { continue }
        $size = [Math]::Pow(2, 32 - $prefix)
        if ([Math]::Floor($number / $size) -eq [Math]::Floor($start / $size) -and $prefix -gt $bestBits) {
            $best = $vlan
            $bestBits = $prefix
        }
    }
    $best
}
