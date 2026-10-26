# ImageArt.Logged.ps1 - the functions of ImageArt.ps1 that PowerShell logs whole at each import (D30).

function Initialize-UsaBannerImageType {
    <#
    .SYNOPSIS
    Compiles ImageArt.cs into this process, once.
    .DESCRIPTION
    Each function here that needs the C# types calls this first; once they
    are there it does nothing. The module does not compile them when it
    loads: compiling takes a second or two, and only New-UsaBannerArt needs
    them.
    #>
    [CmdletBinding()]
    param()
    if ('UsaBanner.ArtMaker' -as [type]) { return }
    Add-Type -Path $script:UsaImageArtSource
}

function Read-UsaBannerImageSystemDrawing {
    <#
    .SYNOPSIS
    Reads an image file into pixels with Windows' own decoder, System.Drawing.
    .DESCRIPTION
    In:  the image's full path, and its format (Get-UsaBannerImageFormat).
    Out: a [UsaBanner.ImageRgba]; the first frame of a GIF or TIFF that has
         several.
    System.Drawing ships with PowerShell 7 on Windows, and reads PNG, JPEG,
    GIF, BMP and TIFF. Throws for an SVG, which it cannot read, and with
    Windows' reason for a file it cannot read.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Format
    )
    if ($Format -eq 'svg') {
        throw "UsaBanner: $Path is an SVG drawing, and Windows does not read those as pictures. Save it as a PNG, then run New-UsaBannerArt again."
    }
    Initialize-UsaBannerImageType
    Add-Type -AssemblyName System.Drawing
    try { $bitmap = [System.Drawing.Bitmap]::new($Path) }
    catch { throw "UsaBanner: Windows cannot read $Path as an image (it reads PNG, JPEG, GIF, BMP and TIFF): $($_.Exception.GetBaseException().Message)" }
    try {
        if ([long]$bitmap.Width * $bitmap.Height -gt $script:UsaImageMaxPixels) {
            throw "UsaBanner: $Path cannot be read: it is $($bitmap.Width) x $($bitmap.Height) pixels, more than the $($script:UsaImageMaxPixels / 1000000) million UsaBanner reads; make it smaller first."
        }
        $box = [System.Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height)
        $locked = $bitmap.LockBits($box, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $bytes = [byte[]]::new($locked.Stride * $bitmap.Height)
            [System.Runtime.InteropServices.Marshal]::Copy($locked.Scan0, $bytes, 0, $bytes.Length)
            [UsaBanner.ImageRgba]::FromBgra($bytes, $bitmap.Width, $bitmap.Height, $locked.Stride)
        }
        finally { $bitmap.UnlockBits($locked) }
    }
    finally { $bitmap.Dispose() }
}
