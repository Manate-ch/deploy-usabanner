function Show-UsaBannerArt {
    <#
    .SYNOPSIS
    Draws one of the module's pieces of art, in colour where the terminal
    has it.
    .DESCRIPTION
    Returns one string per line of the art, with the colour escapes in it;
    at the console the lines print as the picture.

    +-----------+------------------------------------------------------+
    | ColorMode | Draws                                                |
    +-----------+------------------------------------------------------+
    | auto      | the user's USABANNER_COLOR; else none when NO_COLOR  |
    |           | is set; else what the terminal says it supports      |
    | truecolor | 24-bit colour, with the gradients and the sheen      |
    | 256       | each cell in the nearest of the 256 xterm colours    |
    | 16        | one basic colour per part, no gradient               |
    | none      | the plain ASCII art, exactly as shown before login   |
    +-----------+------------------------------------------------------+

    Under Windows PowerShell 5.1 the command runs itself in pwsh
    (PowerShell 7), and stops with what to install when there is none.
    .PARAMETER Name
    The art to draw: rabbit, so far the only one.
    .PARAMETER ColorMode
    One of the modes in the table; auto by default.
    .EXAMPLE
    Show-UsaBannerArt
    .EXAMPLE
    Show-UsaBannerArt -Name rabbit -ColorMode 256
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [ValidatePattern('^[a-z0-9][a-z0-9-]*$')]
        [string]$Name = 'rabbit',

        [ValidateSet('auto', 'truecolor', '256', '16', 'none')]
        [string]$ColorMode = 'auto'
    )
    begin {
        $handedOff = Test-UsaBannerHandoff
        if ($handedOff) { Invoke-UsaBannerHandoff -Command 'Show-UsaBannerArt' -Parameters $PSBoundParameters }
    }
    end {
        if ($handedOff) { return }
        $art = Get-UsaBannerArtData -Name $Name
        $mode = Resolve-UsaBannerColorMode -Requested $ColorMode
        ConvertTo-UsaBannerArtText -Art $art -ColorMode $mode
    }
}
