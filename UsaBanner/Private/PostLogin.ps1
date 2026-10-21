# PostLogin.ps1 - the banner after login (docs/DECISIONS.md, D5), in the
# arrangement picked in the M2 gallery (A, today's order), 64 columns wide:
#
#   the art, centred
#   Welcome to <company>                the company in the welcome gradient
#   ...........  L A B  ...........     the tier strip: a bar in its colour
#   +- <host name> ------ <badge> -+    the panel: the host's name, its
#   | schema   HQ / Virtual / ...  |    site and VLAN, then a row per fact
#   +------------------------------+
#   (ok) all clear   services ...       health: each problem, or all clear
#
# The facts come in as a hashtable, as M3 will gather them; a fact left out
# gets no row.
#
#   +----------+--------------------------------------------------------+
#   | Fact     | Shape                                                  |
#   +----------+--------------------------------------------------------+
#   | Name     | the host name with its domain: the panel's title       |
#   | Ip       | the primary IPv4 address: the VLAN it is in            |
#   | Os       | text, as 'Ubuntu 24.04.3 LTS, kernel 6.8.0-87-generic' |
#   | Role     | text                                                   |
#   | Uptime   | text, as '12d 6h 40m'                                  |
#   | Cpu      | @{ Now; Min; Max; Text }: percentages, and the model   |
#   | Memory   | @{ Pct; Min; Max; Text; Kind }                         |
#   | Disks    | @(@{ Name; Pct; Min; Max; Text; Kind }), one a disk    |
#   | Sessions | text                                                   |
#   | Time     | text: the local time at login                          |
#   | Ipv4     | @(@{ Name; Address }): each adapter's, as 10.20.40.80/22 |
#   | Updates  | @{ Text; Level }, Level good, warn or bad              |
#   | Reboot   | @{ Text; Level }                                       |
#   | Services | @{ Text; Level }                                       |
#   | Problems | @(@{ Level; Text }): what the health lines report      |
#   | Checked  | the checks that ran, named after all clear             |
#   +----------+--------------------------------------------------------+
#
# Min and Max are the last 24 hours' (D17). Memory warns from 90% used, a
# disk and the CPU from 85%, and each is bad from 95%: today's levels.

# D7's presets: a style for each role the banner draws. Edge is the panel's
# border where the preset fixes one; elsewhere the host's colours give it.
# Mono turns the data colours, the tier's and the VLAN's, into reverse video.
$script:UsaPresets = @{
    UsagiTools   = @{
        Label = @{ Fg = '#78C8EB'; FgBasic = 'cyan' }; Value = $null
        Dim = @{ Fg = '#6E7887'; FgBasic = 'bright-black' }; Good = @{ Fg = '#6ED28C'; FgBasic = 'green' }
        Warn = @{ Fg = '#FFBE3C'; FgBasic = 'yellow' }; Bad = @{ Fg = '#F05050'; FgBasic = 'red'; Bold = $true }
        Strong = @{ Bold = $true }; FixedEdge = $false; Edge = $null; Mono = $false
        Welcome = @{ From = '#78C8FF'; To = '#FFC850'; Basic = 'bright-blue' }
    }
    HighContrast = @{
        Label = @{ Fg = '#FFE14D'; FgBasic = 'bright-yellow'; Bold = $true }; Value = @{ Fg = '#FFFFFF'; FgBasic = 'bright-white' }
        Dim = @{ Fg = '#C8D0DA'; FgBasic = 'white' }; Good = @{ Fg = '#4DFF88'; FgBasic = 'bright-green'; Bold = $true }
        Warn = @{ Fg = '#FFD000'; FgBasic = 'bright-yellow'; Bold = $true }; Bad = @{ Fg = '#FF4D4D'; FgBasic = 'bright-red'; Bold = $true }
        Strong = @{ Fg = '#FFFFFF'; FgBasic = 'bright-white'; Bold = $true }; FixedEdge = $true; Edge = @{ Fg = '#FFFFFF'; FgBasic = 'bright-white' }; Mono = $false
        Welcome = @{ From = '#FFFFFF'; To = '#FFE14D'; Basic = 'bright-white' }
    }
    Mono         = @{
        Label = @{ Bold = $true }; Value = $null; Dim = $null; Good = $null
        Warn = @{ Bold = $true }; Bad = @{ Bold = $true; Reverse = $true }
        Strong = @{ Bold = $true }; FixedEdge = $true; Edge = $null; Mono = $true
        Welcome = @{ From = '#FFFFFF'; To = '#FFFFFF'; Basic = '' }
    }
}

# The panel's marks, in Unicode or, for a client that is not UTF-8, in
# ASCII: today's GLYPHS setting. A bar is ten cells.
$script:UsaPanelGlyphs = @{
    Unicode = @{
        Full = [string][char]0x2501; Empty = [string][char]0x2500; Sep = [string][char]0x00B7
        Ok = [string][char]0x2714; Warn = [string][char]0x25B2; Bad = [string][char]0x2716
    }
    Ascii   = @{ Full = '#'; Empty = '.'; Sep = '-'; Ok = '[ok]'; Warn = '[!!]'; Bad = '[XX]' }
}

function Resolve-UsaBannerPreset {
    <#
    .SYNOPSIS
    A colour preset's palette, and the mode it is drawn in.
    .DESCRIPTION
    In:  the configuration's preset, and the terminal's mode
         (Resolve-UsaBannerColorMode).
    Out: @{ Palette; Mode }:

    +--------------+----------------------------------------------------+
    | Preset       | Draws                                              |
    +--------------+----------------------------------------------------+
    | UsagiTools   | its palette, in the terminal's mode                |
    | Classic16    | UsagiTools' palette, in 16 colours at most: the    |
    |              | same on every colour terminal                      |
    | HighContrast | its palette, in the terminal's mode                |
    | Mono         | bold and reverse only, in the mono mode            |
    | Custom       | UsagiTools' palette: the configuration holds no    |
    |              | colours for it yet                                 |
    +--------------+----------------------------------------------------+

    The mono mode, which NO_COLOR gives, draws Mono's palette whatever the
    preset, since no other one shows without colour; none draws no escape.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][ValidateSet('UsagiTools', 'Classic16', 'HighContrast', 'Mono', 'Custom')][string]$Preset,
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'mono', 'none')][string]$Mode
    )
    $drawn = $Mode
    if ($Preset -eq 'Mono' -and $Mode -ne 'none') { $drawn = 'mono' }
    if ($Preset -eq 'Classic16' -and $Mode -in 'truecolor', '256') { $drawn = '16' }
    $palette = switch ($Preset) { 'HighContrast' { 'HighContrast' } 'Mono' { 'Mono' } default { 'UsagiTools' } }
    if ($drawn -eq 'mono') { $palette = 'Mono' }
    @{ Palette = $script:UsaPresets[$palette]; Mode = $drawn }
}

function Get-UsaBannerDataStyle {
    <#
    .SYNOPSIS
    A named colour from the configuration's tables, as a style.
    .DESCRIPTION
    In:  the colour's name, the palette, -Background for a tag or a bar,
         and -Bold.
    Out: the colour as text; or, with -Background, as the ground under
         near-black or white text, whichever its brightness reads better
         with. Mono has no colour: a background becomes reverse video.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Color,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Palette,
        [switch]$Background,
        [switch]$Bold
    )
    if ($Palette.Mono) {
        if ($Background) { return New-UsaBannerStyle -Reverse -Bold:$Bold }
        if ($Bold) { return New-UsaBannerStyle -Bold }
        return $null
    }
    $named = Get-UsaBannerNamedColor -Name $Color
    if (-not $Background) { return New-UsaBannerStyle -Fg $named.Hex -FgBasic $named.Basic -Bold:$Bold }
    $rgb = @(ConvertFrom-UsaBannerHex -Hex $named.Hex)
    if (($rgb[0] * 299 + $rgb[1] * 587 + $rgb[2] * 114) / 1000 -gt 140) {
        return New-UsaBannerStyle -Fg '#141414' -FgBasic 'black' -Bg $named.Hex -BgBasic $named.Basic -Bold:$Bold
    }
    New-UsaBannerStyle -Fg '#FFFFFF' -FgBasic 'bright-white' -Bg $named.Hex -BgBasic $named.Basic -Bold:$Bold
}

function Limit-UsaBannerLine {
    <#
    .SYNOPSIS
    A line's spans cut to a width.
    .DESCRIPTION
    Out: the spans that fit whole; then the first that does not, cut to the
         columns left with ~ as its last character. A span the art renderer
         drew is left out rather than cut: its escapes take no columns.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([object[]]$Spans = @(), [Parameter(Mandatory)][int]$Width)
    $used = 0
    foreach ($span in $Spans) {
        if ($used + $span.Width -le $Width) {
            $span
            $used += $span.Width
            continue
        }
        $room = $Width - $used
        if (-not $span.Drawn -and $room -gt 0) { New-UsaBannerSpan -Text ($span.Text.Substring(0, $room - 1) + '~') -Style $span.Style }
        return
    }
}

function New-UsaBannerTierStrip {
    <#
    .SYNOPSIS
    The tier strip (strip A): the tier's name, spaced out, centred in a bar
    of its colour across the banner.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Tier, [Parameter(Mandatory)][System.Collections.IDictionary]$Palette)
    $word = $Tier.ToCharArray() -join ' '
    $pad = $script:UsaBannerWidth - $word.Length
    $left = [int][Math]::Floor($pad / 2)
    $block = New-UsaBannerBlock
    Add-UsaBannerLine -Block $block -Spans @(New-UsaBannerSpan -Text ((' ' * $left) + $word + (' ' * ($pad - $left))) -Style (Get-UsaBannerDataStyle -Color (Get-UsaBannerTier -Name $Tier).Color -Palette $Palette -Background -Bold))
    $block
}

function New-UsaBannerHostTitle {
    <#
    .SYNOPSIS
    The host name for the panel's top line: bold, and, when the name is in
    the naming standard, its first five letters each in its code's colour.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [System.Collections.IDictionary]$Identity,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Palette
    )
    if (-not $Identity) { return @(New-UsaBannerSpan -Text $Name -Style $Palette.Strong) }
    $fields = @('site', 'site', 'type', 'subtype', 'os')
    for ($i = 0; $i -lt 5; $i++) {
        $row = $Identity.Rows[$fields[$i]]
        $style = if ($row -and $row['color']) { Get-UsaBannerDataStyle -Color ([string]$row['color']) -Palette $Palette -Bold } else { $Palette.Strong }
        New-UsaBannerSpan -Text ([string]$Name[$i]) -Style $style
    }
    New-UsaBannerSpan -Text $Name.Substring(5) -Style $Palette.Strong
}

function Get-UsaBannerBadgeText {
    <#
    .SYNOPSIS
    The badge's text, in the forms it may take, longest first.
    .DESCRIPTION
    In:  the host's identity (Resolve-UsaBannerHostName) and its VLAN row
         (Find-UsaBannerVlan), either $null.
    Out: "<site> - <tag>-<short>", then "<tag>-<short>", then "<tag>": the
         panel takes the first its top line has room for. Without a VLAN,
         the site alone; without either, nothing. short is the VLAN's short
         name, or its name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([System.Collections.IDictionary]$Identity, [System.Collections.IDictionary]$Vlan)
    $site = if ($Identity) { [string]$Identity.Site } else { '' }
    if (-not $Vlan) {
        if ($site) { $site }
        return
    }
    $short = if ($Vlan['short']) { [string]$Vlan['short'] } else { [string]$Vlan['name'] }
    if ($site) { "$site - $($Vlan['tag'])-$short" }
    "$($Vlan['tag'])-$short"
    [string]$Vlan['tag']
}

function New-UsaBannerPanel {
    <#
    .SYNOPSIS
    The host panel: a row per fact, in a box titled with the host's name and
    its badge.
    .DESCRIPTION
    In:  the configuration, the facts (the table at the top of this file),
         the palette, the glyphs, and -AsciiOnly for a client that is not
         UTF-8, which draws a Unicode border set as Classic.
    Out: a block 64 columns wide. A row is a voiced label, nine columns or
         a disk's longer one, then the value: too wide, it first loses its
         detail, such as the 24-hour range, then is cut, ending in ~. The
         border takes the colour of the host's type code, as today's
         BORDER_BY=type, else the tier's; a preset may fix it. A top line
         with no room for the badge takes a shorter form of it, or none.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Facts,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Palette,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Glyphs,
        [switch]$AsciiOnly
    )
    $voice = [string]$Config['voice']
    $tier = [string]$Config['environment']
    $tierRow = Get-UsaBannerTier -Name $tier
    $hostName = [string]$Facts['Name']
    $identity = Resolve-UsaBannerHostName -Name $hostName -Naming $Config['naming']
    $vlan = Find-UsaBannerVlan -Address ([string]$Facts['Ip']) -Vlans @($Config['vlans'])
    # Inside the sides, the padding (two columns left, one right) and the label's space.
    $inside = $script:UsaBannerWidth - 5

    $rows = New-UsaBannerBlock
    $addRow = {
        # In:  a label, the value's spans, and spans of detail that may go
        # Out: nothing; the row joins the panel
        # Why: every row is a voiced label, then a value cut to the room left
        param([string]$Label, [object[]]$Value, [object[]]$Detail = @())
        $labelText = (Get-UsaBannerVoiceLabel -Label $Label -Voice $voice).PadRight(9)
        $room = $inside - $labelText.Length - 1
        $spans = @($Value) + @($Detail)
        if ((Measure-UsaBannerLine -Spans $spans) -gt $room) { $spans = @(Limit-UsaBannerLine -Spans @($Value) -Width $room) }
        Add-UsaBannerLine -Block $rows -Spans (@((New-UsaBannerSpan -Text $labelText -Style $Palette.Label), (New-UsaBannerSpan -Text ' ')) + $spans)
    }
    $levelStyle = {
        # In:  good, warn or bad
        # Out: the palette's style for it
        # Why: updates, reboot and services come with their level
        param([string]$Level)
        switch ($Level) { 'bad' { $Palette.Bad } 'warn' { $Palette.Warn } default { $Palette.Good } }
    }
    $percentStyle = {
        # In:  a percentage, and the one it warns from
        # Out: good, warn, or bad from 95, as the palette's style
        # Why: the CPU, memory and disks share today's levels
        param([int]$Percent, [int]$WarnFrom)
        if ($Percent -ge 95) { $Palette.Bad } elseif ($Percent -ge $WarnFrom) { $Palette.Warn } else { $Palette.Good }
    }
    $usage = {
        # In:  a row's label, a usage fact (Pct, Min, Max, Text, Kind), and the percentage it warns from
        # Out: nothing; the row joins the panel: a bar, the percentage, the size, and the 24-hour range as detail
        # Why: memory and each disk are drawn alike
        param([string]$Label, [System.Collections.IDictionary]$Fact, [int]$WarnFrom)
        $full = [int][Math]::Max(0, [Math]::Min(10, [Math]::Floor(([int]$Fact.Pct + 5) / 10)))
        $size = [string]$Fact.Text
        if ($Fact.Kind) { $size += "  $($Fact.Kind)" }
        $value = @(
            (New-UsaBannerSpan -Text ($Glyphs.Full * $full) -Style (& $percentStyle $Fact.Pct $WarnFrom))
            (New-UsaBannerSpan -Text ($Glyphs.Empty * (10 - $full)) -Style $Palette.Dim)
            (New-UsaBannerSpan -Text ' ')
            (New-UsaBannerSpan -Text "$($Fact.Pct)%" -Style (& $percentStyle $Fact.Pct $WarnFrom))
            (New-UsaBannerSpan -Text "  $size" -Style $Palette.Value)
        )
        & $addRow $Label $value @(New-UsaBannerSpan -Text "  24h $($Fact.Min)-$($Fact.Max)%" -Style $Palette.Dim)
    }

    if ($identity) { & $addRow 'schema' @(New-UsaBannerSpan -Text $identity.Decoded -Style $Palette.Value) }
    if ($vlan) { & $addRow 'vlan' @(New-UsaBannerSpan -Text "$($vlan['tag'])  $($vlan['name'])  ($($vlan['cidr']))" -Style $Palette.Value) }
    & $addRow 'tier' @(New-UsaBannerSpan -Text " $tier " -Style (Get-UsaBannerDataStyle -Color $tierRow.Color -Palette $Palette -Background -Bold)) @(New-UsaBannerSpan -Text "  $(ConvertTo-UsaBannerVoiced -Text $tierRow.Meaning -Voice $voice)" -Style $Palette.Dim)
    foreach ($fact in 'Os', 'Role', 'Uptime') {
        if ($Facts[$fact]) { & $addRow $fact.ToLowerInvariant() @(New-UsaBannerSpan -Text ([string]$Facts[$fact]) -Style $Palette.Value) }
    }
    $cpu = $Facts['Cpu']
    if ($cpu) {
        & $addRow 'cpu' @((New-UsaBannerSpan -Text "$($cpu.Now)%" -Style (& $percentStyle $cpu.Now 85)), (New-UsaBannerSpan -Text "  24h $($cpu.Min)-$($cpu.Max)%" -Style $Palette.Dim)) @(New-UsaBannerSpan -Text "  $($cpu.Text)" -Style $Palette.Value)
    }
    if ($Facts['Memory']) { & $usage 'memory' $Facts['Memory'] 90 }
    foreach ($disk in @($Facts['Disks'])) {
        if ($disk) { & $usage "disk $($disk.Name)" $disk 85 }
    }
    foreach ($fact in 'Sessions', 'Time') {
        if ($Facts[$fact]) { & $addRow $fact.ToLowerInvariant() @(New-UsaBannerSpan -Text ([string]$Facts[$fact]) -Style $Palette.Value) }
    }
    $adapterLabel = 'ipv4'
    foreach ($adapter in @($Facts['Ipv4'])) {
        if (-not $adapter) { continue }
        & $addRow $adapterLabel @(New-UsaBannerSpan -Text ('{0,-10} {1}' -f $adapter.Name, $adapter.Address) -Style $Palette.Value)
        $adapterLabel = ''
    }
    foreach ($fact in 'Updates', 'Reboot', 'Services') {
        $state = $Facts[$fact]
        if ($state) { & $addRow $fact.ToLowerInvariant() @(New-UsaBannerSpan -Text ([string]$state.Text) -Style (& $levelStyle ([string]$state.Level))) }
    }

    $title = @((New-UsaBannerSpan -Text ' ')) + @(New-UsaBannerHostTitle -Name $hostName -Identity $identity -Palette $Palette) + @((New-UsaBannerSpan -Text ' '))
    if ((Measure-UsaBannerTopLine -LeftLabel $title) -gt $script:UsaBannerWidth) { $title = @(Limit-UsaBannerLine -Spans $title -Width ($script:UsaBannerWidth - 4)) }
    $badgeColor = if ($vlan -and $vlan['color']) { [string]$vlan['color'] } else { 'Grey' }
    $badge = @()
    foreach ($text in @(Get-UsaBannerBadgeText -Identity $identity -Vlan $vlan)) {
        $candidate = @(New-UsaBannerSpan -Text " $text " -Style (Get-UsaBannerDataStyle -Color $badgeColor -Palette $Palette -Background -Bold))
        if ((Measure-UsaBannerTopLine -LeftLabel $title -RightLabel $candidate) -le $script:UsaBannerWidth) {
            $badge = $candidate
            break
        }
    }

    $edge = if ($Palette.FixedEdge) { $Palette.Edge }
    elseif ($identity -and $identity.Rows['type']['color']) { Get-UsaBannerDataStyle -Color ([string]$identity.Rows['type']['color']) -Palette $Palette }
    else { Get-UsaBannerDataStyle -Color $tierRow.Color -Palette $Palette }
    $border = $Config['border']
    $char = if ($border['char']) { [string]$border['char'] } else { 'o' }
    $set = Get-UsaBannerBorderSet -Name ([string]$border['set']) -Char $char -AsciiOnly:$AsciiOnly
    New-UsaBannerBox -Sections @($rows) -Set $set -Edge $edge -LeftLabel $title -RightLabel $badge -PadLeft 2 -PadRight 1 -PadY 0
}

function New-UsaBannerHealth {
    <#
    .SYNOPSIS
    The health lines under the panel: each problem, or all clear with the
    checks that ran.
    .DESCRIPTION
    Out: a block no wider than 64 columns: a problem's text wraps under
         itself, and the checks wrap between checks; today's one line runs
         to 70 columns when it names six. A voice changes all clear, never
         a problem or a check.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Facts,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Palette,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Glyphs,
        [AllowEmptyString()][string]$Voice = 'plain'
    )
    $block = New-UsaBannerBlock
    $problems = @(@($Facts['Problems']) | Where-Object { $_ })
    foreach ($problem in $problems) {
        $isBad = [string]$problem.Level -eq 'bad'
        $mark = if ($isBad) { $Glyphs.Bad } else { $Glyphs.Warn }
        $indent = 3 + $mark.Length
        $first = $true
        foreach ($text in @(ConvertTo-UsaBannerWrapped -Text ([string]$problem.Text) -Width ($script:UsaBannerWidth - $indent))) {
            $lead = @(if ($first) { (New-UsaBannerSpan -Text '  '), (New-UsaBannerSpan -Text $mark -Style $(if ($isBad) { $Palette.Bad } else { $Palette.Warn })), (New-UsaBannerSpan -Text ' ') } else { New-UsaBannerSpan -Text (' ' * $indent) })
            Add-UsaBannerLine -Block $block -Spans ($lead + @(New-UsaBannerSpan -Text $text -Style $Palette.Value))
            $first = $false
        }
    }
    if ($problems.Count -gt 0) { return $block }

    $words = Get-UsaBannerVoice -Voice $Voice
    $clear = "$($Glyphs.Ok) $(if ($words) { $words.AllClear } else { 'all clear' })"
    $indent = 2 + $clear.Length + 3
    $room = $script:UsaBannerWidth - $indent
    $lines = [System.Collections.Generic.List[string]]::new()
    $current = ''
    foreach ($check in @($Facts['Checked'] | Where-Object { $_ })) {
        $next = if ($current) { "$current $($Glyphs.Sep) $check" } else { [string]$check }
        if ($next.Length -gt $room -and $current) {
            $lines.Add($current)
            $current = [string]$check
        }
        else { $current = $next }
    }
    if ($current) { $lines.Add($current) }
    Add-UsaBannerLine -Block $block -Spans (@((New-UsaBannerSpan -Text '  '), (New-UsaBannerSpan -Text $clear -Style $Palette.Good)) + @(if ($lines.Count) { New-UsaBannerSpan -Text "   $($lines[0])" -Style $Palette.Dim }))
    for ($i = 1; $i -lt $lines.Count; $i++) {
        Add-UsaBannerLine -Block $block -Spans @((New-UsaBannerSpan -Text (' ' * $indent)), (New-UsaBannerSpan -Text $lines[$i] -Style $Palette.Dim))
    }
    $block
}

function New-UsaBannerWelcome {
    <#
    .SYNOPSIS
    "Welcome to <company>", the company in the preset's welcome gradient.
    .DESCRIPTION
    A voice changes the words around the name, never the name; its tail
    after the name goes when the line would pass 64 columns.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$Company,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Palette,
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'mono', 'none')][string]$Mode,
        [AllowEmptyString()][string]$Voice = 'plain'
    )
    $words = Get-UsaBannerVoice -Voice $Voice
    $lead = '  ' + $(if ($words) { $words.Welcome } else { 'Welcome to' })
    $tail = if ($words) { [string]$words.WelcomeTail } else { '' }
    if ($lead.Length + 1 + $Company.Length + $tail.Length -gt $script:UsaBannerWidth) { $tail = '' }
    $art = New-UsaBannerNameArtData -Rows @("$Company$tail") -Title $Company -Artist 'UsagiTools' -Licence 'MIT' -Source 'the welcome line'
    $art['palette']['w']['from'] = $Palette.Welcome.From
    $art['palette']['w']['to'] = $Palette.Welcome.To
    $art['palette']['w']['basic'] = $Palette.Welcome.Basic
    Join-UsaBannerBeside -Blocks @((New-UsaBannerTextBlock -Lines @($lead)), (New-UsaBannerArtBlock -Art $art -Mode $Mode)) -Gap 1
}

function New-UsaBannerPostLogin {
    <#
    .SYNOPSIS
    The banner after login, as a block.
    .DESCRIPTION
    In:  the configuration, the OS whose colour the art takes, the facts
         (the table at the top of this file), the palette and the mode
         (Resolve-UsaBannerPreset), and -AsciiOnly for a client that is
         not UTF-8.
    Out: the block, 64 columns wide: the art, the welcome line when there is
         a company, the tier strip, the panel, and the health lines.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu', 'linux')][string]$Os,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Facts,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Palette,
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'mono', 'none')][string]$Mode,
        [switch]$AsciiOnly
    )
    $voice = [string]$Config['voice']
    $glyphs = if ($AsciiOnly) { $script:UsaPanelGlyphs['Ascii'] } else { $script:UsaPanelGlyphs['Unicode'] }
    $artName = [string]$Config['art']['name']
    if ($artName -eq 'os') { $artName = 'server' }
    $art = New-UsaBannerArtBlock -Art (Resolve-UsaBannerArtTint -Art (Get-UsaBannerArtData -Name $artName) -Os $Os) -Mode $Mode
    $blank = New-UsaBannerTextBlock -Lines @('')
    $company = [string]$Config['company']
    # Held to the left: the stack centres each block as a whole.
    $welcome = if ($company) { Join-UsaBannerStack -Blocks @(New-UsaBannerWelcome -Company $company -Palette $Palette -Mode $Mode -Voice $voice) -Width $script:UsaBannerWidth } else { $null }
    $health = Join-UsaBannerStack -Blocks @(New-UsaBannerHealth -Facts $Facts -Palette $Palette -Glyphs $glyphs -Voice $voice) -Width $script:UsaBannerWidth
    Join-UsaBannerStack -Align center -Width $script:UsaBannerWidth -Blocks @(
        $art
        $blank
        $welcome
        $(if ($welcome) { $blank })
        (New-UsaBannerTierStrip -Tier ([string]$Config['environment']) -Palette $Palette)
        (New-UsaBannerPanel -Config $Config -Facts $Facts -Palette $Palette -Glyphs $glyphs -AsciiOnly:$AsciiOnly)
        $blank
        $health
    )
}

function Get-UsaBannerPostLogon {
    <#
    .SYNOPSIS
    The banner after login, as the lines a terminal prints.
    .DESCRIPTION
    In:  the configuration, the OS, the facts, the terminal's mode
         (Resolve-UsaBannerColorMode), and -AsciiOnly for a client that is
         not UTF-8.
    Out: its lines, in the mode the configuration's preset draws in.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu', 'linux')][string]$Os,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Facts,
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'mono', 'none')][string]$Mode,
        [switch]$AsciiOnly
    )
    $look = Resolve-UsaBannerPreset -Preset ([string]$Config['color']['preset']) -Mode $Mode
    ConvertTo-UsaBannerFrameText -Block (New-UsaBannerPostLogin -Config $Config -Os $Os -Facts $Facts -Palette $look.Palette -Mode $look.Mode -AsciiOnly:$AsciiOnly) -Mode $look.Mode
}
