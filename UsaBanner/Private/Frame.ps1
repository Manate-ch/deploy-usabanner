# Frame.ps1 - what every banner is built from: styled spans of text, blocks
# of lines, the border sets (docs/DECISIONS.md, D6) and the boxes they draw,
# and text wrapped to a width.
#
#   +-------+------------------------------------------------------------+
#   | Thing | Shape                                                      |
#   +-------+------------------------------------------------------------+
#   | style | @{ Fg; FgBasic; Bg; BgBasic; Bold; Reverse }: Fg and Bg    |
#   |       | are '#RRGGBB', for truecolor and 256; FgBasic and BgBasic  |
#   |       | are 16-colour names (Color.ps1); any key may be left out   |
#   | span  | @{ Text; Style; Drawn; Width }: Drawn is true for text the |
#   |       | art renderer has already coloured, whose escapes take no   |
#   |       | width; Width is the span's width in columns                |
#   | line  | an array of spans                                          |
#   | block | @{ Width; Lines }: lines no wider than Width               |
#   +-------+------------------------------------------------------------+
#
# Text shown before login is printable ASCII (D6), so a frame for it is drawn
# in an ASCII border set, in the none mode. The Unicode sets' characters are
# written below as code points: every file in the module is ASCII.

# The widest any banner, box or piece of art is: an 80-column terminal holds it.
$script:UsaBannerWidth = 64

function New-UsaBannerStyle {
    <#
    .SYNOPSIS
    A style: a colour for 24-bit and 256-colour terminals, a basic colour
    for 16-colour ones, a background of each kind, bold and reverse.
    .DESCRIPTION
    Out: the style as a hashtable; a key not given is left out, and so draws
    in the terminal's own colour.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([string]$Fg, [string]$FgBasic, [string]$Bg, [string]$BgBasic, [switch]$Bold, [switch]$Reverse)
    $style = @{}
    if ($Fg) { $style['Fg'] = $Fg }
    if ($FgBasic) { $style['FgBasic'] = $FgBasic }
    if ($Bg) { $style['Bg'] = $Bg }
    if ($BgBasic) { $style['BgBasic'] = $BgBasic }
    if ($Bold) { $style['Bold'] = $true }
    if ($Reverse) { $style['Reverse'] = $true }
    $style
}

function ConvertTo-UsaBannerStyleSgr {
    <#
    .SYNOPSIS
    The escape that sets a style, in one frame mode.
    .DESCRIPTION
    +-----------+--------------------------------------------------------+
    | Mode      | Gives                                                  |
    +-----------+--------------------------------------------------------+
    | truecolor | bold (1), reverse (7), 38;2;R;G;B and 48;2;R;G;B        |
    | 256       | the same, each colour as 38;5;N or 48;5;N, N from      |
    |           | Find-UsaBanner256                                      |
    | 16        | the same, each colour as its basic name's code; a      |
    |           | background's code is the text code plus 10             |
    | mono      | bold and reverse only: D7's Mono preset                |
    | none      | nothing: what shows before login carries no escape     |
    +-----------+--------------------------------------------------------+
    Out: one escape, its codes joined by ';', or '' when the style sets
    nothing in this mode.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [System.Collections.IDictionary]$Style,
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'mono', 'none')][string]$Mode
    )
    if ($null -eq $Style -or $Mode -eq 'none') { return '' }
    $codes = [System.Collections.Generic.List[string]]::new()
    if ($Style['Bold']) { $codes.Add('1') }
    if ($Style['Reverse']) { $codes.Add('7') }
    foreach ($layer in @(@{ Hex = 'Fg'; Basic = 'FgBasic'; Code = 38; Shift = 0 }, @{ Hex = 'Bg'; Basic = 'BgBasic'; Code = 48; Shift = 10 })) {
        $hex = [string]$Style[$layer.Hex]
        $basic = [string]$Style[$layer.Basic]
        if ($Mode -eq 'truecolor' -and $hex) {
            $rgb = @(ConvertFrom-UsaBannerHex -Hex $hex)
            $codes.Add("$($layer.Code);2;$($rgb[0]);$($rgb[1]);$($rgb[2])")
        }
        elseif ($Mode -eq '256' -and $hex) {
            $rgb = @(ConvertFrom-UsaBannerHex -Hex $hex)
            $codes.Add("$($layer.Code);5;$(Find-UsaBanner256 -R $rgb[0] -G $rgb[1] -B $rgb[2])")
        }
        elseif ($Mode -eq '16' -and $basic) {
            if (-not $script:UsaBasicSgr.ContainsKey($basic)) { throw "UsaBanner: '$basic' is not a basic colour; there is $(($script:UsaBasicSgr.Keys | Sort-Object) -join ', ')." }
            $codes.Add([string]($script:UsaBasicSgr[$basic] + $layer.Shift))
        }
    }
    if ($codes.Count -eq 0) { return '' }
    "$script:UsaEsc[" + ($codes -join ';') + 'm'
}

function New-UsaBannerSpan {
    <#
    .SYNOPSIS
    A span: text in one style, $null for the terminal's own.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyString()][string]$Text = '', [System.Collections.IDictionary]$Style)
    @{ Text = $Text; Style = $Style; Drawn = $false; Width = $Text.Length }
}

function New-UsaBannerBlock {
    <#
    .SYNOPSIS
    A block with no lines yet; Add-UsaBannerLine adds them.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    @{ Width = 0; Lines = [System.Collections.Generic.List[object]]::new() }
}

function Measure-UsaBannerLine {
    <#
    .SYNOPSIS
    A line's width in columns: the sum of its spans' widths.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([object[]]$Spans)
    $width = 0
    foreach ($span in $Spans) { $width += $span.Width }
    $width
}

function Add-UsaBannerLine {
    <#
    .SYNOPSIS
    Adds a line of spans to a block, widening the block to hold it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Block, [object[]]$Spans = @())
    $Block.Lines.Add([object[]]$Spans)
    $width = Measure-UsaBannerLine -Spans $Spans
    if ($width -gt $Block.Width) { $Block.Width = $width }
}

function New-UsaBannerTextBlock {
    <#
    .SYNOPSIS
    A block of plain lines, all in one style.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyString()][string[]]$Lines = @(), [System.Collections.IDictionary]$Style)
    $block = New-UsaBannerBlock
    foreach ($line in $Lines) { Add-UsaBannerLine -Block $block -Spans @(New-UsaBannerSpan -Text $line -Style $Style) }
    $block
}

function New-UsaBannerArtBlock {
    <#
    .SYNOPSIS
    A block of art, drawn by the art renderer in one mode.
    .DESCRIPTION
    In:  checked art with its tints resolved, and a frame mode. mono draws
         the art plain: the Mono preset has no colour to give it.
    Out: a block, one span a row, each span marked as already drawn.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Art,
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'mono', 'none')][string]$Mode
    )
    $artMode = if ($Mode -eq 'mono') { 'none' } else { $Mode }
    $drawn = @(ConvertTo-UsaBannerArtText -Art $Art -ColorMode $artMode)
    $rows = @($Art['art'])
    $block = New-UsaBannerBlock
    for ($i = 0; $i -lt $rows.Count; $i++) {
        Add-UsaBannerLine -Block $block -Spans @(@{ Text = $drawn[$i]; Style = $null; Drawn = $true; Width = ([string]$rows[$i]).Length })
    }
    $block
}

function Join-UsaBannerStack {
    <#
    .SYNOPSIS
    Blocks one above the other.
    .DESCRIPTION
    In:  the blocks, top first ($null ones are left out), left or center,
         and the least width of the result.
    Out: one block. Centring moves each block right as a whole, so art keeps
         its shape; no line gains spaces on its right.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [object[]]$Blocks,
        [ValidateSet('left', 'center')][string]$Align = 'left',
        [int]$Width = 0
    )
    $parts = @($Blocks | Where-Object { $null -ne $_ })
    $widest = $Width
    foreach ($part in $parts) { if ($part.Width -gt $widest) { $widest = $part.Width } }
    $out = New-UsaBannerBlock
    foreach ($part in $parts) {
        $left = if ($Align -eq 'center') { [int][Math]::Floor(($widest - $part.Width) / 2) } else { 0 }
        foreach ($line in $part.Lines) {
            $spans = @($line)
            if ($left -gt 0) { $spans = @(New-UsaBannerSpan -Text (' ' * $left)) + $spans }
            Add-UsaBannerLine -Block $out -Spans $spans
        }
    }
    if ($out.Width -lt $widest) { $out.Width = $widest }
    $out
}

function Join-UsaBannerBeside {
    <#
    .SYNOPSIS
    Blocks side by side.
    .DESCRIPTION
    In:  the blocks, left first ($null ones are left out), the columns
         between them, and top or middle: how a shorter block sits against
         the tallest.
    Out: one block. Each block but the last is padded to its width, so the
         next one starts in the same column on every line; plain spaces at
         the end of a line are dropped, so no line ends in padding.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [object[]]$Blocks,
        [int]$Gap = 2,
        [ValidateSet('top', 'middle')][string]$VAlign = 'middle'
    )
    $parts = @($Blocks | Where-Object { $null -ne $_ })
    $height = 0
    foreach ($part in $parts) { if ($part.Lines.Count -gt $height) { $height = $part.Lines.Count } }
    $out = New-UsaBannerBlock
    for ($row = 0; $row -lt $height; $row++) {
        $spans = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $parts.Count; $i++) {
            $part = $parts[$i]
            $last = $i -eq $parts.Count - 1
            if ($i -gt 0) { $spans.Add((New-UsaBannerSpan -Text (' ' * $Gap))) }
            $top = if ($VAlign -eq 'middle') { [int][Math]::Floor(($height - $part.Lines.Count) / 2) } else { 0 }
            $k = $row - $top
            $used = 0
            if ($k -ge 0 -and $k -lt $part.Lines.Count) {
                foreach ($span in @($part.Lines[$k])) { $spans.Add($span) }
                $used = Measure-UsaBannerLine -Spans @($part.Lines[$k])
            }
            if (-not $last -and $part.Width -gt $used) { $spans.Add((New-UsaBannerSpan -Text (' ' * ($part.Width - $used)))) }
        }
        # A styled span of spaces, such as a bar's, stays: it shows.
        while ($spans.Count -gt 0 -and -not $spans[$spans.Count - 1].Drawn -and $null -eq $spans[$spans.Count - 1].Style -and $spans[$spans.Count - 1].Text.Trim().Length -eq 0) {
            $spans.RemoveAt($spans.Count - 1)
        }
        Add-UsaBannerLine -Block $out -Spans $spans.ToArray()
    }
    $out
}

function ConvertTo-UsaBannerFrameText {
    <#
    .SYNOPSIS
    A block as the lines a terminal prints, in one frame mode.
    .DESCRIPTION
    An escape goes out only where the style changes. A span the art renderer
    drew carries its own escapes, so the style is reset before it; a line
    that ends in a style ends with a reset, so nothing leaks into what
    follows. In the none mode no escape goes out at all.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][hashtable]$Block,
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'mono', 'none')][string]$Mode
    )
    $reset = "$script:UsaEsc[0m"
    foreach ($line in $Block.Lines) {
        $text = [System.Text.StringBuilder]::new()
        $active = ''
        foreach ($span in @($line)) {
            if ($span.Drawn) {
                if ($active) { [void]$text.Append($reset); $active = '' }
                [void]$text.Append($span.Text)
                continue
            }
            if ($span.Text.Length -eq 0) { continue }
            $sgr = ConvertTo-UsaBannerStyleSgr -Style $span.Style -Mode $Mode
            if ($sgr -cne $active) {
                if ($active) { [void]$text.Append($reset) }
                if ($sgr) { [void]$text.Append($sgr) }
                $active = $sgr
            }
            [void]$text.Append($span.Text)
        }
        if ($active) { [void]$text.Append($reset) }
        $text.ToString()
    }
}

# --- borders (D6) ---------------------------------------------------------

function ConvertFrom-UsaBannerCodePoint {
    <#
    .SYNOPSIS
    Code points as characters, one string each.
    .DESCRIPTION
    The Unicode border sets are written as code points, so this file stays
    ASCII: Windows PowerShell 5.1 reads a file without a byte-order mark in
    the ANSI code page.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([int[]]$Code)
    foreach ($c in $Code) { [string][char]$c }
}

# Each set: the top line's left end, fill and right end; the left and right
# sides; the bottom line's left end, fill and right end; and a divider's.
# A fill of two characters repeats from the left end. Before login only the
# ASCII sets are drawn; a Unicode set gives Classic there (D6).
#
#   +----------------+--------------------------------------------------+
#   | Set            | Top, sides, bottom, divider                      |
#   +----------------+--------------------------------------------------+
#   | Classic        | +-+  | |  +-+  +-+                               |
#   | Hash           | ###  # #  ###  ###                               |
#   | Star           | ***  * *  ***  ***                               |
#   | Equals         | +=+  | |  +=+  +=+                               |
#   | Round          | .-.  | |  '-'  |-|                               |
#   | Bevel          | /-\  | |  \-/  |-|                               |
#   | PipeUnderscore | " _ " (a space each end)  | |  |_|  |_|          |
#   | Wavy           | " _- " (spaces)  | |  " -_ " (spaces)  |-_|      |
#   | OneChar        | border.char everywhere, o when it is not set     |
#   | Rounded        | U+256D 2500 256E, 2502, 2570 2500 256F, 251C 2524 |
#   | Single         | U+250C 2500 2510, 2502, 2514 2500 2518, 251C 2524 |
#   | Double         | U+2554 2550 2557, 2551, 255A 2550 255D, 2560 2563 |
#   | Heavy          | U+250F 2501 2513, 2503, 2517 2501 251B, 2523 252B |
#   | Block          | U+2588, the full block, everywhere               |
#   +----------------+--------------------------------------------------+
$script:UsaBorderSets = [ordered]@{
    Classic        = @{ Ascii = $true; Chars = @('+', '-', '+', '|', '|', '+', '-', '+', '+', '-', '+') }
    Hash           = @{ Ascii = $true; Chars = @('#', '#', '#', '#', '#', '#', '#', '#', '#', '#', '#') }
    Star           = @{ Ascii = $true; Chars = @('*', '*', '*', '*', '*', '*', '*', '*', '*', '*', '*') }
    Equals         = @{ Ascii = $true; Chars = @('+', '=', '+', '|', '|', '+', '=', '+', '+', '=', '+') }
    Round          = @{ Ascii = $true; Chars = @('.', '-', '.', '|', '|', "'", '-', "'", '|', '-', '|') }
    Bevel          = @{ Ascii = $true; Chars = @('/', '-', '\', '|', '|', '\', '-', '/', '|', '-', '|') }
    PipeUnderscore = @{ Ascii = $true; Chars = @(' ', '_', ' ', '|', '|', '|', '_', '|', '|', '_', '|') }
    Wavy           = @{ Ascii = $true; Chars = @(' ', '_-', ' ', '|', '|', ' ', '-_', ' ', '|', '-_', '|') }
    OneChar        = @{ Ascii = $true; Chars = $null }
    Rounded        = @{ Ascii = $false; Chars = @(ConvertFrom-UsaBannerCodePoint -Code 0x256D, 0x2500, 0x256E, 0x2502, 0x2502, 0x2570, 0x2500, 0x256F, 0x251C, 0x2500, 0x2524) }
    Single         = @{ Ascii = $false; Chars = @(ConvertFrom-UsaBannerCodePoint -Code 0x250C, 0x2500, 0x2510, 0x2502, 0x2502, 0x2514, 0x2500, 0x2518, 0x251C, 0x2500, 0x2524) }
    Double         = @{ Ascii = $false; Chars = @(ConvertFrom-UsaBannerCodePoint -Code 0x2554, 0x2550, 0x2557, 0x2551, 0x2551, 0x255A, 0x2550, 0x255D, 0x2560, 0x2550, 0x2563) }
    Heavy          = @{ Ascii = $false; Chars = @(ConvertFrom-UsaBannerCodePoint -Code 0x250F, 0x2501, 0x2513, 0x2503, 0x2503, 0x2517, 0x2501, 0x251B, 0x2523, 0x2501, 0x252B) }
    Block          = @{ Ascii = $false; Chars = @(ConvertFrom-UsaBannerCodePoint -Code 0x2588, 0x2588, 0x2588, 0x2588, 0x2588, 0x2588, 0x2588, 0x2588, 0x2588, 0x2588, 0x2588) }
}

function Get-UsaBannerBorderSet {
    <#
    .SYNOPSIS
    The characters of one border set.
    .DESCRIPTION
    In:  a set's name, as the configuration's border.set names it; the
         character OneChar draws with (border.char, o when not set); and
         -AsciiOnly for text shown before login.
    Out: @{ Name; Ascii; TL; T; TR; L; R; BL; B; BR; DL; D; DR }: the top's
         left end, fill and right end; the sides; the bottom's; a divider's.
         Name is the set drawn: Classic when -AsciiOnly turned a Unicode set
         into it, as D6 decided.
    Throws on a set it does not know, naming the ones there are, and on a
    OneChar character that is not one printable character.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Char = 'o',
        [switch]$AsciiOnly
    )
    if (-not $script:UsaBorderSets.Contains($Name)) { throw "UsaBanner: there is no border set called '$Name'. There is: $(@($script:UsaBorderSets.Keys) -join ', ')." }
    $set = $script:UsaBorderSets[$Name]
    if ($AsciiOnly -and -not $set.Ascii) {
        $Name = 'Classic'
        $set = $script:UsaBorderSets[$Name]
    }
    $chars = $set.Chars
    if ($null -eq $chars) {
        if ($Char -cnotmatch '^[!-~]$') { throw "UsaBanner: OneChar draws with one printable character, not '$Char'." }
        $chars = @($Char) * 11
    }
    @{
        Name = $Name; Ascii = $set.Ascii
        TL = $chars[0]; T = $chars[1]; TR = $chars[2]; L = $chars[3]; R = $chars[4]
        BL = $chars[5]; B = $chars[6]; BR = $chars[7]; DL = $chars[8]; D = $chars[9]; DR = $chars[10]
    }
}

function Get-UsaBannerBorderRun {
    <#
    .SYNOPSIS
    One line of a border: its ends, and its fill repeated from the left
    end and cut to fit.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Left, [string]$Fill, [string]$Right, [int]$Width)
    $count = $Width - $Left.Length - $Right.Length
    $repeats = [int][Math]::Ceiling($count / [double]$Fill.Length) + 1
    $Left + ($Fill * $repeats).Substring(0, $count) + $Right
}

function New-UsaBannerLabel {
    <#
    .SYNOPSIS
    A label for a box's top line: the text in its style, with a plain
    space each side.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Text, [System.Collections.IDictionary]$Style)
    @((New-UsaBannerSpan -Text ' '), (New-UsaBannerSpan -Text $Text -Style $Style), (New-UsaBannerSpan -Text ' '))
}

function New-UsaBannerBox {
    <#
    .SYNOPSIS
    A box around blocks of text, with labels in its top line.
    .DESCRIPTION
    In:  the sections, blocks with a divider between each; how each one
         sits, left or center (the last value given goes for the rest); the
         border set (Get-UsaBannerBorderSet); the box's width; the border's
         style; spans for the top line's left, middle and right; and the
         padding inside.
    Out: the box as a block, every line exactly -Width wide. The left label
         starts after the corner and one fill character, the right label
         ends one fill character before the other corner, and the middle
         label is centred in the line between them.
    Throws when the labels need more of the top line than there is, and
    when a section is wider than the room inside.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [object[]]$Sections = @(),
        [ValidateSet('left', 'center')][string[]]$Align = @('left'),
        [Parameter(Mandatory)][hashtable]$Set,
        [int]$Width = $script:UsaBannerWidth,
        [System.Collections.IDictionary]$Edge,
        [object[]]$LeftLabel = @(),
        [object[]]$MiddleLabel = @(),
        [object[]]$RightLabel = @(),
        [int]$PadLeft = 2,
        [int]$PadRight = 2,
        [int]$PadY = 1
    )
    $inner = $Width - 2
    $content = $inner - $PadLeft - $PadRight
    $leftWidth = Measure-UsaBannerLine -Spans $LeftLabel
    $middleWidth = Measure-UsaBannerLine -Spans $MiddleLabel
    $rightWidth = Measure-UsaBannerLine -Spans $RightLabel
    $needed = 2 + $leftWidth + $middleWidth + $rightWidth + 2
    if ($middleWidth -gt 0 -and $leftWidth -gt 0) { $needed++ }
    if ($middleWidth -gt 0 -and $rightWidth -gt 0) { $needed++ }
    if ($leftWidth -gt 0 -and $rightWidth -gt 0 -and $middleWidth -eq 0) { $needed++ }
    if ($needed -gt $Width) { throw "UsaBanner: the box's top line needs $needed columns for its labels; the box is $Width." }

    $out = New-UsaBannerBlock
    $run = Get-UsaBannerBorderRun -Left $Set.TL -Fill $Set.T -Right $Set.TR -Width $Width
    $top = [System.Collections.Generic.List[object]]::new()
    $edgeSpan = {
        # In:  the first column of a piece of the top line, and the column after its last
        # Out: nothing; that piece of the border joins the top line, in the border's style
        # Why: the labels interrupt the border in up to four places
        param([int]$From, [int]$To)
        if ($To -gt $From) { $top.Add((New-UsaBannerSpan -Text $run.Substring($From, $To - $From) -Style $Edge)) }
    }
    $pos = 0
    if ($leftWidth -gt 0) {
        & $edgeSpan 0 2
        foreach ($span in $LeftLabel) { $top.Add($span) }
        $pos = 2 + $leftWidth
    }
    $rightStart = if ($rightWidth -gt 0) { $Width - 2 - $rightWidth } else { $Width }
    if ($middleWidth -gt 0) {
        $middleStart = $pos + [int][Math]::Floor(($rightStart - $pos - $middleWidth) / 2)
        & $edgeSpan $pos $middleStart
        foreach ($span in $MiddleLabel) { $top.Add($span) }
        $pos = $middleStart + $middleWidth
    }
    & $edgeSpan $pos $rightStart
    if ($rightWidth -gt 0) {
        foreach ($span in $RightLabel) { $top.Add($span) }
        & $edgeSpan ($Width - 2) $Width
    }
    Add-UsaBannerLine -Block $out -Spans $top.ToArray()

    $blankLine = @((New-UsaBannerSpan -Text $Set.L -Style $Edge), (New-UsaBannerSpan -Text (' ' * $inner)), (New-UsaBannerSpan -Text $Set.R -Style $Edge))
    for ($i = 0; $i -lt $Sections.Count; $i++) {
        $section = $Sections[$i]
        if ($section.Width -gt $content) { throw "UsaBanner: a section $($section.Width) columns wide does not fit the $content columns inside the box." }
        if ($i -gt 0) { Add-UsaBannerLine -Block $out -Spans @(New-UsaBannerSpan -Text (Get-UsaBannerBorderRun -Left $Set.DL -Fill $Set.D -Right $Set.DR -Width $Width) -Style $Edge) }
        for ($p = 0; $p -lt $PadY; $p++) { Add-UsaBannerLine -Block $out -Spans $blankLine }
        $sectionAlign = if ($i -lt $Align.Count) { $Align[$i] } else { $Align[-1] }
        $shift = if ($sectionAlign -eq 'center') { [int][Math]::Floor(($content - $section.Width) / 2) } else { 0 }
        foreach ($line in $section.Lines) {
            $spans = @($line)
            $used = $PadLeft + $shift + (Measure-UsaBannerLine -Spans $spans)
            Add-UsaBannerLine -Block $out -Spans (@((New-UsaBannerSpan -Text $Set.L -Style $Edge), (New-UsaBannerSpan -Text (' ' * ($PadLeft + $shift)))) + $spans + @((New-UsaBannerSpan -Text (' ' * ($inner - $used))), (New-UsaBannerSpan -Text $Set.R -Style $Edge)))
        }
        for ($p = 0; $p -lt $PadY; $p++) { Add-UsaBannerLine -Block $out -Spans $blankLine }
    }
    Add-UsaBannerLine -Block $out -Spans @(New-UsaBannerSpan -Text (Get-UsaBannerBorderRun -Left $Set.BL -Fill $Set.B -Right $Set.BR -Width $Width) -Style $Edge)
    $out
}

function ConvertTo-UsaBannerWrapped {
    <#
    .SYNOPSIS
    Text broken into lines no wider than a width.
    .DESCRIPTION
    Lines break between words, and runs of spaces between words count as
    one. A word wider than the width is cut into pieces that fit.
    Out: the lines, in order; nothing for text with no words.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Text, [Parameter(Mandatory)][ValidateRange(1, 1000)][int]$Width)
    $current = ''
    foreach ($word in @($Text -split '\s+' | Where-Object { $_ })) {
        while ($word.Length -gt $Width) {
            if ($current) { $current; $current = '' }
            $word.Substring(0, $Width)
            $word = $word.Substring($Width)
        }
        if (-not $current) { $current = $word }
        elseif ($current.Length + 1 + $word.Length -le $Width) { $current += ' ' + $word }
        else { $current; $current = $word }
    }
    if ($current) { $current }
}
