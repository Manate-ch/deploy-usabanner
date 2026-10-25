# FakeHosts.ps1 - the hosts the deploy tests deploy to, dot-sourced in a test file's BeforeAll
# after the module is imported. Folders stand in for a host's file system; every program a
# deploy runs, and every Windows store it changes, is answered here and remembers what each call
# changed. Nothing runs on, or changes, the host the tests run on.
#
#   +------------------+---------------------------------------------------------------------+
#   | Ubuntu           | New-StockHost, then Use-LinuxHost (or Use-StockAnswers with the     |
#   |                  | test's own mocks); Get-HostState, Get-Mode, Get-Calls, Get-Record   |
#   | Windows Server   | New-WindowsHost, then Use-WindowsHost; Get-WindowsHostState         |
#   +------------------+---------------------------------------------------------------------+

# Windows' own sshd_config, as the OpenSSH capability writes it (abridged; its end as written).
$script:StockSshd = @(
    '# This is the sshd server system-wide configuration file.  See'
    '# sshd_config(5) for more information.'
    ''
    '#Port 22'
    '#PubkeyAuthentication yes'
    ''
    '# override default of no subsystems'
    "Subsystem`tsftp`tsftp-server.exe"
    ''
    '# Example of overriding settings on a per-user basis'
    '#Match User anoncvs'
    "#`tAllowTcpForwarding no"
    ''
    'Match Group administrators'
    '       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys'
    ''
) -join "`r`n"

function Write-TestFile {
    # In:  a host folder, a path in it, the text, and the mode in octal
    # Out: nothing; the file is there
    param([string]$Root, [string]$Path, [string]$Text, [string]$Mode = '644')
    $full = Join-Path $Root $Path
    $null = New-Item -ItemType Directory -Path (Split-Path $full) -Force
    [System.IO.File]::WriteAllText($full, $Text)
    [System.IO.File]::SetUnixFileMode($full, [System.IO.UnixFileMode][System.Convert]::ToInt32($Mode, 8))
}

function New-StockHost {
    # In:  -NoSshd for a host without OpenSSH's server; -AbsoluteLink for landscape's link
    #      as Ubuntu ships it, absolute, which run-parts would follow out of the folder
    # Out: the path of a new folder laid out as the parts of a stock Ubuntu 24.04 host that
    #      a deploy reads and writes
    param([switch]$NoSshd, [switch]$AbsoluteLink)
    $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
    foreach ($folder in 'etc/update-motd.d', 'etc/ssh/sshd_config.d', 'etc/systemd/system', 'usr/local/share', 'var/lib') {
        $null = New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force
    }
    Write-TestFile $root 'etc/os-release' "PRETTY_NAME=`"Ubuntu 24.04.3 LTS`"`nNAME=`"Ubuntu`"`nVERSION_ID=`"24.04`"`nID=ubuntu`nID_LIKE=debian`n"
    Write-TestFile $root 'etc/issue' "Ubuntu 24.04.3 LTS \n \l`n`n"
    foreach ($name in '00-header', '10-help-text', '50-motd-news', '85-fwupd', '90-updates-available', '91-release-upgrade', '95-hwe-eol', '98-reboot-required') {
        Write-TestFile $root "etc/update-motd.d/$name" "#!/bin/sh`necho $name`n" -Mode '755'
    }
    Write-TestFile $root 'usr/share/landscape/landscape-sysinfo.wrapper' "#!/bin/sh`necho landscape-sysinfo`n" -Mode '755'
    $target = if ($AbsoluteLink) { '/usr/share/landscape/landscape-sysinfo.wrapper' } else { '../../usr/share/landscape/landscape-sysinfo.wrapper' }
    $null = New-Item -ItemType SymbolicLink -Path (Join-Path $root 'etc/update-motd.d/50-landscape-sysinfo') -Target $target
    if (-not $NoSshd) {
        Write-TestFile $root 'usr/sbin/sshd' '' -Mode '755'
        $null = New-Item -ItemType Directory -Path (Join-Path $root 'run/sshd') -Force
    }
    $root
}

function Get-HostState {
    # In:  a host folder
    # Out: a line for each file, folder and link in it, sorted: its path; its mode; a
    #      file's SHA-256, a link's target
    param([string]$Root)
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object -Property FullName)) {
        $relative = [System.IO.Path]::GetRelativePath($Root, $item.FullName)
        if ($item.LinkTarget) { "$relative -> $($item.LinkTarget)" }
        elseif ($item.PSIsContainer) { "$relative/ $([System.Convert]::ToString([int]$item.UnixFileMode, 8))" }
        else { "$relative $([System.Convert]::ToString([int]$item.UnixFileMode, 8)) $(Get-FileHashText $item.FullName)" }
    }
}

function Get-FileHashText {
    # In:  a file's path
    # Out: its SHA-256 in hex, or unreadable when the tests' user cannot read it
    # Why: a test can make a file no one may read, as the lab met one
    param([string]$Path)
    try { [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($Path))) }
    catch [System.UnauthorizedAccessException] { 'unreadable' }
}

function Get-Mode {
    # In:  a host folder and a path in it
    # Out: the file's mode in octal
    param([string]$Root, [string]$Path)
    [System.Convert]::ToString([int][System.IO.File]::GetUnixFileMode((Join-Path $Root $Path)), 8)
}

function Use-StockAnswers {
    # In:  answers that differ from a stock host's: 'program arguments' -> @{ ExitCode; Output }
    # Out: nothing. Invoke-UsaBannerNative answers as a stock Ubuntu 24.04 host would, in the
    #      words systemd 255 and dpkg used on an Ubuntu 24.04.5 VM (2026-10-22); a call that
    #      changes the host (a unit masked or enabled, a statoverride added, a first sample)
    #      changes what later calls see; each call is logged in $global:UsaDeployCalls
    param([hashtable]$Answers = @{})
    $global:UsaDeployCalls = [System.Collections.Generic.List[string]]::new()
    $global:UsaDeployAnswers = $Answers
    # Running: the services started and not yet stopped, as a run in progress. Disabled: units
    # an admin (or the first install.sh) disabled, which a stock host has enabled. Failed: a run
    # stopped part way, as systemd 255 leaves it ("Failed with result 'signal'", lab 2026-10-23),
    # and a timer masked while active ("Unit to trigger vanished", "Failed with result
    # 'resources'", lab 2026-10-23). Stopped: motd-news.timer, active on a stock host, once stopped.
    $global:UsaDeployUnits = @{ Masked = @(); Enabled = @(); Overrides = @(); Running = @(); Disabled = @(); Failed = @(); Stopped = @() }
    Mock -ModuleName UsaBanner Invoke-UsaBannerNative {
        $call = (@($FilePath) + @($ArgumentList)) -join ' '
        $global:UsaDeployCalls.Add($call)
        if ($global:UsaDeployAnswers.ContainsKey($call)) { return $global:UsaDeployAnswers[$call] }
        $units = $global:UsaDeployUnits
        $done = @{ ExitCode = 0; Output = @() }
        switch -Regex ($call) {
            '^systemctl is-enabled (\S+)$' {
                if ($Matches[1] -in $units.Masked) { return @{ ExitCode = 1; Output = @('masked') } }
                if ($Matches[1] -in $units.Disabled) { return @{ ExitCode = 1; Output = @('disabled') } }
                if ($Matches[1] -in $units.Enabled -or $Matches[1] -eq 'motd-news.timer') { return @{ ExitCode = 0; Output = @('enabled') } }
                return @{ ExitCode = 4; Output = @('not-found') }
            }
            '^systemctl is-active motd-news\.timer$' {
                if ('motd-news.timer' -in $units.Masked -or 'motd-news.timer' -in $units.Stopped) { return @{ ExitCode = 3; Output = @('inactive') } }
                return @{ ExitCode = 0; Output = @('active') }
            }
            '^systemctl is-active (\S+)$' {
                if ($Matches[1] -in $units.Enabled -or $Matches[1] -match '^ssh\.(service|socket)$') { return @{ ExitCode = 0; Output = @('active') } }
                return @{ ExitCode = 3; Output = @('inactive') }
            }
            '^systemctl mask (--now )?(\S+)$' {
                # --now masks first, then stops: either way the reload finds the timer active.
                if ($Matches[2] -eq 'motd-news.timer' -and $Matches[2] -notin $units.Masked -and $Matches[2] -notin $units.Stopped) { $units.Failed += $Matches[2] }
                $units.Masked += $Matches[2]
                return $done
            }
            '^systemctl start (\S+)$' {
                $units.Stopped = @($units.Stopped | Where-Object { $_ -ne $Matches[1] })
                $units.Failed = @($units.Failed | Where-Object { $_ -ne $Matches[1] })
                return $done
            }
            '^systemctl unmask (\S+)$' { $units.Masked = @($units.Masked | Where-Object { $_ -ne $Matches[1] }); return $done }
            '^systemctl enable --now (\S+)$' {
                $units.Enabled += $Matches[1]
                $units.Disabled = @($units.Disabled | Where-Object { $_ -ne $Matches[1] })
                return $done
            }
            '^systemctl disable --now (\S+)$' { $units.Enabled = @($units.Enabled | Where-Object { $_ -ne $Matches[1] }); return $done }
            '^systemctl start --no-block usabanner-sample\.service$' {
                # As sample.sh does at its first run; it runs on until stopped.
                [System.IO.File]::WriteAllText((Join-Path $global:UsaDeployRoot 'var/lib/usabanner/samples.tsv'), '')
                $units.Running += 'usabanner-sample.service'
                return $done
            }
            '^systemctl stop (\S+)$' {
                if ($Matches[1] -in $units.Running) { $units.Failed += $Matches[1] }
                $units.Running = @($units.Running | Where-Object { $_ -ne $Matches[1] })
                if ($Matches[1] -eq 'motd-news.timer') { $units.Stopped += $Matches[1] }
                return $done
            }
            '^systemctl is-failed (\S+)$' {
                if ($Matches[1] -in $units.Failed) { return @{ ExitCode = 0; Output = @('failed') } }
                return @{ ExitCode = 1; Output = @('inactive') }
            }
            '^systemctl reset-failed (\S+)$' { $units.Failed = @($units.Failed | Where-Object { $_ -ne $Matches[1] }); return $done }
            '^dpkg -S (\S+)$' { return @{ ExitCode = 0; Output = @("landscape-common: $($Matches[1])") } }
            '^dpkg-statoverride --list (\S+)$' {
                if ($Matches[1] -in $units.Overrides) { return @{ ExitCode = 0; Output = @("root root 644 $($Matches[1])") } }
                return @{ ExitCode = 1; Output = @() }
            }
            '^dpkg-statoverride --update --add root root 0644 (\S+)$' {
                $units.Overrides += $Matches[1]
                [System.IO.File]::SetUnixFileMode((Join-Path $global:UsaDeployRoot $Matches[1]), [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead')
                return $done
            }
            '^dpkg-statoverride --remove (\S+)$' { $units.Overrides = @($units.Overrides | Where-Object { $_ -ne $Matches[1] }); return $done }
            '^/usr/sbin/sshd -T$' { return @{ ExitCode = 0; Output = @('port 22', 'banner /etc/usabanner/issue.net', 'usepam yes') } }
        }
        $done
    }
}

function Use-LinuxHost {
    # In:  a host folder (New-StockHost), and answers as for Use-StockAnswers
    # Out: nothing; the deploy works on that folder as root, with the host's name and address
    #      h-vsl-web1.ad.example and 10.20.40.80, and the programs answered as there
    param([string]$Root, [hashtable]$Answers = @{})
    $global:UsaDeployRoot = $Root
    Use-StockAnswers $Answers
    Mock -ModuleName UsaBanner Get-UsaBannerHostRoot { $global:UsaDeployRoot }
    Mock -ModuleName UsaBanner Test-UsaBannerPrivileged { $true }
    Mock -ModuleName UsaBanner Get-UsaBannerHostFacts { @{ Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80'; Services = @{ Text = 'ssh, cron, chrony active'; Level = 'good' } } }
}

function Get-Calls {
    # Out: the programs run since the answers were set, a line each, reads left out when -Changes
    param([switch]$Changes)
    @($global:UsaDeployCalls | Where-Object { -not $Changes -or $_ -notmatch '^systemctl is-(enabled|active|failed) |^dpkg -S |^dpkg-statoverride --list |^/usr/sbin/sshd -T$' })
}

function Get-Record {
    # Out: the deploy's record on the host, as a hashtable
    Get-Content -LiteralPath (Join-Path $global:UsaDeployRoot 'var/lib/usabanner/deploy.json') -Raw | ConvertFrom-Json -AsHashtable
}

function New-WindowsHost {
    # Out: the path of a new folder standing in for a Windows host: ProgramData with
    #      sshd_config, Program Files with PowerShell 7 and the modules folder, and Windows
    #      with Windows PowerShell's folder and an admin's own all-users profile (CRLF, UTF-8
    #      with a byte order mark)
    $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
    foreach ($folder in 'ProgramData/ssh', 'ProgramFiles/PowerShell/7', 'ProgramFiles/WindowsPowerShell/Modules', 'Windows/System32/WindowsPowerShell/v1.0') {
        $null = New-Item -ItemType Directory -Path (Join-Path $root $folder) -Force
    }
    [System.IO.File]::WriteAllText((Join-Path $root 'ProgramData/ssh/sshd_config'), $StockSshd)
    [System.IO.File]::WriteAllText((Join-Path $root 'Windows/System32/WindowsPowerShell/v1.0/profile.ps1'), "# Contoso's own profile`r`nSet-Location C:\`r`n", [System.Text.UTF8Encoding]::new($true))
    $root
}

function Get-WindowsHostState {
    # In:  a host folder
    # Out: a line for each file and folder in it, sorted, a file with its SHA-256; then the
    #      logon notice, OpenSSH's default shell and each task, as the stores hold them
    param([string]$Root)
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object -Property FullName)) {
        $relative = [System.IO.Path]::GetRelativePath($Root, $item.FullName)
        if ($item.PSIsContainer) { "$relative/" }
        else { "$relative $(Get-FileHashText $item.FullName)" }
    }
    "notice: $($global:UsaWinNotice.Exists) '$($global:UsaWinNotice.Caption)' '$($global:UsaWinNotice.Text)'"
    "default shell: '$global:UsaWinShell'"
    foreach ($name in @($global:UsaWinTasks.Keys | Sort-Object)) { "task ${name}: $($global:UsaWinTasks[$name].Execute) $($global:UsaWinTasks[$name].Arguments)" }
}

function Use-WindowsHost {
    # In:  the host folder, and answers that differ from the stock host's: 'program arguments'
    #      -> @{ ExitCode; Output }
    # Out: nothing; every Windows seam answers for that host, BEVSW-APP1.ad.example at
    #      10.20.40.81, and each call that changes it is logged in $global:UsaWinCalls
    param([string]$Root, [hashtable]$Answers = @{})
    $global:UsaWinRoot = $Root
    $global:UsaWinCalls = [System.Collections.Generic.List[string]]::new()
    $global:UsaWinAnswers = $Answers
    $global:UsaWinNotice = @{ Caption = ''; Text = ''; Exists = $true }
    # OpenSSH's DefaultShell; '' for none set, which is cmd.exe.
    $global:UsaWinShell = 'C:\Program Files\PowerShell\7\pwsh.exe'
    # The banner's tasks, by name: @{ Execute; Arguments; Schedule }; and those with a run in progress.
    $global:UsaWinTasks = @{}
    $global:UsaWinRunning = @{}
    $global:UsaWinAcl = $false
    # UsagiTools, the folder the banner's own is in, once the deploy has set its ACL.
    $global:UsaWinParentAcl = $false
    # Each folder's owner and ACL entries, by path (Get-UsaBannerFolderSecurity). A folder not
    # listed is Administrators', with what ProgramData passes down: Users may read, and add files
    # and folders, not delete them; CREATOR OWNER's entry is inherit-only.
    $global:UsaWinSecurity = @{}
    Mock -ModuleName UsaBanner Get-UsaBannerHostOs { 'windows' }
    Mock -ModuleName UsaBanner Get-UsaBannerWindowsPaths { @{ ProgramData = "$global:UsaWinRoot/ProgramData"; ProgramFiles = "$global:UsaWinRoot/ProgramFiles"; Windir = "$global:UsaWinRoot/Windows" } }
    Mock -ModuleName UsaBanner Get-UsaBannerWindowsBuild { 20348 }
    Mock -ModuleName UsaBanner Test-UsaBannerPrivileged { $true }
    Mock -ModuleName UsaBanner Get-UsaBannerWindowsSshd { 'C:\Windows\System32\OpenSSH\sshd.exe' }
    Mock -ModuleName UsaBanner Get-UsaBannerServiceState { 'Running' }
    # Started after anything a test writes: sshd has read sshd_config as it is.
    Mock -ModuleName UsaBanner Get-UsaBannerServiceStart { [datetime]::UtcNow }
    Mock -ModuleName UsaBanner Get-UsaBannerHostFacts { @{ Name = 'BEVSW-APP1.ad.example'; Ip = '10.20.40.81'; Services = @{ Text = 'sshd, W32Time running'; Level = 'good' } } }
    Mock -ModuleName UsaBanner Get-UsaBannerSshDefaultShell { $global:UsaWinShell }
    Mock -ModuleName UsaBanner Write-UsaBannerSshDefaultShell {
        $global:UsaWinCalls.Add($(if ($Remove) { 'default shell removed' } else { "default shell set: $Path" }))
        $global:UsaWinShell = if ($Remove) { '' } else { $Path }
    }
    Mock -ModuleName UsaBanner Find-UsaBannerPwsh { 'C:\Program Files\PowerShell\7\pwsh.exe' }
    Mock -ModuleName UsaBanner Read-UsaBannerLogonNoticeValue { @{ Caption = $global:UsaWinNotice.Caption; Text = $global:UsaWinNotice.Text; Exists = $global:UsaWinNotice.Exists } }
    Mock -ModuleName UsaBanner Write-UsaBannerLogonNoticeValue {
        $global:UsaWinCalls.Add($(if ($Remove) { 'notice removed' } else { "notice set: $Caption" }))
        $global:UsaWinNotice = if ($Remove) { @{ Caption = ''; Text = ''; Exists = $false } } else { @{ Caption = $Caption; Text = $Text; Exists = $true } }
    }
    Mock -ModuleName UsaBanner Test-UsaBannerFolderAcl {
        $set = if ($Path -eq "$global:UsaWinRoot/ProgramData/UsagiTools") { $global:UsaWinParentAcl } else { $global:UsaWinAcl }
        $set -and [System.IO.Directory]::Exists($Path)
    }
    Mock -ModuleName UsaBanner Get-UsaBannerFolderSecurity {
        if ($global:UsaWinSecurity.ContainsKey($Path)) { return $global:UsaWinSecurity[$Path] }
        @{ Owner = 'S-1-5-32-544'; OwnerName = 'BUILTIN\Administrators'; Rules = @(
            @{ Sid = 'S-1-5-18'; Name = 'NT AUTHORITY\SYSTEM'; Allow = $true; Rights = 0x1F01FF; InheritOnly = $false }
            @{ Sid = 'S-1-5-32-544'; Name = 'BUILTIN\Administrators'; Allow = $true; Rights = 0x1F01FF; InheritOnly = $false }
            @{ Sid = 'S-1-5-32-545'; Name = 'BUILTIN\Users'; Allow = $true; Rights = 0x1200A9; InheritOnly = $false }
            @{ Sid = 'S-1-5-32-545'; Name = 'BUILTIN\Users'; Allow = $true; Rights = 0x116; InheritOnly = $false }
            @{ Sid = 'S-1-3-0'; Name = 'CREATOR OWNER'; Allow = $true; Rights = 0x10000000; InheritOnly = $true }
        ) }
    }
    Mock -ModuleName UsaBanner Get-UsaBannerTask { $global:UsaWinTasks[$Name] }
    Mock -ModuleName UsaBanner Register-UsaBannerTask {
        $global:UsaWinCalls.Add("task registered: $($Spec.Path)$($Spec.Name)")
        $global:UsaWinTasks[$Spec.Name] = @{ Execute = $Spec.Execute; Arguments = $Spec.Arguments; Schedule = $Spec.Schedule }
    }
    Mock -ModuleName UsaBanner Unregister-UsaBannerTask { $global:UsaWinCalls.Add("task unregistered: $Name"); $global:UsaWinTasks.Remove($Name) }
    Mock -ModuleName UsaBanner Start-UsaBannerTask {
        $global:UsaWinCalls.Add("task started: $Name")
        # As Update-UsaBannerSample does at its first run; it runs on until stopped.
        if ($Name -eq 'UsaBanner sample') { [System.IO.File]::WriteAllText("$global:UsaWinRoot/ProgramData/UsagiTools/Banner/samples.tsv", '') }
        $global:UsaWinRunning[$Name] = $true
    }
    Mock -ModuleName UsaBanner Stop-UsaBannerTask { $global:UsaWinCalls.Add("task stopped: $Name"); $global:UsaWinRunning.Remove($Name) }
    Mock -ModuleName UsaBanner Invoke-UsaBannerNative {
        $call = (@($FilePath) + @($ArgumentList)) -join ' '
        $global:UsaWinCalls.Add($call)
        if ($global:UsaWinAnswers.ContainsKey($call)) { return $global:UsaWinAnswers[$call] }
        if ($FilePath -eq 'icacls.exe' -and $ArgumentList -contains '/inheritance:r') {
            if ($ArgumentList[0] -eq "$global:UsaWinRoot/ProgramData/UsagiTools") { $global:UsaWinParentAcl = $true }
            else {
                # The ACL comes before any file: nothing is in the folder yet.
                if (@([System.IO.Directory]::GetFiles($ArgumentList[0])).Count) { $global:UsaWinCalls.Add('ACL SET AFTER A FILE') }
                $global:UsaWinAcl = $true
            }
        }
        @{ ExitCode = 0; Output = @() }
    }
}
