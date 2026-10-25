# The pure half of Deploy-UsaBannerGPO (UsaBanner/Private/GpoPolicy.ps1, docs/DECISIONS.md, D29):
# the task the GPO carries (its ScheduledTasks.xml item, an ImmediateTaskV2 that runs the
# Windows runner as SYSTEM on servers only, and how it merges into a file that holds other
# items), the parts of a GPO the command writes besides the task (the extension list clients
# read, the version they compare, GPT.INI, the link test, the LDAP escape, the report reader),
# the ADSys startup values, and the two file helpers (CRLF to LF, a path inside a folder).
# Ported from deploy-usawinssh's tests of the same functions, which a lab domain proved. Nothing
# here needs a domain: the command itself is tested in GpoDeploy.Tests.ps1, against a fake one.

BeforeAll {
    $moduleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'UsaBanner'
    Import-Module (Join-Path $moduleRoot 'UsaBanner.psd1') -Force
    $script:Script = '\\ad.example\NETLOGON\UsaBanner\UsaBanner\windows\Sync-UsaBanner.ps1'
    $script:Arguments = InModuleScope UsaBanner -Parameters @{ Script = $script:Script } { param($Script) Get-UsaBannerGpoTaskArgument -ScriptPath $Script }
    $script:Tasks = '[{AADCED64-746C-4633-A97C-D61349046527}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]'
    $script:Zero = '[{00000000-0000-0000-0000-000000000000}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]'

    function Get-TasksXml {
        # In:  the file's text (none for a GPO with no file yet) and the arguments to give the task
        # Out: the result of New-UsaBannerGpoTasksXml
        param([string]$Existing = '', [string]$Arguments = $script:Arguments)
        InModuleScope UsaBanner -Parameters @{ Existing = $Existing; Arguments = $Arguments } {
            param($Existing, $Arguments)
            New-UsaBannerGpoTasksXml -Existing $Existing -TaskName 'UsaBanner sync' -Arguments $Arguments
        }
    }

    function Get-Item1 {
        # In:  the text of a ScheduledTasks.xml, and an item's name
        # Out: the first item with that name, by local name, as an XmlElement
        param([string]$Text, [string]$Name = 'UsaBanner sync')
        $doc = [xml]$Text
        @($doc.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.GetAttribute('name') -eq $Name })[0]
    }

    function New-TaskV2 {
        # Out: a TaskV2 item of the kind GPMC writes: its name, its uid, and the program and
        #      arguments of its one action
        param([string]$Name, [string]$Uid, [string]$Command = 'cmd.exe', [string]$Arguments = '')
        $argumentsXml = if ($Arguments) { "<Arguments>$Arguments</Arguments>" } else { '' }
        '<TaskV2 clsid="{D8896631-B747-47a7-84A6-C155337F3BC8}" name="' + $Name + '" image="2" changed="2025-01-01 00:00:00" uid="' + $Uid + '">' +
        '<Properties action="U" name="' + $Name + '" runAs="NT AUTHORITY\System" logonType="S4U"><Task version="1.3">' +
        '<Principals><Principal id="Author"><UserId>NT AUTHORITY\System</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>' +
        '<Actions Context="Author"><Exec><Command>' + $Command + '</Command>' + $argumentsXml + '</Exec></Actions></Task></Properties></TaskV2>'
    }

    function New-TasksFile {
        # Out: a ScheduledTasks.xml that holds those items, in that order
        param([string[]]$Items, [switch]$RootDisabled)
        $disabled = if ($RootDisabled) { ' disabled="1"' } else { '' }
        '<?xml version="1.0" encoding="utf-8"?><ScheduledTasks clsid="{CC63F200-7309-4ba0-B154-A71CD118DBCC}"' + $disabled + '>' + ($Items -join '') + '</ScheduledTasks>'
    }

    function New-OtherFile {
        # Out: a ScheduledTasks.xml that GPMC could have written, with one task of someone
        #      else's and, optionally, an older item for ours, of another kind
        param([switch]$WithOldOurs, [switch]$RootDisabled)
        $items = @(New-TaskV2 -Name 'Someone else' -Uid '{22222222-2222-2222-2222-222222222222}')
        if ($WithOldOurs) { $items += New-TaskV2 -Name 'UsaBanner sync' -Uid '{11111111-1111-1111-1111-111111111111}' -Command 'powershell.exe' -Arguments '-File old.ps1' }
        New-TasksFile -Items $items -RootDisabled:$RootDisabled
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'ConvertTo-UsaBannerGpoLfByte' {
    It 'turns each CR LF into LF, and leaves a lone CR and every other byte as it was' {
        $in = [byte[]](0x23, 0x0D, 0x0A, 0xC3, 0xA9, 0x0D, 0x0D, 0x0A, 0x0A, 0x41, 0x0D, 0x42, 0x0D, 0x0A)
        $out = InModuleScope UsaBanner -Parameters @{ In = $in } { param($In) ConvertTo-UsaBannerGpoLfByte -Bytes $In }
        , $out | Should -BeOfType [byte[]]
        $out | Should -Be ([byte[]](0x23, 0x0A, 0xC3, 0xA9, 0x0D, 0x0A, 0x0A, 0x41, 0x0D, 0x42, 0x0A))
    }
    It 'returns a file with a NUL byte as it was, CRLF and all: it is binary' {
        $in = [byte[]](0x00, 0x0D, 0x0A, 0xFF, 0x0D, 0x0A)
        $out = InModuleScope UsaBanner -Parameters @{ In = $in } { param($In) ConvertTo-UsaBannerGpoLfByte -Bytes $In }
        $out | Should -Be $in
    }
    It 'returns a file with no CR, and an empty one, as it was' {
        $text = [byte[]](0x61, 0x0A, 0x62, 0x0A)
        $out = InModuleScope UsaBanner -Parameters @{ In = $text } { param($In) ConvertTo-UsaBannerGpoLfByte -Bytes $In }
        $out | Should -Be $text
        $empty = InModuleScope UsaBanner { ConvertTo-UsaBannerGpoLfByte -Bytes ([byte[]]@()) }
        , $empty | Should -BeOfType [byte[]]
        $empty.Length | Should -Be 0
    }
}

Describe 'Test-UsaBannerGpoPathInside' {
    It 'says <Path> in <Folder> is <Expected>' -ForEach @(
        @{ Path = '/srv/netlogon/UsaBanner'; Folder = '/srv/netlogon/UsaBanner'; Expected = $true }
        @{ Path = '/srv/netlogon/UsaBanner/'; Folder = '/srv/netlogon/UsaBanner'; Expected = $true }
        @{ Path = '/srv/netlogon/UsaBanner/UsaBanner/Private'; Folder = '/srv/netlogon/UsaBanner'; Expected = $true }
        @{ Path = '/srv/NETLOGON/usabanner/x'; Folder = '/srv/netlogon/UsaBanner'; Expected = $true }
        @{ Path = '/srv/netlogon/UsaBanner2'; Folder = '/srv/netlogon/UsaBanner'; Expected = $false }
        @{ Path = '/srv/netlogon'; Folder = '/srv/netlogon/UsaBanner'; Expected = $false }
        @{ Path = '/srv/other/UsaBanner'; Folder = '/srv/netlogon/UsaBanner'; Expected = $false }
        @{ Path = '/srv/netlogon/UsaBanner/../Other'; Folder = '/srv/netlogon/UsaBanner'; Expected = $false }
    ) {
        InModuleScope UsaBanner -Parameters @{ Path = $Path; Folder = $Folder } { param($Path, $Folder) Test-UsaBannerGpoPathInside -Path $Path -Folder $Folder } | Should -Be $Expected
    }
}

Describe 'Get-UsaBannerGpoTaskArgument' {
    It 'runs the runner by its path, with the execution policy bypassed for a script on a share' {
        $script:Arguments | Should -BeExactly '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "\\ad.example\NETLOGON\UsaBanner\UsaBanner\windows\Sync-UsaBanner.ps1"'
    }
    It 'refuses a path with a quote, which would end the argument' {
        { InModuleScope UsaBanner { Get-UsaBannerGpoTaskArgument -ScriptPath 'x" -File y.ps1' } } | Should -Throw '*holds a quote*'
    }
}

Describe 'New-UsaBannerGpoTasksXml' {
    Context 'a GPO with no ScheduledTasks.xml yet' {
        BeforeAll {
            $script:R = Get-TasksXml
            $script:Item = Get-Item1 -Text $script:R.Xml
        }
        It 'writes one ImmediateTaskV2 item under the ScheduledTasks container' {
            $doc = [xml]$script:R.Xml
            $doc.DocumentElement.LocalName | Should -Be 'ScheduledTasks'
            $doc.DocumentElement.GetAttribute('clsid') | Should -BeExactly '{CC63F200-7309-4ba0-B154-A71CD118DBCC}'
            @($doc.DocumentElement.ChildNodes | Where-Object NodeType -eq 'Element') | Should -HaveCount 1
            $script:Item.LocalName | Should -Be 'ImmediateTaskV2'
            $script:Item.GetAttribute('clsid') | Should -BeExactly '{9756B581-76EC-4169-9AFC-0CA8D43ADB5F}'
        }
        It 'runs powershell.exe with the arguments, as SYSTEM with highest privileges' {
            $f = $script:R.Fields
            $f.Command | Should -BeExactly 'powershell.exe'
            $f.Arguments | Should -BeExactly $script:Arguments
            $f.RunAs | Should -BeExactly 'NT AUTHORITY\System'
            $f.RunLevel | Should -BeExactly 'HighestAvailable'
            $script:Item.SelectSingleNode('Properties').GetAttribute('logonType') | Should -BeExactly 'S4U'
        }
        It 'runs now and deletes itself, within half an hour, one at a time' {
            $s = $script:Item.SelectSingleNode('Properties/Task/Settings')
            $s.SelectSingleNode('DeleteExpiredTaskAfter').InnerText | Should -BeExactly 'PT0M'
            $s.SelectSingleNode('ExecutionTimeLimit').InnerText | Should -BeExactly 'PT30M'
            $s.SelectSingleNode('MultipleInstancesPolicy').InnerText | Should -BeExactly 'IgnoreNew'
            $t = $script:Item.SelectSingleNode('Properties/Task/Triggers/TimeTrigger')
            $t.SelectSingleNode('StartBoundary').InnerText | Should -BeExactly '%LocalTimeXmlEx%'
            $t.SelectSingleNode('EndBoundary').InnerText | Should -BeExactly '%LocalTimeXmlEx%'
            $script:R.Fields.TimeLimit | Should -BeExactly 'PT30M'
        }
        It 'reaches servers and domain controllers only, through a WMI target on the item' {
            $w = @($script:Item.SelectNodes('Filters/FilterWmi'))
            $w | Should -HaveCount 1
            $w[0].GetAttribute('bool') | Should -BeExactly 'AND'
            $w[0].GetAttribute('not') | Should -BeExactly '0'
            $w[0].GetAttribute('nameSpace') | Should -BeExactly 'Root\cimv2'
            $w[0].GetAttribute('query') | Should -BeExactly 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 2 OR ProductType = 3'
            $script:R.Fields.Filters | Should -BeExactly 'WMI: SELECT * FROM Win32_OperatingSystem WHERE ProductType = 2 OR ProductType = 3'
        }
        It 'keeps the same uid at every run, derived from the task name' {
            $again = Get-Item1 -Text (Get-TasksXml -Arguments 'other').Xml
            $again.GetAttribute('uid') | Should -BeExactly $script:Item.GetAttribute('uid')
            $script:Item.GetAttribute('uid') | Should -BeExactly (InModuleScope UsaBanner { ConvertTo-UsaBannerGpoStableGuid -Name 'UsaBanner|ImmediateTaskV2|UsaBanner sync' })
        }
        It 'writes a declaration that says UTF-8, LF line ends, and no byte-order mark' {
            $script:R.Xml | Should -Match '^<\?xml version="1\.0" encoding="utf-8"\?>'
            $script:R.Xml | Should -Not -Match "`r"
            [int][char]$script:R.Xml[0] | Should -Be 60
        }
    }

    Context 'a file that holds other items' {
        It 'adds the task at the end and keeps the other item exactly' {
            $r = Get-TasksXml -Existing (New-OtherFile)
            $names = @(([xml]$r.Xml).DocumentElement.ChildNodes | Where-Object NodeType -eq 'Element' | ForEach-Object { $_.GetAttribute('name') })
            $names | Should -Be @('Someone else', 'UsaBanner sync')
            $r.Kept | Should -Be @("TaskV2 'Someone else'")
            $r.Replaced | Should -BeNullOrEmpty
            (Get-Item1 -Text $r.Xml -Name 'Someone else').GetAttribute('uid') | Should -BeExactly '{22222222-2222-2222-2222-222222222222}'
        }
        It 'replaces an older item for the task, of any kind, and reports what it held' {
            $r = Get-TasksXml -Existing (New-OtherFile -WithOldOurs)
            $r.Replaced | Should -HaveCount 1
            $r.Replaced[0].Item | Should -Be 'TaskV2'
            $r.Replaced[0].Fields.Arguments | Should -BeExactly '-File old.ps1'
            @(([xml]$r.Xml).DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.GetAttribute('name') -eq 'UsaBanner sync' }) | Should -HaveCount 1
        }
        It 'puts the task in the place of the first older item, and takes a further one away' {
            $text = New-TasksFile -Items @(
                (New-TaskV2 -Name 'UsaBanner sync' -Uid '{11111111-1111-1111-1111-111111111111}' -Command 'powershell.exe' -Arguments '-File first.ps1')
                (New-TaskV2 -Name 'Someone else' -Uid '{22222222-2222-2222-2222-222222222222}')
                (New-TaskV2 -Name 'UsaBanner sync' -Uid '{33333333-3333-3333-3333-333333333333}' -Command 'powershell.exe' -Arguments '-File second.ps1')
            )
            $r = Get-TasksXml -Existing $text
            $r.Replaced | Should -HaveCount 2
            $r.Replaced[0].Fields.Arguments | Should -BeExactly '-File first.ps1'
            $r.Replaced[1].Uid | Should -BeExactly '{33333333-3333-3333-3333-333333333333}'
            $names = @(([xml]$r.Xml).DocumentElement.ChildNodes | Where-Object NodeType -eq 'Element' | ForEach-Object { $_.GetAttribute('name') })
            $names | Should -Be @('UsaBanner sync', 'Someone else')
        }
        It 'switches the file back on when every item was switched off' {
            $r = Get-TasksXml -Existing (New-OtherFile -RootDisabled)
            $r.RootWasDisabled | Should -BeTrue
            ([xml]$r.Xml).DocumentElement.HasAttribute('disabled') | Should -BeFalse
        }
        It 'refuses a file it cannot read rather than overwrite it' {
            { Get-TasksXml -Existing '<ScheduledTasks><broken' -Arguments 'x' } | Should -Throw '*not XML*'
            { Get-TasksXml -Existing '<Files clsid="x"/>' -Arguments 'x' } | Should -Throw '*<Files> root*'
        }
    }
}

Describe 'Compare-UsaBannerGpoTaskField' {
    It 'names each field of an older item that the run changes, old and new' {
        $r = Get-TasksXml -Existing (New-OtherFile -WithOldOurs)
        $diff = @(InModuleScope UsaBanner -Parameters @{ R = $r } { param($R) Compare-UsaBannerGpoTaskField -Old $R.Replaced[0].Fields -New $R.Fields })
        $diff | Should -Contain "Kind: 'TaskV2' -> 'ImmediateTaskV2'"
        $diff | Should -Contain "Arguments: '-File old.ps1' -> '$($script:Arguments)'"
        ($diff -join "`n") | Should -Match "Filters: 'none' -> 'WMI"
        ($diff -join "`n") | Should -Not -Match '^Command:'
    }
}

Describe 'Test-UsaBannerGppXmlSame' {
    BeforeAll {
        function Test-Same {
            param([string]$Existing, [string]$Desired)
            InModuleScope UsaBanner -Parameters @{ Existing = $Existing; Desired = $Desired } { param($Existing, $Desired) Test-UsaBannerGppXmlSame -Existing $Existing -Desired $Desired }
        }
    }
    It 'calls a rerun of the same settings the same, whatever its time stamp and layout' {
        $a = (Get-TasksXml).Xml
        $b = ($a -replace 'changed="[^"]*"', 'changed="1999-01-01 00:00:00"') -replace "`n\s*", ''
        Test-Same -Existing $b -Desired $a | Should -BeTrue
        Test-Same -Existing ([char]0xFEFF + $a) -Desired $a | Should -BeTrue
    }
    It 'sees a changed argument' {
        $a = (Get-TasksXml).Xml
        $b = (Get-TasksXml -Arguments 'other').Xml
        Test-Same -Existing $b -Desired $a | Should -BeFalse
    }
    It 'never calls a missing or unreadable file the same' {
        Test-Same -Existing '' -Desired '<a/>' | Should -BeFalse
        Test-Same -Existing '<a' -Desired '<a/>' | Should -BeFalse
    }
}

Describe 'Get-UsaBannerGpoTaskItemName' {
    It 'lists the name of each item, and of the task it holds where that is another name' {
        $text = (New-OtherFile -WithOldOurs) -replace '(<TaskV2[^>]*name=")Someone else(")', '$1Item name$2'
        $names = @(InModuleScope UsaBanner -Parameters @{ Text = $text } { param($Text) Get-UsaBannerGpoTaskItemName -Xml $Text })
        $names | Should -Contain 'Item name'
        $names | Should -Contain 'Someone else'
        $names | Should -Contain 'UsaBanner sync'
    }
    It 'throws on text that is not XML' {
        { InModuleScope UsaBanner { Get-UsaBannerGpoTaskItemName -Xml '<ScheduledTasks><broken' } } | Should -Throw
    }
}

Describe 'Merge-UsaBannerGpoTaskExtension' {
    BeforeAll {
        function Merge-Ext {
            param([string]$Existing)
            InModuleScope UsaBanner -Parameters @{ Existing = $Existing } { param($Existing) Merge-UsaBannerGpoTaskExtension -Existing $Existing }
        }
    }
    It 'registers Scheduled Tasks, and its tool under the all-zero group, on an empty GPO' {
        Merge-Ext '' | Should -BeExactly ($script:Zero + $script:Tasks)
    }
    It 'keeps what other settings registered, in CSE order' {
        $registry = '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
        Merge-Ext $registry | Should -BeExactly ($script:Zero + $registry + $script:Tasks)
    }
    It 'adds the tool to an all-zero group that lists others, sorted' {
        $zeroWithOther = '[{00000000-0000-0000-0000-000000000000}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
        Merge-Ext $zeroWithOther | Should -BeExactly ('[{00000000-0000-0000-0000-000000000000}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]' + $script:Tasks)
    }
    It 'returns a registered list unchanged, so a rerun writes nothing' {
        $once = Merge-Ext ''
        Merge-Ext $once | Should -BeExactly $once
    }
    It 'reads lowercase GUIDs as the same extension' {
        Merge-Ext $script:Tasks.ToLowerInvariant() | Should -BeExactly ($script:Zero + $script:Tasks)
    }
}

Describe 'Step-UsaBannerGpoVersion' {
    It 'adds one to the computer half: <In> -> <Out>' -ForEach @(
        @{ In = 0; Out = 1 }
        @{ In = 5; Out = 6 }
        @{ In = 0x00030007; Out = 0x00030008 }
        @{ In = 0x0002FFFF; Out = 0x00020000 }
        @{ In = 4294967295; Out = 4294901760 }
    ) {
        InModuleScope UsaBanner -Parameters @{ In = $In } { param($In) Step-UsaBannerGpoVersion -Version $In } | Should -Be $Out
    }
}

Describe 'Get-UsaBannerGpoGptIniText' {
    It 'replaces Version= where it is, keeping the other lines' {
        InModuleScope UsaBanner { Get-UsaBannerGpoGptIniText -Content "[General]`r`nVersion=4`r`ndisplayName=New Group Policy Object`r`n" -Version 5 } |
            Should -BeExactly "[General]`r`nVersion=5`r`ndisplayName=New Group Policy Object`r`n"
    }
    It 'adds Version= under [General], and the section when there is none' {
        InModuleScope UsaBanner { Get-UsaBannerGpoGptIniText -Content "[General]`ndisplayName=x`n" -Version 7 } | Should -BeExactly "[General]`r`nVersion=7`r`ndisplayName=x`r`n"
        InModuleScope UsaBanner { Get-UsaBannerGpoGptIniText -Content '' -Version 1 } | Should -BeExactly "[General]`r`nVersion=1`r`n"
    }
}

Describe 'Get-UsaBannerGpoGptIniVersion' {
    It 'reads the Version= line, whatever the case and the blanks around it' {
        InModuleScope UsaBanner { Get-UsaBannerGpoGptIniVersion -Content "[General]`r`nVersion=12`r`n" } | Should -Be 12
        InModuleScope UsaBanner { Get-UsaBannerGpoGptIniVersion -Content "[General]`r`n  version = 4294901760`r`n" } | Should -Be 4294901760
    }
    It 'says -1 for a text with no Version=' {
        InModuleScope UsaBanner { Get-UsaBannerGpoGptIniVersion -Content "[General]`r`ndisplayName=x`r`n" } | Should -Be -1
        InModuleScope UsaBanner { Get-UsaBannerGpoGptIniVersion -Content '' } | Should -Be -1
    }
}

Describe 'Test-UsaBannerGpoLinkValue' {
    BeforeAll {
        $script:Guid = '{31B2F340-016D-11D2-945F-00C04FB984F9}'
        $script:Other = '[LDAP://cn={6AC1786C-016F-11D2-945F-00C04FB984F9},cn=policies,cn=system,DC=ad,DC=example;0]'
        function Test-Link {
            param([string]$GpLink)
            InModuleScope UsaBanner -Parameters @{ GpLink = $GpLink; Guid = $script:Guid } { param($GpLink, $Guid) Test-UsaBannerGpoLinkValue -GpLink $GpLink -GpoGuid $Guid }
        }
    }
    It 'finds an enabled link among others' {
        $r = Test-Link ($script:Other + '[LDAP://cn={31b2f340-016d-11d2-945f-00c04fb984f9},cn=policies,cn=system,DC=ad,DC=example;0]')
        $r.Linked | Should -BeTrue
        $r.Enabled | Should -BeTrue
    }
    It 'reads flag bit 0 as a disabled link, and bit 1 (enforced) as still enabled' {
        (Test-Link "[LDAP://cn=$($script:Guid),cn=policies,cn=system,DC=ad,DC=example;1]").Enabled | Should -BeFalse
        (Test-Link "[LDAP://cn=$($script:Guid),cn=policies,cn=system,DC=ad,DC=example;2]").Enabled | Should -BeTrue
    }
    It 'says not linked when the GPO is not in the value, or there is no value' {
        (Test-Link $script:Other).Linked | Should -BeFalse
        (Test-Link '').Flags | Should -Be -1
    }
}

Describe 'ConvertTo-UsaBannerLdapFilterValue' {
    It 'escapes the characters that would change the search' {
        InModuleScope UsaBanner { ConvertTo-UsaBannerLdapFilterValue -Value 'a*b(c)d\e' } | Should -BeExactly 'a\2ab\28c\29d\5ce'
    }
    It 'leaves a plain GPO name as it is, and escapes the parentheses in another' {
        InModuleScope UsaBanner { ConvertTo-UsaBannerLdapFilterValue -Value 'UsaBanner (lab)' } | Should -BeExactly 'UsaBanner \28lab\29'
        InModuleScope UsaBanner { ConvertTo-UsaBannerLdapFilterValue -Value 'UsaBanner' } | Should -BeExactly 'UsaBanner'
    }
}

Describe 'ConvertFrom-UsaBannerGpoReport' {
    It 'lists the settings areas on both sides' {
        $xml = '<?xml version="1.0" encoding="utf-16"?><GPO xmlns="http://www.microsoft.com/GroupPolicy/Settings"><Name>x</Name>' +
        '<Computer><ExtensionData><Name>Scheduled Tasks</Name></ExtensionData><ExtensionData><Name>Registry</Name></ExtensionData></Computer>' +
        '<User><ExtensionData><Name>Folder Redirection</Name></ExtensionData></User></GPO>'
        @(InModuleScope UsaBanner -Parameters @{ Xml = $xml } { param($Xml) ConvertFrom-UsaBannerGpoReport -Xml $Xml }) |
            Should -Be @('Computer: Scheduled Tasks', 'Computer: Registry', 'User: Folder Redirection')
    }
}

Describe 'the ADSys startup values' {
    BeforeAll {
        $script:Wanted = InModuleScope UsaBanner {
            [ordered]@{
                metaValues = @{ Type = 'String'; Value = (Get-UsaBannerGpoStartupMeta) }
                all        = @{ Type = 'MultiString'; Value = @($script:UsaGpoStartupScript) }
            }
        }
        $script:Meta = InModuleScope UsaBanner { Get-UsaBannerGpoStartupMeta }
        function Get-Change {
            param([hashtable]$Current)
            @(InModuleScope UsaBanner -Parameters @{ Current = $Current; Wanted = $script:Wanted } { param($Current, $Wanted) Get-UsaBannerGpoStartupChange -Current $Current -Wanted $Wanted })
        }
    }
    It 'is the append strategy for every release the ADSys template names and for all (the text today''s banner and the ADSys fix GPO carry)' {
        $script:Meta | Should -BeExactly '{"22.04":{"strategy":"append"},"24.04":{"strategy":"append"},"25.04":{"strategy":"append"},"25.10":{"strategy":"append"},"all":{"strategy":"append"}}'
    }
    It 'runs the runner the Ubuntu copy holds, by its path under Ubuntu\scripts' {
        $script:Wanted['all'].Value | Should -Be @('UsaBanner/adsys-startup.sh')
        $script:Wanted['all'].Type | Should -Be 'MultiString'
    }
    It 'sets both values on a GPO that has none' {
        $rows = Get-Change @{}
        $rows.Name | Should -Be @('metaValues', 'all')
        $rows.Action | Should -Be @('set', 'set')
        $rows[1].Old | Should -BeExactly ''
        $rows[1].New | Should -BeExactly 'UsaBanner/adsys-startup.sh'
    }
    It 'changes nothing when the GPO holds exactly those values, whatever the case of their names' {
        $current = @{ METAVALUES = @{ Type = 'String'; Value = $script:Meta }; All = @{ Type = 'MultiString'; Value = @('UsaBanner/adsys-startup.sh', '') } }
        (Get-Change $current).Count | Should -Be 0
    }
    It 'overwrites a different script list and shows the old one' {
        $current = @{ metaValues = @{ Type = 'String'; Value = $script:Meta }; all = @{ Type = 'MultiString'; Value = @('UsaBanner/adsys-startup.sh', 'other/x.sh') } }
        $rows = Get-Change $current
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'all'
        $rows[0].Old | Should -BeExactly 'UsaBanner/adsys-startup.sh, other/x.sh'
        $rows[0].Value | Should -Be @('UsaBanner/adsys-startup.sh')
    }
    It 'overwrites a value of the wrong type even when its text matches, and says which type it was' {
        $current = @{ metaValues = @{ Type = 'String'; Value = $script:Meta }; all = @{ Type = 'String'; Value = 'UsaBanner/adsys-startup.sh' } }
        $rows = Get-Change $current
        $rows.Count | Should -Be 1
        $rows[0].Old | Should -BeExactly 'UsaBanner/adsys-startup.sh (String)'
        $rows[0].Type | Should -Be 'MultiString'
    }
    It 'removes any other value under the key (a release-specific list would replace "all" on that release)' {
        $current = @{ metaValues = @{ Type = 'String'; Value = $script:Meta }; all = @{ Type = 'MultiString'; Value = @('UsaBanner/adsys-startup.sh') }; '24.04' = @{ Type = 'MultiString'; Value = @('other/old.sh') } }
        $rows = Get-Change $current
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be '24.04'
        $rows[0].Action | Should -Be 'remove'
        $rows[0].Old | Should -BeExactly 'other/old.sh'
    }
}
