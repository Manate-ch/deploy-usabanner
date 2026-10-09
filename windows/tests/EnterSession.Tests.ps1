# Pester 5 tests for Enter-ManatechPSSession's client side: which colour mode
# it asks the remote host to draw in, where that comes from, and that a
# failed banner never stops the session. The remoting cmdlets are mocked with
# their real parameters (only the Session object's type is relaxed), so a
# parameter New-PSSession does not have fails here as it would for real.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../ManatechBanner.psm1') -Force
}

Describe 'Enter-ManatechPSSession' {
    BeforeEach {
        Mock -ModuleName ManatechBanner New-PSSession { [pscustomobject]@{ ComputerName = 'h-test' } }
        Mock -ModuleName ManatechBanner Invoke-Command -RemoveParameterType Session { 'BANNER ' + (@($ArgumentList) -join '|') }
        Mock -ModuleName ManatechBanner Enter-PSSession -RemoveParameterType Session { }
        Mock -ModuleName ManatechBanner Write-Host { }
        $script:saved = @{ C = $env:MANATECH_BANNER_COLOR; G = $env:MANATECH_BANNER_GLYPHS }
        $env:MANATECH_BANNER_COLOR = $null
        $env:MANATECH_BANNER_GLYPHS = $null
    }
    AfterEach {
        $env:MANATECH_BANNER_COLOR = $saved.C
        $env:MANATECH_BANNER_GLYPHS = $saved.G
    }

    It 'asks for the banner in the colours given, opens the session without them, prints, then enters' {
        Enter-ManatechPSSession -HostName 'h-test' -UserName 'u' -Color 16 -Glyphs ascii
        Should -Invoke -ModuleName ManatechBanner New-PSSession -Times 1 -Exactly -ParameterFilter { $HostName -eq 'h-test' -and $UserName -eq 'u' }
        Should -Invoke -ModuleName ManatechBanner Invoke-Command -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq '16' -and $ArgumentList[1] -eq 'ascii' }
        Should -Invoke -ModuleName ManatechBanner Write-Host -Times 1 -Exactly -ParameterFilter { "$Object" -eq 'BANNER 16|ascii' }
        Should -Invoke -ModuleName ManatechBanner Enter-PSSession -Times 1 -Exactly
    }
    It 'takes the colour mode and glyphs from MANATECH_BANNER_COLOR and MANATECH_BANNER_GLYPHS when not given' {
        $env:MANATECH_BANNER_COLOR = '256'
        $env:MANATECH_BANNER_GLYPHS = 'ASCII'
        Enter-ManatechPSSession -HostName 'h-test'
        Should -Invoke -ModuleName ManatechBanner Invoke-Command -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq '256' -and $ArgumentList[1] -ceq 'ascii' }
    }
    It 'prefers -Color over the variable' {
        $env:MANATECH_BANNER_COLOR = '256'
        Enter-ManatechPSSession -HostName 'h-test' -Color none
        Should -Invoke -ModuleName ManatechBanner Invoke-Command -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq 'none' }
    }
    It 'leaves the remote settings alone when nothing is set' {
        Enter-ManatechPSSession -HostName 'h-test'
        Should -Invoke -ModuleName ManatechBanner Invoke-Command -Times 1 -Exactly -ParameterFilter { -not $ArgumentList[0] -and -not $ArgumentList[1] }
    }
    It 'ignores a value the variable must not hold, with a warning, and still enters' {
        $env:MANATECH_BANNER_COLOR = 'rainbow'
        $warnings = Enter-ManatechPSSession -HostName 'h-test' 3>&1
        "$warnings" | Should -Match "MANATECH_BANNER_COLOR='rainbow' is not one of"
        Should -Invoke -ModuleName ManatechBanner Invoke-Command -Times 1 -Exactly -ParameterFilter { -not $ArgumentList[0] }
        Should -Invoke -ModuleName ManatechBanner Enter-PSSession -Times 1 -Exactly
    }
    It 'hands the remote host the module''s own remote block' {
        $block = InModuleScope ManatechBanner { $script:RemoteBannerBlock }
        Enter-ManatechPSSession -HostName 'h-test'
        Should -Invoke -ModuleName ManatechBanner Invoke-Command -Times 1 -Exactly -ParameterFilter { "$ScriptBlock" -eq "$block" }
    }
    It 'still enters the session when the remote host gives no banner' {
        Mock -ModuleName ManatechBanner Invoke-Command -RemoveParameterType Session { throw 'no module there' }
        $warnings = Enter-ManatechPSSession -HostName 'h-test' 3>&1
        "$warnings" | Should -Match 'no banner from h-test: no module there'
        Should -Invoke -ModuleName ManatechBanner Enter-PSSession -Times 1 -Exactly
    }
}

Describe 'the block the remote host runs' {
    BeforeAll {
        # Unbound from the module, so it finds the stand-ins below the way it
        # would find the remote host's module.
        $script:Remote = [scriptblock]::Create((InModuleScope ManatechBanner { $script:RemoteBannerBlock }).ToString())
        function Import-Module { param([Parameter(ValueFromRemainingArguments)]$Rest) }
        # The block builds the module's path from ProgramData, which Linux does not set.
        $script:savedProgramData = $env:ProgramData
        $env:ProgramData = $TestDrive
    }
    AfterAll { $env:ProgramData = $savedProgramData }
    It 'draws in the colours asked for when the remote module has the options' {
        function Get-ManatechBannerText { param([string]$DataPath, [string]$Color, [string]$Glyphs) "drawn $Color $Glyphs" }
        & $Remote '16' 'ascii' | Should -BeExactly 'drawn 16 ascii'
    }
    It 'asks an older remote module for its own banner rather than failing' {
        function Get-ManatechBannerText { param([string]$DataPath) 'drawn its own way' }
        & $Remote '16' 'ascii' | Should -BeExactly 'drawn its own way'
    }
    It 'passes nothing when nothing was asked for' {
        function Get-ManatechBannerText { param([string]$DataPath, [string]$Color, [string]$Glyphs) "drawn [$Color] [$Glyphs]" }
        & $Remote '' '' | Should -BeExactly 'drawn [] []'
    }
}
