# What every banner is built from (UsaBanner/Private/Frame.ps1): styles,
# spans and blocks, the border sets of docs/DECISIONS.md D6 and the boxes
# they draw, and wrapped text. Whole frames are checked against tests/frames
# (Golden.ps1).

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $schema = Get-Content -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'config' 'usabanner.schema.json') -Raw | ConvertFrom-Json -AsHashtable
    $setCases = @(foreach ($set in $schema['properties']['border']['properties']['set']['enum']) { @{ Set = $set } })
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'Golden.ps1')
    $esc = [string][char]27
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'a style''s escape' {
    It 'in <Mode> is <Codes>: bold, reverse, the text colour, then the background' -ForEach @(
        @{ Mode = 'truecolor'; Codes = '1;7;38;2;255;153;0;48;2;0;0;128' }
        @{ Mode = '256'; Codes = '1;7;38;5;208;48;5;18' }
        @{ Mode = '16'; Codes = '1;7;33;44' }
        @{ Mode = 'mono'; Codes = '1;7' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Mode = $Mode } {
            param($Mode)
            ConvertTo-UsaBannerStyleSgr -Style (New-UsaBannerStyle -Fg '#FF9900' -FgBasic yellow -Bg '#000080' -BgBasic blue -Bold -Reverse) -Mode $Mode
        } | Should -BeExactly "$esc[$Codes`m"
    }

    It 'is empty in none, where text shows before login, and for no style' {
        InModuleScope UsaBanner {
            ConvertTo-UsaBannerStyleSgr -Style (New-UsaBannerStyle -Fg '#FF9900' -FgBasic yellow -Bold) -Mode none
            ConvertTo-UsaBannerStyleSgr -Style $null -Mode truecolor
            ConvertTo-UsaBannerStyleSgr -Style (New-UsaBannerStyle -Fg '#FF9900') -Mode 16
        } | Should -BeExactly @('', '', '')
    }
}

Describe 'spans and blocks' {
    It 'a stack centres each block as a whole, so art keeps its shape, and adds no spaces on the right' {
        $lines = InModuleScope UsaBanner {
            $art = New-UsaBannerTextBlock -Lines @(' /\', '/__\')
            $wide = New-UsaBannerTextBlock -Lines @('0123456789')
            ConvertTo-UsaBannerFrameText -Block (Join-UsaBannerStack -Blocks @($art, $null, $wide) -Align center) -Mode none
        }
        $lines | Should -BeExactly @('    /\', '   /__\', '0123456789')
    }

    It 'side by side pads each block but the last, sits the shorter one in the middle, and leaves no line ending in spaces' {
        $lines = InModuleScope UsaBanner {
            $tall = New-UsaBannerTextBlock -Lines @('a', 'bbb', 'c')
            $short = New-UsaBannerTextBlock -Lines @('x')
            ConvertTo-UsaBannerFrameText -Block (Join-UsaBannerBeside -Blocks @($tall, $short) -Gap 2) -Mode none
        }
        $lines | Should -BeExactly @('a', 'bbb  x', 'c')
    }

    It 'side by side keeps a styled span of spaces at the end of a line: a bar shows' {
        $lines = InModuleScope UsaBanner {
            $bar = New-UsaBannerBlock
            Add-UsaBannerLine -Block $bar -Spans @(New-UsaBannerSpan -Text '   ' -Style (New-UsaBannerStyle -Reverse))
            ConvertTo-UsaBannerFrameText -Block (Join-UsaBannerBeside -Blocks @((New-UsaBannerTextBlock -Lines @('a')), $bar) -Gap 1) -Mode mono
        }
        $lines | Should -BeExactly @("a $esc[7m   $esc[0m")
    }

    It 'draws an escape only where the style changes, resets before art already drawn, and at the end of a styled line' {
        $lines = InModuleScope UsaBanner {
            $bold = New-UsaBannerStyle -Bold
            $block = New-UsaBannerBlock
            Add-UsaBannerLine -Block $block -Spans @((New-UsaBannerSpan -Text 'a' -Style $bold), (New-UsaBannerSpan -Text 'b' -Style $bold), (New-UsaBannerSpan -Text 'c'))
            Add-UsaBannerLine -Block $block -Spans @((New-UsaBannerSpan -Text 'd' -Style $bold), @{ Text = "$([char]27)[31mart$([char]27)[0m"; Style = $null; Drawn = $true; Width = 3 })
            Add-UsaBannerLine -Block $block -Spans @(New-UsaBannerSpan -Text 'e' -Style $bold)
            ConvertTo-UsaBannerFrameText -Block $block -Mode 16
        }
        $lines | Should -BeExactly @("$esc[1mab$esc[0mc", "$esc[1md$esc[0m$esc[31mart$esc[0m", "$esc[1me$esc[0m")
    }
}

Describe 'the border sets' {
    It 'are the configuration''s border.set names, in its order' {
        $schema = Get-Content -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'config' 'usabanner.schema.json') -Raw | ConvertFrom-Json -AsHashtable
        InModuleScope UsaBanner { @($script:UsaBorderSets.Keys) } | Should -BeExactly @($schema['properties']['border']['properties']['set']['enum'])
    }

    It '<Set> draws the L3 box exactly 64 columns wide, as its golden frame shows' -ForEach $setCases {
        $result = InModuleScope UsaBanner -Parameters @{ Set = $Set } {
            param($Set)
            $border = Get-UsaBannerBorderSet -Name $Set
            $box = New-UsaBannerLegalBox -Legal (Get-UsaBannerLegal -Template L3) -Set $border
            @{ Ascii = $border.Ascii; Lines = @(ConvertTo-UsaBannerFrameText -Block $box -Mode none) }
        }
        foreach ($line in $result.Lines) {
            $line.Length | Should -Be 64 -Because $line
            if ($result.Ascii) { $line | Should -MatchExactly '^[ -~]*$' }
        }
        Assert-UsaBannerGoldenFrame -Name "box-$Set" -Lines $result.Lines
    }

    It 'give Classic for a Unicode set when the text shows before login, and keep an ASCII set' {
        InModuleScope UsaBanner {
            (Get-UsaBannerBorderSet -Name Rounded -AsciiOnly).Name
            (Get-UsaBannerBorderSet -Name Block -AsciiOnly).Name
            (Get-UsaBannerBorderSet -Name Wavy -AsciiOnly).Name
            (Get-UsaBannerBorderSet -Name Rounded).Name
        } | Should -BeExactly @('Classic', 'Classic', 'Wavy', 'Rounded')
    }

    It 'draw OneChar in the character given, and refuse one that is not a single printable character' {
        InModuleScope UsaBanner {
            $set = Get-UsaBannerBorderSet -Name OneChar -Char 'x'
            "$($set.TL)$($set.T)$($set.R)$($set.BR)"
            (Get-UsaBannerBorderSet -Name OneChar).T
        } | Should -BeExactly @('xxxx', 'o')
        { InModuleScope UsaBanner { Get-UsaBannerBorderSet -Name OneChar -Char ' ' } } | Should -Throw '*one printable character*'
        { InModuleScope UsaBanner { Get-UsaBannerBorderSet -Name OneChar -Char 'xy' } } | Should -Throw '*one printable character*'
    }

    It 'refuse a set they do not know, naming the ones there are' {
        { InModuleScope UsaBanner { Get-UsaBannerBorderSet -Name Fancy } } | Should -Throw "*no border set called 'Fancy'*Classic, Hash*Block*"
    }
}

Describe 'a box' {
    It 'centres the cap between the title and the hint, as in its golden frame' {
        $lines = InModuleScope UsaBanner {
            $box = New-UsaBannerLegalBox -Legal (Get-UsaBannerLegal -Template L3) -Set (Get-UsaBannerBorderSet -Name Rounded) -Cap '(>_>)'
            @(ConvertTo-UsaBannerFrameText -Block $box -Mode none)
        }
        $top = $lines[0]
        $title = $top.IndexOf(' WARNING ') + ' WARNING '.Length
        $hint = $top.IndexOf(' Log in for more information ')
        $cap = $top.IndexOf(' (>_>) ')
        ($cap - $title) - ($hint - ($cap + ' (>_>) '.Length)) | Should -BeIn @(-1, 0, 1)
        Assert-UsaBannerGoldenFrame -Name 'box-cap' -Lines $lines
    }

    It 'draws a divider between sections, in the set''s divider characters' {
        $lines = InModuleScope UsaBanner {
            $box = New-UsaBannerBox -Sections @((New-UsaBannerTextBlock -Lines @('one')), (New-UsaBannerTextBlock -Lines @('two'))) -Set (Get-UsaBannerBorderSet -Name Classic) -Width 12 -PadY 0
            @(ConvertTo-UsaBannerFrameText -Block $box -Mode none)
        }
        $lines | Should -BeExactly @('+----------+', '|  one     |', '+----------+', '|  two     |', '+----------+')
    }

    It 'refuses labels wider than its top line' {
        {
            InModuleScope UsaBanner {
                New-UsaBannerBox -Set (Get-UsaBannerBorderSet -Name Classic) -Width 20 -LeftLabel @(New-UsaBannerLabel -Text 'TITLE') -RightLabel @(New-UsaBannerLabel -Text 'a hint too long')
            }
        } | Should -Throw '*needs 29 columns*the box is 20*'
    }

    It 'refuses a section wider than the room inside' {
        { InModuleScope UsaBanner { New-UsaBannerBox -Sections @(New-UsaBannerTextBlock -Lines @('x' * 61)) -Set (Get-UsaBannerBorderSet -Name Classic) } } | Should -Throw '*61 columns*58 columns inside*'
    }
}

Describe 'a golden frame' {
    It 'passes on the same lines, fails on others naming its file, and says how to write a missing one' {
        # Checked, never written: a run with USABANNER_GOLDEN=write must not write here.
        $saved = $env:USABANNER_GOLDEN
        $env:USABANNER_GOLDEN = $null
        try {
            $root = Join-Path $TestDrive 'frames'
            $null = New-Item -ItemType Directory -Path $root
            [System.IO.File]::WriteAllText((Join-Path $root 'kept.txt'), "a$([char]0x238B)[1m`nb`n")
            Assert-UsaBannerGoldenFrame -Name 'kept' -Lines @("a$esc[1m", 'b') -Root $root
            { Assert-UsaBannerGoldenFrame -Name 'kept' -Lines @("a$esc[1m", 'c') -Root $root } | Should -Throw '*kept.txt*'
            { Assert-UsaBannerGoldenFrame -Name 'missing' -Lines @('a') -Root $root } | Should -Throw '*USABANNER_GOLDEN=write*'
            Test-Path -LiteralPath (Join-Path $root 'missing.txt') | Should -BeFalse
        }
        finally { $env:USABANNER_GOLDEN = $saved }
    }
}

Describe 'wrapped text' {
    It 'breaks between words, no line wider than the width, words in order' {
        $text = 'Unauthorized access or use is prohibited and may result in disconnection.'
        $lines = @(InModuleScope UsaBanner -Parameters @{ Text = $text } { param($Text) ConvertTo-UsaBannerWrapped -Text $Text -Width 20 })
        $lines | Should -BeExactly @('Unauthorized access', 'or use is prohibited', 'and may result in', 'disconnection.')
        ($lines -join ' ') | Should -BeExactly $text
    }

    It 'cuts a word wider than the width, and counts a run of spaces as one' {
        InModuleScope UsaBanner { ConvertTo-UsaBannerWrapped -Text 'a   abcdefghij  b' -Width 4 } | Should -BeExactly @('a', 'abcd', 'efgh', 'ij b')
    }

    It 'gives nothing for text with no words' {
        @(InModuleScope UsaBanner { ConvertTo-UsaBannerWrapped -Text '   ' -Width 10 }).Count | Should -Be 0
    }
}
