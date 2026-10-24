# The AD Description reader (docs/DECISIONS.md, D29). UsaBanner/linux/
# ad-description.sh runs under sh with an empty environment, against a root in
# TestDrive (USABANNER_ROOT). klist, kinit, kdestroy, resolvectl and ldapsearch
# are stubs, first on PATH, and each logs its call to STUB_LOG:
#   klist       prints the keytab file, which holds what klist -k prints;
#   kinit       answers as STUB_KINIT says, "<exit status>:<line>": the line
#               on stderr, and, with status 0, the credential cache it made;
#               "stop" sends the reader TERM, as systemd's stop of the
#               periodic job does, and fails;
#   resolvectl  prints two SRV records, none when STUB_SRV is none;
#   ldapsearch  answers for each DC as STUB_LDAP_1 (dc1.ad.example, and the
#               domain's own name) and STUB_LDAP_2 (dc2.ad.example) say, the
#               same way: the line on stderr; with status 0, the computer's
#               entry, and the line as its attribute lines, none for an empty
#               Description; NOENTRY, no entry at all. Without the credential
#               cache kinit made, it fails as the real one does.
# The tests need sh and the usual tools (awk, sed, tr, timeout), so they run
# on Linux only.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:Reader = Join-Path $repoRoot 'UsaBanner' 'linux' 'ad-description.sh'
    $script:Sh = (Get-Command sh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source

    # What every stub does first: log its name, arguments, what its standard
    # input is, and the credential cache it was given, a tab between.
    $script:Head = @'
printf '%s\t%s\t%s\t%s\n' "@NAME@" "$*" "$(readlink /proc/self/fd/0)" "${KRB5CCNAME-}" >>"$STUB_LOG"
'@

    $script:Stubs = [ordered]@{
        klist      = @'
[ "$1" = -k ] && [ -r "$2" ] || exit 1
cat "$2"
'@
        kinit      = @'
[ "$STUB_KINIT" = stop ] && { kill -TERM "$STUB_READER_PID"; exit 1; }
code=${STUB_KINIT%%:*}
line=${STUB_KINIT#*:}
[ -n "$line" ] && printf '%s\n' "$line" >&2
[ "$code" = 0 ] && : >"${KRB5CCNAME#FILE:}"
exit "$code"
'@
        kdestroy   = @'
exit 0
'@
        resolvectl = @'
[ "${STUB_SRV-}" = none ] && exit 1
printf '_ldap._tcp.dc._msdcs.ad.example IN SRV 0 100 389 dc1.ad.example.\n_ldap._tcp.dc._msdcs.ad.example IN SRV 0 100 389 dc2.ad.example.\n\n-- Information acquired via protocol DNS in 1.2ms.\n'
'@
        ldapsearch = @'
dc=
while [ $# -gt 0 ]; do
	case $1 in -H) dc=${2#ldap://}; shift ;; esac
	shift
done
case $dc in
dc1.ad.example | ad.example) answer=$STUB_LDAP_1 ;;
dc2.ad.example) answer=$STUB_LDAP_2 ;;
*) exit 255 ;;
esac
code=${answer%%:*}
line=${answer#*:}
if [ "$code" != 0 ]; then
	printf '%s\n' "$line" >&2
	exit "$code"
fi
[ -e "${KRB5CCNAME#FILE:}" ] || { echo 'ldap_sasl_interactive_bind: Local error (-2)' >&2; exit 254; }
[ "$line" = NOENTRY ] && exit 0
printf 'dn: CN=APP1,CN=Computers,DC=ad,DC=example\n'
[ -z "$line" ] || printf '%s\n' "$line"
# The continuation references a real DC prints after the entry, even with -LLL (lab, 2026-10-23).
printf '\n# refldap://ForestDnsZones.ad.example/DC=ForestDnsZones,DC=ad,DC=example\n'
'@
    }

    # The keytab file's content, a klist listing: the machine's key among
    # others, as a keytab made by a join has it.
    $script:Listing = @'
Keytab name: FILE:/etc/krb5.keytab
KVNO Principal
---- --------------------------------------------------------------------------
   2 host/app1.ad.example@AD.EXAMPLE
   2 APP1$@AD.EXAMPLE
   2 RestrictedKrbHost/app1.ad.example@AD.EXAMPLE
'@

    function New-StubBin {
        # In:  a folder, and -Except, the name of a stub to leave out
        # Out: nothing; the folder holds an executable stub for each tool
        # Why: each run has a folder of its own, so a test can leave one tool out
        param([string]$Path, [string]$Except)
        $null = New-Item -ItemType Directory -Path $Path -Force
        foreach ($name in $Stubs.Keys) {
            if ($name -eq $Except) { continue }
            $file = Join-Path $Path $name
            [System.IO.File]::WriteAllText($file, (("#!/bin/sh`n" + $Head.Replace('@NAME@', $name) + "`n" + $Stubs[$name] + "`n") -replace "`r", ''))
            [System.IO.File]::SetUnixFileMode($file, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute')
        }
    }

    function Invoke-AdDescription {
        # In:  -Kinit, -Ldap1, -Ldap2, how the stubs answer; -Before, the Description the
        #      cache holds before the run; -Files, files to write under the root over the
        #      default (the keytab), $null to leave one out; -Variables, more variables for
        #      the run; -Without, a tool left off PATH, which then holds nothing else;
        #      -Umask, the umask the caller has; -Hold, a second name (held) for the cache
        #      file as it was before the run
        # Out: @{ Output; Exit; Cache; Held; Files; Calls; Left; Root; Tmp }: what the script
        #      printed and its exit status; var/lib/usabanner/ad-description afterwards ($null
        #      when absent), what the second name holds, and the names in the folder; the
        #      stubs' calls, each with Name, Arguments, Stdin and Ccache; the names left in
        #      the temporary folder; the root and the temporary folder
        # Why: the periodic job runs the reader as root, with a bare environment
        param(
            [string]$Kinit = '0:', [string]$Ldap1 = '255:', [string]$Ldap2 = '255:',
            [string]$Before, [hashtable]$Files = @{}, [hashtable]$Variables = @{},
            [string]$Without, [string]$Umask = '022', [switch]$Hold
        )
        $run = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $root = Join-Path $run 'root'
        $tmp = Join-Path $run 'tmp'
        $bin = Join-Path $run 'bin'
        $log = Join-Path $run 'stubs.log'
        $captured = Join-Path $run 'output.txt'
        $fed = Join-Path $run 'stdin.txt'
        $folder = Join-Path $root 'var/lib/usabanner'
        $null = New-Item -ItemType Directory -Path $root, $tmp -Force
        [System.IO.File]::WriteAllText($fed, "nothing in the script may read this`n")
        New-StubBin -Path $bin -Except $Without

        $content = @{ 'etc/krb5.keytab' = $Listing + "`n" }
        foreach ($key in $Files.Keys) { $content[$key] = $Files[$key] }
        if ($Before) { $content['var/lib/usabanner/ad-description'] = "$Before`n" }
        foreach ($key in $content.Keys) {
            if ($null -eq $content[$key]) { continue }
            $path = Join-Path $root $key
            $null = New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force
            [System.IO.File]::WriteAllText($path, $content[$key])
        }
        if ($Hold) { $null = New-Item -ItemType HardLink -Path (Join-Path $folder 'held') -Target (Join-Path $folder 'ad-description') }

        $assignments = @("PATH=$(if ($Without) { $bin } else { "$($bin):/usr/bin:/bin" })", "USABANNER_ROOT=$root", "TMPDIR=$tmp", "STUB_LOG=$log", "STUB_KINIT=$Kinit", "STUB_LDAP_1=$Ldap1", "STUB_LDAP_2=$Ldap2")
        foreach ($key in $Variables.Keys) { $assignments += "$key=$($Variables[$key])" }
        # The wrapper sets the umask, gives the script a file for its standard input (not
        # /dev/null, so a stub that inherits it shows), and sends all the script prints, both
        # streams, to a file. Its process ID, which exec keeps, is the reader's.
        & env -i @assignments $Sh -c 'STUB_READER_PID=$$; export STUB_READER_PID; umask "$1"; exec "$2" "$3" <"$5" >"$4" 2>&1' ad-description $Umask $Sh $Reader $captured $fed
        $exit = $LASTEXITCODE

        $cache = Join-Path $folder 'ad-description'
        $calls = @(if (Test-Path -LiteralPath $log) {
                foreach ($line in [System.IO.File]::ReadAllLines($log)) {
                    $field = $line -split "`t"
                    [pscustomobject]@{ Name = $field[0]; Arguments = $field[1]; Stdin = $field[2]; Ccache = $field[3] }
                }
            })
        @{
            Output = [System.IO.File]::ReadAllText($captured)
            Exit   = $exit
            Cache  = if (Test-Path -LiteralPath $cache -PathType Leaf) { [System.IO.File]::ReadAllText($cache) }
            Held   = if ($Hold) { [System.IO.File]::ReadAllText((Join-Path $folder 'held')) }
            Files  = @(Get-ChildItem -LiteralPath $folder -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-Object)
            Calls  = $calls
            Left   = @(Get-ChildItem -LiteralPath $tmp -Force | ForEach-Object { $_.Name })
            Root   = $root
            Tmp    = $tmp
        }
    }

    function Get-CallCount {
        # In:  a run from Invoke-AdDescription, and a tool's name
        # Out: how many times the stub of that tool was called
        # Why: a test says a tool was asked, or never asked
        param($Run, [string]$Name)
        @($Run.Calls | Where-Object { $_.Name -eq $Name }).Count
    }
}

Describe 'linux/ad-description.sh' -Skip:$IsWindows {
    It 'is sh that sh -n accepts' {
        & sh -n $Reader
        $LASTEXITCODE | Should -Be 0
    }

    It 'caches the first DC''s Description, one line, and says which DC gave it' {
        $run = Invoke-AdDescription -Ldap1 '0:description: PROD: web front end' -Ldap2 '0:description: never asked'
        $run.Exit | Should -Be 0
        $run.Cache | Should -BeExactly "PROD: web front end`n"
        $run.Output | Should -BeExactly "usabanner: ad: `"PROD: web front end`" (from dc1.ad.example)`n"
        Get-CallCount $run 'ldapsearch' | Should -Be 1
    }

    It 'asks as this computer for its own object, in a private credential cache, reading nothing from stdin' {
        $run = Invoke-AdDescription -Ldap1 '0:description: PROD: web front end'
        $keytab = Join-Path $run.Root 'etc/krb5.keytab'
        ($run.Calls | ForEach-Object { $_.Name }) -join ' ' | Should -BeExactly 'klist kinit resolvectl ldapsearch kdestroy'
        $call = @{}
        foreach ($entry in $run.Calls) { $call[$entry.Name] = $entry }
        $call.klist.Arguments | Should -BeExactly "-k $keytab"
        $call.kinit.Arguments | Should -BeExactly "-k -t $keytab APP1`$@AD.EXAMPLE"
        $call.resolvectl.Arguments | Should -BeExactly 'query -t SRV _ldap._tcp.dc._msdcs.ad.example'
        # -N: the DC's name from SRV as given, not canonicalized by reverse DNS.
        foreach ($part in '-Y GSSAPI -N ', '-o ldif-wrap=no', '-H ldap://dc1.ad.example', '-b DC=ad,DC=example', '(sAMAccountName=APP1$)') {
            $call.ldapsearch.Arguments | Should -Match ([regex]::Escape($part)) -Because $part
        }
        $call.ldapsearch.Arguments | Should -Match ' description$'
        $call.kinit.Ccache | Should -Match ('^FILE:' + [regex]::Escape($run.Tmp) + '/tmp\.[^/]+/ccache$')
        $call.ldapsearch.Ccache | Should -BeExactly $call.kinit.Ccache
        $call.kdestroy.Ccache | Should -BeExactly $call.kinit.Ccache
        @($run.Calls | Where-Object { $_.Stdin -ne '/dev/null' }).Count | Should -Be 0
    }

    It 'asks the next DC when the first <Case>' -ForEach @(
        @{ Case = 'cannot be contacted'; Ldap1 = '255:ldap_sasl_interactive_bind: Can''t contact LDAP server (-1)' }
        @{ Case = 'does not answer in time'; Ldap1 = '124:' }
        @{ Case = 'answers with an error'; Ldap1 = '49:ldap_sasl_interactive_bind: Invalid credentials (49)' }
    ) {
        $run = Invoke-AdDescription -Ldap1 $Ldap1 -Ldap2 '0:description: LAB: test box' -Before 'PROD: web front end'
        $run.Exit | Should -Be 0
        $run.Cache | Should -BeExactly "LAB: test box`n"
        $run.Output | Should -Match ([regex]::Escape('"LAB: test box" (from dc2.ad.example)'))
        Get-CallCount $run 'ldapsearch' | Should -Be 2
    }

    It 'asks the domain''s own name when DNS gives no SRV record, letting reverse DNS find the DC''s name' {
        $run = Invoke-AdDescription -Ldap1 '0:description: LAB: test box' -Variables @{ STUB_SRV = 'none' }
        $run.Exit | Should -Be 0
        $run.Cache | Should -BeExactly "LAB: test box`n"
        $run.Output | Should -Match ([regex]::Escape('"LAB: test box" (from ad.example)'))
        @($run.Calls | Where-Object { $_.Name -eq 'ldapsearch' })[0].Arguments | Should -Not -Match '(^| )-N( |$)'
    }

    It 'caches an empty Description as an empty line, replacing a cached one' {
        $run = Invoke-AdDescription -Ldap1 '0:' -Before 'PROD: web front end'
        $run.Exit | Should -Be 0
        $run.Cache | Should -BeExactly "`n"
        $run.Output | Should -BeExactly "usabanner: ad: empty on APP1`$ (from dc1.ad.example)`n"
    }

    It 'caches the first line of a Description given as <Case>' -ForEach @(
        @{ Case = 'base64 text with an accented letter'; Ldif = 'description:: UFJPRDogY2Fmw6k='; Expected = "PROD: caf$([char]0xE9)" }
        @{ Case = 'base64 text of two lines'; Ldif = 'description:: ' + [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("first line`nsecond line")); Expected = 'first line' }
        @{ Case = 'two plain values'; Ldif = "description: first value`ndescription: second value"; Expected = 'first value' }
    ) {
        $run = Invoke-AdDescription -Ldap1 "0:$Ldif" -Before 'PROD: web front end'
        $run.Exit | Should -Be 0
        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $run.Root 'var/lib/usabanner/ad-description'))
        [Convert]::ToHexString($bytes) | Should -BeExactly ([Convert]::ToHexString([System.Text.Encoding]::UTF8.GetBytes("$Expected`n")))
    }

    It 'warns, keeps the last Description and writes no other file, when <Case>' -ForEach @(
        @{ Case = 'no KDC can be contacted'; Kinit = '1:kinit: Cannot contact any KDC for realm ''AD.EXAMPLE'' while getting initial credentials'; Ldap1 = '0:description: never asked'; Ldap2 = '0:description: never asked'; Variables = @{}; What = 'kinit: no KDC for AD.EXAMPLE answered'; LdapCalls = 0 }
        @{ Case = 'kinit does not answer in time'; Kinit = '124:'; Ldap1 = '0:description: never asked'; Ldap2 = '0:description: never asked'; Variables = @{}; What = 'kinit: no KDC for AD.EXAMPLE answered'; LdapCalls = 0 }
        @{ Case = 'kinit finds no KDC, DNS naming none'; Kinit = '1:kinit: Cannot find KDC for realm ''AD.EXAMPLE'' while getting initial credentials'; Ldap1 = '0:description: never asked'; Ldap2 = '0:description: never asked'; Variables = @{}; What = 'kinit: no KDC for AD.EXAMPLE answered'; LdapCalls = 0 }
        @{ Case = 'no DC can be contacted over LDAP'; Kinit = '0:'; Ldap1 = '255:ldap_sasl_interactive_bind: Can''t contact LDAP server (-1)'; Ldap2 = '124:'; Variables = @{}; What = 'tried: dc1.ad.example dc2.ad.example'; LdapCalls = 2 }
        @{ Case = 'DNS gives no SRV record and the domain''s own name does not answer'; Kinit = '0:'; Ldap1 = '255:ldap_sasl_interactive_bind: Can''t contact LDAP server (-1)'; Ldap2 = '0:description: never asked'; Variables = @{ STUB_SRV = 'none' }; What = 'tried: ad.example'; LdapCalls = 1 }
    ) {
        $run = Invoke-AdDescription -Kinit $Kinit -Ldap1 $Ldap1 -Ldap2 $Ldap2 -Variables $Variables -Before 'PROD: web front end'
        $run.Exit | Should -Be 75
        $run.Output | Should -Match ([regex]::Escape("usabanner: ad: WARNING: could not contact any domain controller ($What); kept the last description"))
        $run.Cache | Should -BeExactly "PROD: web front end`n"
        ($run.Files -join ',') | Should -BeExactly 'ad-description'
        Get-CallCount $run 'ldapsearch' | Should -Be $LdapCalls
    }

    It 'fails, naming each DC that answered and what it said, when <Case>' -ForEach @(
        @{ Case = 'one answers with an error and one cannot be contacted'; Ldap1 = '49:ldap_sasl_interactive_bind: Invalid credentials (49)'; Ldap2 = '255:ldap_sasl_interactive_bind: Can''t contact LDAP server (-1)'; What = 'no DC gave the description; dc1.ad.example: ldap_sasl_interactive_bind: Invalid credentials (49) (exit 49)' }
        @{ Case = 'both answer with an error'; Ldap1 = '49:ldap_sasl_interactive_bind: Invalid credentials (49)'; Ldap2 = '50:ldap_search_ext: Insufficient access (50)'; What = 'no DC gave the description; dc1.ad.example: ldap_sasl_interactive_bind: Invalid credentials (49) (exit 49); dc2.ad.example: ldap_search_ext: Insufficient access (50) (exit 50)' }
        @{ Case = 'one answers with an error and AD''s own reason for it'; Ldap1 = "49:ldap_sasl_interactive_bind: Invalid credentials (49)`n`tadditional info: 80090308: LdapErr: DSID-0C090569, comment: AcceptSecurityContext error, data 52e, v4f7c"; Ldap2 = '255:'; What = 'no DC gave the description; dc1.ad.example: ldap_sasl_interactive_bind: Invalid credentials (49): 80090308: LdapErr: DSID-0C090569, comment: AcceptSecurityContext error, data 52e, v4f7c (exit 49)' }
    ) {
        $run = Invoke-AdDescription -Ldap1 $Ldap1 -Ldap2 $Ldap2 -Before 'PROD: web front end'
        $run.Exit | Should -Be 1
        $run.Output | Should -Match ([regex]::Escape("usabanner: ad: $What"))
        $run.Cache | Should -BeExactly "PROD: web front end`n"
        ($run.Files -join ',') | Should -BeExactly 'ad-description'
    }

    It 'fails, keeping the last Description, when the DC that answers has no such computer object' {
        $run = Invoke-AdDescription -Ldap1 '0:NOENTRY' -Ldap2 '0:description: never asked' -Before 'PROD: web front end'
        $run.Exit | Should -Be 1
        $run.Output | Should -BeExactly "usabanner: ad: dc1.ad.example has no computer object APP1`$ under DC=ad,DC=example; kept the last description`n"
        $run.Cache | Should -BeExactly "PROD: web front end`n"
        Get-CallCount $run 'ldapsearch' | Should -Be 1
    }

    It 'leaves no credential cache or temporary folder behind when it is stopped part way' {
        $run = Invoke-AdDescription -Kinit 'stop' -Before 'PROD: web front end'
        $run.Exit | Should -Be 1
        $run.Left.Count | Should -Be 0
        Get-CallCount $run 'kdestroy' | Should -Be 1
        $run.Cache | Should -BeExactly "PROD: web front end`n"
    }

    It 'fails, saying why, when kinit is refused for another reason' {
        $run = Invoke-AdDescription -Kinit '1:kinit: Client ''APP1$@AD.EXAMPLE'' not found in Kerberos database while getting initial credentials' -Before 'PROD: web front end'
        $run.Exit | Should -Be 1
        $run.Output | Should -Match ([regex]::Escape("usabanner: ad: kinit as APP1`$@AD.EXAMPLE failed: kinit: Client 'APP1`$@AD.EXAMPLE' not found in Kerberos database"))
        $run.Cache | Should -BeExactly "PROD: web front end`n"
        Get-CallCount $run 'ldapsearch' | Should -Be 0
    }

    It 'fails, saying so, without a readable keytab, and asks nothing' {
        $run = Invoke-AdDescription -Files @{ 'etc/krb5.keytab' = $null } -Before 'PROD: web front end'
        $run.Exit | Should -Be 1
        $run.Output | Should -Match ([regex]::Escape("usabanner: ad: no readable $(Join-Path $run.Root 'etc/krb5.keytab') (not joined, or not root); description not refreshed"))
        $run.Cache | Should -BeExactly "PROD: web front end`n"
        $run.Calls.Count | Should -Be 0
    }

    It 'fails, saying so, when the keytab holds no key of the machine' {
        $listing = "Keytab name: FILE:/etc/krb5.keytab`nKVNO Principal`n---- ---------`n   2 host/app1.ad.example@AD.EXAMPLE`n"
        $run = Invoke-AdDescription -Files @{ 'etc/krb5.keytab' = $listing } -Before 'PROD: web front end'
        $run.Exit | Should -Be 1
        $run.Output | Should -Match ([regex]::Escape('usabanner: ad: no NAME$@REALM principal in ' + (Join-Path $run.Root 'etc/krb5.keytab')))
        $run.Cache | Should -BeExactly "PROD: web front end`n"
        Get-CallCount $run 'kinit' | Should -Be 0
    }

    It 'fails, naming the package, when <Tool> is not installed' -ForEach @(
        @{ Tool = 'kinit'; Line = 'kinit is not installed (package krb5-user)' }
        @{ Tool = 'klist'; Line = 'klist is not installed (package krb5-user)' }
        @{ Tool = 'kdestroy'; Line = 'kdestroy is not installed (package krb5-user)' }
        @{ Tool = 'ldapsearch'; Line = 'ldapsearch is not installed (package ldap-utils; GSSAPI also needs libsasl2-modules-gssapi-mit)' }
        @{ Tool = 'timeout'; Line = 'timeout is not installed (package coreutils)' }
    ) {
        $run = Invoke-AdDescription -Without $Tool -Before 'PROD: web front end'
        $run.Exit | Should -Be 1
        $run.Output | Should -BeExactly "usabanner: ad: $Line; description not refreshed`n"
        $run.Cache | Should -BeExactly "PROD: web front end`n"
    }

    It 'makes its folders and writes a cache any user can read, whatever the umask' {
        $run = Invoke-AdDescription -Ldap1 '0:description: PROD: web front end' -Umask '077'
        $run.Exit | Should -Be 0
        foreach ($name in 'var', 'var/lib', 'var/lib/usabanner') {
            (Get-Item -LiteralPath (Join-Path $run.Root $name)).UnixFileMode | Should -Be ([System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute') -Because $name
        }
        (Get-Item -LiteralPath (Join-Path $run.Root 'var/lib/usabanner/ad-description')).UnixFileMode | Should -Be ([System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead')
    }

    It 'moves the new cache into place, never writing into the old file' {
        # A second name for the old file shows what a reader that holds it sees.
        $run = Invoke-AdDescription -Ldap1 '0:description: LAB: test box' -Before 'PROD: web front end' -Hold
        $run.Exit | Should -Be 0
        $run.Cache | Should -BeExactly "LAB: test box`n"
        $run.Held | Should -BeExactly "PROD: web front end`n"
    }

    It 'fails, saying so, when the cache cannot be written' {
        # A file stands where its folder belongs, so the folder cannot be made.
        $run = Invoke-AdDescription -Ldap1 '0:description: PROD: web front end' -Files @{ 'var/lib/usabanner' = 'a file in the way' }
        $run.Exit | Should -Be 1
        $run.Output | Should -Match ([regex]::Escape("usabanner: ad: cannot write $(Join-Path $run.Root 'var/lib/usabanner/ad-description'); kept the last description"))
        $run.Output | Should -Not -Match 'from dc1'
        $run.Left.Count | Should -Be 0
    }

    It 'leaves no credential cache or temporary folder behind: <Case>' -ForEach @(
        @{ Case = 'after a Description'; Kinit = '0:'; Ldap1 = '0:description: PROD: web front end'; Status = 0 }
        @{ Case = 'when no DC answers'; Kinit = '0:'; Ldap1 = '255:'; Status = 75 }
        @{ Case = 'when a DC answers with an error'; Kinit = '0:'; Ldap1 = '49:ldap_sasl_interactive_bind: Invalid credentials (49)'; Status = 1 }
        @{ Case = 'when kinit is refused'; Kinit = '1:kinit: Preauthentication failed'; Ldap1 = '255:'; Status = 1 }
    ) {
        $run = Invoke-AdDescription -Kinit $Kinit -Ldap1 $Ldap1
        $run.Exit | Should -Be $Status
        $run.Left.Count | Should -Be 0
        Get-CallCount $run 'kdestroy' | Should -Be 1
    }
}
