# The block-letter fonts: the rules a font keeps, the fonts the module ships,
# and a name set in one as art, in the welcome line's colours from left to
# right (docs/DECISIONS.md, D3).

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $fontFiles = @(foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'fonts') -Filter '*.json' -File) { @{ Name = $f.BaseName; Path = $f.FullName } })
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'Golden.ps1')
    $esc = [char]27
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'every font the module ships' {
    It '<Name> keeps every font rule' -ForEach $fontFiles {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        InModuleScope UsaBanner -Parameters @{ Data = $data } { param($Data) Test-UsaBannerFontData -Font $Data } | Should -BeNullOrEmpty
    }

    It '<Name> survives a trip through JSON byte for byte' -ForEach $fontFiles {
        $data = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        $back = ConvertTo-Json -InputObject $data -Depth 10 | ConvertFrom-Json -AsHashtable
        @($back['glyphs'].Keys).Count | Should -Be @($data['glyphs'].Keys).Count
        foreach ($key in $data['glyphs'].Keys) {
            (@($back['glyphs'][$key]) -join "`n") | Should -BeExactly (@($data['glyphs'][$key]) -join "`n") -Because "glyph '$key'"
        }
    }
}

Describe 'the font rules' {
    It 'catch <Case>' -ForEach @(
        @{ Case = 'a font with no artist'; Change = { param($f) $f.Remove('artist') }; Expected = 'artist: missing' }
        @{ Case = 'a height of nought'; Change = { param($f) $f['height'] = 0 }; Expected = 'height: a whole number from 1 to 30' }
        @{ Case = 'a gap of four'; Change = { param($f) $f['gap'] = 4 }; Expected = 'gap: a whole number from 0 to 3' }
        @{ Case = 'a capital with no glyph'; Change = { param($f) $f['glyphs'].Remove('Q') }; Expected = "glyphs: none for 'Q'" }
        @{ Case = 'a glyph a row short'; Change = { param($f) $f['glyphs']['A'] = @(' ### ', '#   #', '#####', '#   #') }; Expected = "glyph 'A': 4 rows for 5" }
        @{ Case = 'a glyph with rows of two widths'; Change = { param($f) $f['glyphs']['B'] = @('#### ', '#   #', '####', '#   #', '#### ') }; Expected = "glyph 'B': rows of 4, 5 columns; all of one width" }
        @{ Case = 'a glyph outside printable ASCII'; Change = { param($f) $f['glyphs']['C'] = @(' ####', "#$([char]0x00B7)   ", '#    ', '#    ', ' ####') }; Expected = "glyph 'C': printable ASCII only" }
        @{ Case = 'a glyph for two characters'; Change = { param($f) $f['glyphs']['AB'] = @('#', '#', '#', '#', '#') }; Expected = "glyph 'AB': a glyph is for one character" }
    ) {
        $problems = @(InModuleScope UsaBanner -Parameters @{ Change = $Change } {
                param($Change)
                $data = Get-UsaBannerFontData -Name 'pixel'
                & $Change $data
                Test-UsaBannerFontData -Font $data
            })
        $problems | Should -Contain $Expected
    }
}

Describe 'a name in block letters' {
    It 'sets the glyphs side by side, one column apart' {
        $expected = @(
            '#   # #####'
            '#   #   #  '
            '#####   #  '
            '#   #   #  '
            '#   # #####'
        )
        (@(Show-UsaBannerArt -Text 'HI' -ColorMode none) -join "`n") | Should -BeExactly ($expected -join "`n")
    }

    It 'draws lower case as capitals' {
        (@(Show-UsaBannerArt -Text 'hi there' -ColorMode none) -join "`n") | Should -BeExactly (@(Show-UsaBannerArt -Text 'HI THERE' -ColorMode none) -join "`n")
    }

    It 'fits Contoso LLC into 63 columns, and in one font named, refuses a name wider than 64' {
        @(Show-UsaBannerArt -Text 'Contoso LLC' -ColorMode none)[0].Length | Should -Be 63
        { Show-UsaBannerArt -Text 'Contoso Holdings' -Font pixel -ColorMode none } | Should -Throw "*'Contoso Holdings' comes out 93 columns wide in the pixel font; art may be at most 64.*"
    }

    It 'in one font named, names each character it has no glyph for' {
        { Show-UsaBannerArt -Text 'Cafe ~ #1' -Font pixel -ColorMode none } | Should -Throw "*the pixel font has no glyph for '~', '#'. It has A-Z, 0-9, a space and: *"
    }

    It 'colours the letters left to right, from the welcome line''s blue to its gold' {
        $row = @(Show-UsaBannerArt -Text 'HI' -ColorMode truecolor)[0]
        $colours = @([regex]::Matches($row, "$esc\[38;2;(\d+;\d+;\d+)m") | ForEach-Object { $_.Groups[1].Value })
        $colours[0] | Should -BeExactly '120;200;255'    # column 0: #78C8FF
        $colours[-1] | Should -BeExactly '255;200;80'    # column 10, the last: #FFC850
    }

    It 'gives a 16-colour terminal bright blue' {
        (@(Show-UsaBannerArt -Text 'HI' -ColorMode 16) -join '') | Should -Match ([regex]::Escape("$esc[94m"))
    }

    It 'makes art that keeps every art rule' {
        InModuleScope UsaBanner {
            $art = ConvertTo-UsaBannerWordArt -Text 'Contoso LLC' -Font (Get-UsaBannerFontData -Name 'pixel')
            Test-UsaBannerArtData -Art $art | Should -BeNullOrEmpty
        }
    }

    It 'names the fonts there are when asked for one that is not' {
        { Show-UsaBannerArt -Text 'HI' -Font 'gothic' } | Should -Throw "*there is no font called 'gothic'. There is: pixel, small.*"
    }
}

Describe 'a long company name' {
    # The order picked in the M2 gallery (D3): Pixel, the Small font, the
    # Small font on two lines, spaced capitals, the name as written.
    It '<Name> comes out <Form>, as its golden frame shows' -ForEach @(
        @{ Name = 'Contoso'; Form = 'pixel' }
        @{ Name = 'Contoso LLC'; Form = 'pixel' }
        @{ Name = 'Contoso Systems'; Form = 'small' }
        @{ Name = 'Contoso Pharmaceuticals'; Form = 'small2' }
        @{ Name = 'Contoso Regional Medical Center'; Form = 'small2' }
        @{ Name = 'Contoso Wholesale Electrical Distributors'; Form = 'plain' }
    ) {
        (InModuleScope UsaBanner -Parameters @{ Name = $Name } { param($Name) Get-UsaBannerNameForm -Name $Name }).Form | Should -BeExactly $Form
        $lines = @(Show-UsaBannerArt -Text $Name -ColorMode none)
        foreach ($line in $lines) { $line.Length | Should -BeLessOrEqual 64 -Because $line }
        Assert-UsaBannerGoldenFrame -Name ('name-' + ($Name.ToLowerInvariant() -replace '[^a-z0-9]+', '-')) -Lines $lines
    }

    It 'breaks two lines at the space that leaves the wider line narrowest, and centres them' {
        $form = InModuleScope UsaBanner { Get-UsaBannerNameForm -Name 'Contoso Regional Medical Center' }
        $small = InModuleScope UsaBanner { Get-UsaBannerFontData -Name small }
        $top = @(InModuleScope UsaBanner -Parameters @{ Font = $small } { param($Font) Get-UsaBannerFontRows -Text 'CONTOSO REGIONAL' -Font $Font })
        $bottom = @(InModuleScope UsaBanner -Parameters @{ Font = $small } { param($Font) Get-UsaBannerFontRows -Text 'MEDICAL CENTER' -Font $Font })
        $left = ' ' * [Math]::Floor(($top[0].Length - $bottom[0].Length) / 2)
        $form.Rows | Should -BeExactly (@($top) + @('') + @($bottom | ForEach-Object { $left + $_ }))
    }

    It 'fits the name to the width it is given: beside the art, 44 columns, Contoso LLC takes the Small font' {
        (InModuleScope UsaBanner { Get-UsaBannerNameForm -Name 'Contoso LLC' -Width 44 }).Form | Should -BeExactly 'small'
    }

    It 'passes over a font with no glyph for a character: Contoso #1 comes out in spaced capitals' {
        $form = InModuleScope UsaBanner { Get-UsaBannerNameForm -Name 'Contoso #1' }
        $form.Form | Should -BeExactly 'spaced'
        $form.Rows | Should -BeExactly @('C O N T O S O   # 1')
    }

    It 'gives the name as written, never cut, when nothing else fits' {
        $name = 'Contoso Wholesale Electrical Distributors of the Great Lakes'
        $form = InModuleScope UsaBanner -Parameters @{ Name = $name } { param($Name) Get-UsaBannerNameForm -Name $Name }
        $form.Form | Should -BeExactly 'plain'
        $form.Rows | Should -BeExactly @($name)
    }

    It 'makes art that keeps every art rule, in every form' {
        foreach ($name in 'Contoso', 'Contoso Systems', 'Contoso Pharmaceuticals', 'Contoso #1', 'Contoso Wholesale Electrical Distributors') {
            InModuleScope UsaBanner -Parameters @{ Name = $name } { param($Name) Test-UsaBannerArtData -Art (ConvertTo-UsaBannerNameArt -Name $Name) } | Should -BeNullOrEmpty -Because $name
        }
    }

    It 'colours two lines as one name, from the welcome line''s blue to its gold, as the golden frame shows' {
        Assert-UsaBannerGoldenFrame -Name 'name-contoso-pharmaceuticals-truecolor' -Lines @(Show-UsaBannerArt -Text 'Contoso Pharmaceuticals' -ColorMode truecolor)
    }
}
