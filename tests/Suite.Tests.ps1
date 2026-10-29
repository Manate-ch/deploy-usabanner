# The tests themselves. PowerShell's variable names ignore case, so an It whose body sets $message
# while its -ForEach data has a Message key overwrites that data, and "$message | Should -BeLike
# $Message" then compares a value with itself and always passes. Three tests did, each for weeks
# (found 2026-10-24).

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $testFiles = @(foreach ($folder in 'tests', 'prototype/tests') {
        $path = Join-Path $repoRoot $folder
        if (Test-Path -LiteralPath $path) {
            foreach ($file in Get-ChildItem -LiteralPath $path -Filter '*.Tests.ps1' -File) { @{ File = "$folder/$($file.Name)"; Path = $file.FullName } }
        }
    })
}

Describe 'the test files' {
    It 'are found, else this checks nothing' -ForEach @(@{ Found = @($testFiles).Count }) {
        $Found | Should -BeGreaterThan 20
    }

    It 'set no variable named as a key of the test''s own data, in <File>' -ForEach $testFiles {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $its = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'It' }, $true)
        $clashes = foreach ($it in $its) {
            $elements = @($it.CommandElements)
            $data = $null
            for ($i = 0; $i -lt $elements.Count - 1; $i++) {
                if ($elements[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and $elements[$i].ParameterName -in 'ForEach', 'TestCases') { $data = $elements[$i + 1] }
            }
            $body = @($elements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] })
            if (-not $data -or -not $body.Count) { continue }
            $keys = @{}
            foreach ($table in $data.FindAll({ param($n) $n -is [System.Management.Automation.Language.HashtableAst] }, $true)) {
                foreach ($pair in $table.KeyValuePairs) {
                    if ($pair.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $keys[$pair.Item1.Value.ToLowerInvariant()] = $true }
                }
            }
            foreach ($assign in $body[-1].FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
                if ($assign.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $keys.ContainsKey($assign.Left.VariablePath.UserPath.ToLowerInvariant())) {
                    "line $($assign.Extent.StartLineNumber): `$$($assign.Left.VariablePath.UserPath) in It $($elements[1].Extent.Text)"
                }
            }
        }
        @($clashes) | Should -BeNullOrEmpty
    }
}
