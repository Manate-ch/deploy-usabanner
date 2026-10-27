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
#   | OpenSSH's DefaultShell                 | a PowerShell, where it is not |
#   |                                        | one: the banner after login   |
#   |                                        | lives in its profile (D21)    |
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
# OpenSSH and PowerShell 7 belong to deploy-usawinssh (D21): a deploy checks
# them and says what is missing, and installs neither.
#
# Read-UsaBannerLogonNoticeValue and New-UsaBannerProfileBlock, which
# PowerShell logs whole at each import, are in WindowsDeploy.Logged.ps1
# (docs/DECISIONS.md, D30).

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

function Write-UsaBannerSshDefaultShell {
    # In:  the program sshd is to start at a login, or -Remove to take the
    #      value away, which leaves sshd starting cmd.exe
    # Out: nothing; the registry holds it
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Path = '', [switch]$Remove)
    $key = 'HKLM:\SOFTWARE\OpenSSH'
    if ($Remove) {
        Remove-ItemProperty -LiteralPath $key -Name 'DefaultShell' -ErrorAction SilentlyContinue
        return
    }
    if (-not (Test-Path -LiteralPath $key)) { $null = New-Item -Path $key -Force }
    $null = New-ItemProperty -LiteralPath $key -Name 'DefaultShell' -Value $Path -PropertyType String -Force
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

# The rights that let whoever holds them swap a folder, or what it holds, or
# give themselves the right to: DELETE, FILE_DELETE_CHILD, WRITE_DAC,
# WRITE_OWNER and GENERIC_ALL. Only these accounts may hold them on the
# banner's folders: SYSTEM, Administrators and TrustedInstaller.
$script:UsaSwapRights = 0x10000 -bor 0x40 -bor 0x40000 -bor 0x80000 -bor 0x10000000
$script:UsaTrustedSids = @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')

function Get-UsaBannerFolderSecurity {
    <#
    .SYNOPSIS
    A folder's owner and the entries of its ACL, as plain values.
    .DESCRIPTION
    In:  a folder.
    Out: @{ Owner; OwnerName; Rules }: the owner's SID and its account's
         name; a rule per entry, @{ Sid; Name; Allow; Rights; InheritOnly },
         Rights the number Windows keeps. A SID with no account is its own
         name. The tests mock this.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$Path)
    $acl = Get-Acl -LiteralPath $Path
    $nameOf = {
        # In:  a SID
        # Out: its account's name, or the SID when no account has it
        param([System.Security.Principal.SecurityIdentifier]$Sid)
        try { $Sid.Translate([System.Security.Principal.NTAccount]).Value } catch { $Sid.Value }
    }
    $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    $rules = foreach ($rule in $acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
        @{
            Sid         = $rule.IdentityReference.Value
            Name        = & $nameOf $rule.IdentityReference
            Allow       = $rule.AccessControlType -eq 'Allow'
            Rights      = [int]$rule.FileSystemRights
            InheritOnly = [bool]($rule.PropagationFlags -band [System.Security.AccessControl.PropagationFlags]::InheritOnly)
        }
    }
    @{ Owner = $owner.Value; OwnerName = & $nameOf $owner; Rules = @($rules) }
}

function Test-UsaBannerFolderRisk {
    <#
    .SYNOPSIS
    Why someone other than Administrators and SYSTEM could swap a folder, or
    what it holds; nothing when no one could.
    .DESCRIPTION
    In:  what Get-UsaBannerFolderSecurity says of the folder.
    Out: a reason each: an owner other than SYSTEM, Administrators or
         TrustedInstaller, who may change the ACL whatever it says; an entry
         that allows anyone else to delete or rename the folder or what is
         in it, or to change its ACL or owner. An inherit-only entry, as
         CREATOR OWNER's in ProgramData, grants nothing on the folder
         itself; a deny entry is not counted on.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$Security)
    if ($Security.Owner -notin $script:UsaTrustedSids) { "it is owned by $($Security.OwnerName)" }
    foreach ($rule in @($Security.Rules)) {
        if (-not $rule.Allow -or $rule.InheritOnly -or $rule.Sid -in $script:UsaTrustedSids) { continue }
        if ($rule.Rights -band $script:UsaSwapRights) { "$($rule.Name) may delete or rename what is in it, or change who may" }
    }
}

function Find-UsaBannerFolderLink {
    <#
    .SYNOPSIS
    The links in and under a folder: junctions, symbolic links and any other
    reparse point.
    .DESCRIPTION
    In:  a folder.
    Out: the folder's own path when it is a link; else each link under it.
         A link is not entered.
    Why: icacls /T goes through a junction, so it would set the owner and
         the ACL of whatever the link points at.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path)
    $isLink = { param([System.IO.FileSystemInfo]$Item) [bool]($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }
    $root = [System.IO.DirectoryInfo]::new($Path)
    if (& $isLink $root) { return $root.FullName }
    $todo = [System.Collections.Generic.Stack[System.IO.DirectoryInfo]]::new()
    $todo.Push($root)
    while ($todo.Count) {
        foreach ($item in $todo.Pop().EnumerateFileSystemInfos()) {
            if (& $isLink $item) { $item.FullName }
            elseif ($item -is [System.IO.DirectoryInfo]) { $todo.Push($item) }
        }
    }
}

function Get-UsaBannerFolderDanger {
    <#
    .SYNOPSIS
    Why someone other than Administrators and SYSTEM could put a link where
    the deploy and the periodic job write as SYSTEM; nothing when no one
    could.
    .DESCRIPTION
    In:  a folder that exists; -Tree to look for links under it too.
    Out: a reason each: the folder is a link; Test-UsaBannerFolderRisk's
         reasons; with -Tree, each link under it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Path, [switch]$Tree)
    if ([System.IO.DirectoryInfo]::new($Path).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        return 'it is a link (a junction or a symbolic link)'
    }
    Test-UsaBannerFolderRisk -Security (Get-UsaBannerFolderSecurity -Path $Path)
    if ($Tree) {
        foreach ($link in @(Find-UsaBannerFolderLink -Path $Path)) { "it holds a link, which icacls /T would go through: $link" }
    }
}

function Assert-UsaBannerDataFolderSafe {
    <#
    .SYNOPSIS
    Refuses the banner's own folder, and the folder it is in, when someone
    other than Administrators and SYSTEM could have swapped either, or could.
    .DESCRIPTION
    In:  the banner's own folder (ProgramData\UsagiTools\Banner), and the
         folders the deploy made.
    Out: nothing; throws, saying what to do, when Get-UsaBannerFolderDanger
         finds a reason: in the folder it is in (UsagiTools); in the
         banner's own folder and under it. Under the folder it is in too,
         when the deploy made that folder: its ACL is set next.
    Why: the deploy and the periodic job write in the banner's folder as
         SYSTEM, and icacls /T sets its ACL. Whoever made UsagiTools before
         the first deploy owns it, and could swap the banner's folder for a
         link to anywhere, after the deploy as well as before it.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [AllowNull()][System.Collections.Generic.List[string]]$Created)
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    $ours = $null -ne $Created -and $Created.Contains($parent)
    $places = @(
        @{ Path = $parent; What = 'the folder the banner''s own folder is in'; Tree = $ours }
        @{ Path = $Path; What = 'the banner''s own folder'; Tree = $true }
    )
    foreach ($place in $places) {
        if (-not [System.IO.Directory]::Exists($place.Path)) { continue }
        $danger = @(Get-UsaBannerFolderDanger -Path $place.Path -Tree:$place.Tree)
        if ($danger.Count) {
            throw "UsaBanner: $($place.Path), $($place.What), is not safe for a folder SYSTEM writes in: $($danger -join '; '). Whoever could change it could have the deploy and the periodic job write wherever a link points, so nothing is changed. See who made it and what it holds, delete it, then deploy again."
        }
    }
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
         Update-UsaBannerSample in the module: a sample, the AD Description
         and the slow facts.
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
    Out: @{ Data; Modules; Profiles; SshdConfig; Old; OldData; OldSshText;
         TaskFolder }: the banner's own folder; the modules folder for all
         users; the all-users profile of each PowerShell installed (Windows
         PowerShell's always, PowerShell 7's where its folder is);
         sshd_config; what the old banner
         (windows/Install-ManatechBanner.ps1) leaves, to look for: its
         folder and its SSH banner file; and the folder where the task
         scheduler keeps the definition of each task in its root folder, a
         file named as the task.
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
        TaskFolder = [System.IO.Path]::Combine($paths.Windir, 'System32', 'Tasks')
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
    #      (windows/Install-ManatechBanner.ps1) on the host, each profile
    #      that holds its block, and each of its two tasks, as "the task
    #      \<name>"
    # Why: on a production host the old banner's GPO task put the banner
    #      back at its midnight run, half an hour after this found none of
    #      it (2026-10-27); the task stays when the GPO stops applying. A
    #      task is found by its definition file, not by Get-ScheduledTask,
    #      whose module PowerShell logs at each import (D30). Only an
    #      administrator may read the task scheduler's folder: for anyone
    #      else no task is found
    param([Parameter(Mandatory)][hashtable]$Layout)
    $Layout.Old | Where-Object { [System.IO.File]::Exists($_) -or [System.IO.Directory]::Exists($_) }
    $Layout.Profiles | Where-Object { [System.IO.File]::Exists($_) -and (Read-UsaBannerWindowsText -Path $_).Text.Contains('# >>> Manatech banner') }
    foreach ($name in $script:UsaOldTasks) {
        if ([System.IO.File]::Exists([System.IO.Path]::Combine($Layout.TaskFolder, $name))) { "the task \$name" }
    }
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
         and execute; whatever is in it already inherits that ACL. The
         folder it is in (UsagiTools) gets the same ACL, on itself alone,
         when the deploy made it; one the deploy did not make is left as it
         is. Assert-UsaBannerDataFolderSafe refuses either folder first when
         someone else could swap it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][System.Collections.Generic.List[string]]$Created
    )
    Assert-UsaBannerDataFolderSafe -Path $Path -Created $Created
    if (-not [System.IO.Directory]::Exists($Path)) {
        if (-not $PSCmdlet.ShouldProcess($Path, 'Make the banner''s own folder')) { return }
        New-UsaBannerHostFolder -Root '' -Path $Path -Created $Created -Mode $null
        "made ${Path}: the banner's own folder"
    }
    # With its ACL, ProgramData lets any user make a folder in UsagiTools, so a
    # name the banner takes later could be taken first.
    $parent = [System.IO.Path]::GetDirectoryName($Path)
    if ($null -ne $Created -and $Created.Contains($parent) -and -not (Test-UsaBannerFolderAcl -Path $parent) -and
        $PSCmdlet.ShouldProcess($parent, 'Set its owner to Administrators, and its ACL: Administrators and SYSTEM full control, Users read and execute, nothing inherited (the folder alone)')) {
        $owner = Invoke-UsaBannerNative -FilePath 'icacls.exe' -ArgumentList $parent, '/setowner', '*S-1-5-32-544', '/Q'
        $grant = Invoke-UsaBannerNative -FilePath 'icacls.exe' -ArgumentList $parent, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-32-545:(OI)(CI)RX', '/Q'
        if ($owner.ExitCode -ne 0 -or $grant.ExitCode -ne 0) {
            throw "UsaBanner: icacls could not set the ACL of ${parent}, so nothing more is changed: $(@($owner.Output) + @($grant.Output) -join ' ')"
        }
        "set the ACL of ${parent}: Administrators and SYSTEM may change it, Users read it"
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

function Set-UsaBannerWindowsShell {
    <#
    .SYNOPSIS
    OpenSSH's default shell: a PowerShell, so the banner shows after an SSH
    login (D21).
    .DESCRIPTION
    In:  the record.
    Out: a line when it changed. The banner after login lives in a
         PowerShell profile, and cmd.exe, which sshd starts where no
         DefaultShell is set, runs none: where the default shell is not a
         PowerShell, it is set to pwsh, or to Windows PowerShell where
         PowerShell 7 is missing. A PowerShell already set is kept. The
         record keeps what was there before the banner first set it, for
         removal.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Record)
    $leaf = Get-UsaBannerSshShellName
    if ($leaf -in 'pwsh.exe', 'powershell.exe') { return }
    $shell = Find-UsaBannerPwsh
    if (-not $shell) { $shell = [System.IO.Path]::Combine((Get-UsaBannerWindowsPaths).Windir, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe') }
    if (-not $PSCmdlet.ShouldProcess('OpenSSH''s default shell (DefaultShell under HKLM:\SOFTWARE\OpenSSH)', "Set it to ${shell}: sshd starts $leaf at a login, which shows no banner")) { return }
    $ours = $Record['shell']
    $before = if ($ours) { [string]$ours['before'] } else { Get-UsaBannerSshDefaultShell }
    Write-UsaBannerSshDefaultShell -Path $shell
    $Record['shell'] = [ordered]@{ path = $shell; before = $before }
    "set OpenSSH's default shell to ${shell}: sshd started $leaf at a login, whose banner after login never showed"
}

function Set-UsaBannerWindowsSsh {
    <#
    .SYNOPSIS
    The SSH banner: its file, and sshd_config's Banner line.
    .DESCRIPTION
    In:  the layout, the configuration, and the record.
    Out: a line for each change, or one saying why there is no SSH banner.
    sshd_config is copied beside itself first and checked with sshd -t
    after: one sshd refuses is put back from the copy, with a warning, and
    the copy is deleted once sshd -t passes. sshd is not restarted, so the
    admin's own SSH session is safe: the line says to restart it. A default
    shell that is not a PowerShell shows no banner after login, so it is set
    to one first (Set-UsaBannerWindowsShell, D21).
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
    Set-UsaBannerWindowsShell -Record $Record
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
    [System.IO.File]::Delete($backup)
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
        'left the logon notice, the text before a console or RDP sign-in, as it is: it holds someone else''s text, set by hand or by a Group Policy'
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
    configuration; the profiles; SSH (the default shell, then the Banner
    line); the logon notice; the periodic job.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config, [switch]$ReplaceOld)
    $layout = Get-UsaBannerWindowsLayout
    Assert-UsaBannerWindowsHost -Layout $layout -Command 'Deploy-UsaBanner' -RefuseOldInstall:(-not $ReplaceOld)
    # Before anything changes, and before the record in the folder is read.
    Assert-UsaBannerDataFolderSafe -Path $layout.Data
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
    default shell where it is still the one the deploy set, the banner's own
    folder, the module's copy, and the folders the deploy made, once empty.
    Only what the record says the deploy changed is changed back.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()
    $layout = Get-UsaBannerWindowsLayout
    Assert-UsaBannerWindowsHost -Layout $layout -Command 'Remove-UsaBanner'
    # The record says which folders to delete: one read through a link could name any.
    Assert-UsaBannerDataFolderSafe -Path $layout.Data
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
    $shell = $record['shell']
    if ($shell -and (Get-UsaBannerSshDefaultShell) -eq [string]$shell['path'] -and
        $PSCmdlet.ShouldProcess('OpenSSH''s default shell (DefaultShell under HKLM:\SOFTWARE\OpenSSH)', 'Put back what it was before the deploy')) {
        $before = [string]$shell['before']
        if ($before) { Write-UsaBannerSshDefaultShell -Path $before }
        else { Write-UsaBannerSshDefaultShell -Remove }
        "put back OpenSSH's default shell as it was before the deploy: $(if ($before) { $before } else { 'none set, so sshd starts cmd.exe' })"
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

function Grant-UsaBannerTreeAccess {
    # In:  a folder about to be deleted, on Windows
    # Out: nothing; Administrators own it and everything in it, and have
    #      full control of each, by SID
    # Why: Install-ManatechBanner.ps1 -UpdateTask's icacls /T leaves each
    #      file already in its clone with no access for anyone (lab,
    #      2026-10-23), and on a host the old banner had been on for long, an
    #      elevated administrator could neither clear a git pack file's
    #      read-only attribute nor delete it (2026-10-26). takeown makes
    #      Administrators the owner, which icacls /setowner does not force;
    #      the owner may then grant. /D Y answers takeown's question about a
    #      folder it may not list, where it would otherwise wait for one: a
    #      Windows whose language takes another letter refuses the Y, and the
    #      delete after this says what is left
    param([Parameter(Mandatory)][string]$Path)
    $null = Invoke-UsaBannerNative -FilePath 'takeown.exe' -ArgumentList '/F', $Path, '/R', '/A', '/D', 'Y'
    $null = Invoke-UsaBannerNative -FilePath 'icacls.exe' -ArgumentList $Path, '/grant:r', '*S-1-5-32-544:F', '/T', '/C', '/Q'
}

function Remove-UsaBannerWindowsFolder {
    # In:  a folder, the one folder the caller may delete, and what it is
    # Out: a line when it was deleted with everything in it; a warning
    #      instead when Windows refused, even after Administrators took the
    #      folder over
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
    $refusal = Remove-UsaBannerTree -Path $Path -Windows
    if ($refusal) {
        Write-Warning "UsaBanner: could not delete ${Path}, ${What}: $refusal"
        return
    }
    "deleted $Path and the $count file(s) in it: $What"
}
