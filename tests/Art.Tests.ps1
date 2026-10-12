# The rabbit as data, and the renderer: every colour mode, checked against
# Appendix A of docs/DECISIONS.md and against docs/rabbit.svg.

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $artFiles = @(foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'art') -Recurse -Filter '*.json' -File) { @{ Name = $f.BaseName; Path = $f.FullName } })
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    $doc = Get-Content -LiteralPath (Join-Path $repoRoot 'docs' 'DECISIONS.md') -Raw
    $docArt = [regex]::Match($doc, '(?s)```text\n(   \^\^.*?)\n```').Groups[1].Value -split "`n"
    $docMask = [regex]::Match($doc, '(?s)```text\n(   ff.*?)\n```').Groups[1].Value -split "`n"
    $rabbit = InModuleScope UsaBanner { Get-UsaBannerArtData -Name 'rabbit' }

    function Split-RenderedLine {
        # In:  one rendered line
        # Out: one object per character shown: Char, and Sgr, the body of the escape in force ('' for none)
        # Why: to compare renderings cell by cell, whatever escapes each chose to write
        param([string]$Line)
        $sgr = ''
        $i = 0
        while ($i -lt $Line.Length) {
            if ($Line[$i] -eq [char]27) {
                $end = $Line.IndexOf('m', $i)
                $body = $Line.Substring($i + 2, $end - $i - 2)
                $sgr = if ($body -eq '0') { '' } else { $body }
                $i = $end + 1
                continue
            }
            [pscustomobject]@{ Char = [string]$Line[$i]; Sgr = $sgr }
            $i++
        }
    }

    function Get-RenderedCell {
        # In:  a colour mode
        # Out: one object per cell of the rabbit in that mode: Row, Col, Class (from Appendix A's mask), Char, Sgr
        # Why: a flat list filters easily by row, column or class
        param([string]$Mode)
        $lines = @(Show-UsaBannerArt -Name 'rabbit' -ColorMode $Mode)
        for ($row = 0; $row -lt $lines.Count; $row++) {
            $col = 0
            foreach ($cell in Split-RenderedLine $lines[$row]) {
                [pscustomobject]@{ Row = $row; Col = $col; Class = [string]$docMask[$row][$col]; Char = $cell.Char; Sgr = $cell.Sgr }
                $col++
            }
        }
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the rabbit''s data' {
    It 'is the art of docs/DECISIONS.md, Appendix A, character for character' {
        $docArt.Count | Should -Be 11
        ($rabbit['art'] -join "`n") | Should -BeExactly ($docArt -join "`n")
    }

    It 'has the mask of Appendix A, character for character' {
        $docMask.Count | Should -Be 11
        ($rabbit['mask'] -join "`n") | Should -BeExactly ($docMask -join "`n")
    }

    It 'has the colours of Appendix A''s table' {
        $palette = $rabbit['palette']
        $palette['R']['rgb'] | Should -BeExactly '#FF9900'
        $palette['C']['rgb'] | Should -BeExactly '#99FFFF'
        $palette['L']['rgb'] | Should -BeExactly '#0099FF'
        $palette['n']['rgb'] | Should -BeExactly '#FF99FF'
        $palette['m']['rgb'] | Should -BeExactly '#FFFFFF'
        "$($palette['f']['from']) $($palette['f']['to'])" | Should -BeExactly '#FFF3C4 #E1B95C'
        "$($palette['#']['from']) $($palette['#']['to'])" | Should -BeExactly '#C8A050 #8C6428'
        $rabbit['fill']['char'] | Should -BeExactly ':'
        "$($rabbit['sheen']['peak']) $($rabbit['sheen']['drop'])" | Should -BeExactly '1.15 0.3'
    }

    It 'keeps every art rule' {
        InModuleScope UsaBanner -Parameters @{ Art = $rabbit } { param($Art) Test-UsaBannerArtData -Art $Art } | Should -BeNullOrEmpty
    }
}

Describe 'every piece of built-in art' {
    It '<Name> survives a trip through JSON byte for byte' -ForEach $artFiles {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        $back = ConvertTo-Json -InputObject $data -Depth 10 | ConvertFrom-Json -AsHashtable
        ($back['art'] -join "`n") | Should -BeExactly ($data['art'] -join "`n")
        ($back['mask'] -join "`n") | Should -BeExactly ($data['mask'] -join "`n")
    }
}

Describe 'the art rules' {
    It 'catch <Case>' -ForEach @(
        @{ Case = 'a mask row one character short'; Change = { param($a) $a['mask'][3] = $a['mask'][3].Substring(1) }; Expected = 'mask row 3: 18 characters for 19' }
        @{ Case = 'a visible character with no class'; Change = { param($a) $a['mask'][0] = '   f        ff    t' }; Expected = "row 0, column 4: '^' has no class in the mask" }
        @{ Case = 'a fill cell over a visible character'; Change = { param($a) $a['mask'][6] = 'f###R##CCC#LL###f t' }; Expected = 'row 6, column 5: a fill cell must be a space in the art' }
        @{ Case = 'a class with no palette entry'; Change = { param($a) $a['palette'].Remove('n') }; Expected = "palette: no entry for class 'n'" }
        @{ Case = 'a colour written as a word'; Change = { param($a) $a['palette']['R']['rgb'] = 'orange' }; Expected = "palette 'R'.rgb: write colours as #RRGGBB" }
        @{ Case = 'half a gradient'; Change = { param($a) $a['palette']['f'].Remove('to') }; Expected = "palette 'f': a gradient needs both from and to" }
        @{ Case = 'a character outside printable ASCII'; Change = { param($a) $a['art'][0] = $a['art'][0].Replace('U', [string][char]0x00DC) }; Expected = 'art row 0: printable ASCII only' }
        @{ Case = 'a sheen region with no width'; Change = { param($a) $a['sheen']['regions'][0]['half'] = 0 }; Expected = 'sheen region 0: middle must be a number, half one above 0' }
    ) {
        $problems = @(InModuleScope UsaBanner -Parameters @{ Change = $Change } {
                param($Change)
                $art = Get-UsaBannerArtData -Name 'rabbit'
                & $Change $art
                Test-UsaBannerArtData -Art $art
            })
        $problems | Should -Contain $Expected
    }

    It 'catch a basic colour that is not one of the 16' {
        $problems = @(InModuleScope UsaBanner {
                $art = Get-UsaBannerArtData -Name 'rabbit'
                $art['palette']['m']['basic'] = 'bright-orange'
                Test-UsaBannerArtData -Art $art
            })
        $problems -join "`n" | Should -BeLike "*palette 'm'.basic: one of black, blue, bright-black,*"
    }
}

Describe 'drawing the rabbit' {
    It 'draws the plain art in none: what shows before login' {
        $lines = @(Show-UsaBannerArt -ColorMode none)
        ($lines -join "`n") | Should -BeExactly ($docArt -join "`n")
        ($lines -join '') | Should -Match '^[ -~]*$'
    }

    It 'keeps every line as wide as the art, in <Mode>' -ForEach @(@{ Mode = 'truecolor' }, @{ Mode = '256' }, @{ Mode = '16' }, @{ Mode = 'none' }) {
        $lines = @(Show-UsaBannerArt -ColorMode $Mode)
        $lines.Count | Should -Be 11
        for ($row = 0; $row -lt 11; $row++) {
            ($lines[$row] -replace "$([char]27)\[[0-9;]*m", '').Length | Should -Be $docArt[$row].Length -Because "row $row"
        }
    }

    It 'leaves no colour on at the end of a line, in <Mode>' -ForEach @(@{ Mode = 'truecolor' }, @{ Mode = '256' }, @{ Mode = '16' }) {
        $coloured = 0
        foreach ($line in Show-UsaBannerArt -ColorMode $Mode) {
            $escapes = [regex]::Matches($line, "$([char]27)\[[0-9;]*m")
            if ($escapes.Count -eq 0) { continue }
            $coloured++
            $escapes[$escapes.Count - 1].Value | Should -BeExactly "$([char]27)[0m" -Because $line
        }
        $coloured | Should -Be 11
    }

    It 'draws in truecolor exactly the characters and colours of docs/rabbit.svg' {
        $svg = [xml](Get-Content -LiteralPath (Join-Path $repoRoot 'docs' 'rabbit.svg') -Raw)
        $glyphs = @($svg.SelectNodes("//*[local-name()='g']/*[local-name()='text']"))
        $cells = @(Get-RenderedCell 'truecolor' | Where-Object Char -ne ' ')
        $cells.Count | Should -Be $glyphs.Count
        for ($i = 0; $i -lt $glyphs.Count; $i++) {
            $glyph = $glyphs[$i]
            $col = ([double]$glyph.x - 16 - 6) / 12    # 16 the margin; a cell 12 wide, x at its middle
            $row = ([double]$glyph.y - 16 - 16) / 22   # 16 the margin; a cell 22 high, y at its baseline, 16 down
            $hex = $glyph.fill.Substring(1)
            # The SVG shows the side text in light grey, #CCCCCC; a terminal draws it in its own colour.
            $expected = if ($hex -eq 'CCCCCC') { '' } else { '38;2;{0};{1};{2}' -f [Convert]::ToInt32($hex.Substring(0, 2), 16), [Convert]::ToInt32($hex.Substring(2, 2), 16), [Convert]::ToInt32($hex.Substring(4, 2), 16) }
            "$($cells[$i].Row),$($cells[$i].Col)" | Should -Be "$row,$col" -Because "glyph $i"
            $cells[$i].Char | Should -BeExactly $glyph.'#text' -Because "glyph $i at $row,$col"
            $cells[$i].Sgr | Should -BeExactly $expected -Because "glyph $i ($($glyph.'#text') at $row,$col)"
        }
    }

    It 'gives fill cells the fill character in colour, and a space without' {
        (Get-RenderedCell 'truecolor' | Where-Object { $_.Row -eq 8 -and $_.Col -eq 1 }).Char | Should -BeExactly ':'
        (Get-RenderedCell '16' | Where-Object { $_.Row -eq 8 -and $_.Col -eq 1 }).Char | Should -BeExactly ':'
        [string](Show-UsaBannerArt -ColorMode none)[8][1] | Should -BeExactly ' '
    }

    It 'draws each cell in 256 colours as the nearest entry to its truecolor colour' {
        $full = @(Get-RenderedCell 'truecolor')
        $reduced = @(Get-RenderedCell '256')
        $reduced.Count | Should -Be $full.Count
        $expected = InModuleScope UsaBanner -Parameters @{ Sgrs = @($full.Sgr) } {
            param($Sgrs)
            foreach ($sgr in $Sgrs) {
                if (-not $sgr) { ''; continue }
                $rgb = @($sgr.Split(';') | Select-Object -Skip 2)
                "38;5;$(Find-UsaBanner256 -R $rgb[0] -G $rgb[1] -B $rgb[2])"
            }
        }
        for ($i = 0; $i -lt $full.Count; $i++) {
            $reduced[$i].Sgr | Should -BeExactly $expected[$i] -Because "cell $($full[$i].Row),$($full[$i].Col)"
        }
    }

    It 'gives the eyes, nose and mouth Appendix A''s 256 colours' {
        $cells = @(Get-RenderedCell '256')
        $expected = [ordered]@{ R = '38;5;208'; C = '38;5;123'; L = '38;5;33'; n = '38;5;213'; m = '38;5;231' }
        foreach ($class in $expected.Keys) {
            @($cells | Where-Object { $_.Class -ceq $class -and $_.Char -ne ' ' } | ForEach-Object Sgr | Sort-Object -Unique) | Should -Be @($expected[$class]) -Because "class $class"
        }
    }

    It 'draws 16 colours one per part: no gradient, no sheen' {
        $cells = @(Get-RenderedCell '16')
        # Class -> the SGR code Appendix A gives it; t is the side text, in the terminal's own colour.
        $expected = [ordered]@{ f = '93'; '#' = '90'; R = '33'; C = '96'; L = '94'; n = '95'; m = '97'; t = '' }
        foreach ($class in $expected.Keys) {
            @($cells | Where-Object { $_.Class -ceq $class -and $_.Char -ne ' ' } | ForEach-Object Sgr | Sort-Object -Unique) | Should -Be @($expected[$class]) -Because "class $class"
        }
    }

    It 'shades the fur brighter down the middle than at the edges' {
        $cells = @(Get-RenderedCell 'truecolor')
        $readRed = {
            # In:  a row and a column
            # Out: the red channel of that cell in the truecolor rendering
            # Why: the sheen shows most plainly in the red of the blonde
            param([int]$Row, [int]$Col)
            [int](($cells | Where-Object { $_.Row -eq $Row -and $_.Col -eq $Col }).Sgr.Split(';')[2])
        }
        (& $readRed 8 8) | Should -BeGreaterThan (& $readRed 8 1)   # head fill: middle, edge
        (& $readRed 2 3) | Should -BeGreaterThan (& $readRed 2 2)   # ear fill: middle, edge
    }

    It 'follows USABANNER_COLOR when no mode is given' {
        $saved = $env:USABANNER_COLOR
        try {
            $env:USABANNER_COLOR = '16'
            ((Show-UsaBannerArt) -join "`n") | Should -BeExactly ((Show-UsaBannerArt -ColorMode 16) -join "`n")
        }
        finally { $env:USABANNER_COLOR = $saved }
    }

    It 'names the art there is when asked for art that is not' {
        { Show-UsaBannerArt -Name 'unicorn' } | Should -Throw "*there is no art called 'unicorn'. There is: rabbit.*"
    }
}

Describe 'the nearest of the 256 colours' {
    It 'is <Index> for <Hex>, <Why>' -ForEach @(
        @{ Hex = '#FF9900'; Index = 208; Why = 'the right eye (an even split of 0-255 would give 214)' }
        @{ Hex = '#99FFFF'; Index = 123; Why = 'the centre eye' }
        @{ Hex = '#0099FF'; Index = 33; Why = 'the left eye' }
        @{ Hex = '#FF99FF'; Index = 213; Why = 'the nose' }
        @{ Hex = '#FFFFFF'; Index = 231; Why = 'the mouth' }
        @{ Hex = '#FFF3C4'; Index = 230; Why = 'the fur at the ear tips' }
        @{ Hex = '#E1B95C'; Index = 179; Why = 'the fur at the chin' }
        @{ Hex = '#C8A050'; Index = 179; Why = 'the fill at the top' }
        @{ Hex = '#8C6428'; Index = 94; Why = 'the fill at the chin' }
        @{ Hex = '#000000'; Index = 16; Why = 'black, in the cube' }
        @{ Hex = '#808080'; Index = 244; Why = 'a mid grey, nearer the grey ramp than the cube' }
        @{ Hex = '#121212'; Index = 233; Why = 'a dark grey, on the grey ramp too' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Hex = $Hex } {
            param($Hex)
            $rgb = @(ConvertFrom-UsaBannerHex -Hex $Hex)
            Find-UsaBanner256 -R $rgb[0] -G $rgb[1] -B $rgb[2]
        } | Should -Be $Index
    }
}
