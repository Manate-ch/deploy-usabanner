# The loader: Windows PowerShell 5.1 must be able to import the module, and
# under 5.1 every command hands itself to pwsh (PowerShell 7).

BeforeDiscovery {
    $moduleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'UsaBanner'
    $hasAnalyzer = [bool](Get-Module -ListAvailable -Name PSScriptAnalyzer)
    # The files Windows PowerShell 5.1 parses: the loader, Bootstrap\ and Public\.
    $files51 = @(
        @{ File = 'UsaBanner.psm1' }
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Bootstrap'), (Join-Path $moduleRoot 'Public') -Filter '*.ps1' -File) {
            @{ File = [System.IO.Path]::GetRelativePath($moduleRoot, $f.FullName) }
        }
    )
    $publicFiles = @(foreach ($f in Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Public') -Filter '*.ps1' -File) { @{ File = $f.Name } })
}

BeforeAll {
    $moduleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'UsaBanner'
    Import-Module (Join-Path $moduleRoot 'UsaBanner.psd1') -Force
    # PSScriptAnalyzer's check of syntax that Windows PowerShell 5.1 lacks, and nothing else.
    $settings51 = @{
        IncludeRules = @('PSUseCompatibleSyntax')
        Rules        = @{ PSUseCompatibleSyntax = @{ Enable = $true; TargetVersions = @('5.1') } }
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the files Windows PowerShell 5.1 parses' {
    It 'have a syntax check that catches PowerShell 7 syntax (else a pass proves nothing)' -Skip:(-not $hasAnalyzer) {
        $sample = Join-Path $TestDrive 'Sample.ps1'
        Set-Content -LiteralPath $sample -Value '$a = $b ?? ''c'''
        @(Invoke-ScriptAnalyzer -Path $sample -Settings $settings51).Count | Should -BeGreaterThan 0
    }

    It 'find no syntax 5.1 lacks in <File>' -ForEach $files51 -Skip:(-not $hasAnalyzer) {
        $found = @(Invoke-ScriptAnalyzer -Path (Join-Path $moduleRoot $File) -Settings $settings51)
        @($found | ForEach-Object { "line $($_.Line): $($_.Message)" }) | Should -BeNullOrEmpty
    }
}

Describe 'the module' {
    It 'is ASCII with LF line ends in every file: Windows PowerShell 5.1 reads a file without a BOM in the ANSI code page' {
        $bad = foreach ($f in Get-ChildItem -LiteralPath $moduleRoot -Recurse -File) {
            $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
            # 9 tab, 10 LF; anything else below 32, CR (13) and anything above 126 is out.
            if (@($bytes | Where-Object { $_ -gt 126 -or ($_ -lt 32 -and $_ -ne 9 -and $_ -ne 10) }).Count -gt 0) { $f.FullName }
        }
        @($bad) | Should -BeNullOrEmpty
    }

    It 'exports the commands in Public\, one a file, each named as its file' {
        $names = foreach ($f in Get-ChildItem -LiteralPath (Join-Path $moduleRoot 'Public') -Filter '*.ps1' -File) {
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
            $functions = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
            $functions.Count | Should -Be 1 -Because $f.Name
            $functions[0].Name | Should -BeExactly $f.BaseName
            $f.BaseName
        }
        $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'UsaBanner.psd1')
        @($manifest.FunctionsToExport | Sort-Object) | Should -Be @($names | Sort-Object)
        @((Get-Command -Module UsaBanner).Name | Sort-Object) | Should -Be @($names | Sort-Object)
    }

    It 'loads Private\ under PowerShell 7 only' {
        InModuleScope UsaBanner {
            Get-UsaBannerLoadOrder -Version '5.1' | Should -Be @('Bootstrap', 'Public')
            Get-UsaBannerLoadOrder -Version '7.4.0' | Should -Be @('Bootstrap', 'Private', 'Public')
        }
    }

    It 'has <File> check for PowerShell 7 first, and do nothing more after a hand-off' -ForEach $publicFiles {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $moduleRoot 'Public' $File), [ref]$null, [ref]$null)
        $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
        $function.Body.DynamicParamBlock | Should -BeNullOrEmpty
        $begin = $function.Body.BeginBlock
        $begin | Should -Not -BeNullOrEmpty
        $begin.Statements[0].Extent.Text | Should -BeExactly '$handedOff = Test-UsaBannerHandoff'
        $begin.Statements[1].Extent.Text | Should -BeExactly ("if (`$handedOff) {{ Invoke-UsaBannerHandoff -Command '{0}' -Parameters `$PSBoundParameters }}" -f $function.Name)
        foreach ($block in $function.Body.ProcessBlock, $function.Body.EndBlock) {
            if ($null -eq $block) { continue }
            $block.Statements[0].Extent.Text | Should -BeExactly 'if ($handedOff) { return }'
        }
    }
}

Describe 'the hand-off to pwsh' {
    It 'is needed under Windows PowerShell 5.1, and not under 7' {
        InModuleScope UsaBanner {
            Test-UsaBannerHandoff -Version '5.1' | Should -BeTrue
            Test-UsaBannerHandoff -Version '7.4.0' | Should -BeFalse
            Test-UsaBannerHandoff | Should -BeFalse
        }
    }

    It 'refuses to hand off again from inside a hand-off: the pwsh it ran was not PowerShell 7' {
        $saved = $env:USABANNER_HANDOFF
        try {
            $env:USABANNER_HANDOFF = '/opt/old/pwsh'
            { InModuleScope UsaBanner { Test-UsaBannerHandoff -Version '6.2' } } | Should -Throw "*'/opt/old/pwsh' was run as PowerShell 7, but it is PowerShell 6.2*"
        }
        finally { $env:USABANNER_HANDOFF = $saved }
    }

    It 'finds the pwsh on the PATH' {
        $expected = (Get-Command -Name 'pwsh' -CommandType Application | Select-Object -First 1).Path
        InModuleScope UsaBanner { Find-UsaBannerPwsh } | Should -Be $expected
    }

    It 'says what to install when there is no pwsh' {
        InModuleScope UsaBanner {
            Mock Find-UsaBannerPwsh { }
            { Invoke-UsaBannerHandoff -Command 'Show-UsaBannerArt' } | Should -Throw '*Show-UsaBannerArt needs PowerShell 7, and none was found. Install it*'
        }
    }

    It 'carries quotes, numbers and switches across unchanged' {
        InModuleScope UsaBanner {
            $parameters = @{ Name = "it's `"x`""; Count = 3; Force = [switch]$true; Quiet = [switch]$false }
            $script = ConvertTo-UsaBannerHandoffScript -Command 'Show-UsaBannerArt' -Parameters $parameters -Manifest "/tmp/o'k/UsaBanner.psd1" -Pwsh '/usr/bin/pwsh'
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$null, [ref]$errors)
            @($errors) | Should -BeNullOrEmpty
            $script | Should -Match ([regex]::Escape("Import-Module -Name '/tmp/o''k/UsaBanner.psd1'"))
            $script | Should -Match '(?m)^Show-UsaBannerArt @parameters$'
            $payload = [regex]::Match($script, "FromBase64String\('([^']+)'\)").Groups[1].Value
            $back = [System.Management.Automation.PSSerializer]::Deserialize([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload)))
            $back['Name'] | Should -BeExactly "it's `"x`""
            $back['Count'] | Should -Be 3
            $back['Force'] | Should -BeOfType [bool]
            $back['Force'] | Should -BeTrue
            $back['Quiet'] | Should -BeFalse
        }
    }

    It 'refuses a name that is not one of the module''s commands' {
        InModuleScope UsaBanner {
            { ConvertTo-UsaBannerHandoffScript -Command 'Remove-Item' -Manifest 'x' -Pwsh 'y' } | Should -Throw "*'Remove-Item' is not a command of this module*"
        }
    }

    It 'runs Show-UsaBannerArt in a real pwsh and returns what a direct run does, in <Mode>' -ForEach @(@{ Mode = 'none' }, @{ Mode = 'truecolor' }) {
        $direct = @(Show-UsaBannerArt -ColorMode $Mode)
        $handed = @(InModuleScope UsaBanner -Parameters @{ Mode = $Mode } {
                param($Mode)
                Invoke-UsaBannerHandoff -Command 'Show-UsaBannerArt' -Parameters @{ ColorMode = $Mode } -Pwsh (Get-Process -Id $PID).Path
            })
        $handed.Count | Should -Be 11
        ($handed -join "`n") | Should -BeExactly ($direct -join "`n")
    }

    It 'fails with the exit code when the command fails in pwsh' {
        {
            InModuleScope UsaBanner {
                Invoke-UsaBannerHandoff -Command 'Show-UsaBannerArt' -Parameters @{ Name = 'no-such-art' } -Pwsh (Get-Process -Id $PID).Path 2>$null
            }
        } | Should -Throw '*Show-UsaBannerArt failed in PowerShell 7*exit code 1*'
    }
}
