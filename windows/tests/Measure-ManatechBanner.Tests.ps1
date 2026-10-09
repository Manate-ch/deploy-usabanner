# Pester 5 tests for Measure-ManatechBanner.ps1. It times Windows-only calls
# (CIM, quser, w32tm), so it runs for real only on a host; here: it parses, it
# says what to pass when the module is missing, and it calls nothing that
# changes a host - it is meant to be run on production servers.

BeforeAll {
    $script:Measure = Join-Path $PSScriptRoot '../Measure-ManatechBanner.ps1'
}

Describe 'Measure-ManatechBanner.ps1' {
    It 'parses' {
        $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($Measure, [ref]$null, [ref]$errors)
        @($errors).Count | Should -Be 0
    }
    It 'is ASCII only (Windows PowerShell 5.1 reads a file without a BOM as ANSI)' {
        @([System.IO.File]::ReadAllBytes($Measure) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
    It 'stops with what to pass when the module is not where it looks' {
        { & $Measure -ModulePath (Join-Path $TestDrive 'nowhere.psm1') } | Should -Throw '*pass -ModulePath*'
    }
    It 'calls nothing that changes a host: no Set-, New-, Remove-, Stop-, Start-, Restart-, Register-, Install- or Invoke-CimMethod' {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($Measure, [ref]$null, [ref]$null)
        $names = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        $names.Count | Should -BeGreaterThan 10
        # Session-only commands, which leave the host as it was.
        $sessionOnly = 'New-Object', 'Set-StrictMode'
        $changing = @($names | Where-Object { $_ -match '^(Set|New|Remove|Stop|Start|Restart|Register|Unregister|Install|Uninstall|Enable|Disable|Clear|Rename|Move|Copy)-|^Invoke-CimMethod$|^msiexec' -and $_ -notin $sessionOnly })
        $changing | Should -BeNullOrEmpty
    }
}
