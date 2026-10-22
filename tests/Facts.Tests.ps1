# The facts record (docs/DECISIONS.md, D26). UsaBanner/linux/facts.sh runs
# under sh with pam_motd's empty environment against an Ubuntu 24.04.5 host
# recorded in fixtures/facts/ubuntu-2404 (its README says what was recorded
# and what was changed), the commands it runs stubbed to answer from the
# recording. Then the module reading the records. The collector's tests need
# sh and the usual tools (awk, sed, sort, timeout), so they run on Linux only.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    $script:Collector = Join-Path $repoRoot 'UsaBanner' 'linux' 'facts.sh'
    $script:Fixture = Join-Path $PSScriptRoot 'fixtures' 'facts' 'ubuntu-2404'
    $script:Log = Join-Path $TestDrive 'stubs.log'

    # The recorded host's records, as the collector prints them.
    $script:Recorded = @(
        "name`th-vsl-web1"
        "ip`t10.20.40.80"
        "os`tUbuntu 24.04.5 LTS, kernel 6.8.0-147-generic"
        "uptime`t10h 32m"
        "cpu`t0`t`t`t2 cores"
        "memory`t14`t`t`t0.5 of 3.8 GiB`t"
        "disk`t/`t6`t`t`t6 of 121 GiB`t"
        "disk`t/var`t57`t`t`t21 of 39 GiB`t"
        "sessions`t3  (admin ops)"
        "time`tThu 2026-10-22 02:18 UTC"
        "ipv4`teth0`t10.20.40.80/22"
    )

    # The stubs, first on PATH. Each logs its call to STUB_LOG and waits 5
    # seconds when STUB_SLOW names it; then it answers the one call the
    # collector makes from STUB_DATA, the recording's commands folder, and
    # fails any other. hostname and date answer for themselves: the README
    # says why.
    $script:Bin = Join-Path $TestDrive 'bin'
    $null = New-Item -ItemType Directory -Path $Bin -Force
    $head = @'
#!/bin/sh
echo "NAME $*" >>"$STUB_LOG"
case " ${STUB_SLOW-} " in *" NAME "*) sleep 5 ;; esac
'@
    $stubs = [ordered]@{
        hostname = '[ $# -eq 0 ] || exit 1; echo h-vsl-web1'
        ip       = 'case "$*" in "-4 route get 1.1.1.1") f=ip-route-get.txt ;; "-br -4 addr show scope global") f=ip-addr.txt ;; *) exit 1 ;; esac; cat "$STUB_DATA/$f"'
        uname    = '[ "$*" = -r ] || exit 1; cat "$STUB_DATA/uname-r.txt"'
        getconf  = '[ "$*" = _NPROCESSORS_ONLN ] || exit 1; cat "$STUB_DATA/getconf.txt"'
        df       = '[ "$*" = "-P -k -l -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs" ] || exit 1; cat "$STUB_DATA/df.txt"'
        who      = '[ $# -eq 0 ] || exit 1; cat "$STUB_DATA/who.txt"'
        date     = '[ "$*" = "+%a %Y-%m-%d %H:%M %Z" ] || exit 1; if [ "${LC_ALL-}" = C ]; then echo "Thu 2026-10-22 02:18 UTC"; else echo "Do 2026-10-22 02:18 UTC"; fi'
    }
    foreach ($name in $stubs.Keys) {
        $path = Join-Path $Bin $name
        [System.IO.File]::WriteAllText($path, $head.Replace('NAME', $name) + "`n" + $stubs[$name] + "`n")
        & chmod 755 $path
    }
    $script:StubPath = "$($Bin):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    function Invoke-Collector {
        # In:  the folder its files are read under, the folder its stubs
        #      answer from, and variables for the run
        # Out: its records, one string each
        # Why: pam_motd runs the login renderer with an empty environment
        param(
            [string]$Root = (Join-Path $Fixture 'root'),
            [string]$Data = (Join-Path $Fixture 'commands'),
            [hashtable]$Variables = @{}
        )
        $assignments = @("PATH=$StubPath", "USABANNER_ROOT=$Root", "STUB_DATA=$Data", "STUB_LOG=$Log")
        foreach ($key in $Variables.Keys) { $assignments += "$key=$($Variables[$key])" }
        @(& env -i @assignments sh $Collector)
    }

    function New-Variant {
        # In:  files to change, as 'root/proc/loadavg' = text; $null removes one
        # Out: the variant's Root and Data folders, for Invoke-Collector @variant
        # Why: each test changes only the part of the recording it is about
        param([hashtable]$Change)
        $copy = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Copy-Item -LiteralPath $Fixture -Destination $copy -Recurse
        foreach ($file in $Change.Keys) {
            $path = Join-Path $copy $file
            if ($null -eq $Change[$file]) {
                Remove-Item -LiteralPath $path
                continue
            }
            $null = New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force
            [System.IO.File]::WriteAllText($path, $Change[$file])
        }
        @{ Root = Join-Path $copy 'root'; Data = Join-Path $copy 'commands' }
    }

    function Select-Record {
        # In:  records, and a kind
        # Out: that kind's records as one string, a line each
        # Why: a test compares one kind's records whole
        param([string[]]$Records, [string]$Kind)
        @($Records | Where-Object { $_.StartsWith("$Kind`t") }) -join "`n"
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'linux/facts.sh' -Skip:$IsWindows {
    BeforeEach { [System.IO.File]::WriteAllText($Log, '') }

    It 'is sh that sh -n accepts' {
        & sh -n $Collector
        $LASTEXITCODE | Should -Be 0
    }

    It 'finds each stub first on PATH (else the tests below prove nothing)' {
        $found = @(& env -i "PATH=$StubPath" sh -c 'for c in hostname ip uname getconf df who date; do command -v "$c"; done')
        $found | Should -BeExactly @(foreach ($name in 'hostname', 'ip', 'uname', 'getconf', 'df', 'who', 'date') { Join-Path $Bin $name })
    }

    It 'gives the recorded Ubuntu 24.04.5 host''s records, in order' {
        (Invoke-Collector) -join "`n" | Should -BeExactly ($Recorded -join "`n")
    }

    It 'asks hostname for the kernel''s name alone, never a DNS lookup, when no name is cached' {
        $null = Invoke-Collector
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -like 'hostname*' }) | Should -BeExactly @('hostname ')
    }

    It 'takes the name the periodic job cached, and then runs no hostname' {
        $variant = New-Variant @{ 'root/var/lib/usabanner/fqdn' = "h-vsl-web1.ad.example`n" }
        Select-Record (Invoke-Collector @variant) name | Should -BeExactly "name`th-vsl-web1.ad.example"
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -like 'hostname*' }).Count | Should -Be 0
    }

    It 'takes <Case>' -ForEach @(
        @{ Case = 'the primary address from the route out'; Change = @{ 'commands/ip-addr.txt' = "ens192           UP             10.20.60.15/24`neth0             UP             10.20.40.80/22`n" }; Expected = "ip`t10.20.40.80" }
        @{ Case = 'the first adapter''s address without a route out'; Change = @{ 'commands/ip-route-get.txt' = $null; 'commands/ip-addr.txt' = "ens192           UP             10.20.60.15/24`neth0             UP             10.20.40.80/22`n" }; Expected = "ip`t10.20.60.15" }
    ) {
        $variant = New-Variant $Change
        Select-Record (Invoke-Collector @variant) ip | Should -BeExactly $Expected
    }

    It 'leaves out the adapters USABANNER_IFACE_HIDE matches: <Case>' -ForEach @(
        @{ Case = 'container bridges and tunnels by default'; Variables = @{}; Expected = 'eth0' }
        @{ Case = 'none when it is empty'; Variables = @{ USABANNER_IFACE_HIDE = '' }; Expected = 'eth0,docker0' }
        @{ Case = 'its own pattern'; Variables = @{ USABANNER_IFACE_HIDE = '^eth' }; Expected = 'docker0' }
    ) {
        @((Select-Record (Invoke-Collector -Variables $Variables) ipv4) -split "`n" | ForEach-Object { ($_ -split "`t")[1] }) -join ',' | Should -BeExactly $Expected
    }

    It 'reads the OS from os-release: <Case>' -ForEach @(
        @{ Case = 'in single quotes'; Change = @{ 'root/etc/os-release' = "PRETTY_NAME='Contoso Linux 9 (Example)'`nID=contoso`n" }; Expected = 'Contoso Linux 9 (Example)' }
        @{ Case = 'without quotes'; Change = @{ 'root/etc/os-release' = "ID=contoso`nPRETTY_NAME=Contoso`n" }; Expected = 'Contoso' }
        @{ Case = 'the first of two'; Change = @{ 'root/etc/os-release' = "PRETTY_NAME=`"Contoso Linux 9`"`nPRETTY_NAME=`"Contoso Linux 10`"`n" }; Expected = 'Contoso Linux 9' }
        @{ Case = 'from /usr/lib without /etc/os-release'; Change = @{ 'root/etc/os-release' = $null; 'root/usr/lib/os-release' = "PRETTY_NAME=`"Contoso Linux 9`"`n" }; Expected = 'Contoso Linux 9' }
        @{ Case = 'as Linux with neither file'; Change = @{ 'root/etc/os-release' = $null }; Expected = 'Linux' }
    ) {
        $variant = New-Variant $Change
        Select-Record (Invoke-Collector @variant) os | Should -BeExactly "os`t$Expected, kernel 6.8.0-147-generic"
    }

    It 'reads os-release as text, never running it' {
        $marker = Join-Path $TestDrive 'os-release-ran'
        $variant = New-Variant @{ 'root/etc/os-release' = "PRETTY_NAME=`"Contoso `$(touch $marker)`"`n" }
        Select-Record (Invoke-Collector @variant) os | Should -BeExactly "os`tContoso `$(touch $marker), kernel 6.8.0-147-generic"
        Test-Path -LiteralPath $marker | Should -BeFalse
    }

    It 'gives the uptime <Case>' -ForEach @(
        @{ Case = 'of 12 days in days'; Uptime = "1060800.99 2000000.00`n"; Expected = "uptime`t12d 6h 40m" }
        @{ Case = 'of a day exactly in days'; Uptime = "86400.00 170000.00`n"; Expected = "uptime`t1d 0h 0m" }
        @{ Case = 'of a minute in hours and minutes'; Uptime = "60.50 100.00`n"; Expected = "uptime`t0h 1m" }
        @{ Case = 'from a file it cannot read as none, and goes on'; Uptime = "up a while`n"; Expected = '' }
    ) {
        $variant = New-Variant @{ 'root/proc/uptime' = $Uptime }
        $records = Invoke-Collector @variant
        Select-Record $records uptime | Should -BeExactly $Expected
        Select-Record $records time | Should -Not -BeNullOrEmpty
    }

    It 'gives the 1-minute load as a share of the online CPUs: <Case>' -ForEach @(
        @{ Case = 'two, rounded'; Cores = "2`n"; Load = "0.09 0.05 0.01 1/180 900`n"; Expected = "cpu`t5`t`t`t2 cores" }
        @{ Case = 'one, past 100'; Cores = "1`n"; Load = "1.23 0.50 0.20 1/180 900`n"; Expected = "cpu`t123`t`t`t1 core" }
        @{ Case = 'an unknown count, none'; Cores = $null; Load = "0.09 0.05 0.01 1/180 900`n"; Expected = '' }
    ) {
        $variant = New-Variant @{ 'commands/getconf.txt' = $Cores; 'root/proc/loadavg' = $Load }
        Select-Record (Invoke-Collector @variant) cpu | Should -BeExactly $Expected
    }

    It 'counts the online CPUs with getconf, which OMP_NUM_THREADS does not change' {
        Select-Record (Invoke-Collector -Variables @{ OMP_NUM_THREADS = '1' }) cpu | Should -BeExactly "cpu`t0`t`t`t2 cores"
    }

    It 'gives the memory in use as free counts it, the percentage cut: <Case>' -ForEach @(
        @{ Case = 'just under 50%'; MemInfo = "MemTotal:        1048576 kB`nMemFree:          100000 kB`nMemAvailable:     524812 kB`n"; Expected = "memory`t49`t`t`t0.5 of 1.0 GiB`t" }
        @{ Case = 'none without MemAvailable'; MemInfo = "MemTotal:        1048576 kB`nMemFree:          100000 kB`n"; Expected = '' }
    ) {
        $variant = New-Variant @{ 'root/proc/meminfo' = $MemInfo }
        Select-Record (Invoke-Collector @variant) memory | Should -BeExactly $Expected
    }

    It 'gives each local filesystem but /boot and below, / first, in TiB, whole GiB or tenths of one' {
        $df = @(
            'Filesystem          1024-blocks       Used  Available Capacity Mounted on'
            '/dev/sdc1            2147483648 1288490189  858993459      60% /srv/data'
            '/dev/sdd1               5242880    1048576    4194304      20% /mnt/small disk'
            '/dev/sda2               1992552     205764    1665548      11% /boot'
            '/dev/mapper/vg-root    31457280   15728640   14155776      53% /'
            'tank/empty                    0          0          0       - /mnt/empty'
        )
        $variant = New-Variant @{ 'commands/df.txt' = ($df -join "`n") + "`n" }
        Select-Record (Invoke-Collector @variant) disk | Should -BeExactly (@(
                "disk`t/`t53`t`t`t15 of 30 GiB`t"
                "disk`t/mnt/small disk`t20`t`t`t1.0 of 5.0 GiB`t"
                "disk`t/srv/data`t60`t`t`t1.2 of 2.0 TiB`t"
            ) -join "`n")
    }

    It 'keeps a field from splitting its record: a tab becomes a space, a control character goes' {
        $variant = New-Variant @{ 'root/var/lib/usabanner/fqdn' = "h-vsl-web1`tad$([char]27).example$([char]127)`n" }
        Select-Record (Invoke-Collector @variant) name | Should -BeExactly "name`th-vsl-web1 ad.example"
    }

    It 'counts the sessions who lists: <Case>' -ForEach @(
        @{ Case = 'none'; Who = ''; Expected = "sessions`t0" }
        @{ Case = 'none given when who fails'; Who = $null; Expected = '' }
    ) {
        $variant = New-Variant @{ 'commands/who.txt' = $Who }
        Select-Record (Invoke-Collector @variant) sessions | Should -BeExactly $Expected
    }

    It 'gives the weekday in English whatever the locale' {
        Select-Record (Invoke-Collector -Variables @{ LC_ALL = 'C.UTF-8'; LANG = 'C.UTF-8' }) time | Should -BeExactly "time`tThu 2026-10-22 02:18 UTC"
    }

    It 'cuts <Command> off after 2 seconds, and gives no <Kind> record' -ForEach @(
        @{ Command = 'who'; Kind = 'sessions'; Limit = 4.5 }
        @{ Command = 'df'; Kind = 'disk'; Limit = 4.5 }
        @{ Command = 'ip'; Kind = 'ipv4'; Limit = 8.5 }
    ) {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $records = Invoke-Collector -Variables @{ STUB_SLOW = $Command }
        $watch.Stop()
        Select-Record $records $Kind | Should -BeNullOrEmpty
        Select-Record $records time | Should -Not -BeNullOrEmpty
        $watch.Elapsed.TotalSeconds | Should -BeLessThan $Limit
    }

    It 'gives no record for a fact it cannot read, and still exits 0' {
        $empty = Join-Path $TestDrive 'empty'
        $null = New-Item -ItemType Directory -Path $empty -Force
        $records = Invoke-Collector -Root $empty -Data $empty
        $LASTEXITCODE | Should -Be 0
        $records -join "`n" | Should -BeExactly ("name`th-vsl-web1", "os`tLinux", "time`tThu 2026-10-22 02:18 UTC" -join "`n")
    }
}

Describe 'ConvertFrom-UsaBannerFactRecord' {
    It 'reads the recorded host''s records as the facts the banner draws' {
        $facts = InModuleScope UsaBanner -Parameters @{ Lines = $Recorded } { param($Lines) ConvertFrom-UsaBannerFactRecord -Line $Lines }
        @($facts.Keys | Sort-Object) | Should -BeExactly @('Cpu', 'Disks', 'Ip', 'Ipv4', 'Memory', 'Name', 'Os', 'Sessions', 'Time', 'Uptime')
        $facts.Name | Should -BeExactly 'h-vsl-web1'
        $facts.Ip | Should -BeExactly '10.20.40.80'
        $facts.Os | Should -BeExactly 'Ubuntu 24.04.5 LTS, kernel 6.8.0-147-generic'
        $facts.Uptime | Should -BeExactly '10h 32m'
        $facts.Cpu.Now | Should -BeOfType [int]
        $facts.Cpu.Now | Should -Be 0
        $facts.Cpu.Min | Should -BeNullOrEmpty
        $facts.Cpu.Max | Should -BeNullOrEmpty
        $facts.Cpu.Text | Should -BeExactly '2 cores'
        $facts.Memory.Pct | Should -Be 14
        $facts.Memory.Text | Should -BeExactly '0.5 of 3.8 GiB'
        $facts.Memory.Kind | Should -BeNullOrEmpty
        @($facts.Disks).Count | Should -Be 2
        $facts.Disks[0].Name | Should -BeExactly '/'
        $facts.Disks[0].Pct | Should -Be 6
        $facts.Disks[0].Text | Should -BeExactly '6 of 121 GiB'
        $facts.Disks[1].Name | Should -BeExactly '/var'
        $facts.Disks[1].Pct | Should -Be 57
        $facts.Sessions | Should -BeExactly '3  (admin ops)'
        $facts.Time | Should -BeExactly 'Thu 2026-10-22 02:18 UTC'
        @($facts.Ipv4).Count | Should -Be 1
        $facts.Ipv4[0].Name | Should -BeExactly 'eth0'
        $facts.Ipv4[0].Address | Should -BeExactly '10.20.40.80/22'
    }

    It 'passes over an empty line and a kind it does not know' {
        $facts = InModuleScope UsaBanner { ConvertFrom-UsaBannerFactRecord -Line @("name`tcwpql-db2", '', "gpu`t3`tContoso X1") }
        @($facts.Keys) | Should -BeExactly @('Name')
        $facts.Name | Should -BeExactly 'cwpql-db2'
    }

    It 'gives $null for an empty field, and for a percentage that is not a whole number' {
        $facts = InModuleScope UsaBanner { ConvertFrom-UsaBannerFactRecord -Line @("cpu`t`t`t`t", "memory`t12.5`t3`t40`t1.0 of 8.0 GiB`tDDR5", "uptime`t") }
        $facts.Cpu.Now | Should -BeNullOrEmpty
        $facts.Cpu.Text | Should -BeNullOrEmpty
        $facts.Memory.Pct | Should -BeNullOrEmpty
        $facts.Memory.Min | Should -Be 3
        $facts.Memory.Max | Should -Be 40
        $facts.Memory.Kind | Should -BeExactly 'DDR5'
        $facts.ContainsKey('Uptime') | Should -BeTrue
        $facts.Uptime | Should -BeNullOrEmpty
    }
}

Describe 'Get-UsaBannerHostFacts' {
    It 'runs the collector and reads its records' -Skip:$IsWindows {
        $environment = @{ PATH = $StubPath; USABANNER_ROOT = (Join-Path $Fixture 'root'); STUB_DATA = (Join-Path $Fixture 'commands'); STUB_LOG = $Log }
        $facts = InModuleScope UsaBanner -Parameters @{ Variables = $environment } { param($Variables) Get-UsaBannerHostFacts -OnWindows $false -Environment $Variables }
        $facts.Name | Should -BeExactly 'h-vsl-web1'
        $facts.Cpu.Text | Should -BeExactly '2 cores'
        @($facts.Disks.Name) -join ',' | Should -BeExactly '/,/var'
        @($facts.Ipv4.Name) -join ',' | Should -BeExactly 'eth0'
    }

    It 'names the host itself when the records give no name' -Skip:$IsWindows {
        $nameless = Join-Path $TestDrive 'nameless.sh'
        [System.IO.File]::WriteAllText($nameless, "printf 'uptime\t1h 2m\n'`n")
        $facts = InModuleScope UsaBanner -Parameters @{ Path = $nameless } { param($Path) Get-UsaBannerHostFacts -OnWindows $false -Collector $Path }
        $facts.Name | Should -BeExactly ([Environment]::MachineName)
        $facts.Uptime | Should -BeExactly '1h 2m'
    }

    It 'reads a Windows host''s facts in the module, running no collector' {
        $marker = Join-Path $TestDrive 'collector-ran'
        $marking = Join-Path $TestDrive 'marking.sh'
        [System.IO.File]::WriteAllText($marking, "touch '$marker'`n")
        Mock -ModuleName UsaBanner Get-UsaBannerWindowsFacts { @{ Name = 'BEVSW-APP1'; Uptime = '13d 1h 59m' } }
        $facts = InModuleScope UsaBanner -Parameters @{ Path = $marking } { param($Path) Get-UsaBannerHostFacts -OnWindows $true -Collector $Path }
        $facts.Name | Should -BeExactly 'BEVSW-APP1'
        $facts.Uptime | Should -BeExactly '13d 1h 59m'
        Should -Invoke Get-UsaBannerWindowsFacts -ModuleName UsaBanner -Times 1 -Exactly
        Test-Path -LiteralPath $marker | Should -BeFalse
    }
}
