# GpoPolicy.ps1 - the pure half of Deploy-UsaBannerGPO (docs/DECISIONS.md, D29): what the
# "UsaBanner" GPO should hold, and how that differs from a GPO of that name that exists
# already. Nothing here talks to a domain or reads a share (GpoDeploy.ps1 does), so all of it
# runs, and is tested, on any OS. It is ported from deploy-usawinssh's UsaDeploy-WinSsh.psm1
# (the task, the extension, the version, GPT.INI, gPLink, the LDAP escape and the report),
# which a lab domain proved, and from today's banner's ManatechMotdGpo.psm1 (the ADSys
# startup values).
#
#   +------------------------------------+-----------------------------------------------------+
#   | ConvertTo-UsaBannerGpoLfByte       | a file's bytes, each CRLF turned into LF            |
#   | Test-UsaBannerGpoPathInside        | is a path a folder, or inside it?                   |
#   | ConvertTo-UsaBannerGppXml          | an XML document as the GPP files here are written   |
#   | ConvertTo-UsaBannerGpoStableGuid   | a preference item's uid, derived from its name      |
#   | Get-UsaBannerGpoTaskArgument       | the task's powershell.exe arguments                 |
#   | New-UsaBannerGpoTasksXml           | ScheduledTasks.xml with the task merged in          |
#   | Get-UsaBannerGpoTaskField          | a task item's account, program, filters, ...        |
#   | Compare-UsaBannerGpoTaskField      | "field: 'old' -> 'new'" for each that differs       |
#   | Test-UsaBannerGppXmlSame           | the same GPP XML, layout and time stamps aside?     |
#   | Get-UsaBannerGpoTaskItemName       | the names of a ScheduledTasks.xml's task items      |
#   | Merge-UsaBannerGpoTaskExtension    | gPCMachineExtensionNames with Scheduled Tasks in it |
#   | Step-UsaBannerGpoVersion           | a GPO version with its computer half + 1            |
#   | Get-UsaBannerGpoGptIniText         | GPT.INI text with Version= set                      |
#   | Get-UsaBannerGpoGptIniVersion      | the Version= a GPT.INI text holds                   |
#   | Test-UsaBannerGpoLinkValue         | is the GPO in this gPLink value, and enabled?       |
#   | ConvertTo-UsaBannerLdapFilterValue | a value escaped for an LDAP filter                  |
#   | ConvertFrom-UsaBannerGpoReport     | the settings areas a Get-GPOReport XML lists        |
#   | Get-UsaBannerGpoStartupMeta        | the ADSys metaValues text: append, every release    |
#   | Get-UsaBannerGpoStartupChange      | which ADSys startup values to set or remove         |
#   +------------------------------------+-----------------------------------------------------+

# Group Policy Preferences identifiers for scheduled tasks. The clsids go in ScheduledTasks.xml
# (ImmediateTaskV2 is "Immediate Task (At least Windows 7)" in GPMC). The CSE and admin-tool
# GUIDs go in the GPO's gPCMachineExtensionNames: a client runs only the extensions listed
# there, so without the pair the file is ignored. GPMC also lists the tool under the all-zero
# CSE.
$script:UsaGpp = @{
    ContainerClsid       = '{CC63F200-7309-4ba0-B154-A71CD118DBCC}'
    ImmediateTaskV2Clsid = '{9756B581-76EC-4169-9AFC-0CA8D43ADB5F}'
    Cse                  = '{AADCED64-746C-4633-A97C-D61349046527}'
    Tool                 = '{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}'
    ZeroCse              = '{00000000-0000-0000-0000-000000000000}'
}

# The item-level target that keeps the task off workstations: the GPP extension evaluates it on
# the host before it creates the task ([MS-GPPREF] 2.2.1.22, FilterWmi). ProductType 2 is a
# domain controller, 3 any other server; 1, a workstation, matches neither.
$script:UsaGpoServerQuery = 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 2 OR ProductType = 3'

# The task item, by name, and the item the neighbouring policies are known by (D21, D29).
$script:UsaGpoTaskName = 'UsaBanner sync'
$script:UsaGpoWinSshTask = 'UsaDeploy-WinSsh'

# The folder the module, the package and the runners are staged in, on both OSes, and the
# file that says Deploy-UsaBannerGPO made it (and may remove files from it).
$script:UsaGpoStageName = 'UsaBanner'
$script:UsaGpoMarkName = '.usabanner-gpo'
$script:UsaGpoMarkText = "Made by Deploy-UsaBannerGPO (UsaBanner), for the GPO's Windows task and Ubuntu startup script.`n" +
    "Files here that are not in the module's payload are removed at the next publish.`n"

# The file a publish puts in a copy before it writes anything there, and takes away when the copy
# is done and, for Ubuntu, the GPT.INI Version is raised. One still there tells the next run that a
# publish was cut short, so that it raises the Version even where every file is current: else ADSys
# would never download what the cut-short run wrote.
$script:UsaGpoPublishingName = '.usabanner-publishing'

# What a GPO made here says about itself, in GPMC.
$script:UsaGpoComment = 'UsaBanner: the login banners. An immediate task on Windows servers and an ADSys startup script on Ubuntu hosts run the deploy from the module and the package staged on the PDC emulator. Written by Deploy-UsaBannerGPO (UsaBanner); a publish overwrites changes made in GPMC.'

# ADSys's startup scripts: the key its administrative template writes, the script it runs
# (relative to the Ubuntu\scripts folder of SYSVOL), and the releases the template names, plus
# "all".
$script:UsaGpoStartupKey = 'HKLM\Software\Policies\Ubuntu\scripts\startup'
$script:UsaGpoStartupScript = 'UsaBanner/adsys-startup.sh'
$script:UsaGpoAdsysReleases = @('22.04', '24.04', '25.04', '25.10', 'all')

#region ----- files -----

function ConvertTo-UsaBannerGpoLfByte {
    # In:  a file's bytes
    # Out: the bytes with every CR LF turned into LF; a lone CR stays. A file with a NUL byte is
    #      binary and comes back as it was
    # Why: sh cannot read a CRLF script, and a clone made by Git for Windows (core.autocrlf)
    #      has CRLF. Latin-1 maps each byte to one character and back, so nothing else changes
    [CmdletBinding()]
    [OutputType([byte[]])]
    param([AllowEmptyCollection()][byte[]]$Bytes)
    if ($Bytes.Length -eq 0 -or [array]::IndexOf($Bytes, [byte]0) -ge 0 -or [array]::IndexOf($Bytes, [byte]13) -lt 0) { return , $Bytes }
    $latin1 = [System.Text.Encoding]::Latin1
    , $latin1.GetBytes($latin1.GetString($Bytes).Replace("`r`n", "`n"))
}

function Test-UsaBannerGpoPathInside {
    # In:  a path, and a folder
    # Out: true when the path is the folder, or is inside it
    # Why: the module's own folder must not be a place it stages into, else it reads what it
    #      writes. Windows paths compare without regard to case
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Folder)
    $inner = [System.IO.Path]::GetFullPath($Path).TrimEnd('/', '\')
    $outer = [System.IO.Path]::GetFullPath($Folder).TrimEnd('/', '\')
    $inner.Equals($outer, [System.StringComparison]::OrdinalIgnoreCase) -or
        $inner.StartsWith($outer + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

#endregion

#region ----- XML plumbing -----

function Get-UsaBannerGpoXmlNode {
    # In:  an XML node, and a path of local names joined with / (* is any element)
    # Out: the nodes at that path under it
    # Why: by local name, so the namespace Get-GPOReport puts on everything does not matter
    param([Parameter(Mandatory)][System.Xml.XmlNode]$Node, [Parameter(Mandatory)][string]$Path)
    $xpath = (@($Path -split '/') | ForEach-Object { if ($_ -eq '*') { '*' } else { "*[local-name()='$_']" } }) -join '/'
    @($Node.SelectNodes($xpath))
}

function Get-UsaBannerGpoXmlText {
    # In:  an XML node, and a path as for Get-UsaBannerGpoXmlNode
    # Out: the text of the first node at that path, or ''
    # Why: the @() matters: one XmlElement indexed with [0] goes to the XML adapter's string
    #      indexer and returns $null
    param([Parameter(Mandatory)][System.Xml.XmlNode]$Node, [Parameter(Mandatory)][string]$Path)
    $found = @(Get-UsaBannerGpoXmlNode -Node $Node -Path $Path)
    if ($found.Count) { $found[0].InnerText } else { '' }
}

function Add-UsaBannerGpoXmlChild {
    # In:  an element, and an ordered table of child elements: a name with text, or a name
    #      with a nested table
    # Out: nothing; the element holds them
    param([Parameter(Mandatory)][System.Xml.XmlElement]$Parent, [Parameter(Mandatory)][System.Collections.IDictionary]$Spec)
    foreach ($name in $Spec.Keys) {
        $child = $Parent.OwnerDocument.CreateElement($name)
        $value = $Spec[$name]
        if ($value -is [System.Collections.IDictionary]) { Add-UsaBannerGpoXmlChild -Parent $child -Spec $value }
        else { $child.InnerText = [string]$value }
        $null = $Parent.AppendChild($child)
    }
}

function ConvertTo-UsaBannerGppXml {
    <#
    .SYNOPSIS
    The document as text, the way the GPP files here are written: an XML
    declaration, two-space indent, LF line ends.
    .DESCRIPTION
    The caller writes it as UTF-8 without a byte order mark, which is what the
    declaration says.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Xml.XmlDocument]$Document)
    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.NewLineChars = "`n"
    $sb = [System.Text.StringBuilder]::new()
    $writer = [System.Xml.XmlWriter]::Create($sb, $settings)
    try { $Document.Save($writer) } finally { $writer.Dispose() }
    # A writer over a StringBuilder declares utf-16; the file is UTF-8.
    ($sb.ToString() -replace '^<\?xml[^>]*\?>', '<?xml version="1.0" encoding="utf-8"?>') + "`n"
}

function ConvertTo-UsaBannerGpoStableGuid {
    <#
    .SYNOPSIS
    A GUID from the first 16 bytes of SHA-256(Name), uppercase in braces.
    .DESCRIPTION
    A preference item's uid is its identity on a client: the same uid updates
    the task, a new one makes a second. GPMC picks a random one; deriving it
    from the name keeps it the same at every publish.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Name)) } finally { $sha.Dispose() }
    # The [byte[]] cast matters: a slice is object[], and [guid]::new would then take its string
    # overload.
    ([guid]::new([byte[]]$bytes[0..15])).ToString('B').ToUpperInvariant()
}

#endregion

#region ----- the task -----

function Get-UsaBannerGpoTaskArgument {
    <#
    .SYNOPSIS
    The arguments powershell.exe gets from the task: the runner, by its path.
    .DESCRIPTION
    -ExecutionPolicy Bypass because a script on a UNC path counts as remote
    under RemoteSigned. An execution policy set by Group Policy still wins
    over it. Throws on a path with a quote, which would end the argument.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$ScriptPath)
    if ($ScriptPath.Contains('"')) { throw "UsaBanner: the runner's path holds a quote, which would end the task's argument: $ScriptPath" }
    "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""
}

function New-UsaBannerGpoTaskItem {
    # In:  a document, the task's name and its powershell.exe arguments
    # Out: the task as an ImmediateTaskV2 item of the document, not yet inserted. See
    #      New-UsaBannerGpoTasksXml
    param(
        [Parameter(Mandatory)][System.Xml.XmlDocument]$Document,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$Arguments
    )
    $doc = $Document
    $item = $doc.CreateElement('ImmediateTaskV2')
    $item.SetAttribute('clsid', $script:UsaGpp.ImmediateTaskV2Clsid)
    $item.SetAttribute('name', $TaskName)
    # image: the icon GPMC draws for the action (2 = update). Display only.
    $item.SetAttribute('image', '2')
    # changed: when the item was written. Ignored when files are compared.
    $item.SetAttribute('changed', (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    $item.SetAttribute('uid', (ConvertTo-UsaBannerGpoStableGuid -Name "UsaBanner|ImmediateTaskV2|$TaskName"))
    # userContext 0: the computer's context. removePolicy 0: nothing to remove when the GPO stops
    # applying - the task deletes itself after every run, and what the deploy set stays as it is
    # (Remove-UsaBanner takes it off).
    $item.SetAttribute('userContext', '0')
    $item.SetAttribute('removePolicy', '0')

    $props = $doc.CreateElement('Properties')
    # action U: create the task where it is missing, else update it in place.
    $props.SetAttribute('action', 'U')
    $props.SetAttribute('name', $TaskName)
    $props.SetAttribute('runAs', 'NT AUTHORITY\System')
    # S4U: no stored password - how GPMC writes a task that runs as SYSTEM.
    $props.SetAttribute('logonType', 'S4U')

    $task = $doc.CreateElement('Task')
    $task.SetAttribute('version', '1.3')
    Add-UsaBannerGpoXmlChild -Parent $task -Spec ([ordered]@{
        RegistrationInfo = [ordered]@{
            Author      = 'Deploy-UsaBannerGPO'
            Description = 'UsaBanner on this server: runs Sync-UsaBanner.ps1 from NETLOGON, which hands over to PowerShell 7. Written by Deploy-UsaBannerGPO (UsaBanner); a publish overwrites changes made in GPMC.'
        }
    })
    $principals = $doc.CreateElement('Principals')
    $principal = $doc.CreateElement('Principal')
    $principal.SetAttribute('id', 'Author')
    Add-UsaBannerGpoXmlChild -Parent $principal -Spec ([ordered]@{ UserId = 'NT AUTHORITY\System'; LogonType = 'S4U'; RunLevel = 'HighestAvailable' })
    $null = $principals.AppendChild($principal)
    $null = $task.AppendChild($principals)

    $settings = $doc.CreateElement('Settings')
    Add-UsaBannerGpoXmlChild -Parent $settings -Spec ([ordered]@{
        IdleSettings               = [ordered]@{ Duration = 'PT10M'; WaitTimeout = 'PT1H'; StopOnIdleEnd = 'true'; RestartOnIdle = 'false' }
        # IgnoreNew: a run still going at the next refresh is not doubled (the runner locks too).
        MultipleInstancesPolicy    = 'IgnoreNew'
        DisallowStartIfOnBatteries = 'false'
        StopIfGoingOnBatteries     = 'false'
        AllowHardTerminate         = 'true'
        StartWhenAvailable         = 'true'
        RunOnlyIfNetworkAvailable  = 'false'
        AllowStartOnDemand         = 'true'
        Enabled                    = 'true'
        Hidden                     = 'false'
        RunOnlyIfIdle              = 'false'
        WakeToRun                  = 'false'
        # Half an hour: a deploy that installs nothing takes seconds, and one that copies the
        # module from the share a minute or two.
        ExecutionTimeLimit         = 'PT30M'
        Priority                   = '7'
        # PT0M: the task deletes itself once it has run, which is what makes it immediate.
        DeleteExpiredTaskAfter     = 'PT0M'
    })
    $null = $task.AppendChild($settings)

    # %LocalTimeXmlEx%: the client puts "now" in both bounds when it creates the task. Child order
    # as GPMC writes an immediate task.
    $triggers = $doc.CreateElement('Triggers')
    $time = $doc.CreateElement('TimeTrigger')
    Add-UsaBannerGpoXmlChild -Parent $time -Spec ([ordered]@{ StartBoundary = '%LocalTimeXmlEx%'; EndBoundary = '%LocalTimeXmlEx%'; Enabled = 'true' })
    $null = $triggers.AppendChild($time)
    $null = $task.AppendChild($triggers)

    $actions = $doc.CreateElement('Actions')
    # Context Author: run as the Principal whose id is Author - SYSTEM, above.
    $actions.SetAttribute('Context', 'Author')
    $exec = $doc.CreateElement('Exec')
    Add-UsaBannerGpoXmlChild -Parent $exec -Spec ([ordered]@{ Command = 'powershell.exe'; Arguments = $Arguments })
    $null = $actions.AppendChild($exec)
    $null = $task.AppendChild($actions)

    $null = $props.AppendChild($task)
    $null = $item.AppendChild($props)

    # Servers only: a workstation never gets the task.
    $filters = $doc.CreateElement('Filters')
    $wmi = $doc.CreateElement('FilterWmi')
    $wmi.SetAttribute('bool', 'AND')
    $wmi.SetAttribute('not', '0')
    $wmi.SetAttribute('query', $script:UsaGpoServerQuery)
    $wmi.SetAttribute('nameSpace', 'Root\cimv2')
    $null = $filters.AppendChild($wmi)
    $null = $item.AppendChild($filters)
    $item
}

function Get-UsaBannerGpoTaskField {
    <#
    .SYNOPSIS
    What a person compares between two scheduled-task items, as an ordered
    table of strings: Kind, Action, RunAs, RunLevel, Command, Arguments,
    Triggers, TimeLimit, Enabled, Filters.
    .DESCRIPTION
    Reads the Task Scheduler 2.0 items (TaskV2, ImmediateTaskV2: a task under
    Properties) and the older Task and ImmediateTask items (attributes appName
    and args). What an item does not have reads as ''. Filters lists each
    item-level target, a WMI one with its query, because the target decides
    which hosts get the task. (Kind, not Item: on a dictionary, .Item is its
    indexer.)
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)][System.Xml.XmlElement]$Item)
    $f = [ordered]@{ Kind = $Item.LocalName; Action = 'U'; RunAs = ''; RunLevel = ''; Command = ''; Arguments = ''; Triggers = ''; TimeLimit = ''; Enabled = ''; Filters = 'none' }
    if ($Item.GetAttribute('disabled') -eq '1') { $f.Kind += ' (switched off in GPMC)' }
    $props = @(Get-UsaBannerGpoXmlNode -Node $Item -Path 'Properties')
    if ($props.Count) {
        $p = $props[0]
        if ($p.GetAttribute('action')) { $f.Action = $p.GetAttribute('action') }
        $f.RunAs = $p.GetAttribute('runAs')
        $task = @(Get-UsaBannerGpoXmlNode -Node $p -Path 'Task')
        if ($task.Count) {
            $t = $task[0]
            $f.RunLevel = Get-UsaBannerGpoXmlText -Node $t -Path 'Principals/Principal/RunLevel'
            $exec = @(Get-UsaBannerGpoXmlNode -Node $t -Path 'Actions/Exec')
            if ($exec.Count) {
                $f.Command = Get-UsaBannerGpoXmlText -Node $exec[0] -Path 'Command'
                $f.Arguments = Get-UsaBannerGpoXmlText -Node $exec[0] -Path 'Arguments'
                if ($exec.Count -gt 1) { $f.Command += " (and $($exec.Count - 1) more program(s))" }
            }
            $f.Triggers = (@(Get-UsaBannerGpoXmlNode -Node $t -Path 'Triggers/*') | ForEach-Object { $_.LocalName }) -join ', '
            $f.TimeLimit = Get-UsaBannerGpoXmlText -Node $t -Path 'Settings/ExecutionTimeLimit'
            $f.Enabled = Get-UsaBannerGpoXmlText -Node $t -Path 'Settings/Enabled'
        }
        else {
            $f.Command = $p.GetAttribute('appName')
            $f.Arguments = $p.GetAttribute('args')
            $f.Enabled = $p.GetAttribute('enabled')
        }
    }
    $filters = @(Get-UsaBannerGpoXmlNode -Node $Item -Path 'Filters/*')
    if ($filters.Count) {
        $f.Filters = (@($filters | ForEach-Object {
                    $not = if ($_.GetAttribute('not') -eq '1') { 'NOT ' } else { '' }
                    if ($_.LocalName -eq 'FilterWmi') { "${not}WMI: $($_.GetAttribute('query'))" } else { "$not$($_.LocalName)" }
                })) -join '; '
    }
    $f
}

function Compare-UsaBannerGpoTaskField {
    <#
    .SYNOPSIS
    "Field: 'old' -> 'new'" for each field of -New that -Old holds
    differently.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Old,
        [Parameter(Mandatory)][System.Collections.IDictionary]$New
    )
    foreach ($name in @($New.Keys)) {
        $was = if ($Old.Contains($name)) { [string]$Old[$name] } else { '' }
        $now = [string]$New[$name]
        if ($was -cne $now) { "${name}: '$was' -> '$now'" }
    }
}

function New-UsaBannerGpoTasksXml {
    <#
    .SYNOPSIS
    The GPO's ScheduledTasks.xml: -Existing (the file's text, blank for none)
    with the banner's task merged in.
    .DESCRIPTION
    The task is an ImmediateTaskV2 item ("Immediate Task (At least Windows 7)"
    in GPMC) named -TaskName: NT AUTHORITY\System with highest privileges, run
    once at each policy refresh and deleted, stopped after half an hour,
    running powershell.exe -Arguments, and targeted at servers by a WMI filter
    on the item.
    Every item for -TaskName (by its name or its task's name, any case, any
    kind of task item) is replaced: the task takes the first one's place, and
    the others go. With none, it is added at the end. Items for other tasks
    are kept as they are. A disabled="1" on the root, which switches every
    item off, is removed.
    Returns Xml (the new file text), Fields (Get-UsaBannerGpoTaskField of the
    task), Replaced (Name, Item, Uid and Fields of each replaced item, in file
    order), Kept (a label per item left alone) and RootWasDisabled.
    Throws when -Existing is not XML, or not a ScheduledTasks file: a file this
    cannot read is not overwritten.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Existing,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$Arguments
    )
    $doc = [System.Xml.XmlDocument]::new()
    if ([string]::IsNullOrWhiteSpace($Existing)) {
        $null = $doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'utf-8', $null))
        $root = $doc.CreateElement('ScheduledTasks')
        $root.SetAttribute('clsid', $script:UsaGpp.ContainerClsid)
        $null = $doc.AppendChild($root)
    }
    else {
        try { $doc.LoadXml($Existing.TrimStart([char]0xFEFF)) }
        catch { throw "UsaBanner: the GPO's ScheduledTasks.xml is not XML this can read ($($_.Exception.Message)). Fix or delete it in GPMC, then run this again." }
        $root = $doc.DocumentElement
        if ($root.LocalName -ne 'ScheduledTasks') { throw "UsaBanner: the GPO's ScheduledTasks.xml has a <$($root.LocalName)> root, not <ScheduledTasks>. Fix or delete it in GPMC, then run this again." }
    }
    $rootWasDisabled = $root.GetAttribute('disabled') -eq '1'
    if ($rootWasDisabled) { $root.RemoveAttribute('disabled') }

    $new = New-UsaBannerGpoTaskItem -Document $doc -TaskName $TaskName -Arguments $Arguments
    $replaced = [System.Collections.Generic.List[object]]::new()
    $kept = [System.Collections.Generic.List[string]]::new()
    $first = $null
    foreach ($node in @($root.ChildNodes)) {
        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        $props = @(Get-UsaBannerGpoXmlNode -Node $node -Path 'Properties')
        $taskOf = if ($props.Count) { $props[0].GetAttribute('name') } else { '' }
        if ($node.GetAttribute('name') -eq $TaskName -or $taskOf -eq $TaskName) {
            $replaced.Add([pscustomobject]@{ Name = $node.GetAttribute('name'); Item = $node.LocalName; Uid = $node.GetAttribute('uid'); Fields = Get-UsaBannerGpoTaskField -Item $node })
            if ($null -eq $first) { $first = $node } else { $null = $root.RemoveChild($node) }
        }
        else {
            $kept.Add("$($node.LocalName) '$($node.GetAttribute('name'))'")
        }
    }
    if ($null -ne $first) { $null = $root.ReplaceChild($new, $first) } else { $null = $root.AppendChild($new) }

    [pscustomobject]@{
        Xml             = ConvertTo-UsaBannerGppXml -Document $doc
        Fields          = Get-UsaBannerGpoTaskField -Item $new
        Replaced        = $replaced.ToArray()
        Kept            = $kept.ToArray()
        RootWasDisabled = $rootWasDisabled
    }
}

function Test-UsaBannerGppXmlSame {
    <#
    .SYNOPSIS
    Whether -Existing and -Desired are the same GPP XML once both are laid out
    the same way and every changed="..." stamp is blanked. A blank or
    unreadable -Existing is never the same.
    .DESCRIPTION
    Every publish stamps a new "changed" time, and GPMC lays files out its own
    way. A byte compare would rewrite the file at every run, and the version
    bump that comes with it makes every client apply the GPO again.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Existing,
        [Parameter(Mandatory)][string]$Desired
    )
    if ([string]::IsNullOrWhiteSpace($Existing)) { return $false }
    $norm = {
        param($text)
        $d = [System.Xml.XmlDocument]::new()
        $d.LoadXml($text.TrimStart([char]0xFEFF))
        (ConvertTo-UsaBannerGppXml -Document $d) -replace 'changed="[^"]*"', 'changed=""'
    }
    try { (& $norm $Existing) -ceq (& $norm $Desired) } catch { $false }
}

function Get-UsaBannerGpoTaskItemName {
    # In:  the text of a ScheduledTasks.xml
    # Out: the name of each item in it, and of the task it holds where that is another name
    # Why: the neighbours check (does a GPO make the task of today's banner, or of
    #      deploy-usawinssh?) looks for a task by name. Throws on text that is not XML
    param([Parameter(Mandatory)][string]$Xml)
    $doc = [System.Xml.XmlDocument]::new()
    $doc.LoadXml($Xml.TrimStart([char]0xFEFF))
    foreach ($node in @($doc.DocumentElement.ChildNodes)) {
        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        $node.GetAttribute('name')
        $props = @(Get-UsaBannerGpoXmlNode -Node $node -Path 'Properties')
        if ($props.Count) { $props[0].GetAttribute('name') }
    }
}

#endregion

#region ----- the GPO object -----

function Merge-UsaBannerGpoTaskExtension {
    <#
    .SYNOPSIS
    The GPO's gPCMachineExtensionNames text -Existing with the Scheduled Tasks
    extension added; unchanged when it is there already.
    .DESCRIPTION
    The value is [{CSE}{tool}...] groups, sorted by CSE GUID: "Group Policy
    processing terminates at the first <CSE GUIDn> out of sequence"
    ([MS-GPOL] 2.2.4). Groups ascend, the tools inside a group too, all
    uppercase, compared ordinally (a culture sort can order GUIDs differently,
    and the value would then differ at every run). Every group already there
    is kept, so what other settings registered survives.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()][AllowEmptyString()][string]$Existing)
    $groups = @{}
    foreach ($m in [regex]::Matches([string]$Existing, '\[((?:\{[0-9A-Fa-f-]{36}\})+)\]')) {
        $guids = @([regex]::Matches($m.Groups[1].Value, '\{[0-9A-Fa-f-]{36}\}') | ForEach-Object { $_.Value.ToUpperInvariant() })
        if (-not $groups.ContainsKey($guids[0])) { $groups[$guids[0]] = [System.Collections.Generic.HashSet[string]]::new() }
        foreach ($tool in @($guids | Select-Object -Skip 1)) { $null = $groups[$guids[0]].Add($tool) }
    }
    foreach ($cse in @($script:UsaGpp.Cse, $script:UsaGpp.ZeroCse)) {
        if (-not $groups.ContainsKey($cse)) { $groups[$cse] = [System.Collections.Generic.HashSet[string]]::new() }
        $null = $groups[$cse].Add($script:UsaGpp.Tool)
    }
    $keys = [string[]]@($groups.Keys)
    [array]::Sort($keys, [System.StringComparer]::Ordinal)
    -join @(foreach ($cse in $keys) {
            $tools = [string[]]@($groups[$cse])
            [array]::Sort($tools, [System.StringComparer]::Ordinal)
            '[' + $cse + (-join $tools) + ']'
        })
}

function Step-UsaBannerGpoVersion {
    <#
    .SYNOPSIS
    -Version with its computer half (the low 16 bits) up by one; the user half
    (the high 16 bits) as it was.
    .DESCRIPTION
    A GPO's version is one 32-bit number, in AD (versionNumber) and in its
    GPT.INI (Version=): 16 bits of user version above 16 bits of computer
    version ([MS-GPOL] 2.2.4). A client applies a GPO again only when that
    number moves, and this GPO is all computer settings. The computer half
    wraps at 16 bits rather than spill into the user half.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param([Parameter(Mandatory)][ValidateRange(0, 4294967295)][long]$Version)
    $user = ($Version -shr 16) -band 0xFFFF
    $computer = (($Version -band 0xFFFF) + 1) -band 0xFFFF
    [long](($user -shl 16) -bor $computer)
}

function Get-UsaBannerGpoGptIniText {
    <#
    .SYNOPSIS
    The GPT.INI text -Content with Version= set to -Version: the line replaced
    where it is, or added under [General] (with the section, when missing).
    Other lines kept, blank ones dropped; CRLF.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][long]$Version
    )
    $lines = if ([string]::IsNullOrWhiteSpace($Content)) { @('[General]') } else { @($Content -split "`r?`n" | Where-Object { $_ -ne '' }) }
    $done = $false
    $out = @(foreach ($line in $lines) {
            if ($line -match '^\s*Version\s*=') { $done = $true; "Version=$Version" } else { $line }
        })
    if (-not $done) {
        $at = -1
        for ($i = 0; $i -lt $out.Count; $i++) { if ($out[$i].Trim() -eq '[General]') { $at = $i; break } }
        $out = if ($at -ge 0) { @($out[0..$at]) + @("Version=$Version") + @($out | Select-Object -Skip ($at + 1)) }
        else { @('[General]', "Version=$Version") + $out }
    }
    ($out -join "`r`n") + "`r`n"
}

function Get-UsaBannerGpoGptIniVersion {
    # In:  the text of a GPT.INI
    # Out: the number its Version= line holds; -1 when it has none
    [CmdletBinding()]
    [OutputType([long])]
    param([AllowNull()][AllowEmptyString()][string]$Content)
    $found = [regex]::Match([string]$Content, '(?im)^\s*Version\s*=\s*(\d+)')
    if ($found.Success) { [long]$found.Groups[1].Value } else { [long]-1 }
}

function Test-UsaBannerGpoLinkValue {
    <#
    .SYNOPSIS
    Whether the GPO -GpoGuid is linked in -GpLink (an OU's or the domain's
    gPLink value), and whether that link is enabled: Linked, Enabled, Flags
    (-1 when not linked).
    .DESCRIPTION
    gPLink is [LDAP://cn={guid},cn=policies,...;flags] per link. Flags bit 0
    set means the link is disabled, bit 1 that it is enforced. Read from the
    raw attribute rather than Get-GPInheritance, whose links arrive empty
    through PowerShell 7's compatibility session.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()][AllowEmptyString()][string]$GpLink = '',
        [Parameter(Mandatory)][string]$GpoGuid
    )
    $id = [regex]::Escape($GpoGuid.Trim('{', '}'))
    $m = [regex]::Match([string]$GpLink, "(?i)\[LDAP://cn=\{$id\},[^\];]*;(\d+)\]")
    if (-not $m.Success) { return [pscustomobject]@{ Linked = $false; Enabled = $false; Flags = -1 } }
    $flags = [int]$m.Groups[1].Value
    [pscustomobject]@{ Linked = $true; Enabled = (($flags -band 1) -eq 0); Flags = $flags }
}

function ConvertTo-UsaBannerLdapFilterValue {
    <#
    .SYNOPSIS
    -Value escaped for use inside an LDAP search filter (RFC 4515): \ * ( ) and
    NUL as \xx.
    .DESCRIPTION
    A GPO name with a parenthesis must not turn the search into another one.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $sb = [System.Text.StringBuilder]::new()
    foreach ($c in $Value.ToCharArray()) {
        switch ($c) {
            '\' { $null = $sb.Append('\5c') }
            '*' { $null = $sb.Append('\2a') }
            '(' { $null = $sb.Append('\28') }
            ')' { $null = $sb.Append('\29') }
            ([char]0) { $null = $sb.Append('\00') }
            default { $null = $sb.Append($c) }
        }
    }
    $sb.ToString()
}

function ConvertFrom-UsaBannerGpoReport {
    <#
    .SYNOPSIS
    From a Get-GPOReport -ReportType Xml text, the settings areas the GPO
    holds, as 'Computer: Scheduled Tasks', 'User: Registry', ...
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Xml)
    $doc = [System.Xml.XmlDocument]::new()
    $doc.LoadXml($Xml.TrimStart([char]0xFEFF))
    $gpo = $doc.DocumentElement
    foreach ($side in 'Computer', 'User') {
        Get-UsaBannerGpoXmlNode -Node $gpo -Path "$side/ExtensionData" | ForEach-Object { "${side}: $(Get-UsaBannerGpoXmlText -Node $_ -Path 'Name')" }
    }
}

#endregion

#region ----- ADSys startup values -----

function Get-UsaBannerGpoStartupMeta {
    <#
    .SYNOPSIS
    The metaValues text the ADSys administrative template writes for startup
    scripts: the append strategy for every release it names and for "all", so
    the startup scripts of every other GPO still run.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    '{' + ((@($script:UsaGpoAdsysReleases) | ForEach-Object { '"' + $_ + '":{"strategy":"append"}' }) -join ',') + '}'
}

function Get-UsaBannerGpoStartupChange {
    <#
    .SYNOPSIS
    What to change under the ADSys startup-scripts key so that it holds exactly
    -Wanted: a row per value to set (missing or different) and per value to
    remove (not wanted).
    .DESCRIPTION
    -Current and -Wanted map value names to @{ Type; Value }: Type as
    Get-GPRegistryValue reports it (String, MultiString, ...), Value a string
    or, for a MultiString, its lines. Lines compare in order, blank ones
    dropped; names compare in any case, as the registry does.
    Rows: Name, Action ('set' or 'remove'), Type and Value to write, and Old
    and New as display text - '' for absent, lines joined with ", ", and Old
    followed by its type in brackets when that changes too.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][hashtable]$Current,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Wanted
    )
    $lines = { param($v) if ($null -eq $v) { '' } else { @($v | ForEach-Object { "$_" } | Where-Object { $_ -ne '' }) -join "`n" } }
    foreach ($name in @($Wanted.Keys)) {
        $want = $Wanted[$name]
        $have = $Current[$name]
        $new = & $lines $want.Value
        $old = if ($null -ne $have) { & $lines $have.Value } else { '' }
        $typeDiffers = ($null -ne $have) -and ([string]$have.Type -ne [string]$want.Type)
        if ($null -eq $have -or $typeDiffers -or $old -cne $new) {
            [pscustomobject]@{
                Name   = $name
                Action = 'set'
                Type   = [string]$want.Type
                Value  = $want.Value
                Old    = ($old -replace "`n", ', ') + $(if ($typeDiffers) { " ($($have.Type))" } else { '' })
                New    = $new -replace "`n", ', '
            }
        }
    }
    foreach ($name in @($Current.Keys | Sort-Object)) {
        if ($Wanted.Contains($name)) { continue }
        [pscustomobject]@{
            Name   = $name
            Action = 'remove'
            Type   = [string]$Current[$name].Type
            Value  = $null
            Old    = (& $lines $Current[$name].Value) -replace "`n", ', '
            New    = ''
        }
    }
}

#endregion
