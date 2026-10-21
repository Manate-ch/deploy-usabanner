# The legal text shown before login (UsaBanner/Private/Legal.ps1): D8's five
# templates, the admin's own text, and the box it sits in. Whole frames are
# checked against tests/frames (Golden.ps1).

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'Golden.ps1')

    function Get-D8Template {
        # In:  nothing
        # Out: each template in docs/DECISIONS.md D8, by id, its lines joined by spaces
        # Why: the module's templates must be D8's, word for word
        $text = Get-Content -LiteralPath (Join-Path $repoRoot 'docs' 'DECISIONS.md') -Raw
        $block = [regex]::Match($text, '(?ms)^## D8\..*?^```text\n(.*?)^```').Groups[1].Value
        $found = [ordered]@{}
        $id = $null
        foreach ($line in $block -split "`n") {
            if ($line -match '^(L[1-5])  ') { $id = $Matches[1]; $found[$id] = @(); continue }
            if (-not $line.Trim()) { $id = $null; continue }
            if ($id) { $found[$id] += $line.Trim() }
        }
        foreach ($key in @($found.Keys)) { $found[$key] = $found[$key] -join ' ' }
        $found
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the templates' {
    It 'are D8''s five, word for word' {
        $d8 = Get-D8Template
        @($d8.Keys) | Should -BeExactly @('L1', 'L2', 'L3', 'L4', 'L5')
        $module = InModuleScope UsaBanner { $script:UsaLegalTemplates }
        foreach ($id in $d8.Keys) { $module[$id].Text | Should -BeExactly $d8[$id] -Because $id }
    }

    It 'L3 is the default (D8)' {
        (Get-Content -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'config' 'defaults.json') -Raw | ConvertFrom-Json).legal.template | Should -BeExactly 'L3'
    }

    It '<Id> has the title <Title>, and its text drops the lead the title says' -ForEach @(
        @{ Id = 'L1'; Title = 'HELLO'; Opens = 'Hey there.' }
        @{ Id = 'L2'; Title = 'PRIVATE'; Opens = 'Private system.' }
        @{ Id = 'L3'; Title = 'WARNING'; Opens = 'This system is' }
        @{ Id = 'L4'; Title = 'WARNING'; Opens = 'AUTHORIZED USE ONLY.' }
        @{ Id = 'L5'; Title = 'ATTENTION'; Opens = 'THIS IS A PRIVATE' }
    ) {
        $legal = InModuleScope UsaBanner -Parameters @{ Id = $Id } { param($Id) Get-UsaBannerLegal -Template $Id }
        $legal.Title | Should -BeExactly $Title
        @($legal.Paragraphs).Count | Should -Be 1
        $legal.Paragraphs[0] | Should -BeLikeExactly "$Opens*"
    }

    It '<Id> sits in a Classic box, as its golden frame shows' -ForEach @(@{ Id = 'L1' }, @{ Id = 'L2' }, @{ Id = 'L3' }, @{ Id = 'L4' }, @{ Id = 'L5' }) {
        $lines = InModuleScope UsaBanner -Parameters @{ Id = $Id } {
            param($Id)
            @(ConvertTo-UsaBannerFrameText -Block (New-UsaBannerLegalBox -Legal (Get-UsaBannerLegal -Template $Id) -Set (Get-UsaBannerBorderSet -Name Classic)) -Mode none)
        }
        foreach ($line in $lines) { $line | Should -MatchExactly '^[ -~]{64}$' }
        Assert-UsaBannerGoldenFrame -Name "legal-$Id" -Lines $lines
    }
}

Describe 'the admin''s own text' {
    It 'keeps its lines as paragraphs, a blank one as a blank line, and takes its title from a lead in capitals' {
        $legal = InModuleScope UsaBanner { Get-UsaBannerLegal -Template custom -Text @('PRIVATE PROPERTY: Contoso staff only.', '', 'Questions go to the help desk at example.com.') }
        $legal.Title | Should -BeExactly 'PRIVATE PROPERTY'
        $legal.Paragraphs | Should -BeExactly @('Contoso staff only.', '', 'Questions go to the help desk at example.com.')
        $lines = InModuleScope UsaBanner -Parameters @{ Legal = $legal } {
            param($Legal)
            @(ConvertTo-UsaBannerFrameText -Block (New-UsaBannerLegalBox -Legal $Legal -Set (Get-UsaBannerBorderSet -Name Classic)) -Mode none)
        }
        Assert-UsaBannerGoldenFrame -Name 'legal-custom' -Lines $lines
    }

    It 'is titled NOTICE when it opens with no such lead' {
        (InModuleScope UsaBanner { Get-UsaBannerLegal -Template custom -Text @('', 'Be nice: this box is shared.') }).Title | Should -BeExactly 'NOTICE'
    }

    It 'gives way in a full top line: with a long title, the cap goes rather than the box failing' {
        $top = InModuleScope UsaBanner {
            $legal = Get-UsaBannerLegal -Template custom -Text @('PRIVATE PROPERTY: Contoso staff only.')
            @(ConvertTo-UsaBannerFrameText -Block (New-UsaBannerLegalBox -Legal $legal -Set (Get-UsaBannerBorderSet -Name Classic) -Cap '[ CONTOSO ONLY ]') -Mode none)[0]
        }
        $top | Should -BeExactly ('+- PRIVATE PROPERTY ' + ('-' * 13) + ' Log in for more information -+')
    }

    It 'is refused when it is empty, or not printable ASCII' {
        { InModuleScope UsaBanner { Get-UsaBannerLegal -Template custom -Text @('', '  ') } } | Should -Throw '*legal.text holds no text*'
        { InModuleScope UsaBanner { Get-UsaBannerLegal -Template custom -Text @("Caf$([char]0xE9) only") } } | Should -Throw '*printable ASCII only*'
    }
}

Describe 'the box in colour' {
    It 'in <Mode>: the border, the title, the cap and the hint each in its own style, as the golden frame shows' -ForEach @(@{ Mode = 'truecolor' }, @{ Mode = '256' }, @{ Mode = '16' }, @{ Mode = 'mono' }) {
        $lines = InModuleScope UsaBanner -Parameters @{ Mode = $Mode } {
            param($Mode)
            $edge = New-UsaBannerStyle -Fg '#7CC0FF' -FgBasic bright-blue
            $title = New-UsaBannerStyle -Fg '#FFD75F' -FgBasic bright-yellow -Bold
            $hint = New-UsaBannerStyle -Fg '#8B949E' -FgBasic bright-black
            $box = New-UsaBannerLegalBox -Legal (Get-UsaBannerLegal -Template L3) -Set (Get-UsaBannerBorderSet -Name Rounded) -Cap '(^_^)' -Edge $edge -TitleStyle $title -CapStyle $title -HintStyle $hint
            @(ConvertTo-UsaBannerFrameText -Block $box -Mode $Mode)
        }
        Assert-UsaBannerGoldenFrame -Name "legal-L3-$Mode" -Lines $lines
    }
}
