# Pester 5 tests for the default-shell decision in Install-ManatechBanner.ps1. The install script
# runs as soon as it is loaded (it changes the host), so the one function is taken from its syntax
# tree and defined on its own here.

BeforeAll {
    $install = Join-Path $PSScriptRoot '../Install-ManatechBanner.ps1'
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($install, [ref]$null, [ref]$null)
    $fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ShellChoice' }, $true))
    $fn | Should -HaveCount 1
    . ([scriptblock]::Create($fn[0].Extent.Text))
}

Describe 'Get-ShellChoice' {
    It 'with any, keeps a PowerShell that is set already: <Current>' -ForEach @(
        @{ Current = 'C:\Program Files\PowerShell\7\pwsh.exe' }
        @{ Current = '"C:\Program Files\PowerShell\7\pwsh.exe"' }
        @{ Current = 'C:\PROGRA~1\POWERSHELL\7\PWSH.EXE' }
        @{ Current = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' }
    ) {
        Get-ShellChoice -Wanted any -Current $Current | Should -Be 'keep'
    }
    It 'with any, sets Windows PowerShell where the default is another shell or none: <Current>' -ForEach @(
        @{ Current = '' }
        @{ Current = 'C:\Windows\System32\cmd.exe' }
        @{ Current = 'C:\Program Files\Git\bin\bash.exe' }
    ) {
        Get-ShellChoice -Wanted any -Current $Current | Should -Be 'powershell'
    }
    It 'passes the explicit choices through, whatever is set: <Wanted>' -ForEach @(
        @{ Wanted = 'keep' }
        @{ Wanted = 'powershell' }
        @{ Wanted = 'pwsh' }
    ) {
        Get-ShellChoice -Wanted $Wanted -Current 'C:\Windows\System32\cmd.exe' | Should -Be $Wanted
    }
}

Describe 'the scripts that take -DefaultShell' {
    It 'both accept any, and the sync uses it unless told otherwise' {
        foreach ($name in 'Install-ManatechBanner.ps1', 'Sync-ManatechBanner.ps1') {
            $p = (Get-Command (Join-Path $PSScriptRoot "../$name")).Parameters['DefaultShell']
            ($p.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }).ValidValues | Should -Contain 'any' -Because $name
        }
        $sync = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Sync-ManatechBanner.ps1'), [ref]$null, [ref]$null)
        $param = @($sync.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'DefaultShell' })[0]
        $param.DefaultValue.Value | Should -Be 'any'
    }
}
