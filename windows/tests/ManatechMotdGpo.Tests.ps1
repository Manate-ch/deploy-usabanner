# Pester 5 tests for ManatechMotdGpo.psm1, the pure half of
# Publish-ManatechMotd.ps1's GPO step. The domain half (New-GPO, the AD
# object, SYSVOL on the PDC) is proved on a DC.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../ManatechMotdGpo.psm1') -Force

    $script:Sync = '\\example.test\NETLOGON\MOTD\windows\Sync-ManatechBanner.ps1'
    $script:Wanted = [ordered]@{
        metaValues = @{ Type = 'String'; Value = (Get-MotdStartupMeta) }
        all        = @{ Type = 'MultiString'; Value = @('MOTD/adsys-startup.sh') }
    }

    # New-Xml TEXT - TEXT parsed, for assertions on the structure.
    function New-Xml { param([string]$Text) $d = [System.Xml.XmlDocument]::new(); $d.LoadXml($Text); $d }
    # Get-Node DOC XPATH - nodes by XPath (no namespaces in GPP files). Index
    # it as @(Get-Node ...)[0]: a single match comes out as the bare element,
    # and [0] on an XmlElement asks for a child element named "0" ($null).
    function Get-Node { param($Doc, [string]$XPath) @($Doc.SelectNodes($XPath)) }

    # A task item the way GPMC writes one by hand: its own uid and layout,
    # CRLF, and the action pointing at the SYSVOL copy.
    $script:HandMade = @"
<?xml version="1.0" encoding="utf-8"?>`r
<ScheduledTasks clsid="{CC63F200-7309-4ba0-B154-A71CD118DBCC}"><TaskV2 clsid="{D8896631-B747-47a7-84A6-C155337F3BC8}" name="Manatech MOTD sync" image="2" changed="2026-09-25 09:15:00" uid="{0F0F0F0F-1111-2222-3333-444444444444}" userContext="0" removePolicy="0"><Properties action="U" name="Manatech MOTD sync" runAs="NT AUTHORITY\System" logonType="S4U"><Task version="1.3"><RegistrationInfo><Author>EXAMPLE\admin</Author><Description></Description></RegistrationInfo><Principals><Principal id="Author"><UserId>NT AUTHORITY\System</UserId><LogonType>S4U</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals><Settings><ExecutionTimeLimit>PT30M</ExecutionTimeLimit><Enabled>true</Enabled></Settings><Triggers><BootTrigger><Enabled>true</Enabled></BootTrigger><CalendarTrigger><StartBoundary>2026-09-25T09:15:00</StartBoundary><Enabled>true</Enabled><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay><Repetition><Interval>PT4H</Interval><Duration>P1D</Duration><StopAtDurationEnd>false</StopAtDurationEnd></Repetition></CalendarTrigger></Triggers><Actions Context="Author"><Exec><Command>powershell.exe</Command><Arguments>-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "\\example.test\SYSVOL\example.test\Ubuntu\scripts\MOTD\windows\Sync-ManatechBanner.ps1"</Arguments></Exec></Actions></Task></Properties></TaskV2><TaskV2 clsid="{D8896631-B747-47a7-84A6-C155337F3BC8}" name="Other task" image="2" changed="2026-09-25 09:16:00" uid="{0E0E0E0E-1111-2222-3333-444444444444}"><Properties action="U" name="Other task" runAs="NT AUTHORITY\System" logonType="S4U"><Task version="1.3"><Actions><Exec><Command>cmd.exe</Command></Exec></Actions></Task></Properties></TaskV2></ScheduledTasks>`r
"@
}

Describe 'the shipped Windows sources' {
    It 'are ASCII only: Windows PowerShell 5.1 reads a file without a BOM in the ANSI code page' {
        $files = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..') -File | Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' })
        $files.Count | Should -BeGreaterThan 3
        foreach ($f in $files) {
            $bad = @([System.IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 127 })
            "$($f.Name): $($bad.Count) non-ASCII byte(s)" | Should -Be "$($f.Name): 0 non-ASCII byte(s)"
        }
    }
}

Describe 'Get-MotdStartupMeta' {
    It 'is the append strategy for every release the ADSys template names and for all (the same text the ADSys fix GPO carries)' {
        Get-MotdStartupMeta | Should -BeExactly '{"22.04":{"strategy":"append"},"24.04":{"strategy":"append"},"25.04":{"strategy":"append"},"25.10":{"strategy":"append"},"all":{"strategy":"append"}}'
    }
}

Describe 'Get-MotdStartupChange' {
    It 'sets both values on a GPO that has none' {
        $rows = @(Get-MotdStartupChange -Current @{} -Wanted $Wanted)
        $rows.Name | Should -Be @('metaValues', 'all')
        $rows.Action | Should -Be @('set', 'set')
        $rows[1].Old | Should -BeExactly ''
        $rows[1].New | Should -BeExactly 'MOTD/adsys-startup.sh'
    }
    It 'changes nothing when the GPO holds exactly those values, whatever the case of their names' {
        $current = @{ METAVALUES = @{ Type = 'String'; Value = (Get-MotdStartupMeta) }; All = @{ Type = 'MultiString'; Value = @('MOTD/adsys-startup.sh', '') } }
        @(Get-MotdStartupChange -Current $current -Wanted $Wanted).Count | Should -Be 0
    }
    It 'overwrites a different script list and shows the old one' {
        $current = @{ metaValues = @{ Type = 'String'; Value = (Get-MotdStartupMeta) }; all = @{ Type = 'MultiString'; Value = @('MOTD/adsys-startup.sh', 'other/x.sh') } }
        $rows = @(Get-MotdStartupChange -Current $current -Wanted $Wanted)
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'all'
        $rows[0].Old | Should -BeExactly 'MOTD/adsys-startup.sh, other/x.sh'
        $rows[0].Value | Should -Be @('MOTD/adsys-startup.sh')
    }
    It 'overwrites a value of the wrong type even when its text matches, and says which type it was' {
        $current = @{ metaValues = @{ Type = 'String'; Value = (Get-MotdStartupMeta) }; all = @{ Type = 'String'; Value = 'MOTD/adsys-startup.sh' } }
        $rows = @(Get-MotdStartupChange -Current $current -Wanted $Wanted)
        $rows.Count | Should -Be 1
        $rows[0].Old | Should -BeExactly 'MOTD/adsys-startup.sh (String)'
        $rows[0].Type | Should -Be 'MultiString'
    }
    It 'removes any other value under the key (a release-specific list would replace "all" on that release)' {
        $current = @{ metaValues = @{ Type = 'String'; Value = (Get-MotdStartupMeta) }; all = @{ Type = 'MultiString'; Value = @('MOTD/adsys-startup.sh') }; '24.04' = @{ Type = 'MultiString'; Value = @('MOTD/old.sh') } }
        $rows = @(Get-MotdStartupChange -Current $current -Wanted $Wanted)
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be '24.04'
        $rows[0].Action | Should -Be 'remove'
        $rows[0].Old | Should -BeExactly 'MOTD/old.sh'
    }
}

Describe 'New-MotdScheduledTasksXml, a GPO with no ScheduledTasks.xml yet' {
    BeforeAll {
        $script:r = New-MotdScheduledTasksXml -Existing $null -TaskName 'Manatech MOTD sync' -ScriptPath $Sync
        $script:doc = New-Xml $r.Xml
        $script:item = @(Get-Node $doc '/ScheduledTasks/TaskV2')[0]
    }
    It 'is one TaskV2 item in a ScheduledTasks file, with the clsids of [MS-GPPREF] 4.2.17' {
        $doc.DocumentElement.GetAttribute('clsid') | Should -BeExactly '{CC63F200-7309-4ba0-B154-A71CD118DBCC}'
        @(Get-Node $doc '/ScheduledTasks/*').Count | Should -Be 1
        $item.GetAttribute('clsid') | Should -BeExactly '{D8896631-B747-47a7-84A6-C155337F3BC8}'
        $item.GetAttribute('name') | Should -BeExactly 'Manatech MOTD sync'
        $item.GetAttribute('userContext') | Should -Be '0'
        $item.GetAttribute('removePolicy') | Should -Be '0'
        $r.Replaced.Count | Should -Be 0
        $r.Kept.Count | Should -Be 0
    }
    It 'keeps its uid from one publish to the next, so a client updates the task instead of adding a second' {
        $again = New-Xml (New-MotdScheduledTasksXml -Existing $null -TaskName 'Manatech MOTD sync' -ScriptPath $Sync).Xml
        @(Get-Node $again '/ScheduledTasks/TaskV2')[0].GetAttribute('uid') | Should -BeExactly $item.GetAttribute('uid')
        $item.GetAttribute('uid') | Should -Match '^\{[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\}$'
    }
    It 'runs as SYSTEM with highest privileges, updating the task in place' {
        $p = @(Get-Node $doc '/ScheduledTasks/TaskV2/Properties')[0]
        $p.GetAttribute('action') | Should -BeExactly 'U'
        $p.GetAttribute('name') | Should -BeExactly 'Manatech MOTD sync'
        $p.GetAttribute('runAs') | Should -BeExactly 'NT AUTHORITY\System'
        $p.GetAttribute('logonType') | Should -BeExactly 'S4U'
        @(Get-Node $doc '//Task')[0].GetAttribute('version') | Should -Be '1.3'
        @(Get-Node $doc '//Principals/Principal')[0].GetAttribute('id') | Should -BeExactly 'Author'
        @(Get-Node $doc '//Principal/UserId')[0].InnerText | Should -BeExactly 'NT AUTHORITY\System'
        @(Get-Node $doc '//Principal/RunLevel')[0].InnerText | Should -BeExactly 'HighestAvailable'
        @(Get-Node $doc '//Actions')[0].GetAttribute('Context') | Should -BeExactly 'Author'
    }
    It 'starts at boot and daily, repeating every 4 hours for the day, children in the order the Task Scheduler schema gives them' {
        @(@(Get-Node $doc '//Triggers')[0].ChildNodes | ForEach-Object { $_.LocalName }) | Should -Be @('BootTrigger', 'CalendarTrigger')
        $cal = @(Get-Node $doc '//Triggers/CalendarTrigger')[0]
        @($cal.ChildNodes | ForEach-Object { $_.LocalName }) | Should -Be @('Enabled', 'StartBoundary', 'Repetition', 'ScheduleByDay')
        @(Get-Node $doc '//CalendarTrigger/Repetition/Interval')[0].InnerText | Should -BeExactly 'PT4H'
        @(Get-Node $doc '//CalendarTrigger/Repetition/Duration')[0].InnerText | Should -BeExactly 'P1D'
        @(Get-Node $doc '//CalendarTrigger/ScheduleByDay/DaysInterval')[0].InnerText | Should -Be '1'
    }
    It 'stops a run after 30 minutes' {
        @(Get-Node $doc '//Settings/ExecutionTimeLimit')[0].InnerText | Should -BeExactly 'PT30M'
        @(Get-Node $doc '//Settings/Enabled')[0].InnerText | Should -BeExactly 'true'
        @(Get-Node $doc '//Settings/DeleteExpiredTaskAfter').Count | Should -Be 0
    }
    It 'runs the sync script from the path given, unprofiled and with Bypass (a UNC script is remote under RemoteSigned)' {
        @(Get-Node $doc '//Exec/Command')[0].InnerText | Should -BeExactly 'powershell.exe'
        @(Get-Node $doc '//Exec/Arguments')[0].InnerText | Should -BeExactly "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$Sync`""
    }
    It 'is written UTF-8 style with LF line ends and no BOM' {
        $r.Xml | Should -Match '^<\?xml version="1.0" encoding="utf-8"\?>\n<ScheduledTasks '
        $r.Xml | Should -Not -Match "`r"
        [int][char]$r.Xml[0] | Should -Not -Be 0xFEFF
    }
    It 'describes itself for the overwrite warnings' {
        $r.Fields.Kind | Should -BeExactly 'TaskV2'
        $r.Fields.RunAs | Should -BeExactly 'NT AUTHORITY\System'
        $r.Fields.Triggers | Should -BeExactly 'at startup; daily from 2026-01-01T00:00:00 every PT4H for P1D'
        $r.Fields.TimeLimit | Should -BeExactly 'PT30M'
        $r.Fields.Filters | Should -BeExactly 'none'
    }
}

Describe 'New-MotdScheduledTasksXml, a GPO that holds tasks already' {
    It 'replaces the item for the sync task where it stands and keeps the items of other tasks as they were' {
        $r = New-MotdScheduledTasksXml -Existing $HandMade -TaskName 'Manatech MOTD sync' -ScriptPath $Sync
        $doc = New-Xml $r.Xml
        @(Get-Node $doc '/ScheduledTasks/*' | ForEach-Object { $_.GetAttribute('name') }) | Should -Be @('Manatech MOTD sync', 'Other task')
        @(Get-Node $doc '/ScheduledTasks/TaskV2')[1].GetAttribute('uid') | Should -BeExactly '{0E0E0E0E-1111-2222-3333-444444444444}'
        @(Get-Node $doc '/ScheduledTasks/TaskV2')[0].GetAttribute('uid') | Should -Not -Be '{0F0F0F0F-1111-2222-3333-444444444444}'
        $r.Kept | Should -Be @("TaskV2 'Other task'")
        $r.Replaced.Count | Should -Be 1
        $r.Replaced[0].Uid | Should -BeExactly '{0F0F0F0F-1111-2222-3333-444444444444}'
    }
    It 'reports what the replaced item had, field by field' {
        $r = New-MotdScheduledTasksXml -Existing $HandMade -TaskName 'Manatech MOTD sync' -ScriptPath $Sync
        $diff = @(Compare-MotdTaskField -Old $r.Replaced[0].Fields -New $r.Fields)
        $diff.Count | Should -Be 2
        $diff[0] | Should -BeLike "Arguments: '*\Ubuntu\scripts\MOTD\windows\Sync-ManatechBanner.ps1`"' -> '*\NETLOGON\MOTD\windows\Sync-ManatechBanner.ps1`"'"
        $diff[1] | Should -BeExactly "Triggers: 'at startup; daily from 2026-09-25T09:15:00 every PT4H for P1D' -> 'at startup; daily from 2026-01-01T00:00:00 every PT4H for P1D'"
    }
    It 'finds the sync task by its task name too, and replaces every item for it' {
        $two = $HandMade -replace 'name="Other task" image', 'name="renamed in GPMC" image' -replace 'name="Other task" runAs', 'name="MANATECH MOTD SYNC" runAs'
        $r = New-MotdScheduledTasksXml -Existing $two -TaskName 'Manatech MOTD sync' -ScriptPath $Sync
        @(Get-Node (New-Xml $r.Xml) '/ScheduledTasks/*').Count | Should -Be 1
        $r.Replaced.Count | Should -Be 2
        $r.Kept.Count | Should -Be 0
    }
    It 'replaces an older Task item for it too, read from its attributes' {
        $old = '<ScheduledTasks clsid="{CC63F200-7309-4ba0-B154-A71CD118DBCC}"><Task clsid="{2DEECB1C-261F-4e13-9B21-16FB83BC03BD}" name="Manatech MOTD sync" uid="{01010101-1111-2222-3333-444444444444}"><Properties action="U" name="Manatech MOTD sync" appName="powershell.exe" args="-File x.ps1" enabled="1"><Triggers><Trigger type="DAILY"/></Triggers></Properties></Task></ScheduledTasks>'
        $r = New-MotdScheduledTasksXml -Existing $old -TaskName 'Manatech MOTD sync' -ScriptPath $Sync
        $r.Replaced[0].Fields.Kind | Should -BeExactly 'Task'
        $r.Replaced[0].Fields.Command | Should -BeExactly 'powershell.exe'
        $r.Replaced[0].Fields.Arguments | Should -BeExactly '-File x.ps1'
        $r.Replaced[0].Fields.Triggers | Should -BeExactly 'DAILY'
        @(Get-Node (New-Xml $r.Xml) '/ScheduledTasks/TaskV2').Count | Should -Be 1
    }
    It 'switches a file that was switched off as a whole back on, and says it was off' {
        $off = $HandMade -replace '<ScheduledTasks clsid="([^"]+)">', '<ScheduledTasks clsid="$1" disabled="1">'
        $r = New-MotdScheduledTasksXml -Existing $off -TaskName 'Manatech MOTD sync' -ScriptPath $Sync
        $r.RootWasDisabled | Should -BeTrue
        (New-Xml $r.Xml).DocumentElement.HasAttribute('disabled') | Should -BeFalse
    }
    It 'shows a switched-off item and item-level targeting in its fields' {
        $narrow = $HandMade -replace 'removePolicy="0">', 'removePolicy="0" disabled="1">' -replace '</Properties></TaskV2><TaskV2', '</Properties><Filters><FilterComputer bool="AND" not="0" type="NETBIOS" name="SRV-EXAMPLE"/></Filters></TaskV2><TaskV2'
        $r = New-MotdScheduledTasksXml -Existing $narrow -TaskName 'Manatech MOTD sync' -ScriptPath $Sync
        $r.Replaced[0].Fields.Kind | Should -BeExactly 'TaskV2 (switched off in GPMC)'
        $r.Replaced[0].Fields.Filters | Should -BeExactly '1 item-level filter(s)'
    }
    It 'refuses a file it cannot read rather than overwrite what is in it' {
        { New-MotdScheduledTasksXml -Existing '<ScheduledTasks><TaskV2' -TaskName 'x' -ScriptPath $Sync } | Should -Throw '*not XML this can read*'
        { New-MotdScheduledTasksXml -Existing '<Files clsid="{215B2E53-57CE-475c-80FE-9EEC14635851}"/>' -TaskName 'x' -ScriptPath $Sync } | Should -Throw '*not <ScheduledTasks>*'
    }
}

Describe 'Test-MotdGppXmlSame' {
    BeforeAll { $script:mine = (New-MotdScheduledTasksXml -Existing $null -TaskName 'Manatech MOTD sync' -ScriptPath $Sync).Xml }
    It 'is the same file when only the changed stamps differ, so a re-publish writes nothing and bumps nothing' {
        $later = $mine -replace 'changed="[^"]*"', 'changed="2099-12-31 23:59:59"'
        Test-MotdGppXmlSame -Existing $later -Desired $mine | Should -BeTrue
    }
    It 'is the same file laid out another way: one line, CRLF, a BOM' {
        $d = New-Xml $mine
        $flat = [string][char]0xFEFF + ($d.OuterXml -replace '\?>', "?>`r`n")
        Test-MotdGppXmlSame -Existing $flat -Desired $mine | Should -BeTrue
    }
    It 'is a different file when a setting differs' {
        Test-MotdGppXmlSame -Existing ($mine -replace 'PT30M', 'PT72H') -Desired $mine | Should -BeFalse
    }
    It 'is never the same as a missing or unreadable file' {
        Test-MotdGppXmlSame -Existing $null -Desired $mine | Should -BeFalse
        Test-MotdGppXmlSame -Existing '<ScheduledTasks' -Desired $mine | Should -BeFalse
    }
}

Describe 'Merge-MotdTaskExtension' {
    It 'registers the Scheduled Tasks CSE with its tool, and the tool under the all-zero CSE as GPMC does' {
        Merge-MotdTaskExtension -Existing '' | Should -BeExactly '[{00000000-0000-0000-0000-000000000000}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}][{AADCED64-746C-4633-A97C-D61349046527}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]'
    }
    It 'keeps what other settings registered (Set-GPRegistryValue''s pair here), in GUID order' {
        $registry = '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
        Merge-MotdTaskExtension -Existing $registry | Should -BeExactly ('[{00000000-0000-0000-0000-000000000000}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]' + $registry + '[{AADCED64-746C-4633-A97C-D61349046527}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]')
    }
    It 'returns the value unchanged once the pair is there, so a re-publish writes nothing' {
        $once = Merge-MotdTaskExtension -Existing '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
        Merge-MotdTaskExtension -Existing $once | Should -BeExactly $once
    }
    It 'writes GUIDs uppercase and keeps every tool of a shared group' {
        $mixed = '[{00000000-0000-0000-0000-000000000000}{bee07a6a-ec9f-4659-b8c9-0b1937907c83}]'
        Merge-MotdTaskExtension -Existing $mixed | Should -BeLike '`[{00000000-0000-0000-0000-000000000000}{BEE07A6A-EC9F-4659-B8C9-0B1937907C83}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}`]*'
    }
}

Describe 'Step-MotdGpoVersion' {
    It 'adds one to the computer half (the low 16 bits) only' {
        Step-MotdGpoVersion -Version 0 | Should -Be 1
        Step-MotdGpoVersion -Version 6 | Should -Be 7
        Step-MotdGpoVersion -Version 0x00030004 | Should -Be 0x00030005
    }
    It 'wraps the computer half rather than spill into the user half' {
        Step-MotdGpoVersion -Version 0x0001FFFF | Should -Be 0x00010000
    }
}

Describe 'Get-MotdGptIniText' {
    It 'replaces Version= where it is and keeps the other lines, CRLF' {
        Get-MotdGptIniText -Content "[General]`r`nVersion=6`r`ndisplayName=New Group Policy Object`r`n" -Version 7 |
            Should -BeExactly "[General]`r`nVersion=7`r`ndisplayName=New Group Policy Object`r`n"
    }
    It 'adds Version= under [General] when there is none, and the section when that is missing too' {
        Get-MotdGptIniText -Content "[General]`r`ndisplayName=x`r`n" -Version 3 | Should -BeExactly "[General]`r`nVersion=3`r`ndisplayName=x`r`n"
        Get-MotdGptIniText -Content '' -Version 1 | Should -BeExactly "[General]`r`nVersion=1`r`n"
    }
}

Describe 'ConvertFrom-MotdGpoReport' {
    It 'reads links and settings areas through the report''s namespaces' {
        $report = @'
<?xml version="1.0" encoding="utf-16"?>
<GPO xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.microsoft.com/GroupPolicy/Settings">
  <Name>Manatech MOTD</Name>
  <Computer>
    <VersionDirectory>4</VersionDirectory>
    <ExtensionData><Extension xmlns:q1="http://www.microsoft.com/GroupPolicy/Settings/Registry" xsi:type="q1:RegistrySettings"/><Name>Registry</Name></ExtensionData>
    <ExtensionData><Extension xmlns:q2="http://www.microsoft.com/GroupPolicy/Settings/ScheduledTasks" xsi:type="q2:ScheduledTasksSettings"/><Name>Scheduled Tasks</Name></ExtensionData>
  </Computer>
  <User><VersionDirectory>0</VersionDirectory></User>
  <LinksTo><SOMName>Linux</SOMName><SOMPath>example.test/Linux</SOMPath><Enabled>true</Enabled><NoOverride>false</NoOverride></LinksTo>
  <LinksTo><SOMName>Servers</SOMName><SOMPath>example.test/Servers</SOMPath><Enabled>false</Enabled><NoOverride>false</NoOverride></LinksTo>
</GPO>
'@
        $r = ConvertFrom-MotdGpoReport -Xml $report
        $r.Areas | Should -Be @('Computer: Registry', 'Computer: Scheduled Tasks')
        $r.Links.Path | Should -Be @('example.test/Linux', 'example.test/Servers')
        $r.Links.Enabled | Should -Be @($true, $false)
    }
    It 'has no links for a GPO linked nowhere' {
        $r = ConvertFrom-MotdGpoReport -Xml '<GPO xmlns="http://www.microsoft.com/GroupPolicy/Settings"><Computer/><User/></GPO>'
        @($r.Links).Count | Should -Be 0
        @($r.Areas).Count | Should -Be 0
    }
}
