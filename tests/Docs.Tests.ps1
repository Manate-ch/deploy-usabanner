# The commands CONTRIBUTING.md shows a contributor: each must run as written,
# so every parameter it names is one the command has. AGENTS.md points to it.

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
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
