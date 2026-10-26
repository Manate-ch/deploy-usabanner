# GpoPolicy.Logged.ps1 - the functions of GpoPolicy.ps1 that PowerShell logs whole at each import (D30).

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
