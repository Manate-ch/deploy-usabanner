<#
.SYNOPSIS
Publishes the banner from a clone of this repo to the two places hosts read
it - SYSVOL for Ubuntu (ADSys), NETLOGON for Windows - and creates or
overwrites the "Manatech MOTD" GPO that points both at it.

.DESCRIPTION
Run on a DC, or a domain machine with the Group Policy Management tools, in
Windows PowerShell 5.1, as someone who can write SYSVOL and edit GPOs, from a
clone checked out at the commit to publish (normally main after a merge):

1. Ubuntu: what a host needs - install.sh, adsys-startup.sh, README.md,
   rootfs\ and windows\ without tests\ and demo.ps1 - goes to
   \\<domain>\SYSVOL\<domain>\Ubuntu\scripts\MOTD\. ADSys downloads only the
   Ubuntu\ tree of SYSVOL, so this copy has to live there.
2. Windows: README.md, rootfs\ (the art and data files, the pre-login
   banner) and windows\, the same way, go to \\<domain>\NETLOGON\MOTD\,
   where the GPO's scheduled task runs Sync-ManatechBanner.ps1 from. That
   folder is created by this script and marked with a .manatech-motd file;
   an existing NETLOGON\MOTD without the mark is someone else's, and the run
   stops before writing anything.
3. Every text file is written with LF line endings, whatever the clone
   holds: sh and awk cannot read CRLF, and Git for Windows (core.autocrlf)
   checks files out as CRLF. The run says how many files it had to convert.
   Files whose published content would not change are left alone, and files
   no longer in the repo are removed - from those two MOTD folders only.
4. When the Ubuntu copy changed, Version= in Ubuntu\GPT.INI goes up: ADSys
   downloads the Ubuntu\ tree again only when that number moves.
5. The GPO -GpoName ("Manatech MOTD") is created when no GPO has that name,
   and made to hold:
   - Ubuntu: the ADSys startup values the ADSys administrative template
     writes - metaValues with the append strategy for every release it
     names and for "all", so every other GPO's startup scripts still run,
     and all = MOTD/adsys-startup.sh - and no other value under that key;
   - Windows: a Group Policy Preferences scheduled task, "Manatech MOTD
     sync": SYSTEM with highest privileges, at startup and daily every 4
     hours, stopped after 30 minutes, running Sync-ManatechBanner.ps1 from
     the Windows copy (an item for that task already in the GPO is
     replaced; items for other tasks stay).
   A GPO of that name that exists already is overwritten: before anything
   changes, a warning names each of those settings it holds differently,
   with the old and the new value, and another lists what else the GPO
   holds, which is left alone. A publish that changes nothing in the GPO
   gives no overwrite warning.
6. The GPO is linked to each -LinkTarget it is not linked to yet (a
   disabled link there is enabled, with a warning). Without -LinkTarget,
   links stay as they are, and a GPO linked nowhere gets a warning instead
   of a default link: the Windows half would run on every Windows machine
   under the link, so where it goes is your call.
7. Everything is read back, one line per check, and the run fails if any
   check does.

Ubuntu hosts install a publish once ADSys has downloaded it (its refresh
runs every 90 minutes); Windows hosts read NETLOGON on their next 4-hourly
sync. -SkipGpo does steps 1-4 only. Every change honours -WhatIf.

.PARAMETER UbuntuPath
The ADSys assets folder to publish into, instead of
\\<Domain>\SYSVOL\<Domain>\Ubuntu - a DC's local SYSVOL path, or a test folder.

.PARAMETER NetlogonPath
The folder for the Windows copy, instead of \\<Domain>\NETLOGON\MOTD. With
-UbuntuPath and no -NetlogonPath it is scripts\MOTD beside the Ubuntu
folder, which on a DC's local SYSVOL path (...\sysvol\<domain>\Ubuntu) is
NETLOGON\MOTD. The scheduled task runs the sync from \\<Domain>\NETLOGON\MOTD,
or from -NetlogonPath when that is a UNC path.

.PARAMETER GpoName
The GPO to create or overwrite.

.PARAMETER LinkTarget
Where to link the GPO, as distinguished names, e.g.
'OU=Linux,DC=ad,DC=example','OU=Servers,DC=ad,DC=example'.

.PARAMETER SkipGpo
Publish the files only, without touching the GPO; this mode also runs under
PowerShell 7.

.EXAMPLE
.\windows\Publish-ManatechMotd.ps1 -WhatIf
.EXAMPLE
.\windows\Publish-ManatechMotd.ps1 -Domain ad.example -LinkTarget 'OU=Linux,DC=ad,DC=example'
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The clone to publish from (the folder holding install.sh).
    [string]$RepoPath = (Split-Path -Parent $PSScriptRoot),
    [string]$Domain = $env:USERDNSDOMAIN,
    [string]$UbuntuPath,
    [string]$NetlogonPath,
    [string]$GpoName = 'Manatech MOTD',
    [string[]]$LinkTarget,
    [switch]$SkipGpo
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Under PowerShell 7 the GroupPolicy module loads through a compatibility
# session: its objects are deserialized copies, and setting a property on one
# changes nothing.
if (-not $SkipGpo -and $PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run this in Windows PowerShell 5.1 (powershell.exe): under PowerShell 7 the GroupPolicy module works through a compatibility session. -SkipGpo publishes the files only.'
}

$RepoPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($RepoPath).TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath (Join-Path $RepoPath 'install.sh'))) { throw "$RepoPath has no install.sh: point -RepoPath at a clone of this repo" }
if ($Domain) { $Domain = $Domain.ToLower() }
if (-not $SkipGpo -and -not $Domain) { throw 'USERDNSDOMAIN is empty: pass -Domain (e.g. -Domain ad.example)' }
if ($UbuntuPath) {
    $ubuntu = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($UbuntuPath).TrimEnd('\', '/')
} else {
    if (-not $Domain) { throw 'USERDNSDOMAIN is empty: pass -Domain (e.g. -Domain ad.example)' }
    $ubuntu = "\\$Domain\SYSVOL\$Domain\Ubuntu"
}
if ($NetlogonPath) {
    $netlogon = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($NetlogonPath).TrimEnd('\', '/')
} elseif ($UbuntuPath) {
    $netlogon = Join-Path (Join-Path (Split-Path -Parent $ubuntu) 'scripts') 'MOTD'
} else {
    $netlogon = "\\$Domain\NETLOGON\MOTD"
}
$ini = Join-Path $ubuntu 'GPT.INI'
if (-not (Test-Path -LiteralPath $ini)) { throw "$ini not found: the ADSys assets folder (Ubuntu\ with its GPT.INI) must exist first" }
$sysvolMotd = Join-Path (Join-Path $ubuntu 'scripts') 'MOTD'

# The mark that says this script owns the NETLOGON folder (and may remove
# files from it). It is published content too, so it is never pruned.
$markName = '.manatech-motd'
$markText = "Published by windows/Publish-ManatechMotd.ps1 (Manatech-MOTD) for the GPO's Windows task.`n" +
    "Files here that are not in the repo are removed at the next publish.`n"

# ConvertTo-LfByte BYTES - the bytes with every CR LF pair turned into LF.
# A file holding a NUL byte is binary and comes back unchanged.
function ConvertTo-LfByte {
    param([byte[]]$Bytes)
    if ($Bytes.Length -eq 0 -or [Array]::IndexOf($Bytes, [byte]0) -ge 0 -or [Array]::IndexOf($Bytes, [byte]13) -lt 0) { return , $Bytes }
    $out = [System.IO.MemoryStream]::new($Bytes.Length)
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        if ($Bytes[$i] -eq 13 -and $i + 1 -lt $Bytes.Length -and $Bytes[$i + 1] -eq 10) { continue }
        $out.WriteByte($Bytes[$i])
    }
    , $out.ToArray()
}

# Get-Payload ITEMS - the files under those top-level repo items, as paths
# relative to the repo root with / separators (whichever OS this runs on),
# without tests and demo.ps1.
function Get-Payload {
    param([string[]]$Items)
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($item in $Items) {
        $p = Join-Path $RepoPath $item
        if (Test-Path -LiteralPath $p -PathType Leaf) { $list.Add($item) }
        elseif (Test-Path -LiteralPath $p -PathType Container) {
            foreach ($f in Get-ChildItem -LiteralPath $p -Recurse -File) {
                $rel = $f.FullName.Substring($RepoPath.Length + 1) -replace '\\', '/'
                if ($rel -match '(^|/)tests(/|$)' -or $rel -match '(^|/)demo\.ps1$') { continue }
                $list.Add($rel)
            }
        }
    }
    , $list
}

$sha = [System.Security.Cryptography.SHA256]::Create()
$script:converted = [System.Collections.Generic.HashSet[string]]::new()

# Get-Sha256 BYTES - their SHA-256 as hex.
function Get-Sha256 {
    param([byte[]]$Bytes)
    [System.BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-', ''
}

# Publish-Tree DEST FILES [EXTRA] - write FILES (repo-relative) under DEST as
# LF, skip those already identical, remove what DEST holds beyond FILES and
# the EXTRA names (relative to DEST, each with its content). Returns how many
# files it wrote or removed.
function Publish-Tree {
    param([string]$Dest, [System.Collections.Generic.List[string]]$Files, [hashtable]$Extra = @{})
    $changed = 0
    $content = [ordered]@{}
    foreach ($rel in $Files) {
        $raw = [System.IO.File]::ReadAllBytes((Join-Path $RepoPath $rel))
        $bytes = ConvertTo-LfByte $raw
        if ($bytes.Length -ne $raw.Length) { [void]$script:converted.Add($rel) }
        $content[$rel] = $bytes
    }
    foreach ($name in $Extra.Keys) { $content[$name] = [System.Text.Encoding]::UTF8.GetBytes($Extra[$name]) }

    foreach ($rel in $content.Keys) {
        $bytes = $content[$rel]
        $to = Join-Path $Dest $rel
        # Hashed here rather than with Get-FileHash: in Windows PowerShell 5.1
        # that is a script function which returns nothing while -WhatIf is in
        # effect for the session - as it is when this runs with
        # powershell.exe -File ... -WhatIf (measured in the lab, 2026-10-03).
        if ((Test-Path -LiteralPath $to) -and
            (Get-Sha256 ([System.IO.File]::ReadAllBytes($to))) -eq (Get-Sha256 $bytes)) { continue }
        if ($PSCmdlet.ShouldProcess($to, 'write')) {
            $dir = Split-Path -Parent $to
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllBytes($to, $bytes)
        }
        Write-Host "  write    $rel"
        $changed++
    }

    if (Test-Path -LiteralPath $Dest) {
        $keep = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($rel in $content.Keys) { [void]$keep.Add($rel) }
        foreach ($f in Get-ChildItem -LiteralPath $Dest -Recurse -File -Force) {
            $rel = $f.FullName.Substring($Dest.Length + 1) -replace '\\', '/'
            if ($keep.Contains($rel)) { continue }
            if ($PSCmdlet.ShouldProcess($f.FullName, 'remove (no longer in the repo)')) { Remove-Item -LiteralPath $f.FullName -Force }
            Write-Host "  remove   $rel"
            $changed++
        }
    }
    $changed
}

# NETLOGON is shared with every other logon script: refuse a MOTD folder
# there that this script did not create, before anything is written.
if ((Test-Path -LiteralPath $netlogon) -and -not (Test-Path -LiteralPath (Join-Path $netlogon $markName)) -and
    @(Get-ChildItem -LiteralPath $netlogon -Recurse -File -Force).Count) {
    throw "$netlogon already holds files and was not created by this script (no $markName in it); this run would remove them. Pass -NetlogonPath to publish the Windows copy somewhere else."
}

Write-Host "$sysvolMotd (Ubuntu hosts, through ADSys):"
$ubuntuChanged = Publish-Tree -Dest $sysvolMotd -Files (Get-Payload 'install.sh', 'adsys-startup.sh', 'README.md', 'rootfs', 'windows')
Write-Host "$netlogon (Windows hosts, the GPO's scheduled task):"
$windowsChanged = Publish-Tree -Dest $netlogon -Files (Get-Payload 'README.md', 'rootfs', 'windows') -Extra @{ $markName = $markText }

if ($script:converted.Count) {
    Write-Host "$($script:converted.Count) file(s) in $RepoPath have CRLF line endings (Git core.autocrlf); they are published as LF."
}

if ($windowsChanged -eq 0) {
    Write-Host "NETLOGON already matches $RepoPath."
} elseif ($WhatIfPreference) {
    Write-Host "$windowsChanged file change(s) would be published to $netlogon."
} else {
    Write-Host "$windowsChanged file change(s) published to $netlogon."
}

if ($ubuntuChanged -eq 0) {
    Write-Host "SYSVOL already matches $RepoPath; GPT.INI left as it is."
} else {
    $text = [System.IO.File]::ReadAllText($ini)
    $m = [regex]::Match($text, '(?im)^Version=(\d+)')
    if (-not $m.Success) { throw "$ini has no Version= line; bump it by hand so ADSys downloads again" }
    $new = [int]$m.Groups[1].Value + 1
    if ($PSCmdlet.ShouldProcess($ini, "Version $($m.Groups[1].Value) -> $new")) {
        [System.IO.File]::WriteAllText($ini, ($text -replace '(?im)^Version=\d+', "Version=$new"))
        Write-Host "$ubuntuChanged file change(s) published to $sysvolMotd; Ubuntu assets Version=$new."
    } else {
        Write-Host "$ubuntuChanged file change(s) would be published to $sysvolMotd, and Ubuntu assets Version=$new."
    }
}
if ($SkipGpo) { return }

# 5. The GPO. Every read and write goes to the PDC emulator, the DC the
#    GroupPolicy cmdlets use when given no -Server, so the AD object and its
#    SYSVOL folder are read and written in one place.
Import-Module GroupPolicy
Import-Module (Join-Path $PSScriptRoot 'ManatechMotdGpo.psm1') -Force
$taskName = 'Manatech MOTD sync'
$syncScript = if ($netlogon.StartsWith('\\') -and $NetlogonPath) { "$netlogon\windows\Sync-ManatechBanner.ps1" } else { "\\$Domain\NETLOGON\MOTD\windows\Sync-ManatechBanner.ps1" }
$key = 'HKLM\Software\Policies\Ubuntu\scripts\startup'
$wanted = [ordered]@{
    metaValues = @{ Type = 'String'; Value = (Get-MotdStartupMeta) }
    all        = @{ Type = 'MultiString'; Value = @('MOTD/adsys-startup.sh') }
}
$domainDn = 'DC=' + (($Domain -split '\.') -join ',DC=')
$pdc = [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain(
    [System.DirectoryServices.ActiveDirectory.DirectoryContext]::new('Domain', $Domain)).PdcRoleOwner.Name
$gp = @{ Domain = $Domain; Server = $pdc }

# Get-StartupValue - every value the GPO holds under the ADSys startup key,
# as name -> @{ Type; Value }.
function Get-StartupValue {
    $state = @{}
    foreach ($v in @(Get-GPRegistryValue -Guid $gpo.Id @gp -Key $key -ErrorAction SilentlyContinue)) {
        if ($v.ValueName) { $state[$v.ValueName] = @{ Type = [string]$v.Type; Value = $v.Value } }
    }
    $state
}
# Get-GpoEntry - the GPO's object in AD, read fresh (the cmdlets above may
# have just changed it).
function Get-GpoEntry { [adsi]"LDAP://$pdc/CN=$gpoGuid,CN=Policies,CN=System,$domainDn" }

Write-Host "GPO '$GpoName' (on $pdc):"
$found = @(Get-GPO -All @gp | Where-Object { $_.DisplayName -eq $GpoName })
if ($found.Count -gt 1) {
    throw "$($found.Count) GPOs are named '$GpoName' ($(($found | ForEach-Object { $_.Id }) -join ', ')): rename or delete the extra ones in GPMC, then publish again."
}
$gpo = if ($found.Count) { $found[0] } else { $null }
$existed = $null -ne $gpo
if (-not $gpo) {
    if ($PSCmdlet.ShouldProcess($GpoName, 'create the GPO')) {
        $gpo = New-GPO -Name $GpoName @gp -Comment 'Manatech login banner: the ADSys startup script for Ubuntu, the scheduled task for Windows Server. Written by windows/Publish-ManatechMotd.ps1 (Manatech-MOTD); a publish overwrites changes made in GPMC.'
    }
    Write-Host '  create   the GPO'
}
if (-not $gpo -and -not $WhatIfPreference) { return }
$gpoGuid = if ($gpo) { $gpo.Id.ToString('B').ToUpperInvariant() } else { $null }
$gpoFolder = if ($gpo) { "\\$pdc\SYSVOL\$Domain\Policies\$gpoGuid" } else { $null }
$tasksFile = if ($gpo) { Join-Path $gpoFolder 'Machine\Preferences\ScheduledTasks\ScheduledTasks.xml' } else { $null }

# What this publish would change, worked out before anything is written.
$valueChanges = @(Get-MotdStartupChange -Current $(if ($existed) { Get-StartupValue } else { @{} }) -Wanted $wanted)
$tasksText = if ($tasksFile -and (Test-Path -LiteralPath $tasksFile)) { [System.IO.File]::ReadAllText($tasksFile) } else { $null }
$tasks = New-MotdScheduledTasksXml -Existing $tasksText -TaskName $taskName -ScriptPath $syncScript
$tasksSame = Test-MotdGppXmlSame -Existing $tasksText -Desired $tasks.Xml

if ($existed) {
    $overwrite = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $valueChanges) {
        $was = if ($c.Old) { "'$($c.Old)'" } else { '(not set)' }
        if ($c.Action -eq 'remove') { $overwrite.Add("startup value $($c.Name): $was -> removed") }
        else { $overwrite.Add("startup value $($c.Name): $was -> '$($c.New)'") }
    }
    if (-not $tasksSame) {
        if ($tasks.RootWasDisabled) { $overwrite.Add('Scheduled Tasks: switched off for every item (disabled="1") -> on') }
        if (-not $tasks.Replaced.Count) { $overwrite.Add("task '$taskName': (none) -> added") }
        for ($i = 0; $i -lt $tasks.Replaced.Count; $i++) {
            $r = $tasks.Replaced[$i]
            if ($i -gt 0) { $overwrite.Add("task '$($r.Name)': a further $($r.Item) item for the same task (uid $($r.Uid)) -> removed"); continue }
            $diff = @(Compare-MotdTaskField -Old $r.Fields -New $tasks.Fields)
            if ($diff.Count) { foreach ($d in $diff) { $overwrite.Add("task '$($r.Name)' $d") } }
            else { $overwrite.Add("task '$($r.Name)': same account, program and triggers; the rest of the item (uid, settings) -> the repo's") }
        }
    }
    if ($overwrite.Count) {
        $verb = if ($WhatIfPreference) { 'would overwrite' } else { 'overwrites' }
        Write-Warning "GPO '$GpoName' already exists (id $($gpo.Id)); this publish $verb its settings with the repo's:"
        foreach ($o in $overwrite) { Write-Warning "  $o" }
    }
    $report = ConvertFrom-MotdGpoReport -Xml (Get-GPOReport -Guid $gpo.Id -ReportType Xml @gp)
    $others = @($report.Areas | Where-Object { $_ -notin 'Computer: Registry', 'Computer: Scheduled Tasks' }) +
        @($tasks.Kept | ForEach-Object { "Computer: Scheduled Tasks, item $_" })
    if ($others.Count) {
        # A warning beside an overwrite, so the two are read together; on a
        # publish that changes nothing, only a note.
        $line = "GPO '$GpoName' also holds settings this publish does not manage, left as they are: $($others -join '; ')"
        if ($overwrite.Count) { Write-Warning $line } else { Write-Host "  note     $line" }
    }
}

# The ADSys startup values. Set-/Remove-GPRegistryValue bump the GPO version
# themselves.
foreach ($c in $valueChanges) {
    if ($c.Action -eq 'remove') {
        if ($PSCmdlet.ShouldProcess($GpoName, "remove startup value $($c.Name)")) {
            Remove-GPRegistryValue -Guid $gpo.Id @gp -Key $key -ValueName $c.Name | Out-Null
        }
        Write-Host "  remove   startup value $($c.Name)"
    } else {
        if ($PSCmdlet.ShouldProcess($GpoName, "startup value $($c.Name) = $($c.New)")) {
            Set-GPRegistryValue -Guid $gpo.Id @gp -Key $key -ValueName $c.Name -Type $c.Type -Value $c.Value | Out-Null
        }
        Write-Host "  value    $($c.Name) = $($c.New)"
    }
}

# The scheduled task: ScheduledTasks.xml, the extension that makes clients
# read it, and the version bump that makes them read it again.
$bump = $false
if (-not $tasksSame) {
    if ($PSCmdlet.ShouldProcess($(if ($tasksFile) { $tasksFile } else { 'ScheduledTasks.xml' }), 'write')) {
        $dir = Split-Path -Parent $tasksFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($tasksFile, $tasks.Xml)
        $bump = $true
    } else {
        Write-Host "---- ScheduledTasks.xml this publish would write ----`n$($tasks.Xml)---- end ----"
    }
    Write-Host "  task     $taskName - $($tasks.Fields.Command) $($tasks.Fields.Arguments); $($tasks.Fields.Triggers); limit $($tasks.Fields.TimeLimit)"
}
$extDiffers = -not $gpo
if ($gpo) {
    $entry = Get-GpoEntry
    $ext = [string]$entry.Properties['gPCMachineExtensionNames'].Value
    $merged = Merge-MotdTaskExtension -Existing $ext
    $extDiffers = $merged -cne $ext
    if ($extDiffers) {
        if ($PSCmdlet.ShouldProcess($GpoName, "gPCMachineExtensionNames = $merged")) {
            $entry.Properties['gPCMachineExtensionNames'].Value = $merged
            $entry.CommitChanges()
            $bump = $true
        }
    }
}
if ($extDiffers) { Write-Host '  register the Scheduled Tasks extension on the GPO' }
if (-not $bump -and $WhatIfPreference -and (-not $tasksSame -or $extDiffers)) { Write-Host '  version  +1 (AD and GPT.INI)' }
if ($bump) {
    # AD first, then GPT.INI, to the same number: clients compare the AD one,
    # and GPMC reports a mismatch while the two differ.
    $entry = Get-GpoEntry
    $was = [long]$entry.Properties['versionNumber'].Value
    $next = Step-MotdGpoVersion -Version $was
    $gptIni = Join-Path $gpoFolder 'GPT.INI'
    $entry.Properties['versionNumber'].Value = [int]$next
    $entry.CommitChanges()
    $gptText = if (Test-Path -LiteralPath $gptIni) { [System.IO.File]::ReadAllText($gptIni) } else { '' }
    [System.IO.File]::WriteAllText($gptIni, (Get-MotdGptIniText -Content $gptText -Version $next))
    Write-Host "  version  $was -> $next (AD and GPT.INI)"
}
if ($existed -and -not $valueChanges.Count -and $tasksSame -and -not $extDiffers) { Write-Host '  settings already match the repo' }

# 6. Links.
# Get-GpoLink TARGET - this GPO's link at TARGET (GpoId, Enabled, ...), or $null.
function Get-GpoLink {
    param([string]$Target)
    if (-not $gpo) { return $null }
    @((Get-GPInheritance -Target $Target @gp).GpoLinks | Where-Object { $_.GpoId -eq $gpo.Id }) | Select-Object -First 1
}
foreach ($t in @($LinkTarget | Where-Object { $_ })) {
    $link = Get-GpoLink $t
    if (-not $link) {
        if ($PSCmdlet.ShouldProcess($t, "link '$GpoName'")) { New-GPLink -Guid $gpo.Id -Target $t @gp -LinkEnabled Yes | Out-Null }
        Write-Host "  link     $t"
    } elseif (-not $link.Enabled) {
        Write-Warning "GPO '$GpoName': its link at $t is disabled; -LinkTarget names it, so $(if ($WhatIfPreference) { 'it would be enabled' } else { 'it is enabled' })."
        if ($PSCmdlet.ShouldProcess($t, "enable the link of '$GpoName'")) { Set-GPLink -Guid $gpo.Id -Target $t @gp -LinkEnabled Yes | Out-Null }
        Write-Host "  link     $t (enabled)"
    }
}
if (-not @($LinkTarget | Where-Object { $_ }).Count) {
    $where = @(if ($existed) { $report.Links | ForEach-Object { $_.Path + $(if (-not $_.Enabled) { ' (link disabled)' } else { '' }) } })
    if ($where.Count) { Write-Host "  links    $($where -join '; ') (left as they are)" }
    else { Write-Warning "GPO '$GpoName' is linked nowhere, so no host applies it. Link it where the Ubuntu and Windows servers are, in GPMC or with -LinkTarget '<OU DN>' (several allowed)." }
}
if ($WhatIfPreference) { return }

# 7. Read it all back.
$checks = [System.Collections.Generic.List[object]]::new()
$checks.Add([pscustomobject]@{ Check = 'startup values: metaValues (append, every release) and all = MOTD/adsys-startup.sh, nothing else'; Pass = (@(Get-MotdStartupChange -Current (Get-StartupValue) -Wanted $wanted).Count -eq 0) })
$nowTasks = if (Test-Path -LiteralPath $tasksFile) { [System.IO.File]::ReadAllText($tasksFile) } else { $null }
$checks.Add([pscustomobject]@{ Check = "task '$taskName' running $syncScript"; Pass = (Test-MotdGppXmlSame -Existing $nowTasks -Desired $tasks.Xml) })
$entry = Get-GpoEntry
$ext = [string]$entry.Properties['gPCMachineExtensionNames'].Value
$checks.Add([pscustomobject]@{ Check = 'Scheduled Tasks extension registered'; Pass = ((Merge-MotdTaskExtension -Existing $ext) -ceq $ext) })
$adVersion = [long]$entry.Properties['versionNumber'].Value
$iniMatch = [regex]::Match([System.IO.File]::ReadAllText((Join-Path $gpoFolder 'GPT.INI')), '(?im)^\s*Version\s*=\s*(\d+)')
$iniVersion = if ($iniMatch.Success) { [long]$iniMatch.Groups[1].Value } else { -1 }
$checks.Add([pscustomobject]@{ Check = "version in AD ($adVersion) = GPT.INI ($iniVersion)"; Pass = ($adVersion -eq $iniVersion) })
foreach ($t in @($LinkTarget | Where-Object { $_ })) {
    $link = Get-GpoLink $t
    $checks.Add([pscustomobject]@{ Check = "linked to $t, enabled"; Pass = ($null -ne $link -and $link.Enabled) })
}
foreach ($c in $checks) { Write-Host ("  {0,-4} {1}" -f $(if ($c.Pass) { 'ok' } else { 'FAIL' }), $c.Check) }
$failed = @($checks | Where-Object { -not $_.Pass })
if ($failed.Count) { throw "$($failed.Count) check(s) failed: $(($failed | ForEach-Object { $_.Check }) -join '; ')" }
