# Font.ps1 - the block-letter fonts, and a name set in one as art: "the
# company name in block letters from a font of our own" (docs/DECISIONS.md,
# D3). A name too wide for the Pixel font takes the Small font, on two lines
# if it must, then spaced capitals, then itself: Get-UsaBannerNameForm.
#
# A font file is fonts\<name>.json in the module. It holds:
#
#   +---------+----------------------------------------------------------+
#   | Key     | What                                                     |
#   +---------+----------------------------------------------------------+
#   | title,  | what the font is, who drew it, its licence and where it  |
#   | artist, | came from, as for art; every font needs all four         |
#   | licence,|                                                          |
#   | source  |                                                          |
#   | height  | the rows in every glyph, 1 to 30                         |
#   | gap     | the columns between two glyphs, 0 to 3                   |
#   | glyphs  | each character's rows, all as wide as each other, in     |
#   |         | printable ASCII. Every capital, every digit and a space  |
#   |         | are required; a lower-case letter is drawn as its capital|
#   +---------+----------------------------------------------------------+
#
# name is for people; the file's name is the font's name.

function Get-UsaBannerFontData {
    <#
    .SYNOPSIS
    Reads one of the module's fonts by name, and checks it.
    .DESCRIPTION
    In:  a name, such as pixel, for fonts\<name>.json in the module.
    Out: the file as an ordered hashtable.
    Throws when there is no such font (naming the ones there are), when the
    file is not JSON, and when it breaks a rule of Test-UsaBannerFontData.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param([Parameter(Mandatory)][string]$Name)
    $dir = Join-Path -Path $script:UsaBannerRoot -ChildPath 'fonts'
    $names = @(if (Test-Path -LiteralPath $dir -PathType Container) {
            Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | ForEach-Object { $_.BaseName } | Sort-Object
        })
    if ($Name -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $names -cnotcontains $Name) {
        throw "UsaBanner: there is no font called '$Name'. There is: $($names -join ', ')."
    }
    $path = Join-Path -Path $dir -ChildPath "$Name.json"
    try { $font = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable }
    catch { throw "UsaBanner: $path is not JSON: $($_.Exception.Message)" }
    $problems = @(Test-UsaBannerFontData -Font $font)
    if ($problems.Count -gt 0) { throw ("UsaBanner: $path breaks the font rules:`n  " + ($problems -join "`n  ")) }
    $font
}

function Test-UsaBannerFontData {
    <#
    .SYNOPSIS
    The rules a font keeps; returns each one it breaks.
    .DESCRIPTION
    In:  the font.
    Out: one string per problem; nothing when the font is sound.
    - title, artist, licence and source are there and not blank;
    - height is a whole number from 1 to 30, and gap one from 0 to 3;
    - glyphs holds every capital A-Z, every digit 0-9 and a space;
    - each glyph is for one character, has height rows, each as wide as the
      others, and is printable ASCII (space to tilde) only.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Font)
    foreach ($key in 'title', 'artist', 'licence', 'source') {
        if ([string]::IsNullOrWhiteSpace([string]$Font[$key])) { "${key}: missing" }
    }
    $isWhole = {
        # In:  a value read from JSON
        # Out: $true when it is a whole number
        # Why: JSON numbers arrive as Int64 (or Int32), never as [int] alone
        param($Value)
        $Value -is [long] -or $Value -is [int]
    }
    $height = $Font['height']
    if (-not (& $isWhole $height) -or $height -lt 1 -or $height -gt 30) { 'height: a whole number from 1 to 30'; return }
    $gap = $Font['gap']
    if (-not (& $isWhole $gap) -or $gap -lt 0 -or $gap -gt 3) { 'gap: a whole number from 0 to 3' }
    $glyphs = $Font['glyphs']
    if ($glyphs -isnot [System.Collections.IDictionary]) { 'glyphs: missing'; return }
    foreach ($ch in @([char[]](65..90)) + @([char[]](48..57)) + @([char]' ')) {
        if (-not $glyphs.Contains([string]$ch)) { "glyphs: none for '$ch'" }
    }
    foreach ($key in $glyphs.Keys) {
        if (([string]$key).Length -ne 1) { "glyph '$key': a glyph is for one character"; continue }
        $rows = @($glyphs[$key])
        if ($rows.Count -ne $height) { "glyph '$key': $($rows.Count) rows for $height"; continue }
        $widths = @($rows | ForEach-Object { ([string]$_).Length } | Sort-Object -Unique)
        if ($widths.Count -ne 1) { "glyph '${key}': rows of $($widths -join ', ') columns; all of one width" }
        if (($rows -join '') -cnotmatch '^[ -~]*$') { "glyph '${key}': printable ASCII only" }
    }
}

function Get-UsaBannerFontRows {
    <#
    .SYNOPSIS
    A text's rows in one font: its glyphs side by side, gap columns apart.
    .DESCRIPTION
    In:  the text, and a checked font (Get-UsaBannerFontData).
    Out: one string per row of the font; a lower-case letter is drawn as its
         capital.
    Throws when the font has no glyph for a character, naming each.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Text,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Font
    )
    $fontName = if ($Font['name']) { [string]$Font['name'] } else { [string]$Font['title'] }
    $glyphs = $Font['glyphs']
    $upper = $Text.ToUpperInvariant()
    $missing = @($upper.ToCharArray() | ForEach-Object { [string]$_ } | Where-Object { -not $glyphs.Contains($_) } | Select-Object -Unique)
    if ($missing.Count -gt 0) {
        $others = @($glyphs.Keys | Where-Object { [string]$_ -cnotmatch '^[A-Z0-9 ]$' } | Sort-Object) -join ' '
        throw "UsaBanner: the $fontName font has no glyph for $(@($missing | ForEach-Object { "'$_'" }) -join ', '). It has A-Z, 0-9, a space and: $others"
    }
    $gap = ' ' * [int]$Font['gap']
    for ($r = 0; $r -lt [int]$Font['height']; $r++) {
        (@(foreach ($ch in $upper.ToCharArray()) { [string]@($glyphs[[string]$ch])[$r] }) -join $gap)
    }
}

function New-UsaBannerNameArtData {
    <#
    .SYNOPSIS
    Rows of a name as art the module's renderer draws.
    .DESCRIPTION
    In:  the rows, and the art's title, artist, licence and source.
    Out: art: a mask with every stroke in class w, and w's colours, today's
         welcome line from #78C8FF to #FFC850, left to right.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Rows,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Artist,
        [Parameter(Mandatory)][string]$Licence,
        [Parameter(Mandatory)][string]$Source
    )
    $mask = [string[]]@(foreach ($row in $Rows) { $row -replace '[^ ]', 'w' })
    $palette = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    $palette['w'] = [ordered]@{ label = 'the letters, in the welcome line''s colours'; from = '#78C8FF'; to = '#FFC850'; across = $true; basic = 'bright-blue' }
    [ordered]@{
        title   = $Title
        artist  = $Artist
        licence = $Licence
        source  = $Source
        art     = $Rows
        mask    = $mask
        palette = $palette
    }
}

function ConvertTo-UsaBannerWordArt {
    <#
    .SYNOPSIS
    A name set in one font, as art the module's renderer draws.
    .DESCRIPTION
    In:  the text, and a checked font (Get-UsaBannerFontData).
    Out: art: the font's title, artist, licence and source, and the rows of
         Get-UsaBannerFontRows in the welcome line's colours.
    Throws when the font has no glyph for a character, naming each, and when
    the name comes out wider than 64 columns, the most any art may be.
    ConvertTo-UsaBannerNameArt is the one that finds a form that fits.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Text,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Font
    )
    $fontName = if ($Font['name']) { [string]$Font['name'] } else { [string]$Font['title'] }
    $rows = [string[]]@(Get-UsaBannerFontRows -Text $Text -Font $Font)
    $width = $rows[0].Length
    if ($width -gt 64) { throw "UsaBanner: '$Text' comes out $width columns wide in the $fontName font; art may be at most 64." }
    New-UsaBannerNameArtData -Rows $rows -Title $Text -Artist ([string]$Font['artist']) -Licence ([string]$Font['licence']) -Source "set in the $fontName font"
}

function Get-UsaBannerNameForm {
    <#
    .SYNOPSIS
    How a company name is set to fit a width.
    .DESCRIPTION
    The first form, in this order, that fits the width (picked in the M2
    gallery, docs/DECISIONS.md D3):

    +--------+---------------------------------------------------------+
    | Form   | The name                                                |
    +--------+---------------------------------------------------------+
    | pixel  | in the Pixel font, on one line                          |
    | small  | in the Small font, on one line                          |
    | small2 | in the Small font on two lines, broken at the space     |
    |        | that leaves the wider line narrowest, the lines centred |
    |        | over each other with a blank row between                |
    | spaced | in capitals, a space after each character               |
    | plain  | as written                                              |
    +--------+---------------------------------------------------------+

    A font's forms are passed over when it has no glyph for a character of
    the name. plain is given even when it is wider than the width: the name
    is never shorter than itself.
    Out: @{ Form; Rows; Font }, Font the font's data for pixel, small and
         small2, $null otherwise.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [int]$Width = $script:UsaBannerWidth
    )
    $upper = $Name.ToUpperInvariant()
    $fits = {
        # In:  rows
        # Out: $true when the widest is no wider than -Width
        # Why: every form is tried against the same width
        param([string[]]$Rows)
        ($Rows | Measure-Object -Property Length -Maximum).Maximum -le $Width
    }
    $hasGlyphs = {
        # In:  a font
        # Out: $true when it has a glyph for every character of the name
        # Why: a form in a font missing one is passed over, not an error
        param([System.Collections.IDictionary]$Font)
        @($upper.ToCharArray() | Where-Object { -not $Font['glyphs'].Contains([string]$_) }).Count -eq 0
    }
    foreach ($fontName in 'pixel', 'small') {
        $font = Get-UsaBannerFontData -Name $fontName
        if (-not (& $hasGlyphs $font)) { continue }
        $rows = [string[]]@(Get-UsaBannerFontRows -Text $Name -Font $font)
        if (& $fits $rows) { return @{ Form = $fontName; Rows = $rows; Font = $font } }
    }
    $small = Get-UsaBannerFontData -Name 'small'
    $words = @($Name -split ' ' | Where-Object { $_ })
    if ($words.Count -gt 1 -and (& $hasGlyphs $small)) {
        $best = $null
        for ($i = 1; $i -lt $words.Count; $i++) {
            $top = [string[]]@(Get-UsaBannerFontRows -Text ($words[0..($i - 1)] -join ' ') -Font $small)
            $bottom = [string[]]@(Get-UsaBannerFontRows -Text ($words[$i..($words.Count - 1)] -join ' ') -Font $small)
            $wider = [Math]::Max($top[0].Length, $bottom[0].Length)
            if ($wider -le $Width -and ($null -eq $best -or $wider -lt $best.Wider)) { $best = @{ Wider = $wider; Top = $top; Bottom = $bottom } }
        }
        if ($best) {
            $rows = [System.Collections.Generic.List[string]]::new()
            foreach ($part in @($best.Top), @($best.Bottom)) {
                if ($rows.Count -gt 0) { $rows.Add('') }
                $left = ' ' * [int][Math]::Floor(($best.Wider - $part[0].Length) / 2)
                foreach ($row in $part) { $rows.Add($left + $row) }
            }
            return @{ Form = 'small2'; Rows = $rows.ToArray(); Font = $small }
        }
    }
    $spaced = [string[]]@(($upper.ToCharArray() -join ' '))
    if (& $fits $spaced) { return @{ Form = 'spaced'; Rows = $spaced; Font = $null } }
    @{ Form = 'plain'; Rows = [string[]]@($Name); Font = $null }
}

function ConvertTo-UsaBannerNameArt {
    <#
    .SYNOPSIS
    The company name as the banner sets it, as art the module's renderer
    draws.
    .DESCRIPTION
    In:  the name, and the columns it may take (64, the widest art, by
         default).
    Out: art in the form Get-UsaBannerNameForm finds: in a font, with that
         font's artist and licence; in spaced capitals or as written, with
         the module's own.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Name,
        [int]$Width = $script:UsaBannerWidth
    )
    $form = Get-UsaBannerNameForm -Name $Name -Width $Width
    if ($form.Font) {
        $fontName = [string]$form.Font['name']
        return New-UsaBannerNameArtData -Rows $form.Rows -Title $Name -Artist ([string]$form.Font['artist']) -Licence ([string]$form.Font['licence']) -Source "set in the $fontName font$(if ($form.Form -eq 'small2') { ', on two lines' })"
    }
    $how = if ($form.Form -eq 'spaced') { 'in spaced capitals' } else { 'as written' }
    New-UsaBannerNameArtData -Rows $form.Rows -Title $Name -Artist 'UsagiTools' -Licence 'MIT' -Source "the name ${how}: no font fits it"
}
