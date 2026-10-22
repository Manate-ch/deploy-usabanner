function Show-UsaBannerArt {
    <#
    .SYNOPSIS
    Draws one of the module's pieces of art, an art file, or a name in block
    letters, in colour where the terminal has it; or lists the art there is.
    .DESCRIPTION
    Returns one string per line of the art, with the colour escapes in it;
    at the console the lines print as the picture.

    +-----------+------------------------------------------------------+
    | ColorMode | Draws                                                |
    +-----------+------------------------------------------------------+
    | auto      | the user's USABANNER_COLOR; else plain when NO_COLOR |
    |           | is set; else what the terminal says it supports      |
    | truecolor | 24-bit colour, with the gradients and the sheen      |
    | 256       | each cell in the nearest of the 256 xterm colours    |
    | 16        | one basic colour per part, no gradient               |
    | none      | the plain ASCII art, exactly as shown before login   |
    +-----------+------------------------------------------------------+

    Art drawn in the OS colour takes this host's: Windows blue, Ubuntu
    orange, or a neutral grey on any other system. -Os draws it in another
    OS's colour instead.

    With -Text, a name set in block letters instead, as the banner sets the
    company's: in the welcome line's colours from left to right, in the
    Pixel font when it fits 64 columns; else in the Small font, on two lines
    if it must; else in spaced capitals; else as written. Lower case comes
    out in capitals. With -Font too, the name is set in that font alone, and
    may come out at most 64 columns wide.

    With -Path, the art in a file instead, such as one New-UsaBannerArt
    saved; it must keep the same rules as the module's own art.

    With -List, one line per piece instead: its name, its folder (base for
    ours, apps for another owner's logo, drawn by us), its size in columns by
    rows, its title, who drew it (and whose logo it is), and its licence.

    Under Windows PowerShell 5.1 the command runs itself in pwsh
    (PowerShell 7), and stops with what to install when there is none.
    .PARAMETER Name
    The art to draw; -List shows what there is.
    .PARAMETER ColorMode
    One of the modes in the table; auto by default.
    .PARAMETER Os
    Whose colour art drawn in the OS colour takes: windows, ubuntu or linux
    (any other system); auto, the default, is this host's.
    .PARAMETER Text
    A name to set in block letters instead of drawing a piece of art.
    .PARAMETER Font
    One font to set -Text in: pixel or small. Without it, the name takes
    the first form that fits, as on the banner.
    .PARAMETER Path
    An art file to draw instead of a piece of the module's art.
    .PARAMETER List
    List every piece of art instead of drawing one.
    .EXAMPLE
    Show-UsaBannerArt
    .EXAMPLE
    Show-UsaBannerArt -Name rabbit -ColorMode 256
    .EXAMPLE
    Show-UsaBannerArt -Name server -Os ubuntu
    .EXAMPLE
    Show-UsaBannerArt -Text 'Contoso LLC'
    .EXAMPLE
    Show-UsaBannerArt -Text 'Contoso Pharmaceuticals' -ColorMode none
    .EXAMPLE
    Show-UsaBannerArt -Path ./logo.json -ColorMode none
    .EXAMPLE
    Show-UsaBannerArt -List
    #>
    [CmdletBinding(DefaultParameterSetName = 'Draw')]
    [OutputType([string])]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Draw')]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$Name = 'rabbit',

        [Parameter(ParameterSetName = 'Draw')]
        [Parameter(ParameterSetName = 'Text')]
        [Parameter(ParameterSetName = 'File')]
        [ValidateSet('auto', 'truecolor', '256', '16', 'none')]
        [string]$ColorMode = 'auto',

        [Parameter(ParameterSetName = 'Draw')]
        [Parameter(ParameterSetName = 'File')]
        [ValidateSet('auto', 'windows', 'ubuntu', 'linux')]
        [string]$Os = 'auto',

        [Parameter(Mandatory, ParameterSetName = 'Text')]
        [ValidateNotNullOrEmpty()]
        [string]$Text,

        [Parameter(ParameterSetName = 'Text')]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$Font,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'List')]
        [switch]$List
    )
    begin {
        $handedOff = Test-UsaBannerHandoff
        if ($handedOff) { Invoke-UsaBannerHandoff -Command 'Show-UsaBannerArt' -Parameters $PSBoundParameters }
    }
    end {
        if ($handedOff) { return }
        if ($List) {
            $index = Get-UsaBannerArtIndex
            foreach ($piece in $index.Keys) {
                $art = Get-UsaBannerArtData -Name $piece
                $rows = @($art['art'])
                $width = ($rows | ForEach-Object { ([string]$_).Length } | Measure-Object -Maximum).Maximum
                $whose = if ($index[$piece].Folder -eq 'apps') { "logo of $($art['owner']), drawn by $($art['artist'])" } else { "by $($art['artist'])" }
                '{0,-14} {1,-4} {2,5}  {3} ({4}, {5})' -f $piece, $index[$piece].Folder, "$($width)x$($rows.Count)", $art['title'], $whose, $art['licence']
            }
            return
        }
        if ($PSCmdlet.ParameterSetName -eq 'Text') {
            if ($Font) { $art = ConvertTo-UsaBannerWordArt -Text $Text -Font (Get-UsaBannerFontData -Name $Font) }
            else { $art = ConvertTo-UsaBannerNameArt -Name $Text }
        }
        else {
            $art = if ($PSCmdlet.ParameterSetName -eq 'File') { Read-UsaBannerArtFile -Path $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path) } else { Get-UsaBannerArtData -Name $Name }
            $artOs = $Os
            if ($artOs -eq 'auto') { $artOs = Get-UsaBannerHostOs }
            $art = Resolve-UsaBannerArtTint -Art $art -Os $artOs
        }
        $mode = Resolve-UsaBannerColorMode -Requested $ColorMode
        ConvertTo-UsaBannerArtText -Art $art -ColorMode $mode
    }
}
