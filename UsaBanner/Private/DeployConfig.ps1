# DeployConfig.ps1 - the configuration a deploy builds: the defaults, or a
# file over them, with the settings given as flags on top. The same command
# builds the same configuration on every host, whatever the host held before.
#
#   +--------------+----------------+--------------------------------------+
#   | Flag         | Setting        | Takes                                |
#   +--------------+----------------+--------------------------------------+
#   | Company      | company        | the name, printable ASCII            |
#   | Environment  | environment    | UNSET, DEV-TEST, LAB, PROD or PUB    |
#   | BannerImage  | art.name       | a piece of the module's art, or os   |
#   | Border       | border.set     | a border set (D6)                    |
#   | BorderChar   | border.char    | the character OneChar draws with     |
#   | BorderCap    | border.cap     | an ASCII face for the top line       |
#   | ColorPreset  | color.preset   | a preset (D7)                        |
#   | ColorMode    | color.mode     | auto, truecolor, 256, 16 or none     |
#   | Glyphs       | glyphs         | auto, unicode or ascii               |
#   | Legal        | legal.template | L1 to L5                             |
#   | LegalText    | legal.text     | the admin's own lines: custom        |
#   | Voice        | voice          | plain, uwu, random or leet           |
#   | PreInit      | preInit        | HostName, Ip, both, or None          |
#   | PreLogon     | preLogon       | the same, for the SSH banner         |
#   | VlanFile     | vlans          | a CSV or TSV file of the VLANs       |
#   | Services     | services       | the names, or default                |
#   | Update       | update.mode    | off, notify or install (D14)         |
#   | UpdateSource | update.source  | the https address of the releases'   |
#   |              |                | files                                |
#   +--------------+----------------+--------------------------------------+
#
# The naming standard is a table of tables: it comes from a file alone.

$script:UsaDeployFlags = [ordered]@{
    Company      = 'company'
    Environment  = 'environment'
    BannerImage  = 'art.name'
    Border       = 'border.set'
    BorderChar   = 'border.char'
    BorderCap    = 'border.cap'
    ColorPreset  = 'color.preset'
    ColorMode    = 'color.mode'
    Glyphs       = 'glyphs'
    Legal        = 'legal.template'
    LegalText    = 'legal.text'
    Voice        = 'voice'
    PreInit      = 'preInit'
    PreLogon     = 'preLogon'
    VlanFile     = 'vlans'
    Services     = 'services'
    Update       = 'update.mode'
    UpdateSource = 'update.source'
}

function Get-UsaBannerDeployFlagName {
    <#
    .SYNOPSIS
    The names of the flags that set a setting, as the table above has them.
    .DESCRIPTION
    Deploy-UsaBanner takes these from its bound parameters and leaves the
    rest (-Path, -WhatIf and the common ones) to itself.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    @($script:UsaDeployFlags.Keys)
}

# The columns a VLAN file may have; the first three it must.
$script:UsaVlanColumns = @('name', 'tag', 'cidr', 'color', 'short')

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

function New-UsaBannerDeployConfig {
    <#
    .SYNOPSIS
    The configuration a deploy builds, from the flags given.
    .DESCRIPTION
    In:  the flags given, by the names in the table at the top of this file
         (Deploy-UsaBanner's parameters); and a configuration file to start
         from, or none, for the defaults.
    Out: the configuration, as an ordered dictionary, checked against the
         schema. A value from a list takes the schema's spelling, so
         -Environment prod sets PROD. -PreInit and -PreLogon set both of
         their settings: what is not named is not shown. -LegalText sets the
         template to custom. -Services default is the OS's own list.
    Throws on a flag the table does not have, on art the module does not
    have, on -LegalText with another template or without text, on a custom
    template left without text, on None or default given with something
    else, on an update channel turned on without a source, when the result
    breaks the schema: each problem with the flag that set it; and on
    -BorderChar when the border set is not OneChar, the one set that draws
    with it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [System.Collections.IDictionary]$Flags = @{},
        [string]$Path
    )
    foreach ($name in $Flags.Keys) {
        if (-not $script:UsaDeployFlags.Contains($name)) { throw "UsaBanner: Deploy-UsaBanner has no setting called '$name'." }
    }
    $config = if ($Path) { Read-UsaBannerConfig -Path $Path } else { Get-UsaBannerConfigDefault }
    $put = {
        # In:  a setting's path, such as border.set, and its value
        # Out: nothing; the configuration holds the value
        param([string]$Setting, $Value)
        $parts = $Setting.Split('.')
        $node = $config
        for ($i = 0; $i -lt $parts.Count - 1; $i++) { $node = $node[$parts[$i]] }
        $node[$parts[-1]] = $Value
    }
    foreach ($name in $script:UsaDeployFlags.Keys) {
        if (-not $Flags.Contains($name)) { continue }
        $value = $Flags[$name]
        $setting = $script:UsaDeployFlags[$name]
        switch ($name) {
            'BannerImage' {
                $known = @('os') + @((Get-UsaBannerArtIndex).Keys)
                $match = @($known | Where-Object { $_ -eq [string]$value })
                if ($match.Count -eq 0) { throw "UsaBanner: -BannerImage takes the module's art, or os for the host's own; there is no art called '$value'. There is: $($known -join ', ')." }
                & $put $setting $match[0]
            }
            'LegalText' {
                $lines = @($value | ForEach-Object { [string]$_ })
                if (@($lines | Where-Object { $_.Trim() }).Count -eq 0) { throw 'UsaBanner: -LegalText holds no text.' }
                if ($Flags.Contains('Legal') -and [string]$Flags['Legal'] -ne 'custom') {
                    throw "UsaBanner: -LegalText is your own legal text, and -Legal $($Flags['Legal']) is a template: give one of them."
                }
                & $put 'legal.template' 'custom'
                & $put $setting $lines
            }
            'Legal' {
                $spelled = @(@(Get-UsaBannerSchemaEnum -Setting $setting) | Where-Object { $_ -eq [string]$value })
                & $put $setting $(if ($spelled.Count) { $spelled[0] } else { [string]$value })
            }
            { $_ -in 'PreInit', 'PreLogon' } {
                $shown = @($value | ForEach-Object { [string]$_ })
                if ('None' -in $shown -and $shown.Count -gt 1) { throw "UsaBanner: -$name None shows nothing, so it goes alone, not with $(@($shown | Where-Object { $_ -ne 'None' }) -join ', ')." }
                & $put "$setting.hostName" ('HostName' -in $shown)
                & $put "$setting.ip" ('Ip' -in $shown)
            }
            'VlanFile' { & $put $setting @(Read-UsaBannerVlanFile -Path ([string]$value)) }
            'Services' {
                $names = @($value | ForEach-Object { [string]$_ })
                if ('default' -in $names) {
                    if ($names.Count -gt 1) { throw "UsaBanner: -Services default watches the OS's own list, so it goes alone, not with $(@($names | Where-Object { $_ -ne 'default' }) -join ', ')." }
                    & $put $setting 'default'
                }
                else { & $put $setting $names }
            }
            default {
                $allowed = @(Get-UsaBannerSchemaEnum -Setting $setting)
                $spelled = @($allowed | Where-Object { $_ -eq [string]$value })
                if ($spelled.Count) { $value = $spelled[0] }
                & $put $setting $value
            }
        }
    }
    if ($config['legal']['template'] -ceq 'custom' -and @(@($config['legal']['text']) | Where-Object { "$_".Trim() }).Count -eq 0) {
        throw 'UsaBanner: the legal template is custom, but there is no text for it: give the lines with -LegalText.'
    }
    # The schema cannot say this without a branch, and D27 keeps it free of them.
    $mode = [string]$config['update']['mode']
    if ($mode -cne 'off' -and -not [string]$config['update']['source']) {
        throw "UsaBanner: the update channel is set to $mode, with no source to look at: give -UpdateSource, the https address the releases' files are downloaded from (docs/DECISIONS.md, D14)."
    }
    $problems = @(Test-UsaBannerConfig -Json (ConvertTo-UsaBannerConfigJson -Config $config))
    if ($problems.Count) {
        $named = foreach ($problem in $problems) {
            $where = ($problem -split ':')[0]
            $flag = $null
            foreach ($candidate in $script:UsaDeployFlags.Keys) {
                $pointer = '/' + $script:UsaDeployFlags[$candidate].Replace('.', '/')
                if ($where -eq $pointer -or $where.StartsWith("$pointer/")) { $flag = $candidate }
            }
            if ($flag -and $Flags.Contains($flag)) { "-${flag}: $problem" } else { $problem }
        }
        throw ("UsaBanner: these settings are not valid:`n  " + ($named -join "`n  "))
    }
    # Only the OneChar set draws border.char: beside any other set the flag would be kept and never drawn.
    if ($Flags.Contains('BorderChar') -and [string]$config['border']['set'] -cne 'OneChar') {
        throw "UsaBanner: -BorderChar is the character the OneChar border set draws with, and the border set is $($config['border']['set']): give -Border OneChar too, or leave -BorderChar out."
    }
    $config
}

function Compare-UsaBannerConfig {
    <#
    .SYNOPSIS
    What changes from one configuration to another, a line per setting.
    .DESCRIPTION
    In:  the configuration a host holds, and the one that replaces it.
    Out: '<setting>: <old> -> <new>' for each setting that differs, in the
         new configuration's order, then any the new one leaves out. A
         setting is a path such as border.set; a list (the VLANs, the
         services, the legal text, a naming table) is one setting, and is
         shown by its length when its JSON runs past 40 characters. Values
         are JSON; one that is not there is (none). Nothing when the two are
         the same. With -NewOnly, '<setting>: <new>': what the new one sets
         otherwise than the old, as Get-UsaBanner lists a host's settings
         against the defaults.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Old,
        [Parameter(Mandatory)][System.Collections.IDictionary]$New,
        [switch]$NewOnly
    )
    $flatten = {
        # In:  a configuration, or part of one, and the path to it
        # Out: an ordered map of each setting's path to its value as JSON
        # Why: the two sides compare setting by setting, whatever their depth
        param([System.Collections.IDictionary]$Node, [string]$Prefix, [System.Collections.Specialized.OrderedDictionary]$Into)
        foreach ($key in $Node.Keys) {
            $path = if ($Prefix) { "$Prefix.$key" } else { [string]$key }
            $value = $Node[$key]
            if ($value -is [System.Collections.IDictionary]) { & $flatten $value $path $Into }
            else { $Into[$path] = $value }
        }
    }
    $show = {
        # In:  a setting's value, or $null when it is not there
        # Out: the value as compact JSON, or its length when that runs long
        param($Value, [bool]$Present)
        if (-not $Present) { return '(none)' }
        $json = ConvertTo-Json -InputObject $Value -Compress -Depth 10
        if ($json.Length -le 40 -or -not ($Value -is [System.Collections.IList])) { return $json }
        $count = @($Value).Count
        "$count $(if ($count -eq 1) { 'entry' } else { 'entries' })"
    }
    $before = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    $after = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    & $flatten $Old '' $before
    & $flatten $New '' $after
    foreach ($path in @($after.Keys) + @($before.Keys | Where-Object { -not $after.Contains($_) })) {
        $had = $before.Contains($path)
        $has = $after.Contains($path)
        $oldJson = if ($had) { ConvertTo-Json -InputObject $before[$path] -Compress -Depth 10 } else { $null }
        $newJson = if ($has) { ConvertTo-Json -InputObject $after[$path] -Compress -Depth 10 } else { $null }
        if ($had -and $has -and $oldJson -ceq $newJson) { continue }
        if ($NewOnly) { "${path}: $(& $show $after[$path] $has)" }
        else { "${path}: $(& $show $before[$path] $had) -> $(& $show $after[$path] $has)" }
    }
}
