# The commands CONTRIBUTING.md shows a contributor: each must run as written,
# so every parameter it names is one the command has. AGENTS.md points to it.
# And README.md's command reference, which build/Update-UsaBannerReadme.ps1
# writes from the commands' own help (docs/DECISIONS.md, D27).

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    # One command a file in Public\, named as its file (tests\Loader.Tests.ps1 holds the module to it).
    $referenceCommands = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'Public') -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object { @{ Command = $_.BaseName } })
    $text = Get-Content -LiteralPath (Join-Path $repoRoot 'CONTRIBUTING.md') -Raw
    # Each fenced PowerShell block, parsed; then each call to one of the module's commands in it.
    $commandCases = foreach ($block in [regex]::Matches($text, '(?ms)^[ ]*```powershell[ ]*\n(.*?)^[ ]*```')) {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($block.Groups[1].Value, [ref]$null, [ref]$null)
        foreach ($command in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
            $name = $command.GetCommandName()
            if ($name -notmatch '^[A-Z][a-z]+-UsaBanner') { continue }
            @{
                Command    = $name
                Line       = $command.Extent.Text
                Parameters = @($command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } | ForEach-Object { $_.ParameterName })
            }
        }
    }
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'CONTRIBUTING.md' {
    # Discovery's variables are gone when tests run, so the count travels as test data.
    It 'shows the module''s commands at all, else this file checks nothing' -ForEach @(@{ Found = @($commandCases).Count }) {
        $Found | Should -BeGreaterThan 0
    }

    It 'names only parameters <Command> has: <Line>' -ForEach $commandCases {
        $known = @((Get-Command -Name $Command -Module UsaBanner).Parameters.Keys)
        foreach ($parameter in $Parameters) { $known | Should -Contain $parameter -Because $Line }
    }

    It 'is where AGENTS.md sends an agent whose human has a logo' {
        Get-Content -LiteralPath (Join-Path $repoRoot 'AGENTS.md') -Raw | Should -Match ([regex]::Escape('`CONTRIBUTING.md` says how to make the file'))
    }

    It 'makes a logo as its steps say: the file lands in art/base, keeps the art rules, and draws by name' {
        # The steps run against a copy of the module, so the new art file lands there, not in the repo.
        $work = Join-Path $TestDrive 'clone'
        $null = New-Item -ItemType Directory -Path $work
        Copy-Item -LiteralPath (Join-Path $repoRoot 'UsaBanner') -Destination $work -Recurse
        . (Join-Path $PSScriptRoot 'TestPng.ps1')
        $ring = New-TestPicture -Width 48 -Height 48 -Pixel {
            param($x, $y)
            if ($x -lt 4 -or $x -ge 44 -or $y -lt 4 -or $y -ge 44) { return 0, 0, 0, 0 }
            if ($x -lt 12 -or $x -ge 36 -or $y -lt 12 -or $y -ge 36) { return 30, 111, 217, 255 }
            255, 255, 255, 255
        }
        New-TestPng -Width 48 -Height 48 -Rgba $ring -Path (Join-Path $work 'contoso-logo.png')
        $text = Get-Content -LiteralPath (Join-Path $repoRoot 'CONTRIBUTING.md') -Raw
        $blocks = @([regex]::Matches($text, '(?ms)^[ ]*```powershell[ ]*\n(.*?)^[ ]*```') | ForEach-Object { $_.Groups[1].Value })
        # Step 1's block exactly as written; then step 3's calls to the module's own commands.
        $checks = [System.Management.Automation.Language.Parser]::ParseInput($blocks[1], [ref]$null, [ref]$null).FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            Where-Object { $_.GetCommandName() -match '^[A-Z][a-z]+-UsaBanner' } | ForEach-Object { $_.Extent.Text }
        Remove-Module UsaBanner -ErrorAction SilentlyContinue
        Push-Location $work
        try {
            $null = & ([scriptblock]::Create($blocks[0]))
            $drawn = @(foreach ($check in $checks) { , @(& ([scriptblock]::Create($check))) })
        }
        finally { Pop-Location }
        Test-Path -LiteralPath (Join-Path $work 'UsaBanner' 'art' 'base' 'contoso.json') | Should -BeTrue
        @($drawn).Count | Should -Be @($checks).Count
        foreach ($lines in $drawn) { @($lines).Count | Should -BeGreaterThan 0 }
        (@($drawn[0]) -join "`n") | Should -Match '^[ -~\n]+$'
    }
}

Describe 'README.md''s command reference (D27)' {
    BeforeAll {
        # The logo test leaves a copy of the module loaded from its test drive, which is gone by now.
        Remove-Module UsaBanner -Force -ErrorAction SilentlyContinue
        Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
        . (Join-Path $repoRoot 'build' 'ReadmeReference.ps1')
        $readme = [System.IO.File]::ReadAllLines((Join-Path $repoRoot 'README.md'))
        $skip = @([System.Management.Automation.Cmdlet]::CommonParameters) + @([System.Management.Automation.Cmdlet]::OptionalCommonParameters)
    }

    It 'is what the commands'' help gives, as build/Update-UsaBannerReadme.ps1 writes it' {
        { & (Join-Path $repoRoot 'build' 'Update-UsaBannerReadme.ps1') -Check } | Should -Not -Throw
    }

    It 'has <Command> give a synopsis, a description, an example and help for each parameter, which its section is made of' -ForEach $referenceCommands {
        $help = Get-Help $Command -Full
        "$($help.Synopsis)".Trim() | Should -Not -BeLike "$Command*" -Because 'with no .SYNOPSIS, Get-Help gives the syntax in its place'
        ((@($help.description) | ForEach-Object Text) -join '').Trim() | Should -Not -BeNullOrEmpty
        @($help.examples.example).Count | Should -BeGreaterThan 0
        foreach ($name in @((Get-Command $Command).Parameters.Keys | Where-Object { $skip -notcontains $_ })) {
            ((@((Get-Help $Command -Parameter $name).description) | ForEach-Object Text) -join '').Trim() | Should -Not -BeNullOrEmpty -Because "-$name has no .PARAMETER"
        }
    }

    It 'has every #link in README.md land on a heading, on GitLab and on GitHub alike' {
        [array]::IndexOf($readme, $ReferenceBegin) | Should -BeGreaterOrEqual 0 -Because 'the reference is there'
        $links = @([regex]::Matches(($readme -join "`n"), '\]\(#([^)\s]+)\)') | ForEach-Object { $_.Groups[1].Value })
        $links.Count | Should -BeGreaterThan 0
        $gitlab = @(Get-ReferenceHeadingId -Lines $readme -Rules GitLab | ForEach-Object Id)
        $github = @(Get-ReferenceHeadingId -Lines $readme -Rules GitHub | ForEach-Object Id)
        foreach ($link in $links) {
            $gitlab | Should -Contain $link -Because "GitLab must find #$link"
            $github | Should -Contain $link -Because "GitHub must find #$link"
        }
    }

    It 'numbers a heading''s second use, and runs of - apart, as GitLab and GitHub each do' {
        $lines = @('# Path', '```', '# not a heading', '```', '## Path', '### A -- B', '#### `-Path`')
        @(Get-ReferenceHeadingId -Lines $lines -Rules GitLab | ForEach-Object Id) | Should -Be @('path', 'path-1', 'a-b', '-path')
        @(Get-ReferenceHeadingId -Lines $lines -Rules GitHub | ForEach-Object Id) | Should -Be @('path', 'path-1', 'a----b', '-path')
    }

    It 'escapes in help text what GitLab would not show as written: <Case>' -ForEach @(
        @{ Case = 'a placeholder, which it drops as a tag'; Text = 'UsaBanner-<version>.zip'; Markdown = 'UsaBanner-\<version\>.zip' }
        @{ Case = 'stars and underscores'; Text = '*.ps1 and NO_COLOR'; Markdown = '\*.ps1 and NO\_COLOR' }
        @{ Case = 'references it would link'; Text = 'see #12 and @admins'; Markdown = 'see \#12 and \@admins' }
        @{ Case = 'a backslash, and a % before a name'; Text = '%ProgramData%\UsagiTools'; Markdown = '\%ProgramData%\\UsagiTools' }
        @{ Case = 'a line that would start a list'; Text = '- not a list'; Markdown = '\- not a list' }
        @{ Case = 'a line that would start a numbered list'; Text = '1. not a list'; Markdown = '1\. not a list' }
        @{ Case = 'a line that would be a heading'; Text = '# not a heading'; Markdown = '\# not a heading' }
        @{ Case = 'plain words, left as they are'; Text = 'The tier: UNSET, DEV-TEST or PROD.'; Markdown = 'The tier: UNSET, DEV-TEST or PROD.' }
    ) {
        ConvertTo-ReferenceInline $Text | Should -BeExactly $Markdown
    }

    It 'keeps a list a list, the paragraph after it apart, and a drawn table as drawn' {
        $text = "Puts in place:`n- one`n  more of one`n- two`nAfter the list.`n`n+---+`n| a |`n+---+`n`nLast."
        @(ConvertTo-ReferenceBlock $text) | Should -BeExactly @('Puts in place:', '', '- one', '  more of one', '- two', '', 'After the list.', '', '```text', '+---+', '| a |', '+---+', '```', '', 'Last.')
    }
}
