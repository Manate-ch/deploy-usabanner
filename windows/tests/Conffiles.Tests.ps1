# Pester 5 tests for rootfs/usr/local/share/manatech/conffiles.sh, which keeps Ubuntu's banner
# conffiles stock, run with sh. Linux only: they need sh, md5sum and awk. dpkg-query, dpkg and
# dpkg-statoverride are stubs on PATH, so the tests need no root and change nothing outside
# TestDrive.

BeforeAll {
    $script:Lib = Join-Path $PSScriptRoot '../../rootfs/usr/local/share/manatech/conffiles.sh'

    # The md5 sums dpkg recorded for the stock files of base-files 13ubuntu10.4 (Ubuntu 24.04.4)
    # and 13ubuntu10.5 (24.04.5), read from /var/lib/dpkg on two lab hosts on 2026-10-11.
    $script:Recorded = @{
        'Ubuntu 24.04.4 LTS' = @{ Issue = '5d0d240fb6f305303afbe168d941cd19'; Net = 'd5ba68e8a13793e68d025c4404f38ecb' }
        'Ubuntu 24.04.5 LTS' = @{ Issue = '1fd8b22ff287a77717f4ed62774e4576'; Net = '7ad49cfe45b1d23848c13dcef2eed74e' }
    }

    function Get-Md5 {
        param([string]$Text)
        $md5 = [System.Security.Cryptography.MD5]::Create()
        -join ($md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)) | ForEach-Object { $_.ToString('x2') })
    }

    function Write-Stub {
        param([string]$Bin, [string]$Name, [string]$Body)
        $path = Join-Path $Bin $Name
        [System.IO.File]::WriteAllText($path, $Body)
        & chmod 755 $path
    }

    # New-Sandbox
    # Out: a new folder whose bin/ holds the stubs:
    #   dpkg-query -W -f=... PKG   prints the folder's conffiles.PKG (" PATH MD5" lines);
    #   dpkg -S PATH               succeeds when the folder's "owned" file lists PATH;
    #   dpkg-statoverride          logs each call to statoverride.calls; --list PATH succeeds when
    #                              "overrides" holds PATH; --update --add U G MODE PATH records it
    #                              there and sets MODE on PATH.
    function New-Sandbox {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $bin = Join-Path $root 'bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        Write-Stub $bin 'dpkg-query' @'
#!/bin/sh
for a in "$@"; do pkg=$a; done
[ -f "$STUB_ROOT/conffiles.$pkg" ] && cat "$STUB_ROOT/conffiles.$pkg"
exit 0
'@
        Write-Stub $bin 'dpkg' @'
#!/bin/sh
[ "$1" = -S ] || exit 2
if grep -qxF "$2" "$STUB_ROOT/owned" 2>/dev/null; then echo "stub-package: $2"; exit 0; fi
exit 1
'@
        Write-Stub $bin 'dpkg-statoverride' @'
#!/bin/sh
echo "$*" >>"$STUB_ROOT/statoverride.calls"
case $1 in
--list) grep -q " $2\$" "$STUB_ROOT/overrides" 2>/dev/null ;;
--update) shift; [ "$1" = --add ] || exit 2; echo "$2 $3 $4 $5" >>"$STUB_ROOT/overrides"; chmod "$4" "$5" ;;
*) exit 2 ;;
esac
'@
        $root
    }

    # Invoke-Lib ROOT SCRIPT
    # Out: Output (the lines it printed) and Exit, after running SCRIPT in sh with conffiles.sh
    #      sourced, a log() like install.sh's, and ROOT's stubs first on PATH.
    function Invoke-Lib {
        param([string]$Root, [string]$Script)
        $prelude = @'
log() { printf 'manatech-motd: %s\n' "$*"; }
'@
        # The here-string ends without a newline: add one, or the next line joins the function's.
        $code = $prelude + "`n. '$Lib'`n" + $Script
        $out = & env "PATH=$Root/bin:$env:PATH" "STUB_ROOT=$Root" sh -c $code 2>&1
        [pscustomobject]@{ Output = @($out | ForEach-Object { "$_" }); Exit = $LASTEXITCODE }
    }

    function Set-Conffile {
        param([string]$Root, [string]$Package, [string]$Path, [string]$Md5)
        [System.IO.File]::AppendAllText((Join-Path $Root "conffiles.$Package"), " $Path $Md5`n")
    }
}

Describe 'conffiles.sh' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'parses under sh -n' {
        & sh -n $Lib
        $LASTEXITCODE | Should -Be 0
    }

    It 'prints stock /etc/issue and /etc/issue.net exactly as base-files ships them for <Pretty>' -ForEach @(
        @{ Pretty = 'Ubuntu 24.04.4 LTS' }, @{ Pretty = 'Ubuntu 24.04.5 LTS' }
    ) {
        $root = New-Sandbox
        $r = Invoke-Lib $root "stock_issue '$Pretty' | md5sum; stock_issue_net '$Pretty' | md5sum"
        $r.Output[0] | Should -BeLike "$($Recorded[$Pretty].Issue) *"
        $r.Output[1] | Should -BeLike "$($Recorded[$Pretty].Net) *"
    }
}

Describe 'restore_conffile' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'puts back a stock /etc/issue that an older version overwrote, mode 644, and says so' {
        $root = New-Sandbox
        $issue = Join-Path $root 'issue'
        [System.IO.File]::WriteAllText($issue, "Welcome to Manatech.`nart`n")
        Set-Conffile $root 'base-files' $issue $Recorded['Ubuntu 24.04.4 LTS'].Issue
        $r = Invoke-Lib $root "restore_conffile base-files '$issue' stock_issue 'Ubuntu 24.04.4 LTS'; echo rc=`$?; stat -c %a '$issue'"
        [System.IO.File]::ReadAllText($issue) | Should -BeExactly "Ubuntu 24.04.4 LTS \n \l`n`n"
        $r.Output | Should -Contain "manatech-motd: ${issue}: the stock base-files version is back"
        $r.Output | Should -Contain 'rc=0'
        $r.Output[-1] | Should -Be '644'
        Test-Path -LiteralPath "$issue.manatech-tmp" | Should -BeFalse
    }

    It 'leaves a file it cannot rebuild as it is, says why, and returns 1' {
        $root = New-Sandbox
        $issue = Join-Path $root 'issue'
        [System.IO.File]::WriteAllText($issue, "someone else's banner`n")
        # The recorded md5 is 24.04.5's, but this host says 24.04.4: the rebuilt text cannot match.
        Set-Conffile $root 'base-files' $issue $Recorded['Ubuntu 24.04.5 LTS'].Issue
        $r = Invoke-Lib $root "restore_conffile base-files '$issue' stock_issue 'Ubuntu 24.04.4 LTS'; echo rc=`$?"
        [System.IO.File]::ReadAllText($issue) | Should -BeExactly "someone else's banner`n"
        $r.Output | Should -Contain 'rc=1'
        ($r.Output -join "`n") | Should -Match 'left as it is \(dpkg will ask about it at the next base-files upgrade\)'
        Test-Path -LiteralPath "$issue.manatech-tmp" | Should -BeFalse
    }

    It 'does nothing to a file that is stock already, or that the package does not list' {
        $root = New-Sandbox
        $stock = Join-Path $root 'issue.net'
        [System.IO.File]::WriteAllText($stock, "Ubuntu 24.04.4 LTS`n")
        Set-Conffile $root 'base-files' $stock $Recorded['Ubuntu 24.04.4 LTS'].Net
        $other = Join-Path $root 'other'
        [System.IO.File]::WriteAllText($other, "mine`n")
        $r = Invoke-Lib $root "restore_conffile base-files '$stock' stock_issue_net 'Ubuntu 24.04.4 LTS'; echo rc=`$?; restore_conffile base-files '$other' stock_issue_net 'Ubuntu 24.04.4 LTS'; echo rc=`$?"
        $r.Output | Should -Be 'rc=0', 'rc=0'
        [System.IO.File]::ReadAllText($other) | Should -BeExactly "mine`n"
    }

    It 'undoes ENABLED=0 in /etc/default/motd-news, and only when that is the one change' {
        $stockText = "# motd-news settings`nENABLED=1`nURLS=`"https://motd.ubuntu.com`"`nWAIT=`"5`"`n"
        $root = New-Sandbox
        $ours = Join-Path $root 'motd-news'
        [System.IO.File]::WriteAllText($ours, $stockText.Replace('ENABLED=1', 'ENABLED=0'))
        Set-Conffile $root 'motd-news-config' $ours (Get-Md5 $stockText)
        $edited = Join-Path $root 'motd-news-edited'
        [System.IO.File]::WriteAllText($edited, $stockText.Replace('ENABLED=1', 'ENABLED=0').Replace('WAIT="5"', 'WAIT="9"'))
        Set-Conffile $root 'motd-news-config' $edited (Get-Md5 $stockText)
        $r = Invoke-Lib $root "restore_conffile motd-news-config '$ours' stock_motd_news '$ours'; echo rc=`$?; restore_conffile motd-news-config '$edited' stock_motd_news '$edited'; echo rc=`$?"
        [System.IO.File]::ReadAllText($ours) | Should -BeExactly $stockText
        [System.IO.File]::ReadAllText($edited) | Should -Match 'ENABLED=0'
        $r.Output | Should -Contain 'rc=0'
        $r.Output | Should -Contain 'rc=1'
    }
}

Describe 'conffile_state' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'says <Expected>, and restore_conffile then does just that' -ForEach @(
        @{ Expected = 'stock'; Text = "Ubuntu 24.04.4 LTS \n \l`n`n"; Recorded = '5d0d240fb6f305303afbe168d941cd19'; Rc = 'rc=0'; After = "Ubuntu 24.04.4 LTS \n \l`n`n" }
        @{ Expected = 'restore'; Text = "Welcome to the banner.`n"; Recorded = '5d0d240fb6f305303afbe168d941cd19'; Rc = 'rc=0'; After = "Ubuntu 24.04.4 LTS \n \l`n`n" }
        # 24.04.5's md5 on a host that says 24.04.4: the rebuilt text cannot match.
        @{ Expected = 'changed'; Text = "Welcome to the banner.`n"; Recorded = '1fd8b22ff287a77717f4ed62774e4576'; Rc = 'rc=1'; After = "Welcome to the banner.`n" }
    ) {
        $root = New-Sandbox
        $issue = Join-Path $root 'issue'
        [System.IO.File]::WriteAllText($issue, $Text)
        Set-Conffile $root 'base-files' $issue $Recorded
        $r = Invoke-Lib $root "conffile_state base-files '$issue' stock_issue 'Ubuntu 24.04.4 LTS'; restore_conffile base-files '$issue' stock_issue 'Ubuntu 24.04.4 LTS' >/dev/null; echo rc=`$?"
        $r.Output | Should -Be @($Expected, $Rc)
        [System.IO.File]::ReadAllText($issue) | Should -BeExactly $After
    }

    It 'says nothing for a file the package does not list' {
        $root = New-Sandbox
        $other = Join-Path $root 'other'
        [System.IO.File]::WriteAllText($other, "mine`n")
        $r = Invoke-Lib $root "conffile_state base-files '$other' stock_issue 'Ubuntu 24.04.4 LTS'; echo end"
        $r.Output | Should -Be @('end')
    }
}

Describe 'retire_landscape' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    BeforeAll {
        # New-Landscape ROOT OWNED: a 755 wrapper and a symlink to it, as landscape-common's
        # postinst makes them; OWNED lists the wrapper as a package file.
        function New-Landscape {
            param([string]$Root, [bool]$Owned)
            $wrapper = Join-Path $Root 'landscape-sysinfo.wrapper'
            [System.IO.File]::WriteAllText($wrapper, "#!/bin/sh`necho sysinfo`n")
            & chmod 755 $wrapper
            $link = Join-Path $Root '50-landscape-sysinfo'
            & ln -s $wrapper $link
            if ($Owned) { [System.IO.File]::WriteAllText((Join-Path $Root 'owned'), "$wrapper`n") }
            [pscustomobject]@{ Wrapper = $wrapper; Link = $link }
        }
    }

    It 'gives the package file behind the symlink a 644 statoverride, once' {
        $root = New-Sandbox
        $l = New-Landscape $root $true
        $r = Invoke-Lib $root "retire_landscape '$($l.Link)'; retire_landscape '$($l.Link)'; stat -c %a '$($l.Wrapper)'"
        $r.Output[-1] | Should -Be '644'
        $calls = @(Get-Content -LiteralPath (Join-Path $root 'statoverride.calls'))
        @($calls | Where-Object { $_ -like '--update --add*' }) | Should -Be "--update --add root root 0644 $($l.Wrapper)"
    }

    It 'only clears the x bit of a file no package owns' {
        $root = New-Sandbox
        $l = New-Landscape $root $false
        $r = Invoke-Lib $root "retire_landscape '$($l.Link)'; stat -c %a '$($l.Wrapper)'"
        $r.Output[-1] | Should -Be '644'
        Test-Path -LiteralPath (Join-Path $root 'statoverride.calls') | Should -BeFalse
    }

    It 'does nothing where there is no landscape script' {
        $root = New-Sandbox
        $r = Invoke-Lib $root "retire_landscape '$root/absent'; echo rc=`$?"
        $r.Output | Should -Be 'rc=0'
    }
}
