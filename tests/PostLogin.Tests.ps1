# The banner after login (UsaBanner/Private/PostLogin.ps1, docs/DECISIONS.md
# D5 and D7): the art, the welcome line, the tier strip, the host panel and
# the health lines, for made-up hosts in made-up Contoso VLANs. Whole frames
# are checked against tests/frames (Golden.ps1).

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $schema = Get-Content -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'config' 'usabanner.schema.json') -Raw | ConvertFrom-Json -AsHashtable
    $setCases = @(foreach ($set in $schema['properties']['border']['properties']['set']['enum']) { @{ Set = $set } })
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'Golden.ps1')
    $esc = [string][char]27

    function Get-Facts {
        # In:  a made-up host: web (Ubuntu), app (Windows) or db (other Linux);
        #      -Problems for the same host with some
        # Out: its facts, in the shape of the table in PostLogin.ps1
        # Why: each test names the host it draws, and changes only that
        param([string]$Kind, [switch]$Problems)
        $bad = [bool]$Problems
        switch ($Kind) {
            'web' {
                @{
                    Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80'
                    Os = 'Ubuntu 24.04.3 LTS, kernel 6.8.0-87-generic'; Role = 'Web front end'; Uptime = '12d 6h 40m'
                    Cpu = @{ Now = 12; Min = 3; Max = 71; Text = '4 cores @ 2.4 GHz' }
                    Memory = @{ Pct = 57; Min = 48; Max = 66; Text = '4.5 of 7.8 GiB'; Kind = 'DDR4' }
                    Disks = @(
                        @{ Name = '/'; Pct = 38; Min = 38; Max = 39; Text = '11 of 29 GiB'; Kind = 'SSD' }
                        @{ Name = '/var'; Pct = $(if ($bad) { 88 } else { 52 }); Min = $(if ($bad) { 80 } else { 51 }); Max = $(if ($bad) { 88 } else { 53 }); Text = $(if ($bad) { '35 of 40 GiB' } else { '21 of 40 GiB' }); Kind = 'SSD' }
                    )
                    Sessions = '2  (admin)'; Time = 'Tue 2026-10-20 09:30 CDT'
                    Ipv4 = @(@{ Name = 'ens160'; Address = '10.20.40.80/22' })
                    Updates = $(if ($bad) { @{ Text = '12 pending, 4 security'; Level = 'warn' } } else { @{ Text = 'none pending'; Level = 'good' } })
                    Reboot = $(if ($bad) { @{ Text = 'pending: kernel 6.8.0-88'; Level = 'warn' } } else { @{ Text = 'none pending, none scheduled'; Level = 'good' } })
                    Services = $(if ($bad) { @{ Text = 'cron inactive; ssh, systemd-timesyncd active'; Level = 'bad' } } else { @{ Text = 'ssh, cron, systemd-timesyncd active'; Level = 'good' } })
                    Problems = @(if ($bad) { @{ Level = 'bad'; Text = 'cron is not active' }; @{ Level = 'warn'; Text = '/var is 88% full' }; @{ Level = 'warn'; Text = 'reboot pending: kernel 6.8.0-88' } })
                    Checked = @('services', 'disks <85%', 'memory', 'ssh', 'clock', 'reboot')
                }
            }
            'app' {
                @{
                    Name = 'BEVSW-APP1.ad.example'; Ip = '10.20.40.79'
                    Os = 'Windows Server 2025 Standard, build 26100.4652'; Role = 'Line-of-business apps'; Uptime = '3d 4h 12m'
                    Cpu = @{ Now = 7; Min = 2; Max = 64; Text = '8 cores @ 2.4 GHz' }
                    Memory = @{ Pct = 41; Min = 33; Max = 58; Text = '6.5 of 16.0 GiB'; Kind = 'DDR4' }
                    Disks = @(
                        @{ Name = 'C:'; Pct = 63; Min = 62; Max = 63; Text = '80 of 127 GiB'; Kind = 'NVMe' }
                        @{ Name = 'D:'; Pct = $(if ($bad) { 91 } else { 71 }); Min = $(if ($bad) { 90 } else { 70 }); Max = $(if ($bad) { 91 } else { 71 }); Text = $(if ($bad) { '1.6 of 1.8 TiB' } else { '1.3 of 1.8 TiB' }); Kind = 'HDD' }
                    )
                    Sessions = '1  (administrator)'; Time = 'Tue 2026-10-20 09:30 -05:00'
                    Ipv4 = @(@{ Name = 'Ethernet0'; Address = '10.20.40.79/22' })
                    Updates = $(if ($bad) { @{ Text = '3 pending, 1 security'; Level = 'warn' } } else { @{ Text = 'none pending'; Level = 'good' } })
                    Reboot = $(if ($bad) { @{ Text = 'pending: Windows Update'; Level = 'warn' } } else { @{ Text = 'none pending, none scheduled'; Level = 'good' } })
                    Services = $(if ($bad) { @{ Text = 'W32Time stopped; sshd, Netlogon running'; Level = 'bad' } } else { @{ Text = 'sshd, W32Time, Netlogon running'; Level = 'good' } })
                    Problems = @(if ($bad) { @{ Level = 'bad'; Text = 'W32Time is stopped' }; @{ Level = 'warn'; Text = 'D: is 91% full' }; @{ Level = 'warn'; Text = 'reboot pending: Windows Update' } })
                    Checked = @('services', 'disks <85%', 'memory', 'sshd', 'clock', 'reboot')
                }
            }
            'db' {
                @{
                    Name = 'cwpql-db2.ad.example'; Ip = '10.20.60.15'
                    Os = 'Debian GNU/Linux 12 (bookworm), kernel 6.1.0-40-amd64'; Role = 'Database'; Uptime = '41d 2h 5m'
                    Cpu = @{ Now = 22; Min = 9; Max = 83; Text = '16 cores @ 3.1 GHz' }
                    Memory = @{ Pct = 72; Min = 70; Max = 79; Text = '46.1 of 64.0 GiB'; Kind = 'DDR5' }
                    Disks = @(
                        @{ Name = '/'; Pct = 22; Min = 22; Max = 22; Text = '10 of 47 GiB'; Kind = 'SSD' }
                        @{ Name = '/srv'; Pct = $(if ($bad) { 96 } else { 64 }); Min = $(if ($bad) { 93 } else { 63 }); Max = $(if ($bad) { 96 } else { 64 }); Text = $(if ($bad) { '1.7 of 1.8 TiB' } else { '1.2 of 1.8 TiB' }); Kind = 'NVMe' }
                    )
                    Sessions = '1  (admin)'; Time = 'Tue 2026-10-20 09:30 CDT'
                    Ipv4 = @(@{ Name = 'eno1'; Address = '10.20.60.15/24' }, @{ Name = 'eno2'; Address = '10.20.70.15/24' })
                    Updates = $(if ($bad) { @{ Text = '5 pending'; Level = 'warn' } } else { @{ Text = 'none pending'; Level = 'good' } })
                    Reboot = $(if ($bad) { @{ Text = 'none pending; scheduled Sat 02:00'; Level = 'warn' } } else { @{ Text = 'none pending, none scheduled'; Level = 'good' } })
                    Services = $(if ($bad) { @{ Text = 'postgresql failed; ssh, cron active'; Level = 'bad' } } else { @{ Text = 'ssh, cron, postgresql active'; Level = 'good' } })
                    Problems = @(if ($bad) { @{ Level = 'bad'; Text = 'postgresql is failed' }; @{ Level = 'bad'; Text = '/srv is 96% full' } })
                    Checked = @('services', 'disks <85%', 'memory', 'ssh', 'clock', 'reboot')
                }
            }
        }
    }

    function Invoke-PostLogin {
        # In:  the host's facts (Get-Facts), the terminal's mode, changes to
        #      the configuration as 'a.b' = value, and -AsciiOnly
        # Out: the banner's lines, for Contoso in its lab, with three VLANs
        # Why: each test states only what it changes
        param([hashtable]$Facts, [string]$Mode = 'none', [hashtable]$Change = @{}, [switch]$AsciiOnly)
        $os = if ($Facts.Name -like 'h-vsl*') { 'ubuntu' } elseif ($Facts.Name -like 'BEVSW*') { 'windows' } else { 'linux' }
        InModuleScope UsaBanner -Parameters @{ Facts = $Facts; Os = $os; Mode = $Mode; Change = $Change; AsciiOnly = [bool]$AsciiOnly } {
            param($Facts, $Os, $Mode, $Change, $AsciiOnly)
            $config = Get-UsaBannerConfigDefault
            $config['company'] = 'Contoso'
            $config['environment'] = 'LAB'
            $config['vlans'] = @(
                [ordered]@{ name = 'Management'; tag = 10; cidr = '10.20.10.0/24'; color = 'Blue'; short = 'Mgmt' }
                [ordered]@{ name = 'Servers'; tag = 40; cidr = '10.20.40.0/22'; color = 'Teal' }
                [ordered]@{ name = 'Application servers'; tag = 60; cidr = '10.20.60.0/24'; color = 'Brown'; short = 'Apps' }
            )
            foreach ($key in $Change.Keys) {
                $parts = $key.Split('.')
                $node = $config
                for ($i = 0; $i -lt $parts.Count - 1; $i++) { $node = $node[$parts[$i]] }
                $node[$parts[-1]] = $Change[$key]
            }
            @(Get-UsaBannerPostLogon -Config $config -Os $Os -Facts $Facts -Mode $Mode -AsciiOnly:$AsciiOnly)
        }
    }

    function Measure-Visible {
        # In:  a line as a terminal gets it
        # Out: the columns it takes on screen
        # Why: escapes take none
        param([string]$Line)
        ($Line -replace "$([char]27)\[[0-9;]*m", '').Length
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the banner after login' {
    It 'is <Name>, as its golden frame shows' -ForEach @(
        @{ Name = 'postlogon-web-truecolor'; Kind = 'web'; Mode = 'truecolor'; Change = @{} }
        @{ Name = 'postlogon-web-256'; Kind = 'web'; Mode = '256'; Change = @{} }
        @{ Name = 'postlogon-web-16'; Kind = 'web'; Mode = '16'; Change = @{} }
        @{ Name = 'postlogon-web-mono'; Kind = 'web'; Mode = 'mono'; Change = @{} }
        @{ Name = 'postlogon-web-none'; Kind = 'web'; Mode = 'none'; Change = @{} }
        @{ Name = 'postlogon-app-problems-16'; Kind = 'app'; Mode = '16'; Change = @{ 'environment' = 'PROD' }; Problems = $true }
        @{ Name = 'postlogon-db-problems-rounded-truecolor'; Kind = 'db'; Mode = 'truecolor'; Change = @{ 'environment' = 'PUB'; 'border.set' = 'Rounded' }; Problems = $true }
        @{ Name = 'postlogon-web-ascii-16'; Kind = 'web'; Mode = '16'; Change = @{ 'border.set' = 'Rounded' }; AsciiOnly = $true }
        @{ Name = 'postlogon-web-highcontrast-truecolor'; Kind = 'web'; Mode = 'truecolor'; Change = @{ 'color.preset' = 'HighContrast' } }
        @{ Name = 'postlogon-web-uwu-16'; Kind = 'web'; Mode = '16'; Change = @{ 'voice' = 'uwu' } }
        @{ Name = 'postlogon-web-leet-none'; Kind = 'web'; Mode = 'none'; Change = @{ 'voice' = 'leet' } }
    ) {
        $lines = Invoke-PostLogin -Facts (Get-Facts $Kind -Problems:([bool]$Problems)) -Mode $Mode -Change $Change -AsciiOnly:([bool]$AsciiOnly)
        Assert-UsaBannerGoldenFrame -Name $Name -Lines $lines
    }

    It 'is postlogon-outsider-none for a host outside the standard and every VLAN, with no company or tier set' {
        $facts = @{ Name = 'webserver01.ad.example'; Ip = '10.20.200.5'; Os = 'Ubuntu 24.04.3 LTS'; Uptime = '1h 2m'; Checked = @('services') }
        Assert-UsaBannerGoldenFrame -Name 'postlogon-outsider-none' -Lines (Invoke-PostLogin -Facts $facts -Change @{ 'company' = ''; 'environment' = 'UNSET' })
    }

    It 'is postlogon-long-name-none: a long host name leaves the badge only its tag' {
        $facts = Get-Facts web
        $facts.Name = 'h-vsl-web1.department-of-long-names.ad.example'
        Assert-UsaBannerGoldenFrame -Name 'postlogon-long-name-none' -Lines (Invoke-PostLogin -Facts $facts)
    }

    It 'stays within 64 columns in <Set>, in every mode' -ForEach $setCases {
        $problems = foreach ($mode in 'truecolor', '256', '16', 'mono', 'none') {
            foreach ($line in Invoke-PostLogin -Facts (Get-Facts db -Problems) -Mode $mode -Change @{ 'border.set' = $Set }) {
                $width = Measure-Visible $line
                if ($width -gt 64) { "${mode}: $width columns: $line" }
            }
        }
        @($problems) | Should -BeNullOrEmpty
    }

    It 'draws <Set> in ASCII for a client that is not UTF-8' -ForEach $setCases {
        $problems = foreach ($line in Invoke-PostLogin -Facts (Get-Facts web -Problems) -Mode '16' -Change @{ 'border.set' = $Set } -AsciiOnly) {
            $plain = $line -replace "$([char]27)\[[0-9;]*m", ''
            if ($plain -cnotmatch '^[ -~]*$') { $plain }
        }
        @($problems) | Should -BeNullOrEmpty
    }
}

Describe 'the colour presets (D7)' {
    It 'draws Classic16 in 16 colours on a truecolor terminal, as the 16-colour frame' {
        $facts = Get-Facts web
        (Invoke-PostLogin -Facts $facts -Mode truecolor -Change @{ 'color.preset' = 'Classic16' }) -join "`n" | Should -BeExactly ((Invoke-PostLogin -Facts $facts -Mode '16') -join "`n")
    }

    It 'draws Mono in bold and reverse only, as NO_COLOR''s mono mode does' {
        $facts = Get-Facts web
        $mono = (Invoke-PostLogin -Facts $facts -Mode truecolor -Change @{ 'color.preset' = 'Mono' }) -join "`n"
        $mono | Should -BeExactly ((Invoke-PostLogin -Facts $facts -Mode mono) -join "`n")
        $mono | Should -Not -Match '\[[0-9;]*(3[0-9]|4[0-9]|9[0-7])(;[0-9;]*)?m'
        $mono | Should -Match ([regex]::Escape("$esc[1;7m") + ' +L A B +')
    }

    It 'draws Mono''s tier strip as reverse video under NO_COLOR, whatever the preset: <Preset>' -ForEach @(
        @{ Preset = 'UsagiTools' }
        @{ Preset = 'HighContrast' }
    ) {
        $lines = Invoke-PostLogin -Facts (Get-Facts web) -Mode mono -Change @{ 'color.preset' = $Preset }
        ($lines -join "`n") | Should -Match ([regex]::Escape("$esc[1;7m") + ' +L A B +')
    }

    It 'draws Custom as UsagiTools: the configuration holds no colours for it yet' {
        $facts = Get-Facts web
        (Invoke-PostLogin -Facts $facts -Mode truecolor -Change @{ 'color.preset' = 'Custom' }) -join "`n" | Should -BeExactly ((Invoke-PostLogin -Facts $facts -Mode truecolor) -join "`n")
    }
}

Describe 'the panel' {
    It 'gives a fact that is not there no row' {
        $lines = Invoke-PostLogin -Facts @{ Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80' }
        $rows = @($lines | Where-Object { $_ -match '^\| ' })
        @($rows | ForEach-Object { ($_ -replace '^\|\s+', '' -split '\s+')[0] }) | Should -BeExactly @('schema', 'vlan', 'tier')
    }

    It 'cuts a value too wide for its row, ending it in ~' {
        $facts = Get-Facts web
        $facts.Os = 'Ubuntu 24.04.3 LTS (Noble Numbat), kernel 6.8.0-87-generic, x86_64 with HWE'
        $row = @(Invoke-PostLogin -Facts $facts | Where-Object { $_ -match '^\| *os ' })[0]
        $row.Length | Should -Be 64
        $row | Should -Match '~ \|$'
    }

    It 'drops the 24-hour range before it cuts a disk''s size' {
        $facts = Get-Facts web
        $facts.Disks = @(@{ Name = '/var'; Pct = 52; Min = 51; Max = 53; Text = '21 of 40 GiB, mirrored'; Kind = 'SSD' })
        $row = @(Invoke-PostLogin -Facts $facts | Where-Object { $_ -match 'disk /var' })[0]
        $row | Should -Match '21 of 40 GiB, mirrored  SSD +\|$'
        $row | Should -Not -Match '24h'
    }

    It 'shortens the badge before it drops it: <Case>' -ForEach @(
        @{ Case = 'site, VLAN tag and short name'; Site = 'HQ'; Vlan = @{ tag = 40; name = 'Servers' }; Expected = @('HQ - 40-Servers', '40-Servers', '40') }
        @{ Case = 'the short name over the name'; Site = 'HQ'; Vlan = @{ tag = 10; name = 'Management'; short = 'Mgmt' }; Expected = @('HQ - 10-Mgmt', '10-Mgmt', '10') }
        @{ Case = 'no site'; Site = ''; Vlan = @{ tag = 40; name = 'Servers' }; Expected = @('40-Servers', '40') }
        @{ Case = 'no VLAN'; Site = 'HQ'; Vlan = $null; Expected = @('HQ') }
    ) {
        InModuleScope UsaBanner -Parameters @{ Site = $Site; Vlan = $Vlan } {
            param($Site, $Vlan)
            $identity = if ($Site) { @{ Site = $Site } } else { $null }
            @(Get-UsaBannerBadgeText -Identity $identity -Vlan $Vlan)
        } | Should -BeExactly $Expected
    }
}

Describe 'the welcome line and the health lines' {
    It 'drops a voice''s tail after the company rather than pass 64 columns' {
        $company = 'Contoso Pharmaceutical Research Laboratories Ltd'
        $lines = Invoke-PostLogin -Facts (Get-Facts web) -Change @{ 'company' = $company; 'voice' = 'uwu' }
        $welcome = @($lines | Where-Object { $_ -like '*Wewcome to*' })[0]
        $welcome | Should -BeExactly "  Wewcome to $company"
    }

    It 'wraps a long problem under itself' {
        $facts = Get-Facts web
        $facts.Problems = @(@{ Level = 'warn'; Text = 'reboot pending since Tuesday: kernel 6.8.0-88, libc6 2.39-0ubuntu8.6 and systemd 255.4-1ubuntu8.11' })
        $lines = @(Invoke-PostLogin -Facts $facts)
        $at = [array]::IndexOf($lines, @($lines | Where-Object { $_ -like "  $([char]0x25B2) reboot pending*" })[0])
        $lines[$at + 1] | Should -BeLike '    *'
        foreach ($line in $lines[$at..($at + 1)]) { $line.Length | Should -BeLessOrEqual 64 }
    }

    It 'wraps the checks after all clear between checks, within 64 columns' {
        $facts = Get-Facts web
        $facts.Checked = @('services', 'disks <85%', 'memory', 'ssh', 'clock', 'reboot', 'updates', 'time sync')
        $lines = @(Invoke-PostLogin -Facts $facts)
        $first = [array]::IndexOf($lines, @($lines | Where-Object { $_ -like '*all clear*' })[0])
        $lines[$first] | Should -Match 'all clear   services'
        $lines[$first + 1] | Should -Match '^ {16}\S'
        foreach ($line in $lines[$first..($lines.Count - 1)]) { $line.Length | Should -BeLessOrEqual 64 }
    }
}
