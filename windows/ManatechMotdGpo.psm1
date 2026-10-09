# ManatechMotdGpo.psm1 - the pure half of Publish-ManatechMotd.ps1's Group
# Policy step: what the "Manatech MOTD" GPO should hold, and how that differs
# from what a GPO of that name holds already. Nothing here talks to a domain
# (the publisher does), so all of it runs and is tested on any OS.
#
#   Get-MotdStartupMeta         the ADSys metaValues text: append, every release
#   Get-MotdStartupChange       which ADSys startup values to set or remove
#   New-MotdScheduledTasksXml   ScheduledTasks.xml with the sync task merged in
#   Get-MotdTaskField           a task item's account, command, triggers, limit
#   Compare-MotdTaskField       "field: 'old' -> 'new'" for each that differs
#   Test-MotdGppXmlSame         same GPP XML, layout and timestamps aside?
#   Merge-MotdTaskExtension     gPCMachineExtensionNames with Scheduled Tasks
#   Step-MotdGpoVersion         a GPO version with its computer half + 1
#   Get-MotdGptIniText          GPT.INI text with Version= set
#   ConvertFrom-MotdGpoReport   links and settings areas from Get-GPOReport
#
# ASCII only, like ManatechBanner.psm1: Windows PowerShell 5.1 reads a file
# without a BOM in the ANSI code page.

Set-StrictMode -Version 3.0

# Group Policy Preferences identifiers for scheduled tasks. The clsids go in
# ScheduledTasks.xml ([MS-GPPREF] 4.2.17, the ScheduledTasks example). The CSE
# and admin-tool GUIDs go in the GPO's gPCMachineExtensionNames: a client
# runs only the extensions listed there, so without the pair the file is
# ignored. GPMC also lists the tool under the all-zero CSE.
$script:Gpp = @{
    ContainerClsid = '{CC63F200-7309-4ba0-B154-A71CD118DBCC}'
    TaskV2Clsid    = '{D8896631-B747-47a7-84A6-C155337F3BC8}'
    Cse            = '{AADCED64-746C-4633-A97C-D61349046527}'
    Tool           = '{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}'
    ZeroCse        = '{00000000-0000-0000-0000-000000000000}'
}

# The releases the ADSys administrative template names, plus "all".
$script:AdsysReleases = @('22.04', '24.04', '25.04', '25.10', 'all')

#region ----- XML plumbing -----

# Get-MotdXmlNode NODE PATH - the nodes at PATH under NODE, PATH being local
# names joined with / (* = any element). By local name, so a namespace on
# the file (Get-GPOReport puts one on everything) does not matter.
function Get-MotdXmlNode {
    param([Parameter(Mandatory)][System.Xml.XmlNode]$Node, [Parameter(Mandatory)][string]$Path)
    $xpath = (@($Path -split '/') | ForEach-Object { if ($_ -eq '*') { '*' } else { "*[local-name()='$_']" } }) -join '/'
    @($Node.SelectNodes($xpath))
}

# Get-MotdXmlText NODE PATH - the text of the first node at PATH, or ''.
function Get-MotdXmlText {
    param([Parameter(Mandatory)][System.Xml.XmlNode]$Node, [Parameter(Mandatory)][string]$Path)
    $found = @(Get-MotdXmlNode -Node $Node -Path $Path)
    if ($found.Count) { $found[0].InnerText } else { '' }
}

# Add-MotdXmlChild PARENT SPEC - child elements from an ordered table: a
# name with text, or a name with a nested table.
function Add-MotdXmlChild {
    param([Parameter(Mandatory)][System.Xml.XmlElement]$Parent, [Parameter(Mandatory)][System.Collections.IDictionary]$Spec)
    foreach ($name in $Spec.Keys) {
        $child = $Parent.OwnerDocument.CreateElement($name)
        $value = $Spec[$name]
        if ($value -is [System.Collections.IDictionary]) { Add-MotdXmlChild -Parent $child -Spec $value }
        else { $child.InnerText = [string]$value }
        $null = $Parent.AppendChild($child)
    }
}

function ConvertTo-MotdGppXml {
    <#
    .SYNOPSIS
    The document as text, the way the GPP files here are written: an XML
    declaration, two-space indent, LF line ends. The caller writes it as
    UTF-8 without a BOM, which is what the declaration says.
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

function ConvertTo-MotdStableGuid {
    <#
    .SYNOPSIS
    A GUID from the first 16 bytes of SHA-256(Name), uppercase in braces.
    .DESCRIPTION
    A preference item's uid is its identity on a client. GPMC picks a random
    one; deriving it from the name keeps it the same at every publish.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $bytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Name)) } finally { $sha.Dispose() }
    # The [byte[]] cast matters: a slice is object[], and [guid]::new would
    # then pick its string overload.
    ([guid]::new([byte[]]$bytes[0..15])).ToString('B').ToUpperInvariant()
}

#endregion

#region ----- ADSys startup values -----

function Get-MotdStartupMeta {
    <#
    .SYNOPSIS
    The metaValues text the ADSys administrative template writes for startup
    scripts: the append strategy for every release it names and for "all",
    so the startup scripts of every other GPO still run.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    '{' + ((@($script:AdsysReleases) | ForEach-Object { '"' + $_ + '":{"strategy":"append"}' }) -join ',') + '}'
}

function Get-MotdStartupChange {
    <#
    .SYNOPSIS
    What to change under the ADSys startup-scripts key so that it holds
    exactly -Wanted: a row per value to set (missing or different) and per
    value to remove (not wanted).
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

#region ----- the scheduled task -----

# Format-MotdTrigger TRIGGER - one trigger of a Task Scheduler 2.0 task, in
# words: 'at startup', 'daily from <start> every PT4H for P1D', ...
function Format-MotdTrigger {
    param([Parameter(Mandatory)][System.Xml.XmlElement]$Trigger)
    $start = Get-MotdXmlText -Node $Trigger -Path 'StartBoundary'
    $text = switch ($Trigger.LocalName) {
        'BootTrigger'     { 'at startup' }
        'LogonTrigger'    { 'at logon' }
        'TimeTrigger'     { "once at $start" }
        'CalendarTrigger' {
            $days = Get-MotdXmlText -Node $Trigger -Path 'ScheduleByDay/DaysInterval'
            $kind = if (@(Get-MotdXmlNode -Node $Trigger -Path 'ScheduleByDay').Count) {
                if ($days -and $days -ne '1') { "every $days days" } else { 'daily' }
            } elseif (@(Get-MotdXmlNode -Node $Trigger -Path 'ScheduleByWeek').Count) { 'weekly' } else { 'monthly' }
            "$kind from $start"
        }
        default { $Trigger.LocalName }
    }
    $every = Get-MotdXmlText -Node $Trigger -Path 'Repetition/Interval'
    if ($every) {
        $text += " every $every"
        $for = Get-MotdXmlText -Node $Trigger -Path 'Repetition/Duration'
        if ($for) { $text += " for $for" }
    }
    $delay = Get-MotdXmlText -Node $Trigger -Path 'Delay'
    if ($delay) { $text += " after $delay" }
    if ((Get-MotdXmlText -Node $Trigger -Path 'Enabled') -eq 'false') { $text += ' (disabled)' }
    $text
}

function Get-MotdTaskField {
    <#
    .SYNOPSIS
    What a person compares between two scheduled-task items, as an ordered
    table of strings: Kind, Action, RunAs, RunLevel, Command, Arguments,
    Triggers, TimeLimit, Enabled, Filters. (Kind, not Item: on a dictionary,
    .Item is its indexer.)
    .DESCRIPTION
    Reads TaskV2 and ImmediateTaskV2 items (a Task Scheduler 2.0 task under
    Properties) and the older Task and ImmediateTask items (Properties
    attributes appName, args and Triggers\Trigger). What an item does not
    have reads as ''. Filters counts item-level targeting, which narrows the
    hosts an item reaches.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)][System.Xml.XmlElement]$Item)
    $f = [ordered]@{ Kind = $Item.LocalName; Action = 'U'; RunAs = ''; RunLevel = ''; Command = ''; Arguments = ''; Triggers = ''; TimeLimit = ''; Enabled = ''; Filters = 'none' }
    if ($Item.GetAttribute('disabled') -eq '1') { $f.Kind += ' (switched off in GPMC)' }
    $props = @(Get-MotdXmlNode -Node $Item -Path 'Properties')
    if ($props.Count) {
        $p = $props[0]
        if ($p.GetAttribute('action')) { $f.Action = $p.GetAttribute('action') }
        $f.RunAs = $p.GetAttribute('runAs')
        $task = @(Get-MotdXmlNode -Node $p -Path 'Task')
        if ($task.Count) {
            $t = $task[0]
            $f.RunLevel = Get-MotdXmlText -Node $t -Path 'Principals/Principal/RunLevel'
            $exec = @(Get-MotdXmlNode -Node $t -Path 'Actions/Exec')
            if ($exec.Count) {
                $f.Command = Get-MotdXmlText -Node $exec[0] -Path 'Command'
                $f.Arguments = Get-MotdXmlText -Node $exec[0] -Path 'Arguments'
                if ($exec.Count -gt 1) { $f.Command += " (and $($exec.Count - 1) more program(s))" }
            }
            $f.Triggers = (@(Get-MotdXmlNode -Node $t -Path 'Triggers/*') | ForEach-Object { Format-MotdTrigger -Trigger $_ }) -join '; '
            $f.TimeLimit = Get-MotdXmlText -Node $t -Path 'Settings/ExecutionTimeLimit'
            $f.Enabled = Get-MotdXmlText -Node $t -Path 'Settings/Enabled'
        } else {
            $f.Command = $p.GetAttribute('appName')
            $f.Arguments = $p.GetAttribute('args')
            $f.Triggers = (@(Get-MotdXmlNode -Node $p -Path 'Triggers/Trigger') | ForEach-Object { $_.GetAttribute('type') }) -join '; '
            $f.Enabled = $p.GetAttribute('enabled')
        }
    }
    $filters = @(Get-MotdXmlNode -Node $Item -Path 'Filters/*')
    if ($filters.Count) { $f.Filters = "$($filters.Count) item-level filter(s)" }
    $f
}

function Compare-MotdTaskField {
    <#
    .SYNOPSIS
    "Field: 'old' -> 'new'" for each field of -New that -Old has differently.
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

# New-MotdSyncTaskItem DOCUMENT TASKNAME SCRIPTPATH - the sync task as a
# TaskV2 item of DOCUMENT, not yet inserted. See New-MotdScheduledTasksXml.
function New-MotdSyncTaskItem {
    param(
        [Parameter(Mandatory)][System.Xml.XmlDocument]$Document,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    $doc = $Document
    $item = $doc.CreateElement('TaskV2')
    $item.SetAttribute('clsid', $script:Gpp.TaskV2Clsid)
    $item.SetAttribute('name', $TaskName)
    # image: the icon GPMC draws for the action (2 = update). Display only.
    $item.SetAttribute('image', '2')
    # changed: when the item was written. Ignored when files are compared.
    $item.SetAttribute('changed', (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
    $item.SetAttribute('uid', (ConvertTo-MotdStableGuid -Name "Manatech-MOTD|TaskV2|$TaskName"))
    # userContext 0: the computer's context. removePolicy 0: the task stays
    # on a host the GPO stops applying to (the README's "Remove" deletes it).
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
    Add-MotdXmlChild -Parent $task -Spec ([ordered]@{
        RegistrationInfo = [ordered]@{
            Author      = 'Publish-ManatechMotd.ps1'
            Description = 'Manatech login banner: runs Sync-ManatechBanner.ps1 from NETLOGON. Written by windows/Publish-ManatechMotd.ps1 (Manatech-MOTD); a publish overwrites changes made in GPMC.'
        }
    })
    $principals = $doc.CreateElement('Principals')
    $principal = $doc.CreateElement('Principal')
    $principal.SetAttribute('id', 'Author')
    Add-MotdXmlChild -Parent $principal -Spec ([ordered]@{ UserId = 'NT AUTHORITY\System'; LogonType = 'S4U'; RunLevel = 'HighestAvailable' })
    $null = $principals.AppendChild($principal)
    $null = $task.AppendChild($principals)

    # GPMC's defaults for a new task, but for the 30-minute time limit.
    $settings = $doc.CreateElement('Settings')
    Add-MotdXmlChild -Parent $settings -Spec ([ordered]@{
        IdleSettings               = [ordered]@{ Duration = 'PT10M'; WaitTimeout = 'PT1H'; StopOnIdleEnd = 'true'; RestartOnIdle = 'false' }
        MultipleInstancesPolicy    = 'IgnoreNew'
        DisallowStartIfOnBatteries = 'true'
        StopIfGoingOnBatteries     = 'true'
        AllowHardTerminate         = 'true'
        StartWhenAvailable         = 'false'
        RunOnlyIfNetworkAvailable  = 'false'
        AllowStartOnDemand         = 'true'
        Enabled                    = 'true'
        Hidden                     = 'false'
        RunOnlyIfIdle              = 'false'
        WakeToRun                  = 'false'
        ExecutionTimeLimit         = 'PT30M'
        Priority                   = '7'
    })
    $null = $task.AppendChild($settings)

    # Child order as the Task Scheduler schema's trigger types have it:
    # Enabled, StartBoundary, Repetition, then the schedule.
    $triggers = $doc.CreateElement('Triggers')
    $boot = $doc.CreateElement('BootTrigger')
    Add-MotdXmlChild -Parent $boot -Spec ([ordered]@{ Enabled = 'true' })
    $null = $triggers.AppendChild($boot)
    # Daily from midnight (host time), repeated every 4 hours for the day.
    $daily = $doc.CreateElement('CalendarTrigger')
    Add-MotdXmlChild -Parent $daily -Spec ([ordered]@{
        Enabled       = 'true'
        StartBoundary = '2026-01-01T00:00:00'
        Repetition    = [ordered]@{ Interval = 'PT4H'; Duration = 'P1D'; StopAtDurationEnd = 'false' }
        ScheduleByDay = [ordered]@{ DaysInterval = '1' }
    })
    $null = $triggers.AppendChild($daily)
    $null = $task.AppendChild($triggers)

    $actions = $doc.CreateElement('Actions')
    # Context Author: run as the Principal whose id is Author - SYSTEM, above.
    $actions.SetAttribute('Context', 'Author')
    $exec = $doc.CreateElement('Exec')
    # Bypass: a script on a UNC path counts as remote under RemoteSigned.
    Add-MotdXmlChild -Parent $exec -Spec ([ordered]@{
        Command   = 'powershell.exe'
        Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`""
    })
    $null = $actions.AppendChild($exec)
    $null = $task.AppendChild($actions)

    $null = $props.AppendChild($task)
    $null = $item.AppendChild($props)
    $item
}

function New-MotdScheduledTasksXml {
    <#
    .SYNOPSIS
    The GPO's ScheduledTasks.xml: -Existing (the file's text, blank for none)
    with the sync task merged in.
    .DESCRIPTION
    The sync task is a TaskV2 item ("Scheduled Task (At least Windows 7)" in
    GPMC) named -TaskName: NT AUTHORITY\System with highest privileges, at
    startup and daily every 4 hours, stopped after 30 minutes, running
    powershell.exe -File -ScriptPath.
    Every item for -TaskName (by its name or its task's name, any case, any
    kind of task item) is replaced: the sync task takes the first one's
    place, and the others go. With none, the sync task is added at the end.
    Items for other tasks are kept as they are. A disabled="1" on the root,
    which switches every item off, is removed.
    Returns Xml (the new file text), Fields (Get-MotdTaskField of the sync
    task), Replaced (Name, Item, Uid and Fields of each replaced item, in file
    order), Kept (a label per item left alone) and RootWasDisabled.
    Throws when -Existing is not XML, or not a ScheduledTasks file: a file
    this cannot read is not overwritten.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [AllowNull()][AllowEmptyString()][string]$Existing,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$ScriptPath
    )
    $doc = [System.Xml.XmlDocument]::new()
    if ([string]::IsNullOrWhiteSpace($Existing)) {
        $null = $doc.AppendChild($doc.CreateXmlDeclaration('1.0', 'utf-8', $null))
        $root = $doc.CreateElement('ScheduledTasks')
        $root.SetAttribute('clsid', $script:Gpp.ContainerClsid)
        $null = $doc.AppendChild($root)
    } else {
        try { $doc.LoadXml($Existing.TrimStart([char]0xFEFF)) }
        catch { throw "ScheduledTasks.xml is not XML this can read ($($_.Exception.Message)); fix or delete it in GPMC, then publish again." }
        $root = $doc.DocumentElement
        if ($root.LocalName -ne 'ScheduledTasks') { throw "ScheduledTasks.xml has a <$($root.LocalName)> root, not <ScheduledTasks>; fix or delete it in GPMC, then publish again." }
    }
    $rootWasDisabled = $root.GetAttribute('disabled') -eq '1'
    if ($rootWasDisabled) { $root.RemoveAttribute('disabled') }

    $new = New-MotdSyncTaskItem -Document $doc -TaskName $TaskName -ScriptPath $ScriptPath
    $replaced = [System.Collections.Generic.List[object]]::new()
    $kept = [System.Collections.Generic.List[string]]::new()
    $first = $null
    foreach ($node in @($root.ChildNodes)) {
        if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
        $props = @(Get-MotdXmlNode -Node $node -Path 'Properties')
        $taskOf = if ($props.Count) { $props[0].GetAttribute('name') } else { '' }
        if ($node.GetAttribute('name') -eq $TaskName -or $taskOf -eq $TaskName) {
            $replaced.Add([pscustomobject]@{ Name = $node.GetAttribute('name'); Item = $node.LocalName; Uid = $node.GetAttribute('uid'); Fields = Get-MotdTaskField -Item $node })
            if ($null -eq $first) { $first = $node } else { $null = $root.RemoveChild($node) }
        } else {
            $kept.Add("$($node.LocalName) '$($node.GetAttribute('name'))'")
        }
    }
    if ($null -ne $first) { $null = $root.ReplaceChild($new, $first) } else { $null = $root.AppendChild($new) }

    [pscustomobject]@{
        Xml             = ConvertTo-MotdGppXml -Document $doc
        Fields          = Get-MotdTaskField -Item $new
        Replaced        = $replaced.ToArray()
        Kept            = $kept.ToArray()
        RootWasDisabled = $rootWasDisabled
    }
}

function Test-MotdGppXmlSame {
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
        (ConvertTo-MotdGppXml -Document $d) -replace 'changed="[^"]*"', 'changed=""'
    }
    try { (& $norm $Existing) -ceq (& $norm $Desired) } catch { $false }
}

#endregion

#region ----- the GPO object -----

function Merge-MotdTaskExtension {
    <#
    .SYNOPSIS
    The GPO's gPCMachineExtensionNames text -Existing with the Scheduled Tasks
    extension added; unchanged when it is there already.
    .DESCRIPTION
    The value is [{CSE}{tool}...] groups: CSE groups in ascending order, the
    tools inside a group too, all uppercase, compared ordinally (a culture
    sort can order GUIDs differently from GPMC, and the value would then
    differ at every run). Every group already there is kept, so what other
    settings registered survives.
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
    foreach ($cse in @($script:Gpp.Cse, $script:Gpp.ZeroCse)) {
        if (-not $groups.ContainsKey($cse)) { $groups[$cse] = [System.Collections.Generic.HashSet[string]]::new() }
        $null = $groups[$cse].Add($script:Gpp.Tool)
    }
    $keys = [string[]]@($groups.Keys)
    [array]::Sort($keys, [System.StringComparer]::Ordinal)
    -join @(foreach ($cse in $keys) {
        $tools = [string[]]@($groups[$cse])
        [array]::Sort($tools, [System.StringComparer]::Ordinal)
        '[' + $cse + (-join $tools) + ']'
    })
}

function Step-MotdGpoVersion {
    <#
    .SYNOPSIS
    -Version with its computer half (the low 16 bits) up by one; the user
    half (the high 16 bits) as it was.
    .DESCRIPTION
    A GPO's version is one 32-bit number, in AD (versionNumber) and in its
    GPT.INI (Version=). A client applies a GPO again only when that number
    differs from the one it applied last, and these settings are all on the
    computer side. The computer half wraps at 16 bits rather than spill into
    the user half.
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param([Parameter(Mandatory)][ValidateRange(0, 4294967295)][long]$Version)
    $user = ($Version -shr 16) -band 0xFFFF
    $computer = (($Version -band 0xFFFF) + 1) -band 0xFFFF
    [long](($user -shl 16) -bor $computer)
}

function Get-MotdGptIniText {
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

function ConvertFrom-MotdGpoReport {
    <#
    .SYNOPSIS
    From a Get-GPOReport -ReportType Xml text: where the GPO is linked
    (Links: Path, Enabled) and the settings areas it holds (Areas:
    'Computer: Registry', 'User: ...').
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Xml)
    $doc = [System.Xml.XmlDocument]::new()
    $doc.LoadXml($Xml.TrimStart([char]0xFEFF))
    $gpo = $doc.DocumentElement
    [pscustomobject]@{
        Links = @(Get-MotdXmlNode -Node $gpo -Path 'LinksTo' | ForEach-Object {
            [pscustomobject]@{ Path = Get-MotdXmlText -Node $_ -Path 'SOMPath'; Enabled = ((Get-MotdXmlText -Node $_ -Path 'Enabled') -eq 'true') }
        })
        Areas = @(foreach ($side in 'Computer', 'User') {
            Get-MotdXmlNode -Node $gpo -Path "$side/ExtensionData" | ForEach-Object { "${side}: $(Get-MotdXmlText -Node $_ -Path 'Name')" }
        })
    }
}

#endregion

Export-ModuleMember -Function Get-MotdStartupMeta, Get-MotdStartupChange, New-MotdScheduledTasksXml,
    Get-MotdTaskField, Compare-MotdTaskField, Test-MotdGppXmlSame, Merge-MotdTaskExtension,
    Step-MotdGpoVersion, Get-MotdGptIniText, ConvertFrom-MotdGpoReport, ConvertTo-MotdStableGuid
