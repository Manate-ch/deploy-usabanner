# Art.ps1 - reading a piece of art and its colours, checking it, and
# drawing it in one colour mode.
#
# An art file is art\base\<name>.json for ours, or art\apps\<name>.json for
# another owner's logo, drawn by us (docs/DECISIONS.md, D3). It holds:
#
#   +---------+----------------------------------------------------------+
#   | Key     | What                                                     |
#   +---------+----------------------------------------------------------+
#   | title,  | what the piece is, who drew it, its licence and where it |
#   | artist, | came from; every piece needs all four                    |
#   | licence,|                                                          |
#   | source  |                                                          |
#   | owner,  | art\apps only: whose trademark the logo is, and the line |
#   | notice  | NOTICE carries for it                                    |
#   | art     | the picture, one string per row, printable ASCII, at     |
#   |         | most 64 columns by 30 rows                               |
#   | mask    | the same shape: each character names the class of the    |
#   |         | cell under it; a space for none                          |
#   | fill    | optional: the class of the cells inside the shape, and   |
#   |         | the character they get in colour (a space without)       |
#   | palette | per class: rgb, one colour; or from and to, a gradient   |
#   |         | down the rows (across: true, left to right instead); or  |
#   |         | tint, the host's OS colour or a shade of it: os,         |
#   |         | os-light, os-dark or os-fill (Tint.ps1); sheen, true to  |
#   |         | shade it; basic, its 16-colour name. A class with no     |
#   |         | colour keys is drawn in the terminal's own colour        |
#   | sheen   | peak and drop, and regions: rows and cols as [first,     |
#   |         | last], with a middle column and a half-width             |
#   +---------+----------------------------------------------------------+
#
# label is for people; nothing reads it.
#
# A configuration names a piece in art.name, or holds art of its own in
# art.custom (Get-UsaBannerConfiguredArt; docs/DECISIONS.md, D31).

# os-logo: the logo of the OS a host runs, from art\apps.
$script:UsaOsLogo = @{ windows = 'windows'; ubuntu = 'ubuntu'; linux = 'tux' }

function Get-UsaBannerArtIndex {
    <#
    .SYNOPSIS
    Every piece of the module's art, by name.
    .DESCRIPTION
    Out: an ordered dictionary, sorted by name, of name -> @{ Folder; Path },
    where Folder is base or apps. A missing apps folder holds nothing.
    Throws when two files share a name: -Name could not tell them apart.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    $found = [System.Collections.Generic.SortedDictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($folder in 'base', 'apps') {
        $dir = Join-Path -Path $script:UsaBannerRoot -ChildPath 'art' -AdditionalChildPath $folder
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $dir -Filter '*.json' -File) {
            if ($found.ContainsKey($file.BaseName)) {
                throw "UsaBanner: two pieces of art are called '$($file.BaseName)': $($found[$file.BaseName].Path) and $($file.FullName)."
            }
            $found[$file.BaseName] = @{ Folder = $folder; Path = $file.FullName }
        }
    }
    $index = [ordered]@{}
    foreach ($key in $found.Keys) { $index[$key] = $found[$key] }
    $index
}

function Get-UsaBannerArtData {
    <#
    .SYNOPSIS
    Reads one piece of the module's art by name, and checks it.
    .DESCRIPTION
    In:  a name, such as rabbit, for art\base\<name>.json or
         art\apps\<name>.json in the module.
    Out: the file as an ordered hashtable: art, mask, fill, palette, sheen,
    and the metadata.
    Throws when there is no such art (naming the ones there are), when the
    file is not JSON, and when it breaks a rule of Test-UsaBannerArtData for
    its folder.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param([Parameter(Mandatory)][string]$Name)
    $index = Get-UsaBannerArtIndex
    if ($Name -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or -not $index.Contains($Name)) {
        throw "UsaBanner: there is no art called '$Name'. There is: $(@($index.Keys) -join ', ')."
    }
    Read-UsaBannerArtFile -Path $index[$Name].Path -Folder $index[$Name].Folder
}

function Read-UsaBannerArtFile {
    <#
    .SYNOPSIS
    Reads one art file, and checks it.
    .DESCRIPTION
    In:  the file's full path, and the folder whose rules it keeps: base, the
         default, or apps.
    Out: the file as an ordered hashtable.
    Throws when there is no such file, when it is not JSON or not a JSON
    object, and when it breaks a rule of Test-UsaBannerArtData.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('base', 'apps')][string]$Folder = 'base'
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "UsaBanner: there is no file at $Path." }
    try { $art = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable }
    catch { throw "UsaBanner: $Path is not JSON: $($_.Exception.Message)" }
    if ($art -isnot [System.Collections.IDictionary]) { throw "UsaBanner: $Path holds no art: it is not a JSON object." }
    $problems = @(Test-UsaBannerArtData -Art $art -Folder $Folder)
    if ($problems.Count -gt 0) { throw ("UsaBanner: $Path breaks the art rules:`n  " + ($problems -join "`n  ")) }
    $art
}

function Test-UsaBannerCustomArt {
    <#
    .SYNOPSIS
    The rules a configuration's own art keeps; returns each one it breaks.
    .DESCRIPTION
    In:  the value of art.custom.
    Out: one string per problem; nothing when the art is sound.
    The rules of the module's own art in art\base (Test-UsaBannerArtData),
    and one more: no two classes differ only in case. Windows reads the
    configuration at a login as a PowerShell data file, where f and F are
    one key. New-UsaBannerArt names its classes a to p.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()]$Art)
    if ($Art -isnot [System.Collections.IDictionary]) { return 'not art: an object as New-UsaBannerArt -OutFile saves it' }
    Test-UsaBannerArtData -Art $Art
    if ($Art['palette'] -isnot [System.Collections.IDictionary]) { return }
    $seen = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $Art['palette'].Keys) {
        $class = [string]$key
        if ($seen.ContainsKey($class)) { "palette: classes '$($seen[$class])' and '$class' differ only in case, and Windows reads the configuration as PowerShell data, where they are one key: give one of them another character" }
        else { $seen[$class] = $class }
    }
}

function Get-UsaBannerConfiguredArt {
    <#
    .SYNOPSIS
    The art a configuration draws, checked.
    .DESCRIPTION
    In:  the configuration's art setting, and the host's OS: windows, ubuntu
         or linux.
    Out: the art, as Get-UsaBannerArtData gives it.
    - art.custom, when there: the configuration's own art (Deploy-UsaBanner
      -ArtPath), checked by Test-UsaBannerCustomArt;
    - else art.name: os is the server pictogram, which takes the OS's
      colour; os-logo is the logo of the OS: windows, ubuntu, or tux on any
      other Linux; any other name is that piece of the module's art.
    Throws when the configuration's own art breaks a rule, naming each, and
    when the module has no art of that name.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Setting,
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu', 'linux')][string]$Os
    )
    if ($null -ne $Setting['custom']) {
        $problems = @(Test-UsaBannerCustomArt -Art $Setting['custom'])
        if ($problems.Count -gt 0) { throw ("UsaBanner: the configuration's own art (art.custom) breaks the art rules:`n  " + ($problems -join "`n  ")) }
        return $Setting['custom']
    }
    $name = [string]$Setting['name']
    if ($name -eq 'os') { $name = 'server' }
    elseif ($name -eq 'os-logo') { $name = $script:UsaOsLogo[$Os] }
    Get-UsaBannerArtData -Name $name
}

function Save-UsaBannerArtFile {
    <#
    .SYNOPSIS
    Writes art to a JSON file, which Show-UsaBannerArt -Path draws.
    .DESCRIPTION
    In:  the art, and the file's full path.
    Out: nothing. The file is UTF-8 with no byte-order mark, and has LF line
         ends on every system, as the module's own art files do.
    Throws, with the system's reason, when the file cannot be written.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Art,
        [Parameter(Mandatory)][string]$Path
    )
    $json = (ConvertTo-Json -InputObject $Art -Depth 10) -replace "`r`n", "`n"
    try { [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false)) }
    catch { throw "UsaBanner: cannot write $Path`: $($_.Exception.GetBaseException().Message)" }
}

function Test-UsaBannerArtData {
    <#
    .SYNOPSIS
    The rules a piece of art keeps; returns each one it breaks.
    .DESCRIPTION
    In:  the art, and its folder: base (the default) or apps.
    Out: one string per problem; nothing when the art is sound.
    - title, artist, licence and source are there and not blank; in apps,
      owner and notice too;
    - art: one row or more, printable ASCII (space to tilde) only, at most 64
      columns by 30 rows, the width of the panel;
    - mask: as many rows as the art, each as long as its art row;
    - every visible art character has a class in the mask;
    - a fill-class cell is a space in the art; the fill character is one
      printable character, not a space;
    - every class in the mask has a palette entry. Colours are #RRGGBB; a
      gradient has both from and to, and not rgb as well; a tint is one of
      $script:UsaTintNames, with no rgb, from or to beside it; across is
      true or false, and true only with from and to or a tint; basic is
      one of the 16 names in $script:UsaBasicSgr;
    - each sheen region has rows and cols as [first, last], a middle, and a
      half-width above 0, and the sheen has a peak and a drop.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Art,
        [ValidateSet('base', 'apps')][string]$Folder = 'base'
    )
    $required = @('title', 'artist', 'licence', 'source')
    if ($Folder -eq 'apps') { $required += 'owner', 'notice' }
    foreach ($key in $required) {
        if ([string]::IsNullOrWhiteSpace([string]$Art[$key])) { "${key}: missing (a piece in art\$Folder needs $($required -join ', '))" }
    }
    $checkNumber = {
        # In:  a value read from JSON
        # Out: $true when it is a number
        # Why: JSON numbers arrive as Int64 or Double, never as [int]
        param($Value)
        $Value -is [long] -or $Value -is [double] -or $Value -is [int]
    }
    $checkPair = {
        # In:  a value read from JSON
        # Out: $true when it is [first, last], two whole numbers with first <= last
        # Why: rows and cols of a sheen region are written that way
        param($Value)
        $pair = @($Value)
        $pair.Count -eq 2 -and ($pair[0] -is [long] -or $pair[0] -is [int]) -and ($pair[1] -is [long] -or $pair[1] -is [int]) -and $pair[0] -le $pair[1]
    }

    $rows = @($Art['art'])
    $mask = @($Art['mask'])
    if ($rows.Count -eq 0) { 'art: there are no rows'; return }
    if ($rows.Count -gt 30) { "art: $($rows.Count) rows, more than 30" }
    $widest = ($rows | ForEach-Object { ([string]$_).Length } | Measure-Object -Maximum).Maximum
    if ($widest -gt 64) { "art: $widest columns, more than 64" }
    if ($mask.Count -ne $rows.Count) { "mask: $($mask.Count) rows for $($rows.Count) rows of art"; return }
    if ($Art['palette'] -isnot [System.Collections.IDictionary]) { 'palette: missing'; return }
    # Class -> palette entry, compared by exact character code: f and F are two classes, and a plain @{} would merge them.
    $palette = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($key in $Art['palette'].Keys) { $palette[[string]$key] = $Art['palette'][$key] }

    $fillClass = ''
    if ($null -ne $Art['fill']) {
        $fillClass = [string]$Art['fill']['class']
        if ($fillClass.Length -ne 1) { 'fill.class: one character' }
        if ([string]$Art['fill']['char'] -cnotmatch '^[!-~]$') { 'fill.char: one printable character, not a space' }
    }

    $classes = [System.Collections.Generic.SortedSet[string]]::new([StringComparer]::Ordinal)
    for ($r = 0; $r -lt $rows.Count; $r++) {
        $line = [string]$rows[$r]
        $classLine = [string]$mask[$r]
        if ($line -cnotmatch '^[ -~]*$') { "art row ${r}: printable ASCII only" }
        if ($classLine.Length -ne $line.Length) { "mask row ${r}: $($classLine.Length) characters for $($line.Length)"; continue }
        for ($c = 0; $c -lt $line.Length; $c++) {
            $class = [string]$classLine[$c]
            if ($class -ne ' ') { [void]$classes.Add($class) }
            if ($line[$c] -ne ' ' -and $class -eq ' ') { "row $r, column ${c}: '$($line[$c])' has no class in the mask" }
            if ($fillClass -and $class -ceq $fillClass -and $line[$c] -ne ' ') { "row $r, column ${c}: a fill cell must be a space in the art" }
        }
    }

    foreach ($class in $classes) {
        if (-not $palette.ContainsKey($class)) { "palette: no entry for class '$class'"; continue }
        $entry = $palette[$class]
        if ($entry -isnot [System.Collections.IDictionary]) { "palette '$class': not an object"; continue }
        if ($entry.Contains('tint')) {
            if ([string]$entry['tint'] -cnotin $script:UsaTintNames) { "palette '$class'.tint: one of $($script:UsaTintNames -join ', ')" }
            if ($entry.Contains('rgb') -or $entry.Contains('from') -or $entry.Contains('to')) { "palette '$class': a tint takes its colours from the OS; leave out rgb, from and to" }
        }
        if ($entry.Contains('across')) {
            if ($entry['across'] -isnot [bool]) { "palette '$class'.across: true or false" }
            elseif ($entry['across'] -and -not ($entry.Contains('from') -or $entry.Contains('tint'))) { "palette '$class': across runs a gradient left to right, so it needs from and to, or a tint" }
        }
        foreach ($key in 'rgb', 'from', 'to') {
            if ($entry.Contains($key) -and [string]$entry[$key] -notmatch '^#[0-9A-Fa-f]{6}$') { "palette '$class'.${key}: write colours as #RRGGBB" }
        }
        if ($entry.Contains('from') -xor $entry.Contains('to')) { "palette '$class': a gradient needs both from and to" }
        if ($entry.Contains('rgb') -and $entry.Contains('from')) { "palette '$class': rgb, or from and to, not both" }
        if ($entry.Contains('basic') -and -not $script:UsaBasicSgr.ContainsKey([string]$entry['basic'])) {
            "palette '$class'.basic: one of $(($script:UsaBasicSgr.Keys | Sort-Object) -join ', ')"
        }
    }

    $sheen = $Art['sheen']
    if ($null -ne $sheen) {
        if (-not (& $checkNumber $sheen['peak']) -or -not (& $checkNumber $sheen['drop'])) { 'sheen: peak and drop must be numbers' }
        $i = 0
        foreach ($region in @($sheen['regions'])) {
            if (-not (& $checkPair $region['rows']) -or -not (& $checkPair $region['cols'])) { "sheen region ${i}: rows and cols must be [first, last]" }
            if (-not (& $checkNumber $region['middle']) -or -not (& $checkNumber $region['half']) -or $region['half'] -le 0) { "sheen region ${i}: middle must be a number, half one above 0" }
            $i++
        }
    }
}

function Get-UsaBannerSheen {
    <#
    .SYNOPSIS
    The sheen factor of one cell; 1 where no region holds it.
    .DESCRIPTION
    In the first region whose rows and cols hold the cell:
      factor = peak - drop * min(1, |col - middle| / half)
    The rabbit's peak 1.15 and drop 0.3 give 1.15 down each middle and 0.85
    at the edges: the fur looks rounded and lit.
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param([System.Collections.IDictionary]$Sheen, [int]$Row, [int]$Col)
    if ($null -eq $Sheen) { return 1.0 }
    foreach ($region in @($Sheen['regions'])) {
        $rows = @($region['rows'])
        $cols = @($region['cols'])
        if ($Row -lt $rows[0] -or $Row -gt $rows[1] -or $Col -lt $cols[0] -or $Col -gt $cols[1]) { continue }
        # 1.0, not 1: [Math]::Min(1, x) would take the integer overload and round x away.
        $distance = [Math]::Min(1.0, [Math]::Abs($Col - [double]$region['middle']) / [double]$region['half'])
        return [double]$Sheen['peak'] - [double]$Sheen['drop'] * $distance
    }
    1.0
}

function Get-UsaBannerCellRgb {
    <#
    .SYNOPSIS
    The 24-bit colour of one cell, or nothing for a class drawn in the
    terminal's own colour.
    .DESCRIPTION
    In:  the class's palette entry, the cell's row and column, the art's row
         count and widest row, and the cell's sheen factor.
    Out: three channels, 0-255, or nothing.
    rgb is one colour. from and to are a gradient down the rows, at
    t = row / (rows - 1); with across true, left to right instead, at
    t = col / (cols - 1). With sheen true, each channel is multiplied by the
    factor. Each channel is then rounded half to even ([Math]::Round's own
    rule) and capped at 255. docs/rabbit.svg was drawn with the same
    arithmetic, and a test compares the two.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Entry,
        [int]$Row,
        [int]$Rows,
        [int]$Col,
        [int]$Cols,
        [double]$Sheen = 1.0
    )
    if ($Entry.Contains('rgb')) {
        $from = @(ConvertFrom-UsaBannerHex -Hex $Entry['rgb'])
        $to = $from
    }
    elseif ($Entry.Contains('from')) {
        $from = @(ConvertFrom-UsaBannerHex -Hex $Entry['from'])
        $to = @(ConvertFrom-UsaBannerHex -Hex $Entry['to'])
    }
    else { return }
    $t = if ($Entry['across']) {
        if ($Cols -gt 1) { $Col / ($Cols - 1) } else { 0.0 }
    }
    elseif ($Rows -gt 1) { $Row / ($Rows - 1) }
    else { 0.0 }
    $factor = if ($Entry['sheen']) { $Sheen } else { 1.0 }
    foreach ($i in 0..2) {
        [int][Math]::Min(255.0, [Math]::Round(($from[$i] + ($to[$i] - $from[$i]) * $t) * $factor))
    }
}

function ConvertTo-UsaBannerArtText {
    <#
    .SYNOPSIS
    Draws checked art data as lines of text, in one colour mode.
    .DESCRIPTION
    Out: one string per row of the art.
    - none: the art rows exactly. Fill cells are spaces in the art, so this
      is the picture as shown before login.
    - mono: as none. D7's Mono preset keeps only bold and reverse, and art
      has neither.
    - truecolor, 256: each visible cell in its class's colour, gradient and
      sheen included; 256 takes the nearest palette entry. Fill cells get the
      fill character.
    - 16: each class's basic colour; no gradient and no sheen. Fill cells get
      the fill character.
    An escape goes out only where the colour changes, and spaces carry none.
    A class with no colour gets a reset (ESC[0m) before it. A line that ends
    in colour ends with a reset, so no colour leaks into what follows.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Art,
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'mono', 'none')][string]$ColorMode
    )
    $rows = @($Art['art'])
    if ($ColorMode -in 'none', 'mono') {
        foreach ($line in $rows) { [string]$line }
        return
    }
    $mask = @($Art['mask'])
    $widest = ($rows | ForEach-Object { ([string]$_).Length } | Measure-Object -Maximum).Maximum
    $reset = "$script:UsaEsc[0m"
    $fillClass = ''
    $fillChar = ' '
    if ($null -ne $Art['fill']) {
        $fillClass = [string]$Art['fill']['class']
        $fillChar = [string]$Art['fill']['char']
    }
    # Class -> palette entry, compared by exact character code, as in Test-UsaBannerArtData.
    $palette = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($key in $Art['palette'].Keys) { $palette[[string]$key] = $Art['palette'][$key] }

    for ($row = 0; $row -lt $rows.Count; $row++) {
        $line = [string]$rows[$row]
        $classes = [string]$mask[$row]
        $text = [System.Text.StringBuilder]::new()
        $active = ''
        for ($col = 0; $col -lt $line.Length; $col++) {
            $class = [string]$classes[$col]
            $char = [string]$line[$col]
            if ($fillClass -and $class -ceq $fillClass) { $char = $fillChar }
            if ($char -eq ' ') {
                [void]$text.Append(' ')
                continue
            }
            $sgr = ''
            if ($palette.ContainsKey($class)) {
                $entry = $palette[$class]
                if ($ColorMode -eq '16') {
                    $sgr = ConvertTo-UsaBannerSgr -Basic ([string]$entry['basic']) -Mode '16'
                }
                else {
                    $factor = Get-UsaBannerSheen -Sheen $Art['sheen'] -Row $row -Col $col
                    $rgb = @(Get-UsaBannerCellRgb -Entry $entry -Row $row -Rows $rows.Count -Col $col -Cols $widest -Sheen $factor)
                    if ($rgb.Count -eq 3) { $sgr = ConvertTo-UsaBannerSgr -Rgb $rgb -Mode $ColorMode }
                }
            }
            if ($sgr -cne $active) {
                [void]$text.Append($(if ($sgr) { $sgr } else { $reset }))
                $active = $sgr
            }
            [void]$text.Append($char)
        }
        if ($active) { [void]$text.Append($reset) }
        $text.ToString()
    }
}
