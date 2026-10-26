# LinuxDeploy.ps1 - Deploy-UsaBanner and Remove-UsaBanner on Ubuntu
# (docs/DECISIONS.md, D16, D17 and D23). What a deploy puts on a host:
#
#   +------------------------------------------+----------------------------+
#   | Path                                     | What                       |
#   +------------------------------------------+----------------------------+
#   | /etc/usabanner/usabanner.json            | the configuration (D12)    |
#   | /etc/usabanner/issue.net                 | the SSH banner, sent       |
#   |                                          | before authentication      |
#   | /etc/issue.d/50-usabanner.issue          | the console's banner,      |
#   |                                          | which agetty prints        |
#   | /etc/ssh/sshd_config.d/00-usabanner.conf | sshd's Banner line, where  |
#   |                                          | sshd is installed          |
#   | /etc/update-motd.d/05-usabanner          | the banner after login,    |
#   |                                          | which pam_motd runs        |
#   | /usr/local/share/usabanner/              | the login renderer and the |
#   |                                          | periodic job (linux/)      |
#   | /var/lib/usabanner/                      | the frame, the services,   |
#   |                                          | what was drawn, the record |
#   |                                          | of the deploy, and the     |
#   |                                          | periodic job's files: the  |
#   |                                          | samples, the slow facts    |
#   |                                          | and the AD Description     |
#   | /etc/systemd/system/usabanner-sample.*   | the periodic job, every 15 |
#   |                                          | minutes (D17)              |
#   | /etc/systemd/system/usabanner-update.*   | the update job, once a     |
#   |                                          | day, where the update      |
#   |                                          | channel is on (D14)        |
#   | /usr/local/share/powershell/Modules/     | the module, for every user |
#   |   UsaBanner/<version>/                   | and the periodic job       |
#   +------------------------------------------+----------------------------+
#
# Ubuntu's own banner files are conffiles and stay as they are, so apt never
# asks about them (D16). The stock MOTD scripts the banner replaces are
# turned off, never deleted. /var/lib/usabanner/deploy.json records each
# change made outside the banner's own files, and Remove-UsaBanner undoes
# exactly those.
#
# Get-UsaBannerSha256, which PowerShell logs whole at each import, is in
# LinuxDeploy.Logged.ps1 (docs/DECISIONS.md, D30).

$script:UsaLinuxEtc = '/etc/usabanner'
$script:UsaLinuxShare = '/usr/local/share/usabanner'
$script:UsaLinuxState = '/var/lib/usabanner'
$script:UsaLinuxModules = '/usr/local/share/powershell/Modules'
$script:UsaLinuxScripts = @('ad-description.sh', 'facts.sh', 'postlogin.awk', 'postlogin.sh', 'redraw.sh', 'sample.sh', 'update.sh')
$script:UsaLinuxMotd = '/etc/update-motd.d/05-usabanner'
$script:UsaLinuxIssue = '/etc/issue.d/50-usabanner.issue'
$script:UsaLinuxDropIn = '/etc/ssh/sshd_config.d/00-usabanner.conf'
$script:UsaLinuxSshd = '/usr/sbin/sshd'

# The stock MOTD scripts the banner replaces (D16): Ubuntu's header and help
# text, the news, and the notices of updates and of a reboot, which the
# banner's own rows carry. 50-landscape-sysinfo is a link to another
# package's file, and goes by a statoverride.
$script:UsaRetiredScripts = @('00-header', '10-help-text', '50-motd-news', '90-updates-available', '98-reboot-required')

# What the old banner (this repository's install.sh) puts on a host: a deploy
# does not go beside it, and -ReplaceOldBanner takes it off first (D23,
# OldBanner.ps1).
$script:UsaOldInstall = @(
    '/etc/update-motd.d/05-manatech-banner'
    '/etc/update-motd.d/15-manatech-health'
    '/etc/manatech'
    '/usr/local/share/manatech'
    '/var/lib/manatech'
    '/etc/issue.d/50-manatech.issue'
    '/etc/ssh/sshd_config.d/00-manatech-banner.conf'
    '/etc/ssh/sshd_config.d/10-manatech-banner.conf'
    '/etc/systemd/system/manatech-motd-update.timer'
    '/etc/systemd/system/manatech-motd-publish.path'
)

$script:UsaMode644 = [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead'
$script:UsaMode755 = [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute'
$script:UsaExecBits = [System.IO.UnixFileMode]'UserExecute, GroupExecute, OtherExecute'

function Get-UsaBannerHostRoot {
    <#
    .SYNOPSIS
    Where the host's file system starts: '' for /.
    .DESCRIPTION
    Every path a deploy reads or writes starts with it. The tests mock it
    with a folder that stands in for a host.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    ''
}

function Test-UsaBannerPrivileged {
    <#
    .SYNOPSIS
    True when this process runs as root.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()
    [System.Environment]::IsPrivilegedProcess
}

function Invoke-UsaBannerNative {
    <#
    .SYNOPSIS
    Runs one program, and returns how it ended and what it said.
    .DESCRIPTION
    In:  the program, by name or path, and its arguments.
    Out: @{ ExitCode; Output }: its exit code, 127 when there is no such
         program; and its standard output and error, a string per line.
    Every program a deploy runs goes through here, so the tests see each
    call and run none of them on the host they run on.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    if (-not (Get-Command -Name $FilePath -CommandType Application -ErrorAction SilentlyContinue)) {
        return @{ ExitCode = 127; Output = @("${FilePath}: not found") }
    }
    $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object { "$_" })
    @{ ExitCode = $LASTEXITCODE; Output = $output }
}

function ConvertTo-UsaBannerOctal {
    # In:  a file mode
    # Out: the mode in octal, as chmod takes it: 755
    param([System.IO.UnixFileMode]$Mode)
    [System.Convert]::ToString([int]$Mode, 8)
}

function New-UsaBannerHostFolder {
    # In:  the host's root, a folder's path on the host, the list of the
    #      folders the deploy made, or none, and the mode a new folder gets;
    #      none on Windows, where a folder takes its parent's ACL
    # Out: nothing; the folder and any parent it lacked exist, and each one
    #      made is on the list, parents first
    # Why: removal takes away a folder the deploy made, once it is empty
    param(
        [AllowEmptyString()][string]$Root,
        [Parameter(Mandatory)][string]$Path,
        [AllowNull()][System.Collections.Generic.List[string]]$Created,
        [AllowNull()][Nullable[System.IO.UnixFileMode]]$Mode = $script:UsaMode755
    )
    $missing = [System.Collections.Generic.List[string]]::new()
    $at = $Path
    while ($at -and $at -ne '/' -and -not [System.IO.Directory]::Exists("$Root$at")) {
        $missing.Insert(0, $at)
        $at = [System.IO.Path]::GetDirectoryName($at)
    }
    foreach ($folder in $missing) {
        if ($null -eq $Mode) { $null = [System.IO.Directory]::CreateDirectory("$Root$folder") }
        else { $null = [System.IO.Directory]::CreateDirectory("$Root$folder", [System.IO.UnixFileMode]$Mode) }
        if ($null -ne $Created -and -not $Created.Contains($folder)) { $Created.Add($folder) }
    }
}

function Set-UsaBannerHostFile {
    <#
    .SYNOPSIS
    Puts one file on the host, where it is not there as it should be.
    .DESCRIPTION
    In:  the host's root; the file's path on the host; its content; its
         mode, none on Windows, where a file takes its folder's ACL; what it
         is, and a detail, for the line that reports it; the list of folders
         the deploy made.
    Out: a line saying what changed: written, or its mode set. Nothing when
         the file was already so, or under -WhatIf, which says it instead.
    The file is written as <path>.usabanner-tmp, given its mode, then moved
    over the old one, so a login never reads half of it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes,
        [AllowNull()][Nullable[System.IO.UnixFileMode]]$Mode = $script:UsaMode644,
        [Parameter(Mandatory)][string]$What,
        [string]$Detail = '',
        [AllowNull()][System.Collections.Generic.List[string]]$Created
    )
    $full = "$Root$Path"
    $exists = [System.IO.File]::Exists($full)
    $same = $exists -and [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($full), $Bytes)
    if ($same -and ($null -eq $Mode -or [System.IO.File]::GetUnixFileMode($full) -eq $Mode)) { return }
    $about = if ($Detail) { "$What ($Detail)" } else { $What }
    $action = if (-not $exists) { "Write $about" } elseif (-not $same) { "Rewrite $about" } else { "Set the mode to $(ConvertTo-UsaBannerOctal $Mode): $about" }
    if (-not $PSCmdlet.ShouldProcess($Path, $action)) { return }
    $folderMode = if ($null -eq $Mode) { $null } else { $script:UsaMode755 }
    New-UsaBannerHostFolder -Root $Root -Path ([System.IO.Path]::GetDirectoryName($Path)) -Created $Created -Mode $folderMode
    if ($same) { [System.IO.File]::SetUnixFileMode($full, [System.IO.UnixFileMode]$Mode) }
    else {
        $temp = "$full.usabanner-tmp"
        [System.IO.File]::WriteAllBytes($temp, $Bytes)
        if ($null -ne $Mode) { [System.IO.File]::SetUnixFileMode($temp, [System.IO.UnixFileMode]$Mode) }
        [System.IO.File]::Move($temp, $full, $true)
    }
    if (-not $exists) { "wrote ${Path}: $about" }
    elseif (-not $same) { "rewrote ${Path}: $about" }
    else { "set ${Path} to $(ConvertTo-UsaBannerOctal $Mode): $about" }
}

function Remove-UsaBannerHostFile {
    # In:  the host's root, a file's path on the host, and what it is
    # Out: a line when it was deleted; a warning instead when the host
    #      refused; nothing when it was not there, or under -WhatIf
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$What
    )
    $info = [System.IO.FileInfo]::new("$Root$Path")
    if (-not ($info.Exists -or $info.LinkTarget)) { return }
    if (-not $PSCmdlet.ShouldProcess($Path, "Delete $What")) { return }
    try { $info.Delete() }
    catch [System.UnauthorizedAccessException], [System.IO.IOException] {
        Write-Warning "UsaBanner: could not delete ${Path}, ${What}: $(Get-UsaBannerRefusal $_)"
        return
    }
    "deleted ${Path}: $What"
}

function Get-UsaBannerRefusal {
    # In:  the error of a .NET call the host refused
    # Out: the refusal as .NET words it (Access to the path '...' is
    #      denied.), without PowerShell's "Exception calling ..." around it
    # Why: on Linux the refusal holds errno's own words, "Permission denied",
    #      which name no file
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)
    $refused = $ErrorRecord.Exception
    while ($refused -is [System.Management.Automation.MethodInvocationException] -and $refused.InnerException) { $refused = $refused.InnerException }
    $refused.Message
}

function Remove-UsaBannerTree {
    # In:  a folder, by its path here; -Windows on a Windows host
    # Out: '' once the folder and everything in it are gone; else a line:
    #      how many files are left, and the host's refusal
    # Why: a delete the host refused must never be reported as done. git
    #      writes its objects read-only, and on Windows .NET deletes no
    #      read-only file, so each attribute is cleared first. On Windows,
    #      where even that is refused, Administrators take the folder over
    #      (Grant-UsaBannerTreeAccess) and it is tried once more
    param([Parameter(Mandatory)][string]$Path, [switch]$Windows)
    $refusal = ''
    foreach ($attempt in 1, 2) {
        if ($attempt -eq 2) {
            if (-not $Windows) { break }
            Grant-UsaBannerTreeAccess -Path $Path
        }
        try {
            foreach ($file in [System.IO.Directory]::GetFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
                $attributes = [System.IO.File]::GetAttributes($file)
                if ($attributes -band [System.IO.FileAttributes]::ReadOnly) { [System.IO.File]::SetAttributes($file, $attributes -band -bnot [System.IO.FileAttributes]::ReadOnly) }
            }
            [System.IO.Directory]::Delete($Path, $true)
            return ''
        }
        catch [System.UnauthorizedAccessException], [System.IO.IOException] { $refusal = Get-UsaBannerRefusal $_ }
    }
    $left = try { @([System.IO.Directory]::GetFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)).Count } catch { 'some' }
    "$left file(s) are left in it. $refusal"
}

function Remove-UsaBannerHostFolder {
    # In:  the host's root, one of the banner's own folders, and what it is
    # Out: a line when it was deleted with everything in it; a warning
    #      instead when the host refused; nothing when it was not there, or
    #      under -WhatIf
    # Why: only the banner's own folders, and the old banner's, are deleted
    #      whole; any other path is refused, whatever the caller asks
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$What
    )
    $ours = @($script:UsaLinuxEtc, $script:UsaLinuxShare, $script:UsaLinuxState) + @($script:UsaOldFolders.Keys)
    if ($Path -notin $ours -and $Path -notlike "$script:UsaLinuxModules/UsaBanner/*") {
        throw "UsaBanner: $Path is not one of the banner's own folders, so it is not deleted."
    }
    $full = "$Root$Path"
    if (-not [System.IO.Directory]::Exists($full)) { return }
    $count = @([System.IO.Directory]::GetFiles($full, '*', [System.IO.SearchOption]::AllDirectories)).Count
    if (-not $PSCmdlet.ShouldProcess($Path, "Delete the folder and the $count file(s) in it: $What")) { return }
    $refusal = Remove-UsaBannerTree -Path $full
    if ($refusal) {
        Write-Warning "UsaBanner: could not delete ${Path}, ${What}: $refusal"
        return
    }
    "deleted $Path and the $count file(s) in it: $What"
}

function Read-UsaBannerDeployRecord {
    <#
    .SYNOPSIS
    The record of what deploys changed on this host outside the banner's own
    files.
    .DESCRIPTION
    In:  the host's root; or the record's path, on Windows.
    Out: an ordered dictionary: retired (the scripts turned off, each with
         its path and its mode before), statoverride (each with its path
         and mode before), masked (each unit, and whether it was active),
         created (the folders made, parents first), module (the module's
         folder, when a deploy put it there); on Windows also notice (the
         logon notice set, and what it was before), shell (OpenSSH's default
         shell set, and what it was before) and sshd. Empty lists when there
         is no record.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([AllowEmptyString()][string]$Root = '', [string]$Path)
    $record = [ordered]@{ version = 1; retired = @(); statoverride = @(); masked = @(); created = @(); module = '' }
    $path = if ($Path) { $Path } else { "$Root$script:UsaLinuxState/deploy.json" }
    if (-not [System.IO.File]::Exists($path)) { return $record }
    $saved = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json -AsHashtable
    foreach ($key in $saved.Keys) {
        if ($null -eq $saved[$key]) { continue }
        # A list of one comes back from JSON as a list; @() keeps a list a list either way.
        if ($key -in 'retired', 'statoverride', 'masked', 'created') { $record[$key] = @($saved[$key]) }
        elseif ($key -eq 'module') { $record[$key] = [string]$saved[$key] }
        else { $record[$key] = $saved[$key] }
    }
    $record
}

function Add-UsaBannerRecordEntry {
    # In:  the record, one of its lists, an entry, and the key that names it
    # Out: nothing; the entry is on the list, unless one with the same name
    #      is there already: the first deploy saw the host as it was
    param(
        [System.Collections.IDictionary]$Record,
        [string]$List,
        [System.Collections.IDictionary]$Entry,
        [string]$Key
    )
    foreach ($kept in @($Record[$List])) { if ($kept[$Key] -eq $Entry[$Key]) { return } }
    $Record[$List] = @($Record[$List]) + @($Entry)
}

function Save-UsaBannerDeployRecord {
    # In:  the host's root, the record, and the folders made so far
    # Out: nothing; /var/lib/usabanner/deploy.json holds the record
    # Why: written after each change it records, so a deploy cut short
    #      leaves a record of what it did change. Under -WhatIf nothing
    #      changed, so there is nothing to record
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [AllowEmptyString()][string]$Root = '',
        [System.Collections.IDictionary]$Record,
        [System.Collections.Generic.List[string]]$Created
    )
    if ($WhatIfPreference) { return }
    $Record['created'] = @($Created)
    $json = ((ConvertTo-Json -InputObject $Record -Depth 5) -replace "`r`n", "`n") + "`n"
    $null = Set-UsaBannerHostFile -Root $Root -Path "$script:UsaLinuxState/deploy.json" -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($json)) -What 'the record of what the deploy changed' -Created $Created
}

function Assert-UsaBannerLinuxHost {
    <#
    .SYNOPSIS
    Stops a deploy or a removal that cannot go ahead here, saying why.
    .DESCRIPTION
    In:  the host's root, the command, and whether the old banner stops it.
    Throws unless this process runs as root (under -WhatIf anyone may look);
    unless the host is Ubuntu, with /etc/update-motd.d for pam_motd to run;
    and, for a deploy without -ReplaceOldBanner, when the old banner (this
    repository's install.sh) is installed, naming what of it was found.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][string]$Command,
        [switch]$RefuseOldInstall
    )
    if (-not $WhatIfPreference -and -not (Test-UsaBannerPrivileged)) {
        throw "UsaBanner: $Command changes files under /etc, /usr/local and /var/lib, so it runs as root: sudo pwsh, then $Command. With -WhatIf it only says what it would change, and anyone may run it."
    }
    $os = Get-UsaBannerHostOs -OnWindows $false -OsReleasePath "$Root/etc/os-release"
    if ($os -ne 'ubuntu' -or -not [System.IO.Directory]::Exists("$Root/etc/update-motd.d")) {
        throw "UsaBanner: $Command works on Ubuntu (24.04 and later) and Windows Server (2022 and later). This host's /etc/os-release does not say ID=ubuntu, or it has no /etc/update-motd.d."
    }
    if (-not $RefuseOldInstall) { return }
    $found = @(Find-UsaBannerLinuxOldInstall -Root $Root)
    if ($found.Count) {
        throw "UsaBanner: this host has the banner of this repository's install.sh ($($found -join ', ')). $Command does not install beside it: $Command -ReplaceOldBanner takes that banner off first, then deploys this one."
    }
}

function Find-UsaBannerLinuxOldInstall {
    # In:  the host's root
    # Out: each path of today's banner (this repository's install.sh) on the
    #      host
    param([AllowEmptyString()][string]$Root = '')
    $script:UsaOldInstall | Where-Object { [System.IO.File]::Exists("$Root$_") -or [System.IO.Directory]::Exists("$Root$_") }
}

function Resolve-UsaBannerLoginLook {
    <#
    .SYNOPSIS
    The colour mode and the glyphs of the banner Ubuntu shows after login.
    .DESCRIPTION
    pam_motd runs the banner with no terminal and no locale, and every login
    gets the same text, so there are no signals to read (D7): the host's
    settings decide alone. Where they say auto: 256 colours, which most SSH
    sessions announce (TERM=xterm-256color), and ASCII, which every client
    shows, as SPEC 3.1 asks of a setup made without the walk-through.
    Out: @{ Mode; AsciiOnly }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $mode = [string]$Config['color']['mode']
    if ($mode -eq 'auto') { $mode = '256' }
    @{ Mode = $mode; AsciiOnly = ([string]$Config['glyphs'] -ne 'unicode') }
}

function New-UsaBannerLinuxDrawing {
    <#
    .SYNOPSIS
    A host's banners, drawn as the files that hold them.
    .DESCRIPTION
    In:  the configuration, the OS (ubuntu, or linux for any other), the
         host's name and primary address, the SHA-256 of the configuration
         file, and the cached AD Description and the SHA-256 of its file
         ('' for none: Read-UsaBannerLinuxAdCache).
    Out: the text of each file, LF line ends: Frame, the banner after login
         (LoginFrame.ps1), with the tier and role the configuration and the
         AD Description give (Resolve-UsaBannerHostConfig); Issue, the
         console's, whose host name and address agetty fills in; IssueNet,
         the SSH banner, plain ASCII; LoginEnv, the services facts.sh
         watches; Drawn, the name, address, configuration and AD Description
         the banners were drawn with, which linux/redraw.sh compares. The
         banners before login end in a blank line, as today's, so the prompt
         does not touch the box.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][ValidateSet('ubuntu', 'linux')][string]$Os,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Ip = '',
        [Parameter(Mandatory)][string]$ConfigSum,
        [AllowEmptyString()][string]$Description = '',
        [AllowEmptyString()][string]$DescriptionSum = ''
    )
    $look = Resolve-UsaBannerLoginLook -Config $Config
    $hostConfig = (Resolve-UsaBannerHostConfig -Config $Config -Description $Description).Config
    $frame = @(New-UsaBannerLoginFrame -Config $hostConfig -Os $Os -Name $Name -Ip $Ip -Mode $look.Mode -AsciiOnly:$look.AsciiOnly)
    $issue = @(Get-UsaBannerPreInit -Config $Config -Os $Os)
    $net = @(Get-UsaBannerPreLogon -Config $Config -Os $Os -Facts @{ HostName = ($Name -split '\.')[0]; Ip = $Ip })
    $services = $Config['services']
    $watched = if ($services -is [string]) { $services } else { @($services) -join ' ' }
    [ordered]@{
        Frame    = ($frame -join "`n") + "`n"
        Issue    = ($issue -join "`n") + "`n`n"
        IssueNet = ($net -join "`n") + "`n`n"
        LoginEnv = "USABANNER_SERVICES=$watched`n"
        Drawn    = "$Name`t$Ip`t$ConfigSum`t$DescriptionSum`n"
    }
}

function Read-UsaBannerLinuxAdCache {
    # In:  the host's root
    # Out: @{ Text; Sum }: the AD Description the periodic job cached
    #      (Read-UsaBannerAdDescription), $null for none, and the SHA-256 of
    #      its file, '' for none
    # Why: the banners are drawn with the one, and linux/redraw.sh compares
    #      the other, as it compares the configuration's
    param([AllowEmptyString()][string]$Root = '')
    $path = "$Root$script:UsaLinuxState/ad-description"
    $text = Read-UsaBannerAdDescription -Path $path
    if ($null -eq $text) { return @{ Text = $null; Sum = '' } }
    @{ Text = $text; Sum = (Get-UsaBannerSha256 -Bytes ([System.IO.File]::ReadAllBytes($path))) }
}

function Write-UsaBannerLinuxDrawing {
    # In:  the host's root, the drawing (New-UsaBannerLinuxDrawing), and the
    #      folders made so far
    # Out: a line for each file that changed
    # Why: what was drawn goes last, so a run cut short is drawn again
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][System.Collections.IDictionary]$Drawing,
        [AllowNull()][System.Collections.Generic.List[string]]$Created
    )
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $files = [ordered]@{
        Frame    = @("$script:UsaLinuxState/postlogin.frame", 'the banner after login, drawn for the login renderer')
        LoginEnv = @("$script:UsaLinuxState/login.env", 'the services the banner watches')
        Issue    = @($script:UsaLinuxIssue, 'the console''s banner')
        IssueNet = @("$script:UsaLinuxEtc/issue.net", 'the SSH banner')
        Drawn    = @("$script:UsaLinuxState/drawn", 'the name, address, configuration and AD Description the banners were drawn with')
    }
    foreach ($key in $files.Keys) {
        Set-UsaBannerHostFile -Root $Root -Path $files[$key][0] -Bytes $utf8.GetBytes([string]$Drawing[$key]) -What $files[$key][1] -Created $Created
    }
}

function Get-UsaBannerSystemdUnits {
    <#
    .SYNOPSIS
    The periodic job's units: each file's name and text.
    .DESCRIPTION
    The service samples the host (linux/sample.sh, D17), then draws the
    banners again if the host's name, address or configuration changed
    (linux/redraw.sh). The timer runs it 2 minutes after boot, then 15
    minutes after each run, so hosts that started at different times do not
    sample at the same moment.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    [ordered]@{
        'usabanner-sample.service' = (@(
                '[Unit]'
                'Description=UsaBanner: sample this host, and draw its banners again when it changed'
                ''
                '[Service]'
                'Type=oneshot'
                "ExecStart=/bin/sh $script:UsaLinuxShare/sample.sh"
                "ExecStartPost=/bin/sh $script:UsaLinuxShare/redraw.sh"
                'SyslogIdentifier=usabanner'
            ) -join "`n") + "`n"
        'usabanner-sample.timer'   = (@(
                '[Unit]'
                'Description=UsaBanner: sample this host every 15 minutes'
                ''
                '[Timer]'
                'OnBootSec=2min'
                'OnUnitActiveSec=15min'
                'RandomizedDelaySec=1min'
                ''
                '[Install]'
                'WantedBy=timers.target'
            ) -join "`n") + "`n"
    }
}

function Get-UsaBannerUpdateUnits {
    <#
    .SYNOPSIS
    The update job's units: each file's name and text.
    .DESCRIPTION
    The service runs linux/update.sh, which has the module look for a newer
    release (Update-UsaBannerRelease, D14), once the network is up. The
    timer runs it 10 minutes after boot, then once a day, each host at its
    own time within the hour, so the hosts of a site do not all ask at once.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()
    [ordered]@{
        'usabanner-update.service' = (@(
                '[Unit]'
                'Description=UsaBanner: look for a newer release of the banner, and say so or install it'
                'Wants=network-online.target'
                'After=network-online.target'
                ''
                '[Service]'
                'Type=oneshot'
                "ExecStart=/bin/sh $script:UsaLinuxShare/update.sh"
                'SyslogIdentifier=usabanner'
            ) -join "`n") + "`n"
        'usabanner-update.timer'   = (@(
                '[Unit]'
                'Description=UsaBanner: look for a newer release of the banner once a day'
                ''
                '[Timer]'
                'OnBootSec=10min'
                'OnUnitActiveSec=1d'
                'RandomizedDelaySec=1h'
                ''
                '[Install]'
                'WantedBy=timers.target'
            ) -join "`n") + "`n"
    }
}

function Install-UsaBannerModuleCopy {
    <#
    .SYNOPSIS
    Copies the module to where every user's PowerShell finds it.
    .DESCRIPTION
    In:  the host's root, the record, the folders made so far; the modules
         folder for all users, the mode of each file copied and of each
         folder made, none on Windows, and the OS whose remover deletes.
    Out: a line when files were copied or removed, and one when the copy
         an earlier deploy recorded, of another version, was deleted.
    The module goes to <modules folder>/UsaBanner/<version>: on Linux
    /usr/local/share/powershell/Modules, where any user's Show-UsaBanner
    and the periodic job's redraw import it from; on Windows, Windows
    PowerShell's, which PowerShell 7 reads too. A module that runs from
    there already is not copied onto itself. Files the copy holds and the
    module does not are removed: the folder is the module's own. The copy
    the record named before, where it is another version, goes once this
    one is in place; a version folder no deploy recorded stays.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][System.Collections.IDictionary]$Record,
        [AllowNull()][System.Collections.Generic.List[string]]$Created,
        [string]$Modules = $script:UsaLinuxModules,
        [AllowNull()][Nullable[System.IO.UnixFileMode]]$FileMode = $script:UsaMode644,
        [AllowNull()][Nullable[System.IO.UnixFileMode]]$FolderMode = $script:UsaMode755,
        [ValidateSet('linux', 'windows')][string]$Os = 'linux'
    )
    $version = [string](Import-PowerShellDataFile -LiteralPath $script:UsaBannerManifest).ModuleVersion
    $target = [System.IO.Path]::Combine($Modules, 'UsaBanner', $version)
    $source = [System.IO.Path]::GetFullPath($script:UsaBannerRoot).TrimEnd('/', '\')
    if ($source -eq [System.IO.Path]::GetFullPath("$Root$target").TrimEnd('/', '\')) { return }
    $previous = [string]$Record['module']
    $copy = [System.Collections.Generic.List[string]]::new()
    $wanted = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($file in [System.IO.Directory]::GetFiles($source, '*', [System.IO.SearchOption]::AllDirectories)) {
        $relative = [System.IO.Path]::GetRelativePath($source, $file).Replace('\', '/')
        $null = $wanted.Add($relative)
        $there = "$Root$target/$relative"
        if (-not ([System.IO.File]::Exists($there) -and [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($there), [byte[]][System.IO.File]::ReadAllBytes($file)))) {
            $copy.Add($relative)
        }
    }
    $extra = @()
    if ([System.IO.Directory]::Exists("$Root$target")) {
        $extra = @([System.IO.Directory]::GetFiles("$Root$target", '*', [System.IO.SearchOption]::AllDirectories) |
                ForEach-Object { [System.IO.Path]::GetRelativePath("$Root$target", $_).Replace('\', '/') } |
                Where-Object { -not $wanted.Contains($_) })
    }
    $installed = $true
    if ($copy.Count -or $extra.Count) {
        $installed = $PSCmdlet.ShouldProcess($target, "Install the module UsaBanner $version for every user: $($copy.Count) file(s) to copy, $($extra.Count) to remove")
        if ($installed) {
            foreach ($relative in $copy) {
                $there = "$Root$target/$relative"
                New-UsaBannerHostFolder -Root $Root -Path ([System.IO.Path]::GetDirectoryName("$target/$relative")) -Created $Created -Mode $FolderMode
                $temp = "$there.usabanner-tmp"
                [System.IO.File]::Copy((Join-Path $source $relative), $temp, $true)
                if ($null -ne $FileMode) { [System.IO.File]::SetUnixFileMode($temp, [System.IO.UnixFileMode]$FileMode) }
                [System.IO.File]::Move($temp, $there, $true)
            }
            foreach ($relative in $extra) { [System.IO.File]::Delete("$Root$target/$relative") }
            "installed the module UsaBanner ${version} for every user: $target ($($copy.Count) file(s) copied, $($extra.Count) removed)"
        }
    }
    if ($installed) { $Record['module'] = $target }
    # The copy an earlier deploy recorded, of another version: Import-Module
    # loads the newest version there, so a downgrade would not take, and
    # Remove-UsaBanner, which reads the record, would never delete it (lab,
    # 2026-10-23). Said under -WhatIf; kept where this install was declined.
    # One separator and -ne's ignoring of case: the copy just installed,
    # recorded with a / by a deploy before 0.1.1, is never taken for it.
    if (($installed -or $WhatIfPreference) -and $previous -and $previous.Replace('\', '/') -ne $target.Replace('\', '/')) {
        $what = "UsaBanner $([System.IO.Path]::GetFileName($previous.Replace('\', '/'))), the copy an earlier deploy installed"
        if ($Os -eq 'windows') { Remove-UsaBannerWindowsFolder -Path $previous -Allowed $previous -What $what }
        else { Remove-UsaBannerHostFolder -Root $Root -Path $previous -What $what }
    }
}

function Disable-UsaBannerExecutable {
    # In:  the host's root, a script's path on the host, the record, and
    #      what the script is
    # Out: a line when it was turned off (chmod -x), and the record holds
    #      its mode before; nothing when it is missing, a link, or off already
    # Why: run-parts runs only executable scripts, and dpkg keeps a
    #      conffile's mode at an upgrade, so it stays off and apt never asks
    #      about it (D16)
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Record,
        [Parameter(Mandatory)][string]$What
    )
    $info = [System.IO.FileInfo]::new("$Root$Path")
    if ($info.LinkTarget -or -not $info.Exists) { return }
    $mode = [System.IO.File]::GetUnixFileMode($info.FullName)
    if (([int]$mode -band [int]$script:UsaExecBits) -eq 0) { return }
    if (-not $PSCmdlet.ShouldProcess($Path, "Turn off $What (chmod -x)")) { return }
    [System.IO.File]::SetUnixFileMode($info.FullName, [System.IO.UnixFileMode]([int]$mode -band -bnot [int]$script:UsaExecBits))
    Add-UsaBannerRecordEntry -Record $Record -List 'retired' -Entry ([ordered]@{ path = $Path; mode = (ConvertTo-UsaBannerOctal $mode) }) -Key 'path'
    "turned off ${Path}: $What"
}

function Disable-UsaBannerStockMotd {
    <#
    .SYNOPSIS
    Turns off the stock MOTD scripts the banner replaces (D16).
    .DESCRIPTION
    In:  the host's root, the record, and the folders made so far.
    Out: a line for each change. The scripts are turned off, never deleted,
         and each change goes on the record for removal:
         - each script of $script:UsaRetiredScripts that runs: chmod -x;
         - 50-landscape-sysinfo, a link to landscape-common's file: a
           mode set on that file comes undone at the package's next
           upgrade, so a dpkg statoverride sets it (0644) and keeps it;
         - motd-news: its timer masked, rather than ENABLED=0 written into
           /etc/default/motd-news, a conffile.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][System.Collections.IDictionary]$Record,
        [AllowNull()][System.Collections.Generic.List[string]]$Created
    )
    foreach ($name in $script:UsaRetiredScripts) {
        Disable-UsaBannerExecutable -Root $Root -Path "/etc/update-motd.d/$name" -Record $Record -What 'a stock MOTD script the banner replaces'
    }
    Save-UsaBannerDeployRecord -Root $Root -Record $Record -Created $Created

    $link = [System.IO.FileInfo]::new("$Root/etc/update-motd.d/50-landscape-sysinfo")
    if ($link.LinkTarget) {
        $target = $link.LinkTarget
        if (-not $target.StartsWith('/')) { $target = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine('/etc/update-motd.d', $target)) }
        $file = [System.IO.FileInfo]::new("$Root$target")
        if ($file.Exists -and ([int][System.IO.File]::GetUnixFileMode($file.FullName) -band [int]$script:UsaExecBits) -ne 0) {
            if ((Invoke-UsaBannerNative -FilePath 'dpkg' -ArgumentList '-S', $target).ExitCode -ne 0) {
                Disable-UsaBannerExecutable -Root $Root -Path $target -Record $Record -What 'the landscape-sysinfo MOTD script'
            }
            elseif ((Invoke-UsaBannerNative -FilePath 'dpkg-statoverride' -ArgumentList '--list', $target).ExitCode -ne 0 -and
                $PSCmdlet.ShouldProcess($target, 'Turn off the landscape-sysinfo MOTD script with a dpkg statoverride (root root 0644)')) {
                $before = ConvertTo-UsaBannerOctal ([System.IO.File]::GetUnixFileMode($file.FullName))
                $added = Invoke-UsaBannerNative -FilePath 'dpkg-statoverride' -ArgumentList '--update', '--add', 'root', 'root', '0644', $target
                if ($added.ExitCode -eq 0) {
                    Add-UsaBannerRecordEntry -Record $Record -List 'statoverride' -Entry ([ordered]@{ path = $target; mode = $before }) -Key 'path'
                    "turned off /etc/update-motd.d/50-landscape-sysinfo: a dpkg statoverride sets $target to 0644"
                }
                else { Write-Warning "UsaBanner: dpkg-statoverride could not turn off ${target}: $($added.Output -join ' ')" }
            }
        }
    }
    elseif ($link.Exists) {
        Disable-UsaBannerExecutable -Root $Root -Path '/etc/update-motd.d/50-landscape-sysinfo' -Record $Record -What 'the landscape-sysinfo MOTD script'
    }
    Save-UsaBannerDeployRecord -Root $Root -Record $Record -Created $Created

    $state = @((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-enabled', 'motd-news.timer').Output)
    $first = if ($state.Count) { [string]$state[0] } else { '' }
    if ($first -and $first -notmatch '^masked|not-found|No such file|Failed') {
        $active = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-active', 'motd-news.timer').Output) + '')[0] -eq 'active'
        if ($PSCmdlet.ShouldProcess('motd-news.timer', 'Stop it, then mask it, so motd-news stays off without a change to /etc/default/motd-news (systemctl stop, systemctl mask)')) {
            # A timer masked while it runs fails: at the reload mask makes, its
            # unit file is /dev/null, and systemd 255 logs "Unit to trigger
            # vanished" and "Failed with result 'resources'" (lab, 2026-10-23),
            # which every login then lists among the failed units. mask --now
            # masks first, so it is stopped before.
            if ($active) {
                $stopped = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'stop', 'motd-news.timer'
                if ($stopped.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not stop motd-news.timer: $($stopped.Output -join ' ')" }
            }
            $masked = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'mask', 'motd-news.timer'
            if ($masked.ExitCode -eq 0) {
                Add-UsaBannerRecordEntry -Record $Record -List 'masked' -Entry ([ordered]@{ unit = 'motd-news.timer'; active = $active }) -Key 'unit'
                'masked motd-news.timer: the MOTD news stay off'
            }
            else { Write-Warning "UsaBanner: systemctl could not mask motd-news.timer: $($masked.Output -join ' ')" }
        }
    }
    Save-UsaBannerDeployRecord -Root $Root -Record $Record -Created $Created
}

function Get-UsaBannerSshDropIn {
    # Out: the text of the drop-in that points sshd's Banner at the banner's
    #      own file
    [CmdletBinding()]
    [OutputType([string])]
    param()
    (@(
            '# UsaBanner: the banner sshd sends before authentication, written by'
            '# Deploy-UsaBanner. Named 00- because sshd takes the first Banner it reads,'
            '# and reads these files in name order.'
            "Banner $script:UsaLinuxEtc/issue.net"
        ) -join "`n") + "`n"
}

function Set-UsaBannerSshBanner {
    <#
    .SYNOPSIS
    Points sshd's Banner at the banner's own file, where sshd is installed.
    .DESCRIPTION
    In:  the host's root, and the folders made so far.
    Out: a line for each change, or one saying why there is no SSH banner.
    The drop-in is named 00- because sshd takes the first Banner it reads,
    and reads sshd_config.d in name order. sshd -t checks the configuration
    with it; one it refuses takes the drop-in back out, with a warning.
    Then ssh reloads, and sessions already open carry on. A Banner sshd
    reads before the drop-in (from another file, or from sshd_config above
    its Include) is someone else's: a warning names what sshd uses.
    sshd -T, which says what sshd uses, needs /run/sshd as -t does, and
    after a boot it is gone until the first connection starts sshd, so it is
    made first. A -T that fails anyway is a warning in sshd's own words.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [AllowNull()][System.Collections.Generic.List[string]]$Created
    )
    if (-not [System.IO.File]::Exists("$Root$script:UsaLinuxSshd")) {
        'no SSH banner: OpenSSH''s server is not installed here; run Deploy-UsaBanner again once it is'
        return
    }
    $want = "$script:UsaLinuxEtc/issue.net"
    $text = Get-UsaBannerSshDropIn
    $full = "$Root$script:UsaLinuxDropIn"
    $before = if ([System.IO.File]::Exists($full)) { [System.IO.File]::ReadAllBytes($full) } else { $null }
    $line = Set-UsaBannerHostFile -Root $Root -Path $script:UsaLinuxDropIn -Bytes ([System.Text.UTF8Encoding]::new($false).GetBytes($text)) -What 'sshd''s Banner line' -Created $Created
    if ($line) {
        # sshd -t refuses any configuration without /run/sshd. ssh.service makes it, and systemd
        # removes it whenever the service stops, which on 24.04 happens while ssh.socket listens.
        New-UsaBannerHostFolder -Root $Root -Path '/run/sshd' -Created $null
        $test = Invoke-UsaBannerNative -FilePath $script:UsaLinuxSshd -ArgumentList '-t'
        if ($test.ExitCode -ne 0) {
            if ($null -eq $before) { [System.IO.File]::Delete($full) } else { [System.IO.File]::WriteAllBytes($full, $before) }
            Write-Warning "UsaBanner: sshd -t refused the configuration with $script:UsaLinuxDropIn, so it is out again, and there is no SSH banner: $($test.Output -join ' ')"
            return
        }
        $line
        $reload = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'try-reload-or-restart', 'ssh'
        if ($reload.ExitCode -eq 0) { 'reloaded ssh: sessions already open carry on' }
        else { Write-Warning "UsaBanner: systemctl could not reload ssh, so the SSH banner shows from its next start: $($reload.Output -join ' ')" }
    }
    if ($WhatIfPreference) { return }
    # A deploy at boot, before any connection had started sshd, warned "Banner none" (lab, 2026-10-25).
    New-UsaBannerHostFolder -Root $Root -Path '/run/sshd' -Created $null
    $read = Invoke-UsaBannerNative -FilePath $script:UsaLinuxSshd -ArgumentList '-T'
    if ($read.ExitCode -ne 0) {
        Write-Warning "UsaBanner: sshd -T could not read the configuration, so which Banner sshd sends is not known: $(@($read.Output) -join ' ')"
        return
    }
    $uses = @(@($read.Output) | Where-Object { $_ -match '^banner\s' } | ForEach-Object { ($_ -split '\s+', 2)[1] })
    $banner = if ($uses.Count) { $uses[0] } else { 'none' }
    if ($banner -ne $want) {
        Write-Warning "UsaBanner: sshd sends the Banner $banner, not ${want}: a file sshd reads before $script:UsaLinuxDropIn sets one, and sshd takes the first."
    }
}

function Set-UsaBannerSampleTimer {
    <#
    .SYNOPSIS
    Installs the periodic job and starts it.
    .DESCRIPTION
    In:  the host's root, and the folders made so far.
    Out: a line for each change. The units are written where they changed,
         and systemd reloaded; the timer is enabled and started unless it
         is already; on a host with no samples yet, a first sample starts at
         once, in the background, so the 24-hour range, the slow facts and
         the FQDN begin now rather than in 15 minutes.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [AllowNull()][System.Collections.Generic.List[string]]$Created
    )
    $units = Get-UsaBannerSystemdUnits
    $changed = $false
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    foreach ($unit in $units.Keys) {
        $line = Set-UsaBannerHostFile -Root $Root -Path "/etc/systemd/system/$unit" -Bytes $utf8.GetBytes([string]$units[$unit]) -What 'a unit of the periodic job' -Created $Created
        if ($line) {
            $line
            $changed = $true
        }
    }
    if ($changed) {
        $reload = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'daemon-reload'
        if ($reload.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl daemon-reload failed: $($reload.Output -join ' ')" }
    }
    $state = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-enabled', 'usabanner-sample.timer').Output) + '')[0]
    if (($changed -or $state -ne 'enabled') -and $PSCmdlet.ShouldProcess('usabanner-sample.timer', 'Enable and start the periodic job (systemctl enable --now)')) {
        $enable = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'enable', '--now', 'usabanner-sample.timer'
        if ($enable.ExitCode -eq 0) { 'started usabanner-sample.timer: a sample every 15 minutes' }
        else { Write-Warning "UsaBanner: systemctl could not enable usabanner-sample.timer: $($enable.Output -join ' ')" }
    }
    if (-not [System.IO.File]::Exists("$Root$script:UsaLinuxState/samples.tsv") -and
        $PSCmdlet.ShouldProcess('usabanner-sample.service', 'Take a first sample now, in the background (systemctl start --no-block)')) {
        $start = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'start', '--no-block', 'usabanner-sample.service'
        if ($start.ExitCode -eq 0) { 'started a first sample: the 24-hour range, the slow facts and the FQDN begin now' }
        else { Write-Warning "UsaBanner: systemctl could not start a first sample; the timer takes one within 15 minutes: $($start.Output -join ' ')" }
    }
}

function Set-UsaBannerUpdateTimer {
    <#
    .SYNOPSIS
    Installs the update job where the configuration turns the update channel
    on, and takes it away where it is off.
    .DESCRIPTION
    In:  the host's root, the configuration, and the folders made so far.
    Out: a line for each change. On: the units written where they changed,
         systemd reloaded, the timer enabled and started unless it is
         already. Off: the timer stopped and disabled, the units deleted,
         and the notice the job left with them: no job is left to take it
         away, and the banner after login would show it for good.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Root = '',
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [AllowNull()][System.Collections.Generic.List[string]]$Created
    )
    $units = Get-UsaBannerUpdateUnits
    $mode = [string]$Config['update']['mode']
    $changed = $false
    if ($mode -eq 'off') {
        if ([System.IO.File]::Exists("$Root/etc/systemd/system/usabanner-update.timer") -and
            $PSCmdlet.ShouldProcess('usabanner-update.timer', 'Stop and disable the update job: the update channel is off (systemctl disable --now)')) {
            $disable = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'disable', '--now', 'usabanner-update.timer'
            if ($disable.ExitCode -eq 0) { 'stopped usabanner-update.timer: the update channel is off' }
            else { Write-Warning "UsaBanner: systemctl could not disable usabanner-update.timer: $($disable.Output -join ' ')" }
        }
        foreach ($unit in $units.Keys) {
            $line = Remove-UsaBannerHostFile -Root $Root -Path "/etc/systemd/system/$unit" -What 'a unit of the update job'
            if ($line) {
                $line
                $changed = $true
            }
        }
        Remove-UsaBannerHostFile -Root $Root -Path "$script:UsaLinuxState/notice" -What "the update job's notice"
    }
    else {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        foreach ($unit in $units.Keys) {
            $line = Set-UsaBannerHostFile -Root $Root -Path "/etc/systemd/system/$unit" -Bytes $utf8.GetBytes([string]$units[$unit]) -What 'a unit of the update job' -Created $Created
            if ($line) {
                $line
                $changed = $true
            }
        }
    }
    if ($changed) {
        $reload = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'daemon-reload'
        if ($reload.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl daemon-reload failed: $($reload.Output -join ' ')" }
    }
    if ($mode -eq 'off') { return }
    $state = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-enabled', 'usabanner-update.timer').Output) + '')[0]
    if (($changed -or $state -ne 'enabled') -and $PSCmdlet.ShouldProcess('usabanner-update.timer', "Enable and start the update job ($mode): once a day (systemctl enable --now)")) {
        $enable = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'enable', '--now', 'usabanner-update.timer'
        if ($enable.ExitCode -eq 0) { "started usabanner-update.timer: the update channel ($mode), once a day" }
        else { Write-Warning "UsaBanner: systemctl could not enable usabanner-update.timer: $($enable.Output -join ' ')" }
    }
}

function Invoke-UsaBannerLinuxDeploy {
    <#
    .SYNOPSIS
    Deploys a configuration to this Ubuntu host: Deploy-UsaBanner's work.
    .DESCRIPTION
    In:  the configuration (New-UsaBannerDeployConfig), and -ReplaceOld to
         take the old banner off first.
    Out: a line for each change, in the order made; nothing when the host
         already has it all. Under -WhatIf, PowerShell says each change
         instead, and nothing changes.
    Every banner is drawn before anything changes, so a configuration or
    art that fails leaves the host as it was. Then the old banner comes off,
    where -ReplaceOld says so (OldBanner.ps1). Then, so a login never meets
    no banner at all: the module and the login renderer; the configuration
    and the drawn banners; the banner after login; the stock MOTD scripts
    off; SSH; the periodic job. Changes made outside the banner's own files
    go on the record as they are made.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config, [switch]$ReplaceOld)
    $root = Get-UsaBannerHostRoot
    Assert-UsaBannerLinuxHost -Root $root -Command 'Deploy-UsaBanner' -RefuseOldInstall:(-not $ReplaceOld)
    $record = Read-UsaBannerDeployRecord -Root $root
    $created = [System.Collections.Generic.List[string]]::new()
    foreach ($folder in @($record['created'])) { if ($folder) { $created.Add([string]$folder) } }

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $configBytes = $utf8.GetBytes((ConvertTo-UsaBannerConfigJson -Config $Config))
    $facts = Get-UsaBannerHostFacts -Services @()
    $ad = Read-UsaBannerLinuxAdCache -Root $root
    $drawing = New-UsaBannerLinuxDrawing -Config $Config -Os 'ubuntu' -Name ([string]$facts['Name']) -Ip ([string]$facts['Ip']) -ConfigSum (Get-UsaBannerSha256 -Bytes $configBytes) -Description $ad.Text -DescriptionSum $ad.Sum
    $configPath = "$script:UsaLinuxEtc/usabanner.json"
    $settings = ''
    if ([System.IO.File]::Exists("$root$configPath")) {
        $old = $null
        try { $old = Read-UsaBannerConfig -Path "$root$configPath" } catch { $settings = 'the old one could not be read, and is replaced whole' }
        if ($null -ne $old) { $settings = @(Compare-UsaBannerConfig -Old $old -New $Config) -join '; ' }
    }

    if ($ReplaceOld) { Remove-UsaBannerLinuxOldInstall -Root $root -Record $record }
    Install-UsaBannerModuleCopy -Root $root -Record $record -Created $created
    foreach ($file in $script:UsaLinuxScripts) {
        Set-UsaBannerHostFile -Root $root -Path "$script:UsaLinuxShare/$file" -Bytes ([System.IO.File]::ReadAllBytes((Join-Path $script:UsaBannerRoot 'linux' $file))) -What 'the login renderer and the periodic job' -Created $created
    }
    Set-UsaBannerHostFile -Root $root -Path $configPath -Bytes $configBytes -What 'the configuration' -Detail $settings -Created $created
    Write-UsaBannerLinuxDrawing -Root $root -Drawing $drawing -Created $created
    Set-UsaBannerHostFile -Root $root -Path $script:UsaLinuxMotd -Bytes ([System.IO.File]::ReadAllBytes((Join-Path $script:UsaBannerRoot 'linux' '05-usabanner'))) -Mode $script:UsaMode755 -What 'the banner after login, which pam_motd runs' -Created $created
    Save-UsaBannerDeployRecord -Root $root -Record $record -Created $created
    Disable-UsaBannerStockMotd -Root $root -Record $record -Created $created
    Set-UsaBannerSshBanner -Root $root -Created $created
    Set-UsaBannerSampleTimer -Root $root -Created $created
    Set-UsaBannerUpdateTimer -Root $root -Config $Config -Created $created
    Save-UsaBannerDeployRecord -Root $root -Record $record -Created $created
}

function Update-UsaBannerDrawing {
    <#
    .SYNOPSIS
    Draws this host's banners again, from its own configuration.
    .DESCRIPTION
    linux/redraw.sh runs it after a sample of the periodic job, when the
    host's name, address, configuration file or cached AD Description is no
    longer what the banners were drawn with: a VM made from a template and
    renamed, an address that moved, an edit of
    /etc/usabanner/usabanner.json, a Description changed in AD. It rewrites
    only the drawn files that change, and says which.
    Throws when the configuration cannot be read: the banners stay as they
    were, and the periodic job's run fails, which the banner's health
    lines show.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()
    $root = Get-UsaBannerHostRoot
    $path = "$root$script:UsaLinuxEtc/usabanner.json"
    $config = Read-UsaBannerConfig -Path $path
    $facts = Get-UsaBannerHostFacts -Services @()
    $os = Get-UsaBannerHostOs -OnWindows $false -OsReleasePath "$root/etc/os-release"
    $ad = Read-UsaBannerLinuxAdCache -Root $root
    $drawing = New-UsaBannerLinuxDrawing -Config $config -Os $os -Name ([string]$facts['Name']) -Ip ([string]$facts['Ip']) -ConfigSum (Get-UsaBannerSha256 -Bytes ([System.IO.File]::ReadAllBytes($path))) -Description $ad.Text -DescriptionSum $ad.Sum
    Write-UsaBannerLinuxDrawing -Root $root -Drawing $drawing -Created $null
}

function Invoke-UsaBannerLinuxRemove {
    <#
    .SYNOPSIS
    Takes the banner off this Ubuntu host: Remove-UsaBanner's work.
    .DESCRIPTION
    Out: a line for each change, in the order made; nothing when there is
         no banner here. Under -WhatIf, PowerShell says each change
         instead, and nothing changes.
    The periodic job and the update job stop first, a run in progress with
    them, so they draw and install nothing more, and a run stopped part way
    leaves no failed unit behind; so does the Group Policy runner's publish
    watcher (linux/adsys-startup.sh, D29), where it wrote one. The stock MOTD
    scripts come back on before the banner goes, so a login meets one or
    both, never neither. Then the SSH drop-in (ssh reloads), the console's
    file, the banner's own folders, the module's copy, and the folders the
    deploy made, once empty. Only what the record says a deploy changed is
    changed back: a script someone else turned off stays off.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()
    $root = Get-UsaBannerHostRoot
    Assert-UsaBannerLinuxHost -Root $root -Command 'Remove-UsaBanner'
    $record = Read-UsaBannerDeployRecord -Root $root

    # Each job, the unit that starts it, and its units' names. The publish
    # watcher is not the deploy's: the Group Policy runner writes it.
    $jobs = [ordered]@{
        'usabanner-sample'  = @{ What = 'the periodic job'; Trigger = 'timer'; Units = @((Get-UsaBannerSystemdUnits).Keys) }
        'usabanner-update'  = @{ What = 'the update job'; Trigger = 'timer'; Units = @((Get-UsaBannerUpdateUnits).Keys) }
        'usabanner-publish' = @{ What = 'the Group Policy publish watcher'; Trigger = 'path'; Units = @('usabanner-publish.path', 'usabanner-publish.service') }
    }
    $stopped = [System.Collections.Generic.List[string]]::new()
    foreach ($job in $jobs.Keys) {
        $trigger = "$job.$($jobs[$job].Trigger)"
        if ([System.IO.File]::Exists("$root/etc/systemd/system/$trigger") -and
            $PSCmdlet.ShouldProcess($trigger, "Stop and disable $($jobs[$job].What) (systemctl disable --now)")) {
            $stopped.Add($job)
            $disable = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'disable', '--now', $trigger
            if ($disable.ExitCode -eq 0) { "stopped $trigger" }
            else { Write-Warning "UsaBanner: systemctl could not disable ${trigger}: $($disable.Output -join ' ')" }
            # The trigger stopped, a run in progress goes on, and writes the
            # banner's folder again after it is gone (lab, 2026-10-23).
            $stop = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'stop', "$job.service"
            if ($stop.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not stop $job.service: $($stop.Output -join ' ')" }
        }
    }
    $gone = @(foreach ($job in $jobs.Keys) {
            foreach ($unit in $jobs[$job].Units) { Remove-UsaBannerHostFile -Root $root -Path "/etc/systemd/system/$unit" -What "a unit of $($jobs[$job].What)" }
        })
    $gone
    if ($gone.Count) {
        $reload = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'daemon-reload'
        if ($reload.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl daemon-reload failed: $($reload.Output -join ' ')" }
    }
    # A run stopped part way ends failed ("Failed with result 'signal'"), and
    # with its unit file gone it stays in systemctl's failed list until it is
    # reset (lab, 2026-10-23).
    foreach ($job in $stopped) {
        $state = [string](@((Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'is-failed', "$job.service").Output) + '')[0]
        if ($state -eq 'failed' -and $PSCmdlet.ShouldProcess("$job.service", 'Clear its failed state, so no failed unit outlives the banner (systemctl reset-failed)')) {
            $reset = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'reset-failed', "$job.service"
            if ($reset.ExitCode -eq 0) { "cleared the failed state of ${job}.service: a run stopped part way, or one that failed, ends so" }
            else { Write-Warning "UsaBanner: systemctl could not reset $job.service: $($reset.Output -join ' ')" }
        }
    }

    foreach ($entry in @($record['retired'])) {
        $full = "$root$($entry['path'])"
        if (-not [System.IO.File]::Exists($full)) { continue }
        $mode = [System.IO.UnixFileMode][System.Convert]::ToInt32([string]$entry['mode'], 8)
        if ([System.IO.File]::GetUnixFileMode($full) -eq $mode) { continue }
        if ($PSCmdlet.ShouldProcess([string]$entry['path'], "Turn the stock MOTD script back on (mode $($entry['mode']))")) {
            [System.IO.File]::SetUnixFileMode($full, $mode)
            "turned back on $($entry['path'])"
        }
    }
    foreach ($entry in @($record['statoverride'])) {
        $path = [string]$entry['path']
        if ($PSCmdlet.ShouldProcess($path, "Remove the dpkg statoverride, and set the mode back to $($entry['mode'])")) {
            $removed = Invoke-UsaBannerNative -FilePath 'dpkg-statoverride' -ArgumentList '--remove', $path
            if ($removed.ExitCode -ne 0) { Write-Warning "UsaBanner: dpkg-statoverride could not remove the override of ${path}: $($removed.Output -join ' ')" }
            if ([System.IO.File]::Exists("$root$path")) { [System.IO.File]::SetUnixFileMode("$root$path", [System.IO.UnixFileMode][System.Convert]::ToInt32([string]$entry['mode'], 8)) }
            "removed the dpkg statoverride on ${path}: /etc/update-motd.d/50-landscape-sysinfo runs again"
        }
    }
    foreach ($entry in @($record['masked'])) {
        $unit = [string]$entry['unit']
        if ($PSCmdlet.ShouldProcess($unit, 'Unmask it, and start it if it was running (systemctl unmask)')) {
            $unmasked = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'unmask', $unit
            if ($unmasked.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not unmask ${unit}: $($unmasked.Output -join ' ')" }
            elseif ($entry['active']) {
                $started = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'start', $unit
                if ($started.ExitCode -ne 0) { Write-Warning "UsaBanner: systemctl could not start ${unit}: $($started.Output -join ' ')" }
            }
            "unmasked $unit"
        }
    }

    Remove-UsaBannerHostFile -Root $root -Path $script:UsaLinuxMotd -What 'the banner after login'
    $dropIn = Remove-UsaBannerHostFile -Root $root -Path $script:UsaLinuxDropIn -What 'sshd''s Banner line'
    if ($dropIn) {
        $dropIn
        $reload = Invoke-UsaBannerNative -FilePath 'systemctl' -ArgumentList 'try-reload-or-restart', 'ssh'
        if ($reload.ExitCode -eq 0) { 'reloaded ssh: sessions already open carry on' }
        else { Write-Warning "UsaBanner: systemctl could not reload ssh, so sshd sends the old banner until its next start: $($reload.Output -join ' ')" }
    }
    Remove-UsaBannerHostFile -Root $root -Path $script:UsaLinuxIssue -What 'the console''s banner'
    Remove-UsaBannerHostFolder -Root $root -Path $script:UsaLinuxEtc -What 'the configuration and the SSH banner'
    Remove-UsaBannerHostFolder -Root $root -Path $script:UsaLinuxShare -What 'the login renderer and the periodic job'
    Remove-UsaBannerHostFolder -Root $root -Path $script:UsaLinuxState -What 'the drawn banner, the samples and the record'
    if ($record['module']) {
        Remove-UsaBannerHostFolder -Root $root -Path ([string]$record['module']) -What 'the module''s copy for every user'
    }
    $made = @($record['created'])
    [array]::Reverse($made)
    foreach ($folder in $made) {
        $full = "$root$folder"
        if (-not [System.IO.Directory]::Exists($full) -or @([System.IO.Directory]::GetFileSystemEntries($full)).Count -gt 0) { continue }
        if ($PSCmdlet.ShouldProcess([string]$folder, 'Delete the empty folder the deploy made')) {
            [System.IO.Directory]::Delete($full)
            "deleted the empty folder ${folder}: the deploy made it"
        }
    }
}
