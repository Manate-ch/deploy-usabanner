# Color.ps1 - colour escapes for each mode, the nearest of the 256 xterm
# colours, which mode a terminal gets, and whether it shows Unicode.

$script:UsaEsc = [string][char]27

# Basic colour name, as art files write it -> its SGR foreground code.
$script:UsaBasicSgr = @{
    'black' = 30; 'red' = 31; 'green' = 32; 'yellow' = 33
    'blue' = 34; 'magenta' = 35; 'cyan' = 36; 'white' = 37
    'bright-black' = 90; 'bright-red' = 91; 'bright-green' = 92; 'bright-yellow' = 93
    'bright-blue' = 94; 'bright-magenta' = 95; 'bright-cyan' = 96; 'bright-white' = 97
}

# The channel levels of the 6x6x6 cube in the 256-colour palette (indexes 16-231).
$script:UsaCubeLevels = @(0, 95, 135, 175, 215, 255)

function ConvertFrom-UsaBannerHex {
    <#
    .SYNOPSIS
    '#RRGGBB' to its three channels, 0-255 each.
    .DESCRIPTION
    Out: three ints, red, green and blue, one after another.
    Throws on anything else, saying how to write a colour.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([Parameter(Mandatory)][string]$Hex)
    if ($Hex -notmatch '^#[0-9A-Fa-f]{6}$') { throw "UsaBanner: '$Hex' is not a colour; write it as #RRGGBB." }
    [Convert]::ToInt32($Hex.Substring(1, 2), 16)
    [Convert]::ToInt32($Hex.Substring(3, 2), 16)
    [Convert]::ToInt32($Hex.Substring(5, 2), 16)
}

function Find-UsaBanner256 {
    <#
    .SYNOPSIS
    The index, 16-255, of the 256-colour palette entry nearest an RGB colour.
    .DESCRIPTION
    Two candidates; the closer by squared distance wins, the cube on a tie:
    - the 6x6x6 cube (16-231): each channel to its nearest level of 0, 95,
      135, 175, 215 and 255. The levels are not evenly spaced, so
      channel * 5 / 255 picks wrong ones: #FF9900 is 208, not 214;
    - the grey ramp (232-255): 8 to 238 in steps of 10, nearest the mean of
      the channels.
    Indexes 0-15 are never returned: terminals let users re-theme those.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param([int]$R, [int]$G, [int]$B)
    $findNearestLevel = {
        # In:  one channel, 0-255
        # Out: the index, 0-5, of the cube level nearest it; the lower on a tie
        # Why: the levels are uneven, so no single division finds it
        param([int]$Value)
        $best = 0
        for ($i = 1; $i -lt 6; $i++) {
            if ([Math]::Abs($Value - $script:UsaCubeLevels[$i]) -lt [Math]::Abs($Value - $script:UsaCubeLevels[$best])) { $best = $i }
        }
        $best
    }
    $ir = & $findNearestLevel $R
    $ig = & $findNearestLevel $G
    $ib = & $findNearestLevel $B
    $dr = $R - $script:UsaCubeLevels[$ir]
    $dg = $G - $script:UsaCubeLevels[$ig]
    $db = $B - $script:UsaCubeLevels[$ib]
    $cubeDistance = $dr * $dr + $dg * $dg + $db * $db

    $step = [Math]::Max(0, [Math]::Min(23, [int][Math]::Round((($R + $G + $B) / 3.0 - 8) / 10)))   # 24 greys: 8 + 10 * step
    $grey = 8 + 10 * $step
    $greyDistance = ($R - $grey) * ($R - $grey) + ($G - $grey) * ($G - $grey) + ($B - $grey) * ($B - $grey)

    if ($greyDistance -lt $cubeDistance) { return 232 + $step }
    16 + 36 * $ir + 6 * $ig + $ib
}

function ConvertTo-UsaBannerSgr {
    <#
    .SYNOPSIS
    The escape that sets the text colour, in one colour mode.
    .DESCRIPTION
    +-----------+---------------------------------------------------+
    | Mode      | Escape                                            |
    +-----------+---------------------------------------------------+
    | truecolor | ESC[38;2;R;G;Bm                                   |
    | 256       | ESC[38;5;Nm, N from Find-UsaBanner256             |
    | 16        | ESC[Nm, N the SGR code of the basic colour named  |
    | none      | nothing                                           |
    +-----------+---------------------------------------------------+
    16 with no basic colour named also gives nothing: the terminal's own
    colour.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [int[]]$Rgb,
        [string]$Basic,
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'none')][string]$Mode
    )
    switch ($Mode) {
        'truecolor' { return "$script:UsaEsc[38;2;$($Rgb[0]);$($Rgb[1]);$($Rgb[2])m" }
        '256' { return "$script:UsaEsc[38;5;$(Find-UsaBanner256 -R $Rgb[0] -G $Rgb[1] -B $Rgb[2])m" }
        '16' { if ($Basic) { return "$script:UsaEsc[$($script:UsaBasicSgr[$Basic])m" } }
    }
    ''
}

function Resolve-UsaBannerColorMode {
    <#
    .SYNOPSIS
    The colour mode to draw in: truecolor, 256, 16, mono or none.
    .DESCRIPTION
    The first row that gives a mode wins:

    +-------------------------+-------------------------------------------+
    | Source                  | Gives                                     |
    +-------------------------+-------------------------------------------+
    | -Requested              | itself, unless auto: the caller asked     |
    | USABANNER_COLOR         | itself: the user's own override           |
    | NO_COLOR, not empty     | mono: no colour, bold and reverse only:   |
    |                         | D7's Mono preset (no-color.org)           |
    | -HostMode               | itself, unless auto: the mode the admin   |
    |                         | found works on this host                  |
    | COLORTERM               | truecolor for truecolor or 24bit          |
    | WT_SESSION, set         | truecolor (Windows Terminal)              |
    | TERM                    | none for dumb; 256 when it holds 256col;  |
    |                         | 16 for any other                          |
    | no TERM                 | truecolor on Windows, whose console and   |
    |                         | sshd pass 24-bit colour; none elsewhere   |
    +-------------------------+-------------------------------------------+

    SSH passes TERM on but not COLORTERM, so a 24-bit terminal over SSH
    often says only 256; -HostMode is how the admin says otherwise.
    A USABANNER_COLOR other than truecolor, 256, 16 or none is ignored, with
    a warning. -Environment replaces the process environment, for tests.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('auto', 'truecolor', '256', '16', 'none')][string]$Requested = 'auto',
        [ValidateSet('auto', 'truecolor', '256', '16', 'none')][string]$HostMode = 'auto',
        [System.Collections.IDictionary]$Environment,
        [bool]$OnWindows = $IsWindows
    )
    if ($Requested -ne 'auto') { return $Requested }
    $readVariable = {
        # In:  an environment variable's name, and the environment handed in ($null for the real one)
        # Out: its value, or '' when it is not set
        # Why: tests hand in an environment of their own; a run reads the process's
        param([string]$VariableName, [System.Collections.IDictionary]$Source)
        $value = if ($null -ne $Source) { $Source[$VariableName] } else { [Environment]::GetEnvironmentVariable($VariableName) }
        if ($null -eq $value) { '' } else { [string]$value }
    }

    $user = & $readVariable 'USABANNER_COLOR' $Environment
    if ($user) {
        if ($user -in 'truecolor', '256', '16', 'none') { return $user.ToLowerInvariant() }
        Write-Warning "UsaBanner: USABANNER_COLOR is '$user'. It takes truecolor, 256, 16 or none, so it is ignored."
    }
    if (& $readVariable 'NO_COLOR' $Environment) { return 'mono' }
    if ($HostMode -ne 'auto') { return $HostMode }

    if ((& $readVariable 'COLORTERM' $Environment) -in 'truecolor', '24bit') { return 'truecolor' }
    if (& $readVariable 'WT_SESSION' $Environment) { return 'truecolor' }
    $term = & $readVariable 'TERM' $Environment
    if ($term -eq 'dumb') { return 'none' }
    if ($term -match '256col') { return '256' }
    if ($term) { return '16' }
    if ($OnWindows) { return 'truecolor' }
    'none'
}

function Resolve-UsaBannerGlyphs {
    <#
    .SYNOPSIS
    Whether to draw for a client that shows Unicode: unicode or ascii.
    .DESCRIPTION
    The first row that gives an answer wins:

    +------------------------+--------------------------------------------+
    | Source                 | Gives                                      |
    +------------------------+--------------------------------------------+
    | -Requested             | itself, unless auto: the caller asked      |
    | USABANNER_GLYPHS       | itself: the user's own override            |
    | -HostGlyphs            | itself, unless auto: what the admin found  |
    |                        | the clients of this host show              |
    | Windows                | unicode, as today's Windows banner draws   |
    | LC_ALL, LC_CTYPE, LANG | the first one set: unicode when it names   |
    |                        | UTF-8, ascii for any other character set   |
    | none of them set       | ascii: the C locale's character set        |
    +------------------------+--------------------------------------------+

    ascii draws a Unicode border set as Classic, and the panel's marks as
    today's ASCII ones. A USABANNER_GLYPHS other than unicode or ascii is
    ignored, with a warning. -Environment replaces the process environment,
    for tests.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [ValidateSet('auto', 'unicode', 'ascii')][string]$Requested = 'auto',
        [ValidateSet('auto', 'unicode', 'ascii')][string]$HostGlyphs = 'auto',
        [System.Collections.IDictionary]$Environment,
        [bool]$OnWindows = $IsWindows
    )
    if ($Requested -ne 'auto') { return $Requested }
    $readVariable = {
        # In:  an environment variable's name, and the environment handed in ($null for the real one)
        # Out: its value, or '' when it is not set
        # Why: tests hand in an environment of their own; a run reads the process's
        param([string]$VariableName, [System.Collections.IDictionary]$Source)
        $value = if ($null -ne $Source) { $Source[$VariableName] } else { [Environment]::GetEnvironmentVariable($VariableName) }
        if ($null -eq $value) { '' } else { [string]$value }
    }

    $user = & $readVariable 'USABANNER_GLYPHS' $Environment
    if ($user) {
        if ($user -in 'unicode', 'ascii') { return $user.ToLowerInvariant() }
        Write-Warning "UsaBanner: USABANNER_GLYPHS is '$user'. It takes unicode or ascii, so it is ignored."
    }
    if ($HostGlyphs -ne 'auto') { return $HostGlyphs }
    if ($OnWindows) { return 'unicode' }
    foreach ($name in 'LC_ALL', 'LC_CTYPE', 'LANG') {
        $locale = & $readVariable $name $Environment
        if ($locale) {
            if ($locale -match 'utf-?8') { return 'unicode' }
            return 'ascii'
        }
    }
    'ascii'
}
