# WindowsDeploy.ps1 - Deploy-UsaBanner and Remove-UsaBanner on Windows Server
# (docs/DECISIONS.md, D2, D5, D14, D21 and D23). What a deploy puts on a host:
#
#   +----------------------------------------+-------------------------------+
#   | Where                                  | What                          |
#   +----------------------------------------+-------------------------------+
#   | %ProgramFiles%\WindowsPowerShell\      | the module: Windows           |
#   |   Modules\UsaBanner\<version>\         | PowerShell 5.1 and 7 find it  |
#   | %ProgramData%\UsagiTools\Banner\       | owned by Administrators;      |
#   |                                        | Administrators and SYSTEM may |
#   |                                        | change it, Users read (D14)   |
#   |   usabanner.json                       | the configuration (D12)       |
#   |   usabanner.psd1                       | the same, as data, which each |
#   |                                        | login reads (D2)              |
#   |   sshd-banner.txt                      | the SSH banner                |
#   |   deploy.json                          | what the deploy changed       |
#   | both all-users profiles                | a block that shows the banner |
#   |                                        | after an SSH login            |
#   | sshd_config                            | its Banner line               |
#   | the logon notice                       | the legal text before a       |
#   |                                        | console or RDP sign-in, where |
#   |                                        | no other is set               |
#   | the task \UsagiTools\UsaBanner sample  | the periodic job: as SYSTEM,  |
#   |                                        | every 15 minutes (D17)        |
#   | the task \UsagiTools\UsaBanner update  | the update job, once a day,   |
#   |                                        | where the update channel is   |
#   |                                        | on (D14)                      |
#   +----------------------------------------+-------------------------------+
#
# OpenSSH, PowerShell 7 and the SSH default shell belong to deploy-usawinssh
# (D21): a deploy checks them and says what is missing, and changes none.

$script:UsaProfileBegin = '# >>> UsaBanner: the banner after an SSH login (Deploy-UsaBanner) >>>'
$script:UsaProfileEnd = '# <<< UsaBanner <<<'
$script:UsaSshdEntry = 'Banner __PROGRAMDATA__/UsagiTools/Banner/sshd-banner.txt'
$script:UsaSshdNote = '# Turned off by Deploy-UsaBanner, which put its own Banner above: '
$script:UsaNoticeKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
$script:UsaTaskPath = '\UsagiTools\'
$script:UsaTaskName = 'UsaBanner sample'
$script:UsaUpdateTaskName = 'UsaBanner update'

function Get-UsaBannerWindowsPaths {
    <#
    .SYNOPSIS
    The folders a deploy on Windows works in: ProgramData, ProgramFiles and
    Windir, this host's. The tests mock them with folders of their own.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    @{ ProgramData = [string]$env:ProgramData; ProgramFiles = [string]$env:ProgramFiles; Windir = [string]$env:windir }
}

function Get-UsaBannerWindowsBuild {
    # Out: this Windows's build number: 20348 is Server 2022
    [CmdletBinding()]
    [OutputType([int])]
    param()
    [System.Environment]::OSVersion.Version.Build
}

function Get-UsaBannerWindowsSshd {
    # Out: the sshd.exe the sshd service runs: System32\OpenSSH for Windows'
    #      own capability, Program Files\OpenSSH for Microsoft's MSI; nothing
    #      when there is no sshd service
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
    if ($service -and $service.PathName -match '^"?([^"]+?\.exe)') { $Matches[1] }
}

function Get-UsaBannerServiceState {
    # In:  a service's name
    # Out: its state as the service manager words it (Running, Stopped);
    #      '' when there is no such service
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($service) { [string]$service.Status } else { '' }
}

function Get-UsaBannerServiceStart {
    # In:  a service's name
    # Out: when its process started, in UTC; nothing when it does not run,
    #      or that cannot be read
    # Why: CIM, not Get-Process: a process SYSTEM runs refuses another
    #      user's Get-Process its start time
    [CmdletBinding()]
    [OutputType([datetime])]
    param([Parameter(Mandatory)][string]$Name)
    $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if (-not $service -or -not $service.ProcessId) { return }
    $process = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId=$($service.ProcessId)" -ErrorAction SilentlyContinue
    if ($process -and $process.CreationDate) { $process.CreationDate.ToUniversalTime() }
}

function Get-UsaBannerSshDefaultShell {
    # Out: OpenSSH's DefaultShell; '' when none is set, which is cmd.exe
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $key = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell' -ErrorAction SilentlyContinue
    if ($key) { [string]$key.DefaultShell } else { '' }
}

function Get-UsaBannerSshShellName {
    # Out: the program sshd starts at a login, by its file name: pwsh.exe,
    #      powershell.exe, or cmd.exe where no DefaultShell is set
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $shell = Get-UsaBannerSshDefaultShell
    if ($shell) { @($shell.Trim().Trim('"') -split '[\\/]')[-1] } else { 'cmd.exe' }
}

function Read-UsaBannerLogonNoticeValue {
    <#
    .SYNOPSIS
    The logon notice as the registry holds it.
    .DESCRIPTION
    Out: @{ Caption; Text; Exists }: LegalNoticeCaption and LegalNoticeText
         under the Policies\System key, '' where one is missing; Exists says
         whether both values are there at all.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $key = Get-ItemProperty -LiteralPath $script:UsaNoticeKey -ErrorAction SilentlyContinue
    $caption = if ($key -and $key.PSObject.Properties['LegalNoticeCaption']) { [string]$key.LegalNoticeCaption } else { $null }
    $text = if ($key -and $key.PSObject.Properties['LegalNoticeText']) { [string]$key.LegalNoticeText } else { $null }
    @{ Caption = [string]$caption; Text = [string]$text; Exists = ($null -ne $caption -and $null -ne $text) }
}

function Write-UsaBannerLogonNoticeValue {
    # In:  the caption and text to set, or -Remove to take both values away
    # Out: nothing; the registry holds them
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Caption = '', [AllowEmptyString()][string]$Text = '', [switch]$Remove)
    if ($Remove) {
        Remove-ItemProperty -LiteralPath $script:UsaNoticeKey -Name 'LegalNoticeCaption', 'LegalNoticeText' -ErrorAction SilentlyContinue
        return
    }
    Set-ItemProperty -LiteralPath $script:UsaNoticeKey -Name 'LegalNoticeCaption' -Value $Caption -Type String
    Set-ItemProperty -LiteralPath $script:UsaNoticeKey -Name 'LegalNoticeText' -Value $Text -Type String
}

function Test-UsaBannerFolderAcl {
    <#
    .SYNOPSIS
    True when a folder has the banner's ACL (D14).
    .DESCRIPTION
    Owned by Administrators; inheritance off; SYSTEM and Administrators full
    control, Users read and execute, each for the folder, its subfolders and
    its files; no other entry.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $acl = Get-Acl -LiteralPath $Path
    if (-not $acl.AreAccessRulesProtected) { return $false }
    if ($acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne 'S-1-5-32-544') { return $false }
    $want = @{ 'S-1-5-18' = 'FullControl'; 'S-1-5-32-544' = 'FullControl'; 'S-1-5-32-545' = 'ReadAndExecute, Synchronize' }
    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    if ($rules.Count -ne $want.Count) { return $false }
    foreach ($rule in $rules) {
        $sid = $rule.IdentityReference.Value
        if (-not $want.ContainsKey($sid) -or [string]$rule.FileSystemRights -ne $want[$sid] -or $rule.AccessControlType -ne 'Allow' -or
            [string]$rule.InheritanceFlags -ne 'ContainerInherit, ObjectInherit') { return $false }
    }
    $true
}

function Get-UsaBannerTask {
    # In:  one of the banner's tasks, by name, in \UsagiTools\; or the old
    #      banner's, with -Path \
    # Out: its program and arguments, as @{ Execute; Arguments }; nothing
    #      when there is no such task
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Name, [string]$Path = $script:UsaTaskPath)
    $task = Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction SilentlyContinue
    if ($task) { @{ Execute = [string]$task.Actions[0].Execute; Arguments = [string]$task.Actions[0].Arguments } }
}

function Register-UsaBannerTask {
    # In:  the task's spec (New-UsaBannerSampleTaskSpec, New-UsaBannerUpdateTaskSpec)
    # Out: nothing; the task is registered as SYSTEM, replacing one of the
    #      same name. A daily task runs within an hour after 03:00, and at
    #      the next start when the host was off then; the sample task 2
    #      minutes after a start and every 15 minutes
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Spec)
    $action = New-ScheduledTaskAction -Execute $Spec.Execute -Argument $Spec.Arguments
    if ($Spec.Schedule -eq 'daily') {
        $triggers = @(New-ScheduledTaskTrigger -Daily -At '03:00' -RandomDelay ([timespan]::FromHours(1)))
        $limit = [timespan]::FromMinutes(30)
    }
    else {
        $startup = New-ScheduledTaskTrigger -AtStartup
        $startup.Delay = 'PT2M'
        $triggers = @($startup, (New-ScheduledTaskTrigger -Once -At ([datetime]::Now.AddMinutes(1)) -RepetitionInterval ([timespan]::FromMinutes(15))))
        $limit = [timespan]::FromMinutes(10)
    }
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit $limit -MultipleInstances IgnoreNew -StartWhenAvailable
    $null = Register-ScheduledTask -TaskPath $Spec.Path -TaskName $Spec.Name -Action $action -Trigger $triggers -Principal $principal -Settings $settings -Description $Spec.Description -Force
}

function Unregister-UsaBannerTask {
    # In:  one of the banner's tasks, by name; or the old banner's, with -Path \
    # Out: nothing; the task is gone
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name, [string]$Path = $script:UsaTaskPath)
    Unregister-ScheduledTask -TaskPath $Path -TaskName $Name -Confirm:$false
}

function Start-UsaBannerTask {
    # In:  one of the banner's tasks, by name
    # Out: nothing; the task runs now, in the background
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Start-ScheduledTask -TaskPath $script:UsaTaskPath -TaskName $Name
}

function Stop-UsaBannerTask {
    # In:  one of the banner's tasks, by name
    # Out: nothing; a run of it in progress is stopped
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Stop-ScheduledTask -TaskPath $script:UsaTaskPath -TaskName $Name
}

function New-UsaBannerSampleTaskSpec {
    <#
    .SYNOPSIS
    The periodic job's task on Windows (D17), as data.
    .DESCRIPTION
    In:  the pwsh.exe it runs.
    Out: @{ Path; Name; Execute; Arguments; Description; Schedule }. As
         SYSTEM, 2 minutes after a start and every 15 minutes, it runs
         Update-UsaBannerSample in the module: a sample and the slow facts.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Pwsh)
    @{
        Path        = $script:UsaTaskPath
        Name        = $script:UsaTaskName
        Execute     = $Pwsh
        Arguments   = '-NoProfile -NonInteractive -Command "& (Import-Module UsaBanner -PassThru) { Update-UsaBannerSample }"'
        Description = 'UsaBanner: sample this host for its banner every 15 minutes (Deploy-UsaBanner).'
        Schedule    = 'sample'
    }
}

function New-UsaBannerUpdateTaskSpec {
    <#
    .SYNOPSIS
    The update job's task on Windows (D14), as data.
    .DESCRIPTION
    In:  the pwsh.exe it runs.
    Out: @{ Path; Name; Execute; Arguments; Description; Schedule }. As
         SYSTEM, once a day, it runs Update-UsaBannerRelease in the module.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Pwsh)
    @{
        Path        = $script:UsaTaskPath
        Name        = $script:UsaUpdateTaskName
        Execute     = $Pwsh
        Arguments   = '-NoProfile -NonInteractive -Command "& (Import-Module UsaBanner -PassThru) { Update-UsaBannerRelease }"'
        Description = 'UsaBanner: look for a newer release of the banner once a day, and say so or install it (Deploy-UsaBanner -Update).'
        Schedule    = 'daily'
    }
}

function New-UsaBannerProfileBlock {
    <#
    .SYNOPSIS
    The block an all-users profile holds to show the banner after an SSH
    login.
    .DESCRIPTION
    In:  the configuration's data file (usabanner.psd1).
    Out: the block's lines. It shows the banner once in a session, at an
         interactive SSH login only: not at the console (D2), and not for
         scp, sftp or a command run over SSH, which start PowerShell with
         -Command, -File or -NonInteractive. A failure is one warning, and
         the login goes on. Windows PowerShell 5.1 reads it too, so it is
         5.1 syntax; there Show-UsaBanner runs itself in pwsh.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$DataFile)
    $path = $DataFile.Replace("'", "''")
    $script:UsaProfileBegin
    '# Shown once a session, at an interactive SSH login only. Remove-UsaBanner takes this block out.'
    'if ($env:SSH_CONNECTION -and -not $env:USABANNER_SHOWN -and -not @([Environment]::GetCommandLineArgs() | Where-Object { $_ -match ''^[-/](c|command|e|ec|encodedcommand|f|file|noni|noninteractive)$'' }).Count) {'
    '    $env:USABANNER_SHOWN = ''1'''
    "    try { Show-UsaBanner -Path '$path' | Out-Host }"
    '    catch { Write-Warning "UsaBanner: $($_.Exception.Message)" }'
    '}'
    $script:UsaProfileEnd
}

function Set-UsaBannerProfileText {
    <#
    .SYNOPSIS
    A profile's text with the banner's block in it.
    .DESCRIPTION
    In:  the profile's text ('' for none), and the block's lines.
    Out: the text with the block in place of the one it held, or added at
         its end after a blank line; nothing else changes. The block takes
         the profile's line ends: CRLF unless the text has LF alone.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Text = '', [Parameter(Mandatory)][string[]]$Block)
    $eol = if ($Text -match "`r`n") { "`r`n" } elseif ($Text -match "`n") { "`n" } else { "`r`n" }
    $joined = $Block -join $eol
    $found = [regex]::Match($Text, '(?s)' + [regex]::Escape($script:UsaProfileBegin) + '.*?' + [regex]::Escape($script:UsaProfileEnd))
    if ($found.Success) { return $Text.Substring(0, $found.Index) + $joined + $Text.Substring($found.Index + $found.Length) }
    if (-not $Text.Trim()) { return "$joined$eol" }
    $Text.TrimEnd("`r", "`n") + $eol + $eol + $joined + $eol
}

function Remove-UsaBannerProfileText {
    <#
    .SYNOPSIS
    A profile's text without the banner's block.
    .DESCRIPTION
    In:  the profile's text, and the block's first and last lines: the
         banner's, or with -Begin and -End the old banner's, which
         Install-ManatechBanner.ps1 adds the same way.
    Out: the text as it was before Set-UsaBannerProfileText added the block:
         the block and the blank line put before it are taken out. A profile
         that held only the block comes back empty.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Text = '',
        [string]$Begin = $script:UsaProfileBegin,
        [string]$End = $script:UsaProfileEnd
    )
    $pattern = '(?s)(\r?\n\r?\n)?' + [regex]::Escape($Begin) + '.*?' + [regex]::Escape($End) + '(\r?\n)?'
    $found = [regex]::Match($Text, $pattern)
    if (-not $found.Success) { return $Text }
    $before = $Text.Substring(0, $found.Index)
    $after = $Text.Substring($found.Index + $found.Length)
    if ($found.Groups[1].Success -and -not $after) { return $before + ($found.Groups[1].Value -replace '(\r?\n)\r?\n$', '$1') }
    $before + $after
}

function Set-UsaBannerSshdBannerLine {
    <#
    .SYNOPSIS
    sshd_config's lines with the banner's Banner line in it.
    .DESCRIPTION
    In:  sshd_config's lines, and the date for the note on a line turned off.
    Out: @{ Lines; Changed; Scoped }. sshd takes the first Banner it reads,
         and a Banner after the first Match block applies only to the
         sessions it matches. So the banner's line goes before the first
         Match, with a blank line after it, and any other Banner above the
         first Match is turned off, kept behind a note. A Banner inside a
         Match block is someone else's choice for those sessions: Scoped
         lists it, and it stays. Changed is false when the file already has
         the banner's line as its only Banner above the first Match.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyCollection()][string[]]$Lines = @())
    $firstMatch = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^\s*Match\s') { $firstMatch = $i; break } }
    $end = if ($firstMatch -lt 0) { $Lines.Count } else { $firstMatch }
    $global = @(for ($i = 0; $i -lt $end; $i++) { if ($Lines[$i] -match '^\s*Banner\s') { $i } })
    $scoped = @(for ($i = $end; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -match '^\s*Banner\s') { $Lines[$i].Trim() } })
    if ($global.Count -eq 1 -and $Lines[$global[0]].Trim() -eq $script:UsaSshdEntry) {
        return @{ Lines = $Lines; Changed = $false; Scoped = $scoped }
    }
    # With no Match block the line goes last, before the final newline's empty line.
    $at = $end
    if ($end -eq $Lines.Count -and $Lines.Count -gt 0 -and $Lines[-1] -eq '') { $at = $Lines.Count - 1 }
    $new = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($i -eq $at) {
            $new.Add($script:UsaSshdEntry)
            # A blank line between it and the Match block that follows.
            if ($end -lt $Lines.Count) { $new.Add('') }
        }
        if ($i -in $global) { $new.Add($script:UsaSshdNote + $Lines[$i].Trim()) } else { $new.Add($Lines[$i]) }
    }
    if ($at -eq $Lines.Count) { $new.Add($script:UsaSshdEntry) }
    @{ Lines = $new.ToArray(); Changed = $true; Scoped = $scoped }
}

function Remove-UsaBannerSshdBannerLine {
    <#
    .SYNOPSIS
    sshd_config's lines without the banner's Banner line.
    .DESCRIPTION
    Out: @{ Lines; Changed }: the banner's line taken out, with the blank
         line Set-UsaBannerSshdBannerLine put between it and a Match block;
         each Banner it turned off back as it was.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyCollection()][string[]]$Lines = @())
    $new = [System.Collections.Generic.List[string]]::new()
    $changed = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq $script:UsaSshdEntry) {
            $changed = $true
            if ($i + 2 -lt $Lines.Count -and $Lines[$i + 1] -eq '' -and $Lines[$i + 2] -match '^\s*Match\s') { $i++ }
            continue
        }
        if ($Lines[$i].StartsWith($script:UsaSshdNote)) {
            $new.Add($Lines[$i].Substring($script:UsaSshdNote.Length))
            $changed = $true
            continue
        }
        $new.Add($Lines[$i])
    }
    @{ Lines = $new.ToArray(); Changed = $changed }
}

function Read-UsaBannerWindowsText {
    # In:  a text file's path
    # Out: @{ Text; Encoding }: its text, and the encoding to write it back
    #      in: UTF-8 or UTF-16 with the byte order mark it had, else UTF-8
    #      without one; '' and UTF-8 for a file that is not there
    # Why: a profile someone wrote stays in their encoding
    param([Parameter(Mandatory)][string]$Path)
    $none = [System.Text.UTF8Encoding]::new($false)
    if (-not [System.IO.File]::Exists($Path)) { return @{ Text = ''; Encoding = $none } }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $encoding = $none
    if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $encoding = [System.Text.UTF8Encoding]::new($true) }
    elseif ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $encoding = [System.Text.UnicodeEncoding]::new($false, $true) }
    elseif ($bytes.Count -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $encoding = [System.Text.UnicodeEncoding]::new($true, $true) }
    $skip = $encoding.GetPreamble().Count
    @{ Text = $encoding.GetString($bytes, $skip, $bytes.Count - $skip); Encoding = $encoding }
}

function ConvertTo-UsaBannerWindowsBytes {
    # In:  a text and its encoding (Read-UsaBannerWindowsText)
    # Out: the bytes of a file holding it: the byte order mark, then the text
    param([AllowEmptyString()][string]$Text, [Parameter(Mandatory)][System.Text.Encoding]$Encoding)
    [byte[]]($Encoding.GetPreamble() + $Encoding.GetBytes($Text))
}

function Get-UsaBannerWindowsLayout {
    <#
    .SYNOPSIS
    Where each part of the banner goes on this Windows host.
    .DESCRIPTION
    Out: @{ Data; Modules; Profiles; SshdConfig; Old; OldData; OldSshText }:
         the banner's own folder; the modules folder for all users; the
         all-users profile of each PowerShell installed (Windows
         PowerShell's always, PowerShell 7's where its folder is);
         sshd_config; and what the old banner
         (windows/Install-ManatechBanner.ps1) leaves, to look for: its
         folder and its SSH banner file.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $paths = Get-UsaBannerWindowsPaths
    $profiles = @([System.IO.Path]::Combine($paths.Windir, 'System32', 'WindowsPowerShell', 'v1.0', 'profile.ps1'))
    $seven = [System.IO.Path]::Combine($paths.ProgramFiles, 'PowerShell', '7')
    if ([System.IO.Directory]::Exists($seven)) { $profiles += [System.IO.Path]::Combine($seven, 'profile.ps1') }
    $oldData = [System.IO.Path]::Combine($paths.ProgramData, 'Manatech')
    $oldSshText = [System.IO.Path]::Combine($paths.ProgramData, 'ssh', 'manatech-banner.txt')
    @{
        Data       = [System.IO.Path]::Combine($paths.ProgramData, 'UsagiTools', 'Banner')
        Modules    = [System.IO.Path]::Combine($paths.ProgramFiles, 'WindowsPowerShell', 'Modules')
        Profiles   = $profiles
        SshdConfig = [System.IO.Path]::Combine($paths.ProgramData, 'ssh', 'sshd_config')
        Old        = @($oldData, $oldSshText)
        OldData    = $oldData
        OldSshText = $oldSshText
    }
}

function Assert-UsaBannerWindowsHost {
    <#
    .SYNOPSIS
    Stops a deploy or a removal that cannot go ahead here, saying why.
    .DESCRIPTION
    Throws unless this process runs as an administrator (under -WhatIf,
    anyone may look); on a Windows older than Server 2022 (D15); and, for a
    deploy without -ReplaceOldBanner, when the old banner is installed,
    naming what of it was found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Layout,
        [Parameter(Mandatory)][string]$Command,
        [switch]$RefuseOldInstall
    )
    if (-not $WhatIfPreference -and -not (Test-UsaBannerPrivileged)) {
        throw "UsaBanner: $Command changes files under Program Files and ProgramData, the registry and the scheduled tasks, so it runs in an elevated PowerShell. With -WhatIf it only says what it would change, and anyone may run it."
    }
    if ((Get-UsaBannerWindowsBuild) -lt 20348) {
        throw "UsaBanner: $Command works on Windows Server 2022 and later (build 20348 and up), and Ubuntu 24.04 and later."
    }
    if (-not $RefuseOldInstall) { return }
    $found = @(Find-UsaBannerWindowsOldInstall -Layout $Layout)
    if ($found.Count) {
        throw "UsaBanner: this host has the banner of this repository's Install-ManatechBanner.ps1 ($($found -join ', ')). $Command does not install beside it: $Command -ReplaceOldBanner takes that banner off first, then deploys this one."
    }
}

function Find-UsaBannerWindowsOldInstall {
    # In:  the layout (Get-UsaBannerWindowsLayout)
    # Out: each file and folder of today's banner
    #      (windows/Install-ManatechBanner.ps1) on the host, and each profile
    #      that holds its block
    param([Parameter(Mandatory)][hashtable]$Layout)
    $Layout.Old | Where-Object { [System.IO.File]::Exists($_) -or [System.IO.Directory]::Exists($_) }
    $Layout.Profiles | Where-Object { [System.IO.File]::Exists($_) -and (Read-UsaBannerWindowsText -Path $_).Text.Contains('# >>> Manatech banner') }
}

function Set-UsaBannerDataFolder {
    <#
    .SYNOPSIS
    Makes the banner's own folder, and gives it the banner's ACL (D14).
    .DESCRIPTION
    In:  the folder, and the folders made so far.
    Out: a line for each change. Owner Administrators, so no one who made
         the folder first keeps an owner's right to change its ACL;
         inheritance off; SYSTEM and Administrators full control, Users read
         and execute; whatever is in it already inherits that ACL.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][System.Collections.Generic.List[string]]$Created
    )
    if (-not [System.IO.Directory]::Exists($Path)) {
        if (-not $PSCmdlet.ShouldProcess($Path, 'Make the banner''s own folder')) { return }
        New-UsaBannerHostFolder -Root '' -Path $Path -Created $Created -Mode $null
        "made ${Path}: the banner's own folder"
    }
    if (Test-UsaBannerFolderAcl -Path $Path) { return }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Set its owner to Administrators, and its ACL: Administrators and SYSTEM full control, Users read and execute, nothing inherited')) { return }
    $owner = Invoke-UsaBannerNative -FilePath 'icacls.exe' -ArgumentList $Path, '/setowner', '*S-1-5-32-544', '/T', '/Q'
    # The folder alone: with /T, a file already in it lost its inherited ACEs
    # and took none of these, which are a folder's (OI)(CI), so nothing could
    # read it, and icacls still said it succeeded (Server 2025, 2026-10-23).
    $grant = Invoke-UsaBannerNative -FilePath 'icacls.exe' -ArgumentList $Path, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-32-545:(OI)(CI)RX', '/Q'
    $reset = @{ ExitCode = 0; Output = @() }
    if (@([System.IO.Directory]::GetFileSystemEntries($Path)).Count) {
        $reset = Invoke-UsaBannerNative -FilePath 'icacls.exe' -ArgumentList ([System.IO.Path]::Combine($Path, '*')), '/reset', '/T', '/Q'
    }
    if ($owner.ExitCode -ne 0 -or $grant.ExitCode -ne 0 -or $reset.ExitCode -ne 0) {
        throw "UsaBanner: icacls could not set the ACL of ${Path}, so nothing more is changed: $(@($owner.Output) + @($grant.Output) + @($reset.Output) -join ' ')"
    }
    "set the ACL of ${Path}: Administrators and SYSTEM may change it, Users read it"
}

function Set-UsaBannerWindowsProfiles {
    # In:  the profiles, and the configuration's data file
    # Out: a line for each profile whose block was written
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([string[]]$Profiles, [Parameter(Mandatory)][string]$DataFile)
    $block = @(New-UsaBannerProfileBlock -DataFile $DataFile)
    foreach ($path in $Profiles) {
        $file = Read-UsaBannerWindowsText -Path $path
        $text = Set-UsaBannerProfileText -Text $file.Text -Block $block
        Set-UsaBannerHostFile -Root '' -Path $path -Bytes (ConvertTo-UsaBannerWindowsBytes -Text $text -Encoding $file.Encoding) -Mode $null -What 'the profile''s block that shows the banner after an SSH login'
    }
}

function Get-UsaBannerWindowsSshText {
    # In:  the configuration
    # Out: the SSH banner's text, as sshd-banner.txt holds it: plain ASCII,
    #      LF line ends, a blank line after the box. The host's name is the
    #      one Windows gives (no address: preLogon shows none on Windows)
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $names = @{ HostName = [System.Environment]::MachineName; Ip = '' }
    (@(Get-UsaBannerPreLogon -Config $Config -Os windows -Facts $names) -join "`n") + "`n`n"
}

function Set-UsaBannerWindowsSsh {
    <#
    .SYNOPSIS
    The SSH banner: its file, and sshd_config's Banner line.
    .DESCRIPTION
    In:  the layout, the configuration, and the record.
    Out: a line for each change, or one saying why there is no SSH banner.
    sshd_config is copied beside itself first and checked with sshd -t
    after: one sshd refuses is put back, with a warning. sshd is not
    restarted, so the admin's own SSH session is safe: the line says to
    restart it. A default shell that is not a PowerShell shows no banner
    after login, and a warning says so; deploy-usawinssh sets it (D21).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][hashtable]$Layout,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Record
    )
    $sshd = Get-UsaBannerWindowsSshd
    if (-not $sshd) {
        'no SSH banner, and no banner after login: OpenSSH''s server is not installed here (deploy-usawinssh installs it); run Deploy-UsaBanner again once it is'
        return
    }
    $leaf = Get-UsaBannerSshShellName
    if ($leaf -notin 'pwsh.exe', 'powershell.exe') {
        Write-Warning "UsaBanner: sshd starts $leaf at a login, so no banner shows after an SSH login. The banner lives in PowerShell's profile: set the default shell to pwsh.exe (deploy-usawinssh does)."
    }
    $text = Get-UsaBannerWindowsSshText -Config $Config
    Set-UsaBannerHostFile -Root '' -Path ([System.IO.Path]::Combine($Layout.Data, 'sshd-banner.txt')) -Bytes ([System.Text.Encoding]::ASCII.GetBytes($text)) -Mode $null -What 'the SSH banner'
    if (-not [System.IO.File]::Exists($Layout.SshdConfig)) {
        Write-Warning "UsaBanner: there is no $($Layout.SshdConfig) yet: sshd writes it at its first start. Start sshd, then run Deploy-UsaBanner again for the SSH banner."
        return
    }
    $file = Read-UsaBannerWindowsText -Path $Layout.SshdConfig
    $eol = if ($file.Text -match "`r`n") { "`r`n" } else { "`n" }
    $result = Set-UsaBannerSshdBannerLine -Lines @($file.Text -split "\r?\n")
    foreach ($line in $result.Scoped) { Write-Warning "UsaBanner: sshd_config has a Banner inside a Match block, which sessions it matches see instead: $line. It is left as it is." }
    if (-not $result.Changed) { return }
    if (-not $PSCmdlet.ShouldProcess($Layout.SshdConfig, "Put the banner's Banner line before the first Match block, turning off any other Banner above it")) { return }
    $backup = "$($Layout.SshdConfig).usabanner-bak"
    [System.IO.File]::Copy($Layout.SshdConfig, $backup, $true)
    [System.IO.File]::WriteAllBytes($Layout.SshdConfig, (ConvertTo-UsaBannerWindowsBytes -Text ($result.Lines -join $eol) -Encoding $file.Encoding))
    $test = Invoke-UsaBannerNative -FilePath $sshd -ArgumentList '-t'
    if ($test.ExitCode -ne 0) {
        [System.IO.File]::Copy($backup, $Layout.SshdConfig, $true)
        Write-Warning "UsaBanner: sshd -t refused sshd_config with the Banner line, so it is put back as it was, and there is no SSH banner: $(@($test.Output) -join ' ')"
        return
    }
    $Record['sshd'] = $true
    "wrote $($Layout.SshdConfig): its Banner line. Restart sshd (Restart-Service sshd) for it to show, then try a new session before closing this one"
}

function Set-UsaBannerWindowsNotice {
    <#
    .SYNOPSIS
    The logon notice: the legal text before a console or RDP sign-in (D5).
    .DESCRIPTION
    In:  the configuration, and the record.
    Out: a line for each change, or one saying the notice is someone
         else's. The banner sets it only where none is set, or where the one
         set is the banner's own, by the record: a notice someone else set,
         by hand or by a Group Policy, stays. A Group Policy would set its
         own again at its next refresh anyway. The record keeps what was
         there before, for removal.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Record
    )
    $want = Get-UsaBannerLogonNotice -Config $Config
    $have = Read-UsaBannerLogonNoticeValue
    $ours = $Record['notice']
    $isOurs = $ours -and $have.Caption -ceq [string]$ours['caption'] -and $have.Text -ceq [string]$ours['text']
    if (-not $isOurs -and ($have.Caption -or $have.Text)) {
        'left the logon notice as it is: it holds someone else''s text, set by hand or by a Group Policy'
        return
    }
    if ($have.Caption -ceq $want.Caption -and $have.Text -ceq $want.Text) { return }
    if (-not $PSCmdlet.ShouldProcess('the logon notice (LegalNoticeCaption, LegalNoticeText)', "Set it to the legal text: $($want.Caption)")) { return }
    $before = if ($ours) { $ours['before'] } else { [ordered]@{ caption = $have.Caption; text = $have.Text; exists = $have.Exists } }
    Write-UsaBannerLogonNoticeValue -Caption $want.Caption -Text $want.Text
    $Record['notice'] = [ordered]@{ caption = $want.Caption; text = $want.Text; before = $before }
    "set the logon notice: $($want.Caption), before a console or RDP sign-in"
}

function Set-UsaBannerWindowsTask {
    # In:  the banner's folder, and the configuration
    # Out: a line for each change: the sample task registered where it is
    #      missing or runs something else, and a first sample on a host with
    #      none yet; the update task the same way where the configuration
    #      turns the update channel on, and unregistered where it is off,
    #      the notice it left deleted with it: no task is left to take it
    #      away, and the banner after login would show it for good
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Data, [Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $pwsh = Find-UsaBannerPwsh
    if (-not $pwsh) { $pwsh = (Get-Process -Id $PID).Path }
    $spec = New-UsaBannerSampleTaskSpec -Pwsh $pwsh
    $have = Get-UsaBannerTask -Name $spec.Name
    if ((-not $have -or $have.Execute -ne $spec.Execute -or $have.Arguments -ne $spec.Arguments) -and
        $PSCmdlet.ShouldProcess("$($spec.Path)$($spec.Name)", 'Register the periodic job: as SYSTEM, every 15 minutes')) {
        Register-UsaBannerTask -Spec $spec
        "registered the task $($spec.Path)$($spec.Name): a sample every 15 minutes, as SYSTEM"
    }
    if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($Data, 'samples.tsv')) -and
        $PSCmdlet.ShouldProcess("$($spec.Path)$($spec.Name)", 'Take a first sample now, in the background')) {
        Start-UsaBannerTask -Name $spec.Name
        'started a first sample: the 24-hour range and the slow facts begin now'
    }

    $update = New-UsaBannerUpdateTaskSpec -Pwsh $pwsh
    $have = Get-UsaBannerTask -Name $update.Name
    $mode = [string]$Config['update']['mode']
    if ($mode -eq 'off') {
        if ($have -and $PSCmdlet.ShouldProcess("$($update.Path)$($update.Name)", 'Unregister the update job: the update channel is off')) {
            Unregister-UsaBannerTask -Name $update.Name
            "unregistered the task $($update.Path)$($update.Name): the update channel is off"
        }
        Remove-UsaBannerHostFile -Path ([System.IO.Path]::Combine($Data, 'notice')) -What "the update job's notice"
        return
    }
    if ((-not $have -or $have.Execute -ne $update.Execute -or $have.Arguments -ne $update.Arguments) -and
        $PSCmdlet.ShouldProcess("$($update.Path)$($update.Name)", "Register the update job ($mode): as SYSTEM, once a day")) {
        Register-UsaBannerTask -Spec $update
        "registered the task $($update.Path)$($update.Name): the update channel ($mode), once a day, as SYSTEM"
    }
}

function Invoke-UsaBannerWindowsDeploy {
    <#
    .SYNOPSIS
    Deploys a configuration to this Windows host: Deploy-UsaBanner's work.
    .DESCRIPTION
    In:  the configuration (New-UsaBannerDeployConfig), and -ReplaceOld to
         take the old banner off first.
    Out: a line for each change, in the order made; nothing when the host
         already has it all. Under -WhatIf, PowerShell says each change
         instead, and nothing changes.
    Every banner is drawn before anything changes, so a configuration or
    art that fails leaves the host as it was. Then the old banner comes off,
    where -ReplaceOld says so (OldBanner.ps1). Then the module; the banner's
    own folder and its ACL, before anything is written in it; the
    configuration; the profiles; SSH; the logon notice; the periodic job.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config, [switch]$ReplaceOld)
    $layout = Get-UsaBannerWindowsLayout
    Assert-UsaBannerWindowsHost -Layout $layout -Command 'Deploy-UsaBanner' -RefuseOldInstall:(-not $ReplaceOld)
    $recordPath = [System.IO.Path]::Combine($layout.Data, 'deploy.json')
    $record = Read-UsaBannerDeployRecord -Path $recordPath
    $created = [System.Collections.Generic.List[string]]::new()
    foreach ($folder in @($record['created'])) { if ($folder) { $created.Add([string]$folder) } }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $json = $utf8.GetBytes((ConvertTo-UsaBannerConfigJson -Config $Config))
    $data = [System.Text.Encoding]::ASCII.GetBytes((ConvertTo-UsaBannerDataFile -Config $Config))
    $null = Get-UsaBannerLogonNotice -Config $Config
    $null = @(Get-UsaBannerPreLogon -Config $Config -Os windows -Facts @{ HostName = [System.Environment]::MachineName; Ip = '' })
    $null = @(Get-UsaBannerPostLogon -Config $Config -Os windows -Facts @{ Name = [System.Environment]::MachineName } -Mode none)
    $jsonPath = [System.IO.Path]::Combine($layout.Data, 'usabanner.json')
    $settings = ''
    if ([System.IO.File]::Exists($jsonPath)) {
        $old = $null
        try { $old = Read-UsaBannerConfig -Path $jsonPath } catch { $settings = 'the old one could not be read, and is replaced whole' }
        if ($null -ne $old) { $settings = @(Compare-UsaBannerConfig -Old $old -New $Config) -join '; ' }
    }

    if ($ReplaceOld) { Remove-UsaBannerWindowsOldInstall -Layout $layout }
    Install-UsaBannerModuleCopy -Root '' -Record $record -Created $created -Modules $layout.Modules -FileMode $null -FolderMode $null -Os windows
    Set-UsaBannerDataFolder -Path $layout.Data -Created $created
    Set-UsaBannerHostFile -Root '' -Path $jsonPath -Bytes $json -Mode $null -What 'the configuration' -Detail $settings
    $dataFile = [System.IO.Path]::Combine($layout.Data, 'usabanner.psd1')
    Set-UsaBannerHostFile -Root '' -Path $dataFile -Bytes $data -Mode $null -What 'the configuration as data, which each login reads'
    Set-UsaBannerWindowsProfiles -Profiles $layout.Profiles -DataFile $dataFile
    Save-UsaBannerWindowsRecord -Path $recordPath -Record $record -Created $created
    Set-UsaBannerWindowsSsh -Layout $layout -Config $Config -Record $record
    Set-UsaBannerWindowsNotice -Config $Config -Record $record
    Save-UsaBannerWindowsRecord -Path $recordPath -Record $record -Created $created
    Set-UsaBannerWindowsTask -Data $layout.Data -Config $Config
}

function Save-UsaBannerWindowsRecord {
    # In:  the record's path, the record, and the folders made so far
    # Out: nothing; the file holds the record. Under -WhatIf nothing changed,
    #      so there is nothing to record
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$Path, [System.Collections.IDictionary]$Record, [System.Collections.Generic.List[string]]$Created)
    if ($WhatIfPreference -or -not [System.IO.Directory]::Exists([System.IO.Path]::GetDirectoryName($Path))) { return }
    $Record['created'] = @($Created)
    $json = ((ConvertTo-Json -InputObject $Record -Depth 5) -replace "`r`n", "`n") + "`n"
    $null = Set-UsaBannerHostFile -Root '' -Path $Path -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($json)) -Mode $null -What 'the record of what the deploy changed'
}

function Invoke-UsaBannerWindowsRemove {
    <#
    .SYNOPSIS
    Takes the banner off this Windows host: Remove-UsaBanner's work.
    .DESCRIPTION
    Out: a line for each change, in the order made; nothing when there is
         no banner here. Under -WhatIf, PowerShell says each change
         instead, and nothing changes.
    The periodic job goes first, then the profiles' blocks, sshd_config's
    Banner line (with any Banner it turned off back on, checked with
    sshd -t), the logon notice where it still holds the banner's text, the
    banner's own folder, the module's copy, and the folders the deploy
    made, once empty. Only what the record says the deploy changed is
    changed back.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()
    $layout = Get-UsaBannerWindowsLayout
    Assert-UsaBannerWindowsHost -Layout $layout -Command 'Remove-UsaBanner'
    $record = Read-UsaBannerDeployRecord -Path ([System.IO.Path]::Combine($layout.Data, 'deploy.json'))

    foreach ($name in $script:UsaTaskName, $script:UsaUpdateTaskName) {
        if ((Get-UsaBannerTask -Name $name) -and $PSCmdlet.ShouldProcess("$script:UsaTaskPath$name", 'Unregister the task')) {
            # Unregistered, a run in progress goes on, and writes the banner's
            # folder again after it is gone (lab, 2026-10-23): stopped first.
            Stop-UsaBannerTask -Name $name
            Unregister-UsaBannerTask -Name $name
            "unregistered the task $script:UsaTaskPath$name"
        }
    }
    foreach ($path in $layout.Profiles) {
        if (-not [System.IO.File]::Exists($path)) { continue }
        $file = Read-UsaBannerWindowsText -Path $path
        $text = Remove-UsaBannerProfileText -Text $file.Text
        if ($text -ceq $file.Text) { continue }
        if ($PSCmdlet.ShouldProcess($path, 'Take out the banner''s block')) {
            if ($text) { [System.IO.File]::WriteAllBytes($path, (ConvertTo-UsaBannerWindowsBytes -Text $text -Encoding $file.Encoding)) }
            else { [System.IO.File]::Delete($path) }
            "took the banner's block out of $path"
        }
    }
    $sshd = Get-UsaBannerWindowsSshd
    if ([System.IO.File]::Exists($layout.SshdConfig)) {
        $file = Read-UsaBannerWindowsText -Path $layout.SshdConfig
        $eol = if ($file.Text -match "`r`n") { "`r`n" } else { "`n" }
        $result = Remove-UsaBannerSshdBannerLine -Lines @($file.Text -split "\r?\n")
        if ($result.Changed -and $PSCmdlet.ShouldProcess($layout.SshdConfig, 'Take out the banner''s Banner line, and turn back on any Banner it turned off')) {
            $backup = "$($layout.SshdConfig).usabanner-bak"
            [System.IO.File]::Copy($layout.SshdConfig, $backup, $true)
            [System.IO.File]::WriteAllBytes($layout.SshdConfig, (ConvertTo-UsaBannerWindowsBytes -Text ($result.Lines -join $eol) -Encoding $file.Encoding))
            $test = if ($sshd) { Invoke-UsaBannerNative -FilePath $sshd -ArgumentList '-t' } else { @{ ExitCode = 0; Output = @() } }
            if ($test.ExitCode -ne 0) {
                [System.IO.File]::Copy($backup, $layout.SshdConfig, $true)
                Write-Warning "UsaBanner: sshd -t refused sshd_config without the Banner line, so it is put back: $(@($test.Output) -join ' ')"
            }
            else {
                [System.IO.File]::Delete($backup)
                "took the Banner line out of $($layout.SshdConfig). Restart sshd (Restart-Service sshd) for it to go"
            }
        }
    }
    $ours = $record['notice']
    if ($ours) {
        $have = Read-UsaBannerLogonNoticeValue
        if ($have.Caption -ceq [string]$ours['caption'] -and $have.Text -ceq [string]$ours['text'] -and
            $PSCmdlet.ShouldProcess('the logon notice (LegalNoticeCaption, LegalNoticeText)', 'Put back what it held before the deploy')) {
            $before = $ours['before']
            if ($before -and $before['exists']) { Write-UsaBannerLogonNoticeValue -Caption ([string]$before['caption']) -Text ([string]$before['text']) }
            else { Write-UsaBannerLogonNoticeValue -Remove }
            'put back the logon notice as it was before the deploy'
        }
    }
    Remove-UsaBannerWindowsFolder -Path $layout.Data -Allowed $layout.Data -What 'the configuration, the SSH banner, the samples and the record'
    if ($record['module']) {
        Remove-UsaBannerWindowsFolder -Path ([string]$record['module']) -Allowed ([string]$record['module']) -What 'the module''s copy for every user'
    }
    $made = @($record['created'])
    [array]::Reverse($made)
    foreach ($folder in $made) {
        if (-not $folder -or -not [System.IO.Directory]::Exists($folder) -or @([System.IO.Directory]::GetFileSystemEntries($folder)).Count -gt 0) { continue }
        if ($PSCmdlet.ShouldProcess([string]$folder, 'Delete the empty folder the deploy made')) {
            [System.IO.Directory]::Delete($folder)
            "deleted the empty folder ${folder}: the deploy made it"
        }
    }
}

function Remove-UsaBannerWindowsFolder {
    # In:  a folder, the one folder the caller may delete, and what it is
    # Out: a line when it was deleted with everything in it
    # Why: only the banner's own folders, and the old banner's, go whole;
    #      any other is refused
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Allowed, [Parameter(Mandatory)][string]$What)
    $layout = Get-UsaBannerWindowsLayout
    # Windows takes either separator, and a deploy before 0.1.1 recorded the
    # module's copy with both (C:\Program Files\...\Modules/UsaBanner/0.1.0):
    # compare with one.
    $modules = [System.IO.Path]::Combine($layout.Modules, 'UsaBanner').Replace('\', '/') + '/'
    $ours = $Path -eq $layout.Data -or $Path -eq $layout.OldData -or $Path.Replace('\', '/').StartsWith($modules)
    if ($Path -ne $Allowed -or -not $ours) { throw "UsaBanner: $Path is not one of the banner's own folders, so it is not deleted." }
    if (-not [System.IO.Directory]::Exists($Path)) { return }
    $count = @([System.IO.Directory]::GetFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)).Count
    if (-not $PSCmdlet.ShouldProcess($Path, "Delete the folder and the $count file(s) in it: $What")) { return }
    [System.IO.Directory]::Delete($Path, $true)
    "deleted $Path and the $count file(s) in it: $What"
}
