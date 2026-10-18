# Pester 5 tests for the OS-independent half of ManatechBanner.psm1:
# config defaults, schema decoding and banner layout. Get-ManatechHostFact
# reads a live Windows host and is exercised by installing, not here.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\ManatechBanner.psm1') -Force
    $script:Data = Join-Path $PSScriptRoot '../../rootfs/usr/local/share/manatech'
    $script:Esc = [string][char]27

    function New-TestFact {
        param([string]$HostName = 'h-vsw-example1.ad.example', [object[]]$Problems = @(), [string]$PrimaryIp = '')
        @{
            HostName = $HostName; PrimaryIp = $PrimaryIp; Os ='Windows Server 2025 Standard, build 26100.1'
            Uptime = [timespan]::new(3, 4, 12, 0); CpuPct = 7; Cores = 8
            MemPct = 41; MemText = '6.5 of 16.0 GiB'; DiskName = 'C:'; DiskPct = 63; DiskText = '80G of 127G'
            Sessions = '1  (administrator)'; Time = 'Wed 2026-09-23 03:00 UTC-05:00'
            Ipv4 = @(@{ Name = 'Ethernet0'; Address = '10.20.40.21/22' }, @{ Name = 'Ethernet1'; Address = '10.20.60.21/24' })
            Problems = $Problems; Checked = @('services', 'memory', 'reboot')
        }
    }
    function New-TestConfig {
        param([string]$Color = 'truecolor', [string]$Glyphs = 'unicode')
        $c = Get-ManatechConfig -DataPath $TestDrive
        $c.Color = $Color; $c.Glyphs = $Glyphs; $c.EnvName = 'LAB'; $c.Role = 'test host'
        $c
    }
    function Get-Visible { param([string]$Text) $Text -replace "$Esc\[[0-9;]*m", '' }
    function Get-Schema {
        $s = @{}
        foreach ($line in Get-Content -LiteralPath (Join-Path $Data 'schema-names.tsv')) {
            if ($line -match '^\s*(#|$)') { continue }
            $f = $line -split "`t"
            $s["$($f[0])|$($f[1])"] = @{ Name = $f[2]; Color = $f[3] }
        }
        $s
    }
}

Describe 'issue.net (the pre-login SSH banner, shared by Linux and Windows)' {
    BeforeAll { $script:Issue = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../rootfs/etc/issue.net')) }
    It 'is plain ASCII with no control characters: clients strip or expose anything else before login' {
        ($Issue -join "`n") | Should -Not -Match '[^\x0A\x20-\x7E]'
    }
    It 'draws the warning box 64 columns wide, like the post-login panel' {
        $box = @($Issue | Where-Object { $_ -match '^[+|]' })
        $box.Count | Should -Be 9
        $box | ForEach-Object { $_.Length | Should -Be 64 }
        $box[0] | Should -Match '^\+- WARNING -+ Login for more information -\+$'
    }
    It 'carries the same art as manatech.art, uncoloured' {
        $art = @(Get-Content -LiteralPath (Join-Path $Data 'manatech.art') | ForEach-Object { $_ -replace '@[cy]', '' })
        $Issue[1..$art.Count] | Should -Be $art
    }
}

Describe 'Get-ManatechConfig' {
    It 'returns the defaults when there is no motd.psd1' {
        $c = Get-ManatechConfig -DataPath $TestDrive
        $c.EnvName | Should -Be 'UNSET'
        $c.BorderBy | Should -Be 'type'
    }
    It 'lets motd.psd1 override a default and keeps the rest' {
        Set-Content -LiteralPath (Join-Path $TestDrive 'motd.psd1') -Value "@{ EnvName = 'PROD' }"
        $c = Get-ManatechConfig -DataPath $TestDrive
        $c.EnvName | Should -Be 'PROD'
        $c.DiskWarn | Should -Be 85
        Remove-Item -LiteralPath (Join-Path $TestDrive 'motd.psd1')
    }
}

Describe 'Get-ManatechConfig with an AD Description' {
    It 'reads "<Desc>" as env <Env> and role "<Role>"' -TestCases @(
        @{ Desc = 'PROD: Hyper-V host'; Env = 'PROD'; Role = 'Hyper-V host'; EnvSrc = 'AD Description' }
        @{ Desc = 'lab:Grafana node'; Env = 'LAB'; Role = 'Grafana node'; EnvSrc = 'AD Description' }
        @{ Desc = 'Grafana visualization node'; Env = 'UNSET'; Role = 'Grafana visualization node'; EnvSrc = '' }
        @{ Desc = 'QA-1: kept whole, the prefix is not letters only'; Env = 'UNSET'; Role = 'QA-1: kept whole, the prefix is not letters only'; EnvSrc = '' }
        @{ Desc = ''; Env = 'UNSET'; Role = ''; EnvSrc = '' }
    ) {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'ad-description.txt') -Value $Desc
        $c = Get-ManatechConfig -DataPath $dir
        $c.EnvName | Should -Be $Env
        $c.Role | Should -Be $Role
        $c.EnvSource | Should -Be $EnvSrc
    }
    It 'lets motd.psd1 win over the AD Description, for EnvName and Role each' {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'ad-description.txt') -Value 'PROD: from AD'
        Set-Content -LiteralPath (Join-Path $dir 'motd.psd1') -Value "@{ EnvName = 'LAB' }"
        $c = Get-ManatechConfig -DataPath $dir
        $c.EnvName | Should -Be 'LAB'
        $c.EnvSource | Should -Be 'motd.psd1'
        $c.Role | Should -Be 'from AD'
        $c.RoleSource | Should -Be 'AD Description'
    }
}

Describe 'Format-ManatechBanner environment' {
    It 'draws a 64-column <Env> strip on <Colour> (<Rgb>) with <Ink> text' -TestCases @(
        @{ Env = 'PROD'; Colour = 'Blue'; Rgb = '80;140;230'; Ink = '255;255;255' }
        @{ Env = 'LAB'; Colour = 'Orange'; Rgb = '240;140;50'; Ink = '20;20;20' }
        @{ Env = 'STAGE'; Colour = 'Black (charcoal)'; Rgb = '70;70;78'; Ink = '255;255;255' }
        @{ Env = 'PUB'; Colour = 'Pink'; Rgb = '240;130;180'; Ink = '20;20;20' }
        @{ Env = 'QA'; Colour = 'Grey, from the * row'; Rgb = '140;145;155'; Ink = '20;20;20' }
    ) {
        $c = New-TestConfig
        $c.EnvName = $Env
        $lines = Format-ManatechBanner -Fact (New-TestFact) -Config $c -DataPath $Data
        $word = [regex]::Escape(($Env.ToCharArray() -join ' '))
        $strip = @($lines | Where-Object { (Get-Visible $_) -match "^ +$word +$" })
        $strip.Count | Should -Be 1
        (Get-Visible $strip[0]).Length | Should -Be 64
        $strip[0] | Should -Match ([regex]::Escape("$Esc[48;2;$($Rgb)m"))
        $strip[0] | Should -Match ([regex]::Escape("$Esc[38;2;$($Ink)m"))
    }
    It 'says where the environment came from in the env row' {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'ad-description.txt') -Value 'PUB: Public web front end'
        $c = Get-ManatechConfig -DataPath $dir
        $c.Color = 'none'; $c.Glyphs = 'ascii'
        $text = (Format-ManatechBanner -Fact (New-TestFact) -Config $c -DataPath $Data) -join "`n"
        $text | Should -Match '\|  env        PUB   from AD Description +\|'
        $text | Should -Match '\|  role      Public web front end +\|'
    }
    It 'asks for the AD Description when there is no role anywhere' {
        $c = New-TestConfig none ascii
        $c.Role = ''
        $text = (Format-ManatechBanner -Fact (New-TestFact) -Config $c -DataPath $Data) -join "`n"
        $text | Should -Match "\|  role      \(set this computer's AD Description\) +\|"
    }
    It 'shows no strip and no env row with EnvShow empty' {
        $c = New-TestConfig none ascii
        $c.EnvShow = @()
        $text = (Format-ManatechBanner -Fact (New-TestFact) -Config $c -DataPath $Data) -join "`n"
        $text | Should -Not -Match 'L A B'
        $text | Should -Not -Match '\|  env '
    }
}

Describe 'Resolve-ManatechHostName' {
    It 'decodes <Name> as <Decoded>' -TestCases @(
        @{ Name = 'h-vsl-web1'; Decoded = 'HQ / Virtual / Server / Linux' }
        @{ Name = 'H-VSW-APP1.ad.example'; Decoded = 'HQ / Virtual / Server / Windows' }
        @{ Name = 'bepfw-edge12'; Decoded = 'Branch East / Physical / Firewall / Windows' }
        @{ Name = 'CWVSW-APP1'; Decoded = 'Cloud West / Virtual / Server / Windows' }
        @{ Name = 'lavsl-thing1'; Decoded = 'Lab A / Virtual / Server / Linux' }
        @{ Name = 'lbvsl-thing1'; Decoded = 'Lab B / Virtual / Server / Linux' }
        @{ Name = 's-vsl-thing1'; Decoded = '? / Virtual / Server / Linux' }
    ) {
        (Resolve-ManatechHostName -Name $Name -Schema (Get-Schema)).Decoded | Should -Be $Decoded
    }
    It 'returns nothing for <Name>, which is outside the schema' -TestCases @(
        @{ Name = 'WIN-4F2K8QZ' }
        @{ Name = 'h-vsl-nonumber' }
        @{ Name = 'hvsl-thing1' }
    ) {
        Resolve-ManatechHostName -Name $Name -Schema (Get-Schema) | Should -BeNullOrEmpty
    }
}

Describe 'Find-ManatechVlan' {
    It 'puts <Address> in VLAN <Id>' -TestCases @(
        @{ Address = '10.20.40.79'; Id = '40' }
        @{ Address = '10.20.43.254'; Id = '40' }
        @{ Address = '10.20.48.5'; Id = '45' }
        @{ Address = '10.20.70.24'; Id = '70' }
        @{ Address = '172.16.21.9'; Id = '50' }
    ) {
        (Find-ManatechVlan -Address $Address -Path (Join-Path $Data 'vlans.tsv')).Id | Should -Be $Id
    }
    It 'finds nothing for <Address>' -TestCases @(
        @{ Address = '8.8.8.8' }
        @{ Address = '10.20.48.16' }
        @{ Address = '' }
        @{ Address = 'not-an-ip' }
    ) {
        Find-ManatechVlan -Address $Address -Path (Join-Path $Data 'vlans.tsv') | Should -BeNullOrEmpty
    }
}

Describe 'Format-ManatechBanner badge' {
    It 'reads "HQ - 40-Servers" on the VLAN 40 colour (Teal) for H-PSW-APP-1 at 10.20.40.79' {
        $lines = Format-ManatechBanner -Fact (New-TestFact -HostName 'H-PSW-APP-1' -PrimaryIp '10.20.40.79') -Config (New-TestConfig) -DataPath $Data
        $lines | Where-Object { (Get-Visible $_) -match ' HQ - 40-Servers ' } | Should -Match ([regex]::Escape("$Esc[48;2;40;180;180m"))
    }
    It 'adds a vlan row with the Short Desc and the subnet' {
        $lines = Format-ManatechBanner -Fact (New-TestFact -HostName 'H-PSW-APP-1' -PrimaryIp '10.20.40.79') -Config (New-TestConfig none ascii) -DataPath $Data
        ($lines -join "`n") | Should -Match '\|  vlan      40  Servers  \(10\.20\.40\.0/22\) +\|'
    }
    It 'keeps the environment colour for a VLAN with no colour code (70)' {
        $lines = Format-ManatechBanner -Fact (New-TestFact -HostName 'h-vsl-web1' -PrimaryIp '10.20.70.24') -Config (New-TestConfig) -DataPath $Data
        $lines | Where-Object { (Get-Visible $_) -match ' HQ - 70-Lab ' } | Should -Match ([regex]::Escape("$Esc[48;2;240;140;50m"))
    }
    It 'shows EnvName with Badge = env' {
        $c = New-TestConfig none ascii
        $c.Badge = 'env'
        $text = (Format-ManatechBanner -Fact (New-TestFact -PrimaryIp '10.20.40.79') -Config $c -DataPath $Data) -join "`n"
        $text | Should -Match ' LAB -\+'
        $text | Should -Not -Match '40-Servers'
    }
    It 'drops the domain, then cuts the badge, to keep the top border at 64 columns' {
        $fact = New-TestFact -HostName 'h-vsw-anextremelylongservernamethatgoesonandon1.ad.example' -PrimaryIp '10.20.60.30'
        $lines = Format-ManatechBanner -Fact $fact -Config (New-TestConfig none ascii) -DataPath $Data
        $top = @($lines | Where-Object { $_ -match '^\+-' })[0]
        $top.Length | Should -Be 64
        $top | Should -Not -Match 'ad\.example'
        $top | Should -Match '~ -\+$'
    }
}

Describe 'Format-ManatechBanner' {
    It 'draws every panel line <Color>/<Glyphs> at the same width, 64 columns' -TestCases @(
        @{ Color = 'truecolor'; Glyphs = 'unicode' }
        @{ Color = '256'; Glyphs = 'unicode' }
        @{ Color = '16'; Glyphs = 'unicode' }
        @{ Color = 'none'; Glyphs = 'ascii' }
    ) {
        $lines = Format-ManatechBanner -Fact (New-TestFact) -Config (New-TestConfig $Color $Glyphs) -DataPath $Data
        $v = if ($Glyphs -eq 'ascii') { '[|+]' } else { "[$([char]0x2502)$([char]0x256D)$([char]0x2570)]" }
        $panel = @($lines | ForEach-Object { Get-Visible $_ } | Where-Object { $_ -match "^$v" })
        $panel.Count | Should -Be 13   # top, schema, env, os, role, uptime, memory, disk, sessions, time, 2 x ipv4, bottom
        $panel | ForEach-Object { $_.Length | Should -Be 64 }
    }
    It 'emits only ASCII and no escapes with Color none and Glyphs ascii' {
        $text = (Format-ManatechBanner -Fact (New-TestFact) -Config (New-TestConfig none ascii) -DataPath $Data) -join "`n"
        $text | Should -Not -Match '[^\x00-\x7F]'
        $text | Should -Not -Match $Esc
    }
    It 'draws the art: one line per line of manatech.art' {
        $art = @(Get-Content -LiteralPath (Join-Path $Data 'manatech.art') | ForEach-Object { $_ -replace '@[cy]', '' })
        $lines = @(Format-ManatechBanner -Fact (New-TestFact) -Config (New-TestConfig none ascii) -DataPath $Data)
        @($lines[0..($art.Count - 1)] | ForEach-Object { Get-Visible $_ }) | Should -Be $art
    }
    It 'colours the border with the type colour of a schema name (Virtual = Blue)' {
        $lines = Format-ManatechBanner -Fact (New-TestFact) -Config (New-TestConfig) -DataPath $Data
        ($lines | Where-Object { $_ -match 'schema' }) | Should -Match ([regex]::Escape("$Esc[38;2;80;140;230m$([char]0x2502)"))
    }
    It 'keeps the environment border and shows no schema row for a name outside the schema' {
        $lines = Format-ManatechBanner -Fact (New-TestFact -HostName 'WIN-4F2K8QZ') -Config (New-TestConfig) -DataPath $Data
        ($lines -join "`n") | Should -Not -Match 'schema'
        ($lines | Where-Object { (Get-Visible $_) -match '^\S\s+os\s' }) | Should -Match ([regex]::Escape("$Esc[38;2;240;140;50m"))
    }
    It 'lists every check on the all-clear line when there are no problems' {
        $lines = Format-ManatechBanner -Fact (New-TestFact) -Config (New-TestConfig none ascii) -DataPath $Data
        ($lines -join "`n") | Should -Match 'all clear   services - memory - reboot'
    }
    It 'prints one line per problem and no all-clear line when there are problems' {
        $p = @(@{ Level = 'bad'; Text = 'sshd is stopped' }, @{ Level = 'warn'; Text = 'C: is 90% full' })
        $text = (Format-ManatechBanner -Fact (New-TestFact -Problems $p) -Config (New-TestConfig none ascii) -DataPath $Data) -join "`n"
        $text | Should -Match '\[XX\] sshd is stopped'
        $text | Should -Match '\[!!\] C: is 90% full'
        $text | Should -Not -Match 'all clear'
    }
}

# The GPO task failed every run with nobody logged on: quser reports that on
# standard error and exits 1, and the task's Stop preference let it end the
# sync (lab, 2026-10-03). Windows PowerShell 5.1 fails on the standard-error
# line itself; PowerShell 7 does not, but fails on the exit code when
# $PSNativeCommandUseErrorActionPreference is on - which the control uses.
Describe 'Invoke-ManatechNative (console tools quser and w32tm)' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    BeforeAll {
        $script:Module = Get-Module ManatechBanner
        $script:Tool = 'echo "USERNAME"; echo "No User exists for *" >&2; exit 1'
    }
    It 'returns the standard output and leaves the exit code, under a caller set to Stop' {
        $r = & $Module {
            param($Tool)
            $ErrorActionPreference = 'Stop'
            $PSNativeCommandUseErrorActionPreference = $true
            $out = @(Invoke-ManatechNative sh '-c', $Tool)
            [pscustomobject]@{ Out = $out; Code = $LASTEXITCODE }
        } $Tool
        $r.Out | Should -Be @('USERNAME')
        $r.Code | Should -Be 1
    }
    It 'positive control: the same tool called directly does stop such a caller' {
        {
            & $Module {
                param($Tool)
                $ErrorActionPreference = 'Stop'
                $PSNativeCommandUseErrorActionPreference = $true
                $null = @(& sh -c $Tool 2>$null)
            } $Tool
        } | Should -Throw
    }
}
