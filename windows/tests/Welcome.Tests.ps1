# Pester 5 tests for the welcome line, "Welcome to <name>". The name and its
# colours come from welcome.tsv on Linux (05-manatech-banner, under sh with
# pam_motd's empty environment) and on Windows (Format-ManatechBanner), so a
# fork changes the line with data alone. Every case runs through both.

BeforeDiscovery {
    $t = "`t"
    # Text: what welcome.tsv holds (SHIPPED = the repo's own file, NONE = no
    # file). Name: what both banners must show.
    $script:Cases = @(
        @{ What = 'the shipped file'; Text = 'SHIPPED'; Name = 'Manatech' }
        @{ What = 'a row of its own'; Text = "Contoso${t}10${t}20${t}30${t}200${t}210${t}220${t}1;36`n"; Name = 'Contoso' }
        @{ What = 'a name with a space'; Text = "Contoso Ltd${t}10${t}20${t}30${t}200${t}210${t}220${t}36`n"; Name = 'Contoso Ltd' }
        @{ What = 'comment lines before the row'; Text = "# a comment`n`n# name${t}r1`nContoso${t}1${t}2${t}3${t}4${t}5${t}6${t}35`n"; Name = 'Contoso' }
        @{ What = 'a number above 255'; Text = "Contoso${t}10${t}20${t}300${t}200${t}210${t}220${t}36`n"; Name = 'Manatech' }
        @{ What = 'the SGR code missing'; Text = "Contoso${t}10${t}20${t}30${t}200${t}210${t}220`n"; Name = 'Manatech' }
        @{ What = 'a bad SGR code'; Text = "Contoso${t}10${t}20${t}30${t}200${t}210${t}220${t}1;3x`n"; Name = 'Manatech' }
        @{ What = 'no welcome.tsv'; Text = 'NONE'; Name = 'Manatech' }
    )
}

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '../..'
    $script:Share = Join-Path $RepoRoot 'rootfs/usr/local/share/manatech'
    Import-Module (Join-Path $PSScriptRoot '../ManatechBanner.psm1') -Force

    # Set-Welcome DIR TEXT - DIR's welcome.tsv: kept for SHIPPED, removed for
    # NONE, else TEXT.
    function Set-Welcome {
        param([string]$Dir, [string]$Text)
        $file = Join-Path $Dir 'welcome.tsv'
        if ($Text -eq 'SHIPPED') { return }
        if ($Text -eq 'NONE') { Remove-Item -LiteralPath $file; return }
        [System.IO.File]::WriteAllText($file, $Text)
    }

    # Read-OnLinux TEXT - the name in 05-manatech-banner's welcome line, run in a
    # copy of rootfs with a plain motd.conf.
    function Read-OnLinux {
        param([string]$Text)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'rootfs') -Destination $root -Recurse
        [System.IO.File]::WriteAllText((Join-Path $root 'etc/manatech/motd.conf'), "COLOR=none`nGLYPHS=ascii`n")
        Set-Welcome (Join-Path $root 'usr/local/share/manatech') $Text
        $out = & env -i 'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' "MANATECH_ROOT=$root" `
            sh (Join-Path $root 'etc/update-motd.d/05-manatech-banner') 2>&1
        $line = @($out | Where-Object { "$_" -match '^  Welcome to ' })
        if ($line.Count -ne 1) { return "($($line.Count) welcome lines)" }
        "$($line[0])" -replace '^  Welcome to ', ''
    }

    # Read-OnWindows TEXT - the name in Format-ManatechBanner's welcome line,
    # drawn from a copy of the shared data files.
    function Read-OnWindows {
        param([string]$Text)
        $dir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Copy-Item -LiteralPath $Share -Destination $dir -Recurse
        Set-Welcome $dir $Text
        $c = Get-ManatechConfig -DataPath $dir
        $c.Color = 'none'; $c.Glyphs = 'ascii'
        $fact = @{
            HostName = 'h-vsw-example1.ad.example'; PrimaryIp = ''; Os = 'Windows Server 2025 Standard, build 26100.1'
            Uptime = [timespan]::new(1, 2, 3, 0); CpuPct = 7; Cores = 8
            MemPct = 41; MemText = '6.5 of 16.0 GiB'; DiskName = 'C:'; DiskPct = 63; DiskText = '80G of 127G'
            Sessions = '1  (administrator)'; Time = 'Wed 2026-09-23 03:00 UTC-05:00'
            Ipv4 = @(@{ Name = 'Ethernet0'; Address = '10.20.40.21/24' })
            Problems = @(); Checked = @('services', 'memory', 'reboot')
        }
        $line = @(Format-ManatechBanner -Fact $fact -Config $c -DataPath $dir | Where-Object { $_ -match '^  Welcome to ' })
        if ($line.Count -ne 1) { return "($($line.Count) welcome lines)" }
        $line[0] -replace '^  Welcome to ', ''
    }
}

Describe 'The welcome line, from welcome.tsv' {
    It 'Linux shows "<Name>" for <What>' -ForEach $Cases -Skip:(-not (Get-Command sh -ErrorAction SilentlyContinue)) {
        Read-OnLinux $Text | Should -BeExactly $Name
    }
    It 'Windows shows "<Name>" for <What>' -ForEach $Cases {
        Read-OnWindows $Text | Should -BeExactly $Name
    }
}

Describe 'Install-ManatechBanner.ps1' {
    It 'copies every shared data file the module reads, welcome.tsv included' {
        $module = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../ManatechBanner.psm1'))
        $install = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot '../Install-ManatechBanner.ps1'))
        $read = @([regex]::Matches($module, "Join-Path \`$DataPath '([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $copied = @([regex]::Matches($install, "Join-Path \`$share '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        $read | Should -Contain 'welcome.tsv'
        # Per host, not shared: motd.psd1 is copied once, and -AdDescription
        # writes ad-description.txt.
        $missing = @($read | Where-Object { $_ -notin 'motd.psd1', 'ad-description.txt' -and $_ -notin $copied })
        $missing -join ', ' | Should -BeExactly ''
    }
}
