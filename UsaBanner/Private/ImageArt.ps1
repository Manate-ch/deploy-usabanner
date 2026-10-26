# ImageArt.ps1 - an image file made into art (docs/DECISIONS.md, D19):
# reading the image, then the art's palette and metadata. The pixel work is
# C#, in ImageArt.cs beside this file, compiled the first time it is needed.
#
#   +------------------+----------------------------------------------------+
#   | Format           | Read by                                            |
#   +------------------+----------------------------------------------------+
#   | PNG              | ImageArt.cs's own reader on every system, so a PNG |
#   |                  | makes the same art everywhere                      |
#   | JPEG, GIF, BMP,  | System.Drawing on Windows; ImageMagick on Linux,   |
#   | TIFF and others  | when it is installed                               |
#   +------------------+----------------------------------------------------+
#
# Initialize-UsaBannerImageType and Read-UsaBannerImageSystemDrawing, which
# PowerShell logs whole at each import, are in ImageArt.Logged.ps1
# (docs/DECISIONS.md, D30).

$script:UsaImageArtSource = Join-Path -Path $PSScriptRoot -ChildPath 'ImageArt.cs'

# The largest image read: in pixels, about 8000 x 4000, and in bytes.
$script:UsaImageMaxPixels = 32000000
$script:UsaImageMaxBytes = 256MB

# What each format is called in a message.
$script:UsaImageFormatNames = @{
    png = 'a PNG image'; jpeg = 'a JPEG image'; gif = 'a GIF image'; bmp = 'a BMP image'
    tiff = 'a TIFF image'; webp = 'a WebP image'; svg = 'an SVG drawing'; unknown = 'in no image format UsaBanner knows'
}

# The 16 basic colours as xterm draws them, for the one nearest a colour.
# Black is left out: a dark terminal would hide it.
$script:UsaBasicRgb = [ordered]@{
    'red' = 0xCD0000; 'green' = 0x00CD00; 'yellow' = 0xCDCD00; 'blue' = 0x0000EE
    'magenta' = 0xCD00CD; 'cyan' = 0x00CDCD; 'white' = 0xE5E5E5; 'bright-black' = 0x7F7F7F
    'bright-red' = 0xFF0000; 'bright-green' = 0x00FF00; 'bright-yellow' = 0xFFFF00; 'bright-blue' = 0x5C5CFF
    'bright-magenta' = 0xFF00FF; 'bright-cyan' = 0x00FFFF; 'bright-white' = 0xFFFFFF
}

function Get-UsaBannerImageFormat {
    <#
    .SYNOPSIS
    Which image format a file is in, by its first bytes.
    .DESCRIPTION
    In:  a file's full path.
    Out: png, jpeg, gif, bmp, tiff, webp or svg; unknown for anything else.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    $head = [byte[]]::new(1024)
    $stream = [System.IO.File]::OpenRead($Path)
    try { $count = $stream.Read($head, 0, $head.Length) }
    finally { $stream.Dispose() }
    $hex = [System.BitConverter]::ToString($head, 0, [Math]::Min($count, 16))
    # Pairs, not a hashtable: the order they are tried in is the order written.
    $signatures = @(
        , @('png', '^89-50-4E-47-0D-0A-1A-0A')
        , @('jpeg', '^FF-D8-FF')
        , @('gif', '^47-49-46-38')
        , @('bmp', '^42-4D')
        , @('tiff', '^(49-49-2A-00|4D-4D-00-2A)')
        , @('webp', '^52-49-46-46-..-..-..-..-57-45-42-50')
    )
    foreach ($signature in $signatures) {
        if ($hex -match $signature[1]) { return $signature[0] }
    }
    if ([System.Text.Encoding]::ASCII.GetString($head, 0, $count) -match '<svg[\s>]') { return 'svg' }
    'unknown'
}

function Find-UsaBannerImageMagick {
    <#
    .SYNOPSIS
    The path of ImageMagick's command, or nothing.
    .DESCRIPTION
    magick (ImageMagick 7) first, then convert (ImageMagick 6, which Ubuntu
    packages). Used on Linux only: on Windows, convert.exe is the disk tool.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    foreach ($name in 'magick', 'convert') {
        $found = @(Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue)
        if ($found.Count -gt 0) { return $found[0].Path }
    }
}

function Read-UsaBannerImage {
    <#
    .SYNOPSIS
    Reads an image file into pixels.
    .DESCRIPTION
    In:  the image's full path. -OnWindows replaces what this host is, for
         tests.
    Out: a [UsaBanner.ImageRgba].
    A PNG is read by the module's own reader on every system. Any other format
    goes to System.Drawing on Windows, and to ImageMagick elsewhere. Throws,
    saying what is wrong and what to do, when the file cannot be read.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [bool]$OnWindows = $IsWindows
    )
    Initialize-UsaBannerImageType
    $length = (Get-Item -LiteralPath $Path).Length
    if ($length -gt $script:UsaImageMaxBytes) {
        throw "UsaBanner: $Path is $([Math]::Ceiling($length / 1MB)) MB; images up to $($script:UsaImageMaxBytes / 1MB) MB are read."
    }
    $format = Get-UsaBannerImageFormat -Path $Path
    if ($format -eq 'png') { return Read-UsaBannerPng -Path $Path }
    if ($OnWindows) { return Read-UsaBannerImageSystemDrawing -Path $Path -Format $format }
    Read-UsaBannerImageMagick -Path $Path -Format $format
}

function Read-UsaBannerPng {
    <#
    .SYNOPSIS
    Reads a PNG file into pixels with the module's own reader.
    .DESCRIPTION
    In:  the PNG's full path, and the path to name in a message, when the PNG
         stands in for another file.
    Out: a [UsaBanner.ImageRgba].
    Throws with the reader's reason when the file is not a PNG, is damaged,
    or is larger than $script:UsaImageMaxPixels.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Shown = $Path
    )
    Initialize-UsaBannerImageType
    try { [UsaBanner.PngReader]::Decode([System.IO.File]::ReadAllBytes($Path), $script:UsaImageMaxPixels) }
    catch { throw "UsaBanner: $Shown cannot be read: $($_.Exception.GetBaseException().Message)." }
}

function Read-UsaBannerImageMagick {
    <#
    .SYNOPSIS
    Reads an image file into pixels through ImageMagick: formats other than
    PNG, on Linux.
    .DESCRIPTION
    In:  the image's full path, and its format (Get-UsaBannerImageFormat).
    Out: a [UsaBanner.ImageRgba]. ImageMagick writes the image's first frame
         to a temporary file as an 8-bit RGBA PNG, for the module's own reader;
         the file is removed after. An SVG is drawn at 192 dots an inch, on a
         transparent background.
    Throws when ImageMagick is not installed, saying how to install it, and
    with ImageMagick's own words when it cannot read the file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Format = 'unknown'
    )
    $magick = Find-UsaBannerImageMagick
    if (-not $magick) {
        throw "UsaBanner: $Path is $($script:UsaImageFormatNames[$Format]). On Linux, New-UsaBannerArt reads PNG by itself, and other formats through ImageMagick, which is not installed. Install it (sudo apt install imagemagick), or save the image as a PNG, then run New-UsaBannerArt again."
    }
    $png = [System.IO.Path]::GetTempFileName()
    try {
        # [0]: the first frame. PNG32: 8-bit RGBA, whatever the image was.
        $said = & $magick -density 192 -background none ('{0}[0]' -f $Path) -colorspace sRGB "PNG32:$png" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "UsaBanner: ImageMagick ($magick) cannot read $Path`: $((@($said) | ForEach-Object { "$_" }) -join ' ')"
        }
        Read-UsaBannerPng -Path $png -Shown $Path
    }
    finally { Remove-Item -LiteralPath $png -Force -ErrorAction SilentlyContinue }
}

function Find-UsaBannerBasicColor {
    <#
    .SYNOPSIS
    The basic colour, of the 16, nearest an RGB colour.
    .DESCRIPTION
    In:  a colour as 0xRRGGBB.
    Out: its name as art files write it, from $script:UsaBasicRgb: never
         black, which a dark terminal hides.
    Distance is RGB weighted by the two colours' mean red ("redmean"), which
    follows the eye better than plain RGB distance.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([int]$Rgb)
    $r = ($Rgb -shr 16) -band 255
    $g = ($Rgb -shr 8) -band 255
    $b = $Rgb -band 255
    $best = ''
    $bestDistance = [double]::MaxValue
    foreach ($name in $script:UsaBasicRgb.Keys) {
        $basic = $script:UsaBasicRgb[$name]
        $dr = $r - (($basic -shr 16) -band 255)
        $dg = $g - (($basic -shr 8) -band 255)
        $db = $b - ($basic -band 255)
        $meanRed = ($r + (($basic -shr 16) -band 255)) / 2
        $distance = (2 + $meanRed / 256) * $dr * $dr + 4 * $dg * $dg + (2 + (255 - $meanRed) / 256) * $db * $db
        if ($distance -lt $bestDistance) {
            $bestDistance = $distance
            $best = $name
        }
    }
    $best
}

function ConvertFrom-UsaBannerImage {
    <#
    .SYNOPSIS
    An image as art the module's renderer draws.
    .DESCRIPTION
    In:  the image (Read-UsaBannerImage); the art's size, most colours,
         background, fill and style, as New-UsaBannerArt takes them; the
         image file's name; and the art's name and metadata.
    Out: the art: name, title, artist, licence and source; art and mask; fill,
         when a part is drawn as fill; and a palette entry for each class a, b,
         c...: its colour, the nearest of the 16 basic colours, and a label
         with its share of the picture, and its colour in the image when that
         was too dark and was lightened.
    Writes a warning when the size asked for would not fit 64 x 30 and was
    made smaller. Throws when nothing is left to draw.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][object]$Image,
        [Parameter(Mandatory)][string]$ImageName,
        [int]$Columns,
        [int]$Rows,
        [int]$Colors = 6,
        [string]$Background = 'auto',
        [string]$Fill = 'auto',
        [ValidateSet('auto', 'shape', 'ramp')][string]$Style = 'auto',
        [string]$Name,
        [string]$Title,
        [string]$Artist = 'unknown',
        [string]$Licence = 'unknown',
        [string]$Source
    )
    Initialize-UsaBannerImageType
    $readChoice = {
        # In:  auto, none or #RRGGBB
        # Out: the mode, auto, none or color, and the colour as 0xRRGGBB (-1 for none)
        # Why: -Background and -Fill take the same three kinds of answer
        param([string]$Choice)
        if ($Choice -match '^#[0-9A-Fa-f]{6}$') { return 'color', [Convert]::ToInt32($Choice.Substring(1), 16) }
        $Choice.ToLowerInvariant(), -1
    }
    $settings = [UsaBanner.ArtSettings]::new()
    $settings.Columns = $Columns
    $settings.Rows = $Rows
    $settings.Colors = $Colors
    $settings.Style = $Style.ToLowerInvariant()
    $settings.Background, $settings.BackgroundRgb = & $readChoice $Background
    $settings.Fill, $settings.FillRgb = & $readChoice $Fill
    try { $result = [UsaBanner.ArtMaker]::Convert($Image, $settings) }
    catch { throw "UsaBanner: $ImageName cannot be made into art: $($_.Exception.GetBaseException().Message)." }
    if ($result.Fitted) { Write-Warning "UsaBanner: $($result.Fitted)." }

    $palette = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    for ($k = 0; $k -lt $result.Rgb.Count; $k++) {
        $percent = [int][Math]::Round($result.Share[$k] * 100)
        $notes = @($(if ($percent -gt 0) { "$percent% of the picture" } else { 'under 1% of the picture' }))
        if ($result.Rgb[$k] -ne $result.ImageRgb[$k]) { $notes += "$([UsaBanner.ArtMaker]::Hex($result.ImageRgb[$k])) in the image, lightened so a dark terminal shows it" }
        if ($k -eq $result.FillClass) { $notes += 'drawn as the fill character: a space before login' }
        $palette[[string][char](97 + $k)] = [ordered]@{
            label = $notes -join '; '
            rgb   = [UsaBanner.ArtMaker]::Hex($result.Rgb[$k])
            basic = Find-UsaBannerBasicColor -Rgb $result.Rgb[$k]
        }
    }
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ImageName)
    $artName = (($(if ($Name) { $Name } else { $baseName })).ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if (-not $Title) { $Title = $baseName }
    if (-not $Source) {
        $colours = if ($result.Rgb.Count -eq 1) { '1 colour' } else { "$($result.Rgb.Count) colours" }
        $Source = "made by New-UsaBannerArt from $ImageName`: $($result.Style) style, $colours, background $($result.Background)"
    }
    $art = [ordered]@{
        name    = $(if ($artName) { $artName } else { 'art' })
        title   = $Title
        artist  = $Artist
        licence = $Licence
        source  = $Source
        art     = [string[]]$result.Art
        mask    = [string[]]$result.Mask
    }
    if ($result.FillClass -ge 0) {
        $art['fill'] = [ordered]@{ class = [string][char](97 + $result.FillClass); char = [string][UsaBanner.ArtMaker]::FillChar }
    }
    $art['palette'] = $palette
    $art
}
