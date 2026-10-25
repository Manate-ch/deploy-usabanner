# The configuration a deploy builds from its flags, the VLAN file it reads,
# and the report of what a deploy changes (UsaBanner/Private/DeployConfig.ps1).

BeforeAll {
    $moduleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'UsaBanner'
    Import-Module (Join-Path $moduleRoot 'UsaBanner.psd1') -Force
    $defaultsPath = Join-Path $moduleRoot 'config' 'defaults.json'

    function New-DeployConfig {
        # In:  the flags, and a configuration file to start from, or none
        # Out: the configuration New-UsaBannerDeployConfig builds
        param([hashtable]$Flags = @{}, [string]$Path)
        InModuleScope UsaBanner -Parameters @{ Flags = $Flags; Path = $Path } {
            param($Flags, $Path)
            if ($Path) { New-UsaBannerDeployConfig -Flags $Flags -Path $Path } else { New-UsaBannerDeployConfig -Flags $Flags }
        }
    }

    function Get-Setting {
        # In:  a configuration and a setting's path, such as border.set
        # Out: the setting's value, a list kept whole
        param([System.Collections.IDictionary]$Config, [string]$Setting)
        $value = $Config
        foreach ($part in $Setting.Split('.')) { $value = $value[$part] }
        , $value
    }

    function Get-Failure {
        # In:  a script block
        # Out: the message it throws, or '' when it throws none
        param([scriptblock]$Script)
        try { $null = & $Script; '' } catch { $_.Exception.Message }
    }

    function New-TextFile {
        # In:  a file name and its text
        # Out: the path of the file, written in TestDrive
        param([string]$Name, [string]$Text)
        $path = Join-Path $TestDrive $Name
        [System.IO.File]::WriteAllText($path, $Text)
        $path
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the configuration a deploy builds' {
    It 'is the defaults when no flag is given' {
        $config = New-DeployConfig
        InModuleScope UsaBanner -Parameters @{ Config = $config } { param($Config) ConvertTo-UsaBannerConfigJson -Config $Config } |
            Should -BeExactly (Get-Content -LiteralPath $defaultsPath -Raw)
    }

    It 'sets <Setting> from -<Flag>' -ForEach @(
        @{ Flag = 'Company'; Given = 'Contoso LLC'; Setting = 'company' }
        @{ Flag = 'Environment'; Given = 'PROD'; Setting = 'environment' }
        @{ Flag = 'BannerImage'; Given = 'tux'; Setting = 'art.name' }
        @{ Flag = 'Border'; Given = 'Rounded'; Setting = 'border.set' }
        @{ Flag = 'BorderChar'; Given = '*'; Setting = 'border.char' }
        @{ Flag = 'BorderCap'; Given = '(^_^)'; Setting = 'border.cap' }
        @{ Flag = 'ColorPreset'; Given = 'HighContrast'; Setting = 'color.preset' }
        @{ Flag = 'ColorMode'; Given = '16'; Setting = 'color.mode' }
        @{ Flag = 'Glyphs'; Given = 'unicode'; Setting = 'glyphs' }
        @{ Flag = 'Legal'; Given = 'L5'; Setting = 'legal.template' }
        @{ Flag = 'Voice'; Given = 'uwu'; Setting = 'voice' }
    ) {
        Get-Setting (New-DeployConfig @{ $Flag = $Given }) $Setting | Should -BeExactly $Given
    }

    It 'spells a value from a list as the schema does: -<Flag> <Given> sets <Expected>' -ForEach @(
        @{ Flag = 'Environment'; Given = 'prod'; Setting = 'environment'; Expected = 'PROD' }
        @{ Flag = 'Border'; Given = 'rounded'; Setting = 'border.set'; Expected = 'Rounded' }
        @{ Flag = 'ColorPreset'; Given = 'highcontrast'; Setting = 'color.preset'; Expected = 'HighContrast' }
        @{ Flag = 'ColorMode'; Given = 'TrueColor'; Setting = 'color.mode'; Expected = 'truecolor' }
        @{ Flag = 'Glyphs'; Given = 'ASCII'; Setting = 'glyphs'; Expected = 'ascii' }
        @{ Flag = 'Legal'; Given = 'l5'; Setting = 'legal.template'; Expected = 'L5' }
        @{ Flag = 'Voice'; Given = 'UwU'; Setting = 'voice'; Expected = 'uwu' }
        @{ Flag = 'BannerImage'; Given = 'Tux'; Setting = 'art.name'; Expected = 'tux' }
    ) {
        Get-Setting (New-DeployConfig @{ $Flag = $Given }) $Setting | Should -BeExactly $Expected
    }

    It 'starts from a file, and the flags change only their own settings' {
        $path = New-TextFile 'site.json' '{"version":1,"company":"Contoso","environment":"LAB","voice":"leet","vlans":[{"name":"Servers","tag":40,"cidr":"10.20.40.0/22"}]}'
        $config = New-DeployConfig @{ Environment = 'PROD' } -Path $path
        $config['environment'] | Should -BeExactly 'PROD'
        $config['company'] | Should -BeExactly 'Contoso'
        $config['voice'] | Should -BeExactly 'leet'
        @($config['vlans']).Count | Should -Be 1
        $config['border']['set'] | Should -BeExactly 'Classic'
    }

    It '-<Flag> <Given> shows the host name: <Name>, and the IP: <Ip>' -ForEach @(
        foreach ($flag in 'PreInit', 'PreLogon') {
            @{ Flag = $flag; Given = @('HostName'); Name = $true; Ip = $false }
            @{ Flag = $flag; Given = @('Ip'); Name = $false; Ip = $true }
            @{ Flag = $flag; Given = @('HostName', 'Ip'); Name = $true; Ip = $true }
            @{ Flag = $flag; Given = @('hostname'); Name = $true; Ip = $false }
            @{ Flag = $flag; Given = @('None'); Name = $false; Ip = $false }
        }
    ) {
        $section = $Flag.Substring(0, 1).ToLowerInvariant() + $Flag.Substring(1)
        $config = New-DeployConfig @{ $Flag = $Given }
        $config[$section]['hostName'] | Should -Be $Name
        $config[$section]['ip'] | Should -Be $Ip
    }

    It 'refuses None with anything else' {
        Get-Failure { New-DeployConfig @{ PreLogon = @('None', 'Ip') } } | Should -BeLike '*-PreLogon None shows nothing, so it goes alone, not with Ip*'
    }

    It 'takes -LegalText as the admin''s own text, and the template becomes custom' {
        $config = New-DeployConfig @{ LegalText = @('PRIVATE: Contoso staff only.', '', 'Ask the help desk for access.') }
        $config['legal']['template'] | Should -BeExactly 'custom'
        $config['legal']['text'] | Should -BeExactly @('PRIVATE: Contoso staff only.', '', 'Ask the help desk for access.')
    }

    It 'takes -Legal custom with -LegalText' {
        (New-DeployConfig @{ Legal = 'custom'; LegalText = @('Contoso staff only.') })['legal']['template'] | Should -BeExactly 'custom'
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = '-LegalText with a template'; Flags = @{ Legal = 'L3'; LegalText = @('Contoso staff only.') }; Message = '*-LegalText is your own legal text, and -Legal L3 is a template: give one of them*' }
        @{ Case = '-LegalText without text'; Flags = @{ LegalText = @('', '  ') }; Message = '*-LegalText holds no text*' }
        @{ Case = 'a custom template without text'; Flags = @{ Legal = 'custom' }; Message = '*the legal template is custom, but there is no text for it*' }
        @{ Case = 'default with names'; Flags = @{ Services = @('default', 'ssh') }; Message = '*-Services default watches the OS''s own list, so it goes alone, not with ssh*' }
        @{ Case = 'a flag it does not have'; Flags = @{ Colour = 'x' }; Message = '*Deploy-UsaBanner has no setting called ''Colour''*' }
        @{ Case = 'art the module does not have, naming what there is'; Flags = @{ BannerImage = 'minecraft' }; Message = '*there is no art called ''minecraft''. There is: os, *rabbit*' }
    ) {
        Get-Failure { New-DeployConfig $Flags } | Should -BeLike $Message
    }

    It 'takes -Services <Given> as <Expected>' -ForEach @(
        @{ Given = @('ssh', 'postgresql'); Expected = @('ssh', 'postgresql') }
        @{ Given = @('zabbix-agent2'); Expected = @('zabbix-agent2') }
        @{ Given = @('default'); Expected = 'default' }
    ) {
        $services = Get-Setting (New-DeployConfig @{ Services = $Given }) 'services'
        if ($Expected -is [array]) { @($services) | Should -BeExactly $Expected; $services -is [array] | Should -BeTrue }
        else { $services | Should -BeExactly $Expected }
    }

    It 'names the flag of a value the schema refuses: <Case>' -ForEach @(
        @{ Case = 'a company name that is not ASCII'; Flags = @{ Company = 'Caf' + [char]0x00E9 }; Message = '*-Company: /company: *' }
        @{ Case = 'a OneChar character that is two'; Flags = @{ BorderChar = 'ab' }; Message = '*-BorderChar: /border/char: *' }
        @{ Case = 'a cap too long for the top line'; Flags = @{ BorderCap = '(^_^) (^_^) (^_^)' }; Message = '*-BorderCap: /border/cap: *' }
        @{ Case = 'a service name with a space'; Flags = @{ Services = @('my service') }; Message = '*-Services: /services*' }
        @{ Case = 'legal text that is not ASCII'; Flags = @{ LegalText = @([char]0x00A7 + ' 1030') }; Message = '*-LegalText: /legal/text/0: *' }
    ) {
        $got = Get-Failure { New-DeployConfig $Flags }
        $got | Should -BeLike '*these settings are not valid*'
        $got | Should -BeLike $Message
    }

    It 'maps every flag to a setting the schema has' {
        $settings = InModuleScope UsaBanner { @($script:UsaDeployFlags.Values) }
        $schema = Get-Content -LiteralPath (Join-Path $moduleRoot 'config' 'usabanner.schema.json') -Raw | ConvertFrom-Json -AsHashtable
        foreach ($setting in $settings) {
            $node = $schema
            foreach ($part in $setting.Split('.')) {
                $node['properties'].Keys | Should -Contain $part -Because "the flag for $setting sets it"
                $node = $node['properties'][$part]
            }
        }
        $settings.Count | Should -Be 18
    }

    It 'turns the update channel on with -Update and the address of the releases with -UpdateSource' {
        $config = New-DeployConfig @{ Update = 'Notify'; UpdateSource = 'https://releases.example.com/usabanner' }
        Get-Setting $config 'update.mode' | Should -BeExactly 'notify'
        Get-Setting $config 'update.source' | Should -BeExactly 'https://releases.example.com/usabanner'
    }

    It 'leaves the update channel off unless a flag turns it on' {
        Get-Setting (New-DeployConfig @{ Company = 'Contoso' }) 'update.mode' | Should -BeExactly 'off'
    }

    It 'refuses an update channel turned on with no source to look at' {
        Get-Failure { New-DeployConfig @{ Update = 'install' } } | Should -BeLike '*the update channel is set to install, with no source to look at: give -UpdateSource*'
    }

    It 'refuses a source that is not https, naming the flag' {
        Get-Failure { New-DeployConfig @{ Update = 'notify'; UpdateSource = 'http://releases.example.com/usabanner' } } | Should -BeLike '*-UpdateSource: /update/source: *'
    }
}

Describe 'a VLAN file' {
    It 'reads a CSV file: name, tag and cidr, with color and short where a row gives them' {
        $path = New-TextFile 'vlans.csv' "name,tag,cidr,color,short`nManagement,10,10.20.10.0/24,Blue,Mgmt`nServers,40,10.20.40.0/22,,`n`"Apps, internal`",60,10.20.60.0/24,Brown,Apps`n"
        $rows = @(New-DeployConfig @{ VlanFile = $path })[0]['vlans']
        @($rows).Count | Should -Be 3
        $rows[0] | ConvertTo-Json -Compress | Should -BeExactly '{"name":"Management","tag":10,"cidr":"10.20.10.0/24","color":"Blue","short":"Mgmt"}'
        $rows[1] | ConvertTo-Json -Compress | Should -BeExactly '{"name":"Servers","tag":40,"cidr":"10.20.40.0/22"}'
        $rows[2]['name'] | Should -BeExactly 'Apps, internal'
    }

    It 'reads a TSV file, its columns in any order and any case' {
        $path = New-TextFile 'vlans.tsv' "CIDR`tName`tTag`n10.20.30.0/24`tServers`t30`n"
        $rows = (New-DeployConfig @{ VlanFile = $path })['vlans']
        $rows[0] | ConvertTo-Json -Compress | Should -BeExactly '{"name":"Servers","tag":30,"cidr":"10.20.30.0/24"}'
    }

    It 'drops the spaces a hand-written file has around its fields' {
        $path = New-TextFile 'spaced.csv' "name, tag, cidr`nServers, 30, 10.20.30.0/24`n"
        $rows = (New-DeployConfig @{ VlanFile = $path })['vlans']
        $rows[0] | ConvertTo-Json -Compress | Should -BeExactly '{"name":"Servers","tag":30,"cidr":"10.20.30.0/24"}'
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = 'a file with no rows'; Text = "name,tag,cidr`n"; Message = '*holds no VLANs*' }
        @{ Case = 'a file without a cidr column'; Text = "name,tag`nServers,30`n"; Message = '*has no cidr column*' }
        @{ Case = 'a column it does not know'; Text = "name,tag,cidr,vlan`nServers,30,10.20.30.0/24,30`n"; Message = '*has a column UsaBanner does not know: vlan*' }
        @{ Case = 'a tag that is not a whole number'; Text = "name,tag,cidr`nServers,30,10.20.30.0/24`nPrinters,thirty,10.20.20.0/24`n"; Message = '*line 3: the tag ''thirty'' is not a whole number*' }
    ) {
        $path = New-TextFile 'bad.csv' $Text
        Get-Failure { New-DeployConfig @{ VlanFile = $path } } | Should -BeLike $Message
    }

    It 'refuses a file that is not there' {
        Get-Failure { New-DeployConfig @{ VlanFile = (Join-Path $TestDrive 'missing.csv') } } | Should -BeLike '*there is no VLAN file at*missing.csv*'
    }

    It 'leaves the rest to the schema, which names the row and the flag' {
        $path = New-TextFile 'range.csv' "name,tag,cidr`nServers,5000,10.20.30.0/24`n"
        Get-Failure { New-DeployConfig @{ VlanFile = $path } } | Should -BeLike '*-VlanFile: /vlans/0/tag: *'
    }
}

Describe 'what a deploy changes' {
    BeforeAll {
        function Compare-Config {
            # In:  the configuration a host holds, and the one replacing it
            # Out: Compare-UsaBannerConfig's lines
            param($Old, $New)
            @(InModuleScope UsaBanner -Parameters @{ Old = $Old; New = $New } { param($Old, $New) Compare-UsaBannerConfig -Old $Old -New $New })
        }
    }

    It 'is nothing for the same configuration' {
        Compare-Config (New-DeployConfig @{ Company = 'Contoso' }) (New-DeployConfig @{ Company = 'Contoso' }) | Should -BeNullOrEmpty
    }

    It 'names each setting that changes, in the new configuration''s order' {
        $lines = Compare-Config (New-DeployConfig @{ Environment = 'LAB' }) (New-DeployConfig @{ Environment = 'PROD'; Border = 'Rounded' })
        $lines | Should -BeExactly @('environment: "LAB" -> "PROD"', 'border.set: "Classic" -> "Rounded"')
    }

    It 'shows a long list by its length, and a short one as it is' {
        $path = New-TextFile 'three.csv' "name,tag,cidr`nManagement,10,10.20.10.0/24`nServers,40,10.20.40.0/22`nApps,60,10.20.60.0/24`n"
        Compare-Config (New-DeployConfig) (New-DeployConfig @{ VlanFile = $path }) | Should -BeExactly 'vlans: [] -> 3 entries'
        Compare-Config (New-DeployConfig) (New-DeployConfig @{ Services = @('ssh') }) | Should -BeExactly 'services: "default" -> ["ssh"]'
    }

    It 'shows a setting only one side has as (none)' {
        Compare-Config (New-DeployConfig) (New-DeployConfig @{ BorderCap = '(^_^)' }) | Should -BeExactly 'border.cap: (none) -> "(^_^)"'
        Compare-Config (New-DeployConfig @{ BorderCap = '(^_^)' }) (New-DeployConfig) | Should -BeExactly 'border.cap: "(^_^)" -> (none)'
    }

    It 'gives only the new values with -NewOnly: what a host sets otherwise than the defaults, for Get-UsaBanner' {
        $lines = @(InModuleScope UsaBanner {
                Compare-UsaBannerConfig -Old (Get-UsaBannerConfigDefault) -New (New-UsaBannerDeployConfig -Flags @{ Company = 'Contoso'; Border = 'Rounded'; Services = @('ssh') }) -NewOnly
            })
        $lines | Should -BeExactly @('company: "Contoso"', 'border.set: "Rounded"', 'services: ["ssh"]')
    }
}
