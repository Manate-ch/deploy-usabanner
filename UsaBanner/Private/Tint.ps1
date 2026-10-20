# Tint.ps1 - the OS colours: the colour a host's art takes where its palette
# asks for the OS's colour instead of naming one (D3, option B: our own art in
# the OS colour), and which OS this host is.

# OS -> its art colour, a gradient by row from light at the top, and the basic
# colours a 16-colour terminal gets for it, its shades and itself.
$script:UsaOsTint = @{
    windows = @{ from = '#7CC0FF'; to = '#1E6FD9'; basic = 'bright-blue'; basicLight = 'bright-cyan'; basicDark = 'blue' }
    ubuntu  = @{ from = '#FFA45C'; to = '#E0501A'; basic = 'yellow'; basicLight = 'bright-yellow'; basicDark = 'red' }
    linux   = @{ from = '#E2E7EE'; to = '#8D99A8'; basic = 'white'; basicLight = 'bright-white'; basicDark = 'bright-black' }
}

# The tints a palette entry may name.
$script:UsaTintNames = @('os', 'os-light', 'os-dark', 'os-fill')

function Get-UsaBannerTintColor {
    <#
    .SYNOPSIS
    The colours one tint gives on one OS.
    .DESCRIPTION
    In:  a tint and an OS: windows, ubuntu or linux (any other system).
    Out: an ordered dictionary of from and to, a gradient by row, and basic,
         the colour's name for a 16-colour terminal:

    +----------+------------------------------------------+--------------+
    | Tint     | from and to                              | basic        |
    +----------+------------------------------------------+--------------+
    | os       | the OS colour                            | its own      |
    | os-light | each channel 35% of the way to 255       | a light one  |
    | os-dark  | each channel times 0.62                  | a dark one   |
    | os-fill  | each channel times 0.42, for fill cells  | bright-black |
    +----------+------------------------------------------+--------------+

    Each channel is rounded half to even ([Math]::Round's own rule), as the
    gallery the art was picked from drew it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][ValidateSet('os', 'os-light', 'os-dark', 'os-fill')][string]$Tint,
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu', 'linux')][string]$Os
    )
    $osTint = $script:UsaOsTint[$Os]
    $shade = {
        # In:  '#RRGGBB'
        # Out: that colour in this tint
        # Why: from and to shade alike
        param([string]$Hex)
        $channels = foreach ($channel in @(ConvertFrom-UsaBannerHex -Hex $Hex)) {
            $value = switch ($Tint) {
                'os-light' { $channel + (255 - $channel) * 0.35 }
                'os-dark' { $channel * 0.62 }
                'os-fill' { $channel * 0.42 }
                default { $channel }
            }
            [int][Math]::Round($value)
        }
        '#{0:X2}{1:X2}{2:X2}' -f $channels
    }
    $basic = switch ($Tint) {
        'os' { $osTint['basic'] }
        'os-light' { $osTint['basicLight'] }
        'os-dark' { $osTint['basicDark'] }
        'os-fill' { 'bright-black' }
    }
    [ordered]@{ from = (& $shade $osTint['from']); to = (& $shade $osTint['to']); basic = $basic }
}

function Resolve-UsaBannerArtTint {
    <#
    .SYNOPSIS
    Art with every tinted palette entry given its OS's colours.
    .DESCRIPTION
    In:  checked art, and an OS: windows, ubuntu or linux.
    Out: a copy of the art. In its palette, each entry with a tint has from,
         to and basic from Get-UsaBannerTintColor in place of the tint; its
         other keys, such as label and sheen, stay. Entries with no tint,
         and the art handed in, are left as they were.
    Classes are compared by exact character code, so f and F stay apart.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.IDictionary])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Art,
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu', 'linux')][string]$Os
    )
    $copy = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    foreach ($key in $Art.Keys) { $copy[$key] = $Art[$key] }
    if ($Art['palette'] -isnot [System.Collections.IDictionary]) { return $copy }
    $palette = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    foreach ($class in $Art['palette'].Keys) {
        $entry = $Art['palette'][$class]
        if ($entry -isnot [System.Collections.IDictionary] -or -not $entry.Contains('tint')) {
            $palette[$class] = $entry
            continue
        }
        $resolved = [ordered]@{}
        foreach ($key in $entry.Keys) { if ($key -ne 'tint') { $resolved[$key] = $entry[$key] } }
        $color = Get-UsaBannerTintColor -Tint ([string]$entry['tint']) -Os $Os
        foreach ($key in $color.Keys) { $resolved[$key] = $color[$key] }
        $palette[$class] = $resolved
    }
    $copy['palette'] = $palette
    $copy
}

function Get-UsaBannerHostOs {
    <#
    .SYNOPSIS
    Which OS colour this host's art takes: windows, ubuntu or linux.
    .DESCRIPTION
    windows on Windows; ubuntu where the os-release file says ID=ubuntu;
    linux on any other system, and where there is no os-release file. A
    system only based on Ubuntu, such as one with ID_LIKE=ubuntu, is linux:
    its own name is not Ubuntu's.
    -OnWindows and -OsReleasePath replace what this host says, for tests.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [bool]$OnWindows = $IsWindows,
        [string]$OsReleasePath = '/etc/os-release'
    )
    if ($OnWindows) { return 'windows' }
    if (Test-Path -LiteralPath $OsReleasePath -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $OsReleasePath) {
            if ($line -match '^ID=(.*)$' -and $Matches[1].Trim().Trim('"', "'") -eq 'ubuntu') { return 'ubuntu' }
        }
    }
    'linux'
}
