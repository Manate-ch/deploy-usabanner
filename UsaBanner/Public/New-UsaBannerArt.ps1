function New-UsaBannerArt {
    <#
    .SYNOPSIS
    Turns an image into banner art: plain ASCII characters, with a colour for
    each part where the terminal has colour.
    .DESCRIPTION
    Returns one string per line of the art, with the colour escapes in it, as
    Show-UsaBannerArt does; at the console the lines print as the picture.
    -OutFile saves the art too, as a JSON file Show-UsaBannerArt -Path draws.

    +------------------+----------------------------------------------------+
    | Image            | Read by                                            |
    +------------------+----------------------------------------------------+
    | PNG              | the module itself, on every system                 |
    | JPEG, GIF, BMP,  | Windows' own decoder, System.Drawing; on Linux,    |
    | TIFF             | ImageMagick (sudo apt install imagemagick)         |
    | other formats    | ImageMagick, on Linux only                         |
    +------------------+----------------------------------------------------+

    How the image becomes art:
    - The background is left out: transparent pixels; or else, when one
      colour holds half of the image's edge or more, the pixels of that colour
      the edge reaches. -Background names the colour instead, or none keeps
      every pixel that is not transparent.
    - Colours: at most -Colors, taken from the image. A colour too dark for a
      dark terminal is lightened until it shows.
    - Shape style, for logos: each character's shape follows the outline, each
      character cell read as 2 x 4 dots. The largest part the picture
      encloses, such as the disc inside a badge's ring, is drawn as fill: a
      gap before login, and solid in colour (-Fill).
    - Ramp style, for photos: each character by brightness, from . to @, the
      brightest densest, for terminals with a dark background.
    - auto, the default style, is shape for an image with a background and
      few colours, and ramp for any other. -Verbose says which it took, with
      the colours and the background.

    The art is 40 columns wide unless -Width or -Height says otherwise, or
    narrower for a small image, at a column to two pixels. Its rows keep the
    image's shape: a character cell is about twice as tall as it is wide. Art
    may take 64 columns and 30 rows; a picture that would take more is made
    smaller, with a warning when -Width or -Height asked for the size.

    Under Windows PowerShell 5.1 the command runs itself in pwsh (PowerShell
    7), and stops with what to install when there is none.
    .PARAMETER Path
    The image file.
    .PARAMETER Width
    The art's width in characters, 1 to 64.
    .PARAMETER Height
    The art's height in rows, 1 to 30. Given with -Width, the picture is
    stretched to fit both.
    .PARAMETER Colors
    The most colours, 1 to 16; 6 by default.
    .PARAMETER Background
    auto, the default; none, to keep every pixel that is not transparent; or a
    colour as #RRGGBB, to leave out the pixels of about that colour that the
    image's edge reaches.
    .PARAMETER Fill
    Shape style: the part drawn as fill, a gap before login and solid in
    colour. auto, the default, is the largest part the picture encloses;
    none draws no part as fill; a colour as #RRGGBB picks the part nearest
    it.
    .PARAMETER Style
    auto, the default; shape; or ramp.
    .PARAMETER ColorMode
    How the lines returned are coloured, as for Show-UsaBannerArt; auto by
    default. The saved file holds the colours whatever the mode.
    .PARAMETER OutFile
    A JSON file to save the art in.
    .PARAMETER Force
    Replace the -OutFile file when there is one.
    .PARAMETER Title
    The art's title in the saved file; the image's name by default.
    .PARAMETER Artist
    Who made the image, in the saved file; unknown by default.
    .PARAMETER Licence
    The image's licence, in the saved file; unknown by default.
    .PARAMETER Source
    Where the art came from, in the saved file; by default, the image's file
    name and how the art was made.
    .EXAMPLE
    New-UsaBannerArt -Path ./logo.png
    .EXAMPLE
    New-UsaBannerArt -Path ./logo.png -Width 30 -Colors 3 -OutFile ./logo.json
    .EXAMPLE
    New-UsaBannerArt -Path ./logo.jpg -Background '#FFFFFF' -ColorMode none
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [ValidateRange(1, 64)]
        [int]$Width,

        [ValidateRange(1, 30)]
        [int]$Height,

        [ValidateRange(1, 16)]
        [int]$Colors = 6,

        [ValidatePattern('^(auto|none|#[0-9A-Fa-f]{6})$')]
        [string]$Background = 'auto',

        [ValidatePattern('^(auto|none|#[0-9A-Fa-f]{6})$')]
        [string]$Fill = 'auto',

        [ValidateSet('auto', 'shape', 'ramp')]
        [string]$Style = 'auto',

        [ValidateSet('auto', 'truecolor', '256', '16', 'none')]
        [string]$ColorMode = 'auto',

        [string]$OutFile,

        [switch]$Force,

        [string]$Title,

        [string]$Artist,

        [string]$Licence,

        [string]$Source
    )
    begin {
        $handedOff = Test-UsaBannerHandoff
        if ($handedOff) { Invoke-UsaBannerHandoff -Command 'New-UsaBannerArt' -Parameters $PSBoundParameters }
    }
    end {
        if ($handedOff) { return }
        $imagePath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) { throw "UsaBanner: there is no file at $Path." }
        $outPath = ''
        if ($OutFile) {
            $outPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($OutFile)
            if ((Test-Path -LiteralPath $outPath) -and -not $Force) { throw "UsaBanner: $OutFile is there already; -Force replaces it." }
        }
        $picture = Read-UsaBannerImage -Path $imagePath
        $made = @{
            Image      = $picture
            ImageName  = [System.IO.Path]::GetFileName($imagePath)
            Name       = [System.IO.Path]::GetFileNameWithoutExtension($(if ($outPath) { $outPath } else { $imagePath }))
            Columns    = $Width
            Rows       = $Height
            Colors     = $Colors
            Background = $Background
            Fill       = $Fill
            Style      = $Style
        }
        foreach ($key in 'Title', 'Artist', 'Licence', 'Source') {
            if ($PSBoundParameters.ContainsKey($key)) { $made[$key] = $PSBoundParameters[$key] }
        }
        $art = ConvertFrom-UsaBannerImage @made
        $widest = (@($art['art']) | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
        Write-Verbose "UsaBanner: $($art['source']); $widest x $(@($art['art']).Count)."
        if ($outPath) { Save-UsaBannerArtFile -Art $art -Path $outPath }
        ConvertTo-UsaBannerArtText -Art $art -ColorMode (Resolve-UsaBannerColorMode -Requested $ColorMode)
    }
}
