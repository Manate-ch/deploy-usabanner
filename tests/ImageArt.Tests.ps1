# New-UsaBannerArt: an image made into art (docs/DECISIONS.md, D19). The
# module reads PNG itself; the tests write their PNGs with TestPng.ps1, a
# writer kept apart from the reader.

BeforeDiscovery {
    # Every colour type at every bit depth it allows, interlaced and not.
    $readerCases = foreach ($interlace in $false, $true) {
        foreach ($pair in @(@(0, 1), @(0, 2), @(0, 4), @(0, 8), @(0, 16), @(2, 8), @(2, 16), @(3, 1), @(3, 2), @(3, 4), @(3, 8), @(4, 8), @(4, 16), @(6, 8), @(6, 16))) {
            @{ Type = $pair[0]; Depth = $pair[1]; Interlace = $interlace; Layout = $(if ($interlace) { 'interlaced' } else { 'not interlaced' }) }
        }
    }
    $formatCases = @(
        @{ Format = 'png'; Name = 'PNG'; Head = '89504E470D0A1A0A0000000D49484452' }
        @{ Format = 'jpeg'; Name = 'JPEG'; Head = 'FFD8FFE000104A464946' }
        @{ Format = 'gif'; Name = 'GIF'; Head = '474946383961' }
        @{ Format = 'bmp'; Name = 'BMP'; Head = '424D3600000000000000' }
        @{ Format = 'tiff'; Name = 'TIFF, Intel order'; Head = '49492A0008000000' }
        @{ Format = 'tiff'; Name = 'TIFF, Motorola order'; Head = '4D4D002A00000008' }
        @{ Format = 'webp'; Name = 'WebP'; Head = '524946462400000057454250' }
        @{ Format = 'svg'; Name = 'SVG'; Head = [Convert]::ToHexString([System.Text.Encoding]::ASCII.GetBytes("<?xml version=`"1.0`"?>`n<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"4`">")) }
        @{ Format = 'unknown'; Name = 'text'; Head = [Convert]::ToHexString([System.Text.Encoding]::ASCII.GetBytes('hello there')) }
    )
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'TestPng.ps1')
    InModuleScope UsaBanner { Initialize-UsaBannerImageType }
    $esc = [char]27

    function Read-TestPng {
        # In:  a PNG's path
        # Out: its pixels, as the module's own reader reads them
        # Why: most reader tests compare those with what was written
        param([string]$Path)
        InModuleScope UsaBanner -Parameters @{ Path = $Path } { param($Path) Read-UsaBannerPng -Path $Path }
    }

    function New-TestImage {
        # In:  a file name, a size, and each pixel's [r, g, b, a] from its x and y
        # Out: the full path of the PNG written in TestDrive: colour type 6, 8 bits
        # Why: the conversion tests draw their pictures from shapes
        param([string]$Name, [int]$Width, [int]$Height, [scriptblock]$Pixel)
        $path = Join-Path $TestDrive $Name
        New-TestPng -Width $Width -Height $Height -Rgba (New-TestPicture -Width $Width -Height $Height -Pixel $Pixel) -Path $path
        $path
    }

    function Add-TestChunk {
        # In:  a PNG's bytes, and a chunk's type and data
        # Out: the bytes with the chunk right after the header chunk, its CRC worked out
        # Why: the reader must refuse a critical chunk it does not know, and skip an ancillary one
        param([byte[]]$Png, [string]$Type, [byte[]]$Data = [byte[]]::new(0))
        $body = [byte[]]([System.Text.Encoding]::ASCII.GetBytes($Type) + $Data)
        $length = [BitConverter]::GetBytes([uint32]$Data.Length)
        [Array]::Reverse($length)
        $crc = [BitConverter]::GetBytes([UsaBannerTests.TestPng]::Crc($body, 0, $body.Length))
        [Array]::Reverse($crc)
        [byte[]]($Png[0..32] + $length + $body + $crc + $Png[33..($Png.Length - 1)])
    }

    # A square ring, 8 pixels thick, around a square of white: 40 x 40 pixels, inside a margin
    # of 4. At 20 columns each dot is one pixel, so the ring is 4 cells wide and 2 rows tall.
    $ringPixel = {
        param($x, $y)
        if ($x -lt 4 -or $x -ge 44 -or $y -lt 4 -or $y -ge 44) { return $margin }
        if ($x -lt 12 -or $x -ge 36 -or $y -lt 12 -or $y -ge 36) { return $ring }
        255, 255, 255, 255
    }
    $ringArt = @(
        '88888888888888888888'
        '88888888888888888888'
        @(1..6 | ForEach-Object { '8888            8888' })
        '88888888888888888888'
        '88888888888888888888'
    )
    $ringMask = @(
        'aaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaaaaaaaaa'
        @(1..6 | ForEach-Object { 'aaaabbbbbbbbbbbbaaaa' })
        'aaaaaaaaaaaaaaaaaaaa'
        'aaaaaaaaaaaaaaaaaaaa'
    )
    $margin = @(0, 0, 0, 0)
    $ring = @(30, 111, 217, 255)
    $ringPng = New-TestImage -Name 'ring.png' -Width 48 -Height 48 -Pixel $ringPixel
    # A grey gradient, dark at the left: a photo, to the auto style.
    $gradientPng = New-TestImage -Name 'gradient.png' -Width 80 -Height 20 -Pixel { param($x, $y) ($x * 3), ($x * 3), ($x * 3), 255 }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the PNG reader' {
    It 'checks chunks with the standard CRC-32, as the tests'' writer does' {
        $check = [System.Text.Encoding]::ASCII.GetBytes('123456789')
        '{0:X8}' -f [UsaBanner.PngReader]::Crc32($check, 0, 9) | Should -BeExactly 'CBF43926'
        '{0:X8}' -f [UsaBannerTests.TestPng]::Crc($check, 0, 9) | Should -BeExactly 'CBF43926'
    }

    It 'reads colour type <Type> at <Depth> bits, <Layout>, as written' -ForEach $readerCases {
        $colours = [int][Math]::Min(256, [Math]::Pow(2, $Depth))
        $rgba = New-TestPicture -Width 13 -Height 11 -Pixel {
            param($x, $y)
            $n = $y * 13 + $x
            # Each channel in its own parentheses: a comma binds tighter than %.
            if ($Type -eq 3) {
                $k = $n % $colours
                return ((17 * $k) % 256), ((91 * $k + 7) % 256), ((53 * $k + 3) % 256), $(if ($k % 3 -eq 0) { 255 } else { (40 * $k) % 256 })
            }
            ((37 * $n + 11) % 256), ((59 * $n + 5) % 256), ((83 * $n + 29) % 256), ((13 * $n + 100) % 256)
        }
        $path = Join-Path $TestDrive "type$Type-depth$Depth-$Layout.png"
        New-TestPng -Width 13 -Height 11 -Rgba $rgba -Path $path -ColorType $Type -Depth $Depth -Interlace:$Interlace
        # What the reader must give: each sample at the PNG's depth, back to 8 bits as the
        # specification scales it; 16 bits to its high byte.
        $back = {
            param([int]$Value)
            if ($Depth -ge 8) { return $Value }
            [int][Math]::Floor(($Value -shr (8 - $Depth)) * 255 / ([Math]::Pow(2, $Depth) - 1))
        }
        $expected = [byte[]]::new($rgba.Length)
        for ($i = 0; $i -lt 143; $i++) {
            $r = $rgba[4 * $i]; $g = $rgba[4 * $i + 1]; $b = $rgba[4 * $i + 2]; $a = $rgba[4 * $i + 3]
            $pixel = switch ($Type) {
                0 { $v = & $back $r; , @($v, $v, $v, 255) }
                2 { , @((& $back $r), (& $back $g), (& $back $b), 255) }
                3 { , @($r, $g, $b, $a) }
                4 { $v = & $back $r; , @($v, $v, $v, (& $back $a)) }
                6 { , @((& $back $r), (& $back $g), (& $back $b), (& $back $a)) }
            }
            for ($c = 0; $c -lt 4; $c++) { $expected[4 * $i + $c] = $pixel[$c] }
        }
        $image = Read-TestPng -Path $path
        "$($image.Width) x $($image.Height)" | Should -Be '13 x 11'
        [Convert]::ToHexString($image.Pixels) | Should -BeExactly ([Convert]::ToHexString($expected))
    }

    It 'reads rows stored with filter <Filter> alone' -ForEach @(0..4 | ForEach-Object { @{ Filter = $_ } }) {
        $rgba = New-TestPicture -Width 9 -Height 7 -Pixel { param($x, $y) ((29 * $x + 3 * $y) % 256), ((7 * $x * $y) % 256), ((200 - 11 * $y) % 256), 255 }
        $path = Join-Path $TestDrive "filter$Filter.png"
        New-TestPng -Width 9 -Height 7 -Rgba $rgba -Path $path -Filter $Filter
        [Convert]::ToHexString((Read-TestPng -Path $path).Pixels) | Should -BeExactly ([Convert]::ToHexString($rgba))
    }

    It 'draws the tRNS key colour transparent, in grey and in 16-bit RGB to the last bit' {
        $grey = Join-Path $TestDrive 'grey-key.png'
        [System.IO.File]::WriteAllBytes($grey, [UsaBannerTests.TestPng]::Write(3, 1, 0, 8, [int[]](10, 20, 30), $null, $null, [int[]](20), $false, 0))
        [Convert]::ToHexString((Read-TestPng -Path $grey).Pixels) | Should -BeExactly '0A0A0AFF141414001E1E1EFF'
        $rgb = Join-Path $TestDrive 'rgb-key.png'
        $samples = [int[]](0x1234, 0x5678, 0x9ABC, 0x1111, 0x2222, 0x3333, 0x1112, 0x2222, 0x3333)
        [System.IO.File]::WriteAllBytes($rgb, [UsaBannerTests.TestPng]::Write(3, 1, 2, 16, $samples, $null, $null, [int[]](0x1111, 0x2222, 0x3333), $false, 0))
        [Convert]::ToHexString((Read-TestPng -Path $rgb).Pixels) | Should -BeExactly '12569AFF11223300112233FF'
    }

    It 'skips an ancillary chunk it does not know' {
        $rgba = New-TestPicture -Width 3 -Height 2 -Pixel { param($x, $y) (80 * $x), (100 * $y), 7, 255 }
        $path = Join-Path $TestDrive 'plain.png'
        New-TestPng -Width 3 -Height 2 -Rgba $rgba -Path $path
        $withText = Join-Path $TestDrive 'with-text.png'
        [System.IO.File]::WriteAllBytes($withText, (Add-TestChunk -Png ([System.IO.File]::ReadAllBytes($path)) -Type 'tEXt' -Data ([System.Text.Encoding]::ASCII.GetBytes("Comment`0hi"))))
        [Convert]::ToHexString((Read-TestPng -Path $withText).Pixels) | Should -BeExactly ([Convert]::ToHexString($rgba))
    }

    It 'refuses <Case>, saying why' -ForEach @(
        @{ Case = 'a file that is not a PNG'; Change = { param([byte[]]$Png) [System.Text.Encoding]::ASCII.GetBytes('GIF89a, not a PNG') }; Expected = '*bad.png cannot be read: it is not a PNG file.' }
        @{ Case = 'a damaged chunk'; Change = { param([byte[]]$Png) $Png[$Png.Length - 20] = $Png[$Png.Length - 20] -bxor 0xFF; , $Png }; Expected = '*bad.png cannot be read: its IDAT chunk fails its CRC check: the file is damaged.' }
        @{ Case = 'a file cut short'; Change = { param([byte[]]$Png) , [byte[]]$Png[0..($Png.Length - 20)] }; Expected = '*bad.png cannot be read: it is cut short: a chunk runs past the end of the file.' }
        @{ Case = 'a critical chunk it does not know'; Change = { param([byte[]]$Png) , (Add-TestChunk -Png $Png -Type 'ABCD') }; Expected = "*bad.png cannot be read: it needs its ABCD chunk read, and UsaBanner's PNG reader does not know it." }
    ) {
        $rgba = New-TestPicture -Width 13 -Height 11 -Pixel { param($x, $y) (19 * $x), (23 * $y), (($x * $y) % 256), 255 }
        $good = Join-Path $TestDrive 'good.png'
        New-TestPng -Width 13 -Height 11 -Rgba $rgba -Path $good
        $bad = Join-Path $TestDrive 'bad.png'
        [System.IO.File]::WriteAllBytes($bad, [byte[]](& $Change ([System.IO.File]::ReadAllBytes($good))))
        { Read-TestPng -Path $bad } | Should -Throw $Expected
    }

    It 'refuses a row filter PNG does not have' {
        $path = Join-Path $TestDrive 'filter5.png'
        [System.IO.File]::WriteAllBytes($path, [UsaBannerTests.TestPng]::Write(2, 2, 0, 8, [int[]](1, 2, 3, 4), $null, $null, $null, $false, 5))
        { Read-TestPng -Path $path } | Should -Throw '*filter5.png cannot be read: row 0 names filter 5, which PNG does not have: the file is damaged.'
    }

    It 'refuses an image with more pixels than it reads, before reading them' {
        $rgba = New-TestPicture -Width 13 -Height 11 -Pixel { param($x, $y) 1, 2, 3, 255 }
        $path = Join-Path $TestDrive 'big.png'
        New-TestPng -Width 13 -Height 11 -Rgba $rgba -Path $path
        {
            InModuleScope UsaBanner -Parameters @{ Path = $path } {
                param($Path)
                $saved = $script:UsaImageMaxPixels
                try {
                    $script:UsaImageMaxPixels = 100
                    Read-UsaBannerPng -Path $Path
                }
                finally { $script:UsaImageMaxPixels = $saved }
            }
        } | Should -Throw '*big.png cannot be read: it is 13 x 11 pixels, more than the 100 UsaBanner reads; make it smaller first.'
    }
}

Describe 'reading an image file' {
    It 'tells <Name> by its first bytes' -ForEach $formatCases {
        $path = Join-Path $TestDrive 'sample.bin'
        [System.IO.File]::WriteAllBytes($path, [Convert]::FromHexString($Head))
        InModuleScope UsaBanner -Parameters @{ Path = $path } { param($Path) Get-UsaBannerImageFormat -Path $Path } | Should -BeExactly $Format
    }

    It 'reads a PNG with its own reader on every system, so a PNG makes the same art everywhere' {
        Mock -ModuleName UsaBanner Read-UsaBannerImageSystemDrawing { throw 'System.Drawing was asked' }
        Mock -ModuleName UsaBanner Find-UsaBannerImageMagick { throw 'ImageMagick was asked' }
        $expected = [Convert]::ToHexString((Read-TestPng -Path $ringPng).Pixels)
        foreach ($onWindows in $true, $false) {
            $image = InModuleScope UsaBanner -Parameters @{ Path = $ringPng; OnWindows = $onWindows } { param($Path, $OnWindows) Read-UsaBannerImage -Path $Path -OnWindows $OnWindows }
            [Convert]::ToHexString($image.Pixels) | Should -BeExactly $expected
        }
    }

    It 'on Windows, says an SVG must be saved as a PNG first' {
        $svg = Join-Path $TestDrive 'logo.svg'
        Set-Content -LiteralPath $svg -Value '<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"></svg>'
        { InModuleScope UsaBanner -Parameters @{ Path = $svg } { param($Path) Read-UsaBannerImage -Path $Path -OnWindows $true } } |
            Should -Throw '*logo.svg is an SVG drawing, and Windows does not read those as pictures. Save it as a PNG, then run New-UsaBannerArt again.'
    }

    It 'on Linux, says how to install ImageMagick when another format comes without it' {
        $jpeg = Join-Path $TestDrive 'photo.jpg'
        [System.IO.File]::WriteAllBytes($jpeg, [Convert]::FromHexString('FFD8FFE000104A46494600'))
        Mock -ModuleName UsaBanner Find-UsaBannerImageMagick { }
        { InModuleScope UsaBanner -Parameters @{ Path = $jpeg } { param($Path) Read-UsaBannerImage -Path $Path -OnWindows $false } } |
            Should -Throw '*photo.jpg is a JPEG image. On Linux, New-UsaBannerArt reads PNG by itself, and other formats through ImageMagick, which is not installed. Install it (sudo apt install imagemagick), or save the image as a PNG, then run New-UsaBannerArt again.'
    }

    It 'on Linux, reads other formats through ImageMagick, and removes the PNG it had ImageMagick write' -Skip:$IsWindows {
        $gif = Join-Path $TestDrive 'logo.gif'
        [System.IO.File]::WriteAllBytes($gif, [System.Text.Encoding]::ASCII.GetBytes('GIF89a'))
        $said = Join-Path $TestDrive 'magick-arguments.txt'
        $fake = Join-Path $TestDrive 'magick'
        # A stand-in for ImageMagick: it notes its arguments, then writes the ring as the PNG asked for.
        Set-Content -LiteralPath $fake -Value @(
            '#!/bin/sh'
            "printf '%s\n' `"`$@`" > '$said'"
            'for last; do :; done'
            "cp '$ringPng' `"`${last#PNG32:}`""
        )
        & chmod +x $fake
        Mock -ModuleName UsaBanner Find-UsaBannerImageMagick ([scriptblock]::Create("'$fake'"))
        $image = InModuleScope UsaBanner -Parameters @{ Path = $gif } { param($Path) Read-UsaBannerImage -Path $Path -OnWindows $false }
        [Convert]::ToHexString($image.Pixels) | Should -BeExactly ([Convert]::ToHexString((Read-TestPng -Path $ringPng).Pixels))
        $arguments = @(Get-Content -LiteralPath $said)
        $arguments[0..6] | Should -Be @('-density', '192', '-background', 'none', "$gif[0]", '-colorspace', 'sRGB')
        $arguments[7] | Should -BeLike 'PNG32:*'
        Test-Path -LiteralPath $arguments[7].Substring(6) | Should -BeFalse
    }

    It 'on Linux, says what ImageMagick said when it cannot read a file' -Skip:$IsWindows {
        $gif = Join-Path $TestDrive 'broken.gif'
        [System.IO.File]::WriteAllBytes($gif, [System.Text.Encoding]::ASCII.GetBytes('GIF89a'))
        $fake = Join-Path $TestDrive 'magick-fails'
        Set-Content -LiteralPath $fake -Value @('#!/bin/sh', 'echo "convert: improper image header" >&2', 'exit 1')
        & chmod +x $fake
        Mock -ModuleName UsaBanner Find-UsaBannerImageMagick ([scriptblock]::Create("'$fake'"))
        { InModuleScope UsaBanner -Parameters @{ Path = $gif } { param($Path) Read-UsaBannerImage -Path $Path -OnWindows $false } } |
            Should -Throw "*ImageMagick ($fake) cannot read *broken.gif: convert: improper image header"
    }
}

Describe 'an image made into art' {
    It 'draws a logo''s outline in shape style, and the part it encloses as fill: a gap before login' {
        $json = Join-Path $TestDrive 'ring.json'
        (@(New-UsaBannerArt -Path $ringPng -ColorMode none -OutFile $json) -join "`n") | Should -BeExactly ($ringArt -join "`n")
        $art = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable
        (@($art['mask']) -join "`n") | Should -BeExactly ($ringMask -join "`n")
        $art['fill']['class'] | Should -BeExactly 'b'
        $art['fill']['char'] | Should -BeExactly '8'
        $art['palette']['a']['rgb'] | Should -BeExactly '#1E6FD9'
        $art['palette']['a']['basic'] | Should -BeExactly 'bright-blue'
        $art['palette']['a']['label'] | Should -BeExactly '64% of the picture'
        $art['palette']['b']['rgb'] | Should -BeExactly '#FFFFFF'
        $art['palette']['b']['label'] | Should -BeExactly '36% of the picture; drawn as the fill character: a space before login'
        $art['source'] | Should -BeExactly 'made by New-UsaBannerArt from ring.png: shape style, 2 colours, background transparent'
        InModuleScope UsaBanner -Parameters @{ Art = $art } { param($Art) Test-UsaBannerArtData -Art $Art } | Should -BeNullOrEmpty
    }

    It 'draws the fill in its colour, with the fill character, where the terminal has colour' {
        $row = @(New-UsaBannerArt -Path $ringPng -ColorMode truecolor)[2]
        $row | Should -BeExactly ("$esc[38;2;30;111;217m8888$esc[38;2;255;255;255m888888888888$esc[38;2;30;111;217m8888$esc[0m")
    }

    It 'leaves out a background of one colour the edge reaches, but not that colour inside the picture' {
        $margin = @(255, 255, 255, 255)
        $ring = @(0, 0, 0, 255)
        $png = New-TestImage -Name 'black-ring.png' -Width 48 -Height 48 -Pixel $ringPixel
        $json = Join-Path $TestDrive 'black-ring.json'
        (@(New-UsaBannerArt -Path $png -ColorMode none -OutFile $json) -join "`n") | Should -BeExactly ($ringArt -join "`n")
        $art = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable
        $art['fill']['class'] | Should -BeExactly 'b'
        $art['source'] | Should -BeLike '*background #FFFFFF'
    }

    It 'lightens a colour too dark for a dark terminal, and says so' {
        $margin = @(0, 0, 0, 0)
        $ring = @(0, 0, 0, 255)
        $png = New-TestImage -Name 'dark-ring.png' -Width 48 -Height 48 -Pixel $ringPixel
        $json = Join-Path $TestDrive 'dark-ring.json'
        $null = New-UsaBannerArt -Path $png -OutFile $json
        $art = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable
        $art['palette']['a']['rgb'] | Should -BeExactly '#505050'
        $art['palette']['a']['basic'] | Should -BeExactly 'bright-black'
        $art['palette']['a']['label'] | Should -BeExactly '64% of the picture; #000000 in the image, lightened so a dark terminal shows it'
    }

    It 'draws a photo in ramp style, the brightest densest' {
        $json = Join-Path $TestDrive 'gradient.json'
        $rows = @(New-UsaBannerArt -Path $gradientPng -ColorMode none -OutFile $json)
        $ramp = '.:-=+*#%@'
        $rows.Count | Should -Be 5
        foreach ($row in $rows) {
            $row.Length | Should -Be 40
            $row[0] | Should -BeExactly '.'
            $row[-1] | Should -BeExactly '@'
            $levels = @($row.ToCharArray() | ForEach-Object { $ramp.IndexOf($_) })
            $levels | Should -Not -Contain -1
            for ($c = 1; $c -lt $levels.Count; $c++) { $levels[$c] | Should -BeGreaterOrEqual $levels[$c - 1] }
        }
        (Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable)['source'] | Should -BeLike '*: ramp style, *background none'
    }

    It 'takes -Style shape for a picture auto would draw as a photo' {
        $rows = @(New-UsaBannerArt -Path $gradientPng -ColorMode none -Style shape)
        ($rows -join '') | Should -Match '^[8]+$'
    }

    It 'keeps to -Colors' {
        $png = New-TestImage -Name 'stripes.png' -Width 84 -Height 24 -Pixel {
            param($x, $y)
            if ($x -lt 2 -or $x -ge 82 -or $y -lt 2 -or $y -ge 22) { return 0, 0, 0, 0 }
            $hues = @(@(230, 25, 75), @(60, 180, 75), @(255, 225, 25), @(0, 130, 200), @(245, 130, 48), @(145, 30, 180), @(70, 240, 240), @(240, 50, 230))
            $hue = $hues[[int][Math]::Floor(($x - 2) / 10)]
            $hue[0], $hue[1], $hue[2], 255
        }
        foreach ($most in 8, 3, 1) {
            $json = Join-Path $TestDrive "stripes-$most.json"
            $null = New-UsaBannerArt -Path $png -Colors $most -OutFile $json -Force
            @((Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable)['palette'].Keys).Count | Should -Be $most
        }
    }

    It 'makes colours closer than the eye tells apart one class' {
        $png = New-TestImage -Name 'two-blues.png' -Width 44 -Height 24 -Pixel {
            param($x, $y)
            if ($x -lt 2 -or $x -ge 42 -or $y -lt 2 -or $y -ge 22) { return 0, 0, 0, 0 }
            if ($x -lt 22) { return 30, 111, 217, 255 }
            40, 120, 222, 255
        }
        $json = Join-Path $TestDrive 'two-blues.json'
        $null = New-UsaBannerArt -Path $png -OutFile $json
        @((Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable)['palette'].Keys).Count | Should -Be 1
    }

    It 'folds the thin blend anti-aliasing leaves between two colours into one of them' {
        $png = New-TestImage -Name 'blend.png' -Width 104 -Height 44 -Pixel {
            param($x, $y)
            if ($x -lt 2 -or $x -ge 102 -or $y -lt 2 -or $y -ge 42) { return 0, 0, 0, 0 }
            if ($x -lt 52) { return 30, 111, 217, 255 }
            if ($x -eq 52) { return 142, 183, 236, 255 }
            255, 255, 255, 255
        }
        $json = Join-Path $TestDrive 'blend.json'
        $null = New-UsaBannerArt -Path $png -OutFile $json
        $palette = (Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable)['palette']
        @($palette.Keys | ForEach-Object { $palette[$_]['rgb'] }) | Should -Be @('#1E6FD9', '#FFFFFF')
    }

    It 'folds the halo a JPEG leaves around a part on a background colour into the part, so the part is not drawn as fill' {
        # A blue square, ringed 2 pixels deep by an off blue: lighter, and off the line to white,
        # as JPEG's colour blur leaves it. On white, the halo is noise, and the square is solid.
        $square = {
            param($x, $y)
            if ($x -lt 4 -or $x -ge 88 -or $y -lt 4 -or $y -ge 88) { return $margin }
            if ($x -lt 6 -or $x -ge 86 -or $y -lt 6 -or $y -ge 86) { return 120, 175, 250, 255 }
            30, 111, 217, 255
        }
        $margin = @(255, 255, 255, 255)
        $png = New-TestImage -Name 'jpeg-halo.png' -Width 92 -Height 92 -Pixel $square
        $json = Join-Path $TestDrive 'jpeg-halo.json'
        $rows = @(New-UsaBannerArt -Path $png -ColorMode none -OutFile $json)
        "$($rows[0].Length) x $($rows.Count)" | Should -Be '40 x 20'
        ($rows -join '') | Should -Match '^8+$'
        $art = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable
        @($art['palette'].Keys | ForEach-Object { $art['palette'][$_]['rgb'] }) | Should -Be @('#1E6FD9')
        $art.Contains('fill') | Should -BeFalse
    }

    It 'keeps a thin ring on a transparent background as a colour of its own: an outline, not a halo' {
        $square = {
            param($x, $y)
            if ($x -lt 4 -or $x -ge 88 -or $y -lt 4 -or $y -ge 88) { return 0, 0, 0, 0 }
            if ($x -lt 6 -or $x -ge 86 -or $y -lt 6 -or $y -ge 86) { return 120, 175, 250, 255 }
            30, 111, 217, 255
        }
        $png = New-TestImage -Name 'outline.png' -Width 92 -Height 92 -Pixel $square
        $json = Join-Path $TestDrive 'outline.json'
        $null = New-UsaBannerArt -Path $png -OutFile $json
        $art = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable
        @($art['palette'].Keys | ForEach-Object { $art['palette'][$_]['rgb'] }) | Should -Be @('#1E6FD9', '#78AFFA')
        $art['fill']['class'] | Should -BeExactly 'a'
    }

    It 'draws no part as fill with -Fill none, and the part nearest a colour with -Fill #RRGGBB' {
        $json = Join-Path $TestDrive 'ring-none.json'
        $rows = @(New-UsaBannerArt -Path $ringPng -ColorMode none -Fill none -OutFile $json)
        $rows[2] | Should -BeExactly ('8' * 20)
        (Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable).Contains('fill') | Should -BeFalse
        $json = Join-Path $TestDrive 'ring-blue.json'
        $rows = @(New-UsaBannerArt -Path $ringPng -ColorMode none -Fill '#2060E0' -OutFile $json)
        $rows[0] | Should -BeExactly (' ' * 20)
        $rows[2] | Should -BeExactly ('    ' + '8' * 12 + '    ')
        (Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable)['fill']['class'] | Should -BeExactly 'a'
    }

    It 'draws a <BoxWidth> x <BoxHeight> picture <Expected>: 40 columns, or one to two pixels of a smaller one, rows keeping its shape' -ForEach @(
        @{ BoxWidth = 200; BoxHeight = 100; Expected = '40 x 10' }
        @{ BoxWidth = 30; BoxHeight = 30; Expected = '15 x 8' }
    ) {
        $png = New-TestImage -Name "box-$BoxWidth.png" -Width ($BoxWidth + 4) -Height ($BoxHeight + 4) -Pixel {
            param($x, $y)
            if ($x -lt 2 -or $x -ge $BoxWidth + 2 -or $y -lt 2 -or $y -ge $BoxHeight + 2) { return 0, 0, 0, 0 }
            200, 40, 40, 255
        }
        $rows = @(New-UsaBannerArt -Path $png -ColorMode none)
        "$($rows[0].Length) x $($rows.Count)" | Should -Be $Expected
        ($rows -join '') | Should -Match '^8+$'
    }

    It 'draws a 200 x 100 picture <Expected> for <Asked>: one keeps its shape, both stretch it' -ForEach @(
        @{ Asked = '-Width 20'; Columns = 20; Rows = 0; Expected = '20 x 5' }
        @{ Asked = '-Height 4'; Columns = 0; Rows = 4; Expected = '16 x 4' }
        @{ Asked = '-Width 10 -Height 10'; Columns = 10; Rows = 10; Expected = '10 x 10' }
    ) {
        $png = Join-Path $TestDrive 'box-wide.png'
        if (-not (Test-Path -LiteralPath $png)) {
            $null = New-TestImage -Name 'box-wide.png' -Width 204 -Height 104 -Pixel {
                param($x, $y)
                if ($x -lt 2 -or $x -ge 202 -or $y -lt 2 -or $y -ge 102) { return 0, 0, 0, 0 }
                200, 40, 40, 255
            }
        }
        $size = @{}
        if ($Columns) { $size['Width'] = $Columns }
        if ($Rows) { $size['Height'] = $Rows }
        $drawn = @(New-UsaBannerArt -Path $png -ColorMode none @size)
        "$($drawn[0].Length) x $($drawn.Count)" | Should -Be $Expected
    }

    It 'makes a picture too tall for 30 rows narrower, warning when -Width asked for more' {
        $png = New-TestImage -Name 'tall.png' -Width 24 -Height 404 -Pixel {
            param($x, $y)
            if ($x -lt 2 -or $x -ge 22 -or $y -lt 2 -or $y -ge 402) { return 0, 0, 0, 0 }
            90, 160, 90, 255
        }
        $rows = @(New-UsaBannerArt -Path $png -ColorMode none -Width 20 -WarningVariable warned -WarningAction SilentlyContinue)
        "$($rows[0].Length) x $($rows.Count)" | Should -Be '3 x 30'
        @($warned | ForEach-Object { "$_" }) | Should -Be @('UsaBanner: at 20 columns the picture takes 200 rows, and art may take 30, so it is 3 columns wide.')
        $rows = @(New-UsaBannerArt -Path $png -ColorMode none -WarningVariable warned -WarningAction SilentlyContinue)
        "$($rows[0].Length) x $($rows.Count)" | Should -Be '3 x 30'
        @($warned) | Should -BeNullOrEmpty
    }

    It 'refuses a picture that is all background, saying how to keep a colour' {
        $clear = New-TestImage -Name 'clear.png' -Width 8 -Height 8 -Pixel { param($x, $y) 0, 0, 0, 0 }
        { New-UsaBannerArt -Path $clear } | Should -Throw '*clear.png cannot be made into art: all of it is background (transparent), so there is nothing to draw.'
        $red = New-TestImage -Name 'red.png' -Width 8 -Height 8 -Pixel { param($x, $y) 255, 0, 0, 255 }
        { New-UsaBannerArt -Path $red } | Should -Throw '*red.png cannot be made into art: all of it is background (#FF0000), so there is nothing to draw; -Background none keeps it.'
        @(New-UsaBannerArt -Path $red -Background none -ColorMode none) | Should -Be @('----', '----')
    }

    It 'makes the same art from the same image every time' {
        # The same file name in two folders: the art's name comes from the file's.
        $first = Join-Path (New-Item -ItemType Directory -Path (Join-Path $TestDrive 'first') -Force).FullName 'same.json'
        $second = Join-Path (New-Item -ItemType Directory -Path (Join-Path $TestDrive 'second') -Force).FullName 'same.json'
        $null = New-UsaBannerArt -Path $gradientPng -OutFile $first
        $null = New-UsaBannerArt -Path $gradientPng -OutFile $second
        [System.IO.File]::ReadAllText($second) | Should -BeExactly ([System.IO.File]::ReadAllText($first))
    }
}

Describe 'New-UsaBannerArt' {
    It 'saves art in -OutFile that Show-UsaBannerArt -Path draws as New-UsaBannerArt did, in <Mode>' -ForEach @(@{ Mode = 'none' }, @{ Mode = 'truecolor' }, @{ Mode = '16' }) {
        $json = Join-Path $TestDrive "round-$Mode.json"
        $made = @(New-UsaBannerArt -Path $ringPng -ColorMode $Mode -OutFile $json)
        (@(Show-UsaBannerArt -Path $json -ColorMode $Mode) -join "`n") | Should -BeExactly ($made -join "`n")
    }

    It 'writes the file as UTF-8 with no byte-order mark, LF line ends, and its metadata' {
        $json = Join-Path $TestDrive 'Contoso Logo.json'
        $null = New-UsaBannerArt -Path $ringPng -OutFile $json -Title 'Contoso' -Artist 'Contoso design' -Licence 'all rights reserved'
        $bytes = [System.IO.File]::ReadAllBytes($json)
        $bytes[0] | Should -Be ([byte][char]'{')
        $bytes | Should -Not -Contain 13
        $bytes[-1] | Should -Be 10
        $art = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable
        @($art.Keys)[0..4] | Should -Be @('name', 'title', 'artist', 'licence', 'source')
        $art['name'] | Should -BeExactly 'contoso-logo'
        $art['title'] | Should -BeExactly 'Contoso'
        $art['artist'] | Should -BeExactly 'Contoso design'
        $art['licence'] | Should -BeExactly 'all rights reserved'
    }

    It 'names the art after the image, by unknown, when nothing says otherwise' {
        $json = Join-Path $TestDrive 'defaults.json'
        $null = New-UsaBannerArt -Path $ringPng -OutFile $json
        $art = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable
        "$($art['title']) | $($art['artist']) | $($art['licence'])" | Should -BeExactly 'ring | unknown | unknown'
    }

    It 'refuses to replace an -OutFile file unless -Force says to' {
        $json = Join-Path $TestDrive 'kept.json'
        Set-Content -LiteralPath $json -Value 'mine'
        { New-UsaBannerArt -Path $ringPng -OutFile $json } | Should -Throw "*kept.json is there already; -Force replaces it."
        Get-Content -LiteralPath $json | Should -Be 'mine'
        $null = New-UsaBannerArt -Path $ringPng -OutFile $json -Force
        (Get-Content -LiteralPath $json -Raw | ConvertFrom-Json -AsHashtable)['name'] | Should -BeExactly 'kept'
    }

    It 'says with -Verbose which style it took, with the colours, the background and the size' {
        $said = @(New-UsaBannerArt -Path $ringPng -ColorMode none -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -like 'UsaBanner:*' })
        @($said | ForEach-Object { $_.Message }) | Should -Be @('UsaBanner: made by New-UsaBannerArt from ring.png: shape style, 2 colours, background transparent; 20 x 10.')
    }

    It 'says when there is no image at the path' {
        { New-UsaBannerArt -Path (Join-Path $TestDrive 'missing.png') } | Should -Throw '*there is no file at *missing.png.'
    }

    It 'takes paths relative to the current location' {
        $folder = Join-Path $TestDrive 'here'
        $null = New-Item -ItemType Directory -Path $folder -Force
        Copy-Item -LiteralPath $ringPng -Destination (Join-Path $folder 'logo.png')
        Push-Location $folder
        try { $rows = @(New-UsaBannerArt -Path 'logo.png' -ColorMode none -OutFile 'logo.json') }
        finally { Pop-Location }
        ($rows -join "`n") | Should -BeExactly ($ringArt -join "`n")
        Test-Path -LiteralPath (Join-Path $folder 'logo.json') | Should -BeTrue
    }

    It 'runs in a real pwsh through the hand-off, from the same location, as a direct run does' {
        $folder = Join-Path $TestDrive 'handed'
        $null = New-Item -ItemType Directory -Path $folder -Force
        Copy-Item -LiteralPath $ringPng -Destination (Join-Path $folder 'logo.png')
        $direct = @(New-UsaBannerArt -Path $ringPng -ColorMode truecolor)
        Push-Location $folder
        try {
            $handed = @(InModuleScope UsaBanner {
                    Invoke-UsaBannerHandoff -Command 'New-UsaBannerArt' -Parameters @{ Path = 'logo.png'; ColorMode = 'truecolor'; OutFile = 'logo.json'; Force = [switch]$true } -Pwsh (Get-Process -Id $PID).Path
                })
        }
        finally { Pop-Location }
        ($handed -join "`n") | Should -BeExactly ($direct -join "`n")
        Test-Path -LiteralPath (Join-Path $folder 'logo.json') | Should -BeTrue
    }

    It 'leaves the C# uncompiled until an image is read: importing the module stays quick' {
        $manifest = Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1'
        $probe = "Import-Module -Name '$($manifest.Replace("'", "''"))'; [bool]('UsaBanner.ArtMaker' -as [type])"
        & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -Command $probe | Should -Be 'False'
    }
}

Describe 'Show-UsaBannerArt -Path' {
    It 'says what is wrong with a file that breaks the art rules' {
        $json = Join-Path $TestDrive 'broken.json'
        Set-Content -LiteralPath $json -Value '{ "title": "x", "licence": "MIT", "source": "here", "art": ["#"], "mask": ["a"], "palette": { "a": { "rgb": "#FFFFFF" } } }'
        { Show-UsaBannerArt -Path $json } | Should -Throw '*broken.json breaks the art rules:*artist: missing*'
    }

    It 'says when there is no such file' {
        { Show-UsaBannerArt -Path (Join-Path $TestDrive 'nothing.json') } | Should -Throw '*there is no file at *nothing.json.'
    }

    It 'says when the file is not JSON' {
        $json = Join-Path $TestDrive 'text.json'
        Set-Content -LiteralPath $json -Value 'not json'
        { Show-UsaBannerArt -Path $json } | Should -Throw '*text.json is not JSON*'
    }
}
