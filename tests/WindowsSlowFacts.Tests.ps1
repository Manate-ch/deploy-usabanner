# A Windows host's slow facts (UsaBanner/Private/WindowsSlowFacts.ps1,
# docs/DECISIONS.md D17): what the periodic job writes to slow.tsv, in the
# form linux/sample.sh writes, and what a login takes from it. The hardware
# probe is mocked with what it gave on two lab virtual machines, Windows
# Server 2025 and 2022, on 2026-10-22 at about 03:50 UTC: the same on both.
# The physical host is made up, the lab has no physical Windows host, and so
# are the update counts: the Windows Update search is measured in the lab
# run. Facts.Tests.ps1 reads one slow.tsv with both this module and
# linux/facts.sh.

# The -ForEach data is built at discovery, before BeforeAll runs: the time it
# uses is set here too.
BeforeDiscovery { $Epoch = 1792635480 }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    $script:Epoch = 1792635480
    $script:Now = [datetimeoffset]::FromUnixTimeSeconds($Epoch)

    # What Get-UsaBannerWinHardware gave on both lab virtual machines.
    $script:Recorded = @{
        Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine'
        CpuName = 'Intel(R) Xeon(R) Gold 6254 CPU @ 3.10GHz'; CpuMhz = 2195
        Memory = @(@{ Type = 2; Configured = 0; Rated = 0 }, @{ Type = 2; Configured = 0; Rated = 0 })
        Disks = @(@{ Name = 'C:'; MediaType = 'Unspecified'; BusType = 'SAS' })
    }

    # A physical host, its CPU named without a speed.
    $script:Physical = @{
        Manufacturer = 'Contoso'; Model = 'Contoso Rack Server'
        CpuName = 'Contoso 16-Core Processor'; CpuMhz = 3000
        Memory = @(@{ Type = 26; Configured = 3200; Rated = 3200 }, @{ Type = 26; Configured = 3200; Rated = 3200 })
        Disks = @(
            @{ Name = 'C:'; MediaType = 'SSD'; BusType = 'NVMe' }
            @{ Name = 'D:'; MediaType = 'HDD'; BusType = 'RAID' }
            @{ Name = 'E:'; MediaType = 'Unspecified'; BusType = 'USB' }
            @{ Name = 'F:'; MediaType = 'Unspecified'; BusType = 'iSCSI' }
        )
    }

    function Invoke-SlowFacts {
        # In:  what Get-UsaBannerWinHardware gives, what
        #      Get-UsaBannerWinUpdates gives, and the file
        # Out: the file's text after Write-UsaBannerSlowFacts
        # Why: the probes read Windows; what is under test is what is written
        param([AllowNull()][hashtable]$Hardware, [AllowNull()][hashtable]$Updates, [string]$Path = (Join-Path $TestDrive 'slow.tsv'))
        Mock -ModuleName UsaBanner Get-UsaBannerWinHardware { $Hardware }
        Mock -ModuleName UsaBanner Get-UsaBannerWinUpdates { $Updates }
        InModuleScope UsaBanner -Parameters @{ Path = $Path; Now = $Now } { param($Path, $Now) Write-UsaBannerSlowFacts -Path $Path -Now $Now }
        [System.IO.File]::ReadAllText($Path)
    }

    function Join-Line {
        # In:  lines
        # Out: them as one text, each ending in LF
        # Why: slow.tsv is LF-ended on every OS
        param([string[]]$Line)
        -join @(foreach ($one in $Line) { "$one`n" })
    }

    function New-Facts {
        # In:  nothing
        # Out: a Windows host's facts with a CPU, memory and two disks
        # Why: each test fills in the same host
        @{
            Cpu    = @{ Now = 12; Min = $null; Max = $null; Text = '4 cores' }
            Memory = @{ Pct = 41; Min = $null; Max = $null; Text = '6.5 of 16.0 GiB'; Kind = $null }
            Disks  = @(
                @{ Name = 'C:'; Pct = 63; Min = $null; Max = $null; Text = '80 of 127 GiB'; Kind = $null }
                @{ Name = 'D:'; Pct = 71; Min = $null; Max = $null; Text = '1.3 of 1.8 TiB'; Kind = $null }
            )
        }
    }

    function Add-SlowFacts {
        # In:  the lines of a slow.tsv
        # Out: New-Facts, filled in from them by Add-UsaBannerSlowFacts
        # Why: each test reads one file into the same host
        param([string[]]$Line)
        $file = Join-Path $TestDrive ([guid]::NewGuid().ToString() + '.tsv')
        [System.IO.File]::WriteAllText($file, (Join-Line $Line))
        InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = $file; Now = $Now } {
            param($Facts, $Path, $Now)
            Add-UsaBannerSlowFacts -Facts $Facts -Path $Path -Now $Now -ErrorAction Stop
            $Facts
        }
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
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'Write-UsaBannerSlowFacts' {
    It 'writes the recorded hosts'' CPU speed from its name, and no kinds: they are virtual machines' {
        Invoke-SlowFacts $Recorded -Updates @{ Waiting = 3; Security = 1 } | Should -BeExactly (Join-Line "$Epoch`tcpu-speed`t3.1", "$Epoch`tupdates`t3`t1")
    }

    It 'writes a physical host''s memory kind and each drive''s, by its bus, then by its media' {
        Invoke-SlowFacts $Physical -Updates @{ Waiting = 0; Security = 0 } | Should -BeExactly (Join-Line @(
                "$Epoch`tcpu-speed`t3.0"
                "$Epoch`tmemory-kind`tDDR4-3200"
                "$Epoch`tdisk-kind`tC:`tNVMe"
                "$Epoch`tdisk-kind`tD:`tHDD"
                "$Epoch`tdisk-kind`tE:`tremovable"
                "$Epoch`tupdates`t0`t0"
            ))
    }

    It 'writes no kinds in a virtual machine, whatever its virtual hardware claims' {
        $vm = $Physical.Clone()
        $vm.Manufacturer = 'VMware, Inc.'
        $vm.Model = 'VMware20,1'
        Invoke-SlowFacts $vm -Updates $null | Should -BeExactly (Join-Line "$Epoch`tcpu-speed`t3.0")
    }

    It 'writes no line for <Case>' -ForEach @(
        @{ Case = 'the updates when the Windows Update agent cannot answer'; Hardware = 'recorded'; Updates = $null; Expected = @("$Epoch`tcpu-speed`t3.1") }
        @{ Case = 'the hardware when CIM cannot be read'; Hardware = $null; Updates = @{ Waiting = 2; Security = 0 }; Expected = @("$Epoch`tupdates`t2`t0") }
        @{ Case = 'either'; Hardware = $null; Updates = $null; Expected = @() }
    ) {
        $read = if ($Hardware) { $Recorded } else { $null }
        Invoke-SlowFacts $read -Updates $Updates | Should -BeExactly (Join-Line $Expected)
    }

    It 'writes the file anew, whole, leaving nothing beside it' {
        $folder = Join-Path $TestDrive 'anew'
        $null = New-Item -ItemType Directory -Path $folder
        $path = Join-Path $folder 'slow.tsv'
        [System.IO.File]::WriteAllText($path, (Join-Line "$($Epoch - 900)`tmemory-kind`tDDR3-1600", "$($Epoch - 900)`tupdates`t9`t9"))
        Invoke-SlowFacts $Recorded -Updates @{ Waiting = 1; Security = 0 } -Path $path | Should -BeExactly (Join-Line "$Epoch`tcpu-speed`t3.1", "$Epoch`tupdates`t1`t0")
        @(Get-ChildItem -LiteralPath $folder -Force | ForEach-Object { $_.Name }) | Should -BeExactly @('slow.tsv')
    }

    It 'makes its folder when missing' {
        $path = Join-Path $TestDrive 'made' 'for' 'slow.tsv'
        Invoke-SlowFacts $Recorded -Updates $null -Path $path | Should -BeExactly (Join-Line "$Epoch`tcpu-speed`t3.1")
    }

    It 'stops, and leaves nothing beside the file, when the file cannot be replaced' {
        # The lab (Server 2022, 2026-10-23): this file, with an ACL no one could read, was never replaced, a file
        # beside it was left at each run, and the task still said it succeeded. A folder in its place stands in:
        # the writer itself must fail (Invoke-SlowFacts reads the file back, which would throw for it), and leave
        # nothing beside the file or in the folder (Move-Item moved the file into it).
        $folder = Join-Path $TestDrive 'locked'
        $null = New-Item -ItemType Directory -Path (Join-Path $folder 'slow.tsv') -Force
        Mock -ModuleName UsaBanner Get-UsaBannerWinHardware { $null }
        Mock -ModuleName UsaBanner Get-UsaBannerWinUpdates { $null }
        { InModuleScope UsaBanner -Parameters @{ Path = (Join-Path $folder 'slow.tsv'); Now = $Now } { param($Path, $Now) Write-UsaBannerSlowFacts -Path $Path -Now $Now } } | Should -Throw
        @(Get-ChildItem -LiteralPath $folder -Recurse -Force | ForEach-Object { $_.Name }) | Should -BeExactly @('slow.tsv')
    }
}

Describe 'Add-UsaBannerSlowFacts' {
    It 'fills in the CPU''s speed, the memory''s kind, each disk''s kind and the updates' {
        $facts = Add-SlowFacts "$($Epoch - 900)`tcpu-speed`t3.1", "$($Epoch - 900)`tmemory-kind`tDDR5-4800", "$($Epoch - 900)`tdisk-kind`tC:`tNVMe", "$($Epoch - 900)`tdisk-kind`tD:`tHDD", "$($Epoch - 900)`tupdates`t5`t2"
        $facts.Cpu.Text | Should -BeExactly '4 cores @ 3.1 GHz'
        $facts.Memory.Kind | Should -BeExactly 'DDR5-4800'
        @($facts.Disks | ForEach-Object { '{0} {1}' -f $_.Name, $_.Kind }) -join ', ' | Should -BeExactly 'C: NVMe, D: HDD'
        '{0}|{1}' -f $facts.Updates.Text, $facts.Updates.Level | Should -BeExactly '5 pending, 2 security|warn'
    }

    It 'takes the last line of each kind, as linux/facts.sh does' {
        $facts = Add-SlowFacts "$($Epoch - 900)`tmemory-kind`tDDR4-2933", "$($Epoch - 900)`tupdates`t5`t2", "$($Epoch - 600)`tmemory-kind`tDDR4-3200", "$($Epoch - 600)`tupdates`t4`t0"
        $facts.Memory.Kind | Should -BeExactly 'DDR4-3200'
        '{0}|{1}' -f $facts.Updates.Text, $facts.Updates.Level | Should -BeExactly '4 pending|good'
    }

    It 'passes over <Case>' -ForEach @(
        @{ Case = 'a line 24 hours old'; Line = "$($Epoch - 86400)`tmemory-kind`tDDR4-3200" }
        @{ Case = 'a line with no time'; Line = "never`tmemory-kind`tDDR4-3200" }
        @{ Case = 'a kind without its value'; Line = "$($Epoch - 900)`tmemory-kind" }
        @{ Case = 'a disk without its kind'; Line = "$($Epoch - 900)`tdisk-kind`tC:" }
        @{ Case = 'a speed that is not one'; Line = "$($Epoch - 900)`tcpu-speed`t3,1" }
        @{ Case = 'a count that is not one'; Line = "$($Epoch - 900)`tupdates`tmany`t0" }
        @{ Case = 'a count too long for a 64-bit number'; Line = "$($Epoch - 900)`tupdates`t99999999999999999999`t0" }
        @{ Case = 'a kind in capitals'; Line = "$($Epoch - 900)`tMEMORY-KIND`tDDR4-3200" }
    ) {
        $facts = Add-SlowFacts $Line
        $facts.Cpu.Text | Should -BeExactly '4 cores'
        @($facts.Memory.Kind, $facts.Disks[0].Kind, $facts.Disks[1].Kind).Where({ $null -ne $_ }).Count | Should -Be 0
        $facts.ContainsKey('Updates') | Should -BeFalse
    }

    It 'takes a time too long for a 64-bit number without an error, as awk takes it' {
        (Add-SlowFacts "99999999999999999999999`tmemory-kind`tDDR4-3200").Memory.Kind | Should -BeExactly 'DDR4-3200'
    }

    It 'leaves the facts as they are without the file' {
        $facts = InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = (Join-Path $TestDrive 'none.tsv'); Now = $Now } {
            param($Facts, $Path, $Now)
            Add-UsaBannerSlowFacts -Facts $Facts -Path $Path -Now $Now
            $Facts
        }
        $facts.Cpu.Text | Should -BeExactly '4 cores'
        $facts.Memory.Kind | Should -BeNullOrEmpty
        $facts.ContainsKey('Updates') | Should -BeFalse
    }

    It 'leaves the facts as they are, and goes on, with a file this user cannot read' {
        # The lab (Server 2022, 2026-10-23): a slow.tsv no one could read stopped every login's banner.
        $path = Join-Path $TestDrive 'unreadable.tsv'
        [System.IO.File]::WriteAllText($path, "$Epoch`tmemory-kind`tDDR4-3200`n")
        [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]::None)
        $facts = InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = $path; Now = $Now } {
            param($Facts, $Path, $Now)
            Add-UsaBannerSlowFacts -Facts $Facts -Path $Path -Now $Now
            $Facts
        }
        $facts.Memory.Kind | Should -BeNullOrEmpty
        $facts.Cpu.Text | Should -BeExactly '4 cores'
    }
}

Describe 'ConvertTo-UsaBannerCpuGhz' {
    It 'gives <Expected> for <Case>' -ForEach @(
        @{ Case = 'the recorded name, whose speed beats the 2195 MHz Windows gave'; Name = 'Intel(R) Xeon(R) Gold 6254 CPU @ 3.10GHz'; Mhz = 2195; Expected = '3.1' }
        @{ Case = 'a name with a space before GHz'; Name = 'Contoso CPU @ 2.6 GHz'; Mhz = 0; Expected = '2.6' }
        @{ Case = 'a name without a speed, from the MHz'; Name = 'Contoso 16-Core Processor'; Mhz = 3000; Expected = '3.0' }
        @{ Case = 'the MHz, to a tenth'; Name = ''; Mhz = 2195; Expected = '2.2' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Name = $Name; Mhz = $Mhz } { param($Name, $Mhz) ConvertTo-UsaBannerCpuGhz -Name $Name -Mhz $Mhz } | Should -BeExactly $Expected
    }

    It 'gives nothing without a name''s speed or the MHz' {
        InModuleScope UsaBanner { ConvertTo-UsaBannerCpuGhz -Name 'Contoso 16-Core Processor' -Mhz 0 } | Should -BeNullOrEmpty
    }

    It 'writes a decimal point in any culture' {
        Use-Culture 'de-DE' { InModuleScope UsaBanner { ConvertTo-UsaBannerCpuGhz -Name 'Contoso 16-Core Processor' -Mhz 2195 } } | Should -BeExactly '2.2'
        Use-Culture 'de-DE' { InModuleScope UsaBanner { ConvertTo-UsaBannerCpuGhz -Name 'Contoso CPU @ 3.10GHz' -Mhz 0 } } | Should -BeExactly '3.1'
    }
}

Describe 'ConvertTo-UsaBannerMemoryKind' {
    It 'gives <Expected> for <Case>' -ForEach @(
        @{ Case = 'DDR4 at its configured speed'; Module = @(@{ Type = 26; Configured = 2933; Rated = 3200 }); Expected = 'DDR4-2933' }
        @{ Case = 'DDR5 at its rated speed, none configured'; Module = @(@{ Type = 34; Configured = 0; Rated = 4800 }); Expected = 'DDR5-4800' }
        @{ Case = 'DDR3 at no speed'; Module = @(@{ Type = 24; Configured = 0; Rated = 0 }); Expected = 'DDR3' }
        @{ Case = 'LPDDR5'; Module = @(@{ Type = 35; Configured = 6400; Rated = 6400 }); Expected = 'LPDDR5-6400' }
        @{ Case = 'the first module of a known type'; Module = @(@{ Type = 2; Configured = 0; Rated = 0 }, @{ Type = 26; Configured = 3200; Rated = 3200 }); Expected = 'DDR4-3200' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Module = $Module } { param($Module) ConvertTo-UsaBannerMemoryKind -Module $Module } | Should -BeExactly $Expected
    }

    It 'gives nothing for <Case>' -ForEach @(
        @{ Case = 'the recorded Hyper-V modules, of type 2, Unknown'; Module = @(@{ Type = 2; Configured = 0; Rated = 0 }, @{ Type = 2; Configured = 0; Rated = 0 }) }
        @{ Case = 'no module'; Module = @() }
    ) {
        InModuleScope UsaBanner -Parameters @{ Module = $Module } { param($Module) ConvertTo-UsaBannerMemoryKind -Module $Module } | Should -BeNullOrEmpty
    }
}

Describe 'ConvertTo-UsaBannerDiskKind' {
    It 'gives <Expected> for media <MediaType> on a <BusType> bus' -ForEach @(
        @{ MediaType = 'SSD'; BusType = 'NVMe'; Expected = 'NVMe' }
        @{ MediaType = 'SSD'; BusType = 'SATA'; Expected = 'SSD' }
        @{ MediaType = 'HDD'; BusType = 'SAS'; Expected = 'HDD' }
        @{ MediaType = 'Unspecified'; BusType = 'USB'; Expected = 'removable' }
        @{ MediaType = 'SSD'; BusType = 'USB'; Expected = 'removable' }
        @{ MediaType = 'Unspecified'; BusType = 'SD'; Expected = 'removable' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Disk = @{ Name = 'C:'; MediaType = $MediaType; BusType = $BusType } } { param($Disk) ConvertTo-UsaBannerDiskKind -Disk $Disk } | Should -BeExactly $Expected
    }

    It 'gives nothing for the recorded Hyper-V disk, its media Unspecified on a SAS bus' {
        InModuleScope UsaBanner { ConvertTo-UsaBannerDiskKind -Disk @{ Name = 'C:'; MediaType = 'Unspecified'; BusType = 'SAS' } } | Should -BeNullOrEmpty
    }
}

Describe 'Select-UsaBannerWinDisk' {
    BeforeAll {
        function Select-Disk {
            # In:  the drives, and the MSFT_Partition and MSFT_PhysicalDisk stand-ins
            # Out: each drive Select-UsaBannerWinDisk gives, as 'name media bus'
            param([string[]]$Drive, [object[]]$Partition, [object[]]$PhysicalDisk)
            InModuleScope UsaBanner -Parameters @{ Drive = $Drive; Partition = $Partition; PhysicalDisk = $PhysicalDisk } {
                param($Drive, $Partition, $PhysicalDisk)
                Select-UsaBannerWinDisk -Drive $Drive -Partition $Partition -PhysicalDisk $PhysicalDisk | ForEach-Object { '{0} {1} {2}' -f $_.Name, $_.MediaType, $_.BusType }
            }
        }

        function New-PartitionStandIn {
            # In:  a drive letter and a disk number
            # Out: an MSFT_Partition as Get-CimInstance gives it: the letter a char, the number a UInt32
            param([char]$Letter, [uint32]$Disk)
            [pscustomobject]@{ DriveLetter = $Letter; DiskNumber = $Disk }
        }

        # MSFT_PhysicalDisk instances as Get-CimInstance gives them: the DeviceId a string, the codes numbers.
        $script:NvmeSsd = [pscustomobject]@{ DeviceId = '0'; MediaType = [uint16]4; BusType = [uint16]17 }
        $script:SataHdd = [pscustomobject]@{ DeviceId = '1'; MediaType = [uint16]3; BusType = [uint16]11 }
        $script:HyperV = [pscustomobject]@{ DeviceId = '0'; MediaType = [uint16]0; BusType = [uint16]10 }
    }

    It 'gives each fixed drive its own disk, the codes that decide a kind named: an NVMe SSD and a SATA HDD' {
        Select-Disk -Drive 'C:', 'D:' -Partition (New-PartitionStandIn 'C' 0), (New-PartitionStandIn 'D' 1) -PhysicalDisk $NvmeSsd, $SataHdd |
            Should -Be @('C: SSD NVMe', 'D: HDD 11')
    }

    It 'gives what ConvertTo-UsaBannerDiskKind reads as <Kind> for the codes <MediaType> and <BusType>' -ForEach @(
        @{ MediaType = 4; BusType = 17; Kind = 'NVMe' }
        @{ MediaType = 4; BusType = 11; Kind = 'SSD' }
        @{ MediaType = 3; BusType = 10; Kind = 'HDD' }
        @{ MediaType = 0; BusType = 7; Kind = 'removable' }
        @{ MediaType = 4; BusType = 12; Kind = 'removable' }
        @{ MediaType = 0; BusType = 13; Kind = 'removable' }
        @{ MediaType = 0; BusType = 10; Kind = '' }
    ) {
        $disk = [pscustomobject]@{ DeviceId = '0'; MediaType = [uint16]$MediaType; BusType = [uint16]$BusType }
        $found = InModuleScope UsaBanner -Parameters @{ Disk = $disk; Partition = (New-PartitionStandIn 'C' 0) } {
            param($Disk, $Partition)
            @(Select-UsaBannerWinDisk -Drive 'C:' -Partition $Partition -PhysicalDisk $Disk) | ForEach-Object { ConvertTo-UsaBannerDiskKind -Disk $_ }
        }
        "$found" | Should -BeExactly $Kind
    }

    It 'gives the recorded Hyper-V disk as its codes, which name no kind' {
        Select-Disk -Drive 'C:' -Partition (New-PartitionStandIn 'C' 0) -PhysicalDisk $HyperV | Should -Be @('C: 0 10')
    }

    It 'leaves out a drive with <Case>' -ForEach @(
        @{ Case = 'no partition of its letter'; Letters = @('D'); Disks = @(0) }
        @{ Case = 'two partitions of its letter'; Letters = @('C', 'C'); Disks = @(0, 0) }
        @{ Case = 'its partition on a disk CIM does not list'; Letters = @('C'); Disks = @(5) }
    ) {
        $partitions = @(for ($i = 0; $i -lt $Letters.Count; $i++) { New-PartitionStandIn $Letters[$i] $Disks[$i] })
        @(Select-Disk -Drive 'C:' -Partition $partitions -PhysicalDisk $NvmeSsd) | Should -BeNullOrEmpty
    }

    It 'leaves out a drive whose partition two disks claim' {
        @(Select-Disk -Drive 'C:' -Partition (New-PartitionStandIn 'C' 0) -PhysicalDisk $NvmeSsd, $HyperV) | Should -BeNullOrEmpty
    }

    It 'passes over a partition with no drive letter, as a recovery partition is' {
        Select-Disk -Drive 'C:' -Partition (New-PartitionStandIn ([char]0) 0), (New-PartitionStandIn 'C' 0) -PhysicalDisk $NvmeSsd | Should -Be @('C: SSD NVMe')
    }
}

Describe 'Test-UsaBannerVirtualHardware' {
    It 'finds <Manufacturer> <Model> <Expected>' -ForEach @(
        @{ Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine'; Expected = 'virtual' }
        @{ Manufacturer = 'QEMU'; Model = 'Standard PC (Q35 + ICH9, 2009)'; Expected = 'virtual' }
        @{ Manufacturer = 'VMware, Inc.'; Model = 'VMware7,1'; Expected = 'virtual' }
        @{ Manufacturer = 'innotek GmbH'; Model = 'VirtualBox'; Expected = 'virtual' }
        @{ Manufacturer = 'Xen'; Model = 'HVM domU'; Expected = 'virtual' }
        @{ Manufacturer = 'Microsoft Corporation'; Model = 'Surface Laptop'; Expected = 'physical' }
        @{ Manufacturer = 'Contoso'; Model = 'Contoso Rack Server'; Expected = 'physical' }
        @{ Manufacturer = ''; Model = ''; Expected = 'physical' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Manufacturer = $Manufacturer; Model = $Model } {
            param($Manufacturer, $Model)
            Test-UsaBannerVirtualHardware -Manufacturer $Manufacturer -Model $Model
        } | Should -Be ($Expected -eq 'virtual')
    }
}

Describe 'Format-UsaBannerUpdates' {
    It 'gives <Expected> for <Waiting> waiting, <Security> for security, as linux/facts.sh does' -ForEach @(
        @{ Waiting = 0; Security = 0; Expected = 'none pending|good' }
        @{ Waiting = 12; Security = 0; Expected = '12 pending|good' }
        @{ Waiting = 64; Security = 3; Expected = '64 pending, 3 security|warn' }
    ) {
        $row = InModuleScope UsaBanner -Parameters @{ Waiting = $Waiting; Security = $Security } { param($Waiting, $Security) Format-UsaBannerUpdates -Waiting $Waiting -Security $Security }
        '{0}|{1}' -f $row.Text, $row.Level | Should -BeExactly $Expected
    }
}

Describe 'Format-UsaBannerReboot' {
    It 'gives <Expected> for <Case>' -ForEach @(
        @{ Case = 'no reason'; Reason = @(); Expected = 'none pending|good' }
        @{ Case = 'servicing'; Reason = @('servicing'); Expected = 'pending: servicing|warn' }
        @{ Case = 'both reasons'; Reason = @('servicing', 'Windows Update'); Expected = 'pending: servicing, Windows Update|warn' }
    ) {
        $row = InModuleScope UsaBanner -Parameters @{ Reason = $Reason } { param($Reason) Format-UsaBannerReboot -Reason $Reason }
        '{0}|{1}' -f $row.Text, $row.Level | Should -BeExactly $Expected
    }

    It 'gives <Expected> for <Case>, the System log read' -ForEach @(
        @{ Case = 'no restart event since the boot'; Reason = @(); Restart = $null; Expected = 'none pending, none scheduled|good' }
        @{ Case = 'a restart called off (1075)'; Reason = @(); Restart = @{ Id = 1075; Time = [datetimeoffset]'2026-10-22T04:19:14-05:00'; User = 'BEVSW-APP1\Administrator' }; Expected = 'none pending, none scheduled|good' }
        @{ Case = 'a restart set (1074)'; Reason = @(); Restart = @{ Id = 1074; Time = [datetimeoffset]'2026-10-22T04:19:10-05:00'; Type = 'restart'; User = 'BEVSW-APP1\Administrator' }; Expected = 'none pending; restart set Thu 04:19 by Administrator|warn' }
        @{ Case = 'a power off set, servicing pending'; Reason = @('servicing'); Restart = @{ Id = 1074; Time = [datetimeoffset]'2026-10-22T23:05:00-05:00'; Type = 'power off'; User = 'NT AUTHORITY\SYSTEM' }; Expected = 'pending: servicing; power off set Thu 23:05 by SYSTEM|warn' }
    ) {
        $row = InModuleScope UsaBanner -Parameters @{ Reason = $Reason; Restart = $Restart } { param($Reason, $Restart) Format-UsaBannerReboot -Reason $Reason -Restart $Restart -RestartRead }
        '{0}|{1}' -f $row.Text, $row.Level | Should -BeExactly $Expected
    }
}

Describe 'the probes, run here' {
    It 'gives no hardware where CIM cannot be read' -Skip:$IsWindows {
        InModuleScope UsaBanner { Get-UsaBannerWinHardware } | Should -BeNullOrEmpty
    }

    It 'gives no update counts where there is no Windows Update agent' -Skip:$IsWindows {
        InModuleScope UsaBanner { Get-UsaBannerWinUpdates } | Should -BeNullOrEmpty
    }

    It 'finds no reboot pending where there is no registry' -Skip:$IsWindows {
        @(InModuleScope UsaBanner { Get-UsaBannerWinRebootPending -ErrorAction Stop }).Count | Should -Be 0
    }

    It 'throws where there is no System log to read restart events from' -Skip:$IsWindows {
        { InModuleScope UsaBanner { Get-UsaBannerWinRestartEvent -Since ([datetimeoffset]::Now) } } | Should -Throw -ExpectedMessage "*'Get-WinEvent'*"
    }
}
