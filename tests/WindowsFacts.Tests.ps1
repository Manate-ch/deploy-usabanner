# A Windows host's facts (UsaBanner/Private/WindowsFacts.ps1, docs/DECISIONS.md
# D26). The probes are mocked with what they gave on two lab virtual machines,
# Windows Server 2025 and 2022, on 2026-10-22 at about 02:42 UTC, their names
# and addresses replaced. quser listed no one on either ("No User exists for
# *"), so the sessions test writes lines in quser's format, and the CPU
# samples are made up: the recording took none. The probes that need CIM run
# on Windows only; the ones through .NET also run here, on any OS.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force

    # What each probe gave, per host.
    $script:Recorded = @{
        'Server 2025' = @{
            System     = @{ Caption = 'Microsoft Windows Server 2025 Standard'; Build = '26100'; Ubr = '33296'; BootTime = [datetimeoffset]'2026-10-08T19:42:09-05:00'; MemoryKiB = 8387520; FreeKiB = 5861084; DnsHostName = 'BEVSW-APP1'; Domain = 'WORKGROUP'; PartOfDomain = $false; Cores = 4; SystemDrive = 'C:' }
            Now        = [datetimeoffset]'2026-10-21T21:41:47-05:00'
            Drives     = @(@{ Name = 'C:'; Type = 'Fixed'; Ready = $true; Size = 135219113984; Free = 107627487232 })
            Interfaces = @(
                @{ Name = 'Ethernet 2'; Type = 'Ethernet'; Up = $true; Addresses = @('10.20.40.79/24') }
                @{ Name = 'Loopback Pseudo-Interface 1'; Type = 'Loopback'; Up = $true; Addresses = @('127.0.0.1/8') }
            )
            PrimaryIp  = '10.20.40.79'
        }
        'Server 2022' = @{
            System     = @{ Caption = 'Microsoft Windows Server 2022 Standard'; Build = '20348'; Ubr = '5499'; BootTime = [datetimeoffset]'2026-10-08T19:42:13-05:00'; MemoryKiB = 16776128; FreeKiB = 11066928; DnsHostName = 'BEVSW-APP2'; Domain = 'WORKGROUP'; PartOfDomain = $false; Cores = 4; SystemDrive = 'C:' }
            Now        = [datetimeoffset]'2026-10-21T21:42:56-05:00'
            Drives     = @(
                @{ Name = 'C:'; Type = 'Fixed'; Ready = $true; Size = 135370108928; Free = 89695043584 }
                @{ Name = 'D:'; Type = 'CDRom'; Ready = $true; Size = 14552367104; Free = 0 }
            )
            Interfaces = @(
                @{ Name = 'Ethernet 2'; Type = 'Ethernet'; Up = $true; Addresses = @('10.20.40.78/24') }
                @{ Name = 'Loopback Pseudo-Interface 1'; Type = 'Loopback'; Up = $true; Addresses = @('127.0.0.1/8') }
            )
            PrimaryIp  = '10.20.40.78'
        }
    }

    function Invoke-WindowsFacts {
        # In:  a host's probes as $Recorded holds them; -Session, a user per
        #      session as quser lists them; -Change, keys of the system's
        #      answer to replace; -Arguments, for Get-UsaBannerWindowsFacts
        # Out: @{ Facts; Calls }: the facts, and the probes in the order they ran
        # Why: the probes read Windows; what is under test is the assembly
        param([hashtable]$Probes, [string[]]$Session = @(), [hashtable]$Change = @{}, [hashtable]$Arguments = @{})
        $calls = [System.Collections.Generic.List[string]]::new()
        $system = $Probes.System.Clone()
        foreach ($key in $Change.Keys) { $system[$key] = $Change[$key] }
        $samples = [System.Collections.Generic.Queue[object]]::new([object[]]@(
                @{ Idle = 1000000000; Clock = 5000000000; Own = 300000 }
                @{ Idle = 1001930000; Clock = 5002000000; Own = 340000 }
            ))
        Mock -ModuleName UsaBanner Get-UsaBannerWinSystem { $calls.Add('system'); $system }
        Mock -ModuleName UsaBanner Get-UsaBannerWinInterface { $calls.Add('interfaces'); $Probes.Interfaces }
        Mock -ModuleName UsaBanner Get-UsaBannerPrimaryIp { $calls.Add('route'); $Probes.PrimaryIp }
        Mock -ModuleName UsaBanner Get-UsaBannerWinDrive { $calls.Add('drives'); $Probes.Drives }
        Mock -ModuleName UsaBanner Get-UsaBannerWinSession { $calls.Add('quser'); $Session }
        Mock -ModuleName UsaBanner Get-UsaBannerWinCpuSample { $calls.Add('cpu'); $samples.Dequeue() }
        Mock -ModuleName UsaBanner Start-Sleep { $calls.Add("sleep $Milliseconds") }
        $splat = @{ Now = $Probes.Now; SamplePath = (Join-Path $TestDrive 'no-samples.tsv') }
        foreach ($key in $Arguments.Keys) { $splat[$key] = $Arguments[$key] }
        $facts = InModuleScope UsaBanner -Parameters @{ Splat = $splat } { param($Splat) Get-UsaBannerWindowsFacts @Splat }
        @{ Facts = $facts; Calls = $calls.ToArray() }
    }

    function Use-Culture {
        # In:  a culture's name, and a script block
        # Out: what the block returns, run in that culture
        # Why: the facts must read the same in every culture
        param([string]$Name, [scriptblock]$Script)
        $saved = [cultureinfo]::CurrentCulture
        try {
            [cultureinfo]::CurrentCulture = $Name
            & $Script
        }
        finally { [cultureinfo]::CurrentCulture = $saved }
    }

    # Adapters a Hyper-V host with WSL, containers and a VPN might show.
    $script:Adapters = @(
        @{ Name = 'Ethernet 2'; Type = 'Ethernet'; Up = $true; Addresses = @('10.20.40.79/24') }
        @{ Name = 'vEthernet (External)'; Type = 'Ethernet'; Up = $true; Addresses = @('10.20.40.11/22') }
        @{ Name = 'vEthernet (WSL (Hyper-V firewall))'; Type = 'Ethernet'; Up = $true; Addresses = @('172.29.80.1/20') }
        @{ Name = 'vEthernet (Default Switch)'; Type = 'Ethernet'; Up = $true; Addresses = @('172.17.96.1/20') }
        @{ Name = 'vEthernet (nat)'; Type = 'Ethernet'; Up = $true; Addresses = @('172.18.0.1/16') }
        @{ Name = 'Contoso VPN'; Type = 'Ppp'; Up = $true; Addresses = @('10.99.0.5/32') }
        @{ Name = 'Tunnel adapter'; Type = 'Tunnel'; Up = $true; Addresses = @('10.99.1.5/32') }
        @{ Name = 'Loopback Pseudo-Interface 1'; Type = 'Loopback'; Up = $true; Addresses = @('127.0.0.1/8') }
        @{ Name = 'Ethernet 3'; Type = 'Ethernet'; Up = $false; Addresses = @('10.20.60.5/24') }
        @{ Name = 'Ethernet 4'; Type = 'Ethernet'; Up = $true; Addresses = @('169.254.12.7/16') }
        @{ Name = 'Ethernet 5'; Type = 'Ethernet'; Up = $true; Addresses = @('169.254.3.3/16', '10.20.70.5/24') }
    )
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'Get-UsaBannerWindowsFacts' {
    It 'gives the recorded <Os> host''s facts' -ForEach @(
        @{ Os = 'Server 2025'; Expected = @{
                Name = 'BEVSW-APP1'; Ip = '10.20.40.79'; Os = 'Windows Server 2025 Standard, build 26100.33296'; Uptime = '13d 1h 59m'
                Cpu = '3|4 cores'; Memory = '30|2.4 of 8.0 GiB'; Disks = 'C:|20|26 of 126 GiB'; Sessions = '0'
                Time = 'Wed 2026-10-21 21:41 -05:00'; Ipv4 = 'Ethernet 2|10.20.40.79/24'
            }
        }
        @{ Os = 'Server 2022'; Expected = @{
                Name = 'BEVSW-APP2'; Ip = '10.20.40.78'; Os = 'Windows Server 2022 Standard, build 20348.5499'; Uptime = '13d 2h 0m'
                Cpu = '3|4 cores'; Memory = '34|5.4 of 16.0 GiB'; Disks = 'C:|33|43 of 126 GiB'; Sessions = '0'
                Time = 'Wed 2026-10-21 21:42 -05:00'; Ipv4 = 'Ethernet 2|10.20.40.78/24'
            }
        }
    ) {
        $facts = (Invoke-WindowsFacts $Recorded[$Os]).Facts
        @($facts.Keys | Sort-Object) | Should -BeExactly @('Cpu', 'Disks', 'Ip', 'Ipv4', 'Memory', 'Name', 'Os', 'Sessions', 'Time', 'Uptime')
        foreach ($key in 'Name', 'Ip', 'Os', 'Uptime', 'Sessions', 'Time') { $facts[$key] | Should -BeExactly $Expected[$key] -Because $key }
        '{0}|{1}' -f $facts.Cpu.Now, $facts.Cpu.Text | Should -BeExactly $Expected.Cpu
        '{0}|{1}' -f $facts.Memory.Pct, $facts.Memory.Text | Should -BeExactly $Expected.Memory
        @($facts.Disks | ForEach-Object { '{0}|{1}|{2}' -f $_.Name, $_.Pct, $_.Text }) -join ',' | Should -BeExactly $Expected.Disks
        @($facts.Ipv4 | ForEach-Object { '{0}|{1}' -f $_.Name, $_.Address }) -join ',' | Should -BeExactly $Expected.Ipv4
        @($facts.Cpu.Min, $facts.Cpu.Max, $facts.Memory.Min, $facts.Memory.Max, $facts.Memory.Kind, $facts.Disks[0].Kind).Where({ $null -ne $_ }).Count | Should -Be 0
    }

    It 'reads the CPU last, over a quiet window of 200 ms after every other probe' {
        $calls = (Invoke-WindowsFacts $Recorded['Server 2025']).Calls
        $calls[-3..-1] | Should -BeExactly @('cpu', 'sleep 200', 'cpu')
        @($calls | Select-Object -SkipLast 3 | Sort-Object) | Should -BeExactly @('drives', 'interfaces', 'quser', 'route', 'system')
    }

    It 'names a host in a domain with its domain in lower case, keeping its own name''s case' {
        (Invoke-WindowsFacts $Recorded['Server 2025'] -Change @{ Domain = 'AD.EXAMPLE'; PartOfDomain = $true }).Facts.Name | Should -BeExactly 'BEVSW-APP1.ad.example'
    }

    It 'names the host by its machine name without a DNS host name' {
        (Invoke-WindowsFacts $Recorded['Server 2025'] -Change @{ DnsHostName = '' }).Facts.Name | Should -BeExactly ([Environment]::MachineName)
    }

    It 'takes the first listed adapter''s address without a route out, and gives no Ip with neither' {
        $probes = $Recorded['Server 2025'].Clone()
        $probes.PrimaryIp = ''
        (Invoke-WindowsFacts $probes).Facts.Ip | Should -BeExactly '10.20.40.79'
        $probes.Interfaces = @()
        (Invoke-WindowsFacts $probes).Facts.ContainsKey('Ip') | Should -BeFalse
    }

    It 'leaves out <Case>' -ForEach @(
        @{ Case = 'WSL''s, the Default Switch''s and containers'' NAT adapters by default, but keeps a Hyper-V host''s own'; Arguments = @{}; Expected = 'Ethernet 2,vEthernet (External),Ethernet 5' }
        @{ Case = 'no adapter by name when -Hide is empty'; Arguments = @{ Hide = '' }; Expected = 'Ethernet 2,vEthernet (External),vEthernet (WSL (Hyper-V firewall)),vEthernet (Default Switch),vEthernet (nat),Ethernet 5' }
        @{ Case = 'every vEthernet adapter when -Hide says so, as today''s banner did'; Arguments = @{ Hide = '^vEthernet' }; Expected = 'Ethernet 2,Ethernet 5' }
    ) {
        $probes = $Recorded['Server 2025'].Clone()
        $probes.Interfaces = $Adapters
        @((Invoke-WindowsFacts $probes -Arguments $Arguments).Facts.Ipv4 | ForEach-Object { $_.Name }) -join ',' | Should -BeExactly $Expected
    }

    It 'keeps only an adapter''s own addresses, never a link-local one' {
        $probes = $Recorded['Server 2025'].Clone()
        $probes.Interfaces = $Adapters
        # Indexed first: an array's own Address method would answer .Address.
        $adapter = @((Invoke-WindowsFacts $probes).Facts.Ipv4 | Where-Object { $_.Name -eq 'Ethernet 5' })
        $adapter.Count | Should -Be 1
        $adapter[0].Address | Should -BeExactly '10.20.70.5/24'
    }

    It 'counts each session quser lists, and each user once' {
        $quser = @(
            ' USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME'
            '>administrator         console             1  Active      none   10/22/2026 2:10 AM'
            ' ops                                       2  Disc        1:05   10/21/2026 9:02 PM'
            ' administrator         rdp-tcp#3           3  Active         .   10/22/2026 1:15 AM'
        )
        $sessions = @(InModuleScope UsaBanner -Parameters @{ Lines = $quser } { param($Lines) ConvertFrom-UsaBannerQuser -Line $Lines })
        $sessions | Should -BeExactly @('administrator', 'ops', 'administrator')
        (Invoke-WindowsFacts $Recorded['Server 2025'] -Session $sessions).Facts.Sessions | Should -BeExactly '3  (administrator ops)'
    }

    It 'writes the day in English in any culture' {
        (Use-Culture 'de-DE' { (Invoke-WindowsFacts $Recorded['Server 2025']).Facts }).Time | Should -BeExactly 'Wed 2026-10-21 21:41 -05:00'
    }

    It 'writes the memory with a decimal point in any culture' {
        (Use-Culture 'de-DE' { (Invoke-WindowsFacts $Recorded['Server 2025']).Facts }).Memory.Text | Should -BeExactly '2.4 of 8.0 GiB'
    }

    It 'lists the system drive first, then the other fixed drives that are ready, by name' {
        $probes = $Recorded['Server 2025'].Clone()
        $probes.Drives = @(
            @{ Name = 'E:'; Type = 'Fixed'; Ready = $true; Size = 20GB; Free = 10GB }
            @{ Name = 'C:'; Type = 'Fixed'; Ready = $true; Size = 20GB; Free = 10GB }
            @{ Name = 'F:'; Type = 'Fixed'; Ready = $false; Size = 0; Free = 0 }
            @{ Name = 'D:'; Type = 'Fixed'; Ready = $true; Size = 20GB; Free = 10GB }
        )
        @((Invoke-WindowsFacts $probes -Change @{ SystemDrive = 'D:' }).Facts.Disks | ForEach-Object { $_.Name }) -join ',' | Should -BeExactly 'D:,C:,E:'
    }

    It 'takes the CPU''s, the memory''s and each disk''s 24-hour range from the periodic job''s samples' {
        $file = Join-Path $TestDrive 'windows-samples.tsv'
        $time = $Recorded['Server 2025'].Now.ToUnixTimeSeconds()
        [System.IO.File]::WriteAllText($file, (@("$($time - 900)`tcpu`t40", "$($time - 900)`tmemory`t25", "$($time - 900)`tdisk`tC:`t19") -join "`n") + "`n")
        $facts = (Invoke-WindowsFacts $Recorded['Server 2025'] -Arguments @{ SamplePath = $file }).Facts
        '{0}-{1}' -f $facts.Cpu.Min, $facts.Cpu.Max | Should -BeExactly '3-40'
        '{0}-{1}' -f $facts.Memory.Min, $facts.Memory.Max | Should -BeExactly '25-30'
        '{0}-{1}' -f $facts.Disks[0].Min, $facts.Disks[0].Max | Should -BeExactly '19-20'
    }

    It 'gives no uptime after a clock was set back' {
        (Invoke-WindowsFacts $Recorded['Server 2025'] -Change @{ BootTime = [datetimeoffset]'2026-10-22T00:00:00-05:00' }).Facts.ContainsKey('Uptime') | Should -BeFalse
    }
}

Describe 'Format-UsaBannerUptime' {
    It 'gives <Span> as <Expected>, as linux/facts.sh does' -ForEach @(
        @{ Span = '00:00:59'; Expected = '0h 0m' }
        @{ Span = '10:23:59'; Expected = '10h 23m' }
        @{ Span = '1.00:00:00'; Expected = '1d 0h 0m' }
        @{ Span = '12.06:40:30'; Expected = '12d 6h 40m' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Span = [timespan]$Span } { param($Span) Format-UsaBannerUptime -Span $Span } | Should -BeExactly $Expected
    }
}

Describe 'Format-UsaBannerSize' {
    It 'gives <Case>, as linux/facts.sh does' -ForEach @(
        @{ Case = 'TiB to a tenth from 1 TiB'; Used = 1.2 * 1TB; Size = 2TB; Expected = '1.2 of 2.0 TiB' }
        @{ Case = 'whole GiB from 10 GiB, rounded'; Used = 15.5 * 1GB; Size = 30GB; Expected = '16 of 30 GiB' }
        @{ Case = 'GiB to a tenth below 10 GiB'; Used = 1GB; Size = 5GB; Expected = '1.0 of 5.0 GiB' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Used = $Used; Size = $Size } { param($Used, $Size) Format-UsaBannerSize -Used $Used -Size $Size } | Should -BeExactly $Expected
    }

    It 'writes a decimal point in any culture' {
        Use-Culture 'de-DE' { InModuleScope UsaBanner { Format-UsaBannerSize -Used 1GB -Size 5GB } } | Should -BeExactly '1.0 of 5.0 GiB'
    }
}

Describe 'Get-UsaBannerWinCpuPercent' {
    It 'gives <Case>' -ForEach @(
        @{ Case = 'the busy share less this process''s own'; To = @{ Idle = 1930000; Clock = 2000000; Own = 40000 }; Cores = 4; Expected = 3 }
        @{ Case = '0 when this process was the busy one'; To = @{ Idle = 1990000; Clock = 2000000; Own = 400000 }; Cores = 1; Expected = 0 }
        @{ Case = '100 at most'; To = @{ Idle = -100000; Clock = 2000000; Own = 0 }; Cores = 2; Expected = 100 }
    ) {
        InModuleScope UsaBanner -Parameters @{ To = $To; Cores = $Cores } {
            param($To, $Cores)
            Get-UsaBannerWinCpuPercent -From @{ Idle = 0; Clock = 0; Own = 0 } -To $To -Cores $Cores
        } | Should -Be $Expected
    }

    It 'gives nothing <Case>' -ForEach @(
        @{ Case = 'without a first sample'; From = $null; Cores = 4 }
        @{ Case = 'when the clock did not move'; From = @{ Idle = 0; Clock = 2000000; Own = 0 }; Cores = 4 }
        @{ Case = 'without a core count'; From = @{ Idle = 0; Clock = 0; Own = 0 }; Cores = 0 }
    ) {
        InModuleScope UsaBanner -Parameters @{ From = $From; Cores = $Cores } {
            param($From, $Cores)
            Get-UsaBannerWinCpuPercent -From $From -To @{ Idle = 1930000; Clock = 2000000; Own = 40000 } -Cores $Cores
        } | Should -BeNullOrEmpty
    }
}

Describe 'the probes through .NET, run here' {
    It 'finds the address the default route sends from, as the kernel''s route lookup does' -Skip:$IsWindows {
        $route = "$(& ip -4 route get 192.0.2.1 2>$null)"
        $expected = if ($route -match '\bsrc (\S+)') { $Matches[1] } else { '' }
        InModuleScope UsaBanner { Get-UsaBannerPrimaryIp } | Should -BeExactly $expected
    }

    It 'lists the adapters with their type, state and IPv4 addresses' {
        $loopback = @(InModuleScope UsaBanner { Get-UsaBannerWinInterface } | Where-Object { $_.Type -eq 'Loopback' })
        $loopback.Count | Should -BeGreaterThan 0
        $loopback[0].Up | Should -BeOfType [bool]
        $loopback[0].Addresses | Should -Contain '127.0.0.1/8'
    }

    It 'lists the drives, a fixed one with its size' {
        $fixed = @(InModuleScope UsaBanner { Get-UsaBannerWinDrive } | Where-Object { $_.Type -eq 'Fixed' -and $_.Ready })
        $fixed.Count | Should -BeGreaterThan 0
        $fixed[0].Size | Should -BeGreaterThan 0
        $fixed[0].Free | Should -BeLessOrEqual $fixed[0].Size
    }

    It 'lists no sessions where there is no quser' -Skip:$IsWindows {
        @(InModuleScope UsaBanner { Get-UsaBannerWinSession }).Count | Should -Be 0
    }
}
