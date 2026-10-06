# Pester 5 tests for the Linux banner script (rootfs/etc/update-motd.d/
# 05-manatech-banner), run under sh with pam_motd's empty environment against
# a copy of rootfs in TestDrive. Linux only: they need sh and the usual tools
# (ip, awk, df, who). The copies use COLOR=none and GLYPHS=ascii, so the
# output can be matched as plain text.

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '../..'

    # New-BannerRoot [FQDN] - a copy of rootfs with a plain-text motd.conf, and
    # var/lib/manatech/fqdn holding FQDN when one is given.
    function New-BannerRoot {
        param([string]$Fqdn = '')
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'rootfs') -Destination $root -Recurse
        [System.IO.File]::WriteAllText((Join-Path $root 'etc/manatech/motd.conf'), "COLOR=none`nGLYPHS=ascii`n")
        if ($Fqdn) {
            New-Item -ItemType Directory -Path (Join-Path $root 'var/lib/manatech') -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $root 'var/lib/manatech/fqdn'), "$Fqdn`n")
        }
        $root
    }

    # A hostname stub first on PATH: "stub-short" for the short name, and a
    # 5-second stall for -f - the DNS lookup a login must never wait on.
    $script:Bin = Join-Path $TestDrive 'bin'
    New-Item -ItemType Directory -Path $Bin -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Bin 'hostname'),
        "#!/bin/sh`nif [ `"`$1`" = -f ]; then sleep 5; echo slow.example; exit 0; fi`necho stub-short`n")
    & chmod 755 (Join-Path $Bin 'hostname')

    # Invoke-Banner ROOT - the banner's output, run the way pam_motd runs it.
    function Invoke-Banner {
        param([string]$Root)
        & env -i "PATH=$($Bin):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "MANATECH_ROOT=$Root" `
            sh (Join-Path $Root 'etc/update-motd.d/05-manatech-banner') 2>&1 | Out-String
    }
}

Describe '05-manatech-banner under pam_motd' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'resolves hostname to the stub in that environment (else the timing test proves nothing)' {
        $found = & env -i "PATH=$($Bin):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" sh -c 'command -v hostname'
        $found | Should -Be (Join-Path $Bin 'hostname')
    }
    It 'takes the FQDN from /var/lib/manatech/fqdn' {
        $out = Invoke-Banner (New-BannerRoot 'h-vsl-test-1.ad.example')
        $out | Should -Match '\+- h-vsl-test-1\.ad\.example -'
    }
    It 'falls back to the short name without it, and never waits on hostname -f' {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $out = Invoke-Banner (New-BannerRoot)
        $watch.Stop()
        $out | Should -Match '\+- stub-short -'
        $watch.Elapsed.TotalSeconds | Should -BeLessThan 4
    }
    It 'draws the whole panel, down to the bottom border' {
        $out = Invoke-Banner (New-BannerRoot 'h-vsl-test-1.ad.example')
        $out | Should -Match '\+-{62}\+'
    }
}
