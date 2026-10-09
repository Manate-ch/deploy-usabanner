# Pester 5 tests for the probes Get-ManatechHostFact makes (ManatechBanner.psm1),
# as far as they run off Windows: the CPU arithmetic, the .NET network probes,
# a CPU % that could not be measured, and the services that stop by design.
# The probes as a whole are timed on a host with Measure-ManatechBanner.ps1.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../ManatechBanner.psm1') -Force
    $script:Data = Join-Path $PSScriptRoot '../../rootfs/usr/local/share/manatech'
    $script:Esc = [string][char]27
    # Sample SAMPLE IDLE CLOCK OWN - a CPU sample as Get-ManatechCpuSample returns one.
    function New-Sample { param([double]$Idle, [double]$Clock, [double]$Own = 0) @{ Idle = $Idle; Clock = $Clock; Own = $Own } }
}

Describe 'Get-ManatechCpuPct' {
    It 'is the busy share of the window: idle 98.4% of it is 2% busy' {
        InModuleScope ManatechBanner -Parameters @{ From = (New-Sample 0 0); To = (New-Sample 984 1000) } {
            Get-ManatechCpuPct -From $From -To $To -Cores 4 | Should -Be 2
        }
    }
    It 'leaves out what the banner itself used: half busy, a quarter of it the banner, on 4 cores' {
        InModuleScope ManatechBanner -Parameters @{ From = (New-Sample 0 0 0); To = (New-Sample 500 1000 1000) } {
            Get-ManatechCpuPct -From $From -To $To -Cores 4 | Should -Be 25
        }
    }
    It 'never goes below 0 or above 100' {
        InModuleScope ManatechBanner -Parameters @{ From = (New-Sample 0 0 0); To = (New-Sample 1000 1000 4000) } {
            Get-ManatechCpuPct -From $From -To $To -Cores 4 | Should -Be 0
        }
        InModuleScope ManatechBanner -Parameters @{ From = (New-Sample 0 0); To = (New-Sample -50 1000) } {
            Get-ManatechCpuPct -From $From -To $To -Cores 4 | Should -Be 100
        }
    }
    It 'is $null without two samples or without time between them' {
        InModuleScope ManatechBanner -Parameters @{ S = (New-Sample 5 5) } {
            Get-ManatechCpuPct -From $null -To $S -Cores 4 | Should -BeNullOrEmpty
            Get-ManatechCpuPct -From $S -To $S -Cores 4 | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-ManatechInterface and Get-ManatechPrimaryIp (.NET, so they run here too)' {
    It 'lists each up interface with its IPv4 addresses as a/n, never loopback or link-local' {
        $nics = @(InModuleScope ManatechBanner { Get-ManatechInterface })
        $nics.Count | Should -BeGreaterThan 0
        foreach ($n in $nics) {
            $n.Name | Should -Not -BeNullOrEmpty
            $n.Address | Should -Match '^(\d{1,3}\.){3}\d{1,3}/\d{1,2}( (\d{1,3}\.){3}\d{1,3}/\d{1,2})*$'
            $n.Address | Should -Not -Match '(^| )(127\.|169\.254\.)'
        }
    }
    It 'leaves out interfaces whose name matches the hide pattern' {
        $first = @(InModuleScope ManatechBanner { Get-ManatechInterface })[0].Name
        $hidden = @(InModuleScope ManatechBanner -Parameters @{ Hide = ('^' + [regex]::Escape($first) + '$') } { Get-ManatechInterface -Hide $Hide })
        @($hidden | Where-Object { $_.Name -eq $first }).Count | Should -Be 0
    }
    It 'gives the default route''s source address, or nothing, without throwing' {
        $ip = InModuleScope ManatechBanner { Get-ManatechPrimaryIp }
        if ($ip) { $ip | Should -Match '^(\d{1,3}\.){3}\d{1,3}$' } else { $ip | Should -BeExactly '' }
    }
}

Describe 'Format-ManatechBanner with a CPU % that could not be measured' {
    It 'shows a dash instead of a number' {
        $fact = @{
            HostName = 'h-vsw-example1.ad.example'; PrimaryIp = ''; Os = 'Windows Server 2025 Standard, build 26100.1'
            Uptime = [timespan]::new(3, 4, 12, 0); CpuPct = $null; Cores = 8
            MemPct = 41; MemText = '6.5 of 16.0 GiB'; DiskName = 'C:'; DiskPct = 63; DiskText = '80G of 127G'
            Sessions = '0  ()'; Time = 'Sat 2026-10-03 09:00 UTC-05:00'; Ipv4 = @(); Problems = @(); Checked = @('reboot')
        }
        $config = Get-ManatechConfig -DataPath $TestDrive
        $config.Color = 'none'
        $text = (Format-ManatechBanner -Fact $fact -Config $config -DataPath $Data) -join "`n"
        $text | Should -Match 'cpu - / 8 cores'
    }
}

Describe 'services that stop by design' {
    It 'are ignored on every host, InventorySvc among them, on top of an empty ServiceIgnore by default' {
        (Get-ManatechConfig -DataPath $TestDrive).ServiceIgnore | Should -BeNullOrEmpty
        InModuleScope ManatechBanner { $script:ServiceStopsByDesign } | Should -Contain 'InventorySvc'
    }
}
