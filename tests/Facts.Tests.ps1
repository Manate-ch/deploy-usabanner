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
        "cpu`t0`t`t`t2 cores @ 3.1 GHz"
        "memory`t14`t`t`t0.5 of 3.8 GiB`t"
        "disk`t/`t6`t`t`t6 of 121 GiB`t"
        "disk`t/var`t57`t`t`t21 of 39 GiB`t"
        "reboot`tnone pending, none scheduled`tgood"
        "sessions`t3  (admin ops)"
        "time`tThu 2026-10-22 02:18 UTC"
        "ipv4`teth0`t10.20.40.80/22"
        "problem`tbad`t4 failed units: hv-fcopy-daemon.service, hv-kvp-daemon.service, hv-vss-daemon.service, contoso-motd-update.service"
        "check`tunits"
        "services`tssh, cron, ntpsec, sssd active; adsysd on demand`tgood"
        "check`tservices"
        "check`tdisks <85%"
        "check`tmemory"
        "check`tclock"
        "check`treboot"
    )

    # The stubs, first on PATH. Each logs its call to STUB_LOG and waits 5
    # seconds when STUB_SLOW names it; then it answers the one call the
    # collector makes from STUB_DATA, the recording's commands folder, and
    # fails any other. hostname and date answer for themselves: the README
    # says why. hostname -f, which only the periodic job asks, answers from
    # hostname-f.txt when a test writes one, after 8 seconds when
    # STUB_SLOW_FQDN is set; date +%s is 2026-10-22 02:18 UTC, and date -d is
    # the real one in UTC. lsblk answers for a device from lsblk<device>.txt,
    # its slashes as underscores. systemctl answers show from units/<unit>, a
    # block per unit asked, with only the properties asked, and for a unit not
    # there as systemd does for one it cannot find; without a units folder it
    # fails, as where there is no systemd.
    $script:Bin = Join-Path $TestDrive 'bin'
    $null = New-Item -ItemType Directory -Path $Bin -Force
    $head = @'
#!/bin/sh
echo "NAME $*" >>"$STUB_LOG"
case " ${STUB_SLOW-} " in *" NAME "*) sleep 5 ;; esac
'@
    $stubs = [ordered]@{
        hostname = 'case "$*" in "") echo h-vsl-web1 ;; -f) [ -n "${STUB_SLOW_FQDN-}" ] && sleep 8; cat "$STUB_DATA/hostname-f.txt" ;; *) exit 1 ;; esac'
        ip       = 'case "$*" in "-4 route get 1.1.1.1") f=ip-route-get.txt ;; "-br -4 addr show scope global") f=ip-addr.txt ;; *) exit 1 ;; esac; cat "$STUB_DATA/$f"'
        uname    = '[ "$*" = -r ] || exit 1; cat "$STUB_DATA/uname-r.txt"'
        getconf  = '[ "$*" = _NPROCESSORS_ONLN ] || exit 1; cat "$STUB_DATA/getconf.txt"'
        df       = '[ "$*" = "-P -k -l -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs" ] || exit 1; cat "$STUB_DATA/df.txt"'
        who      = '[ $# -eq 0 ] || exit 1; cat "$STUB_DATA/who.txt"'
        date     = 'case "$*" in "+%s") echo 1792635480 ;; "+%a %Y-%m-%d %H:%M %Z") if [ "${LC_ALL-}" = C ]; then echo "Thu 2026-10-22 02:18 UTC"; else echo "Do 2026-10-22 02:18 UTC"; fi ;; "-d @"*" +%a %H:%M") TZ=UTC exec /usr/bin/date "$@" ;; *) exit 1 ;; esac'
        dmidecode = '[ "$*" = "-t memory" ] || exit 1; cat "$STUB_DATA/dmidecode-memory.txt"'
        lsblk    = '[ "$1 $2 $3 $4 $5" = "-s -n -r -o TYPE,RM,ROTA,TRAN" ] || exit 1; for last; do :; done; cat "$STUB_DATA/lsblk$(printf "%s" "$last" | tr / _).txt"'
        'systemd-detect-virt' = '[ "$*" = "--quiet --vm" ] || exit 1; virt=$(cat "$STUB_DATA/systemd-detect-virt.txt" 2>/dev/null); [ -n "$virt" ] && [ "$virt" != none ]'
        systemctl = @'
[ -d "$STUB_DATA/units" ] || exit 1
case "$1" in
list-units)
	[ "$*" = "list-units --state=failed --no-legend --plain" ] || exit 1
	cat "$STUB_DATA/systemctl-failed.txt" ;;
show)
	[ "$2" = -p ] || exit 1
	case $3 in Id,LoadState,ActiveState,TriggeredBy | ActiveState) ;; *) exit 1 ;; esac
	keys=$(printf '%s' "$3" | tr , '|')
	shift 3
	first=1
	for u; do
		[ -n "$first" ] || echo
		first=
		if [ -r "$STUB_DATA/units/$u" ]; then cat "$STUB_DATA/units/$u"; else printf 'Id=%s\nTriggeredBy=\nLoadState=not-found\nActiveState=inactive\n' "$u"; fi | grep -E "^($keys)="
	done ;;
*) exit 1 ;;
esac
'@
        timedatectl = '[ "$*" = "show -p NTPSynchronized --value" ] || exit 1; cat "$STUB_DATA/timedatectl-ntp.txt"'
    }
    foreach ($name in $stubs.Keys) {
        $path = Join-Path $Bin $name
        [System.IO.File]::WriteAllText($path, $head.Replace('NAME', $name) + "`n" + $stubs[$name] + "`n")
        & chmod 755 $path
    }
    $script:StubPath = "$($Bin):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    $script:Sampler = Join-Path $repoRoot 'UsaBanner' 'linux' 'sample.sh'
    $script:Epoch = 1792635480

    # Samples from the 24 hours before date +%s: the first exactly 24 hours
    # old, so out of the range; the last of a disk not mounted now.
    $script:RangeSamples = @(
        "$($Epoch - 86400)`tcpu`t99"
        "$($Epoch - 86399)`tcpu`t3"
        "$($Epoch - 900)`tcpu`t71"
        "$($Epoch - 900)`tmemory`t20"
        "$($Epoch - 1800)`tmemory`t10"
        "$($Epoch - 900)`tdisk`t/`t7"
        "$($Epoch - 1800)`tdisk`t/`t5"
        "$($Epoch - 900)`tdisk`t/var`t60"
        "$($Epoch - 1800)`tdisk`t/var`t50"
        "$($Epoch - 900)`tdisk`t/srv`t90"
    )

    function Invoke-Collector {
        # In:  the folder its files are read under, the folder its stubs
        #      answer from, variables for the run, and -Program, the sampler
        #      for the collector
        # Out: what it prints, a line each
        # Why: pam_motd runs the login renderer with an empty environment,
        #      and systemd the periodic job
        param(
            [string]$Root = (Join-Path $Fixture 'root'),
            [string]$Data = (Join-Path $Fixture 'commands'),
            [hashtable]$Variables = @{},
            [string]$Program = $Collector
        )
        $assignments = @("PATH=$StubPath", "USABANNER_ROOT=$Root", "STUB_DATA=$Data", "STUB_LOG=$Log")
        foreach ($key in $Variables.Keys) { $assignments += "$key=$($Variables[$key])" }
        @(& env -i @assignments sh $Program)
    }

    function New-Variant {
        # In:  files to change, as 'root/proc/loadavg' = text ($null removes
        #      one), and -Executable, those of them to make programs
        # Out: the variant's Root and Data folders, for Invoke-Collector @variant
        # Why: each test changes only the part of the recording it is about
        param([hashtable]$Change, [string[]]$Executable = @())
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
        foreach ($file in $Executable) { & chmod 755 (Join-Path $copy $file) }
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
        $found = @(& env -i "PATH=$StubPath" sh -c 'for c in hostname ip uname getconf df who date dmidecode lsblk systemd-detect-virt systemctl timedatectl; do command -v "$c"; done')
        $found | Should -BeExactly @(foreach ($name in 'hostname', 'ip', 'uname', 'getconf', 'df', 'who', 'date', 'dmidecode', 'lsblk', 'systemd-detect-virt', 'systemctl', 'timedatectl') { Join-Path $Bin $name })
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
        @{ Case = 'two, rounded'; Cores = "2`n"; Load = "0.09 0.05 0.01 1/180 900`n"; Expected = "cpu`t5`t`t`t2 cores @ 3.1 GHz" }
        @{ Case = 'one, past 100'; Cores = "1`n"; Load = "1.23 0.50 0.20 1/180 900`n"; Expected = "cpu`t123`t`t`t1 core @ 3.1 GHz" }
        @{ Case = 'an unknown count, none'; Cores = $null; Load = "0.09 0.05 0.01 1/180 900`n"; Expected = '' }
    ) {
        $variant = New-Variant @{ 'commands/getconf.txt' = $Cores; 'root/proc/loadavg' = $Load }
        Select-Record (Invoke-Collector @variant) cpu | Should -BeExactly $Expected
    }

    It 'counts the online CPUs with getconf, which OMP_NUM_THREADS does not change' {
        Select-Record (Invoke-Collector -Variables @{ OMP_NUM_THREADS = '1' }) cpu | Should -BeExactly "cpu`t0`t`t`t2 cores @ 3.1 GHz"
    }

    It 'gives the CPUs'' rated speed <Case>' -ForEach @(
        @{ Case = 'from cpufreq when the model name has none'; Change = @{ 'root/proc/cpuinfo' = "processor`t: 0`nmodel name`t: AMD EPYC 7763 64-Core Processor`n"; 'root/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq' = "3529052`n" }; Expected = "cpu`t0`t`t`t2 cores @ 3.5 GHz" }
        @{ Case = 'not at all with neither'; Change = @{ 'root/proc/cpuinfo' = "processor`t: 0`nmodel name`t: AMD EPYC 7763 64-Core Processor`n" }; Expected = "cpu`t0`t`t`t2 cores" }
    ) {
        $variant = New-Variant $Change
        Select-Record (Invoke-Collector @variant) cpu | Should -BeExactly $Expected
    }

    It 'fills the memory''s and disks'' kinds from the job''s cache, less than 24 hours old' {
        $slow = @("$($Epoch - 900)`tmemory-kind`tDDR4-3200", "$($Epoch - 900)`tdisk-kind`t/`tNVMe", "$($Epoch - 86400)`tdisk-kind`t/var`tHDD")
        $variant = New-Variant @{ 'root/var/lib/usabanner/slow.tsv' = ($slow -join "`n") + "`n" }
        $records = Invoke-Collector @variant
        @('memory', 'disk' | ForEach-Object { Select-Record $records $_ }) -join "`n" | Should -BeExactly (@(
                "memory`t14`t`t`t0.5 of 3.8 GiB`tDDR4-3200"
                "disk`t/`t6`t`t`t6 of 121 GiB`tNVMe"
                "disk`t/var`t57`t`t`t21 of 39 GiB`t"
            ) -join "`n")
    }

    It 'gives the updates the job counted: <Case>' -ForEach @(
        @{ Case = 'none'; Counts = "0`t0"; Expected = "updates`tnone pending`tgood" }
        @{ Case = 'some, none for security'; Counts = "12`t0"; Expected = "updates`t12 pending`tgood" }
        @{ Case = 'some for security, a warning'; Counts = "64`t3"; Expected = "updates`t64 pending, 3 security`twarn" }
    ) {
        $variant = New-Variant @{ 'root/var/lib/usabanner/slow.tsv' = "$($Epoch - 900)`tupdates`t$Counts`n" }
        Select-Record (Invoke-Collector @variant) updates | Should -BeExactly $Expected
    }

    It 'gives no updates from a count 24 hours old' {
        $variant = New-Variant @{ 'root/var/lib/usabanner/slow.tsv' = "$($Epoch - 86400)`tupdates`t64`t3`n" }
        Select-Record (Invoke-Collector @variant) updates | Should -BeExactly ''
    }

    It 'gives a reboot <Case>' -ForEach @(
        @{ Case = 'pending, with the packages that asked for it'; Change = @{ 'root/run/reboot-required' = "*** System restart required ***`n"; 'root/run/reboot-required.pkgs' = "linux-image-6.8.0-88-generic`nlibc6`nlinux-image-6.8.0-88-generic`n" }; Expected = "reboot`tpending: libc6, kernel 6.8.0-88`twarn" }
        @{ Case = 'pending, without its packages'; Change = @{ 'root/run/reboot-required' = "*** System restart required ***`n" }; Expected = "reboot`tpending`twarn" }
        @{ Case = 'scheduled'; Change = @{ 'root/run/systemd/shutdown/scheduled' = "USEC=1792738800000000`nWARN_WALL=1`nMODE=reboot`nUID=0`n" }; Expected = "reboot`tnone pending; scheduled Fri 07:00`twarn" }
        @{ Case = 'power-off scheduled'; Change = @{ 'root/run/systemd/shutdown/scheduled' = "USEC=1792738800000000`nWARN_WALL=1`nMODE=poweroff`nUID=0`n" }; Expected = "reboot`tnone pending; poweroff scheduled Fri 07:00`twarn" }
        @{ Case = 'pending and scheduled'; Change = @{ 'root/run/reboot-required' = "*** System restart required ***`n"; 'root/run/reboot-required.pkgs' = "linux-image-6.8.0-88-generic`n"; 'root/run/systemd/shutdown/scheduled' = "USEC=1792738800000000`nWARN_WALL=1`nMODE=reboot`nUID=0`n" }; Expected = "reboot`tpending: kernel 6.8.0-88; scheduled Fri 07:00`twarn" }
    ) {
        $variant = New-Variant $Change
        Select-Record (Invoke-Collector @variant) reboot | Should -BeExactly $Expected
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
        $records -join "`n" | Should -BeExactly ("name`th-vsl-web1", "os`tLinux", "reboot`tnone pending, none scheduled`tgood", "time`tThu 2026-10-22 02:18 UTC", "check`treboot" -join "`n")
    }

    It 'fills min and max from the samples of the last 24 hours, the value now included' {
        $variant = New-Variant @{ 'root/var/lib/usabanner/samples.tsv' = ($RangeSamples -join "`n") + "`n" }
        $records = Invoke-Collector @variant
        @('cpu', 'memory', 'disk' | ForEach-Object { Select-Record $records $_ }) -join "`n" | Should -BeExactly (@(
                "cpu`t0`t0`t71`t2 cores @ 3.1 GHz"
                "memory`t14`t10`t20`t0.5 of 3.8 GiB`t"
                "disk`t/`t6`t5`t7`t6 of 121 GiB`t"
                "disk`t/var`t57`t50`t60`t21 of 39 GiB`t"
            ) -join "`n")
    }

    It 'leaves min and max empty for a fact without a sample' {
        $variant = New-Variant @{ 'root/var/lib/usabanner/samples.tsv' = "$($Epoch - 900)`tcpu`t40`n" }
        $records = Invoke-Collector @variant
        Select-Record $records cpu | Should -BeExactly "cpu`t0`t0`t40`t2 cores @ 3.1 GHz"
        Select-Record $records memory | Should -BeExactly "memory`t14`t`t`t0.5 of 3.8 GiB`t"
    }

    It 'passes over a line in the samples that is not a sample' {
        $lines = @('not a sample', "$($Epoch - 900)`tcpu`tlots", "$($Epoch - 900)`tmemory", "soon`tcpu`t50", "$($Epoch - 900)`tdisk`t/")
        $variant = New-Variant @{ 'root/var/lib/usabanner/samples.tsv' = ($lines -join "`n") + "`n" }
        $records = Invoke-Collector @variant
        @('cpu', 'memory', 'disk' | ForEach-Object { Select-Record $records $_ }) -join "`n" | Should -BeExactly (@(
                "cpu`t0`t`t`t2 cores @ 3.1 GHz"
                "memory`t14`t`t`t0.5 of 3.8 GiB`t"
                "disk`t/`t6`t`t`t6 of 121 GiB`t"
                "disk`t/var`t57`t`t`t21 of 39 GiB`t"
            ) -join "`n")
    }

    It 'fills the range the module fills from the same samples' {
        $file = Join-Path $TestDrive 'shared-samples.tsv'
        [System.IO.File]::WriteAllText($file, ($RangeSamples -join "`n") + "`n")
        $variant = New-Variant @{ 'root/var/lib/usabanner/samples.tsv' = ($RangeSamples -join "`n") + "`n" }
        $byShell = InModuleScope UsaBanner -Parameters @{ Lines = @(Invoke-Collector @variant) } { param($Lines) ConvertFrom-UsaBannerFactRecord -Line $Lines }
        $byModule = InModuleScope UsaBanner -Parameters @{ Lines = @(Invoke-Collector); File = $file; Epoch = $Epoch } {
            param($Lines, $File, $Epoch)
            $read = ConvertFrom-UsaBannerFactRecord -Line $Lines
            Add-UsaBannerSampleRange -Facts $read -Path $File -Now ([datetimeoffset]::FromUnixTimeSeconds($Epoch))
            $read
        }
        $ranges = {
            # In:  facts
            # Out: their ranges as one line
            # Why: the two readers are compared whole
            param($Facts)
            (@("cpu $($Facts.Cpu.Min)-$($Facts.Cpu.Max)", "memory $($Facts.Memory.Min)-$($Facts.Memory.Max)") + @($Facts.Disks | ForEach-Object { "$($_.Name) $($_.Min)-$($_.Max)" })) -join ', '
        }
        & $ranges $byShell | Should -BeExactly 'cpu 0-71, memory 10-20, / 5-7, /var 50-60'
        & $ranges $byModule | Should -BeExactly (& $ranges $byShell)
    }

    It 'takes the kinds and the updates the module takes from the same slow facts' {
        # The last line of a kind counts, one with a time too long for a 64-bit
        # number too; one 24 hours old, short of a field or with a count that
        # is not one does not.
        $slow = @(
            "$($Epoch - 86400)`tmemory-kind`tDDR3-1600"
            "$($Epoch - 900)`tmemory-kind`tDDR4-2933"
            "$($Epoch - 900)`tdisk-kind`t/`tSSD"
            "$($Epoch - 600)`tdisk-kind`t/`tNVMe"
            "$($Epoch - 600)`tdisk-kind`t/var"
            "99999999999999999999999`tmemory-kind`tDDR5-4800"
            "$($Epoch - 900)`tupdates`t64`t3"
            "$($Epoch - 600)`tupdates`t12`t0"
            "$($Epoch - 300)`tupdates`tmany`t0"
        )
        $file = Join-Path $TestDrive 'shared-slow.tsv'
        [System.IO.File]::WriteAllText($file, ($slow -join "`n") + "`n")
        $variant = New-Variant @{ 'root/var/lib/usabanner/slow.tsv' = ($slow -join "`n") + "`n" }
        $byShell = InModuleScope UsaBanner -Parameters @{ Lines = @(Invoke-Collector @variant) } { param($Lines) ConvertFrom-UsaBannerFactRecord -Line $Lines }
        $byModule = InModuleScope UsaBanner -Parameters @{ Lines = @(Invoke-Collector); File = $file; Epoch = $Epoch } {
            param($Lines, $File, $Epoch)
            $read = ConvertFrom-UsaBannerFactRecord -Line $Lines
            Add-UsaBannerSlowFacts -Facts $read -Path $File -Now ([datetimeoffset]::FromUnixTimeSeconds($Epoch))
            $read
        }
        $kinds = {
            # In:  facts
            # Out: their kinds and updates as one line
            # Why: the two readers are compared whole
            param($Facts)
            (@("memory $($Facts.Memory.Kind)") + @($Facts.Disks | ForEach-Object { "$($_.Name) $($_.Kind)" }) + @("updates $($Facts.Updates.Text) $($Facts.Updates.Level)")) -join ', '
        }
        & $kinds $byShell | Should -BeExactly 'memory DDR5-4800, / NVMe, /var , updates 12 pending good'
        & $kinds $byModule | Should -BeExactly (& $kinds $byShell)
    }

    It 'names the units that failed: <Case>' -ForEach @(
        @{ Case = 'none, and still names the check'; Failed = ''; Expected = '' }
        @{ Case = 'one'; Failed = "cron.service loaded failed failed Regular background program processing daemon`n"; Expected = "problem`tbad`t1 failed unit: cron.service" }
    ) {
        $variant = New-Variant @{ 'commands/systemctl-failed.txt' = $Failed }
        $records = Invoke-Collector @variant
        Select-Record $records problem | Should -BeExactly $Expected
        (Select-Record $records check) -split "`n" | Should -Contain "check`tunits"
    }

    It 'watches <Case>' -ForEach @(
        @{ Case = 'D10''s services on a host joined to AD, one started by its socket as on demand'; Change = @{}; Variables = @{}; Expected = "services`tssh, cron, ntpsec, sssd active; adsysd on demand`tgood"; Problems = '' }
        @{ Case = 'neither sssd nor adsysd on a host not joined'; Change = @{ 'root/etc/sssd/sssd.conf' = $null }; Variables = @{}; Expected = "services`tssh, cron, ntpsec active`tgood"; Problems = '' }
        @{ Case = 'the time sync daemon that is installed'; Change = @{ 'commands/units/ntpsec.service' = $null; 'commands/units/ntp.service' = $null; 'commands/units/systemd-timesyncd.service' = "Id=systemd-timesyncd.service`nTriggeredBy=`nLoadState=loaded`nActiveState=active`n" }; Variables = @{}; Expected = "services`tssh, cron, systemd-timesyncd, sssd active; adsysd on demand`tgood"; Problems = '' }
        @{ Case = 'adsysd only where it is installed'; Change = @{ 'commands/units/adsysd.service' = $null }; Variables = @{}; Expected = "services`tssh, cron, ntpsec, sssd active`tgood"; Problems = '' }
        @{ Case = 'ssh on demand, as on Ubuntu 24.04 before its first connection'; Change = @{ 'commands/units/ssh.service' = "Id=ssh.service`nTriggeredBy=ssh.socket`nLoadState=loaded`nActiveState=inactive`n" }; Variables = @{}; Expected = "services`tcron, ntpsec, sssd active; ssh, adsysd on demand`tgood"; Problems = '' }
        @{ Case = 'a service down, as bad'; Change = @{ 'commands/units/cron.service' = "Id=cron.service`nTriggeredBy=`nLoadState=loaded`nActiveState=inactive`n" }; Variables = @{}; Expected = "services`tcron inactive; ssh, ntpsec, sssd active; adsysd on demand`tbad"; Problems = "problem`tbad`tcron is inactive" }
        @{ Case = 'a service down whose socket is down too, as bad'; Change = @{ 'commands/units/adsysd.socket' = "Id=adsysd.socket`nActiveState=inactive`n" }; Variables = @{}; Expected = "services`tadsysd inactive; ssh, cron, ntpsec, sssd active`tbad"; Problems = "problem`tbad`tadsysd is inactive" }
        @{ Case = 'the services USABANNER_SERVICES names, one failed and one not found'; Change = @{ 'commands/units/postgresql.service' = "Id=postgresql.service`nTriggeredBy=`nLoadState=loaded`nActiveState=failed`n" }; Variables = @{ USABANNER_SERVICES = 'ssh postgresql nginx' }; Expected = "services`tpostgresql failed, nginx not found; ssh active`tbad"; Problems = "problem`tbad`tpostgresql is failed`nproblem`tbad`tservice nginx not found" }
    ) {
        $variant = New-Variant ($Change + @{ 'commands/systemctl-failed.txt' = '' })
        $records = Invoke-Collector @variant -Variables $Variables
        Select-Record $records services | Should -BeExactly $Expected
        Select-Record $records problem | Should -BeExactly $Problems
        (Select-Record $records check) -split "`n" | Should -Contain "check`tservices"
    }

    It 'says nothing of the services when systemctl''s answer does not line up with the question' {
        # A systemctl first on PATH that answers one block, whatever it is asked.
        $bin = Join-Path $TestDrive 'one-block'
        $null = New-Item -ItemType Directory -Path $bin -Force
        $oneBlock = Join-Path $bin 'systemctl'
        [System.IO.File]::WriteAllText($oneBlock, "#!/bin/sh`ncase `"`$1`" in`nshow) printf 'Id=ssh.service\nTriggeredBy=\nLoadState=loaded\nActiveState=active\n' ;;`nesac`n")
        & chmod 755 $oneBlock
        $records = Invoke-Collector -Variables @{ PATH = "$($bin):$StubPath" }
        Select-Record $records services | Should -BeNullOrEmpty
        (Select-Record $records check) -split "`n" | Should -Not -Contain "check`tservices"
    }

    It 'watches none when USABANNER_SERVICES is empty, and names no services check' {
        $records = Invoke-Collector -Variables @{ USABANNER_SERVICES = '' }
        Select-Record $records services | Should -BeNullOrEmpty
        (Select-Record $records check) -split "`n" | Should -Not -Contain "check`tservices"
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -like 'systemctl show*' }) | Should -BeNullOrEmpty
    }

    It 'asks systemctl about a service''s sockets only while the service is down' {
        $null = Invoke-Collector
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -like 'systemctl show -p ActiveState*' }) | Should -BeExactly @('systemctl show -p ActiveState adsysd.socket')
        $variant = New-Variant @{ 'commands/units/adsysd.service' = "Id=adsysd.service`nTriggeredBy=adsysd.socket`nLoadState=loaded`nActiveState=active`n" }
        [System.IO.File]::WriteAllText($Log, '')
        $null = Invoke-Collector @variant
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -like 'systemctl show -p ActiveState*' }) | Should -BeNullOrEmpty
    }

    It 'reports <Case>' -ForEach @(
        @{ Case = 'a disk from 85% full, and bad from 95%'; Change = @{ 'commands/df.txt' = (@('Filesystem          1024-blocks       Used  Available Capacity Mounted on', '/dev/sda1             31457280   26738688    4718592      85% /', '/dev/sdb1             41943040   40265318    1677722      96% /var', '/dev/sdc1             10485760    8808038    1677722      84% /srv') -join "`n") + "`n" }; Expected = "problem`twarn`t/ is 85% full`nproblem`tbad`t/var is 96% full" }
        @{ Case = 'the memory from 90% in use'; Change = @{ 'root/proc/meminfo' = "MemTotal:        1048576 kB`nMemFree:           50000 kB`nMemAvailable:     104857 kB`n" }; Expected = "problem`twarn`tmemory 90% in use" }
        @{ Case = 'the memory from 95%, as bad'; Change = @{ 'root/proc/meminfo' = "MemTotal:        1048576 kB`nMemFree:           10000 kB`nMemAvailable:      52428 kB`n" }; Expected = "problem`tbad`tmemory 95% in use" }
        @{ Case = 'the clock not synchronised'; Change = @{ 'commands/timedatectl-ntp.txt' = "no`n" }; Expected = "problem`twarn`tclock is not synchronised" }
        @{ Case = 'a reboot pending, with what asked for it'; Change = @{ 'root/run/reboot-required' = "*** System restart required ***`n"; 'root/run/reboot-required.pkgs' = "linux-image-6.8.0-88-generic`nlibc6`n" }; Expected = "problem`twarn`treboot pending: libc6, kernel 6.8.0-88" }
    ) {
        $variant = New-Variant ($Change + @{ 'commands/systemctl-failed.txt' = '' })
        $records = Invoke-Collector @variant
        Select-Record $records problem | Should -BeExactly $Expected
        (Select-Record $records check) -split "`n" | Should -BeExactly @("check`tunits", "check`tservices", "check`tdisks <85%", "check`tmemory", "check`tclock", "check`treboot")
    }

    It 'names no clock check when timedatectl gives no answer' {
        $variant = New-Variant @{ 'commands/timedatectl-ntp.txt' = $null }
        (Select-Record (Invoke-Collector @variant) check) -split "`n" | Should -Not -Contain "check`tclock"
    }

    It 'cuts <Command> off after 2 seconds, and names no <Check> check' -ForEach @(
        @{ Command = 'systemctl'; Check = 'units or services'; Gone = @("check`tunits", "check`tservices"); Limit = 8.5 }
        @{ Command = 'timedatectl'; Check = 'clock'; Gone = @("check`tclock"); Limit = 4.5 }
    ) {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $records = Invoke-Collector -Variables @{ STUB_SLOW = $Command }
        $watch.Stop()
        $checks = (Select-Record $records check) -split "`n"
        foreach ($gone in $Gone) { $checks | Should -Not -Contain $gone }
        $checks | Should -Contain "check`treboot"
        $watch.Elapsed.TotalSeconds | Should -BeLessThan $Limit
    }
}

Describe 'linux/sample.sh' -Skip:$IsWindows {
    BeforeEach { [System.IO.File]::WriteAllText($Log, '') }

    It 'is sh that sh -n accepts' {
        & sh -n $Sampler
        $LASTEXITCODE | Should -Be 0
    }

    It 'adds this host''s cpu, memory and disks with the time, and keeps the last 24 hours' {
        $kept = @("$($Epoch - 86400)`tcpu`t99", "$($Epoch - 86399)`tcpu`t3", 'not a sample')
        $variant = New-Variant @{ 'root/var/lib/usabanner/samples.tsv' = ($kept -join "`n") + "`n" }
        $null = Invoke-Collector @variant -Program $Sampler
        [System.IO.File]::ReadAllText((Join-Path $variant.Root 'var/lib/usabanner/samples.tsv')) | Should -BeExactly ((@(
                    "$($Epoch - 86399)`tcpu`t3"
                    "$Epoch`tcpu`t0"
                    "$Epoch`tmemory`t14"
                    "$Epoch`tdisk`t/`t6"
                    "$Epoch`tdisk`t/var`t57"
                ) -join "`n") + "`n")
    }

    It 'caches <Case>' -ForEach @(
        @{ Case = 'the name hostname -f gives in a domain'; Answer = "h-vsl-web1.ad.example`n"; Before = $null; After = 'h-vsl-web1.ad.example' }
        @{ Case = 'no name, dropping the old one, when hostname -f gives the short name alone'; Answer = "h-vsl-web1`n"; Before = 'h-vsl-web1.old.example'; After = $null }
        @{ Case = 'nothing new when hostname -f gives another host''s name'; Answer = "localhost.localdomain`n"; Before = 'h-vsl-web1.ad.example'; After = 'h-vsl-web1.ad.example' }
        @{ Case = 'nothing new when hostname -f fails'; Answer = $null; Before = 'h-vsl-web1.ad.example'; After = 'h-vsl-web1.ad.example' }
    ) {
        $change = @{}
        if ($null -ne $Answer) { $change['commands/hostname-f.txt'] = $Answer }
        if ($Before) { $change['root/var/lib/usabanner/fqdn'] = "$Before`n" }
        $variant = New-Variant $change
        $null = Invoke-Collector @variant -Program $Sampler
        $cache = Join-Path $variant.Root 'var/lib/usabanner/fqdn'
        if ($null -eq $After) { Test-Path -LiteralPath $cache | Should -BeFalse }
        else { [System.IO.File]::ReadAllText($cache) | Should -BeExactly "$After`n" }
    }

    It 'leaves the cache as it was when hostname -f stalls, and still samples' {
        $variant = New-Variant @{ 'commands/hostname-f.txt' = "h-vsl-web1.new.example`n"; 'root/var/lib/usabanner/fqdn' = "h-vsl-web1.ad.example`n" }
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $null = Invoke-Collector @variant -Program $Sampler -Variables @{ STUB_SLOW_FQDN = '1' }
        $watch.Stop()
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 7.5
        [System.IO.File]::ReadAllText((Join-Path $variant.Root 'var/lib/usabanner/fqdn')) | Should -BeExactly "h-vsl-web1.ad.example`n"
        @(Get-Content -LiteralPath (Join-Path $variant.Root 'var/lib/usabanner/samples.tsv')) -match "^$Epoch`tcpu`t" | Should -Not -BeNullOrEmpty
    }

    It 'writes files any user can read, whatever the umask' {
        $variant = New-Variant @{ 'commands/hostname-f.txt' = "h-vsl-web1.ad.example`n" }
        $assignments = @("PATH=$StubPath", "USABANNER_ROOT=$($variant.Root)", "STUB_DATA=$($variant.Data)", "STUB_LOG=$Log")
        $null = & env -i @assignments sh -c 'umask 077; exec sh "$1"' umask-077 $Sampler
        $folder = Join-Path $variant.Root 'var/lib/usabanner'
        (Get-Item -LiteralPath $folder).UnixFileMode | Should -Be ([System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute')
        foreach ($name in 'samples.tsv', 'slow.tsv', 'fqdn') {
            (Get-Item -LiteralPath (Join-Path $folder $name)).UnixFileMode | Should -Be ([System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead') -Because $name
        }
    }

    It 'leaves no file behind but samples.tsv, slow.tsv and fqdn' {
        $variant = New-Variant @{ 'commands/hostname-f.txt' = "h-vsl-web1.ad.example`n" }
        $null = Invoke-Collector @variant -Program $Sampler
        @(Get-ChildItem -LiteralPath (Join-Path $variant.Root 'var/lib/usabanner') -Force | ForEach-Object { $_.Name } | Sort-Object) | Should -BeExactly @('fqdn', 'samples.tsv', 'slow.tsv')
    }

    It 'keeps the memory''s kind and speed: <Case>' -ForEach @(
        @{ Case = 'none from a virtual machine''s firmware'; Dmi = $null; Expected = '' }
        @{ Case = 'the first module with a type, at its configured speed'; Dmi = (@(
                    '# dmidecode 3.5', '', 'Handle 0x0010, DMI type 17, 92 bytes', 'Memory Device', "`tSize: No Module Installed", "`tType: Unknown", ''
                    'Handle 0x0011, DMI type 17, 92 bytes', 'Memory Device', "`tSize: 32 GB", "`tType: DDR4", "`tSpeed: 3200 MT/s", "`tConfigured Memory Speed: 2933 MT/s", ''
                    'Handle 0x0012, DMI type 17, 92 bytes', 'Memory Device', "`tSize: 32 GB", "`tType: DDR4", "`tSpeed: 3200 MT/s", "`tConfigured Memory Speed: 3200 MT/s"
                ) -join "`n") + "`n"; Expected = 'DDR4-2933'
        }
    ) {
        $change = @{}
        if ($Dmi) { $change['commands/dmidecode-memory.txt'] = $Dmi }
        $variant = New-Variant $change
        $null = Invoke-Collector @variant -Program $Sampler
        @(Get-Content -LiteralPath (Join-Path $variant.Root 'var/lib/usabanner/slow.tsv') | Where-Object { $_ -like "*`tmemory-kind`t*" } | ForEach-Object { ($_ -split "`t")[2] }) -join ',' | Should -BeExactly $Expected
    }

    It 'keeps each disk''s kind on a physical host, from the disk under its filesystem' {
        $variant = New-Variant @{
            'commands/systemd-detect-virt.txt'                    = "none`n"
            'commands/lsblk_dev_mapper_ubuntu--vg-ubuntu--lv.txt' = "lvm 0 0 `npart 0 0 `ndisk 0 0 nvme`n"
            'commands/lsblk_dev_sda2.txt'                         = "part 1 0 `ndisk 1 0 usb`n"
            'commands/lsblk_dev_sdb1.txt'                         = "part 0 1 `ndisk 0 1 sata`n"
            'commands/lsblk_dev_sda1.txt'                         = "part 0 0 `ndisk 0 0 sata`n"
        }
        $null = Invoke-Collector @variant -Program $Sampler
        @(Get-Content -LiteralPath (Join-Path $variant.Root 'var/lib/usabanner/slow.tsv') | Where-Object { $_ -like "*`tdisk-kind`t*" } | ForEach-Object { ($_ -split "`t")[2..3] -join '=' }) -join ',' | Should -BeExactly '/=NVMe,/boot=removable,/var=HDD,/boot/efi=SSD'
    }

    It 'keeps no disk kind in a virtual machine, and asks lsblk nothing' {
        $variant = New-Variant @{ 'commands/lsblk_dev_sdb1.txt' = "part 0 1 `ndisk 0 1 sata`n" }
        $null = Invoke-Collector @variant -Program $Sampler
        @(Get-Content -LiteralPath (Join-Path $variant.Root 'var/lib/usabanner/slow.tsv') | Where-Object { $_ -like "*`tdisk-kind`t*" }).Count | Should -Be 0
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -like 'lsblk*' }).Count | Should -Be 0
    }

    It 'keeps the updates apt-check counts: <Case>' -ForEach @(
        @{ Case = 'as it prints them'; Stub = "#!/bin/sh`necho '64;3' >&2`n"; Expected = '64,3' }
        @{ Case = 'none when it prints something else'; Stub = "#!/bin/sh`necho 'E: Could not get lock' >&2`nexit 1`n"; Expected = '' }
        @{ Case = 'none without it'; Stub = $null; Expected = '' }
    ) {
        $change = @{}
        $programs = @()
        if ($Stub) {
            $change['root/usr/lib/update-notifier/apt-check'] = $Stub
            $programs = @('root/usr/lib/update-notifier/apt-check')
        }
        $variant = New-Variant $change -Executable $programs
        $null = Invoke-Collector @variant -Program $Sampler
        @(Get-Content -LiteralPath (Join-Path $variant.Root 'var/lib/usabanner/slow.tsv') | Where-Object { $_ -like "*`tupdates`t*" } | ForEach-Object { ($_ -split "`t")[2..3] -join ',' }) -join ';' | Should -BeExactly $Expected
    }

    It 'writes slow.tsv anew at every run' {
        $variant = New-Variant @{ 'root/var/lib/usabanner/slow.tsv' = "$($Epoch - 900)`tmemory-kind`tDDR3-1600`n" }
        $null = Invoke-Collector @variant -Program $Sampler
        [System.IO.File]::ReadAllText((Join-Path $variant.Root 'var/lib/usabanner/slow.tsv')) | Should -BeExactly ''
    }
}

Describe 'ConvertFrom-UsaBannerFactRecord' {
    It 'reads the recorded host''s records as the facts the banner draws' {
        $facts = InModuleScope UsaBanner -Parameters @{ Lines = $Recorded } { param($Lines) ConvertFrom-UsaBannerFactRecord -Line $Lines }
        @($facts.Keys | Sort-Object) | Should -BeExactly @('Checked', 'Cpu', 'Disks', 'Ip', 'Ipv4', 'Memory', 'Name', 'Os', 'Problems', 'Reboot', 'Services', 'Sessions', 'Time', 'Uptime')
        '{0}|{1}' -f $facts.Reboot.Text, $facts.Reboot.Level | Should -BeExactly 'none pending, none scheduled|good'
        '{0}|{1}' -f $facts.Services.Text, $facts.Services.Level | Should -BeExactly 'ssh, cron, ntpsec, sssd active; adsysd on demand|good'
        @($facts.Problems).Count | Should -Be 1
        '{0}|{1}' -f $facts.Problems[0].Level, $facts.Problems[0].Text | Should -BeExactly 'bad|4 failed units: hv-fcopy-daemon.service, hv-kvp-daemon.service, hv-vss-daemon.service, contoso-motd-update.service'
        $facts.Checked | Should -BeExactly @('units', 'services', 'disks <85%', 'memory', 'clock', 'reboot')
        $facts.Name | Should -BeExactly 'h-vsl-web1'
        $facts.Ip | Should -BeExactly '10.20.40.80'
        $facts.Os | Should -BeExactly 'Ubuntu 24.04.5 LTS, kernel 6.8.0-147-generic'
        $facts.Uptime | Should -BeExactly '10h 32m'
        $facts.Cpu.Now | Should -BeOfType [int]
        $facts.Cpu.Now | Should -Be 0
        $facts.Cpu.Min | Should -BeNullOrEmpty
        $facts.Cpu.Max | Should -BeNullOrEmpty
        $facts.Cpu.Text | Should -BeExactly '2 cores @ 3.1 GHz'
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

    It 'reads the updates and the reboot as their text and a level' {
        $facts = InModuleScope UsaBanner { ConvertFrom-UsaBannerFactRecord -Line @("updates`t64 pending, 3 security`twarn", "reboot`tpending: kernel 6.8.0-88`twarn") }
        '{0}|{1}' -f $facts.Updates.Text, $facts.Updates.Level | Should -BeExactly '64 pending, 3 security|warn'
        '{0}|{1}' -f $facts.Reboot.Text, $facts.Reboot.Level | Should -BeExactly 'pending: kernel 6.8.0-88|warn'
    }

    It 'reads the services, each problem and each check, in order, passing over one without its text' {
        $facts = InModuleScope UsaBanner { ConvertFrom-UsaBannerFactRecord -Line @("problem`tbad`tcron is inactive", "services`tcron inactive; ssh active`tbad", "check`tservices", "problem`twarn`t/var is 88% full", "problem`twarn", "check`tdisks <85%", "check`t", 'check') }
        '{0}|{1}' -f $facts.Services.Text, $facts.Services.Level | Should -BeExactly 'cron inactive; ssh active|bad'
        @($facts.Problems | ForEach-Object { '{0}|{1}' -f $_.Level, $_.Text }) -join ',' | Should -BeExactly 'bad|cron is inactive,warn|/var is 88% full'
        $facts.Checked | Should -BeExactly @('services', 'disks <85%')
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
        $facts.Cpu.Text | Should -BeExactly '2 cores @ 3.1 GHz'
        @($facts.Disks.Name) -join ',' | Should -BeExactly '/,/var'
        @($facts.Ipv4.Name) -join ',' | Should -BeExactly 'eth0'
    }

    It 'hands the collector the services to watch: <Case>' -Skip:$IsWindows -ForEach @(
        @{ Case = 'the names'; Services = @('ssh', 'nginx'); Expected = 'ssh nginx' }
        @{ Case = 'none'; Services = @(); Expected = '' }
        @{ Case = 'default'; Services = 'default'; Expected = 'default' }
        @{ Case = 'default, when the configuration has none'; Services = $null; Expected = 'default' }
    ) {
        $echo = Join-Path $TestDrive 'services.sh'
        [System.IO.File]::WriteAllText($echo, "printf 'name\t[%s]\n' `"`$USABANNER_SERVICES`"`n")
        $facts = InModuleScope UsaBanner -Parameters @{ Path = $echo; Services = $Services } { param($Path, $Services) Get-UsaBannerHostFacts -OnWindows $false -Collector $Path -Services $Services }
        $facts.Name | Should -BeExactly "[$Expected]"
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
