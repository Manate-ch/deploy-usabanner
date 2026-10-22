# A Windows host's health lines (UsaBanner/Private/WindowsHealth.ps1,
# docs/DECISIONS.md D10), in the forms linux/facts.sh gives them on Linux.
# The healthy host here is made up after the lab's Server 2025 host;
# WindowsFacts.Tests.ps1 holds the two recorded hosts whole.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force

    # The services of a healthy host: the three D10 watches running, two
    # automatic services that stop by design, and a manual one stopped.
    $script:Healthy = @(
        @{ Name = 'sshd'; Status = 'Running'; StartType = '' }
        @{ Name = 'W32Time'; Status = 'Running'; StartType = '' }
        @{ Name = 'Netlogon'; Status = 'Running'; StartType = '' }
        @{ Name = 'edgeupdate'; Status = 'Stopped'; StartType = 'Automatic' }
        @{ Name = 'InventorySvc'; Status = 'Stopped'; StartType = 'Automatic' }
        @{ Name = 'Spooler'; Status = 'Stopped'; StartType = 'Manual' }
    )

    function New-Facts {
        # In:  nothing
        # Out: a healthy host's facts: two disks, the memory, no reboot pending
        # Why: each test changes one part of them
        @{
            Memory = @{ Pct = 41; Min = $null; Max = $null; Text = '6.5 of 16.0 GiB'; Kind = $null }
            Disks  = @(
                @{ Name = 'C:'; Pct = 63; Min = $null; Max = $null; Text = '80 of 127 GiB'; Kind = $null }
                @{ Name = 'D:'; Pct = 71; Min = $null; Max = $null; Text = '1.3 of 1.8 TiB'; Kind = $null }
            )
            Reboot = @{ Text = 'none pending'; Level = 'good' }
        }
    }

    function Invoke-Health {
        # In:  -Services, every service; -Triggered, the ones a trigger
        #      starts; -Time, what w32tm said; -Facts, the facts so far;
        #      -Arguments, more for Add-UsaBannerWinHealth
        # Out: the facts, filled in
        # Why: the probes read Windows; what is under test is the judging
        param(
            [AllowEmptyCollection()][System.Collections.IDictionary[]]$Services = $script:Healthy,
            [AllowEmptyCollection()][string[]]$Triggered = @(),
            [AllowNull()][System.Collections.IDictionary]$Time = @{ Answered = $true; Source = 'time.example.com,0x9' },
            [System.Collections.IDictionary]$Facts = (New-Facts),
            [hashtable]$Arguments = @{}
        )
        Mock -ModuleName UsaBanner Test-UsaBannerWinTriggerStart { $Triggered -contains $Name }
        $splat = @{ Facts = $Facts; ServiceList = $Services; TimeSource = $Time }
        foreach ($key in $Arguments.Keys) { $splat[$key] = $Arguments[$key] }
        InModuleScope UsaBanner -Parameters @{ Splat = $splat } { param($Splat) Add-UsaBannerWinHealth @Splat }
        $Facts
    }

    function Join-Problem {
        # In:  facts
        # Out: their problems, one 'level|text' each
        # Why: a test compares the problems whole
        param([System.Collections.IDictionary]$Facts)
        @(@($Facts['Problems']) | Where-Object { $_ } | ForEach-Object { '{0}|{1}' -f $_.Level, $_.Text })
    }

    function New-ServiceList {
        # In:  a service's name, and what to change of it
        # Out: the healthy host's services with that one changed, or added
        # Why: each test changes one service
        param([string]$Name, [hashtable]$Change)
        $found = $false
        $list = foreach ($service in $script:Healthy) {
            $copy = $service.Clone()
            if ($copy.Name -eq $Name) {
                $found = $true
                foreach ($key in $Change.Keys) { $copy[$key] = $Change[$key] }
            }
            $copy
        }
        if (-not $found) { $list = @($list) + @(@{ Name = $Name } + $Change) }
        , @($list)
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'Add-UsaBannerWinHealth' {
    It 'gives a healthy host all clear: each check, its services running, no problem' {
        $facts = Invoke-Health
        '{0}|{1}' -f $facts.Services.Text, $facts.Services.Level | Should -BeExactly 'sshd, W32Time running|good'
        $facts.Checked | Should -BeExactly @('auto-start', 'services', 'disks <85%', 'memory', 'clock', 'reboot')
        $facts.ContainsKey('Problems') | Should -BeFalse
    }

    It 'watches Netlogon too on a host in a domain' {
        (Invoke-Health -Arguments @{ PartOfDomain = $true }).Services.Text | Should -BeExactly 'sshd, W32Time, Netlogon running'
    }

    It 'watches <Case>' -ForEach @(
        @{ Case = 'a service stopped, as bad'; Name = 'W32Time'; Change = @{ Status = 'Stopped'; StartType = 'Manual' }; Triggered = @(); Expected = 'W32Time stopped; sshd running|bad'; Problems = @('bad|W32Time is stopped') }
        @{ Case = 'a service starting, its state in words'; Name = 'W32Time'; Change = @{ Status = 'StartPending'; StartType = 'Manual' }; Triggered = @(); Expected = 'W32Time start pending; sshd running|bad'; Problems = @('bad|W32Time is start pending') }
        @{ Case = 'a stopped service a trigger starts, as on demand'; Name = 'W32Time'; Change = @{ Status = 'Stopped'; StartType = 'Manual' }; Triggered = @('W32Time'); Expected = 'sshd running; W32Time on demand|good'; Problems = @() }
    ) {
        $facts = Invoke-Health -Services (New-ServiceList $Name $Change) -Triggered $Triggered
        '{0}|{1}' -f $facts.Services.Text, $facts.Services.Level | Should -BeExactly $Expected
        Join-Problem $facts | Should -BeExactly $Problems
    }

    It 'watches a service that is not there, as bad' {
        $facts = Invoke-Health -Services @($Healthy | Where-Object { $_.Name -ne 'W32Time' })
        '{0}|{1}' -f $facts.Services.Text, $facts.Services.Level | Should -BeExactly 'W32Time not found; sshd running|bad'
        Join-Problem $facts | Should -BeExactly @('bad|service W32Time not found')
    }

    It 'watches the services it is given, in their order, whatever their case' {
        (Invoke-Health -Arguments @{ Services = @('w32time', 'SSHD') }).Services.Text | Should -BeExactly 'w32time, SSHD running'
    }

    It 'watches none when it is given none, and names no services check' {
        $facts = Invoke-Health -Arguments @{ Services = @() }
        $facts.ContainsKey('Services') | Should -BeFalse
        $facts.Checked | Should -Not -Contain 'services'
    }

    It 'sweeps the automatic services stopped: <Case>' -ForEach @(
        @{ Case = 'one, as bad'; Add = @('ContosoAgent'); Triggered = @(); Ignore = @(); Expected = @('bad|1 automatic service stopped: ContosoAgent') }
        @{ Case = 'two, by name'; Add = @('ContosoAgent', 'ContosoSync'); Triggered = @(); Ignore = @(); Expected = @('bad|2 automatic services stopped: ContosoAgent, ContosoSync') }
        @{ Case = 'none a trigger starts'; Add = @('AppXSvc'); Triggered = @('AppXSvc'); Ignore = @(); Expected = @() }
        @{ Case = 'none the host leaves out'; Add = @('ContosoAgent'); Triggered = @(); Ignore = @('contosoagent'); Expected = @() }
        @{ Case = 'none that stop by design, nor a manual one stopped'; Add = @(); Triggered = @(); Ignore = @(); Expected = @() }
    ) {
        $list = @($Healthy) + @(foreach ($name in $Add) { @{ Name = $name; Status = 'Stopped'; StartType = 'Automatic' } })
        $facts = Invoke-Health -Services $list -Triggered $Triggered -Arguments @{ Ignore = $Ignore }
        Join-Problem $facts | Should -BeExactly $Expected
        $facts.Checked | Should -Contain 'auto-start'
    }

    It 'names no auto-start or services check when the service manager does not answer' {
        $facts = Invoke-Health -Services @()
        $facts.Checked | Should -BeExactly @('disks <85%', 'memory', 'clock', 'reboot')
        $facts.ContainsKey('Services') | Should -BeFalse
    }

    It 'reports <Case>' -ForEach @(
        @{ Case = 'a disk from 85% full, and bad from 95%'; Change = @{ Disks = @(@{ Name = 'C:'; Pct = 85 }, @{ Name = 'D:'; Pct = 96 }, @{ Name = 'E:'; Pct = 84 }) }; Time = @{ Answered = $true; Source = 'time.example.com,0x9' }; Expected = @('warn|C: is 85% full', 'bad|D: is 96% full') }
        @{ Case = 'the memory from 90% in use'; Change = @{ Memory = @{ Pct = 90 } }; Time = @{ Answered = $true; Source = 'time.example.com,0x9' }; Expected = @('warn|memory 90% in use') }
        @{ Case = 'the memory from 95%, as bad'; Change = @{ Memory = @{ Pct = 95 } }; Time = @{ Answered = $true; Source = 'time.example.com,0x9' }; Expected = @('bad|memory 95% in use') }
        @{ Case = 'the clock on the CMOS clock'; Change = @{}; Time = @{ Answered = $true; Source = 'Local CMOS Clock' }; Expected = @('warn|clock is not synchronised (source: Local CMOS Clock)') }
        @{ Case = 'the clock free-running'; Change = @{}; Time = @{ Answered = $true; Source = 'Free-running System Clock' }; Expected = @('warn|clock is not synchronised (source: Free-running System Clock)') }
        @{ Case = 'the Windows Time service not answering'; Change = @{}; Time = @{ Answered = $false; Source = $null }; Expected = @('warn|Windows Time is not answering') }
        @{ Case = 'a reboot pending'; Change = @{ Reboot = @{ Text = 'pending: servicing, Windows Update'; Level = 'warn' } }; Time = @{ Answered = $true; Source = 'time.example.com,0x9' }; Expected = @('warn|reboot pending: servicing, Windows Update') }
    ) {
        $facts = New-Facts
        foreach ($key in $Change.Keys) { $facts[$key] = $Change[$key] }
        $filled = Invoke-Health -Facts $facts -Time $Time
        Join-Problem $filled | Should -BeExactly $Expected
        $filled.Checked | Should -BeExactly @('auto-start', 'services', 'disks <85%', 'memory', 'clock', 'reboot')
    }

    It 'names no disks or memory check for facts without them' {
        (Invoke-Health -Facts @{ Reboot = @{ Text = 'none pending'; Level = 'good' } }).Checked | Should -BeExactly @('auto-start', 'services', 'clock', 'reboot')
    }

    It 'names no clock check when w32tm <Case>' -ForEach @(
        @{ Case = 'names no source it can read'; Time = @{ Answered = $true; Source = $null } }
        @{ Case = 'is not there'; Time = $null }
    ) {
        (Invoke-Health -Time $Time).Checked | Should -Not -Contain 'clock'
    }
}

Describe 'the probes, run here' {
    It 'lists no services where there is no service manager' -Skip:$IsWindows {
        @(InModuleScope UsaBanner { Get-UsaBannerWinServiceList }).Count | Should -Be 0
    }

    It 'reads no time source where there is no w32tm' -Skip:$IsWindows {
        InModuleScope UsaBanner { Get-UsaBannerWinTimeSource } | Should -BeNullOrEmpty
    }

    It 'finds no trigger where there is no registry' -Skip:$IsWindows {
        InModuleScope UsaBanner { Test-UsaBannerWinTriggerStart -Name 'sshd' -ErrorAction Stop } | Should -BeFalse
    }
}
