# Pester tests for the login renderer on Linux (docs/DECISIONS.md, D2):
# Private/LoginFrame.ps1 pre-draws the banner after login, and
# linux/postlogin.sh has postlogin.awk draw a host's facts into it. Each test
# draws the same facts both ways and holds the two to the same bytes, under
# every awk this host has: Ubuntu's own is mawk. Linux only: they need sh.

BeforeDiscovery {
    $script:Awks = @(@('mawk', 'gawk', 'original-awk') | Where-Object { Get-Command $_ -CommandType Application -ErrorAction SilentlyContinue })

    # Facts records, as linux/facts.sh prints them (D26), one set a host.
    $script:Records = @{
        lab   = @(
            "name`th-vsl-web1.ad.example", "ip`t10.20.40.79", "os`tUbuntu 24.04.5 LTS, kernel 6.8.0-147-generic", "uptime`t15h 59m"
            "cpu`t4`t0`t4`t2 cores @ 3.1 GHz", "memory`t14`t14`t14`t0.6 of 3.8 GiB`t", "disk`t/`t6`t6`t6`t6 of 121 GiB`t"
            "updates`t64 pending, 3 security`twarn", "reboot`tnone pending, none scheduled`tgood", "sessions`t0", "time`tThu 2026-10-22 02:45 CDT"
            "ipv4`teth0`t10.20.40.79/22", "problem`tbad`t4 failed units: hv-fcopy-daemon.service, hv-kvp-daemon.service, hv-vss-daemon.service, contoso-sync.service"
            "check`tunits", "services`tssh, cron, ntpsec, sssd active; adsysd on demand`tgood", "check`tservices", "check`tdisks <85%", "check`tmemory", "check`tclock", "check`treboot"
        )
        quiet = @(
            "name`tBEVSW-APP1", "ip`t10.20.40.80", "os`tUbuntu 24.04.5 LTS, kernel 6.8.0-147-generic", "uptime`t12d 6h 40m"
            "cpu`t3`t`t`t16 cores @ 3.1 GHz", "memory`t23`t`t`t7.3 of 31.3 GiB`t", "disk`t/`t25`t`t`t29 of 122 GiB`t", "disk`t/srv`t57`t40`t61`t140 of 246 GiB`tSSD"
            "sessions`t2  (alice bob)", "time`tThu 2026-10-22 07:16 UTC", "ipv4`teth0`t10.20.40.80/22", "ipv4`tbond0.120`t10.20.120.4/24"
            "services`tssh, cron, systemd-timesyncd active`tgood", "check`tunits", "check`tservices", "check`tdisks <85%", "check`tmemory", "check`tclock", "check`treboot", "check`ta-much-longer-check-name"
        )
        busy  = @(
            "name`th-psl-db01", "ip`t10.20.60.5", "os`tUbuntu 24.04.5 LTS with a description far longer than the row has room for, kernel 6.8.0-147-generic", "uptime`t412d 3h 2m"
            "cpu`t97`t12`t99`t64 cores @ 2.4 GHz with a model name long enough to go", "memory`t91`t40`t96`t115.2 of 125.6 GiB`tDDR5-4800"
            "disk`t/`t88`t80`t90`t96 of 109 GiB`tNVMe", "disk`t/var/lib/kubelet/pods/0c1e4a2b-1234-5678-9abc-def012345678/volumes/kubernetes.io~csi/pvc-1/mount`t99`t98`t99`t9.9 of 10.0 GiB`t"
            "updates`t12 pending, 4 security`twarn", "reboot`tpending: kernel 6.8.0-148`twarn", "services`tssh active; cron failed`tbad", "time`tThu 2026-10-22 23:59 UTC"
            "problem`tbad`tcron is failed", "problem`twarn`tmemory 91% in use: this text is long enough that it has to wrap onto the next line under itself, and then once more"
            "problem`twarn`t/var/lib/kubelet/pods/0c1e4a2b-1234-5678-9abc-def012345678/volumes/kubernetes.io~csi/pvc-1/mount is 99% full"
        )
        bare  = @("name`th-vsl-web1")
        # The update channel's notice (D14): under all clear; alone, where
        # nothing was checked; and two under problems, the first naming an
        # address too long for a line.
        noticed  = @(
            "name`tBEVSW-APP1", "ip`t10.20.40.80", "os`tUbuntu 24.04.5 LTS, kernel 6.8.0-147-generic"
            "services`tssh, cron active`tgood", "check`tservices", "check`treboot"
            "notice`tThis banner has an update available. See https://releases.example.com/usabanner for more info!"
        )
        alone    = @("name`th-vsl-web1", "notice`tThis banner has an update available. See https://git.example.com/contoso/usabanner/-/releases for more info!")
        troubled = @(
            "name`th-psl-db01", "ip`t10.20.60.5", "problem`tbad`tcron is failed", "problem`twarn`t/srv is 91% full", "check`tservices"
            "notice`tThis banner has an update available. See https://releases.example.com/contoso/a-path-long-enough-that-the-address-is-cut/usabanner for more info!"
            "notice`tA second line, as a notice of more than one line gives."
        )
        # Each record built with + is in parentheses: a comma binds tighter.
        utf8  = @(
            "name`th-vsl-web1", "ip`t10.20.40.79", ("os`tUbuntu 24.04.5 LTS, " + [char]0x00E9 + 'dition sp' + [char]0x00E9 + 'ciale ' + ([string][char]0x2014 * 30) + ', kernel 6.8')
            ("disk`t/mnt/donn" + [char]0x00E9 + "es`t50`t`t`t5 of 10 GiB`t"), "check`tunits"
        )
    }
    $script:Vlan = @(@{ tag = 40; name = 'Servers'; cidr = '10.20.40.0/22'; short = 'Srv'; color = 'Teal' })

    # Each case: a host's records (Machine: $Host is PowerShell's own), the
    # configuration's changes, the mode, and ASCII or not.
    $script:Cases = @(
        @{ Case = 'the lab host, truecolor'; Machine = 'lab'; Change = @{}; Mode = 'truecolor'; Ascii = $false }
        @{ Case = 'the lab host, 256, for a client that is not UTF-8'; Machine = 'lab'; Change = @{}; Mode = '256'; Ascii = $true }
        @{ Case = 'the lab host, 16 colours'; Machine = 'lab'; Change = @{}; Mode = '16'; Ascii = $false }
        @{ Case = 'the lab host, no colour, ASCII'; Machine = 'lab'; Change = @{}; Mode = 'none'; Ascii = $true }
        @{ Case = 'the lab host, mono'; Machine = 'lab'; Change = @{}; Mode = 'mono'; Ascii = $false }
        @{ Case = 'the lab host in its VLAN, uwu'; Machine = 'lab'; Change = @{ vlans = $Vlan; voice = 'uwu' }; Mode = 'truecolor'; Ascii = $false }
        @{ Case = 'a quiet host, HighContrast in Heavy'; Machine = 'quiet'; Change = @{ company = 'Contoso'; environment = 'PROD'; preset = 'HighContrast'; set = 'Heavy' }; Mode = 'truecolor'; Ascii = $false }
        @{ Case = 'a quiet host, Heavy drawn as Classic'; Machine = 'quiet'; Change = @{ company = 'Contoso'; environment = 'PROD'; preset = 'HighContrast'; set = 'Heavy' }; Mode = '256'; Ascii = $true }
        @{ Case = 'a busy host, the Mono preset in Double'; Machine = 'busy'; Change = @{ environment = 'LAB'; preset = 'Mono'; set = 'Double' }; Mode = '256'; Ascii = $false }
        @{ Case = 'a busy host, Classic16 in Rounded'; Machine = 'busy'; Change = @{ preset = 'Classic16'; set = 'Rounded' }; Mode = 'truecolor'; Ascii = $false }
        @{ Case = 'a busy host, uwu in Wavy'; Machine = 'busy'; Change = @{ voice = 'uwu'; set = 'Wavy' }; Mode = '16'; Ascii = $true }
        @{ Case = 'a busy host, leet in OneChar'; Machine = 'busy'; Change = @{ voice = 'leet'; set = 'OneChar'; char = '*'; environment = 'PUB' }; Mode = 'truecolor'; Ascii = $false }
        @{ Case = 'a busy host, random, no colour'; Machine = 'busy'; Change = @{ voice = 'random' }; Mode = 'none'; Ascii = $false }
        @{ Case = 'a host with no facts yet'; Machine = 'bare'; Change = @{}; Mode = 'truecolor'; Ascii = $false }
        @{ Case = 'a host with no facts yet, in its VLAN'; Machine = 'bare'; Change = @{ vlans = $Vlan; company = 'Contoso' }; Mode = '256'; Ascii = $false }
        @{ Case = 'UTF-8 in the facts, cut by characters'; Machine = 'utf8'; Change = @{}; Mode = 'truecolor'; Ascii = $false }
        @{ Case = 'an update notice under all clear'; Machine = 'noticed'; Change = @{}; Mode = 'truecolor'; Ascii = $false }
        @{ Case = 'an update notice under all clear, mono'; Machine = 'noticed'; Change = @{}; Mode = 'mono'; Ascii = $false }
        @{ Case = 'an update notice alone, nothing checked'; Machine = 'alone'; Change = @{}; Mode = '256'; Ascii = $true }
        @{ Case = 'two notices under problems, an address cut, HighContrast'; Machine = 'troubled'; Change = @{ preset = 'HighContrast' }; Mode = '16'; Ascii = $false }
        @{ Case = 'two notices under problems, no colour'; Machine = 'troubled'; Change = @{}; Mode = 'none'; Ascii = $false }
        # The role is drawn ahead, beside the tier (D29): the frame's rows, then awk's.
        @{ Case = 'the lab host with a role'; Machine = 'lab'; Change = @{ role = 'Web front end' }; Mode = 'truecolor'; Ascii = $false }
        @{ Case = 'a busy host with a role longer than its row, uwu'; Machine = 'busy'; Change = @{ role = 'Line-of-business applications for the finance and payroll teams'; voice = 'uwu' }; Mode = '16'; Ascii = $true }
        @{ Case = 'a host with no facts yet, with a role'; Machine = 'bare'; Change = @{ role = 'Kiosk'; environment = 'PUB' }; Mode = '256'; Ascii = $false }
    )
    $script:Pairs = @(foreach ($awk in $Awks) { foreach ($case in $Cases) { $case + @{ Awk = $awk; Lines = $Records[$case.Machine] } } })
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'Golden.ps1')
    $script:PostLogin = Join-Path $repoRoot 'UsaBanner' 'linux' 'postlogin.sh'

    function New-TestConfig {
        # In:  the changes to the defaults (company, environment, preset, set, char, voice, vlans)
        # Out: the configuration
        # Why: each case draws a different banner
        param([hashtable]$Change)
        $config = InModuleScope UsaBanner { Get-UsaBannerConfigDefault }
        foreach ($key in $Change.Keys) {
            switch ($key) {
                'preset' { $config['color']['preset'] = $Change[$key] }
                'set' { $config['border']['set'] = $Change[$key] }
                'char' { $config['border']['char'] = $Change[$key] }
                default { $config[$key] = $Change[$key] }
            }
        }
        $config
    }

    function Invoke-BothWays {
        # In:  the configuration, the records, the mode, -Ascii, and the awk to run
        # Out: @{ Module; Login }: the lines the module draws from the records,
        #      and those postlogin.sh draws from them into the frame
        # Why: the login renderer must draw exactly what the module draws
        param([hashtable]$Config, [string[]]$Lines, [string]$Mode, [bool]$Ascii, [string]$Awk)
        $parameters = @{ Config = $Config; Lines = $Lines; Mode = $Mode; Ascii = $Ascii }
        $both = InModuleScope UsaBanner -Parameters $parameters {
            param($Config, $Lines, $Mode, $Ascii)
            $facts = ConvertFrom-UsaBannerFactRecord -Line $Lines
            @{
                Module = @(Get-UsaBannerPostLogon -Config $Config -Os ubuntu -Facts $facts -Mode $Mode -AsciiOnly:$Ascii)
                Frame  = @(New-UsaBannerLoginFrame -Config $Config -Os ubuntu -Name ([string]$facts['Name']) -Ip ([string]$facts['Ip']) -Mode $Mode -AsciiOnly:$Ascii)
            }
        }
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $bin = Join-Path $dir 'bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText((Join-Path $dir 'postlogon.frame'), ($both.Frame -join "`n") + "`n", $utf8)
        [System.IO.File]::WriteAllText((Join-Path $dir 'records'), ($Lines -join "`n") + "`n", $utf8)
        # The awk under test, first on PATH.
        [System.IO.File]::WriteAllText((Join-Path $bin 'awk'), "#!/bin/sh`nexec $Awk `"`$@`"`n")
        & chmod 755 (Join-Path $bin 'awk')
        $login = @(& env -i "PATH=$($bin):/usr/bin:/bin" sh $PostLogin (Join-Path $dir 'postlogon.frame') (Join-Path $dir 'records'))
        @{ Module = $both.Module; Login = $login }
    }
}

Describe 'linux/postlogin.sh' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'is sh that sh -n accepts' {
        & sh -n $PostLogin
        $LASTEXITCODE | Should -Be 0
    }

    It 'finds an awk to test with' {
        $Awks | Should -Not -BeNullOrEmpty
    }

    It 'draws what the module draws: <Case>, under <Awk>' -ForEach $Pairs {
        $drawn = Invoke-BothWays -Config (New-TestConfig -Change $Change) -Lines $Lines -Mode $Mode -Ascii $Ascii -Awk $Awk
        $drawn.Module.Count | Should -BeGreaterThan 0
        Show-UsaBannerEscape $drawn.Login | Should -BeExactly (Show-UsaBannerEscape $drawn.Module)
    }

    It 'prints nothing when there is no frame yet' {
        $records = Join-Path $TestDrive 'nothing.records'
        [System.IO.File]::WriteAllText($records, "name`th-vsl-web1`n")
        $out = @(& env -i 'PATH=/usr/bin:/bin' sh $PostLogin (Join-Path $TestDrive 'no.frame') $records)
        $LASTEXITCODE | Should -Be 0
        $out | Should -BeNullOrEmpty
    }

    It 'runs facts.sh beside it when it is given no records' {
        # A copy whose facts.sh prints the lab host's records.
        $copy = Join-Path $TestDrive 'copy'
        New-Item -ItemType Directory -Path $copy -Force | Out-Null
        Copy-Item -LiteralPath $PostLogin, (Join-Path (Split-Path $PostLogin) 'postlogin.awk') -Destination $copy
        $lines = @("name`th-vsl-web1", "os`tUbuntu 24.04.5 LTS", "check`tunits")
        [System.IO.File]::WriteAllText((Join-Path $copy 'facts.sh'), "printf '%s\n' '$($lines -join "' '")'`n")
        $config = New-TestConfig -Change @{}
        $frame = @(InModuleScope UsaBanner -Parameters @{ Config = $config } { param($Config) New-UsaBannerLoginFrame -Config $Config -Os ubuntu -Name 'h-vsl-web1' -Mode none })
        $framePath = Join-Path $copy 'postlogon.frame'
        [System.IO.File]::WriteAllText($framePath, ($frame -join "`n") + "`n")
        $expected = InModuleScope UsaBanner -Parameters @{ Config = $config; Lines = $lines } { param($Config, $Lines) @(Get-UsaBannerPostLogon -Config $Config -Os ubuntu -Facts (ConvertFrom-UsaBannerFactRecord -Line $Lines) -Mode none) }
        $out = @(& env -i 'PATH=/usr/bin:/bin' sh (Join-Path $copy 'postlogin.sh') $framePath)
        ($out -join "`n") | Should -BeExactly ($expected -join "`n")
    }
}

Describe 'the panel, for a mount point longer than its row' {
    It 'cuts the label with ~ and keeps the value, where it once could not draw the panel at all' {
        $lines = @("name`th-psl-db01", "disk`t/var/lib/kubelet/pods/0c1e4a2b-1234-5678-9abc-def012345678/volumes/kubernetes.io~csi/pvc-1/mount`t99`t98`t99`t9.9 of 10.0 GiB`t")
        $drawn = InModuleScope UsaBanner -Parameters @{ Lines = $lines } {
            param($Lines)
            @(Get-UsaBannerPostLogon -Config (Get-UsaBannerConfigDefault) -Os ubuntu -Facts (ConvertFrom-UsaBannerFactRecord -Line $Lines) -Mode none -AsciiOnly)
        }
        $row = @($drawn | Where-Object { $_ -like '*disk /var/lib/kube*' })
        $row.Count | Should -Be 1
        $row[0] | Should -Match '^\|  disk /var/lib/kubelet/p~ ########## 99%  9\.9 of 10\.0 GiB +\|$'
        $row[0].Length | Should -Be 64
    }
}
