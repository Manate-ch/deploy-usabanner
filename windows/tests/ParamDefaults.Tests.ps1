# Pester 5 tests: no shipped script reads $PSScriptRoot or $PSCommandPath in
# its param() defaults. When Windows PowerShell 5.1 starts an advanced script
# ([CmdletBinding()]) with powershell.exe -File - the way a scheduled task, a
# GPO task, or pwsh 7 handing a script to 5.1 starts it - both are empty in
# its param() defaults and set in its body (measured on a lab DC, 2026-10-12:
# the publisher stopped in Split-Path before reading anything). A plain
# script, & from a 5.1 session and pwsh 7 all see them set, so a run here
# never shows the failure; only this rule does. It covers plain scripts too:
# adding [CmdletBinding()] later would bring the failure back. Fill such a
# default in the script body.

BeforeAll {
    # Find-ParamDefaultRoot AST - "<parameter>: <variable>" for each default in
    # the script's own param() block that reads $PSScriptRoot or $PSCommandPath.
    function Find-ParamDefaultRoot {
        param([System.Management.Automation.Language.ScriptBlockAst]$Ast)
        if (-not $Ast.ParamBlock) { return }
        foreach ($p in $Ast.ParamBlock.Parameters) {
            if (-not $p.DefaultValue) { continue }
            $vars = $p.DefaultValue.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)
            foreach ($v in $vars) {
                if ($v.VariablePath.UserPath -in 'PSScriptRoot', 'PSCommandPath') {
                    "$($p.Name.VariablePath.UserPath): $($v.VariablePath.UserPath)"
                }
            }
        }
    }
}

Describe 'param() defaults in the shipped scripts' {
    It 'are checked by a rule that finds both variables and nothing else (positive control)' {
        $text = 'param([string]$RepoPath = (Split-Path -Parent $PSScriptRoot), [string]$Self = $PSCommandPath, [string]$Data = (Join-Path $env:ProgramData "x"))'
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
        @(Find-ParamDefaultRoot $ast) | Should -Be @('RepoPath: PSScriptRoot', 'Self: PSCommandPath')
    }
    It 'never read $PSScriptRoot or $PSCommandPath (empty there in an advanced script under Windows PowerShell 5.1 -File)' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..') -Filter '*.ps1' -File)
        $files.Count | Should -BeGreaterThan 3
        $hits = @(foreach ($f in $files) {
                $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$null)
                foreach ($h in @(Find-ParamDefaultRoot $ast)) { "$($f.Name) -$h" }
            })
        $hits -join '; ' | Should -BeExactly ''
    }
}
