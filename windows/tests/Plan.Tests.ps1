# Pester tests for rootfs/usr/local/share/manatech/plan.sh (what install.sh would change) and for
# install.sh --whatif, run with sh. Linux only: they need sh, cmp, md5sum and awk. PLAN_ROOT points
# the plan at a fake host in TestDrive; dpkg-query, dpkg, dpkg-statoverride and systemctl are stubs
# on PATH. Nothing outside TestDrive changes, and no test needs root.

BeforeAll {
    $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    $script:Src = Join-Path $RepoRoot 'rootfs'
    $script:Lib = Join-Path $Src 'usr/local/share/manatech'

    # What base-files 13ubuntu10.4 (Ubuntu 24.04.4) records for its stock /etc/issue and
    # /etc/issue.net; Conffiles.Tests.ps1 checks the texts against them.
    $script:Pretty = 'Ubuntu 24.04.4 LTS'
    $script:IssueMd5 = '5d0d240fb6f305303afbe168d941cd19'
    $script:IssueNetMd5 = 'd5ba68e8a13793e68d025c4404f38ecb'
    $script:StockMotdNews = "# motd-news settings`nENABLED=1`nURLS=`"https://motd.ubuntu.com`"`nWAIT=`"5`"`n"

    function Get-Md5 {
        param([string]$Text)
        $md5 = [System.Security.Cryptography.MD5]::Create()
        -join ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') })
    }

    function Write-File {
        param([string]$Path, [string]$Text, [string]$Mode = '644')
        New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
        [System.IO.File]::WriteAllText($Path, $Text)
        & chmod $Mode $Path
    }

    # New-FakeHost STATE
    # In:  stock    Ubuntu as installed: nothing of ours, the stock MOTD scripts on;
    #      old      set up with --all by an install.sh from before the conffile fix: its banner over
    #               /etc/issue and /etc/issue.net, ENABLED=0 in /etc/default/motd-news, the sshd
    #               drop-in naming /etc/issue.net, landscape-sysinfo off by chmod only, and an update
    #               service whose ExecStart lacks the space before its options;
    #      current  set up by this install.sh --all.
    #      The timer of old and current runs this repo's install.sh.
    # Out: Root (STUB_ROOT: the stubs' data), Fs (PLAN_ROOT: the host) and Bin (the stubs).
    # The stubs: dpkg-query -W -f=... PKG prints Root/conffiles.PKG; dpkg -S PATH succeeds when Root/owned
    # lists PATH; dpkg-statoverride --list PATH succeeds when Root/overrides holds it; systemctl
    # is-enabled UNIT prints Root/enabled.UNIT, or "disabled".
    function New-FakeHost {
        param([ValidateSet('stock', 'old', 'current')][string]$State)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $fs = Join-Path $root 'fs'
        $bin = Join-Path $root 'bin'
        Write-File (Join-Path $bin 'dpkg-query') @'
#!/bin/sh
for a in "$@"; do pkg=$a; done
[ -f "$STUB_ROOT/conffiles.$pkg" ] && cat "$STUB_ROOT/conffiles.$pkg"
exit 0
'@ '755'
        Write-File (Join-Path $bin 'dpkg') @'
#!/bin/sh
[ "$1" = -S ] || exit 2
grep -qxF "$2" "$STUB_ROOT/owned" 2>/dev/null
'@ '755'
        Write-File (Join-Path $bin 'dpkg-statoverride') @'
#!/bin/sh
[ "$1" = --list ] || exit 2
grep -q " $2\$" "$STUB_ROOT/overrides" 2>/dev/null
'@ '755'
        Write-File (Join-Path $bin 'systemctl') @'
#!/bin/sh
[ "$1" = is-enabled ] || exit 2
if [ -f "$STUB_ROOT/enabled.$2" ]; then cat "$STUB_ROOT/enabled.$2"; exit 0; fi
echo disabled
exit 1
'@ '755'

        Write-File (Join-Path $fs 'etc/os-release') "PRETTY_NAME=`"$Pretty`"`n"
        $scriptMode = if ($State -eq 'stock') { '755' } else { '644' }
        foreach ($s in '00-header', '10-help-text', '50-motd-news', '98-reboot-required') {
            Write-File (Join-Path $fs "etc/update-motd.d/$s") "#!/bin/sh`necho $s`n" $scriptMode
        }
        $wrapper = Join-Path $fs 'usr/share/landscape/landscape-sysinfo.wrapper'
        Write-File $wrapper "#!/bin/sh`necho sysinfo`n" $(if ($State -eq 'stock') { '755' } else { '644' })
        & ln -s $wrapper (Join-Path $fs 'etc/update-motd.d/50-landscape-sysinfo')
        Write-File (Join-Path $root 'owned') "$wrapper`n"
        if ($State -eq 'current') { Write-File (Join-Path $root 'overrides') "root root 0644 $wrapper`n" }

        $motdNewsFile = Join-Path $fs 'etc/default/motd-news'
        Write-File $motdNewsFile $(if ($State -eq 'old') { $StockMotdNews.Replace('ENABLED=1', 'ENABLED=0') } else { $StockMotdNews })
        Write-File (Join-Path $root 'conffiles.motd-news-config') " $motdNewsFile $(Get-Md5 $StockMotdNews)`n"
        $issue = Join-Path $fs 'etc/issue'
        $issueNet = Join-Path $fs 'etc/issue.net'
        if ($State -eq 'old') {
            Write-File $issue "\S{PRETTY_NAME} \n \l`nWelcome to the banner.`n"
            Write-File $issueNet "the old SSH banner`n"
        }
        else {
            Write-File $issue "$Pretty \n \l`n`n"
            Write-File $issueNet "$Pretty`n"
        }
        Write-File (Join-Path $root 'conffiles.base-files') " $issue $IssueMd5`n $issueNet $IssueNetMd5`n"
        if ($State -ne 'current') { Write-File (Join-Path $root 'enabled.motd-news.timer') "enabled`n" }
        else { Write-File (Join-Path $root 'enabled.motd-news.timer') "masked`n" }

        if ($State -ne 'stock') {
            foreach ($f in Get-ChildItem -LiteralPath $Lib -File) {
                Write-File (Join-Path $fs "usr/local/share/manatech/$($f.Name)") ([System.IO.File]::ReadAllText($f.FullName))
            }
            foreach ($s in '05-manatech-banner', '15-manatech-health') {
                Write-File (Join-Path $fs "etc/update-motd.d/$s") ([System.IO.File]::ReadAllText((Join-Path $Src "etc/update-motd.d/$s"))) '755'
            }
            Write-File (Join-Path $fs 'etc/manatech/motd.conf') "ENV_NAME=LAB`n"
            $dropin = Join-Path $fs 'etc/ssh/sshd_config.d/00-manatech-banner.conf'
            $units = Join-Path $fs 'etc/systemd/system'
            New-Item -ItemType Directory -Path $units -Force | Out-Null
            & sh -c ". '$Lib/units.sh'; units_clone '$units' '$RepoRoot'"
            Write-File (Join-Path $root 'enabled.manatech-motd-update.timer') "enabled`n"
            if ($State -eq 'current') {
                Write-File (Join-Path $fs 'etc/issue.d/50-manatech.issue') ([System.IO.File]::ReadAllText((Join-Path $Src 'etc/issue.d/50-manatech.issue')))
                Write-File (Join-Path $fs 'etc/manatech/issue.net') ([System.IO.File]::ReadAllText((Join-Path $Src 'etc/issue.net')))
                Write-File $dropin ([System.IO.File]::ReadAllText((Join-Path $Src 'etc/ssh/sshd_config.d/00-manatech-banner.conf')))
            }
            else {
                Write-File $dropin "Banner /etc/issue.net`n"
                $service = Join-Path $units 'manatech-motd-update.service'
                Write-File $service ([System.IO.File]::ReadAllText($service).Replace("$RepoRoot/install.sh", "$RepoRoot/install.sh--update"))
            }
        }
        [pscustomobject]@{ Root = $root; Fs = $fs; Bin = $bin }
    }

    # Invoke-Plan FAKEHOST SCRIPT
    # Out: Output (the lines printed) and Exit, after SCRIPT ran in sh with units.sh, conffiles.sh
    #      and plan.sh sourced, PLAN_ROOT at FAKEHOST's Fs and its stubs first on PATH.
    function Invoke-Plan {
        param($FakeHost, [string]$Script)
        $prelude = @'
log() { printf 'manatech-motd: %s\n' "$*"; }
'@
        # The here-string ends without a newline: add one, or the next line joins the function's.
        $code = $prelude + "`n. '$Lib/units.sh'`n. '$Lib/conffiles.sh'`n. '$Lib/plan.sh'`n" + $Script
        $out = & env "PATH=$($FakeHost.Bin):$env:PATH" "STUB_ROOT=$($FakeHost.Root)" "PLAN_ROOT=$($FakeHost.Fs)" sh -c $code 2>&1
        [pscustomobject]@{ Output = @($out | ForEach-Object { "$_" }); Exit = $LASTEXITCODE }
    }

    # Invoke-Whatif FAKEHOST ARGS
    # Out: Output and Exit of sh install.sh ARGS, run as this (non-root) user against FAKEHOST.
    function Invoke-Whatif {
        param($FakeHost, [string[]]$Arguments)
        $out = & env "PATH=$($FakeHost.Bin):$env:PATH" "STUB_ROOT=$($FakeHost.Root)" "PLAN_ROOT=$($FakeHost.Fs)" sh (Join-Path $RepoRoot 'install.sh') @Arguments 2>&1
        [pscustomobject]@{ Output = @($out | ForEach-Object { "$_" }); Exit = $LASTEXITCODE }
    }

    # Get-TreeState DIR
    # Out: one line per file and link under DIR: its path, mode and content md5 (or link target).
    # Why: two of them, before and after a run, show whether the run changed anything at all.
    function Get-TreeState {
        param([string]$Dir)
        foreach ($item in Get-ChildItem -LiteralPath $Dir -Recurse -Force | Sort-Object FullName) {
            if ($item.LinkType) { "$($item.FullName) -> $($item.Target)"; continue }
            if ($item.PSIsContainer) { continue }
            $mode = (& stat -c %a $item.FullName)
            "$($item.FullName) $mode $(Get-Md5 ([System.IO.File]::ReadAllText($item.FullName)))"
        }
    }
}

Describe 'plan.sh' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'parses under sh -n' {
        & sh -n (Join-Path $Lib 'plan.sh')
        $LASTEXITCODE | Should -Be 0
    }

    It 'finds nothing to change on a host this install.sh set up with --all' {
        $h = New-FakeHost current
        $r = Invoke-Plan $h "plan_retire; plan_ssh '$Src'; plan_units units_clone '$RepoRoot' ''; host_parts '$RepoRoot'"
        $r.Output | Should -Be @('--all')
    }

    It 'lists, one line each, what --all would change on a host an older install.sh set up' {
        $h = New-FakeHost old
        $r = Invoke-Plan $h "plan_retire; plan_ssh '$Src'; plan_units units_clone '$RepoRoot' ''"
        $wrapper = Join-Path $h.Fs 'usr/share/landscape/landscape-sysinfo.wrapper'
        $r.Output | Should -Be @(
            "would keep landscape-sysinfo off across upgrades (a 644 statoverride on $wrapper)"
            'would put back the stock /etc/default/motd-news (ENABLED=1; the masked timer keeps it off)'
            'would mask motd-news.timer'
            'would install /etc/issue.d/50-manatech.issue (the console banner)'
            'would install /etc/manatech/issue.net (the SSH banner)'
            'would put back the stock /etc/issue'
            'would put back the stock /etc/issue.net'
            'would install /etc/ssh/sshd_config.d/00-manatech-banner.conf (the sshd drop-in; then sshd -t and a reload)'
            'would write /etc/systemd/system/manatech-motd-update.service'
        )
    }

    It 'notes a conffile it cannot put back, and does not count it as a change' {
        $h = New-FakeHost old
        # dpkg's record is 24.04.5's while the host says 24.04.4: the rebuilt stock text cannot match it.
        $issue = Join-Path $h.Fs 'etc/issue'
        Write-File (Join-Path $h.Root 'conffiles.base-files') " $issue 1fd8b22ff287a77717f4ed62774e4576`n"
        $r = Invoke-Plan $h "plan_ssh '$Src'"
        $r.Output | Should -Contain 'note: /etc/issue was changed, not as this installer changes it; it stays as it is, and dpkg will ask about it at the next base-files upgrade'
        $r.Output | Should -Not -Contain 'would put back the stock /etc/issue'
    }

    It 'would put back a stock /etc/issue over anything in it: our old banner and anyone else''s look alike' {
        $h = New-FakeHost old
        Write-File (Join-Path $h.Fs 'etc/issue') "someone else's console banner`n"
        $r = Invoke-Plan $h "plan_ssh '$Src'"
        $r.Output | Should -Contain 'would put back the stock /etc/issue'
    }

    It 'reads the parts from the host: <Case>' -ForEach @(
        @{ Case = 'all three'; Change = ''; Expected = '--all' }
        @{ Case = 'the stock scripts turned back on: no --retire'; Change = 'chmod 755 "$PLAN_ROOT"/etc/update-motd.d/00-header "$PLAN_ROOT"/etc/update-motd.d/10-help-text "$PLAN_ROOT"/etc/update-motd.d/50-motd-news "$PLAN_ROOT"/etc/update-motd.d/98-reboot-required'; Expected = '--ssh --timer' }
        @{ Case = 'no sshd drop-in: no --ssh'; Change = 'rm "$PLAN_ROOT"/etc/ssh/sshd_config.d/00-manatech-banner.conf'; Expected = '--retire --timer' }
        @{ Case = 'the timer runs another copy: no --timer'; Change = 'sed -i "s#ExecStart=.*#ExecStart=/bin/sh /var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh#" "$PLAN_ROOT"/etc/systemd/system/manatech-motd-update.service'; Expected = '--retire --ssh' }
    ) {
        $h = New-FakeHost current
        $r = Invoke-Plan $h "$Change`nhost_parts '$RepoRoot'"
        $r.Output | Should -Be @($Expected)
    }
}

Describe 'note_pending' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'notes for the login banner how many changes --all would make, on a host an older install.sh set up' {
        $h = New-FakeHost old
        $r = Invoke-Plan $h "note_pending '$RepoRoot' '$Src' ''; echo rc=`$?"
        $r.Output | Should -Be @('rc=0')
        [System.IO.File]::ReadAllText((Join-Path $h.Fs 'var/lib/manatech/pending')) | Should -BeExactly "options=--all`nrepo=$RepoRoot`nchanges=9`n"
    }

    It 'adds --ad to the advice when the timer runs with it' {
        $h = New-FakeHost old
        $null = Invoke-Plan $h "note_pending '$RepoRoot' '$Src' '--ad'"
        [System.IO.File]::ReadAllText((Join-Path $h.Fs 'var/lib/manatech/pending')) | Should -BeLike "options=--all --ad`n*"
    }

    It 'removes the note once there is nothing to change' {
        $h = New-FakeHost current
        Write-File (Join-Path $h.Fs 'var/lib/manatech/pending') "options=--all`nrepo=$RepoRoot`nchanges=3`n"
        $null = Invoke-Plan $h "note_pending '$RepoRoot' '$Src' ''"
        Test-Path -LiteralPath (Join-Path $h.Fs 'var/lib/manatech/pending') | Should -BeFalse
    }

    It 'leaves the note alone when the timer runs another copy' {
        $h = New-FakeHost old
        $note = Join-Path $h.Fs 'var/lib/manatech/pending'
        Write-File $note "options=--all`nrepo=/opt/another-copy`nchanges=3`n"
        $null = Invoke-Plan $h "note_pending '/opt/another-copy-not-this' '$Src' ''"
        [System.IO.File]::ReadAllText($note) | Should -BeExactly "options=--all`nrepo=/opt/another-copy`nchanges=3`n"
    }
}

Describe 'install.sh --whatif' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'lists what --all would change on a stock host, changes nothing, and needs no root' {
        $h = New-FakeHost stock
        $before = @(Get-TreeState $h.Root)
        $r = Invoke-Whatif $h @('--all', '--whatif')
        $after = @(Get-TreeState $h.Root)
        $r.Exit | Should -Be 0
        ($after -join "`n") | Should -BeExactly ($before -join "`n")
        $code = @(Get-ChildItem -LiteralPath $Lib -File).Count
        $lines = @($r.Output | Where-Object { $_ -like 'manatech-motd: would *' })
        $lines.Count | Should -Be ($code + 2 + 1 + 4 + 1 + 1 + 3 + 3)   # code, login scripts, motd.conf; four scripts, landscape, motd-news; three ssh files; two units and the enable
        $r.Output | Should -Contain 'manatech-motd: would turn off /etc/update-motd.d/00-header (chmod -x)'
        $r.Output | Should -Contain 'manatech-motd: would enable manatech-motd-update.timer'
        $r.Output[-1] | Should -BeExactly "manatech-motd: --whatif: $($lines.Count) change(s); run it again without --whatif, as root, to make them"
    }

    It 'says there is nothing to change on a host this install.sh set up with --all' {
        $h = New-FakeHost current
        $r = Invoke-Whatif $h @('--all', '--whatif')
        $r.Output | Should -Be @('manatech-motd: --whatif: nothing to change')
    }

    It 'pulls nothing under --update, and says so' {
        $h = New-FakeHost current
        $r = Invoke-Whatif $h @('--update', '--whatif')
        $r.Output | Should -Be @('manatech-motd: --update: no pull under --whatif; below is what this copy would change', 'manatech-motd: --whatif: nothing to change')
    }

    It 'still needs root without --whatif' {
        $h = New-FakeHost current
        $r = Invoke-Whatif $h @('--all')
        $r.Exit | Should -Be 1
        $r.Output | Should -Be @('manatech-motd: run as root (sudo)')
    }
}
