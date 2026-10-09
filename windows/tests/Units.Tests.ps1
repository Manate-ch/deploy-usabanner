# Pester 5 tests for rootfs/usr/local/share/manatech/units.sh: the systemd
# units install.sh writes. Each layout is generated into TestDrive with sh and
# checked with systemd's own systemd-analyze verify, then its key lines are
# pinned. Linux only: they need sh and systemd-analyze.

BeforeAll {
    $script:UnitsSh = Join-Path $PSScriptRoot '../../rootfs/usr/local/share/manatech/units.sh'

    # New-Units LAYOUT [ARGS] - a new folder holding the units that
    # "units_LAYOUT FOLDER ARGS" (units.sh) writes.
    function New-Units {
        param([string]$Layout, [string[]]$Arguments = @())
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        & sh -c ". `"`$1`"; shift; units_$Layout `"`$@`"" sh $UnitsSh $dir @Arguments
        if ($LASTEXITCODE -ne 0) { throw "units_$Layout failed ($LASTEXITCODE)" }
        $dir
    }

    # Get-Line DIR FILE KEY - the lines of FILE in DIR that start with KEY=.
    function Get-Line {
        param([string]$Dir, [string]$File, [string]$Key)
        @(Get-Content -LiteralPath (Join-Path $Dir $File) | Where-Object { $_ -like "$Key=*" })
    }

    # Test-Verify DIR - systemd-analyze verify over every unit in DIR; its
    # output, with the exit code on the last line.
    function Test-Verify {
        param([string]$Dir)
        $files = @(Get-ChildItem -LiteralPath $Dir -File | ForEach-Object { $_.FullName })
        $out = & systemd-analyze verify @files 2>&1 | Out-String
        "$out`nexit=$LASTEXITCODE"
    }
}

Describe 'units.sh' -Skip:(-not ((Get-Command sh -ErrorAction SilentlyContinue) -and (Get-Command systemd-analyze -ErrorAction SilentlyContinue))) {
    It 'has a systemd-analyze verify here that rejects a broken unit (else a pass proves nothing)' {
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dir 'broken.service'), "[Service]`nType=oneshot`nExecStart=/nonexistent/manatech-probe`n")
        Test-Verify $dir | Should -Not -Match 'exit=0$'
    }

    Context 'Group Policy delivery (units_adsys)' {
        BeforeAll { $script:Adsys = New-Units adsys }

        It 'writes the timer, its service, the publish watcher and its service' {
            @(Get-ChildItem -LiteralPath $Adsys -File | ForEach-Object { $_.Name } | Sort-Object) |
                Should -Be @('manatech-motd-publish.path', 'manatech-motd-publish.service',
                    'manatech-motd-update.service', 'manatech-motd-update.timer')
        }
        It 'passes systemd-analyze verify' {
            Test-Verify $Adsys | Should -Match 'exit=0$'
        }
        It 'watches the GPT.INI of the ADSys copy of SYSVOL, and starts the publish service' {
            Get-Line $Adsys 'manatech-motd-publish.path' 'PathChanged' | Should -Be 'PathChanged=/var/cache/adsys/sysvol/assets/GPT.INI'
            Get-Line $Adsys 'manatech-motd-publish.path' 'Unit' | Should -Be 'Unit=manatech-motd-publish.service'
        }
        It 'runs adsys-startup.sh from the ADSys copy: in full from the timer, --if-new-version from the watcher' {
            Get-Line $Adsys 'manatech-motd-update.service' 'ExecStart' |
                Should -Be 'ExecStart=/bin/sh /var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh'
            Get-Line $Adsys 'manatech-motd-publish.service' 'ExecStart' |
                Should -Be 'ExecStart=/bin/sh /var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh --if-new-version'
        }
        It 'does nothing until the ADSys copy holds adsys-startup.sh (a template image before it is joined)' {
            foreach ($f in 'manatech-motd-update.service', 'manatech-motd-publish.service') {
                Get-Line $Adsys $f 'ConditionPathExists' |
                    Should -Be 'ConditionPathExists=/var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh'
            }
        }
    }

    Context 'the shell scripts (install.sh itself is not run by any test)' {
        It 'sh -n rejects a broken script here (else the parse checks prove nothing)' {
            $f = Join-Path $TestDrive 'broken.sh'
            [System.IO.File]::WriteAllText($f, "if true; then`necho unterminated`n")
            & sh -n $f 2>&1 | Out-Null
            $LASTEXITCODE | Should -Not -Be 0
        }
        It '<Name> parses under sh -n' -TestCases @(
            @{ Name = 'install.sh'; Rel = '../../install.sh' }
            @{ Name = 'adsys-startup.sh'; Rel = '../../adsys-startup.sh' }
            @{ Name = 'units.sh'; Rel = '../../rootfs/usr/local/share/manatech/units.sh' }
            @{ Name = 'ad-description.sh'; Rel = '../../rootfs/usr/local/share/manatech/ad-description.sh' }
        ) {
            $out = & sh -n (Join-Path $PSScriptRoot $Rel) 2>&1 | Out-String
            "$out`nexit=$LASTEXITCODE" | Should -Match 'exit=0$'
        }
    }

    Context 'a git clone (units_clone)' {
        It 'runs install.sh with a space before its options: <Run>' -TestCases @(
            @{ Run = '--update --ad'; Line = 'ExecStart=/bin/sh /opt/manatech-motd/install.sh --update --ad' }
            @{ Run = '--update'; Line = 'ExecStart=/bin/sh /opt/manatech-motd/install.sh --update' }
            @{ Run = ''; Line = 'ExecStart=/bin/sh /opt/manatech-motd/install.sh' }
        ) {
            $dir = New-Units clone @('/opt/manatech-motd', $Run)
            Get-Line $dir 'manatech-motd-update.service' 'ExecStart' | Should -Be $Line
        }
        It 'writes only the timer and its service, and passes systemd-analyze verify' {
            $dir = New-Units clone @('/opt/manatech-motd', '--update')
            @(Get-ChildItem -LiteralPath $dir -File | ForEach-Object { $_.Name } | Sort-Object) |
                Should -Be @('manatech-motd-update.service', 'manatech-motd-update.timer')
            Test-Verify $dir | Should -Match 'exit=0$'
        }
    }
}
