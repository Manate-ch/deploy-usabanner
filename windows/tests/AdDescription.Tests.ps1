# Pester 5 tests: an AD Description reads the same on Linux (motd-lib.sh,
# under sh with pam_motd's empty environment) as on Windows
# (Get-ManatechConfig), case for case. Linux used to need the letters right
# against the colon and kept trailing spaces, so "PROD : Hyper-V host" was a
# role with no environment there while Windows read it as PROD.

BeforeDiscovery {
    # Desc: the Description as AD holds it. EnvName and Role: how both read it.
    $script:Cases = @(
        @{ Desc = 'PROD: Hyper-V host'; EnvName = 'PROD'; Role = 'Hyper-V host' }
        @{ Desc = 'PROD : Hyper-V host'; EnvName = 'PROD'; Role = 'Hyper-V host' }
        @{ Desc = '  prod:  Hyper-V host  '; EnvName = 'PROD'; Role = 'Hyper-V host' }
        @{ Desc = "PROD:`tHyper-V host"; EnvName = 'PROD'; Role = 'Hyper-V host' }
        @{ Desc = "`tLAB`t:Grafana node"; EnvName = 'LAB'; Role = 'Grafana node' }
        @{ Desc = 'lab:Grafana node'; EnvName = 'LAB'; Role = 'Grafana node' }
        @{ Desc = 'PROD: role: with a colon'; EnvName = 'PROD'; Role = 'role: with a colon' }
        @{ Desc = 'PROD:'; EnvName = 'PROD'; Role = '' }
        @{ Desc = 'Grafana visualization node'; EnvName = 'UNSET'; Role = 'Grafana visualization node' }
        @{ Desc = '  Grafana node  '; EnvName = 'UNSET'; Role = 'Grafana node' }
        @{ Desc = 'QA-1: kept whole, the prefix is not letters only'; EnvName = 'UNSET'; Role = 'QA-1: kept whole, the prefix is not letters only' }
        @{ Desc = 'PROD 1: a space inside is no prefix'; EnvName = 'UNSET'; Role = 'PROD 1: a space inside is no prefix' }
        @{ Desc = ': no prefix at all'; EnvName = 'UNSET'; Role = ': no prefix at all' }
        @{ Desc = ''; EnvName = 'UNSET'; Role = '' }
    )
}

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '../..'
    Import-Module (Join-Path $PSScriptRoot '../ManatechBanner.psm1') -Force

    # Read-OnLinux DESC - "<ENV_NAME>|<ROLE>" once motd-lib.sh has read DESC as
    # the cached AD Description, in a copy of rootfs with a plain motd.conf.
    function Read-OnLinux {
        param([string]$Desc)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'rootfs') -Destination $root -Recurse
        [System.IO.File]::WriteAllText((Join-Path $root 'etc/manatech/motd.conf'), "COLOR=none`nGLYPHS=ascii`n")
        New-Item -ItemType Directory -Path (Join-Path $root 'var/lib/manatech') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $root 'var/lib/manatech/ad-description'), "$Desc`n")
        $out = & env -i 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' "MANATECH_ROOT=$root" `
            sh -c '. "$MANATECH_ROOT/usr/local/share/manatech/motd-lib.sh"; printf "%s|%s\n" "$ENV_NAME" "$ROLE"' 2>&1
        @($out) -join "`n"
    }

    # Read-OnWindows DESC - "<EnvName>|<Role>" from Get-ManatechConfig with DESC
    # as ad-description.txt.
    function Read-OnWindows {
        param([string]$Desc)
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'ad-description.txt') -Value $Desc
        $c = Get-ManatechConfig -DataPath $dir
        "$($c.EnvName)|$($c.Role)"
    }
}

Describe 'The AD Description ("ENV: role")' {
    It 'Linux reads "<Desc>" as <EnvName> and "<Role>"' -ForEach $Cases -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
        Read-OnLinux $Desc | Should -BeExactly "$EnvName|$Role"
    }
    It 'Windows reads "<Desc>" as <EnvName> and "<Role>"' -ForEach $Cases {
        Read-OnWindows $Desc | Should -BeExactly "$EnvName|$Role"
    }
}
