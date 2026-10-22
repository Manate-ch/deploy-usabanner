# Pester tests for the setup-changes line of rootfs/etc/update-motd.d/15-manatech-health, run
# under sh with pam_motd's empty environment against a copy of rootfs in TestDrive. Linux only:
# they need sh and awk. systemctl, df and timedatectl are stubs that report a healthy host, and
# the copy's motd.conf sets plain text (COLOR=none, GLYPHS=ascii) and thresholds no host reaches.

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '../..'

    $script:Bin = Join-Path $TestDrive 'bin'
    New-Item -ItemType Directory -Path $Bin -Force | Out-Null
    # The stubs: no failed units and every unit active; df's header and no filesystems; the clock in sync.
    foreach ($stub in @(
            @{ Name = 'systemctl'; Body = "#!/bin/sh`ncase `$1 in is-active) echo active ;; esac`nexit 0`n" }
            @{ Name = 'df'; Body = "#!/bin/sh`necho 'Filesystem 1024-blocks Used Available Capacity Mounted on'`n" }
            @{ Name = 'timedatectl'; Body = "#!/bin/sh`necho yes`n" }
        )) {
        [System.IO.File]::WriteAllText((Join-Path $Bin $stub.Name), $stub.Body)
        & chmod 755 (Join-Path $Bin $stub.Name)
    }

    # Invoke-Health NOTE [-Unreached TEXT]
    # Out: the health script's output, run the way pam_motd runs it, with NOTE (when given) as the
    #      host's var/lib/manatech/pending, and -Unreached as its var/lib/manatech/ad-unreached.
    function Invoke-Health {
        param([string]$Note, [string]$Unreached)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'rootfs') -Destination $root -Recurse
        [System.IO.File]::WriteAllText((Join-Path $root 'etc/manatech/motd.conf'), "COLOR=none`nGLYPHS=ascii`nDISK_WARN=101`nMEM_WARN=101`nWATCH=`n")
        New-Item -ItemType Directory -Path (Join-Path $root 'var/lib/manatech') -Force | Out-Null
        if ($Note) { [System.IO.File]::WriteAllText((Join-Path $root 'var/lib/manatech/pending'), $Note) }
        if ($Unreached) { [System.IO.File]::WriteAllText((Join-Path $root 'var/lib/manatech/ad-unreached'), $Unreached) }
        & env -i "PATH=$($Bin):/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" "MANATECH_ROOT=$root" `
            sh (Join-Path $root 'etc/update-motd.d/15-manatech-health') 2>&1 | Out-String
    }
}

Describe '15-manatech-health: setup changes waiting' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'says how many, how to see them and how to make them' {
        $out = Invoke-Health "options=--all`nrepo=/opt/manatech-motd`nchanges=3`n"
        $out | Should -Match '(?m) 3 setup changes wait: sh /opt/manatech-motd/install\.sh --all --whatif$'
        $out | Should -Match '(?m)^    shows them; sudo sh /opt/manatech-motd/install\.sh --all makes them$'
    }

    It 'says it in the singular for one, and keeps every option' {
        $out = Invoke-Health "options=--ssh --timer --ad`nrepo=/opt/manatech-motd`nchanges=1`n"
        $out | Should -Match '(?m) 1 setup change waits: sh /opt/manatech-motd/install\.sh --ssh --timer --ad --whatif$'
        $out | Should -Match '(?m)^    shows it; sudo sh /opt/manatech-motd/install\.sh --ssh --timer --ad makes it$'
    }

    It 'shows nothing for a note it cannot trust: <Case>' -ForEach @(
        @{ Case = 'a command in the path'; Note = "options=--all`nrepo=/opt/x;reboot`nchanges=3`n" }
        @{ Case = 'a relative path'; Note = "options=--all`nrepo=opt/manatech-motd`nchanges=3`n" }
        @{ Case = 'an option install.sh does not have'; Note = "options=--all --evil`nrepo=/opt/manatech-motd`nchanges=3`n" }
        @{ Case = 'no options'; Note = "options=`nrepo=/opt/manatech-motd`nchanges=3`n" }
        @{ Case = 'a count that is not a number'; Note = "options=--all`nrepo=/opt/manatech-motd`nchanges=3x`n" }
        @{ Case = 'an escape in the path'; Note = "options=--all`nrepo=/opt/" + [char]27 + "[2J`nchanges=3`n" }
    ) {
        $out = Invoke-Health $Note
        $out | Should -Not -Match 'setup change'
        $out | Should -Not -Match 'install\.sh'
    }

    It 'shows no line without a note, and names the check on the all-clear line' {
        $out = Invoke-Health ''
        $out | Should -Not -Match 'setup change'
        # The real host's /run/reboot-required can add a line of its own; the all-clear shows only without one.
        if ($out -match 'all clear') { $out | Should -Match 'all clear .*setup' }
    }
}

Describe '15-manatech-health: no domain controller reached' -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
    It 'warns that no domain controller could be contacted, and when' {
        # 1792645632 is Thu 2026-10-22 05:07:12 UTC, and pam_motd's environment has no TZ.
        $out = Invoke-Health -Unreached "1792645632`ttried: dc1.ad.example dc2.ad.example`n"
        $out | Should -Match '(?m) could not contact any domain controller at Thu 05:07; AD role not refreshed$'
    }

    It 'warns without a time it cannot read' {
        $out = Invoke-Health -Unreached "soon`ttried: dc1.ad.example`n"
        $out | Should -Match '(?m) could not contact any domain controller; AD role not refreshed$'
    }

    It 'says nothing of it without the note' {
        Invoke-Health '' | Should -Not -Match 'domain controller'
    }
}
