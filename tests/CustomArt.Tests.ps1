# Art of a configuration's own, art.custom, which Deploy-UsaBanner -ArtPath
# puts there, and the logo of the OS a host runs, art.name os-logo
# (UsaBanner/Private/Art.ps1, docs/DECISIONS.md D31).

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force

    function New-Art {
        # In:  nothing
        # Out: a small piece of art as New-UsaBannerArt -OutFile saves one, with a
        #      gradient across, and a sheen whose numbers have fractions
        # Why: each test starts from art that keeps every rule, and changes one thing
        [ordered]@{
            title   = 'Contoso'
            artist  = 'Contoso design'
            licence = 'All rights reserved'
            source  = 'drawn by hand for these tests'
            art     = @('C0NT0S0', '=======')
            mask    = @('aaaaaaa', 'bbbbbbb')
            palette = [ordered]@{
                a = [ordered]@{ rgb = '#3366FF'; basic = 'bright-blue' }
                b = [ordered]@{ from = '#FF8800'; to = '#FFDD00'; across = $true; sheen = $true; basic = 'yellow' }
            }
            sheen   = [ordered]@{ peak = 1.15; drop = 0.3; regions = @([ordered]@{ rows = @(0, 1); cols = @(0, 6); middle = 3; half = 3.5 }) }
        }
    }

    function Save-Art {
        # In:  art, as a dictionary or as JSON text, and a file name
        # Out: the path of the art saved in TestDrive, as -OutFile writes it
        param($Art, [string]$Name = 'contoso-logo.json')
        $path = Join-Path $TestDrive $Name
        $text = if ($Art -is [string]) { $Art } else { ConvertTo-Json -InputObject $Art -Depth 10 }
        [System.IO.File]::WriteAllText($path, $text)
        $path
    }

    function Get-CaseArtJson {
        # In:  nothing
        # Out: art whose two classes are a and A, as JSON text
        # Why: a PowerShell hashtable cannot hold both keys; JSON read with -AsHashtable can
        '{"title":"Contoso","artist":"Contoso design","licence":"All rights reserved","source":"by hand",' +
        '"art":["C0NT0S0","======="],"mask":["aaaaaaa","AAAAAAA"],' +
        '"palette":{"a":{"rgb":"#3366FF","basic":"bright-blue"},"A":{"rgb":"#FF8800","basic":"yellow"}}}'
    }

    function New-DeployConfig {
        # In:  the flags, and a configuration file to start from, or none
        # Out: the configuration New-UsaBannerDeployConfig builds
        param([hashtable]$Flags = @{}, [string]$Path)
        InModuleScope UsaBanner -Parameters @{ Flags = $Flags; Path = $Path } {
            param($Flags, $Path)
            if ($Path) { New-UsaBannerDeployConfig -Flags $Flags -Path $Path } else { New-UsaBannerDeployConfig -Flags $Flags }
        }
    }

    function Get-Failure {
        # In:  a script block
        # Out: the message it throws, or '' when it throws none
        param([scriptblock]$Script)
        try { $null = & $Script; '' } catch { $_.Exception.Message }
    }

    function Get-ConfiguredArt {
        # In:  the art setting, and the OS
        # Out: the art Get-UsaBannerConfiguredArt gives
        param([System.Collections.IDictionary]$Setting, [string]$Os = 'ubuntu')
        InModuleScope UsaBanner -Parameters @{ Setting = $Setting; Os = $Os } { param($Setting, $Os) Get-UsaBannerConfiguredArt -Setting $Setting -Os $Os }
    }

    function Get-Banner {
        # In:  the moment (logon: the SSH banner; post: the banner after login), the
        #      art setting, and the OS
        # Out: the banner's lines for Contoso's made-up host, in no colour
        param([string]$Moment, [System.Collections.IDictionary]$Art, [string]$Os = 'ubuntu')
        InModuleScope UsaBanner -Parameters @{ Moment = $Moment; Art = $Art; Os = $Os } {
            param($Moment, $Art, $Os)
            $config = Get-UsaBannerConfigDefault
            $config['company'] = 'Contoso'
            $config['art'] = $Art
            if ($Moment -eq 'logon') { return @(Get-UsaBannerPreLogon -Config $config -Os $Os -Facts @{ HostName = 'h-vsl-web1'; Ip = '10.20.40.80' }) }
            $facts = @{
                Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80'
                Os = 'Ubuntu 24.04.3 LTS, kernel 6.8.0-87-generic'; Role = 'Web front end'; Uptime = '12d 6h 40m'
                Cpu = @{ Now = 12; Min = 3; Max = 71; Text = '4 cores @ 2.4 GHz' }
                Memory = @{ Pct = 57; Min = 48; Max = 66; Text = '4.5 of 7.8 GiB'; Kind = 'DDR4' }
                Disks = @(@{ Name = '/'; Pct = 38; Min = 38; Max = 39; Text = '11 of 29 GiB'; Kind = 'SSD' })
                Sessions = '2  (admin)'; Time = 'Tue 2026-10-20 09:30 CDT'
                Ipv4 = @(@{ Name = 'ens160'; Address = '10.20.40.80/22' })
                Updates = @{ Text = 'none pending'; Level = 'good' }
                Reboot = @{ Text = 'none pending, none scheduled'; Level = 'good' }
                Services = @{ Text = 'ssh, cron, systemd-timesyncd active'; Level = 'good' }
                Problems = @()
                Checked = @('services', 'disks <85%', 'memory', 'ssh', 'clock', 'reboot')
            }
            @(Get-UsaBannerPostLogon -Config $config -Os $Os -Facts $facts -Mode 'none')
        }
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the art a configuration draws' {
    It 'is the configuration''s own art when it holds one, whatever art.name says' {
        $drawn = Get-ConfiguredArt -Setting ([ordered]@{ name = 'rabbit'; custom = (New-Art) })
        $drawn['title'] | Should -BeExactly 'Contoso'
        $drawn['art'] -join "`n" | Should -BeExactly "C0NT0S0`n======="
    }

    It 'is the server pictogram for os' {
        (Get-ConfiguredArt -Setting @{ name = 'os' })['title'] | Should -BeExactly (InModuleScope UsaBanner { Get-UsaBannerArtData -Name 'server' })['title']
    }

    It 'is the <Logo> logo for os-logo on <Os>' -ForEach @(
        @{ Os = 'windows'; Logo = 'windows' }
        @{ Os = 'ubuntu'; Logo = 'ubuntu' }
        @{ Os = 'linux'; Logo = 'tux' }
    ) {
        $want = InModuleScope UsaBanner -Parameters @{ Logo = $Logo } { param($Logo) Get-UsaBannerArtData -Name $Logo }
        $drawn = Get-ConfiguredArt -Setting @{ name = 'os-logo' } -Os $Os
        $drawn['title'] | Should -BeExactly $want['title']
        $drawn['art'] -join "`n" | Should -BeExactly ($want['art'] -join "`n")
    }

    It 'refuses the configuration''s own art when it breaks a rule, naming the rule' {
        $art = New-Art
        $art['art'] = @("C0NT0S$([char]0xE9)", '=======')
        Get-Failure { Get-ConfiguredArt -Setting @{ name = 'os'; custom = $art } } | Should -BeLike '*own art (art.custom) breaks the art rules*art row 0: printable ASCII only*'
    }
}

Describe 'the rules for a configuration''s own art' {
    It 'find nothing wrong with sound art' {
        InModuleScope UsaBanner -Parameters @{ Art = (New-Art) } { param($Art) Test-UsaBannerCustomArt -Art $Art } | Should -BeNullOrEmpty
    }

    It 'refuse two classes that differ only in case, which a Windows data file cannot hold apart' {
        $art = Get-CaseArtJson | ConvertFrom-Json -AsHashtable
        $problems = @(InModuleScope UsaBanner -Parameters @{ Art = $art } { param($Art) Test-UsaBannerCustomArt -Art $Art })
        $problems | Should -HaveCount 1
        $problems[0] | Should -BeLike "palette: classes 'a' and 'A' differ only in case*"
    }

    It 'refuse what is not art at all' {
        InModuleScope UsaBanner { Test-UsaBannerCustomArt -Art 'contoso-logo.png' } | Should -BeLike 'not art*'
    }

    It 'are the rules of the module''s own art too' {
        $art = New-Art
        $art.Remove('title')
        InModuleScope UsaBanner -Parameters @{ Art = $art } { param($Art) Test-UsaBannerCustomArt -Art $Art } | Should -BeLike 'title: missing*'
    }
}

Describe 'Deploy-UsaBanner -ArtPath' {
    It 'puts the file''s art in art.custom as it is, and leaves art.name' {
        $config = New-DeployConfig @{ ArtPath = (Save-Art (New-Art)) }
        $config['art']['custom']['title'] | Should -BeExactly 'Contoso'
        $config['art']['custom']['art'] -join "`n" | Should -BeExactly "C0NT0S0`n======="
        $config['art']['custom']['sheen']['peak'] | Should -Be 1.15
        $config['art']['name'] | Should -BeExactly 'os'
    }

    It 'is a flag of Deploy-UsaBanner and of Deploy-UsaBannerGPO alike' {
        (Get-Command Deploy-UsaBanner).Parameters.ContainsKey('ArtPath') | Should -BeTrue
        (Get-Command Deploy-UsaBannerGPO).Parameters.ContainsKey('ArtPath') | Should -BeTrue
    }

    It 'refuses an image, saying how to make art of it' {
        $png = Join-Path $TestDrive 'contoso-logo.png'
        [System.IO.File]::WriteAllBytes($png, [byte[]](137, 80, 78, 71))
        Get-Failure { New-DeployConfig @{ ArtPath = $png } } | Should -BeLike '*-ArtPath takes art as New-UsaBannerArt -OutFile saves it, a .json file*New-UsaBannerArt -Path*'
    }

    It 'refuses -BannerImage beside it' {
        Get-Failure { New-DeployConfig @{ BannerImage = 'rabbit'; ArtPath = (Save-Art (New-Art)) } } | Should -BeLike '*-BannerImage names a piece of the module''s art, and -ArtPath brings art of your own: give one of them*'
    }

    It 'refuses art that breaks a rule, naming the file and the rule' {
        $art = New-Art
        $art.Remove('licence')
        Get-Failure { New-DeployConfig @{ ArtPath = (Save-Art $art) } } | Should -BeLike '*contoso-logo.json breaks the art rules*licence: missing*'
    }

    It 'refuses classes that differ only in case, naming the flag' {
        Get-Failure { New-DeployConfig @{ ArtPath = (Save-Art (Get-CaseArtJson)) } } | Should -BeLike "*-ArtPath: /art/custom: palette: classes 'a' and 'A' differ only in case*"
    }

    It 'refuses a file that is not there' {
        Get-Failure { New-DeployConfig @{ ArtPath = (Join-Path $TestDrive 'none.json') } } | Should -BeLike '*there is no file at*none.json*'
    }
}

Describe '-BannerImage, beside art of a configuration''s own' {
    It 'takes os-logo' {
        (New-DeployConfig @{ BannerImage = 'os-logo' })['art']['name'] | Should -BeExactly 'os-logo'
    }

    It 'drops the art a -Path file held, as it names the art to draw' {
        $file = Join-Path $TestDrive 'site.json'
        [System.IO.File]::WriteAllText($file, (ConvertTo-Json -InputObject ([ordered]@{ company = 'Contoso'; art = [ordered]@{ custom = (New-Art) } }) -Depth 10))
        (New-DeployConfig -Path $file)['art'].Contains('custom') | Should -BeTrue
        $config = New-DeployConfig @{ BannerImage = 'rabbit' } -Path $file
        $config['art'].Contains('custom') | Should -BeFalse
        $config['art']['name'] | Should -BeExactly 'rabbit'
    }
}

Describe 'a configuration with art of its own' {
    BeforeAll {
        $config = InModuleScope UsaBanner -Parameters @{ Art = (New-Art) } {
            param($Art)
            $config = Get-UsaBannerConfigDefault
            $config['art']['custom'] = $Art
            $config
        }
    }

    It 'passes the schema and the art rules' {
        InModuleScope UsaBanner -Parameters @{ Config = $config } { param($Config) Test-UsaBannerConfig -Json (ConvertTo-UsaBannerConfigJson -Config $Config) } | Should -BeNullOrEmpty
    }

    It 'has each art rule it breaks named at /art/custom' {
        $json = (InModuleScope UsaBanner -Parameters @{ Config = $config } { param($Config) ConvertTo-UsaBannerConfigJson -Config $Config }).Replace('"bright-blue"', '"navy"')
        @(InModuleScope UsaBanner -Parameters @{ Json = $json } { param($Json) Test-UsaBannerConfig -Json $Json }) | Should -BeLike "/art/custom: palette 'a'.basic: one of *"
    }

    It 'is refused by the schema when art.custom is not an object' {
        @(InModuleScope UsaBanner { Test-UsaBannerConfig -Json '{"art":{"custom":"contoso-logo.png"}}' }) -join "`n" | Should -BeLike '*/art/custom*'
    }

    It 'comes back from the Windows data file as art that keeps the rules, its fractions numbers still' {
        $text = InModuleScope UsaBanner -Parameters @{ Config = $config } { param($Config) ConvertTo-UsaBannerDataFile -Config $Config }
        $file = Join-Path $TestDrive 'usabanner.psd1'
        [System.IO.File]::WriteAllText($file, $text)
        $back = Import-PowerShellDataFile -LiteralPath $file
        $back['art']['custom']['sheen']['peak'] | Should -BeOfType [double]
        $back['art']['custom']['sheen']['peak'] | Should -Be 1.15
        $back['art']['custom']['sheen']['regions'][0]['half'] | Should -Be 3.5
        InModuleScope UsaBanner -Parameters @{ Art = $back['art']['custom'] } { param($Art) Test-UsaBannerCustomArt -Art $Art } | Should -BeNullOrEmpty
    }

    It 'is one setting in what a deploy reports, by its title and size' {
        $lines = @(InModuleScope UsaBanner -Parameters @{ Config = $config } { param($Config) Compare-UsaBannerConfig -Old (Get-UsaBannerConfigDefault) -New $Config })
        $lines | Should -HaveCount 1
        $lines[0] | Should -BeExactly 'art.custom: (none) -> "Contoso", 7 x 2'
    }
}

Describe 'the banners with art of their own' {
    It 'draws it in the SSH banner, printable ASCII within 64 columns' {
        $lines = Get-Banner -Moment logon -Art ([ordered]@{ name = 'os'; custom = (New-Art) })
        $lines -join "`n" | Should -Match 'C0NT0S0'
        foreach ($line in $lines) {
            $line | Should -MatchExactly '^[ -~]*$'
            $line.Length | Should -BeLessOrEqual 64 -Because $line
        }
    }

    It 'draws it in the banner after login' {
        Get-Banner -Moment post -Art ([ordered]@{ name = 'os'; custom = (New-Art) }) | Out-String | Should -Match 'C0NT0S0'
    }

    It 'draws the <Logo> logo for os-logo on <Os>, as naming it would' -ForEach @(
        @{ Os = 'windows'; Logo = 'windows' }
        @{ Os = 'ubuntu'; Logo = 'ubuntu' }
        @{ Os = 'linux'; Logo = 'tux' }
    ) {
        $byLogo = Get-Banner -Moment logon -Art @{ name = 'os-logo' } -Os $Os
        $byName = Get-Banner -Moment logon -Art @{ name = $Logo } -Os $Os
        $byLogo -join "`n" | Should -BeExactly ($byName -join "`n")
    }
}
