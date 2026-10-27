# Enter-UsaPSSession (UsaBanner/Public/Enter-UsaPSSession.ps1): the session it opens, the banner it has the host
# draw over it, the warning when there is none, and the session it enters. The remoting cmdlets are mocked with
# their real parameters, and the session stand-in is of the real type, so a parameter New-PSSession lacks, or an
# object Enter-PSSession would not take, fails here as it would for real.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    $esc = [string][char]27
    # Pester lists each bound parameter's aliases among the bound names too (KeyFilePath brings IdentityFilePath):
    # the names New-PSSession was called with are the rest.
    $aliases = @((Get-Command New-PSSession).Parameters.Values | ForEach-Object { $_.Aliases })
}

Describe 'Enter-UsaPSSession' {
    BeforeEach {
        $global:UsaSession = New-MockObject -Type System.Management.Automation.Runspaces.PSSession -Properties @{ ComputerName = 'h-open' }
        $global:UsaShown = [System.Collections.Generic.List[string]]::new()
        $global:UsaSent = $null
        Mock -ModuleName UsaBanner New-PSSession { $global:UsaSession }
        Mock -ModuleName UsaBanner Invoke-Command { $global:UsaSent = $ScriptBlock; "$esc[1mline 1$esc[0m", 'line 2' }
        Mock -ModuleName UsaBanner Out-Host { $global:UsaShown.Add([string]$InputObject) }
        Mock -ModuleName UsaBanner Enter-PSSession { }
        Mock -ModuleName UsaBanner Invoke-UsaBannerHandoff { throw 'handed off' }
        $script:saved = @{ C = $env:USABANNER_COLOR; G = $env:USABANNER_GLYPHS }
        $env:USABANNER_COLOR = $null
        $env:USABANNER_GLYPHS = $null
    }
    AfterEach {
        $env:USABANNER_COLOR = $saved.C
        $env:USABANNER_GLYPHS = $saved.G
    }

    It 'opens the session over SSH with what it was given, prints the host''s banner as it came, then enters that session' {
        Enter-UsaPSSession -HostName 'h-test.ad.example' -UserName 'admin@ad.example' -Port 2222 -KeyFilePath '/keys/id_ed25519'
        Should -Invoke -ModuleName UsaBanner New-PSSession -Times 1 -Exactly -ParameterFilter {
            ((@($PesterBoundParameters.Keys) | Where-Object { $_ -notin $aliases } | Sort-Object) -join ',') -eq 'ErrorAction,HostName,KeyFilePath,Port,UserName' -and
            $HostName -eq 'h-test.ad.example' -and $UserName -eq 'admin@ad.example' -and $Port -eq 2222 -and $KeyFilePath -eq '/keys/id_ed25519'
        }
        Should -Invoke -ModuleName UsaBanner Invoke-Command -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Session[0], $global:UsaSession) }
        @($global:UsaShown) | Should -Be @("$esc[1mline 1$esc[0m", 'line 2')
        Should -Invoke -ModuleName UsaBanner Enter-PSSession -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Session, $global:UsaSession) }
    }

    It 'opens the session over WinRM with what it was given, and nothing else' {
        $credential = [pscredential]::new('ad\admin', [securestring]::new())
        $option = [System.Management.Automation.Remoting.PSSessionOption]::new()
        Enter-UsaPSSession 'h-test.ad.example' -Credential $credential -Port 5986 -UseSSL -ConfigurationName 'PowerShell.7' -Authentication Kerberos -SessionOption $option -ColorMode 16
        Should -Invoke -ModuleName UsaBanner New-PSSession -Times 1 -Exactly -ParameterFilter {
            ((@($PesterBoundParameters.Keys) | Where-Object { $_ -notin $aliases } | Sort-Object) -join ',') -eq 'Authentication,ComputerName,ConfigurationName,Credential,ErrorAction,Port,SessionOption,UseSSL' -and
            $ComputerName -eq 'h-test.ad.example' -and $Credential.UserName -eq 'ad\admin' -and $Port -eq 5986 -and $UseSSL -and
            $ConfigurationName -eq 'PowerShell.7' -and $Authentication -eq 'Kerberos' -and [object]::ReferenceEquals($SessionOption, $option)
        }
        Should -Invoke -ModuleName UsaBanner Enter-PSSession -Times 1 -Exactly
    }

    It 'uses a session already open, given by name or by place, and opens none' -ForEach @(
        @{ Case = 'named'; Call = { Enter-UsaPSSession -Session $global:UsaSession } }
        @{ Case = 'by place'; Call = { Enter-UsaPSSession $global:UsaSession } }
    ) {
        & $Call
        Should -Invoke -ModuleName UsaBanner New-PSSession -Times 0 -Exactly
        Should -Invoke -ModuleName UsaBanner Enter-PSSession -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Session, $global:UsaSession) }
    }

    It 'warns once when the host gives no banner, in the host''s words without its prefix, and still enters' {
        Mock -ModuleName UsaBanner Invoke-Command { throw 'UsaBanner: no banner is deployed here, so there is none to show.' }
        $warnings = @(Enter-UsaPSSession -HostName 'h-test.ad.example' 3>&1)
        @($warnings | ForEach-Object { "$_" }) | Should -Be @('UsaBanner: no banner from h-test.ad.example: no banner is deployed here, so there is none to show.')
        Should -Invoke -ModuleName UsaBanner Out-Host -Times 0 -Exactly
        Should -Invoke -ModuleName UsaBanner Enter-PSSession -Times 1 -Exactly
    }

    It 'names an open session by its own computer name in that warning' {
        Mock -ModuleName UsaBanner Invoke-Command { throw 'The term ''Get-UsaBanner'' is not recognized' }
        $warnings = @(Enter-UsaPSSession -Session $global:UsaSession 3>&1)
        "$warnings" | Should -BeExactly 'UsaBanner: no banner from h-open: The term ''Get-UsaBanner'' is not recognized'
    }

    It 'stops when the session cannot be opened: there is nothing to enter' {
        Mock -ModuleName UsaBanner New-PSSession { throw 'h-gone: no such host' }
        { Enter-UsaPSSession -HostName 'h-gone' } | Should -Throw '*h-gone: no such host*'
        Should -Invoke -ModuleName UsaBanner Enter-PSSession -Times 0 -Exactly
    }

    It 'has the host draw with this terminal''s colour mode and glyphs: <Case>' -ForEach @(
        @{ Case = 'as given'; Given = @{ ColorMode = '16'; Glyphs = 'ascii' }; Color = $null; Glyph = $null; Want = @('16', 'ascii') }
        @{ Case = 'from USABANNER_COLOR and USABANNER_GLYPHS here'; Given = @{}; Color = '256'; Glyph = 'ascii'; Want = @('256', 'ascii') }
        @{ Case = 'the flags over the variables'; Given = @{ ColorMode = 'none' }; Color = '256'; Glyph = 'unicode'; Want = @('none', 'unicode') }
        @{ Case = 'none of either: the host''s own'; Given = @{}; Color = $null; Glyph = $null; Want = @('', '') }
    ) {
        $env:USABANNER_COLOR = $Color
        $env:USABANNER_GLYPHS = $Glyph
        Enter-UsaPSSession -HostName 'h-test.ad.example' @Given
        Should -Invoke -ModuleName UsaBanner Invoke-Command -Times 1 -Exactly -ParameterFilter { "$($ArgumentList[0])" -eq $Want[0] -and "$($ArgumentList[1])" -eq $Want[1] }
    }

    It 'refuses -HostName under Windows PowerShell 5.1 before it opens anything, saying what to run' {
        Mock -ModuleName UsaBanner Test-UsaBannerHandoff { $true }
        { Enter-UsaPSSession -HostName 'h-test.ad.example' } | Should -Throw '*Enter-UsaPSSession -HostName is PowerShell remoting over SSH, which needs PowerShell 7: run it in pwsh. Windows PowerShell 5.1 enters over WinRM, with -ComputerName.*'
        Should -Invoke -ModuleName UsaBanner New-PSSession -Times 0 -Exactly
    }

    It 'enters over WinRM under Windows PowerShell 5.1 as it is, handed to no pwsh' {
        Mock -ModuleName UsaBanner Test-UsaBannerHandoff { $true }
        Enter-UsaPSSession 'h-test.ad.example'
        Should -Invoke -ModuleName UsaBanner Invoke-UsaBannerHandoff -Times 0 -Exactly
        Should -Invoke -ModuleName UsaBanner New-PSSession -Times 1 -Exactly
        Should -Invoke -ModuleName UsaBanner Enter-PSSession -Times 1 -Exactly
    }

    It 'passes New-PSSession exactly the transport parameters it takes, each one New-PSSession has in the same set' {
        $function = (Get-Command Enter-UsaPSSession).ScriptBlock.Ast
        $loop = $function.Find({ param($node) $node -is [System.Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -eq 'key' }, $true)
        $passed = @($loop.Condition.FindAll({ param($node) $node -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) | ForEach-Object { $_.Value })
        $common = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
        $own = (Get-Command Enter-UsaPSSession).ParameterSets
        $theirs = (Get-Command New-PSSession).ParameterSets
        $declared = foreach ($set in 'SSHHost', 'ComputerName') {
            $names = @(($own | Where-Object Name -eq $set).Parameters.Name | Where-Object { $_ -notin $common -and $_ -notin 'ColorMode', 'Glyphs' })
            $match = @($theirs | Where-Object Name -eq $set)
            $match.Count | Should -Be 1 -Because "New-PSSession has a $set set"
            @($names | Where-Object { $_ -notin $match[0].Parameters.Name }) | Should -BeNullOrEmpty -Because "New-PSSession's $set set takes every one"
            $names
        }
        @($passed | Sort-Object) | Should -Be @($declared | Sort-Object -Unique)
    }
}

Describe 'the block the host runs' {
    BeforeAll {
        # The block Enter-UsaPSSession sends, unbound from the module, so it finds the stand-ins below the way it
        # finds the host's module.
        Mock -ModuleName UsaBanner New-PSSession { New-MockObject -Type System.Management.Automation.Runspaces.PSSession -Properties @{ ComputerName = 'h-open' } }
        Mock -ModuleName UsaBanner Invoke-Command { $global:UsaSent = $ScriptBlock }
        Mock -ModuleName UsaBanner Enter-PSSession { }
        Enter-UsaPSSession -HostName 'h-test.ad.example'
        $script:Remote = [scriptblock]::Create($global:UsaSent.ToString())
        function Import-Module { param([string]$Name, $ErrorAction) $global:UsaImported = $Name }
        $script:saved = @{ C = $env:USABANNER_COLOR; G = $env:USABANNER_GLYPHS }
    }
    AfterAll {
        $env:USABANNER_COLOR = $saved.C
        $env:USABANNER_GLYPHS = $saved.G
    }
    BeforeEach {
        $env:USABANNER_COLOR = 'truecolor'
        $env:USABANNER_GLYPHS = $null
    }

    It 'imports UsaBanner and returns the banner after login, as the host''s logins draw it' {
        function Get-UsaBanner { param([string]$Moment) "drawn $Moment" }
        & $Remote '' '' | Should -BeExactly 'drawn PostLogon'
        $global:UsaImported | Should -BeExactly 'UsaBanner'
    }

    It 'draws with this terminal''s colour mode and glyphs, then puts the host''s own back' {
        function Get-UsaBanner { param([string]$Moment) "drawn $env:USABANNER_COLOR $env:USABANNER_GLYPHS" }
        & $Remote '16' 'ascii' | Should -BeExactly 'drawn 16 ascii'
        $env:USABANNER_COLOR | Should -BeExactly 'truecolor'
        $env:USABANNER_GLYPHS | Should -BeNullOrEmpty
    }

    It 'leaves the host''s own colour mode and glyphs when this terminal has none' {
        function Get-UsaBanner { param([string]$Moment) "drawn $env:USABANNER_COLOR [$env:USABANNER_GLYPHS]" }
        & $Remote '' '' | Should -BeExactly 'drawn truecolor []'
    }

    It 'puts the host''s own back when the draw fails' {
        function Get-UsaBanner { param([string]$Moment) throw 'no banner is deployed here' }
        { & $Remote '16' 'ascii' } | Should -Throw '*no banner is deployed here*'
        $env:USABANNER_COLOR | Should -BeExactly 'truecolor'
        $env:USABANNER_GLYPHS | Should -BeNullOrEmpty
    }
}
