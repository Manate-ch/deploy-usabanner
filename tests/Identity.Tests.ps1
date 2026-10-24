# Who a host is (UsaBanner/Private/Identity.ps1): its name decoded by the
# naming standard (docs/DECISIONS.md, D20), the VLAN its address is in, its
# tier, and the named colours they are drawn in. Each table starts out as
# today's banner has it, in rootfs/usr/local/share/manatech.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    $schema = Get-Content -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'config' 'usabanner.schema.json') -Raw | ConvertFrom-Json -AsHashtable
    $today = Join-Path $repoRoot 'rootfs' 'usr' 'local' 'share' 'manatech'

    function Read-TodayTable {
        # In:  the name of one of today's TSV files
        # Out: each row that is not a comment, as its fields
        # Why: the module's tables start out as today's, row for row
        param([string]$Name)
        foreach ($line in Get-Content -LiteralPath (Join-Path $today $Name)) {
            if ($line -match '^\s*(#|$)') { continue }
            , ($line -split "`t")
        }
    }

    function Resolve-Name {
        # In:  a host name, and lists that replace the default naming table's
        # Out: what Resolve-UsaBannerHostName makes of the name
        # Why: each test states only the lists it changes
        param([string]$Name, [hashtable]$Change = @{})
        InModuleScope UsaBanner -Parameters @{ Name = $Name; Change = $Change } {
            param($Name, $Change)
            $naming = (Get-UsaBannerConfigDefault)['naming']
            foreach ($key in $Change.Keys) { $naming[$key] = $Change[$key] }
            Resolve-UsaBannerHostName -Name $Name -Naming $naming
        }
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the naming standard' {
    It 'ships today''s schema-names.tsv row for row, as D20 decided' {
        $naming = InModuleScope UsaBanner { (Get-UsaBannerConfigDefault)['naming'] }
        $lists = [ordered]@{ site = 'sites'; type = 'types'; subtype = 'subtypes'; os = 'os' }
        $shipped = foreach ($field in $lists.Keys) {
            foreach ($row in $naming[$lists[$field]]) { "$field`t$($row['code'])`t$($row['name'])`t$($row['color'])" }
        }
        @($shipped) | Should -BeExactly @(foreach ($f in Read-TodayTable 'schema-names.tsv') { $f -join "`t" })
    }

    It 'decodes <Name> as <Decoded>' -ForEach @(
        @{ Name = 'h-vsl-web1'; Decoded = 'HQ / Virtual / Server / Linux'; Site = 'HQ' }
        @{ Name = 'BEVSW-APP-1.ad.example'; Decoded = 'Branch East / Virtual / Server / Windows'; Site = 'Branch East' }
        @{ Name = 'cwaqw-sql2'; Decoded = 'Cloud West / Azure / Database / Windows'; Site = 'Cloud West' }
        @{ Name = 'bepxu-core1'; Decoded = 'Branch East / Physical / Networking Switch / Unifi'; Site = 'Branch East' }
        @{ Name = 'zzvsl-web1'; Decoded = '? / Virtual / Server / Linux'; Site = '' }
    ) {
        $id = Resolve-Name $Name
        $id.Decoded | Should -BeExactly $Decoded
        $id.Site | Should -BeExactly $Site
    }

    It 'gives each code its row, with the colour its letters are drawn in' {
        $id = Resolve-Name 'h-pff-fw1'
        $id.Codes.Values | Should -BeExactly @('h-', 'p', 'f', 'f')
        @($id.Rows.Values | ForEach-Object { $_['color'] }) | Should -BeExactly @('Blue', 'Orange', 'Red', 'Red')
    }

    It 'decodes no name outside the standard: <Case>' -ForEach @(
        @{ Case = 'the shape, but no type it knows'; Name = 'proxy-01' }
        @{ Case = 'the shape, but no OS it knows'; Name = 'relay-01' }
        @{ Case = 'no hyphen after the five letters'; Name = 'webserver01' }
        @{ Case = 'no digit at the end'; Name = 'h-vsl-web' }
        @{ Case = 'no name at all'; Name = '' }
    ) {
        Resolve-Name $Name | Should -BeNullOrEmpty
    }

    It 'takes a host''s own sites in place of the examples' {
        $sites = @(@{ code = 'nw'; name = 'North Warehouse'; color = 'Teal' })
        (Resolve-Name 'nwvsl-web1' -Change @{ sites = $sites }).Decoded | Should -BeExactly 'North Warehouse / Virtual / Server / Linux'
        (Resolve-Name 'h-vsl-web1' -Change @{ sites = $sites }).Decoded | Should -BeExactly '? / Virtual / Server / Linux'
    }

    It 'decodes nothing with an empty types list' {
        Resolve-Name 'h-vsl-web1' -Change @{ types = @() } | Should -BeNullOrEmpty
    }

    It 'takes the first row where a list has a code twice' {
        $types = @(@{ code = 'v'; name = 'Virtual' }, @{ code = 'v'; name = 'Vendor' })
        (Resolve-Name 'h-vsl-web1' -Change @{ types = $types }).Decoded | Should -BeExactly 'HQ / Virtual / Server / Linux'
    }
}

Describe 'the VLAN an address is in' {
    BeforeAll {
        $vlans = @(
            @{ name = 'Servers'; tag = 40; cidr = '10.20.40.0/22'; color = 'Teal' }
            @{ name = 'Overlay network'; tag = 45; cidr = '10.20.40.0/28' }
            @{ name = 'Management'; tag = 10; cidr = '10.20.10.0/24'; color = 'Blue'; short = 'Mgmt' }
        )
    }

    It 'is VLAN <Tag> for <Address>: <Why>' -ForEach @(
        @{ Address = '10.20.40.80'; Tag = 40; Why = 'inside a /22' }
        @{ Address = '10.20.43.255'; Tag = 40; Why = 'the /22''s last address' }
        @{ Address = '10.20.40.5'; Tag = 45; Why = 'where networks nest, the longest prefix wins' }
        @{ Address = '10.20.10.1'; Tag = 10; Why = 'another row' }
    ) {
        $row = InModuleScope UsaBanner -Parameters @{ Address = $Address; Vlans = $vlans } { param($Address, $Vlans) Find-UsaBannerVlan -Address $Address -Vlans $Vlans }
        $row['tag'] | Should -Be $Tag
    }

    It 'is none for <Case>' -ForEach @(
        @{ Case = 'an address in no VLAN'; Address = '10.20.44.1' }
        @{ Case = 'an IPv6 address'; Address = 'fd00::1' }
        @{ Case = 'a short form, which .NET would read as 10.20.40.80'; Address = '10.20.10320' }
        @{ Case = 'no address'; Address = '' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Address = $Address; Vlans = $vlans } { param($Address, $Vlans) Find-UsaBannerVlan -Address $Address -Vlans $Vlans } | Should -BeNullOrEmpty
    }

    It 'is none with no VLANs, as the defaults have' {
        InModuleScope UsaBanner { Find-UsaBannerVlan -Address '10.20.40.80' -Vlans @((Get-UsaBannerConfigDefault)['vlans']) } | Should -BeNullOrEmpty
    }
}

Describe 'the named colours' {
    It 'are today''s colors.tsv, each in 24-bit and as its 16-colour code' {
        $problems = foreach ($f in Read-TodayTable 'colors.tsv') {
            $found = InModuleScope UsaBanner -Parameters @{ Name = $f[0] } { param($Name) $c = Get-UsaBannerNamedColor -Name $Name; @{ Hex = $c.Hex; Sgr = $script:UsaBasicSgr[$c.Basic] } }
            $hex = '#{0:X2}{1:X2}{2:X2}' -f [int]$f[2], [int]$f[3], [int]$f[4]
            if ($found.Hex -cne $hex) { "$($f[0]): $($found.Hex), today $hex" }
            if ($found.Sgr -ne [int]$f[5]) { "$($f[0]): code $($found.Sgr), today $($f[5])" }
        }
        @($problems) | Should -BeNullOrEmpty
    }

    It 'are the names the schema allows, no more and no fewer' {
        InModuleScope UsaBanner { @($script:UsaNamedColors.Keys) } | Should -BeExactly $schema['$defs']['colorName']['enum']
    }

    It 'refuse a name that is not one, listing them' {
        { InModuleScope UsaBanner { Get-UsaBannerNamedColor -Name 'Mauve' } } | Should -Throw "*'Mauve' is not a named colour; there is Pink, White, *"
    }
}

Describe 'the tiers' {
    It 'are the tiers the schema allows, in its order' {
        InModuleScope UsaBanner { @($script:UsaTiers.Keys) } | Should -BeExactly $schema['properties']['environment']['enum']
    }

    It 'draw <Tier> in <Color>, its colour today, and say it holds <Meaning>' -ForEach @(
        @{ Tier = 'UNSET'; Color = 'Grey'; Meaning = 'not set yet' }
        @{ Tier = 'DEV-TEST'; Color = 'Black'; Meaning = 'sandbox and development' }
        @{ Tier = 'LAB'; Color = 'Orange'; Meaning = 'larger-scale testing' }
        @{ Tier = 'PROD'; Color = 'Blue'; Meaning = 'production' }
        @{ Tier = 'PUB'; Color = 'Pink'; Meaning = 'public-facing' }
    ) {
        $got = InModuleScope UsaBanner -Parameters @{ Tier = $Tier } { param($Tier) Get-UsaBannerTier -Name $Tier }
        $got.Color | Should -BeExactly $Color
        $got.Meaning | Should -BeExactly $Meaning
    }

    It 'refuse a tier that is not one' {
        { InModuleScope UsaBanner { Get-UsaBannerTier -Name 'STAGING' } } | Should -Throw "*'STAGING' is not a tier; there is UNSET, DEV-TEST, LAB, PROD, PUB.*"
    }
}
