# Pester tests for rootfs/usr/local/share/manatech/ad-description.sh, run under sh with an empty
# environment against a root in TestDrive (MANATECH_ROOT), and for install.sh's --ad step. Linux
# only: they need sh. klist, kinit, kdestroy, resolvectl and ldapsearch are stubs: klist lists the
# machine's key, resolvectl two DCs, and kinit and ldapsearch answer as STUB_KINIT, STUB_LDAP_1
# and STUB_LDAP_2 say, "<exit status>:<line>": the line on stderr, or, when ldapsearch exits 0,
# the description it returns.

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '../..'
    $script:Script = Join-Path $RepoRoot 'rootfs/usr/local/share/manatech/ad-description.sh'
    $script:Bin = Join-Path $TestDrive 'bin'
    New-Item -ItemType Directory -Path $Bin -Force | Out-Null
    $stubs = @{
        klist      = @'
#!/bin/sh
printf 'Keytab name: FILE:/etc/krb5.keytab\nKVNO Principal\n---- ---------\n   2 BEVSW-APP1$@AD.EXAMPLE\n'
'@
        kinit      = @'
#!/bin/sh
code=${STUB_KINIT%%:*}
line=${STUB_KINIT#*:}
[ -n "$line" ] && printf '%s\n' "$line" >&2
exit "$code"
'@
        kdestroy   = @'
#!/bin/sh
exit 0
'@
        resolvectl = @'
#!/bin/sh
printf '_ldap._tcp.dc._msdcs.ad.example IN SRV 0 100 389 dc1.ad.example.\n_ldap._tcp.dc._msdcs.ad.example IN SRV 0 100 389 dc2.ad.example.\n'
'@
        ldapsearch = @'
#!/bin/sh
dc=
while [ $# -gt 0 ]; do
	case $1 in -H) dc=${2#ldap://}; shift ;; esac
	shift
done
case $dc in
dc1.ad.example) answer=$STUB_LDAP_1 ;;
dc2.ad.example) answer=$STUB_LDAP_2 ;;
*) exit 255 ;;
esac
code=${answer%%:*}
line=${answer#*:}
if [ "$code" = 0 ]; then
	printf 'dn: CN=BEVSW-APP1,CN=Computers,DC=ad,DC=example\ndescription: %s\n' "$line"
else
	printf '%s\n' "$line" >&2
fi
exit "$code"
'@
    }
    foreach ($name in $stubs.Keys) {
        $path = Join-Path $Bin $name
        [System.IO.File]::WriteAllText($path, ($stubs[$name] -replace "`r", '') + "`n")
        & chmod 755 $path
    }

    # Invoke-AdDescription [-Kinit] [-Ldap1] [-Ldap2] [-Before TEXT] [-Unreached TEXT]
    # Out: @{ Output; Exit; Cache; Note }: what the script printed, its exit status, and its
    #      var/lib/manatech/ad-description and ad-unreached afterwards ($null when absent).
    #      -Before and -Unreached are those two files before it ran.
    function Invoke-AdDescription {
        param([string]$Kinit = '0:', [string]$Ldap1 = '255:', [string]$Ldap2 = '255:', [string]$Before, [string]$Unreached)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $lib = Join-Path $root 'var/lib/manatech'
        New-Item -ItemType Directory -Path (Join-Path $root 'etc'), $lib -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $root 'etc/krb5.keytab'), 'key')
        if ($Before) { [System.IO.File]::WriteAllText((Join-Path $lib 'ad-description'), "$Before`n") }
        if ($Unreached) { [System.IO.File]::WriteAllText((Join-Path $lib 'ad-unreached'), $Unreached) }
        $output = & env -i "PATH=$($Bin):/usr/bin:/bin" "MANATECH_ROOT=$root" "STUB_KINIT=$Kinit" "STUB_LDAP_1=$Ldap1" "STUB_LDAP_2=$Ldap2" sh $Script 2>&1 | Out-String
        $exit = $LASTEXITCODE
        $read = { param($Name) $path = Join-Path $lib $Name; if (Test-Path -LiteralPath $path) { [System.IO.File]::ReadAllText($path) } }
        @{ Output = $output; Exit = $exit; Cache = (& $read 'ad-description'); Note = (& $read 'ad-unreached') }
    }
}

Describe 'ad-description.sh' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'is sh that sh -n accepts' {
        & sh -n $Script
        $LASTEXITCODE | Should -Be 0
    }

    It 'caches the description the first DC gives, and removes the note of an earlier outage' {
        $run = Invoke-AdDescription -Ldap1 '0:PROD: web front end' -Unreached "1792645632`ttried: dc1.ad.example dc2.ad.example`n"
        $run.Exit | Should -Be 0
        $run.Cache | Should -BeExactly "PROD: web front end`n"
        $run.Note | Should -BeNullOrEmpty
        $run.Output | Should -Match '"PROD: web front end" \(from dc1\.ad\.example\)'
    }

    It 'asks the next DC when the first cannot be contacted' {
        $run = Invoke-AdDescription -Ldap1 '255:ldap_sasl_interactive_bind: Can''t contact LDAP server (-1)' -Ldap2 '0:LAB: test box'
        $run.Exit | Should -Be 0
        $run.Cache | Should -BeExactly "LAB: test box`n"
        $run.Output | Should -Match '\(from dc2\.ad\.example\)'
    }

    It 'warns, keeps the last description and leaves a note, when <Case>' -ForEach @(
        @{ Case = 'no KDC can be contacted'; Kinit = '1:kinit: Cannot contact any KDC for realm ''AD.EXAMPLE'' while getting initial credentials'; Ldap1 = '0:never asked'; Ldap2 = '0:never asked'; What = 'kinit: no KDC for AD.EXAMPLE answered' }
        @{ Case = 'kinit does not answer in time'; Kinit = '124:'; Ldap1 = '0:never asked'; Ldap2 = '0:never asked'; What = 'kinit: no KDC for AD.EXAMPLE answered' }
        @{ Case = 'no DC can be contacted over LDAP'; Kinit = '0:'; Ldap1 = '255:ldap_sasl_interactive_bind: Can''t contact LDAP server (-1)'; Ldap2 = '124:'; What = 'tried: dc1.ad.example dc2.ad.example' }
    ) {
        $run = Invoke-AdDescription -Kinit $Kinit -Ldap1 $Ldap1 -Ldap2 $Ldap2 -Before 'PROD: web front end'
        $run.Exit | Should -Be 75
        $run.Output | Should -Match ([regex]::Escape("manatech-motd: ad: WARNING: could not contact any domain controller ($What); kept the last description"))
        $run.Cache | Should -BeExactly "PROD: web front end`n"
        $run.Note | Should -Match ("^\d+`t" + [regex]::Escape($What) + "`n$")
    }

    It 'fails, naming the DC and what it said, when a DC answers with an error' {
        $run = Invoke-AdDescription -Ldap1 '49:ldap_sasl_interactive_bind: Invalid credentials (49)' -Ldap2 '255:ldap_sasl_interactive_bind: Can''t contact LDAP server (-1)' -Before 'PROD: web front end'
        $run.Exit | Should -Be 1
        $run.Output | Should -Match ([regex]::Escape('no DC gave the description; dc1.ad.example: ldap_sasl_interactive_bind: Invalid credentials (49) (exit 49)'))
        $run.Note | Should -BeNullOrEmpty
        $run.Cache | Should -BeExactly "PROD: web front end`n"
    }

    It 'fails, saying why, when kinit is refused for another reason' {
        $run = Invoke-AdDescription -Kinit '1:kinit: Client ''BEVSW-APP1$@AD.EXAMPLE'' not found in Kerberos database while getting initial credentials' -Before 'PROD: web front end'
        $run.Exit | Should -Be 1
        $run.Output | Should -Match ([regex]::Escape("kinit as BEVSW-APP1`$@AD.EXAMPLE failed: kinit: Client 'BEVSW-APP1`$@AD.EXAMPLE' not found in Kerberos database"))
        $run.Note | Should -BeNullOrEmpty
    }
}

Describe 'install.sh --ad' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    BeforeAll {
        # The --ad step exactly as install.sh has it, run under set -eu as install.sh runs,
        # with ad-description.sh a stub that exits as each test says.
        $text = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'install.sh'))
        $script:AdBlock = [regex]::Match($text, '(?ms)^if \[ -n "\$ad" \]; then\n.*?^fi\n').Value
    }

    It 'finds the --ad step in install.sh' {
        $AdBlock | Should -Not -BeNullOrEmpty
    }

    It 'leaves rc <Rc> when ad-description.sh exits <Status>' -ForEach @(
        @{ Status = 0; Rc = 0 }
        @{ Status = 75; Rc = 0 }
        @{ Status = 1; Rc = 1 }
    ) {
        $src = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $dir = Join-Path $src 'usr/local/share/manatech'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $dir 'ad-description.sh'), "exit $Status`n")
        $program = "set -eu`nsrc='$src'`nad=1`nrc=0`n" + $AdBlock + 'echo "rc=$rc"' + "`n"
        (& sh -c $program 2>&1 | Out-String) | Should -Match "(?m)^rc=$Rc$"
    }
}
