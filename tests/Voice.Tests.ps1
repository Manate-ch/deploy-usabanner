# Meme voices (UsaBanner/Private/Voice.ps1, docs/DECISIONS.md D25): each
# voice's rules, the legal box in each voice, and what a voice never touches.
# Whole frames are checked against tests/frames (Golden.ps1).

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'Golden.ps1')
    $l3 = 'This system is for authorized use only. Activity on this system is monitored and recorded. Unauthorized access or use is prohibited.'
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'a voice''s rules, on prose' {
    It '<Voice>: <Expected>' -ForEach @(
        @{ Voice = 'uwu'; Expected = 'T-This system is fow authowized use onwy uwu. A-Activity on this system is monitowed and wecowded owo. U-Unauthowized access ow use is pwohibited >w<.' }
        @{ Voice = 'random'; Expected = 'This system is 4 authorized use only. XD Activity on this system is monitored and recorded. lolz Unauthorized access or use is prohibited. *holds up spork*' }
        @{ Voice = 'leet'; Expected = '7H15 5Y573M 15 F0R 4U7H0R1Z3D U53 0NLY. 4C71V17Y 0N 7H15 5Y573M 15 M0N170R3D 4ND R3C0RD3D. UN4U7H0R1Z3D 4CC355 0R U53 15 PR0H1B173D. -=[ 0WN3D BY 7H3 5Y50P ]=-' }
        @{ Voice = 'plain'; Expected = 'This system is for authorized use only. Activity on this system is monitored and recorded. Unauthorized access or use is prohibited.' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Text = $l3; Voice = $Voice } { param($Text, $Voice) ConvertTo-UsaBannerVoiced -Text $Text -Voice $Voice -Prose } | Should -BeExactly $Expected
    }

    It 'uwu turns n before a vowel at a word''s start into ny, in either case' {
        InModuleScope UsaBanner { ConvertTo-UsaBannerVoiced -Text 'not now, NOTICE: a banana' -Voice uwu } | Should -BeExactly 'nyot nyow, NYOTICE: a banana'
    }

    It 'random swaps whole words only: <Text>' -ForEach @(
        @{ Text = 'the theme for you, to your toes'; Expected = 'teh theme 4 u, 2 ur toes' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Text = $Text } { param($Text) ConvertTo-UsaBannerVoiced -Text $Text -Voice random } | Should -BeExactly $Expected
    }

    It 'keeps 18 U.S.C. 1030 in one sentence: no face falls inside it' {
        $l4 = InModuleScope UsaBanner { (Get-UsaBannerLegal -Template L4).Paragraphs[0] }
        $voiced = InModuleScope UsaBanner -Parameters @{ Text = $l4 } { param($Text) ConvertTo-UsaBannerVoiced -Text $Text -Voice uwu -Prose }
        $voiced | Should -BeLikeExactly '*18 U.S.C. 1030*'
    }

    It 'without -Prose, keeps to the word rules: no stutter, no face, no sign-off' {
        InModuleScope UsaBanner {
            ConvertTo-UsaBannerVoiced -Text 'larger-scale testing' -Voice uwu
            ConvertTo-UsaBannerVoiced -Text 'larger-scale testing' -Voice random
            ConvertTo-UsaBannerVoiced -Text 'larger-scale testing' -Voice leet
        } | Should -BeExactly @('wawgew-scawe testing', 'larger-scale testing', 'L4RG3R-5C4L3 73571NG')
    }

    It 'gives printable ASCII, and the same text the same way every time, for every template in every voice' {
        foreach ($voice in 'uwu', 'random', 'leet') {
            foreach ($template in 'L1', 'L2', 'L3', 'L4', 'L5') {
                $pair = @(InModuleScope UsaBanner -Parameters @{ Voice = $voice; Template = $template } {
                        param($Voice, $Template)
                        $text = (Get-UsaBannerLegal -Template $Template).Paragraphs[0]
                        ConvertTo-UsaBannerVoiced -Text $text -Voice $Voice -Prose
                        ConvertTo-UsaBannerVoiced -Text $text -Voice $Voice -Prose
                    })
                $pair[0] | Should -MatchExactly '^[ -~]+$' -Because "$voice $template"
                $pair[1] | Should -BeExactly $pair[0] -Because "$voice $template"
            }
        }
    }

    It 'refuses a voice it does not know, naming the ones there are' {
        { InModuleScope UsaBanner { ConvertTo-UsaBannerVoiced -Text 'hi' -Voice pirate } } | Should -Throw "*no voice called 'pirate'. There is: plain, uwu, random, leet.*"
    }
}

Describe 'a voice''s words' {
    It 'titles WARNING <Expected> in <Voice>' -ForEach @(
        @{ Voice = 'uwu'; Expected = 'W-WAWNING!! OwO' }
        @{ Voice = 'random'; Expected = 'WARNING!!1!one' }
        @{ Voice = 'leet'; Expected = '\/\/4RN1NG!!' }
        @{ Voice = 'plain'; Expected = 'WARNING' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Voice = $Voice } { param($Voice) Get-UsaBannerVoiceTitle -Title 'WARNING' -Voice $Voice } | Should -BeExactly $Expected
    }

    It 'has a word for every row of the panel, nine columns at most, in every voice' {
        $problems = InModuleScope UsaBanner {
            foreach ($voice in $script:UsaVoices.Keys) {
                foreach ($label in 'schema', 'vlan', 'tier', 'os', 'role', 'uptime', 'cpu', 'memory', 'disk', 'sessions', 'time', 'ipv4', 'updates', 'reboot', 'services') {
                    $word = $script:UsaVoices[$voice].Labels[$label]
                    if (-not $word) { "${voice}: no word for $label" }
                    elseif ($word.Length -gt 9) { "${voice}: '$word' is $($word.Length) columns" }
                    elseif ($word -cnotmatch '^[ -~]+$') { "${voice}: '$word' is not ASCII" }
                }
            }
        }
        @($problems) | Should -BeNullOrEmpty
    }

    It 'keeps a disk''s mount point, a fact, as it is' {
        InModuleScope UsaBanner {
            Get-UsaBannerVoiceLabel -Label 'disk /var' -Voice uwu
            Get-UsaBannerVoiceLabel -Label 'disk C:' -Voice leet
            Get-UsaBannerVoiceLabel -Label 'uptime' -Voice plain
            Get-UsaBannerVoiceLabel -Label '' -Voice uwu
        } | Should -BeExactly @('diwk /var', 'D15K C:', 'uptime', '')
    }
}

Describe 'the legal box in a voice' {
    It 'in <Voice>, rewrites the title, the hint and the text, and brings its cap, as the golden frame shows' -ForEach @(@{ Voice = 'uwu' }, @{ Voice = 'random' }, @{ Voice = 'leet' }) {
        $lines = InModuleScope UsaBanner -Parameters @{ Voice = $Voice } {
            param($Voice)
            @(ConvertTo-UsaBannerFrameText -Block (New-UsaBannerLegalBox -Legal (Get-UsaBannerLegal -Template L3) -Set (Get-UsaBannerBorderSet -Name Classic) -Voice $Voice) -Mode none)
        }
        foreach ($line in $lines) { $line | Should -MatchExactly '^[ -~]{64}$' }
        Assert-UsaBannerGoldenFrame -Name "legal-L3-$Voice" -Lines $lines
    }

    It 'gives way: the uwu title of L5 is too long for the cap too, so the cap goes, as the golden frame shows' {
        $lines = InModuleScope UsaBanner {
            @(ConvertTo-UsaBannerFrameText -Block (New-UsaBannerLegalBox -Legal (Get-UsaBannerLegal -Template L5) -Set (Get-UsaBannerBorderSet -Name Classic) -Voice uwu) -Mode none)
        }
        $lines[0] | Should -Not -BeLike '*(>w<)*'
        $lines[0] | Should -BeLike '*A-ATTENTION!! OwO*pwease wog in fow mowe info uwu~*'
        Assert-UsaBannerGoldenFrame -Name 'legal-L5-uwu' -Lines $lines
    }

    It 'shortens the hint when the title leaves too little room even without the cap' {
        $top = InModuleScope UsaBanner {
            $legal = Get-UsaBannerLegal -Template custom -Text @('PRIVATE PROPERTY: Contoso staff only.')
            @(ConvertTo-UsaBannerFrameText -Block (New-UsaBannerLegalBox -Legal $legal -Set (Get-UsaBannerBorderSet -Name Classic) -Voice uwu) -Mode none)[0]
        }
        $top | Should -BeLike '+- P-PWIVATE PWOPEWTY!! OwO -* wog in uwu~ -+'
        $top.Length | Should -Be 64
    }

    It 'keeps the cap the configuration sets over the voice''s own' {
        $top = InModuleScope UsaBanner {
            @(ConvertTo-UsaBannerFrameText -Block (New-UsaBannerLegalBox -Legal (Get-UsaBannerLegal -Template L3) -Set (Get-UsaBannerBorderSet -Name Classic) -Voice leet -Cap '(o_O)') -Mode none)[0]
        }
        $top | Should -BeLike '*(o_O)*'
        $top | Should -Not -BeLike '*31337*'
    }
}
