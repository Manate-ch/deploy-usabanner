# GpoDeploy.ps1 - Deploy-UsaBannerGPO's work (docs/DECISIONS.md, D13, D21, D23 and D29): the
# banner for every domain host, by one Group Policy object. What a run puts where, all of it
# on the PDC emulator, which the Group Policy cmdlets use when given no server:
#
#   +----------------------------------------+------------------------------------------+
#   | Where                                  | What                                     |
#   +----------------------------------------+------------------------------------------+
#   | \\<pdc>\NETLOGON\UsaBanner\            | for Windows servers: usabanner.json (the |
#   |                                        | package), UsaBanner\ (the module, whole) |
#   |                                        | and the mark .usabanner-gpo              |
#   | \\<pdc>\SYSVOL\<domain>\Ubuntu\        | for Ubuntu (ADSys): adsys-startup.sh,    |
#   |   scripts\UsaBanner\                   | usabanner.json, UsaBanner\ and the mark  |
#   | \\<pdc>\SYSVOL\<domain>\Ubuntu\GPT.INI | its Version= goes up by one when the     |
#   |                                        | Ubuntu copy changed: ADSys downloads     |
#   |                                        | again only when it moves                 |
#   | the GPO "UsaBanner" in AD and SYSVOL   | an ImmediateTaskV2 (servers), the ADSys  |
#   |                                        | startup values for Ubuntu, and the links |
#   |                                        | the admin names                          |
#   +----------------------------------------+------------------------------------------+
#
# A run works out everything it would do before it writes anything (the plan), so a refusal
# leaves the domain as it was; then it writes, files first and the policy last, so no host
# is told to run what is not there yet; then it reads it all back. Every touch of the domain
# is a one-job function in the first part of this file, and the tests answer for each of
# them; they cannot answer for the GroupPolicy cmdlets, which only Windows has. Four of them,
# Search-UsaBannerDirectory, Get-UsaBannerGpoAttribute, Set-UsaBannerGpoAttribute and
# Get-UsaBannerGpoLinkAt, are in GpoDeploy.Logged.ps1: PowerShell logs them whole at each
# import (docs/DECISIONS.md, D30).

# The staged module's folder name, in both copies. The runner finds the module and the
# package from its own place (windows\Sync-UsaBanner.ps1, linux\adsys-startup.sh), so this
# and the task's path move together.
$script:UsaGpoModuleFolder = 'UsaBanner'

#region ----- the domain, one job each -----

function Get-UsaBannerGpoModuleRoot {
    # Out: this module's own folder, what the run stages. The tests mock it with a folder of
    #      their own
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $script:UsaBannerRoot
}

function Import-UsaBannerGroupPolicy {
    # Out: nothing; the GroupPolicy module is loaded. Under PowerShell 7 it is Windows
    #      PowerShell's, and answers through the compatibility session
    # Why: kept out of -WhatIf, which Import-Module would report on
    [CmdletBinding()]
    param()
    $WhatIfPreference = $false
    try { Import-Module -Name GroupPolicy -ErrorAction Stop -WarningAction SilentlyContinue }
    catch { throw "UsaBanner: the GroupPolicy module did not load ($($_.Exception.Message)). Run this on a domain controller, or on a domain member that has the Group Policy Management tools." }
}

function Get-UsaBannerGpoDomain {
    # In:  the domain's DNS name; none for the domain of the computer this runs on
    # Out: @{ Name; Dn; Pdc }: its DNS name (lowercase), its distinguished name, and its PDC
    #      emulator
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Domain = '')
    $found = if ($Domain) {
        [System.DirectoryServices.ActiveDirectory.Domain]::GetDomain([System.DirectoryServices.ActiveDirectory.DirectoryContext]::new(
                [System.DirectoryServices.ActiveDirectory.DirectoryContextType]::Domain, $Domain))
    }
    else { [System.DirectoryServices.ActiveDirectory.Domain]::GetComputerDomain() }
    $name = $found.Name.ToLowerInvariant()
    [pscustomobject]@{ Name = $name; Dn = 'DC=' + (($name -split '\.') -join ',DC='); Pdc = $found.PdcRoleOwner.Name }
}

function Get-UsaBannerGpoPlace {
    <#
    .SYNOPSIS
    The paths a run stages files in and reads a GPO's from.
    .DESCRIPTION
    In:  the domain (Get-UsaBannerGpoDomain).
    Out: @{ Netlogon; Ubuntu; Policies; TaskScript }. The first three are on the
         PDC emulator, where the run reads and writes: NETLOGON\UsaBanner, the
         ADSys assets folder (SYSVOL\<domain>\Ubuntu) and SYSVOL's Policies. The
         task's script is the same file by the domain's name, not the PDC's:
         each server reads it from its own domain controller.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Domain)
    $stage = $script:UsaGpoStageName
    [pscustomobject]@{
        Netlogon   = "\\$($Domain.Pdc)\NETLOGON\$stage"
        Ubuntu     = "\\$($Domain.Pdc)\SYSVOL\$($Domain.Name)\Ubuntu"
        Policies   = "\\$($Domain.Pdc)\SYSVOL\$($Domain.Name)\Policies"
        TaskScript = "\\$($Domain.Name)\NETLOGON\$stage\$script:UsaGpoModuleFolder\windows\Sync-UsaBanner.ps1"
    }
}

function Find-UsaBannerGpo {
    # In:  the domain, and a GPO's display name
    # Out: a row for every GPO of that name, in any case: Guid ({...}, uppercase) and Name.
    #      AD does not keep display names apart, so there can be more than one
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Domain, [Parameter(Mandatory)][string]$Name)
    $filter = "(&(objectClass=groupPolicyContainer)(displayName=$(ConvertTo-UsaBannerLdapFilterValue -Value $Name)))"
    foreach ($found in @(Search-UsaBannerDirectory -Server $Domain.Pdc -BaseDn "CN=Policies,CN=System,$($Domain.Dn)" -Filter $filter -Scope OneLevel -Property 'cn', 'displayname')) {
        [pscustomobject]@{ Guid = ([string]$found['cn']).ToUpperInvariant(); Name = [string]$found['displayname'] }
    }
}

function Find-UsaBannerGpoWithTasks {
    # In:  the domain
    # Out: a row for every GPO that has the Scheduled Tasks extension registered: Guid and
    #      Name
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Domain)
    $filter = "(&(objectClass=groupPolicyContainer)(gPCMachineExtensionNames=*$(ConvertTo-UsaBannerLdapFilterValue -Value $script:UsaGpp.Cse)*))"
    foreach ($found in @(Search-UsaBannerDirectory -Server $Domain.Pdc -BaseDn "CN=Policies,CN=System,$($Domain.Dn)" -Filter $filter -Scope OneLevel -Property 'cn', 'displayname')) {
        [pscustomobject]@{ Guid = ([string]$found['cn']).ToUpperInvariant(); Name = [string]$found['displayname'] }
    }
}

function New-UsaBannerGpoObject {
    # In:  the domain, a display name and a comment
    # Out: nothing; the GPO exists. Find-UsaBannerGpo finds it again: under PowerShell 7 the
    #      object New-GPO returns is a copy
    # Why: -Confirm:$false, since the run asked already
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Domain,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Comment
    )
    $null = New-GPO -Name $Name -Domain $Domain.Name -Server $Domain.Pdc -Comment $Comment -Confirm:$false -ErrorAction Stop
}

function Get-UsaBannerGpoRegistryValue {
    # In:  the domain, a GPO's guid and a registry key (HKLM\Software\...)
    # Out: a row for each value the GPO holds under that key: Name, Type (String,
    #      MultiString, ...) and Value; nothing where the key is not there
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Domain,
        [Parameter(Mandatory)][string]$Guid,
        [Parameter(Mandatory)][string]$Key
    )
    foreach ($value in @(Get-GPRegistryValue -Guid $Guid -Domain $Domain.Name -Server $Domain.Pdc -Key $Key -ErrorAction SilentlyContinue)) {
        if ($value.ValueName) { [pscustomobject]@{ Name = [string]$value.ValueName; Type = [string]$value.Type; Value = $value.Value } }
    }
}

function Set-UsaBannerGpoRegistryValue {
    # In:  the domain, a GPO's guid, a registry key, a value's name and type, and the value
    # Out: nothing; the GPO holds it. Set-GPRegistryValue raises the GPO's version itself
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Domain,
        [Parameter(Mandatory)][string]$Guid,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)]$Value
    )
    $null = Set-GPRegistryValue -Guid $Guid -Domain $Domain.Name -Server $Domain.Pdc -Key $Key -ValueName $Name -Type $Type -Value $Value -Confirm:$false -ErrorAction Stop
}

function Remove-UsaBannerGpoRegistryValue {
    # In:  the domain, a GPO's guid, a registry key and a value's name
    # Out: nothing; the GPO holds no such value. Remove-GPRegistryValue raises the version
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Domain,
        [Parameter(Mandatory)][string]$Guid,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Name
    )
    $null = Remove-GPRegistryValue -Guid $Guid -Domain $Domain.Name -Server $Domain.Pdc -Key $Key -ValueName $Name -Confirm:$false -ErrorAction Stop
}

function Get-UsaBannerGpoLinkPlace {
    # In:  the domain, and a GPO's guid
    # Out: a row for every object in the domain that links it, the domain and its OUs: Dn and
    #      Enabled, read from their gPLink values on the PDC emulator
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Domain, [Parameter(Mandatory)][string]$Guid)
    $filter = "(gPLink=*$(ConvertTo-UsaBannerLdapFilterValue -Value $Guid)*)"
    foreach ($found in @(Search-UsaBannerDirectory -Server $Domain.Pdc -BaseDn $Domain.Dn -Filter $filter -Scope Subtree -Property 'distinguishedname', 'gplink' -PageSize 500)) {
        $state = Test-UsaBannerGpoLinkValue -GpLink ([string]$found['gplink']) -GpoGuid $Guid
        if ($state.Linked) { [pscustomobject]@{ Dn = [string]$found['distinguishedname']; Enabled = $state.Enabled } }
    }
}

function New-UsaBannerGpoLink {
    # In:  the domain, a GPO's guid and the distinguished name to link it at
    # Out: nothing; it is linked there, enabled
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Domain,
        [Parameter(Mandatory)][string]$Guid,
        [Parameter(Mandatory)][string]$TargetDn
    )
    $null = New-GPLink -Guid $Guid -Target $TargetDn -Domain $Domain.Name -Server $Domain.Pdc -LinkEnabled Yes -Confirm:$false -ErrorAction Stop
}

function Enable-UsaBannerGpoLink {
    # In:  the domain, a GPO's guid and the distinguished name it is linked at
    # Out: nothing; that link is enabled
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Domain,
        [Parameter(Mandatory)][string]$Guid,
        [Parameter(Mandatory)][string]$TargetDn
    )
    $null = Set-GPLink -Guid $Guid -Target $TargetDn -Domain $Domain.Name -Server $Domain.Pdc -LinkEnabled Yes -Confirm:$false -ErrorAction Stop
}

function Get-UsaBannerGpoReportXml {
    # In:  the domain, and a GPO's guid
    # Out: its Get-GPOReport, as XML text
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][psobject]$Domain, [Parameter(Mandatory)][string]$Guid)
    [string](Get-GPOReport -Guid $Guid -Domain $Domain.Name -Server $Domain.Pdc -ReportType Xml -ErrorAction Stop)
}

#endregion

#region ----- the files, on the share -----

function Get-UsaBannerGpoModuleFile {
    # In:  the module's folder
    # Out: a row for each file in it, in path order: Path (relative, with /), Bytes (each CRLF
    #      turned into LF, unless the file holds a NUL byte) and Converted
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $full = [System.IO.Path]::GetFullPath($Root).TrimEnd('/', '\')
    $paths = [string[]][System.IO.Directory]::GetFiles($full, '*', [System.IO.SearchOption]::AllDirectories)
    [array]::Sort($paths, [System.StringComparer]::Ordinal)
    foreach ($file in $paths) {
        $raw = [System.IO.File]::ReadAllBytes($file)
        $bytes = ConvertTo-UsaBannerGpoLfByte -Bytes $raw
        [pscustomobject]@{
            Path      = [System.IO.Path]::GetRelativePath($full, $file).Replace('\', '/')
            Bytes     = $bytes
            Converted = ($bytes.Length -ne $raw.Length)
        }
    }
}

function Get-UsaBannerGpoPayload {
    # In:  the OS the copy is for (windows or ubuntu), the package's bytes, the mark's bytes and
    #      the module's files (Get-UsaBannerGpoModuleFile)
    # Out: an ordered map of each file's path in the copy (with /) to its bytes. Both copies
    #      hold the package, the module folder and the mark; the Ubuntu one also the ADSys
    #      startup script, at its root, where ADSys's value points
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu')][string]$Os,
        [Parameter(Mandatory)][byte[]]$Package,
        [Parameter(Mandatory)][byte[]]$Mark,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Module
    )
    $payload = [ordered]@{}
    if ($Os -eq 'ubuntu') {
        $startup = @($Module | Where-Object { $_.Path -ceq 'linux/adsys-startup.sh' })
        if ($startup.Count -eq 0) { throw "UsaBanner: the module has no linux/adsys-startup.sh, which the Ubuntu copy needs. Nothing was written." }
        $payload['adsys-startup.sh'] = $startup[0].Bytes
    }
    $payload['usabanner.json'] = $Package
    foreach ($file in $Module) { $payload["$script:UsaGpoModuleFolder/$($file.Path)"] = $file.Bytes }
    $payload[$script:UsaGpoMarkName] = $Mark
    $payload
}

function Get-UsaBannerGpoTreePath {
    # In:  a copy's folder, and a file's path in it, with /
    # Out: the file's path on this OS
    param([Parameter(Mandatory)][string]$Folder, [Parameter(Mandatory)][string]$Relative)
    [System.IO.Path]::Combine($Folder, $Relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
}

function Get-UsaBannerGpoTreePlan {
    <#
    .SYNOPSIS
    What a copy's folder holds, against what it should.
    .DESCRIPTION
    In:  the folder on the share, and its payload (Get-UsaBannerGpoPayload).
    Out: @{ Path; Foreign; Write; Remove; Unfinished }. Write lists the
         payload's files that are missing or whose bytes differ; Remove the files
         the folder holds that are not in the payload. Foreign is true when the
         folder holds files and not the mark: it is someone else's, and nothing
         is removed from it (Remove is empty). Unfinished is true when a publish
         into it was cut short (it holds .usabanner-publishing, which neither
         counts as someone else's file nor is pruned: the run takes it away last).
    Reads only.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Payload
    )
    $held = @()
    if ([System.IO.Directory]::Exists($Path)) {
        $held = @([System.IO.Directory]::GetFiles($Path, '*', [System.IO.SearchOption]::AllDirectories) |
                ForEach-Object { [System.IO.Path]::GetRelativePath($Path, $_).Replace('\', '/') })
    }
    $unfinished = $script:UsaGpoPublishingName -in $held
    $held = @($held | Where-Object { $_ -ne $script:UsaGpoPublishingName })
    $foreign = $held.Count -gt 0 -and $script:UsaGpoMarkName -notin $held
    $write = @(foreach ($relative in $Payload.Keys) {
            $there = Get-UsaBannerGpoTreePath -Folder $Path -Relative $relative
            if (-not ([System.IO.File]::Exists($there) -and [System.Linq.Enumerable]::SequenceEqual([byte[]][System.IO.File]::ReadAllBytes($there), [byte[]]$Payload[$relative]))) { $relative }
        })
    $wanted = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Payload.Keys), [System.StringComparer]::OrdinalIgnoreCase)
    $remove = @(if (-not $foreign) { $held | Where-Object { -not $wanted.Contains($_) } })
    [pscustomobject]@{ Path = $Path; Foreign = $foreign; Write = $write; Remove = $remove; Unfinished = $unfinished }
}

function Write-UsaBannerGpoTree {
    # In:  a copy's folder, its payload and its plan (Get-UsaBannerGpoTreePlan)
    # Out: nothing; the folder holds the payload and nothing else
    # Why: each file is written beside itself and moved over the old one, so a host never
    #      reads half of it. A run cut short leaves a .usabanner-tmp file, which the next
    #      run removes with whatever else is not the payload
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Payload,
        [Parameter(Mandatory)][psobject]$Plan
    )
    foreach ($relative in $Plan.Write) {
        $full = Get-UsaBannerGpoTreePath -Folder $Path -Relative $relative
        $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($full))
        $temp = "$full.usabanner-tmp"
        [System.IO.File]::WriteAllBytes($temp, [byte[]]$Payload[$relative])
        [System.IO.File]::Move($temp, $full, $true)
    }
    foreach ($relative in $Plan.Remove) { [System.IO.File]::Delete((Get-UsaBannerGpoTreePath -Folder $Path -Relative $relative)) }
}

function Test-UsaBannerGpoTree {
    # In:  a copy's folder, and its payload
    # Out: what is wrong with the folder, a line each: a file missing, a file whose SHA-256
    #      differs from the payload's, a file that is not in the payload; nothing where the
    #      folder is the payload and nothing but
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Payload
    )
    foreach ($relative in $Payload.Keys) {
        $there = Get-UsaBannerGpoTreePath -Folder $Path -Relative $relative
        if (-not [System.IO.File]::Exists($there)) { "$relative is missing"; continue }
        if ((Get-FileHash -LiteralPath $there -Algorithm SHA256).Hash -ne (Get-UsaBannerSha256 -Bytes ([byte[]]$Payload[$relative]))) { "$relative differs" }
    }
    $wanted = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Payload.Keys), [System.StringComparer]::OrdinalIgnoreCase)
    if ([System.IO.Directory]::Exists($Path)) {
        foreach ($file in [System.IO.Directory]::GetFiles($Path, '*', [System.IO.SearchOption]::AllDirectories)) {
            $relative = [System.IO.Path]::GetRelativePath($Path, $file).Replace('\', '/')
            if (-not $wanted.Contains($relative)) { "$relative is not part of the payload" }
        }
    }
}

function Get-UsaBannerGpoFilePath {
    # In:  SYSVOL's Policies folder, a GPO's guid, and which file: Tasks (its
    #      Machine\Preferences\ScheduledTasks\ScheduledTasks.xml) or GptIni (its GPT.INI)
    # Out: the path; '' while there is no guid, the GPO not being made yet
    param(
        [Parameter(Mandatory)][string]$Policies,
        [AllowEmptyString()][string]$Guid,
        [Parameter(Mandatory)][ValidateSet('Tasks', 'GptIni')][string]$File
    )
    if (-not $Guid) { return '' }
    if ($File -eq 'GptIni') { [System.IO.Path]::Combine($Policies, $Guid, 'GPT.INI') }
    else { [System.IO.Path]::Combine($Policies, $Guid, 'Machine', 'Preferences', 'ScheduledTasks', 'ScheduledTasks.xml') }
}

#endregion

#region ----- the plan: reads only -----

function Get-UsaBannerGpoStagingPlan {
    <#
    .SYNOPSIS
    What staging would write, and a refusal before any of it is written.
    .DESCRIPTION
    In:  the run (Invoke-UsaBannerGpoDeploy keeps it).
    Out: nothing; the run holds the copies to stage, each with its payload and
         its plan. The Ubuntu copy is only there when the ADSys assets folder
         is (its GPT.INI): without it a warning says what to create, and the
         Windows half goes on.
    Throws, with nothing written, when a destination holds files and has no
    mark (it is someone else's: staging would remove them), and when the
    module's own folder is, or is inside, a destination.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Run)
    $root = Get-UsaBannerGpoModuleRoot
    $module = @(Get-UsaBannerGpoModuleFile -Root $root)
    $Run.Converted = @($module | Where-Object { $_.Converted }).Count
    $mark = [System.Text.UTF8Encoding]::new($false).GetBytes($script:UsaGpoMarkText)
    $place = $Run.Place
    $ini = [System.IO.Path]::Combine($place.Ubuntu, 'GPT.INI')
    $trees = [System.Collections.Generic.List[object]]::new()
    $trees.Add(@{ Os = 'windows'; Label = 'Windows hosts'; Path = $place.Netlogon })
    $Run.AdsysIni = ''
    $Run.AdsysVersion = -1
    if ([System.IO.File]::Exists($ini)) {
        $trees.Add(@{ Os = 'ubuntu'; Label = 'Ubuntu hosts'; Path = [System.IO.Path]::Combine($place.Ubuntu, 'scripts', $script:UsaGpoStageName) })
        $Run.AdsysIni = $ini
        $Run.AdsysVersion = Get-UsaBannerGpoGptIniVersion -Content ([System.IO.File]::ReadAllText($ini))
    }
    else {
        Write-Warning "UsaBanner: $ini is not there, so Ubuntu hosts get nothing from this GPO. ADSys downloads the Ubuntu folder of SYSVOL, and downloads it again only when the Version in its GPT.INI goes up. Make the folder, and a GPT.INI in it with the two lines [General] and Version=1, then run this again. The Windows half goes on without it."
    }
    foreach ($tree in $trees) {
        if (Test-UsaBannerGpoPathInside -Path $root -Folder $tree.Path) {
            throw "UsaBanner: the module this runs from, $root, is $($tree.Path) or inside it, so staging would copy it onto itself. Run it from a copy of the module somewhere else. Nothing was written."
        }
        $tree.Payload = Get-UsaBannerGpoPayload -Os $tree.Os -Package $Run.Package -Mark $mark -Module $module
        $tree.Plan = Get-UsaBannerGpoTreePlan -Path $tree.Path -Payload $tree.Payload
        if ($tree.Plan.Foreign) {
            throw "UsaBanner: $($tree.Path) already holds files, and it has no $script:UsaGpoMarkName in it, so this command did not make it: staging would remove what it does not recognise. Nothing was written. Move those files, or if all of them may go, put an empty file named $script:UsaGpoMarkName in the folder, and run this again."
        }
        $tree.Changed = $false
        $tree.WouldChange = $false
    }
    $Run.Trees = $trees
}

function Get-UsaBannerGpoSettingsPlan {
    <#
    .SYNOPSIS
    What the GPO would be made to hold, and a refusal before any of it is
    written.
    .DESCRIPTION
    In:  the run.
    Out: nothing; the run holds the GPO (found by its name, or not there yet),
         the ScheduledTasks.xml to write and whether the file has it already,
         and the ADSys startup values to set and remove.
    Throws, with nothing written, when more than one GPO has the name, and
    when the GPO's ScheduledTasks.xml is not a file this can merge into.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Run)
    $ctx = $Run.Domain
    $found = @(Find-UsaBannerGpo -Domain $ctx -Name $Run.Name)
    if ($found.Count -gt 1) {
        throw "UsaBanner: $($found.Count) GPOs are named '$($Run.Name)' ($(($found | ForEach-Object { $_.Guid }) -join ', ')). Rename or delete the extra ones in GPMC, then run this again. Nothing was written."
    }
    $Run.Existed = $found.Count -eq 1
    $Run.Guid = if ($Run.Existed) { [string]$found[0].Guid } else { '' }

    $tasksFile = Get-UsaBannerGpoFilePath -Policies $Run.Place.Policies -Guid $Run.Guid -File Tasks
    $tasksText = if ($tasksFile -and [System.IO.File]::Exists($tasksFile)) { [System.IO.File]::ReadAllText($tasksFile) } else { $null }
    try { $Run.Tasks = New-UsaBannerGpoTasksXml -Existing $tasksText -TaskName $script:UsaGpoTaskName -Arguments (Get-UsaBannerGpoTaskArgument -ScriptPath $Run.Place.TaskScript) }
    catch { throw "$($_.Exception.Message) The file: $tasksFile. Nothing was written." }
    $Run.TasksSame = Test-UsaBannerGppXmlSame -Existing $tasksText -Desired $Run.Tasks.Xml

    $Run.Wanted = [ordered]@{
        metaValues = @{ Type = 'String'; Value = (Get-UsaBannerGpoStartupMeta) }
        all        = @{ Type = 'MultiString'; Value = @($script:UsaGpoStartupScript) }
    }
    $Run.ValueChanges = @()
    if ($Run.AdsysIni) {
        $current = @{}
        if ($Run.Guid) {
            foreach ($value in @(Get-UsaBannerGpoRegistryValue -Domain $ctx -Guid $Run.Guid -Key $script:UsaGpoStartupKey)) {
                $current[$value.Name] = @{ Type = $value.Type; Value = $value.Value }
            }
        }
        $Run.ValueChanges = @(Get-UsaBannerGpoStartupChange -Current $current -Wanted $Run.Wanted)
    }
    $Run.Flags = if ($Run.Guid) { [int](Get-UsaBannerGpoAttribute -Domain $ctx -Guid $Run.Guid -Name 'flags') } else { 0 }
}

function Write-UsaBannerGpoOverwriteWarning {
    <#
    .SYNOPSIS
    For a GPO that exists already: what this run changes in it, old and new,
    and what else it holds.
    .DESCRIPTION
    In:  the run, planned (Get-UsaBannerGpoSettingsPlan).
    Out: nothing; before anything is changed, one warning lists each setting
    the GPO holds otherwise than the run will leave it: the startup values,
    the task, the computer settings switched off. Another lists what else it
    holds, which is left as it is (the report's areas other than Computer:
    Registry and Computer: Scheduled Tasks, and the task items kept); with no
    overwrite beside it, that one is only a note. A GPO the run changes
    nothing in gets neither warning.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Run)
    if (-not $Run.Existed) { return }
    $overwrite = [System.Collections.Generic.List[string]]::new()
    foreach ($change in $Run.ValueChanges) {
        $was = if ($change.Old) { "'$($change.Old)'" } else { '(not set)' }
        if ($change.Action -eq 'remove') { $overwrite.Add("startup value $($change.Name): $was -> removed") }
        else { $overwrite.Add("startup value $($change.Name): $was -> '$($change.New)'") }
    }
    $tasks = $Run.Tasks
    if (-not $Run.TasksSame) {
        if ($tasks.RootWasDisabled) { $overwrite.Add('Scheduled Tasks: every item switched off (disabled="1") -> on') }
        if (-not $tasks.Replaced.Count) { $overwrite.Add("task '$script:UsaGpoTaskName': (none) -> added") }
        for ($i = 0; $i -lt $tasks.Replaced.Count; $i++) {
            $replaced = $tasks.Replaced[$i]
            if ($i -gt 0) { $overwrite.Add("task '$($replaced.Name)': a further $($replaced.Item) item for the same task (uid $($replaced.Uid)) -> removed"); continue }
            $diff = @(Compare-UsaBannerGpoTaskField -Old $replaced.Fields -New $tasks.Fields)
            if ($diff.Count) { foreach ($d in $diff) { $overwrite.Add("task '$($replaced.Name)' $d") } }
            else { $overwrite.Add("task '$($replaced.Name)': same account, program, arguments and target; the rest of the item (uid, settings) -> the module's") }
        }
    }
    if (($Run.Flags -band 2) -ne 0) { $overwrite.Add('computer settings: disabled -> enabled') }
    if ($overwrite.Count) {
        $verb = if ($WhatIfPreference) { 'would overwrite' } else { 'overwrites' }
        Write-Warning "UsaBanner: the GPO '$($Run.Name)' exists already (id $($Run.Guid)); this run $verb these of its settings with the module's:"
        foreach ($line in $overwrite) { Write-Warning "  $line" }
    }
    $areas = @()
    try { $areas = @(ConvertFrom-UsaBannerGpoReport -Xml (Get-UsaBannerGpoReportXml -Domain $Run.Domain -Guid $Run.Guid)) }
    catch { Write-Information -MessageData "  note: the report of the GPO '$($Run.Name)' could not be read ($($_.Exception.Message)), so other settings it may hold are not listed" -InformationAction Continue }
    $others = @($areas | Where-Object { $_ -notin 'Computer: Registry', 'Computer: Scheduled Tasks' }) + @($tasks.Kept | ForEach-Object { "Computer: Scheduled Tasks, item $_" })
    if ($others.Count) {
        $line = "the GPO '$($Run.Name)' also holds settings this run does not manage, left as they are: $($others -join '; ')"
        if ($overwrite.Count) { Write-Warning "UsaBanner: $line" } else { Write-Information -MessageData "  note: $line" -InformationAction Continue }
    }
}

#endregion

#region ----- the writes: files first, the policy last -----

function Invoke-UsaBannerGpoStaging {
    <#
    .SYNOPSIS
    Writes the copies to NETLOGON and SYSVOL.
    .DESCRIPTION
    In:  the run, planned.
    Out: a line for each copy written, and one for the Ubuntu GPT.INI. Each
    copy is written file by file where a file's bytes differ, and pruned of
    what is not the payload. When anything in the Ubuntu copy changed, the
    Version in its GPT.INI goes up by one, after every file is written: ADSys
    downloads again only when it moves.
    A copy gets .usabanner-publishing before its first file, and loses it once
    it is done: the Windows one after its files, the Ubuntu one after the
    Version is raised. A run cut short anywhere between leaves it, and the next
    run then raises the Version even where every file is current.
    Under -WhatIf nothing is written, and the raise is shown as well wherever
    the Ubuntu copy would be written.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$Run)
    foreach ($tree in $Run.Trees) {
        $count = $tree.Plan.Write.Count
        $gone = $tree.Plan.Remove.Count
        if ($count -eq 0 -and $gone -eq 0 -and -not $tree.Plan.Unfinished) { continue }
        $finish = if ($tree.Plan.Unfinished) { '; the last publish here was cut short, and this one finishes it' } else { '' }
        if ($PSCmdlet.ShouldProcess($tree.Path, "Stage the banner for $($tree.Label): $count file(s) to write, $gone to remove$finish")) {
            $flag = Get-UsaBannerGpoTreePath -Folder $tree.Path -Relative $script:UsaGpoPublishingName
            $null = [System.IO.Directory]::CreateDirectory($tree.Path)
            [System.IO.File]::WriteAllText($flag, "A publish by Deploy-UsaBannerGPO started here at $([datetime]::UtcNow.ToString('u', [cultureinfo]::InvariantCulture)); it takes this file away when it is done.`n")
            Write-UsaBannerGpoTree -Path $tree.Path -Payload $tree.Payload -Plan $tree.Plan
            # The Windows copy is done here; the Ubuntu one once its Version is raised, below.
            if ($tree.Os -ne 'ubuntu') { [System.IO.File]::Delete($flag) }
            $tree.Changed = $true
            "staged $($tree.Path) for $($tree.Label): $count file(s) written, $gone removed$finish"
        }
        # -WhatIf writes nothing, so a copy it would write is marked for the Version raise below to be shown.
        elseif ($WhatIfPreference) { $tree.WouldChange = $true }
    }
    if ($Run.Converted -and @($Run.Trees | Where-Object { $_.Changed }).Count) {
        "$($Run.Converted) file(s) of the module have CRLF line endings in this clone (Git for Windows' core.autocrlf); they are staged as LF"
    }
    $ubuntu = @($Run.Trees | Where-Object { $_.Os -eq 'ubuntu' -and ($_.Changed -or $_.WouldChange) })
    if ($ubuntu.Count) {
        $text = [System.IO.File]::ReadAllText($Run.AdsysIni)
        $was = [math]::Max(0, (Get-UsaBannerGpoGptIniVersion -Content $text))
        $next = $was + 1
        if ($PSCmdlet.ShouldProcess($Run.AdsysIni, "Raise the Version from $was to ${next}, so that ADSys downloads the Ubuntu folder again")) {
            [System.IO.File]::WriteAllText($Run.AdsysIni, (Get-UsaBannerGpoGptIniText -Content $text -Version $next))
            # The Ubuntu copy is done: ADSys will download it.
            [System.IO.File]::Delete((Get-UsaBannerGpoTreePath -Folder $ubuntu[0].Path -Relative $script:UsaGpoPublishingName))
            $Run.AdsysVersion = $next
            "raised the Version in $($Run.AdsysIni) from $was to ${next}: ADSys downloads the Ubuntu folder again"
        }
    }
}

function Invoke-UsaBannerGpoSettings {
    <#
    .SYNOPSIS
    Makes the GPO hold the startup values, the task and the extension that
    runs it, with the computer settings on.
    .DESCRIPTION
    In:  the run, planned.
    Out: a line for each change. The GPO is made when no GPO has the name. The
    ADSys startup values come first (Set-GPRegistryValue raises the version
    itself and registers its own extension), then ScheduledTasks.xml, then the
    extension list, read again after the cmdlets, then the computer settings;
    the version goes up by one, AD first and then GPT.INI, when the file or
    the extension changed. Under -WhatIf the ScheduledTasks.xml it would write
    is shown on the information stream, and the version raise is shown where
    the file or the extension would change.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$Run)
    $ctx = $Run.Domain
    $name = $Run.Name
    if (-not $Run.Existed -and $PSCmdlet.ShouldProcess($name, 'Make the GPO')) {
        New-UsaBannerGpoObject -Domain $ctx -Name $name -Comment $script:UsaGpoComment
        # Found again over LDAP: under PowerShell 7 the object New-GPO returns is a copy.
        $made = @(Find-UsaBannerGpo -Domain $ctx -Name $name)
        if ($made.Count -ne 1) { throw "UsaBanner: New-GPO '$name' returned, but $($ctx.Pdc) holds $($made.Count) GPO(s) of that name." }
        $Run.Guid = [string]$made[0].Guid
        "made the GPO '$name' (id $($Run.Guid))"
    }
    # A GPO that was not made (-Confirm said no) has nothing to put settings in; under -WhatIf
    # the steps below only say what they would do.
    if (-not $Run.Guid -and -not $WhatIfPreference) { return }
    $guid = $Run.Guid
    $tasksFile = Get-UsaBannerGpoFilePath -Policies $Run.Place.Policies -Guid $guid -File Tasks
    $key = $script:UsaGpoStartupKey

    foreach ($change in $Run.ValueChanges) {
        if ($change.Action -eq 'remove') {
            if ($PSCmdlet.ShouldProcess($name, "Remove the startup value $($change.Name)")) {
                Remove-UsaBannerGpoRegistryValue -Domain $ctx -Guid $guid -Key $key -Name $change.Name
                "removed the startup value $($change.Name) (it held '$($change.Old)')"
            }
        }
        elseif ($PSCmdlet.ShouldProcess($name, "Set the startup value $($change.Name) = $($change.New)")) {
            Set-UsaBannerGpoRegistryValue -Domain $ctx -Guid $guid -Key $key -Name $change.Name -Type $change.Type -Value $change.Value
            "set the startup value $($change.Name) = $($change.New)"
        }
    }

    $bump = $false
    if (-not $Run.TasksSame) {
        $shown = if ($tasksFile) { $tasksFile } else { "ScheduledTasks.xml of the GPO '$name'" }
        if ($PSCmdlet.ShouldProcess($shown, "Write the task '$script:UsaGpoTaskName': an immediate task that runs the banner's runner on servers only")) {
            $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($tasksFile))
            [System.IO.File]::WriteAllText($tasksFile, $Run.Tasks.Xml)
            $bump = $true
            "wrote ${tasksFile}: the task '$script:UsaGpoTaskName', an immediate task that runs $($Run.Place.TaskScript) as SYSTEM at each policy refresh, on servers only ($($Run.Tasks.Fields.Filters))"
        }
        else { Write-Information -MessageData "---- ScheduledTasks.xml this run would write ----`n$($Run.Tasks.Xml)---- end ----" -InformationAction Continue }
    }

    # Read now, not at the plan: Set-GPRegistryValue registers the Registry extension itself.
    $ext = if ($guid) { [string](Get-UsaBannerGpoAttribute -Domain $ctx -Guid $guid -Name 'gPCMachineExtensionNames') } else { '' }
    $merged = Merge-UsaBannerGpoTaskExtension -Existing $ext
    if ($merged -cne $ext -and $PSCmdlet.ShouldProcess($name, "Register the Scheduled Tasks extension: gPCMachineExtensionNames = $merged")) {
        Set-UsaBannerGpoAttribute -Domain $ctx -Guid $guid -Name 'gPCMachineExtensionNames' -Value $merged
        $bump = $true
        "registered the Scheduled Tasks extension on the GPO '$name': $merged"
    }

    $flags = if ($guid) { [int](Get-UsaBannerGpoAttribute -Domain $ctx -Guid $guid -Name 'flags') } else { 0 }
    if (($flags -band 2) -ne 0 -and $PSCmdlet.ShouldProcess($name, 'Switch the computer settings on')) {
        Set-UsaBannerGpoAttribute -Domain $ctx -Guid $guid -Name 'flags' -Value ([int]($flags -band (-bnot 2)))
        "switched on the computer settings of the GPO '$name'"
    }

    # -WhatIf writes neither the task file nor the extension, so the raise is shown where either would change.
    if ($WhatIfPreference -and (-not $Run.TasksSame -or $merged -cne $ext)) { $bump = $true }
    # AD first, then GPT.INI, to the same number: clients compare the AD one, and GPMC reports a
    # mismatch while the two differ.
    if ($bump -and $PSCmdlet.ShouldProcess($name, 'Raise the version by one, so that clients apply the GPO again')) {
        $was = [long](Get-UsaBannerGpoAttribute -Domain $ctx -Guid $guid -Name 'versionNumber')
        if ($was -lt 0) { $was += 4294967296 }
        $next = Step-UsaBannerGpoVersion -Version $was
        # versionNumber is a signed 32-bit attribute: a user half from 0x8000 up reads negative.
        Set-UsaBannerGpoAttribute -Domain $ctx -Guid $guid -Name 'versionNumber' -Value ([int]$(if ($next -gt [int]::MaxValue) { $next - 4294967296 } else { $next }))
        $gptIni = Get-UsaBannerGpoFilePath -Policies $Run.Place.Policies -Guid $guid -File GptIni
        $text = if ([System.IO.File]::Exists($gptIni)) { [System.IO.File]::ReadAllText($gptIni) } else { '' }
        [System.IO.File]::WriteAllText($gptIni, (Get-UsaBannerGpoGptIniText -Content $text -Version $next))
        "raised the version of the GPO '$name' from $was to $next (AD and GPT.INI)"
    }
}

function Invoke-UsaBannerGpoLinking {
    <#
    .SYNOPSIS
    Links the GPO where the admin said.
    .DESCRIPTION
    In:  the run.
    Out: a line for each link made or enabled. Each -LinkTarget gets a link; a
    disabled one is enabled, with a warning. Without -LinkTarget the links stay
    as they are: listed when there are some, and a warning when none is enabled.
    No link is made on the admin's behalf, not even at the domain root: a link
    is the admin's act.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$Run)
    if (-not $Run.Guid -and -not $WhatIfPreference) { return }
    $ctx = $Run.Domain
    $name = $Run.Name
    foreach ($target in $Run.Targets) {
        $link = if ($Run.Guid) { Get-UsaBannerGpoLinkAt -Domain $ctx -TargetDn $target -Guid $Run.Guid } else { $null }
        if ($link -and $link.Linked -and $link.Enabled) { continue }
        if ($link -and $link.Linked) {
            Write-Warning "UsaBanner: the link of the GPO '$name' at $target is disabled; -LinkTarget names it, so $(if ($WhatIfPreference) { 'it would be enabled' } else { 'it is enabled' })."
            if ($PSCmdlet.ShouldProcess($target, "Enable the link of '$name'")) {
                Enable-UsaBannerGpoLink -Domain $ctx -Guid $Run.Guid -TargetDn $target
                "enabled the link of the GPO '$name' at $target"
            }
        }
        elseif ($PSCmdlet.ShouldProcess($target, "Link '$name', enabled")) {
            New-UsaBannerGpoLink -Domain $ctx -Guid $Run.Guid -TargetDn $target
            "linked the GPO '$name' at $target, enabled"
        }
    }
    if ($Run.Targets.Count) { return }
    $places = @(if ($Run.Guid) { Get-UsaBannerGpoLinkPlace -Domain $ctx -Guid $Run.Guid })
    if ($places.Count) {
        $shown = ($places | ForEach-Object { $_.Dn + $(if (-not $_.Enabled) { ' (link disabled)' } else { '' }) }) -join '; '
        Write-Information -MessageData "  links of the GPO '$name', left as they are: $shown" -InformationAction Continue
    }
    if (-not @($places | Where-Object { $_.Enabled }).Count) {
        $why = if ($places.Count) { 'only by disabled links' } else { 'nowhere' }
        Write-Warning "UsaBanner: the GPO '$name' is linked $why, so no host applies it. Link it with -LinkTarget '<distinguished name>' (several are allowed), or in GPMC."
    }
}

#endregion

#region ----- the neighbours, and the read-back -----

function Write-UsaBannerGpoNeighbourWarning {
    <#
    .SYNOPSIS
    Warns of the two policies this one depends on or collides with.
    .DESCRIPTION
    In:  the run.
    Out: nothing; warnings only. Read from the GPOs that have the Scheduled
    Tasks extension (their ScheduledTasks.xml, from SYSVOL; one that cannot be
    read is skipped, with a note). Today's banner: a GPO with the task "Manatech
    MOTD sync" that an enabled link reaches undoes this one at each refresh.
    deploy-usawinssh: with no GPO that has its task "UsaDeploy-WinSsh" linked by
    an enabled link, a Windows server without PowerShell 7 gets no banner.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Run)
    $ctx = $Run.Domain
    $today = [System.Collections.Generic.List[object]]::new()
    $winssh = [System.Collections.Generic.List[string]]::new()
    foreach ($gpo in @(Find-UsaBannerGpoWithTasks -Domain $ctx)) {
        $file = Get-UsaBannerGpoFilePath -Policies $Run.Place.Policies -Guid $gpo.Guid -File Tasks
        if (-not [System.IO.File]::Exists($file)) { continue }
        try { $names = @(Get-UsaBannerGpoTaskItemName -Xml ([System.IO.File]::ReadAllText($file))) }
        catch {
            Write-Information -MessageData "  note: the ScheduledTasks.xml of the GPO '$($gpo.Name)' ($($gpo.Guid)) could not be read ($($_.Exception.Message)), so it is skipped when looking for today's banner and deploy-usawinssh" -InformationAction Continue
            continue
        }
        $isToday = $script:UsaOldGpoTask -in $names
        $isWinSsh = $script:UsaGpoWinSshTask -in $names
        if (-not ($isToday -or $isWinSsh)) { continue }
        $enabled = @(Get-UsaBannerGpoLinkPlace -Domain $ctx -Guid $gpo.Guid | Where-Object { $_.Enabled })
        if (-not $enabled.Count) { continue }
        if ($isToday) { $today.Add([pscustomobject]@{ Name = $gpo.Name; Guid = $gpo.Guid; Dn = @($enabled | ForEach-Object { $_.Dn }) }) }
        if ($isWinSsh) { $winssh.Add($gpo.Name) }
    }
    foreach ($old in $today) {
        Write-Warning "UsaBanner: the GPO '$($old.Name)' ($($old.Guid)) delivers today's banner (its task is '$script:UsaOldGpoTask') and is linked, enabled, at $($old.Dn -join '; '): while it applies to a host, it and this GPO undo each other at each refresh. Take it off those hosts (D29)."
    }
    if (-not $winssh.Count) {
        Write-Warning "UsaBanner: no GPO that makes the task '$script:UsaGpoWinSshTask' is linked and enabled, so Windows servers without PowerShell 7 get no banner: deploy-usawinssh installs it (D21)."
    }
}

function Test-UsaBannerGpoReadBack {
    <#
    .SYNOPSIS
    Reads back what the run wrote, one line per check.
    .DESCRIPTION
    In:  the run, after the writes.
    Out: 'ok   <check>' or 'FAIL <check>' for each: every copy is its payload
    (each file's SHA-256, and nothing extra but the mark); the Ubuntu GPT.INI
    Version is at least the one written; the task file is the one wanted; the
    extension is registered; the computer settings are on; the version in AD is
    the one in GPT.INI; the ADSys startup values are exactly the wanted ones;
    each -LinkTarget is linked and enabled. Throws when any check fails.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][hashtable]$Run)
    $ctx = $Run.Domain
    $guid = $Run.Guid
    $checks = [System.Collections.Generic.List[object]]::new()
    $add = { param($Check, $Pass, $Detail) $checks.Add([pscustomobject]@{ Check = $Check; Pass = [bool]$Pass; Detail = [string]$Detail }) }

    foreach ($tree in $Run.Trees) {
        $problems = @(Test-UsaBannerGpoTree -Path $tree.Path -Payload $tree.Payload)
        & $add "$($tree.Label): $($tree.Path) is the payload, $($tree.Payload.Count) files by SHA-256 and nothing else" ($problems.Count -eq 0) (@($problems | Select-Object -First 3) -join '; ')
    }
    if ($Run.AdsysIni) {
        $version = Get-UsaBannerGpoGptIniVersion -Content ([System.IO.File]::ReadAllText($Run.AdsysIni))
        & $add "Ubuntu GPT.INI is at Version $version, at least $($Run.AdsysVersion)" ($version -ge $Run.AdsysVersion) $Run.AdsysIni
    }

    $tasksFile = Get-UsaBannerGpoFilePath -Policies $Run.Place.Policies -Guid $guid -File Tasks
    $tasksNow = if ([System.IO.File]::Exists($tasksFile)) { [System.IO.File]::ReadAllText($tasksFile) } else { $null }
    & $add "task '$script:UsaGpoTaskName' in $tasksFile is the one wanted" (Test-UsaBannerGppXmlSame -Existing $tasksNow -Desired $Run.Tasks.Xml) ''
    $ext = [string](Get-UsaBannerGpoAttribute -Domain $ctx -Guid $guid -Name 'gPCMachineExtensionNames')
    & $add 'Scheduled Tasks extension registered' ((Merge-UsaBannerGpoTaskExtension -Existing $ext) -ceq $ext) $ext
    $flags = [int](Get-UsaBannerGpoAttribute -Domain $ctx -Guid $guid -Name 'flags')
    & $add 'computer settings enabled' (($flags -band 2) -eq 0) "flags $flags"
    $adVersion = [long](Get-UsaBannerGpoAttribute -Domain $ctx -Guid $guid -Name 'versionNumber')
    if ($adVersion -lt 0) { $adVersion += 4294967296 }
    $gptIni = Get-UsaBannerGpoFilePath -Policies $Run.Place.Policies -Guid $guid -File GptIni
    $iniVersion = if ([System.IO.File]::Exists($gptIni)) { Get-UsaBannerGpoGptIniVersion -Content ([System.IO.File]::ReadAllText($gptIni)) } else { [long]-1 }
    & $add "version in AD ($adVersion) = GPT.INI ($iniVersion)" ($adVersion -eq $iniVersion) ''
    if ($Run.AdsysIni) {
        $current = @{}
        foreach ($value in @(Get-UsaBannerGpoRegistryValue -Domain $ctx -Guid $guid -Key $script:UsaGpoStartupKey)) {
            $current[$value.Name] = @{ Type = $value.Type; Value = $value.Value }
        }
        $left = @(Get-UsaBannerGpoStartupChange -Current $current -Wanted $Run.Wanted)
        & $add "startup values: metaValues (append, every release) and all = $script:UsaGpoStartupScript, nothing else under $script:UsaGpoStartupKey" ($left.Count -eq 0) (@($left | ForEach-Object { $_.Name }) -join ', ')
    }
    foreach ($target in $Run.Targets) {
        $link = Get-UsaBannerGpoLinkAt -Domain $ctx -TargetDn $target -Guid $guid
        & $add "linked at $target, enabled" ($link.Linked -and $link.Enabled) "gPLink flags $($link.Flags)"
    }

    foreach ($check in $checks) { '{0,-4} {1}' -f $(if ($check.Pass) { 'ok' } else { 'FAIL' }), $check.Check }
    $failed = @($checks | Where-Object { -not $_.Pass })
    if ($failed.Count) {
        throw "UsaBanner: $($failed.Count) of $($checks.Count) checks failed: $(($failed | ForEach-Object { if ($_.Detail) { "$($_.Check) ($($_.Detail))" } else { $_.Check } }) -join '; ')"
    }
}

#endregion

function Invoke-UsaBannerGpoDeploy {
    <#
    .SYNOPSIS
    Deploy-UsaBannerGPO's work: stage the banner on the PDC emulator, make the
    GPO that points hosts at it, link it where the admin said.
    .DESCRIPTION
    In:  the package's configuration (New-UsaBannerDeployConfig), the GPO's
         display name, the distinguished names to link it at, and the domain's
         DNS name (none for this computer's).
    Out: a line for each change, in the order made, and then a line for each
         read-back check; nothing else on a run that changes nothing. Under
         -WhatIf, PowerShell says each change instead, and nothing changes.
    In this order: the package (refused when it turns the update channel on);
    the domain, and every -LinkTarget checked to be there; the plan, which
    reads and writes nothing and refuses what it must (a destination that is
    someone else's, the module staged onto itself, two GPOs of the name, a
    ScheduledTasks.xml it cannot merge into); the overwrite warnings; the
    files; the GPO; the links; the neighbours' warnings; the read-back.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][string]$Name,
        [string[]]$LinkTarget = @(),
        [AllowEmptyString()][string]$Domain = ''
    )
    $ErrorActionPreference = 'Stop'

    # 1. The package: the configuration every host gets, and no update channel in it. The GPO
    #    is the update path (D29): a new publish is a new version, while an update job beside
    #    it would install a release the next refresh puts back to the staged one.
    $mode = [string]$Config['update']['mode']
    if ($mode -cne 'off') {
        throw "UsaBanner: No update channel in a package for Group Policy. The GPO is the update path: a new publish is a new version, while an update job beside it would install a newer release that the next policy refresh puts back to the staged one, and each deletes the other's copy. This configuration sets update.mode to '$mode': leave -Update off, and take the update channel out of the file -Path names. Nothing was read from the domain, and nothing was written."
    }
    $json = ConvertTo-UsaBannerConfigJson -Config $Config
    # The schema keeps every setting to ASCII, but this file goes to every host, so ASCII is its
    # contract here too (the schema check can fail quietly: Test-Json changed in PowerShell 7.6).
    $odd = [regex]::Match($json, '[^\x20-\x7E\n]')
    if ($odd.Success) {
        throw "UsaBanner: the package holds a character that is not ASCII (U+$('{0:X4}' -f [int][char]$odd.Value) at position $($odd.Index) of usabanner.json). Every host reads it, and the module's files are ASCII only: use plain ASCII in the settings. Nothing was read from the domain, and nothing was written."
    }
    $package = [System.Text.UTF8Encoding]::new($false).GetBytes($json)

    # 2. The domain, and the places the links go.
    Import-UsaBannerGroupPolicy
    $ctx = Get-UsaBannerGpoDomain -Domain $Domain
    $place = Get-UsaBannerGpoPlace -Domain $ctx
    Write-Information -MessageData "Domain $($ctx.Name), PDC emulator $($ctx.Pdc). PowerShell $($PSVersionTable.PSVersion): the GroupPolicy cmdlets answer through the Windows PowerShell compatibility session, so their objects are copies; the run reads AD and SYSVOL itself." -InformationAction Continue
    $targets = @($LinkTarget | Where-Object { $_ })
    foreach ($target in $targets) {
        try { $null = Get-UsaBannerGpoLinkAt -Domain $ctx -TargetDn $target }
        catch { throw "$($_.Exception.Message) Nothing was written." }
    }

    # 3. The plan: everything the run would do, worked out before any of it is done.
    $run = @{ Name = $Name; Domain = $ctx; Place = $place; Targets = $targets; Package = $package }
    Get-UsaBannerGpoStagingPlan -Run $run
    Get-UsaBannerGpoSettingsPlan -Run $run
    Write-UsaBannerGpoOverwriteWarning -Run $run

    # 4. The writes, and then what to say about the neighbours.
    Invoke-UsaBannerGpoStaging -Run $run
    Invoke-UsaBannerGpoSettings -Run $run
    Invoke-UsaBannerGpoLinking -Run $run
    Write-UsaBannerGpoNeighbourWarning -Run $run

    # 5. Read it all back: nothing to read after -WhatIf, or when -Confirm said no to making the GPO.
    if ($WhatIfPreference -or -not $run.Guid) { return }
    Test-UsaBannerGpoReadBack -Run $run
}
