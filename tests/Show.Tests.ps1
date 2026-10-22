# Show-UsaBanner (UsaBanner/Public/Show-UsaBanner.ps1): each moment drawn
# from a configuration file and a host's facts. The frames are the ones the
# moments' own tests hold (PreLogin.Tests, PostLogin.Tests), so the command
# draws exactly what they do.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'Golden.ps1')
    $esc = [string][char]27

    # The web host of PostLogin.Tests, all clear.
    $facts = @{
        Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80'
        Os = 'Ubuntu 24.04.3 LTS, kernel 6.8.0-87-generic'; Role = 'Web front end'; Uptime = '12d 6h 40m'
        Cpu = @{ Now = 12; Min = 3; Max = 71; Text = '4 cores @ 2.4 GHz' }
        Memory = @{ Pct = 57; Min = 48; Max = 66; Text = '4.5 of 7.8 GiB'; Kind = 'DDR4' }
        Disks = @(
            @{ Name = '/'; Pct = 38; Min = 38; Max = 39; Text = '11 of 29 GiB'; Kind = 'SSD' }
            @{ Name = '/var'; Pct = 52; Min = 51; Max = 53; Text = '21 of 40 GiB'; Kind = 'SSD' }
        )
        Sessions = '2  (admin)'; Time = 'Tue 2026-10-20 09:30 CDT'
        Ipv4 = @(@{ Name = 'ens160'; Address = '10.20.40.80/22' })
        Updates = @{ Text = 'none pending'; Level = 'good' }
        Reboot = @{ Text = 'none pending, none scheduled'; Level = 'good' }
        Services = @{ Text = 'ssh, cron, systemd-timesyncd active'; Level = 'good' }
        Problems = @()
        Checked = @('services', 'disks <85%', 'memory', 'ssh', 'clock', 'reboot')
    }

    function New-ConfigFile {
        # In:  a file name, and settings over Contoso's lab with three VLANs
        # Out: the path of the configuration file written in TestDrive
        # Why: the command reads a file, as a host will
        param([string]$Name, [hashtable]$Change = @{})
        $config = [ordered]@{
            version = 1; company = 'Contoso'; environment = 'LAB'
            vlans = @(
                [ordered]@{ name = 'Management'; tag = 10; cidr = '10.20.10.0/24'; color = 'Blue'; short = 'Mgmt' }
                [ordered]@{ name = 'Servers'; tag = 40; cidr = '10.20.40.0/22'; color = 'Teal' }
                [ordered]@{ name = 'Application servers'; tag = 60; cidr = '10.20.60.0/24'; color = 'Brown'; short = 'Apps' }
            )
        }
        foreach ($key in $Change.Keys) { $config[$key] = $Change[$key] }
        $path = Join-Path $TestDrive $Name
        Set-Content -LiteralPath $path -Value (ConvertTo-Json -InputObject $config -Depth 10)
        $path
    }

    function Use-Environment {
        # In:  variables to set for one script block ($null clears one), and the block
        # Out: what the block returns; the variables are as they were afterwards
        # Why: auto reads the process environment
        param([hashtable]$Variables, [scriptblock]$Script)
        $saved = @{}
        foreach ($name in $Variables.Keys) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
        try {
            foreach ($name in $Variables.Keys) { [Environment]::SetEnvironmentVariable($name, $Variables[$name]) }
            & $Script
        }
        finally {
            foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
        }
    }

    $lab = New-ConfigFile 'lab.json'
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'Show-UsaBanner' {
    It 'draws the banner after login from a configuration file and the facts, as PostLogin.Tests holds it' {
        Assert-UsaBannerGoldenFrame -Name 'postlogon-web-16' -Lines @(Show-UsaBanner -Path $lab -Facts $facts -Os ubuntu -ColorMode 16 -Glyphs unicode)
    }

    It 'draws the SSH banner with the host name, without its domain, as PreLogin.Tests holds it' {
        $path = New-ConfigFile 'ssh.json' @{ environment = 'UNSET'; vlans = @(); preLogon = @{ hostName = $true; ip = $true } }
        Assert-UsaBannerGoldenFrame -Name 'prelogon-host-ip' -Lines @(Show-UsaBanner PreLogon -Path $path -Facts $facts -Os ubuntu)
    }

    It 'draws the console''s banner as agetty prints it, the host name and IP filled in' {
        $lines = @(Show-UsaBanner PreInit -Path $lab -Facts $facts -Os ubuntu -ColorMode 16)
        ($lines -join "`n") | Should -Not -Match '\\n|\\4'
        Assert-UsaBannerGoldenFrame -Name 'show-preinit-16' -Lines $lines
    }

    It 'draws the console''s banner without escapes for a terminal without colour' {
        (@(Show-UsaBanner PreInit -Path $lab -Facts $facts -Os ubuntu -ColorMode none) -join "`n") | Should -Not -Match ([regex]::Escape($esc))
    }

    It 'shows Windows'' logon notice for PreInit on Windows: its caption, then its text' {
        $lines = @(Show-UsaBanner PreInit -Path $lab -Os windows)
        $lines[0] | Should -BeExactly 'WARNING'
        $lines[1] | Should -BeExactly ''
        ($lines[2..($lines.Count - 1)] -join ' ') | Should -BeExactly 'This system is for authorized use only. Activity on this system is monitored and recorded. Unauthorized access or use is prohibited.'
        foreach ($line in $lines) { $line.Length | Should -BeLessOrEqual 64 }
    }

    It 'draws from the defaults without -Path, and names this host without -Facts' {
        $lines = @(Show-UsaBanner -Os linux -ColorMode none -Glyphs ascii)
        ($lines -join "`n") | Should -Match ([regex]::Escape([Environment]::MachineName))
        ($lines -join "`n") | Should -Match 'U N S E T'
        ($lines -join "`n") | Should -Not -Match 'all clear'
    }

    It 'takes the mode the configuration sets for this host when asked for auto' {
        $path = New-ConfigFile 'mode.json' @{ color = @{ mode = '16' } }
        $auto = Use-Environment @{ USABANNER_COLOR = $null; NO_COLOR = $null; COLORTERM = $null; WT_SESSION = $null; TERM = 'xterm-256color' } {
            @(Show-UsaBanner -Path $path -Facts $facts -Os ubuntu -Glyphs unicode)
        }
        ($auto -join "`n") | Should -BeExactly (@(Show-UsaBanner -Path $path -Facts $facts -Os ubuntu -Glyphs unicode -ColorMode 16) -join "`n")
    }

    It 'draws ASCII for a client whose locale is not UTF-8, and Unicode for one that is' -Skip:$IsWindows {
        $ascii = Use-Environment @{ USABANNER_GLYPHS = $null; LC_ALL = $null; LC_CTYPE = $null; LANG = 'C' } {
            @(Show-UsaBanner -Path $lab -Facts $facts -Os ubuntu -ColorMode none)
        }
        ($ascii -join "`n") | Should -Not -Match '[^\x00-\x7F]'
        $unicode = Use-Environment @{ USABANNER_GLYPHS = $null; LC_ALL = $null; LC_CTYPE = $null; LANG = 'C.UTF-8' } {
            @(Show-UsaBanner -Path $lab -Facts $facts -Os ubuntu -ColorMode none)
        }
        ($unicode -join "`n") | Should -Match ([string][char]0x2501)
    }

    It 'runs in a real pwsh with its facts intact, as from Windows PowerShell 5.1' {
        $direct = @(Show-UsaBanner -Path $lab -Facts $facts -Os ubuntu -ColorMode none -Glyphs ascii)
        $handed = @(InModuleScope UsaBanner -Parameters @{ Path = $lab; Facts = $facts } {
                param($Path, $Facts)
                Invoke-UsaBannerHandoff -Command 'Show-UsaBanner' -Parameters @{ Path = $Path; Facts = $Facts; Os = 'ubuntu'; ColorMode = 'none'; Glyphs = 'ascii' } -Pwsh (Get-Process -Id $PID).Path
            })
        $handed.Count | Should -Be $direct.Count
        ($handed -join "`n") | Should -BeExactly ($direct -join "`n")
    }
}
