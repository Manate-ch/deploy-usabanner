# A host's tier and role from its AD Description (UsaBanner/Private/AdDescription.ps1,
# docs/DECISIONS.md D29): the Description read as today's banner reads it, today's tier
# names in this banner's tiers, the configuration over it, the cache a login reads, and
# the Windows periodic job's read of AD, which the tests stand in for.

BeforeDiscovery {
    # Desc: the Description as AD holds it; Tier, Role and Prefix: how it reads. The first
    # fourteen are the old banner's cases (its windows/tests/AdDescription.Tests.ps1,
    # retired 2026-10-29), with this banner's tiers.
    $script:Cases = @(
        @{ Desc = 'PROD: Hyper-V host'; Tier = 'PROD'; Role = 'Hyper-V host'; Prefix = 'PROD' }
        @{ Desc = 'PROD : Hyper-V host'; Tier = 'PROD'; Role = 'Hyper-V host'; Prefix = 'PROD' }
        @{ Desc = '  prod:  Hyper-V host  '; Tier = 'PROD'; Role = 'Hyper-V host'; Prefix = 'PROD' }
        @{ Desc = "PROD:`tHyper-V host"; Tier = 'PROD'; Role = 'Hyper-V host'; Prefix = 'PROD' }
        @{ Desc = "`tLAB`t:Grafana node"; Tier = 'LAB'; Role = 'Grafana node'; Prefix = 'LAB' }
        @{ Desc = 'lab:Grafana node'; Tier = 'LAB'; Role = 'Grafana node'; Prefix = 'LAB' }
        @{ Desc = 'PROD: role: with a colon'; Tier = 'PROD'; Role = 'role: with a colon'; Prefix = 'PROD' }
        @{ Desc = 'PROD:'; Tier = 'PROD'; Role = ''; Prefix = 'PROD' }
        @{ Desc = 'Grafana visualization node'; Tier = ''; Role = 'Grafana visualization node'; Prefix = '' }
        @{ Desc = '  Grafana node  '; Tier = ''; Role = 'Grafana node'; Prefix = '' }
        @{ Desc = 'QA-1: kept whole, the prefix is not letters only'; Tier = ''; Role = 'QA-1: kept whole, the prefix is not letters only'; Prefix = '' }
        @{ Desc = 'PROD 1: a space inside is no prefix'; Tier = ''; Role = 'PROD 1: a space inside is no prefix'; Prefix = '' }
        @{ Desc = ': no prefix at all'; Tier = ''; Role = ': no prefix at all'; Prefix = '' }
        @{ Desc = ''; Tier = ''; Role = ''; Prefix = '' }
        # Today's names in this banner's tiers, and the hyphen in DEV-TEST.
        @{ Desc = 'DEV-TEST : build agents'; Tier = 'DEV-TEST'; Role = 'build agents'; Prefix = 'DEV-TEST' }
        @{ Desc = 'dev: build agents'; Tier = 'DEV-TEST'; Role = 'build agents'; Prefix = 'DEV' }
        @{ Desc = 'Test: build agents'; Tier = 'DEV-TEST'; Role = 'build agents'; Prefix = 'TEST' }
        @{ Desc = 'STAGE: release rehearsal'; Tier = 'LAB'; Role = 'release rehearsal'; Prefix = 'STAGE' }
        @{ Desc = 'pub: kiosk'; Tier = 'PUB'; Role = 'kiosk'; Prefix = 'PUB' }
        # A prefix that is no tier still gives the role after it.
        @{ Desc = 'QA: test rig'; Tier = ''; Role = 'test rig'; Prefix = 'QA' }
        @{ Desc = 'DEV-: test rig'; Tier = ''; Role = 'test rig'; Prefix = 'DEV-' }
        @{ Desc = '-X: a prefix starts with a letter'; Tier = ''; Role = '-X: a prefix starts with a letter'; Prefix = '' }
    )
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force

    function Read-Description {
        # In:  a Description
        # Out: how the module reads it: @{ Tier; Role; Prefix }
        param([string]$Text)
        InModuleScope UsaBanner -Parameters @{ Text = $Text } { param($Text) ConvertFrom-UsaBannerAdDescription -Text $Text }
    }

    function Resolve-Host {
        # In:  the configuration's environment and role, and the cached Description
        # Out: Resolve-UsaBannerHostConfig's answer, and the configuration it was given
        param([string]$Environment = 'UNSET', [string]$Role = '', [string]$Description = '')
        InModuleScope UsaBanner -Parameters @{ Environment = $Environment; Role = $Role; Description = $Description } {
            param($Environment, $Role, $Description)
            $config = Get-UsaBannerConfigDefault
            $config['environment'] = $Environment
            $config['role'] = $Role
            @{ Given = $config; Resolved = (Resolve-UsaBannerHostConfig -Config $config -Description $Description) }
        }
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'an AD Description, as a tier and a role' {
    It 'reads "<Desc>" as the tier "<Tier>" and the role "<Role>"' -ForEach $Cases {
        $read = Read-Description $Desc
        $read.Tier | Should -BeExactly $Tier
        $read.Role | Should -BeExactly $Role
        $read.Prefix | Should -BeExactly $Prefix
    }

    It 'reads the first line alone' {
        (Read-Description "PROD: Web front end`r`nsecond line").Role | Should -BeExactly 'Web front end'
    }

    It 'makes the role printable ASCII: <Case>' -ForEach @(
        @{ Case = 'a letter loses its accent'; Desc = 'PROD: Caf' + [char]0x00E9 + ' kiosk'; Role = 'Cafe kiosk' }
        @{ Case = 'a blank inside becomes a space'; Desc = "PROD: web`tfront" + [char]0x00A0 + 'end'; Role = 'web front end' }
        @{ Case = 'another character becomes ?'; Desc = 'PROD: ' + [char]0x4E2D + ' web'; Role = '? web' }
        @{ Case = 'a character outside the BMP becomes one ?'; Desc = 'PROD: web ' + [char]::ConvertFromUtf32(0x1F600); Role = 'web ?' }
        @{ Case = 'a control character becomes ?'; Desc = 'PROD: web' + [char]7; Role = 'web?' }
    ) {
        $got = (Read-Description $Desc).Role
        $got | Should -BeExactly $Role
        $got | Should -MatchExactly '^[ -~]*$'
    }
}

Describe 'Resolve-UsaBannerHostConfig' {
    It 'takes both from the AD Description where the configuration leaves them unset' {
        $r = (Resolve-Host -Description 'PROD : Web front end').Resolved
        $r.Tier | Should -BeExactly 'PROD'
        $r.TierFrom | Should -BeExactly 'AD Description'
        $r.Role | Should -BeExactly 'Web front end'
        $r.RoleFrom | Should -BeExactly 'AD Description'
        $r.Config['environment'] | Should -BeExactly 'PROD'
        $r.Config['role'] | Should -BeExactly 'Web front end'
    }

    It 'lets the configuration win, for the tier and the role each: <Case>' -ForEach @(
        @{ Case = 'its tier'; Environment = 'LAB'; Role = ''; Tier = 'LAB'; TierFrom = 'configuration'; Expected = 'Web front end'; RoleFrom = 'AD Description' }
        @{ Case = 'its role'; Environment = 'UNSET'; Role = 'Build agents'; Tier = 'PROD'; TierFrom = 'AD Description'; Expected = 'Build agents'; RoleFrom = 'configuration' }
        @{ Case = 'both'; Environment = 'PUB'; Role = 'Kiosk'; Tier = 'PUB'; TierFrom = 'configuration'; Expected = 'Kiosk'; RoleFrom = 'configuration' }
    ) {
        $r = (Resolve-Host -Environment $Environment -Role $Role -Description 'PROD : Web front end').Resolved
        $r.Tier | Should -BeExactly $Tier
        $r.TierFrom | Should -BeExactly $TierFrom
        $r.Role | Should -BeExactly $Expected
        $r.RoleFrom | Should -BeExactly $RoleFrom
    }

    It 'leaves the tier UNSET and the role empty, from neither, with no Description' {
        $r = (Resolve-Host).Resolved
        $r.Tier | Should -BeExactly 'UNSET'
        $r.TierFrom | Should -BeExactly ''
        $r.Role | Should -BeExactly ''
        $r.RoleFrom | Should -BeExactly ''
    }

    It 'leaves the tier UNSET for a prefix that is no tier, and still takes the role' {
        $r = (Resolve-Host -Description 'QA: test rig').Resolved
        $r.Tier | Should -BeExactly 'UNSET'
        $r.TierFrom | Should -BeExactly ''
        $r.Role | Should -BeExactly 'test rig'
        $r.RoleFrom | Should -BeExactly 'AD Description'
    }

    It 'changes a copy, never the configuration it is given' {
        $both = Resolve-Host -Description 'PROD : Web front end'
        $both.Given['environment'] | Should -BeExactly 'UNSET'
        $both.Given['role'] | Should -BeExactly ''
        [object]::ReferenceEquals($both.Given, $both.Resolved.Config) | Should -BeFalse
    }

    It 'takes a data file''s configuration, which has no role key when an older deploy wrote it' {
        $r = InModuleScope UsaBanner { Resolve-UsaBannerHostConfig -Config @{ version = 1; environment = 'UNSET' } -Description 'LAB: Grafana node' }
        $r.Config['environment'] | Should -BeExactly 'LAB'
        $r.Config['role'] | Should -BeExactly 'Grafana node'
    }
}

Describe 'the cached AD Description' {
    It 'reads <Case>' -ForEach @(
        @{ Case = 'its first line'; Text = "PROD : Web front end`n"; Expected = 'PROD : Web front end' }
        @{ Case = 'an empty Description as empty'; Text = "`n"; Expected = '' }
        @{ Case = 'an empty file as empty'; Text = ''; Expected = '' }
    ) {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        [System.IO.File]::WriteAllText($path, $Text)
        InModuleScope UsaBanner -Parameters @{ Path = $path } { param($Path) Read-UsaBannerAdDescription -Path $Path } | Should -BeExactly $Expected
    }

    It 'is $null where none is cached' {
        $none = InModuleScope UsaBanner -Parameters @{ Path = (Join-Path $TestDrive 'no-such-cache') } { param($Path) Read-UsaBannerAdDescription -Path $Path }
        $null -eq $none | Should -BeTrue
    }
}

Describe 'Update-UsaBannerAdDescription, the Windows periodic job''s read' {
    BeforeEach {
        $script:Cache = Join-Path $TestDrive ([guid]::NewGuid().ToString('n')) 'Banner' 'ad-description'
    }

    It 'caches the Description''s first line, making the folder where it is missing' {
        Mock -ModuleName UsaBanner Get-UsaBannerAdComputerDescription { "PROD : Web front end`r`nsecond line" }
        InModuleScope UsaBanner -Parameters @{ Path = $Cache } { param($Path) Update-UsaBannerAdDescription -Path $Path }
        [System.IO.File]::ReadAllText($Cache) | Should -BeExactly "PROD : Web front end`n"
    }

    It 'caches an empty Description as an empty line, over the one before' {
        $null = New-Item -ItemType Directory -Path (Split-Path $Cache) -Force
        [System.IO.File]::WriteAllText($Cache, "PROD : Web front end`n")
        Mock -ModuleName UsaBanner Get-UsaBannerAdComputerDescription { '' }
        InModuleScope UsaBanner -Parameters @{ Path = $Cache } { param($Path) Update-UsaBannerAdDescription -Path $Path }
        [System.IO.File]::ReadAllText($Cache) | Should -BeExactly "`n"
    }

    It 'keeps the last Description, and warns why, when AD cannot be asked' {
        $null = New-Item -ItemType Directory -Path (Split-Path $Cache) -Force
        [System.IO.File]::WriteAllText($Cache, "PROD : Web front end`n")
        Mock -ModuleName UsaBanner Get-UsaBannerAdComputerDescription { throw 'The specified domain either does not exist or could not be contacted.' }
        $warnings = @(InModuleScope UsaBanner -Parameters @{ Path = $Cache } { param($Path) Update-UsaBannerAdDescription -Path $Path -WarningVariable warned -WarningAction SilentlyContinue; $warned } |
                ForEach-Object { [string]$_ })
        [System.IO.File]::ReadAllText($Cache) | Should -BeExactly "PROD : Web front end`n"
        $warnings | Should -Be @('UsaBanner: the AD Description was not read, so the last one is kept: The specified domain either does not exist or could not be contacted.')
    }
}
