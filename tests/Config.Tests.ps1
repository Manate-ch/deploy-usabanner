# The configuration file: the schema, the defaults, reading and writing.

BeforeAll {
    $moduleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'UsaBanner'
    Import-Module (Join-Path $moduleRoot 'UsaBanner.psd1') -Force
    $defaultsPath = Join-Path $moduleRoot 'config' 'defaults.json'
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the defaults' {
    It 'pass the schema' {
        InModuleScope UsaBanner -Parameters @{ Path = $defaultsPath } { param($Path) Test-UsaBannerConfig -Json (Get-Content -LiteralPath $Path -Raw) } | Should -BeNullOrEmpty
    }

    It 'are written back byte for byte' {
        InModuleScope UsaBanner { ConvertTo-UsaBannerConfigJson -Config (Get-UsaBannerConfigDefault) } | Should -BeExactly (Get-Content -LiteralPath $defaultsPath -Raw)
    }

    It 'set <Key> to <Value>: <Why>' -ForEach @(
        @{ Key = 'art.name'; Value = 'os'; Why = 'our own pictogram in the OS colour' }
        @{ Key = 'border.set'; Value = 'Classic'; Why = 'the box a setup without the walk-through gets' }
        @{ Key = 'legal.template'; Value = 'L3'; Why = 'the business warning' }
        @{ Key = 'preInit.hostName'; Value = $true; Why = 'the console offers it' }
        @{ Key = 'preLogon.hostName'; Value = $false; Why = 'SSH shows it only when the admin opts in' }
        @{ Key = 'preLogon.ip'; Value = $false; Why = 'likewise' }
        @{ Key = 'services'; Value = 'default'; Why = 'the OS''s own list' }
        @{ Key = 'color.mode'; Value = 'auto'; Why = 'the terminal''s signals decide' }
        @{ Key = 'glyphs'; Value = 'auto'; Why = 'the client''s locale decides' }
        @{ Key = 'voice'; Value = 'plain'; Why = 'a meme voice is a deliberate change, never a default' }
    ) {
        $value = InModuleScope UsaBanner { Get-UsaBannerConfigDefault }
        foreach ($part in $Key.Split('.')) { $value = $value[$part] }
        $value | Should -Be $Value
    }
}

Describe 'reading and writing a configuration' {
    It 'round-trips a full configuration byte for byte' {
        $first = Join-Path $TestDrive 'first.json'
        $second = Join-Path $TestDrive 'second.json'
        $legal = InModuleScope UsaBanner -Parameters @{ First = $first; Second = $second } {
            param($First, $Second)
            $config = Get-UsaBannerConfigDefault
            $config['company'] = 'Contoso LLC'
            $config['environment'] = 'PROD'
            $config['legal'] = [ordered]@{ template = 'custom'; text = @('Back\slash, \_/ and "quotes" stay as written.', "It's all ASCII.") }
            $config['vlans'] = @(
                [ordered]@{ name = 'Servers'; tag = 30; cidr = '10.20.30.0/24' }
                [ordered]@{ name = 'Printers'; tag = 20; cidr = '10.20.20.0/24' }
            )
            $config['services'] = @('sshd', 'W32Time')
            Write-UsaBannerConfig -Config $config -Path $First
            Write-UsaBannerConfig -Config (Read-UsaBannerConfig -Path $First) -Path $Second
            (Read-UsaBannerConfig -Path $Second)['legal']['text']
        }
        (Get-FileHash -LiteralPath $second).Hash | Should -Be (Get-FileHash -LiteralPath $first).Hash
        $legal[0] | Should -BeExactly 'Back\slash, \_/ and "quotes" stay as written.'
        [System.IO.File]::ReadAllBytes($first) | Where-Object { $_ -eq 13 } | Should -BeNullOrEmpty
    }

    It 'fills in what a file leaves out from the defaults, key by key' {
        $path = Join-Path $TestDrive 'short.json'
        Set-Content -LiteralPath $path -Value '{"version":1,"company":"Contoso","preLogon":{"ip":true}}'
        $config = InModuleScope UsaBanner -Parameters @{ Path = $path } { param($Path) Read-UsaBannerConfig -Path $Path }
        $config['company'] | Should -BeExactly 'Contoso'
        $config['environment'] | Should -BeExactly 'UNSET'
        $config['preLogon']['ip'] | Should -BeTrue
        $config['preLogon']['hostName'] | Should -BeFalse
        $config['border']['set'] | Should -BeExactly 'Classic'
    }

    It 'takes a host''s own sites in place of the examples, keeps the shipped types, and reads a VLAN''s colour and badge name' {
        $path = Join-Path $TestDrive 'identity.json'
        Set-Content -LiteralPath $path -Value '{"version":1,"naming":{"sites":[{"code":"nw","name":"North Warehouse","color":"Teal"}]},"vlans":[{"name":"Management","tag":10,"cidr":"10.20.10.0/24","color":"Blue","short":"Mgmt"}]}'
        $config = InModuleScope UsaBanner -Parameters @{ Path = $path } { param($Path) Read-UsaBannerConfig -Path $Path }
        @($config['naming']['sites'] | ForEach-Object { $_['name'] }) | Should -BeExactly @('North Warehouse')
        @($config['naming']['types']).Count | Should -Be 7
        $config['vlans'][0]['color'] | Should -BeExactly 'Blue'
        $config['vlans'][0]['short'] | Should -BeExactly 'Mgmt'
    }

    It 'names the problem: <Case>' -ForEach @(
        @{ Case = 'a tier it does not know'; Json = '{"version":1,"environment":"STAGING"}'; Where = '/environment' }
        @{ Case = 'a version it cannot read'; Json = '{"version":2}'; Where = '/version' }
        @{ Case = 'a key it does not know'; Json = '{"version":1,"colour":{"mode":"16"}}'; Where = '/colour'; What = 'not a setting UsaBanner knows' }
        @{ Case = 'a key in the wrong case'; Json = '{"version":1,"preLogon":{"IP":true}}'; Where = '/preLogon/IP'; What = 'not a setting UsaBanner knows' }
        @{ Case = 'a company name that is not ASCII'; Json = '{"version":1,"company":"Caf' + [char]0x00E9 + '"}'; Where = '/company' }
        @{ Case = 'a VLAN tag out of range'; Json = '{"version":1,"vlans":[{"name":"Servers","tag":5000,"cidr":"10.20.30.0/24"}]}'; Where = '/vlans/0/tag' }
        @{ Case = 'services that are neither default nor a list'; Json = '{"version":1,"services":"none"}'; Where = '/services' }
        @{ Case = 'a service name with a space'; Json = '{"version":1,"services":["my service"]}'; Where = '/services/0' }
        @{ Case = 'a OneChar character that is two'; Json = '{"version":1,"border":{"set":"OneChar","char":"ab"}}'; Where = '/border/char' }
        @{ Case = 'legal text that is not ASCII'; Json = '{"version":1,"legal":{"template":"custom","text":["' + [char]0x00A7 + ' 1030"]}}'; Where = '/legal/text/0' }
        @{ Case = 'a voice it does not know'; Json = '{"version":1,"voice":"pirate"}'; Where = '/voice' }
        @{ Case = 'a naming code of two letters where one goes'; Json = '{"version":1,"naming":{"types":[{"code":"vv","name":"Virtual"}]}}'; Where = '/naming/types/0/code' }
        @{ Case = 'a colour it does not know'; Json = '{"version":1,"vlans":[{"name":"Servers","tag":40,"cidr":"10.20.40.0/22","color":"Mauve"}]}'; Where = '/vlans/0/color' }
    ) {
        $path = Join-Path $TestDrive 'bad.json'
        Set-Content -LiteralPath $path -Value $Json
        $message = ''
        try { InModuleScope UsaBanner -Parameters @{ Path = $path } { param($Path) Read-UsaBannerConfig -Path $Path } }
        catch { $message = $_.Exception.Message }
        $message | Should -BeLike '*is not a valid configuration*'
        $message | Should -BeLike "*${Where}: *"
        if ($What) { $message | Should -BeLike "*${Where}: $What*" }
    }

    It 'lists only what is wrong: a tier it does not know, with services <Services>' -ForEach @(
        @{ Services = 'default' }
        @{ Services = @('ssh') }
    ) {
        # Test-Json lists a branch the value did not take as a problem too: with services as a
        # oneOf, a wrong tier came with "/services: Value is "string" but should be "array"".
        $json = InModuleScope UsaBanner -Parameters @{ Services = $Services } {
            param($Services)
            $config = Get-UsaBannerConfigDefault
            $config['environment'] = 'STAGING'
            $config['services'] = $Services
            ConvertTo-UsaBannerConfigJson -Config $config
        }
        $problems = @(InModuleScope UsaBanner -Parameters @{ Json = $json } { param($Json) Test-UsaBannerConfig -Json $Json })
        $problems.Count | Should -Be 1 -Because ($problems -join '; ')
        $problems[0] | Should -BeLike '/environment: *'
    }

    It 'names each problem where it is, under a $ref, in a list or in an object in an object, when Test-Json names only those near the top' {
        # Test-Json as PowerShell 7.6.8's (measured 2026-10-24): false for any problem, and a record only
        # for one at most one step below the part it checks; so whichever PowerShell runs this test.
        Mock -ModuleName UsaBanner Invoke-UsaBannerSchemaCheck {
            $records = @()
            $valid = Test-Json -Json $Json -Schema $Schema -ErrorVariable records -ErrorAction SilentlyContinue
            @{ Valid = [bool]$valid; Errors = @($records | Where-Object { $_.ToString() -match "at '(/[^/']*)?'$" }) }
        }
        $json = '{"version":1,"environment":"STAGING","company":"Caf' + [char]0x00E9 + '","preLogon":{"IP":true},' +
            '"vlans":[{"name":"Servers","tag":5000,"cidr":"10.20.30.0/24"}],"legal":{"template":"custom","text":["ok","' + [char]0x00A7 + ' 1030"]}}'
        $problems = @(InModuleScope UsaBanner -Parameters @{ Json = $json } { param($Json) Test-UsaBannerConfig -Json $Json })
        @($problems | ForEach-Object { ($_ -split ': ')[0] } | Sort-Object) | Should -Be @('/company', '/environment', '/legal/text/1', '/preLogon/IP', '/vlans/0/tag') -Because ($problems -join '; ')
        $problems | Should -Contain '/preLogon/IP: not a setting UsaBanner knows'
    }

    It 'refuses a configuration Test-Json calls not valid, even when it names no problem at all' {
        Mock -ModuleName UsaBanner Invoke-UsaBannerSchemaCheck { @{ Valid = $false; Errors = @() } }
        $path = Join-Path $TestDrive 'unnamed.json'
        Set-Content -LiteralPath $path -Value '{"version":1,"company":"Contoso"}'
        $message = ''
        try { InModuleScope UsaBanner -Parameters @{ Path = $path } { param($Path) Read-UsaBannerConfig -Path $Path } }
        catch { $message = $_.Exception.Message }
        $message | Should -BeLike '*is not a valid configuration*'
        $message | Should -BeLike '*/company: not valid against the schema, though Test-Json does not say why*'
    }

    It 'writes nothing when the configuration is not valid' {
        $path = Join-Path $TestDrive 'keep.json'
        Set-Content -LiteralPath $path -Value 'the old file' -NoNewline
        {
            InModuleScope UsaBanner -Parameters @{ Path = $path } {
                param($Path)
                $config = Get-UsaBannerConfigDefault
                $config['environment'] = 'STAGING'
                Write-UsaBannerConfig -Config $config -Path $Path
            }
        } | Should -Throw '*not writing*the configuration is not valid*/environment*'
        Get-Content -LiteralPath $path -Raw | Should -BeExactly 'the old file'
        Test-Path -LiteralPath "$path.tmp" | Should -BeFalse
    }

    It 'says when a file is not JSON' {
        $path = Join-Path $TestDrive 'broken.json'
        Set-Content -LiteralPath $path -Value '{"version": 1,'
        { InModuleScope UsaBanner -Parameters @{ Path = $path } { param($Path) Read-UsaBannerConfig -Path $Path } } | Should -Throw '*is not JSON*'
    }

    It 'takes a relative path from PowerShell''s location' {
        Push-Location -LiteralPath $TestDrive
        try { InModuleScope UsaBanner { Write-UsaBannerConfig -Config (Get-UsaBannerConfigDefault) -Path 'relative.json' } }
        finally { Pop-Location }
        Test-Path -LiteralPath (Join-Path $TestDrive 'relative.json') -PathType Leaf | Should -BeTrue
    }
}
