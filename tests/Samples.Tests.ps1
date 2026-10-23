# The 24-hour range on Windows (UsaBanner/Private/Samples.ps1,
# docs/DECISIONS.md D17): the module's samples file, in the form
# linux/sample.sh writes, and the range it fills in. Facts.Tests.ps1 reads
# one samples file with both this module and linux/facts.sh.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    $script:Epoch = 1792635480
    $script:Now = [datetimeoffset]::FromUnixTimeSeconds($Epoch)

    function New-Facts {
        # In:  nothing
        # Out: a Windows host's facts with a CPU, memory and two disks
        # Why: each test samples or widens the same host
        @{
            Name   = 'BEVSW-APP1'
            Cpu    = @{ Now = 12; Min = $null; Max = $null; Text = '4 cores' }
            Memory = @{ Pct = 41; Min = $null; Max = $null; Text = '6.5 of 16.0 GiB'; Kind = $null }
            Disks  = @(
                @{ Name = 'C:'; Pct = 63; Min = $null; Max = $null; Text = '80 of 127 GiB'; Kind = $null }
                @{ Name = 'D:'; Pct = 71; Min = $null; Max = $null; Text = '1.3 of 1.8 TiB'; Kind = $null }
            )
        }
    }

    function Write-Samples {
        # In:  a file, and its lines
        # Out: nothing; the file holds the lines, each ending in LF
        # Why: the samples file is LF-ended on every OS
        param([string]$Path, [string[]]$Line)
        [System.IO.File]::WriteAllText($Path, (($Line -join "`n") + "`n"))
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'Add-UsaBannerSample' {
    It 'adds the CPU, the memory and each disk with the time, and keeps the last 24 hours' {
        $path = Join-Path $TestDrive 'kept.tsv'
        Write-Samples $path "$($Epoch - 86400)`tcpu`t99", "$($Epoch - 86399)`tcpu`t3", 'not a sample'
        InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = $path; Now = $Now } { param($Facts, $Path, $Now) Add-UsaBannerSample -Facts $Facts -Path $Path -Now $Now }
        [System.IO.File]::ReadAllText($path) | Should -BeExactly ((@(
                    "$($Epoch - 86399)`tcpu`t3"
                    "$Epoch`tcpu`t12"
                    "$Epoch`tmemory`t41"
                    "$Epoch`tdisk`tC:`t63"
                    "$Epoch`tdisk`tD:`t71"
                ) -join "`n") + "`n")
    }

    It 'makes its folder, and leaves no other file behind' {
        $folder = Join-Path $TestDrive 'ProgramData' 'UsagiTools' 'Banner'
        InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = (Join-Path $folder 'samples.tsv'); Now = $Now } { param($Facts, $Path, $Now) Add-UsaBannerSample -Facts $Facts -Path $Path -Now $Now }
        @(Get-ChildItem -LiteralPath $folder -Force | ForEach-Object { $_.Name }) | Should -BeExactly @('samples.tsv')
    }

    It 'stops, and leaves nothing beside the file, when the file cannot be replaced' {
        # The lab (Server 2022, 2026-10-23): a slow.tsv no one could read was never replaced, a file beside it was
        # left at each run, and the task still said it succeeded. A folder in the file's place stands in for it.
        $folder = Join-Path $TestDrive 'locked'
        $null = New-Item -ItemType Directory -Path (Join-Path $folder 'samples.tsv') -Force
        { InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = (Join-Path $folder 'samples.tsv'); Now = $Now } { param($Facts, $Path, $Now) Add-UsaBannerSample -Facts $Facts -Path $Path -Now $Now } } | Should -Throw
        # Recurse: Move-Item moved the file into the folder that stands in.
        @(Get-ChildItem -LiteralPath $folder -Recurse -Force | ForEach-Object { $_.Name }) | Should -BeExactly @('samples.tsv')
    }

    It 'leaves out a fact without a percentage' {
        $facts = New-Facts
        $facts.Cpu.Now = $null
        $facts.Remove('Memory')
        $path = Join-Path $TestDrive 'some.tsv'
        InModuleScope UsaBanner -Parameters @{ Facts = $facts; Path = $path; Now = $Now } { param($Facts, $Path, $Now) Add-UsaBannerSample -Facts $Facts -Path $Path -Now $Now }
        [System.IO.File]::ReadAllText($path) | Should -BeExactly "$Epoch`tdisk`tC:`t63`n$Epoch`tdisk`tD:`t71`n"
    }
}

Describe 'Add-UsaBannerSampleRange' {
    It 'fills min and max from the samples of the last 24 hours, the value now included' {
        $path = Join-Path $TestDrive 'range.tsv'
        Write-Samples $path @(
            "$($Epoch - 86400)`tcpu`t99"
            "$($Epoch - 86399)`tcpu`t3"
            "$($Epoch - 900)`tcpu`t71"
            "$($Epoch - 900)`tmemory`t20"
            "$($Epoch - 1800)`tmemory`t10"
            "$($Epoch - 900)`tdisk`tC:`t60"
            "$($Epoch - 1800)`tdisk`tC:`t50"
            "$($Epoch - 900)`tdisk`tE:`t90"
        )
        $facts = InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = $path; Now = $Now } {
            param($Facts, $Path, $Now)
            Add-UsaBannerSampleRange -Facts $Facts -Path $Path -Now $Now
            $Facts
        }
        '{0}-{1}' -f $facts.Cpu.Min, $facts.Cpu.Max | Should -BeExactly '3-71'
        '{0}-{1}' -f $facts.Memory.Min, $facts.Memory.Max | Should -BeExactly '10-41'
        '{0}-{1}' -f $facts.Disks[0].Min, $facts.Disks[0].Max | Should -BeExactly '50-63'
        $facts.Disks[1].Min | Should -BeNullOrEmpty
        $facts.Disks[1].Max | Should -BeNullOrEmpty
    }

    It 'passes over a line that is not a sample' {
        $path = Join-Path $TestDrive 'junk.tsv'
        Write-Samples $path 'not a sample', "$($Epoch - 900)`tcpu`tlots", "$($Epoch - 900)`tmemory", "soon`tcpu`t50", "$($Epoch - 900)`tdisk`tC:"
        $facts = InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = $path; Now = $Now } {
            param($Facts, $Path, $Now)
            Add-UsaBannerSampleRange -Facts $Facts -Path $Path -Now $Now
            $Facts
        }
        @($facts.Cpu.Min, $facts.Cpu.Max, $facts.Memory.Min, $facts.Memory.Max, $facts.Disks[0].Min, $facts.Disks[0].Max).Where({ $null -ne $_ }).Count | Should -Be 0
    }

    It 'leaves the facts as they were without a samples file' {
        $facts = InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = (Join-Path $TestDrive 'none.tsv'); Now = $Now } {
            param($Facts, $Path, $Now)
            Add-UsaBannerSampleRange -Facts $Facts -Path $Path -Now $Now
            $Facts
        }
        @($facts.Cpu.Min, $facts.Cpu.Max, $facts.Memory.Min, $facts.Memory.Max).Where({ $null -ne $_ }).Count | Should -Be 0
    }

    It 'leaves the facts as they were, and goes on, with a samples file this user cannot read' {
        # The lab (Server 2022, 2026-10-23): a job file no one could read stopped every login's banner.
        $path = Join-Path $TestDrive 'unreadable.tsv'
        Write-Samples $path "$($Epoch - 600)`tcpu`t3"
        [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]::None)
        $facts = InModuleScope UsaBanner -Parameters @{ Facts = (New-Facts); Path = $path; Now = $Now } {
            param($Facts, $Path, $Now)
            Add-UsaBannerSampleRange -Facts $Facts -Path $Path -Now $Now
            $Facts
        }
        @($facts.Cpu.Min, $facts.Cpu.Max, $facts.Memory.Min, $facts.Memory.Max).Where({ $null -ne $_ }).Count | Should -Be 0
    }
}

Describe 'Get-UsaBannerDataPath' {
    It 'keeps the banner''s files in /var/lib/usabanner on Linux' {
        InModuleScope UsaBanner { Get-UsaBannerDataPath -Name 'samples.tsv' -OnWindows $false } | Should -BeExactly '/var/lib/usabanner/samples.tsv'
    }

    It 'keeps them under ProgramData on Windows' {
        $saved = $env:ProgramData
        try {
            $env:ProgramData = 'X:\Data'
            InModuleScope UsaBanner { Get-UsaBannerDataPath -Name 'samples.tsv' -OnWindows $true } | Should -Match '^X:\\Data[\\/]UsagiTools[\\/]Banner[\\/]samples\.tsv$'
        }
        finally { $env:ProgramData = $saved }
    }
}

Describe 'Update-UsaBannerSample' {
    It 'adds this Windows host''s sample to the samples file, its range read from the same file, then writes its slow facts' {
        Mock -ModuleName UsaBanner Get-UsaBannerWindowsFacts { New-Facts }
        $samplesFile = Join-Path $TestDrive 'job' 'samples.tsv'
        $sampledFirst = [System.Collections.Generic.List[bool]]::new()
        Mock -ModuleName UsaBanner Write-UsaBannerSlowFacts { $sampledFirst.Add((Test-Path -LiteralPath $samplesFile)) }
        InModuleScope UsaBanner -Parameters @{ Path = $samplesFile; SlowPath = (Join-Path $TestDrive 'job' 'slow.tsv'); Now = $Now } {
            param($Path, $SlowPath, $Now)
            Update-UsaBannerSample -Path $Path -SlowPath $SlowPath -Now $Now
        }
        [System.IO.File]::ReadAllText($samplesFile) | Should -BeExactly ((@("$Epoch`tcpu`t12", "$Epoch`tmemory`t41", "$Epoch`tdisk`tC:`t63", "$Epoch`tdisk`tD:`t71") -join "`n") + "`n")
        Should -Invoke Get-UsaBannerWindowsFacts -ModuleName UsaBanner -Times 1 -Exactly -ParameterFilter { $SamplePath -like '*job*samples.tsv' -and $SlowPath -like '*job*slow.tsv' }
        Should -Invoke Write-UsaBannerSlowFacts -ModuleName UsaBanner -Times 1 -Exactly -ParameterFilter { $Path -like '*job*slow.tsv' -and $Now.ToUnixTimeSeconds() -eq 1792635480 }
        $sampledFirst | Should -BeExactly @($true)
    }
}
