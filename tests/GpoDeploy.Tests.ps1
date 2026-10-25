# Deploy-UsaBannerGPO (UsaBanner/Public/Deploy-UsaBannerGPO.ps1 and Private/GpoDeploy.ps1, docs/DECISIONS.md,
# D29) against a fake domain. Folders stand in for NETLOGON, the ADSys assets folder (SYSVOL\<domain>\Ubuntu)
# and SYSVOL's Policies; a hashtable stands in for each GPO's attributes, its ADSys values and the links; and
# every touch of the domain, which is a function of its own in GpoDeploy.ps1, answers from them and writes
# down what it was asked to change. The GroupPolicy cmdlets and System.DirectoryServices are inside those
# functions and nowhere else (the last Describe holds the code to that), so what runs here is the command
# itself: the plan, the staging, the task file, the extension, the version, the links, the neighbours and the
# read-back. What only a domain shows is for a lab (the report of this MR says which).
#
# Each case asserts what was written and what was not: a snapshot of every file in the fake domain (path,
# SHA-256, time stamp), of every GPO and of every link, taken before and after.

BeforeDiscovery {
    # The flags Deploy-UsaBanner takes, one test case each below: every parameter of it but -Path and the
    # switch the runners pass.
    $moduleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'UsaBanner'
    Import-Module (Join-Path $moduleRoot 'UsaBanner.psd1') -Force
    $common = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
    $flagCases = @((Get-Command Deploy-UsaBanner).Parameters.Keys | Where-Object { $_ -notin $common -and $_ -notin 'Path', 'ReplaceOldBanner' } | ForEach-Object { @{ Flag = $_ } })
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:ModuleRoot = Join-Path $repoRoot 'UsaBanner'
    Import-Module (Join-Path $script:ModuleRoot 'UsaBanner.psd1') -Force

    $script:TaskScript = '\\ad.example\NETLOGON\UsaBanner\UsaBanner\windows\Sync-UsaBanner.ps1'
    $script:ServersOu = 'OU=Servers,DC=ad,DC=example'
    $script:LinuxOu = 'OU=Linux,DC=ad,DC=example'
    $script:RootDn = 'DC=ad,DC=example'
    $script:Cse = '{AADCED64-746C-4633-A97C-D61349046527}'

    function Write-TestFile {
        # In:  a path, and the text or the bytes to put in it
        # Out: nothing; the file is there, with its folders
        param([string]$Path, $Content)
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
        if ($Content -is [byte[]]) { [System.IO.File]::WriteAllBytes($Path, $Content) } else { [System.IO.File]::WriteAllText($Path, [string]$Content) }
    }

    function New-FakeDomain {
        # In:  -NoAdsys for a domain whose ADSys assets folder (Ubuntu\GPT.INI) is not made
        # Out: the fake domain: the folders for NETLOGON, Ubuntu and Policies; the GPOs; the links, where
        #      the domain and two OUs exist; the list of what was asked to change (Writes); and the
        #      attributes whose writes it ignores, as a DC that lost one would
        param([switch]$NoAdsys)
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $domain = @{
            Root         = $root
            Netlogon     = Join-Path $root 'NETLOGON' 'UsaBanner'
            Ubuntu       = Join-Path $root 'SYSVOL' 'ad.example' 'Ubuntu'
            Policies     = Join-Path $root 'SYSVOL' 'ad.example' 'Policies'
            Gpos         = [ordered]@{}
            Links        = [ordered]@{}
            Writes       = [System.Collections.Generic.List[string]]::new()
            IgnoreWrites = @()
            NextId       = 1
        }
        foreach ($dn in $script:RootDn, $script:ServersOu, $script:LinuxOu) { $domain.Links[$dn] = [System.Collections.Generic.List[object]]::new() }
        $null = New-Item -ItemType Directory -Path $domain.Policies -Force
        if (-not $NoAdsys) { Write-TestFile (Join-Path $domain.Ubuntu 'GPT.INI') "[General]`r`nVersion=7`r`n" }
        $domain
    }

    function Add-FakeGpo {
        # In:  the fake domain, a GPO's name and what it holds: the text of its ScheduledTasks.xml, its flags
        #      and version, its ADSys values (name -> @{ Type; Value }), the settings areas the report lists
        #      besides those two, and its extension list
        # Out: its guid
        param(
            [hashtable]$Domain,
            [string]$Name = 'UsaBanner',
            [string]$TasksXml = '',
            [int]$Flags = 0,
            [int]$Version = 0,
            [hashtable]$Values = @{},
            [string[]]$Areas = @(),
            [string]$Ext = ''
        )
        $guid = '{{B0000000-0000-0000-0000-{0:D12}}}' -f $Domain.NextId
        $Domain.NextId++
        $gpo = @{ Name = $Name; Comment = ''; Attr = @{ gPCMachineExtensionNames = $Ext; flags = $Flags; versionNumber = $Version }; Values = [ordered]@{}; Areas = $Areas }
        foreach ($valueName in $Values.Keys) { $gpo.Values[$valueName] = $Values[$valueName] }
        $Domain.Gpos[$guid] = $gpo
        $folder = Join-Path $Domain.Policies $guid
        Write-TestFile (Join-Path $folder 'GPT.INI') "[General]`r`nVersion=$Version`r`ndisplayName=$Name`r`n"
        if ($TasksXml) { Write-TestFile (Join-Path $folder 'Machine' 'Preferences' 'ScheduledTasks' 'ScheduledTasks.xml') $TasksXml }
        $guid
    }

    function Use-FakeDomain {
        # In:  the fake domain
        # Out: nothing; every function of GpoDeploy.ps1 that touches the domain answers from it
        param([hashtable]$Domain)
        $global:UsaGpoFake = $Domain
        $global:UsaGpoTaskScript = $script:TaskScript
        # What Set-GPRegistryValue and Remove-GPRegistryValue do to a GPO besides the value: they
        # raise its version in AD and in GPT.INI themselves, and Set- registers the Registry extension.
        $global:UsaGpoCmdlet = {
            param($Guid, [switch]$RegisterRegistry)
            $fake = $global:UsaGpoFake
            $attr = $fake.Gpos[$Guid].Attr
            if ($RegisterRegistry -and ([string]$attr['gPCMachineExtensionNames']) -notmatch '35378EAC') {
                $attr['gPCMachineExtensionNames'] = [string]$attr['gPCMachineExtensionNames'] + '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
            }
            $was = [long]$attr['versionNumber']
            $next = (($was -shr 16) -shl 16) -bor (($was -band 0xFFFF) + 1)
            $attr['versionNumber'] = [int]$next
            [System.IO.File]::WriteAllText((Join-Path $fake.Policies $Guid 'GPT.INI'), "[General]`r`nVersion=$next`r`ndisplayName=$($fake.Gpos[$Guid].Name)`r`n")
        }
        Mock -ModuleName UsaBanner Import-UsaBannerGroupPolicy { }
        Mock -ModuleName UsaBanner Get-UsaBannerGpoDomain { [pscustomobject]@{ Name = 'ad.example'; Dn = 'DC=ad,DC=example'; Pdc = 'dc01.ad.example' } }
        Mock -ModuleName UsaBanner Get-UsaBannerGpoPlace {
            $fake = $global:UsaGpoFake
            [pscustomobject]@{ Netlogon = $fake.Netlogon; Ubuntu = $fake.Ubuntu; Policies = $fake.Policies; TaskScript = $global:UsaGpoTaskScript }
        }
        Mock -ModuleName UsaBanner Find-UsaBannerGpo {
            $fake = $global:UsaGpoFake
            foreach ($guid in @($fake.Gpos.Keys)) {
                if ($fake.Gpos[$guid].Name -eq $Name) { [pscustomobject]@{ Guid = $guid; Name = $fake.Gpos[$guid].Name } }
            }
        }
        Mock -ModuleName UsaBanner Find-UsaBannerGpoWithTasks {
            $fake = $global:UsaGpoFake
            foreach ($guid in @($fake.Gpos.Keys)) {
                if (([string]$fake.Gpos[$guid].Attr['gPCMachineExtensionNames']) -match '(?i)\{AADCED64-746C-4633-A97C-D61349046527\}') { [pscustomobject]@{ Guid = $guid; Name = $fake.Gpos[$guid].Name } }
            }
        }
        Mock -ModuleName UsaBanner New-UsaBannerGpoObject {
            $fake = $global:UsaGpoFake
            $guid = '{{A0000000-0000-0000-0000-{0:D12}}}' -f $fake.NextId
            $fake.NextId++
            $fake.Writes.Add("New-GPO $Name")
            if (-not $fake.ContainsKey('AtFirstPolicyWrite')) {
                $fake.AtFirstPolicyWrite = @{
                    Windows = Test-Path -LiteralPath (Join-Path $fake.Netlogon 'usabanner.json')
                    Ubuntu  = Test-Path -LiteralPath (Join-Path $fake.Ubuntu 'scripts' 'UsaBanner' 'adsys-startup.sh')
                    Version = $(if (Test-Path -LiteralPath (Join-Path $fake.Ubuntu 'GPT.INI')) { [long][regex]::Match([System.IO.File]::ReadAllText((Join-Path $fake.Ubuntu 'GPT.INI')), '(?m)^Version=(\d+)').Groups[1].Value } else { 0 })
                }
            }
            $fake.Gpos[$guid] = @{ Name = $Name; Comment = $Comment; Attr = @{ gPCMachineExtensionNames = ''; flags = 0; versionNumber = 0 }; Values = [ordered]@{}; Areas = @() }
            $folder = Join-Path $fake.Policies $guid
            $null = New-Item -ItemType Directory -Path (Join-Path $folder 'Machine') -Force
            [System.IO.File]::WriteAllText((Join-Path $folder 'GPT.INI'), "[General]`r`nVersion=0`r`ndisplayName=$Name`r`n")
        }
        Mock -ModuleName UsaBanner Get-UsaBannerGpoAttribute { $global:UsaGpoFake.Gpos[$Guid].Attr[$Name] }
        Mock -ModuleName UsaBanner Set-UsaBannerGpoAttribute {
            $fake = $global:UsaGpoFake
            $fake.Writes.Add("set attribute $Name")
            if ($fake.IgnoreWrites -notcontains $Name) { $fake.Gpos[$Guid].Attr[$Name] = $Value }
        }
        Mock -ModuleName UsaBanner Get-UsaBannerGpoRegistryValue {
            $values = $global:UsaGpoFake.Gpos[$Guid].Values
            foreach ($valueName in @($values.Keys)) { [pscustomobject]@{ Name = $valueName; Type = $values[$valueName].Type; Value = $values[$valueName].Value } }
        }
        Mock -ModuleName UsaBanner Set-UsaBannerGpoRegistryValue {
            $fake = $global:UsaGpoFake
            if (-not $fake.ContainsKey('AtFirstPolicyWrite')) {
                $fake.AtFirstPolicyWrite = @{
                    Windows = Test-Path -LiteralPath (Join-Path $fake.Netlogon 'usabanner.json')
                    Ubuntu  = Test-Path -LiteralPath (Join-Path $fake.Ubuntu 'scripts' 'UsaBanner' 'adsys-startup.sh')
                    Version = $(if (Test-Path -LiteralPath (Join-Path $fake.Ubuntu 'GPT.INI')) { [long][regex]::Match([System.IO.File]::ReadAllText((Join-Path $fake.Ubuntu 'GPT.INI')), '(?m)^Version=(\d+)').Groups[1].Value } else { 0 })
                }
            }
            $fake.Writes.Add("set value $Name")
            $fake.Gpos[$Guid].Values[$Name] = @{ Type = $Type; Value = $Value }
            & $global:UsaGpoCmdlet $Guid -RegisterRegistry
        }
        Mock -ModuleName UsaBanner Remove-UsaBannerGpoRegistryValue {
            $fake = $global:UsaGpoFake
            $fake.Writes.Add("remove value $Name")
            $fake.Gpos[$Guid].Values.Remove($Name)
            & $global:UsaGpoCmdlet $Guid
        }
        Mock -ModuleName UsaBanner Get-UsaBannerGpoLinkAt {
            $fake = $global:UsaGpoFake
            if (-not $fake.Links.Contains($TargetDn)) { throw "UsaBanner: -LinkTarget '$TargetDn' is not an object that dc01.ad.example has (there is no such object)." }
            # What Test-UsaBannerGpoLinkValue makes of the gPLink value, which GpoPolicy.Tests.ps1 tests.
            $link = @($fake.Links[$TargetDn] | Where-Object { $_.Guid -eq $Guid })
            if ($Guid -and $link.Count) { [pscustomobject]@{ Linked = $true; Enabled = (($link[0].Flags -band 1) -eq 0); Flags = $link[0].Flags } }
            else { [pscustomobject]@{ Linked = $false; Enabled = $false; Flags = -1 } }
        }
        Mock -ModuleName UsaBanner Get-UsaBannerGpoLinkPlace {
            $fake = $global:UsaGpoFake
            foreach ($dn in @($fake.Links.Keys)) {
                foreach ($link in $fake.Links[$dn]) {
                    if ($link.Guid -eq $Guid) { [pscustomobject]@{ Dn = $dn; Enabled = (($link.Flags -band 1) -eq 0) } }
                }
            }
        }
        Mock -ModuleName UsaBanner New-UsaBannerGpoLink {
            $fake = $global:UsaGpoFake
            $fake.Writes.Add("link $TargetDn")
            $fake.Links[$TargetDn].Add(@{ Guid = $Guid; Flags = 0 })
        }
        Mock -ModuleName UsaBanner Enable-UsaBannerGpoLink {
            $fake = $global:UsaGpoFake
            $fake.Writes.Add("enable link $TargetDn")
            foreach ($link in $fake.Links[$TargetDn]) { if ($link.Guid -eq $Guid) { $link.Flags = $link.Flags -band (-bnot 1) } }
        }
        Mock -ModuleName UsaBanner Get-UsaBannerGpoReportXml {
            $gpo = $global:UsaGpoFake.Gpos[$Guid]
            $areas = @($gpo.Areas)
            if ($gpo.Values.Count) { $areas += 'Computer: Registry' }
            if (([string]$gpo.Attr['gPCMachineExtensionNames']) -match 'AADCED64') { $areas += 'Computer: Scheduled Tasks' }
            $sides = foreach ($side in 'Computer', 'User') {
                "<$side>" + (-join @($areas | Where-Object { $_ -like "${side}: *" } | ForEach-Object { '<ExtensionData><Name>' + $_.Substring($side.Length + 2) + '</Name></ExtensionData>' })) + "</$side>"
            }
            '<?xml version="1.0" encoding="utf-16"?><GPO xmlns="http://www.microsoft.com/GroupPolicy/Settings"><Name>' + $gpo.Name + '</Name>' + (-join $sides) + '</GPO>'
        }
    }

    function New-FakeModule {
        # In:  where to make it
        # Out: the folder, which stands in for the module: a manifest, a script each in Public and Private,
        #      the two runners, a text file with CRLF line ends (and a lone CR), one with LF, and a binary
        #      file with a NUL byte and a CRLF
        param([string]$At = (Join-Path $TestDrive ([guid]::NewGuid().ToString('n')) 'Mod'))
        Write-TestFile (Join-Path $At 'UsaBanner.psd1') "@{ ModuleVersion = '0.0.1' }`n"
        Write-TestFile (Join-Path $At 'Public' 'Hello.ps1') "# hello`n"
        Write-TestFile (Join-Path $At 'Private' 'Old.ps1') "# old`n"
        Write-TestFile (Join-Path $At 'linux' 'adsys-startup.sh') "#!/bin/sh`necho startup`n"
        Write-TestFile (Join-Path $At 'windows' 'Sync-UsaBanner.ps1') "# runner`n"
        Write-TestFile (Join-Path $At 'data' 'crlf.txt') ([System.Text.Encoding]::ASCII.GetBytes("one`r`ntwo`r`nlone`rcr`r`n"))
        Write-TestFile (Join-Path $At 'data' 'lf.txt') "a`nb`n"
        Write-TestFile (Join-Path $At 'data' 'binary.bin') ([byte[]](0x00, 0x0D, 0x0A, 0xFF, 0x0D, 0x0A))
        $At
    }

    function Use-FakeModule {
        # In:  a folder
        # Out: nothing; the command stages that folder as the module
        param([string]$Folder)
        $global:UsaGpoModule = $Folder
        Mock -ModuleName UsaBanner Get-UsaBannerGpoModuleRoot { $global:UsaGpoModule }
    }

    function Get-FileMap {
        # In:  the fake domain
        # Out: a map of each file under it (its path from the root, with /) to its SHA-256 and time stamp
        param([hashtable]$Domain)
        $map = @{}
        foreach ($file in Get-ChildItem -LiteralPath $Domain.Root -Recurse -File -Force) {
            $map[[System.IO.Path]::GetRelativePath($Domain.Root, $file.FullName).Replace('\', '/')] = '{0} {1}' -f (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash, $file.LastWriteTimeUtc.Ticks
        }
        $map
    }

    function Get-DomainState {
        # In:  the fake domain
        # Out: lines that say everything in it: each file, each GPO with its attributes and values, each
        #      link, and what was asked to change
        param([hashtable]$Domain)
        $map = Get-FileMap $Domain
        foreach ($path in @($map.Keys | Sort-Object)) { "file $path $($map[$path])" }
        foreach ($guid in $Domain.Gpos.Keys) {
            $gpo = $Domain.Gpos[$guid]
            "gpo $guid '$($gpo.Name)' ext=$($gpo.Attr['gPCMachineExtensionNames']) flags=$($gpo.Attr['flags']) version=$($gpo.Attr['versionNumber'])"
            foreach ($valueName in $gpo.Values.Keys) { "  value $valueName $($gpo.Values[$valueName].Type) $(@($gpo.Values[$valueName].Value) -join '|')" }
        }
        foreach ($dn in $Domain.Links.Keys) { foreach ($link in $Domain.Links[$dn]) { "link $dn $($link.Guid) $($link.Flags)" } }
        "writes: $($Domain.Writes -join '; ')"
    }

    function Get-Changed {
        # In:  two file maps (Get-FileMap), before and after
        # Out: the paths whose file is new, gone or different, sorted
        param([hashtable]$Before, [hashtable]$After)
        @(@($Before.Keys) + @($After.Keys) | Sort-Object -Unique | Where-Object { $Before[$_] -ne $After[$_] })
    }

    function Set-OldTimes {
        # In:  the fake domain
        # Out: nothing; every file in it was last written in 2020, so a file written again shows
        param([hashtable]$Domain)
        foreach ($file in Get-ChildItem -LiteralPath $Domain.Root -Recurse -File -Force) {
            [System.IO.File]::SetLastWriteTimeUtc($file.FullName, [datetime]::new(2020, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc))
        }
    }

    function Invoke-Gpo {
        # In:  the command's parameters
        # Out: what the command returned (Lines), warned (Warnings) and said (Notes), and the message of
        #      the error it threw (Error); the lines it returned before it threw are kept
        param([hashtable]$Parameters = @{})
        $all = [System.Collections.Generic.List[object]]::new()
        $thrown = ''
        try { Deploy-UsaBannerGPO @Parameters 3>&1 6>&1 | ForEach-Object { $all.Add($_) } }
        catch { $thrown = $_.Exception.Message }
        [pscustomobject]@{
            Lines    = @($all | Where-Object { $_ -is [string] })
            Warnings = @($all | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
            Notes    = @($all | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { [string]$_.MessageData })
            Error    = $thrown
        }
    }

    function Get-CheckLine {
        # Out: the lines of a result that are read-back checks
        param($Result)
        @($Result.Lines | Where-Object { $_ -match '^(ok   |FAIL )' })
    }

    function Get-ChangeLine {
        # Out: the lines of a result that are not read-back checks: the changes made
        param($Result)
        @($Result.Lines | Where-Object { $_ -notmatch '^(ok   |FAIL )' })
    }

    function Get-GpoByName {
        # Out: the fake GPO of that name (the first), with its guid in Guid
        param([hashtable]$Domain, [string]$Name = 'UsaBanner')
        foreach ($guid in $Domain.Gpos.Keys) {
            if ($Domain.Gpos[$guid].Name -eq $Name) { $gpo = $Domain.Gpos[$guid]; $gpo.Guid = $guid; return $gpo }
        }
    }

    function Get-IniVersion {
        # Out: the Version= a GPT.INI holds
        param([string]$Path)
        [long][regex]::Match([System.IO.File]::ReadAllText($Path), '(?m)^Version=(\d+)').Groups[1].Value
    }

    function Get-FileList {
        # In:  a folder
        # Out: the path of each file in it from the folder, with /, sorted by ordinal comparison
        param([string]$Folder)
        $list = @(foreach ($file in [System.IO.Directory]::GetFiles($Folder, '*', [System.IO.SearchOption]::AllDirectories)) { [System.IO.Path]::GetRelativePath($Folder, $file).Replace('\', '/') })
        [array]::Sort($list, [System.StringComparer]::Ordinal)
        $list
    }

    function New-TaskItem {
        # In:  an item's name and uid, and the arguments of its program
        # Out: a TaskV2 item of the kind GPMC writes
        param([string]$Name, [string]$Uid, [string]$Arguments = '')
        $argumentsXml = if ($Arguments) { "<Arguments>$Arguments</Arguments>" } else { '' }
        '<TaskV2 clsid="{D8896631-B747-47a7-84A6-C155337F3BC8}" name="' + $Name + '" image="2" changed="2025-01-01 00:00:00" uid="' + $Uid + '">' +
        '<Properties action="U" name="' + $Name + '" runAs="NT AUTHORITY\System" logonType="S4U"><Task version="1.3">' +
        '<Principals><Principal id="Author"><UserId>NT AUTHORITY\System</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>' +
        '<Actions Context="Author"><Exec><Command>powershell.exe</Command>' + $argumentsXml + '</Exec></Actions></Task></Properties></TaskV2>'
    }

    function New-TasksFile {
        # In:  items
        # Out: a ScheduledTasks.xml that holds them
        param([string[]]$Items)
        '<?xml version="1.0" encoding="utf-8"?><ScheduledTasks clsid="{CC63F200-7309-4ba0-B154-A71CD118DBCC}">' + ($Items -join '') + '</ScheduledTasks>'
    }
}

AfterAll {
    Remove-Variable -Name UsaGpoFake, UsaGpoTaskScript, UsaGpoModule, UsaGpoCmdlet -Scope Global -ErrorAction SilentlyContinue
    Remove-Module UsaBanner -ErrorAction SilentlyContinue
}

Describe 'Deploy-UsaBannerGPO, a first run' {
    BeforeAll {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
        $script:R = Invoke-Gpo @{ Company = 'Contoso'; Environment = 'PROD'; LinkTarget = @($script:ServersOu) }
        $script:Gpo = Get-GpoByName $script:D
        $script:Ubuntu = Join-Path $script:D.Ubuntu 'scripts' 'UsaBanner'
        $script:ModuleFiles = @(Get-FileList $script:ModuleRoot)
        $script:Package = InModuleScope UsaBanner {
            ConvertTo-UsaBannerConfigJson -Config (New-UsaBannerDeployConfig -Flags @{ Company = 'Contoso'; Environment = 'PROD' })
        }
    }

    It 'runs without error, and makes the GPO with a comment that says what it holds and that a run overwrites changes made in GPMC' {
        $script:R.Error | Should -BeNullOrEmpty
        $script:D.Gpos.Count | Should -Be 1
        $script:Gpo.Name | Should -BeExactly 'UsaBanner'
        $script:Gpo.Comment | Should -BeLike '*Deploy-UsaBannerGPO*'
        $script:Gpo.Comment | Should -BeLike '*overwrites changes made in GPMC*'
    }

    It 'stages the Windows copy: the package, the module folder whole, and the mark' {
        $expected = @(@('usabanner.json', '.usabanner-gpo') + @($script:ModuleFiles | ForEach-Object { "UsaBanner/$_" }))
        [array]::Sort($expected, [System.StringComparer]::Ordinal)
        Get-FileList $script:D.Netlogon | Should -Be $expected
        foreach ($file in $script:ModuleFiles) {
            [System.IO.File]::ReadAllBytes((Join-Path $script:D.Netlogon 'UsaBanner' $file)) | Should -Be ([System.IO.File]::ReadAllBytes((Join-Path $script:ModuleRoot $file))) -Because $file
        }
    }

    It 'stages the Ubuntu copy: the same, and the ADSys startup script at its root, from the module''s linux folder' {
        $expected = @(@('adsys-startup.sh', 'usabanner.json', '.usabanner-gpo') + @($script:ModuleFiles | ForEach-Object { "UsaBanner/$_" }))
        [array]::Sort($expected, [System.StringComparer]::Ordinal)
        Get-FileList $script:Ubuntu | Should -Be $expected
        [System.IO.File]::ReadAllBytes((Join-Path $script:Ubuntu 'adsys-startup.sh')) | Should -Be ([System.IO.File]::ReadAllBytes((Join-Path $script:ModuleRoot 'linux' 'adsys-startup.sh')))
        [System.IO.File]::ReadAllBytes((Join-Path $script:Ubuntu 'UsaBanner' 'linux' 'bootstrap.sh')) | Should -Be ([System.IO.File]::ReadAllBytes((Join-Path $script:ModuleRoot 'linux' 'bootstrap.sh')))
        [System.IO.File]::ReadAllBytes((Join-Path $script:Ubuntu '.usabanner-gpo')) | Should -Be ([System.IO.File]::ReadAllBytes((Join-Path $script:D.Netlogon '.usabanner-gpo')))
    }

    It 'writes the package as the module writes a configuration: what the flags build, UTF-8 without a byte order mark, ASCII, LF' {
        foreach ($package in (Join-Path $script:D.Netlogon 'usabanner.json'), (Join-Path $script:Ubuntu 'usabanner.json')) {
            $bytes = [System.IO.File]::ReadAllBytes($package)
            [System.Text.Encoding]::UTF8.GetString($bytes) | Should -BeExactly $script:Package
            @($bytes | Where-Object { $_ -gt 126 -or ($_ -lt 32 -and $_ -ne 10) }) | Should -BeNullOrEmpty
        }
        $script:Package | Should -BeLike '*"company": "Contoso"*'
        $script:Package | Should -BeLike '*"environment": "PROD"*'
    }

    It 'raises the ADSys Version by one: the Ubuntu copy changed, and ADSys downloads again only when it moves' {
        Get-IniVersion (Join-Path $script:D.Ubuntu 'GPT.INI') | Should -Be 8
        [System.IO.File]::ReadAllText((Join-Path $script:D.Ubuntu 'GPT.INI')) | Should -BeExactly "[General]`r`nVersion=8`r`n"
    }

    It 'writes one ImmediateTaskV2 for servers only, that runs the Windows runner from the domain''s NETLOGON as SYSTEM' {
        $file = Join-Path $script:D.Policies $script:Gpo.Guid 'Machine' 'Preferences' 'ScheduledTasks' 'ScheduledTasks.xml'
        $items = @(([xml][System.IO.File]::ReadAllText($file)).DocumentElement.ChildNodes | Where-Object NodeType -eq 'Element')
        $items | Should -HaveCount 1
        $items[0].LocalName | Should -Be 'ImmediateTaskV2'
        $items[0].GetAttribute('name') | Should -BeExactly 'UsaBanner sync'
        $items[0].SelectSingleNode('Properties').GetAttribute('runAs') | Should -BeExactly 'NT AUTHORITY\System'
        $items[0].SelectSingleNode('Properties/Task/Actions/Exec/Command').InnerText | Should -BeExactly 'powershell.exe'
        $items[0].SelectSingleNode('Properties/Task/Actions/Exec/Arguments').InnerText | Should -BeExactly "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script:TaskScript`""
        $items[0].SelectSingleNode('Filters/FilterWmi').GetAttribute('query') | Should -BeExactly 'SELECT * FROM Win32_OperatingSystem WHERE ProductType = 2 OR ProductType = 3'
        $items[0].SelectSingleNode('Properties/Task/Settings/ExecutionTimeLimit').InnerText | Should -BeExactly 'PT30M'
    }

    It 'names, for the task, the runner that the Windows copy holds: the path the domain gives is the file staged' {
        $relative = $script:TaskScript.Substring('\\ad.example\NETLOGON\UsaBanner\'.Length).Replace('\', '/')
        $runner = Join-Path $script:D.Netlogon $relative
        $runner | Should -Exist
        # Sync-UsaBanner.ps1 finds the package beside the module folder it sits in: two folders up from it.
        Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $runner))) 'usabanner.json' | Should -Exist
    }

    It 'sets exactly two ADSys startup values, and names, for the second, the script the Ubuntu copy holds' {
        @($script:Gpo.Values.Keys) | Should -Be @('metaValues', 'all')
        $script:Gpo.Values['metaValues'].Type | Should -Be 'String'
        $script:Gpo.Values['metaValues'].Value | Should -BeExactly '{"22.04":{"strategy":"append"},"24.04":{"strategy":"append"},"25.04":{"strategy":"append"},"25.10":{"strategy":"append"},"all":{"strategy":"append"}}'
        $script:Gpo.Values['all'].Type | Should -Be 'MultiString'
        $script:Gpo.Values['all'].Value | Should -Be @('UsaBanner/adsys-startup.sh')
        Join-Path $script:D.Ubuntu 'scripts' 'UsaBanner/adsys-startup.sh' | Should -Exist
    }

    It 'registers the Scheduled Tasks extension beside the Registry one that setting the values registered, with the computer settings on' {
        # The list is read after the values are set: read before, it would lack the Registry group, and the
        # run would take it from the GPO (the ADSys values would then never be applied).
        $script:Gpo.Attr['gPCMachineExtensionNames'] | Should -BeExactly '[{00000000-0000-0000-0000-000000000000}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}][{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}][{AADCED64-746C-4633-A97C-D61349046527}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]'
        $script:Gpo.Attr['flags'] | Should -Be 0
    }

    It 'raises the version once itself, in AD and in GPT.INI to the same number, on top of the two the cmdlets raised for the values' {
        $script:Gpo.Attr['versionNumber'] | Should -Be 3
        Get-IniVersion (Join-Path $script:D.Policies $script:Gpo.Guid 'GPT.INI') | Should -Be 3
        @($script:D.Writes | Where-Object { $_ -eq 'set attribute versionNumber' }) | Should -HaveCount 1
    }

    It 'links it at the one target, enabled, and nowhere else: not at the domain root' {
        $script:D.Links[$script:ServersOu] | Should -HaveCount 1
        $script:D.Links[$script:ServersOu][0].Guid | Should -Be $script:Gpo.Guid
        $script:D.Links[$script:ServersOu][0].Flags | Should -Be 0
        $script:D.Links[$script:LinuxOu] | Should -HaveCount 0
        $script:D.Links[$script:RootDn] | Should -HaveCount 0
    }

    It 'writes the files first and the policy last: when the GPO was first written to, both copies and the ADSys Version were done' {
        $script:D.AtFirstPolicyWrite.Windows | Should -BeTrue
        $script:D.AtFirstPolicyWrite.Ubuntu | Should -BeTrue
        $script:D.AtFirstPolicyWrite.Version | Should -Be 8
    }

    It 'asks for nothing else to be changed in the domain, in this order' {
        @($script:D.Writes) | Should -Be @(
            'New-GPO UsaBanner'
            'set value metaValues'
            'set value all'
            'set attribute gPCMachineExtensionNames'
            'set attribute versionNumber'
            "link $script:ServersOu"
        )
    }

    It 'says each change in a line, then reads it all back: nine checks, every one ok' {
        $changes = Get-ChangeLine $script:R
        $changes | Should -HaveCount 10
        $changes[0] | Should -BeLike "staged $($script:D.Netlogon) for Windows hosts: $($script:ModuleFiles.Count + 2) file(s) written, 0 removed"
        $changes[1] | Should -BeLike "staged $($script:Ubuntu) for Ubuntu hosts: $($script:ModuleFiles.Count + 3) file(s) written, 0 removed"
        $changes[2] | Should -BeLike 'raised the Version in * from 7 to 8:*'
        $changes[3] | Should -BeLike "made the GPO 'UsaBanner' (id {A0000000-*"
        $changes[4] | Should -BeLike 'set the startup value metaValues = *'
        $changes[5] | Should -BeLike 'set the startup value all = UsaBanner/adsys-startup.sh'
        $changes[6] | Should -BeLike 'wrote *ScheduledTasks.xml: the task ''UsaBanner sync''*'
        $changes[7] | Should -BeLike "registered the Scheduled Tasks extension on the GPO 'UsaBanner': *"
        $changes[8] | Should -BeLike "raised the version of the GPO 'UsaBanner' from 2 to 3 (AD and GPT.INI)"
        $changes[9] | Should -BeLike "linked the GPO 'UsaBanner' at $script:ServersOu, enabled"
        $checks = Get-CheckLine $script:R
        $checks | Should -HaveCount 9
        @($checks | Where-Object { $_ -notlike 'ok   *' }) | Should -BeNullOrEmpty
        $script:R.Lines | Should -HaveCount 19
    }

    It 'names, in the read-back, what it checked' {
        $checks = Get-CheckLine $script:R
        $checks[0] | Should -BeLike "ok   Windows hosts: $($script:D.Netlogon) is the payload, $($script:ModuleFiles.Count + 2) files by SHA-256 and nothing else"
        $checks[1] | Should -BeLike "ok   Ubuntu hosts: $($script:Ubuntu) is the payload, $($script:ModuleFiles.Count + 3) files by SHA-256 and nothing else"
        $checks[2] | Should -BeExactly 'ok   Ubuntu GPT.INI is at Version 8, at least 8'
        $checks[3] | Should -BeLike "ok   task 'UsaBanner sync' in *ScheduledTasks.xml is the one wanted"
        $checks[4] | Should -BeExactly 'ok   Scheduled Tasks extension registered'
        $checks[5] | Should -BeExactly 'ok   computer settings enabled'
        $checks[6] | Should -BeExactly 'ok   version in AD (3) = GPT.INI (3)'
        $checks[7] | Should -BeLike 'ok   startup values: metaValues (append, every release) and all = UsaBanner/adsys-startup.sh, nothing else under HKLM\Software\Policies\Ubuntu\scripts\startup'
        $checks[8] | Should -BeExactly "ok   linked at $script:ServersOu, enabled"
    }

    It 'warns of one thing only, a domain with no deploy-usawinssh GPO linked, and says the domain it worked in' {
        $script:R.Warnings | Should -HaveCount 1
        $script:R.Warnings[0] | Should -BeLike "*no GPO that makes the task 'UsaDeploy-WinSsh' is linked and enabled*Windows servers without PowerShell 7 get no banner*"
        $script:R.Notes | Should -HaveCount 1
        $script:R.Notes[0] | Should -BeLike 'Domain ad.example, PDC emulator dc01.ad.example.*compatibility session*'
    }
}

Describe 'Deploy-UsaBannerGPO, the same run again' {
    BeforeAll {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
        $parameters = @{ Company = 'Contoso'; Environment = 'PROD'; LinkTarget = @($script:ServersOu) }
        $script:First = Invoke-Gpo $parameters
        Set-OldTimes $script:D
        $script:Before = @(Get-DomainState $script:D)
        $script:D.Writes.Clear()
        $script:Again = Invoke-Gpo $parameters
        $script:After = @(Get-DomainState $script:D)
    }

    It 'asks for nothing to be changed: no attribute, value, version or link is set, and no GPO made' {
        $script:Again.Error | Should -BeNullOrEmpty
        $script:D.Writes | Should -HaveCount 0
        $script:After[-1] | Should -BeExactly 'writes: '
    }

    It 'writes no file again: the domain is as it was, every file with the SHA-256 and the time stamp it had' {
        # A file written again, even with the same bytes, has a new time stamp: Set-OldTimes gave every file an old one.
        @($script:After | Where-Object { $_ -notlike 'writes:*' }) | Should -Be @($script:Before | Where-Object { $_ -notlike 'writes:*' })
        @($script:After | Where-Object { $_ -like 'file *' }).Count | Should -BeGreaterThan 130
    }

    It 'returns only the read-back lines, the same nine' {
        $script:Again.Lines | Should -HaveCount 9
        (Get-ChangeLine $script:Again) | Should -HaveCount 0
        $script:Again.Lines | Should -Be (Get-CheckLine $script:First)
    }

    It 'warns of the neighbours still, and of nothing about the GPO: it holds what the run wants' {
        $script:Again.Warnings | Should -HaveCount 1
        $script:Again.Warnings[0] | Should -BeLike '*UsaDeploy-WinSsh*'
        $script:Again.Notes | Should -HaveCount 1
    }
}

Describe 'Deploy-UsaBannerGPO, a changed package' {
    BeforeAll {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
        $script:First = Invoke-Gpo @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu) }
        Set-OldTimes $script:D
        $script:Before = Get-FileMap $script:D
        $script:Gpo = Get-GpoByName $script:D
        $script:GpoBefore = "$($script:Gpo.Attr['versionNumber']) $($script:Gpo.Attr['flags']) $($script:Gpo.Attr['gPCMachineExtensionNames'])"
        $script:D.Writes.Clear()
        $script:R = Invoke-Gpo @{ Company = 'Contoso Ltd'; LinkTarget = @($script:ServersOu) }
        $script:After = Get-FileMap $script:D
    }

    It 'rewrites the package in both copies, and no other file; the Ubuntu GPT.INI moves, for ADSys' {
        $script:R.Error | Should -BeNullOrEmpty
        Get-Changed $script:Before $script:After | Should -Be @(
            'NETLOGON/UsaBanner/usabanner.json'
            'SYSVOL/ad.example/Ubuntu/GPT.INI'
            'SYSVOL/ad.example/Ubuntu/scripts/UsaBanner/usabanner.json'
        )
        [System.IO.File]::ReadAllText((Join-Path $script:D.Netlogon 'usabanner.json')) | Should -BeLike '*"company": "Contoso Ltd"*'
        [System.IO.File]::ReadAllText((Join-Path $script:D.Ubuntu 'scripts' 'UsaBanner' 'usabanner.json')) | Should -BeLike '*"company": "Contoso Ltd"*'
    }

    It 'raises the Ubuntu GPT.INI by one' {
        Get-IniVersion (Join-Path $script:D.Ubuntu 'GPT.INI') | Should -Be 9
    }

    It 'leaves the GPO alone: its version is not stepped, and no attribute, value or link is touched' {
        $script:D.Writes | Should -HaveCount 0
        "$($script:Gpo.Attr['versionNumber']) $($script:Gpo.Attr['flags']) $($script:Gpo.Attr['gPCMachineExtensionNames'])" | Should -BeExactly $script:GpoBefore
        Get-IniVersion (Join-Path $script:D.Policies $script:Gpo.Guid 'GPT.INI') | Should -Be 3
    }

    It 'says the two files and the Version in a line each, and no warning about the GPO' {
        $changes = Get-ChangeLine $script:R
        $changes | Should -HaveCount 3
        $changes[0] | Should -BeLike 'staged * for Windows hosts: 1 file(s) written, 0 removed'
        $changes[1] | Should -BeLike 'staged * for Ubuntu hosts: 1 file(s) written, 0 removed'
        $changes[2] | Should -BeLike 'raised the Version in * from 8 to 9:*'
        @($script:R.Warnings | Where-Object { $_ -like '*exists already*' }) | Should -HaveCount 0
        (Get-CheckLine $script:R) | Should -HaveCount 9
    }
}

Describe 'Deploy-UsaBannerGPO, a publish cut short before the Ubuntu Version moved' {
    BeforeAll {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
        $script:Ini = Join-Path $script:D.Ubuntu 'GPT.INI'
        $script:Ubuntu = Join-Path $script:D.Ubuntu 'scripts' 'UsaBanner'
        $null = Invoke-Gpo @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu) }
        # A GPT.INI that cannot be written stands for a run stopped there, when every file of both copies
        # is written (the suite runs as a user other than root, whom the mode stops).
        [System.IO.File]::SetUnixFileMode($script:Ini, [System.IO.UnixFileMode]'UserRead, GroupRead, OtherRead')
        $script:Cut = Invoke-Gpo @{ Company = 'Contoso Ltd'; LinkTarget = @($script:ServersOu) }
        $script:VersionAfterCut = Get-IniVersion $script:Ini
        $script:FlagsAfterCut = @(@((Join-Path $script:D.Netlogon '.usabanner-publishing'), (Join-Path $script:Ubuntu '.usabanner-publishing')) | Where-Object { Test-Path -LiteralPath $_ })
        $script:PackageAfterCut = [System.IO.File]::ReadAllText((Join-Path $script:Ubuntu 'usabanner.json'))
        [System.IO.File]::SetUnixFileMode($script:Ini, [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead')
        Set-OldTimes $script:D
        $script:Before = Get-FileMap $script:D
        $script:D.Writes.Clear()
        $script:R = Invoke-Gpo @{ Company = 'Contoso Ltd'; LinkTarget = @($script:ServersOu) }
        $script:After = Get-FileMap $script:D
    }

    It 'stops at the GPT.INI with the new package written, the Version where it was, and the Ubuntu copy marked as unfinished: the Windows copy, which waits for no Version, is done' {
        $script:Cut.Error | Should -Not -BeNullOrEmpty
        $script:PackageAfterCut | Should -BeLike '*"company": "Contoso Ltd"*'
        $script:VersionAfterCut | Should -Be 8
        $script:FlagsAfterCut | Should -Be @(Join-Path $script:Ubuntu '.usabanner-publishing')
    }

    It 'finishes it at the next run of the same package: the Version goes up, though no file of either copy is written again, and the GPO is not touched' {
        $script:R.Error | Should -BeNullOrEmpty
        Get-IniVersion $script:Ini | Should -Be 9
        Get-Changed $script:Before $script:After | Should -Be @(
            'SYSVOL/ad.example/Ubuntu/GPT.INI'
            'SYSVOL/ad.example/Ubuntu/scripts/UsaBanner/.usabanner-publishing'
        )
        $script:D.Writes | Should -HaveCount 0
    }

    It 'says so, takes the marker away, and every read-back check is ok' {
        $changes = Get-ChangeLine $script:R
        $changes | Should -HaveCount 2
        $changes[0] | Should -BeLike 'staged * for Ubuntu hosts: 0 file(s) written, 0 removed; the last publish here was cut short, and this one finishes it'
        $changes[1] | Should -BeLike 'raised the Version in * from 8 to 9:*'
        Join-Path $script:Ubuntu '.usabanner-publishing' | Should -Not -Exist
        (Get-CheckLine $script:R) | Should -HaveCount 9
        @(Get-CheckLine $script:R | Where-Object { $_ -notlike 'ok   *' }) | Should -HaveCount 0
    }
}

Describe 'Deploy-UsaBannerGPO, a first publish cut short before any file' {
    It 'takes a folder that holds only the marker of an unfinished publish as its own, not someone else''s, and finishes it' {
        $d = New-FakeDomain
        Use-FakeDomain $d
        Write-TestFile (Join-Path $d.Netlogon '.usabanner-publishing') "started`n"
        $r = Invoke-Gpo @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu) }
        $r.Error | Should -BeNullOrEmpty
        (Get-ChangeLine $r)[0] | Should -BeLike 'staged * for Windows hosts: * file(s) written, 0 removed; the last publish here was cut short, and this one finishes it'
        Join-Path $d.Netlogon '.usabanner-publishing' | Should -Not -Exist
    }
}

Describe 'Deploy-UsaBannerGPO, what the staged copies hold' {
    BeforeEach {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
        $script:Mod = New-FakeModule
        Use-FakeModule $script:Mod
        $script:Ubuntu = Join-Path $script:D.Ubuntu 'scripts' 'UsaBanner'
    }

    It 'stages a file with CRLF line ends as LF, in both copies, and says how many files it converted' {
        $r = Invoke-Gpo @{ LinkTarget = @($script:ServersOu) }
        $r.Error | Should -BeNullOrEmpty
        foreach ($copy in $script:D.Netlogon, $script:Ubuntu) {
            [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes((Join-Path $copy 'UsaBanner' 'data' 'crlf.txt'))) | Should -BeExactly "one`ntwo`nlone`rcr`n"
            [System.IO.File]::ReadAllText((Join-Path $copy 'UsaBanner' 'data' 'lf.txt')) | Should -BeExactly "a`nb`n"
        }
        $r.Lines | Should -Contain "1 file(s) of the module have CRLF line endings in this clone (Git for Windows' core.autocrlf); they are staged as LF"
        $r.Error | Should -BeNullOrEmpty
        (Get-CheckLine $r) | Should -HaveCount 9
    }

    It 'copies a file with a NUL byte as it is, byte for byte: it is binary' {
        $null = Invoke-Gpo
        foreach ($copy in $script:D.Netlogon, $script:Ubuntu) {
            [System.IO.File]::ReadAllBytes((Join-Path $copy 'UsaBanner' 'data' 'binary.bin')) | Should -Be ([byte[]](0x00, 0x0D, 0x0A, 0xFF, 0x0D, 0x0A))
        }
    }

    It 'holds the Windows copy to the package, the module and the mark, and the Ubuntu copy to that and the startup script' {
        $null = Invoke-Gpo
        $module = @('data/binary.bin', 'data/crlf.txt', 'data/lf.txt', 'linux/adsys-startup.sh', 'Private/Old.ps1', 'Public/Hello.ps1', 'UsaBanner.psd1', 'windows/Sync-UsaBanner.ps1' | ForEach-Object { "UsaBanner/$_" })
        $windows = @($module + '.usabanner-gpo' + 'usabanner.json')
        $ubuntu = @($windows + 'adsys-startup.sh')
        [array]::Sort($windows, [System.StringComparer]::Ordinal)
        [array]::Sort($ubuntu, [System.StringComparer]::Ordinal)
        Get-FileList $script:D.Netlogon | Should -Be $windows
        Get-FileList $script:Ubuntu | Should -Be $ubuntu
        $windows | Should -HaveCount 10
        $ubuntu | Should -HaveCount 11
    }

    It 'removes, from both copies, a file the module no longer has, and raises the Ubuntu Version for it' {
        $null = Invoke-Gpo
        $before = Get-IniVersion (Join-Path $script:D.Ubuntu 'GPT.INI')
        Remove-Item -LiteralPath (Join-Path $script:Mod 'Private' 'Old.ps1')
        $r = Invoke-Gpo
        $r.Error | Should -BeNullOrEmpty
        foreach ($copy in $script:D.Netlogon, $script:Ubuntu) {
            Join-Path $copy 'UsaBanner' 'Private' 'Old.ps1' | Should -Not -Exist
            Join-Path $copy 'UsaBanner' 'Public' 'Hello.ps1' | Should -Exist
        }
        Get-IniVersion (Join-Path $script:D.Ubuntu 'GPT.INI') | Should -Be ($before + 1)
        (Get-ChangeLine $r)[0] | Should -BeLike 'staged * for Windows hosts: 0 file(s) written, 1 removed'
    }

    It 'removes what its folder holds that the payload does not, a leftover temporary file too, but only in a folder with the mark' {
        $null = Invoke-Gpo
        $other = Join-Path $script:D.Ubuntu 'scripts' 'OtherPolicy' 'other.sh'
        Write-TestFile $other "echo other`n"
        Write-TestFile (Join-Path $script:D.Netlogon 'Stale.txt') "stale`n"
        Write-TestFile (Join-Path $script:Ubuntu 'UsaBanner' 'Private' 'Stale.ps1') "# stale`n"
        Write-TestFile (Join-Path $script:Ubuntu 'usabanner.json.usabanner-tmp') "half`n"
        $r = Invoke-Gpo
        $r.Error | Should -BeNullOrEmpty
        Join-Path $script:D.Netlogon 'Stale.txt' | Should -Not -Exist
        Join-Path $script:Ubuntu 'UsaBanner' 'Private' 'Stale.ps1' | Should -Not -Exist
        Join-Path $script:Ubuntu 'usabanner.json.usabanner-tmp' | Should -Not -Exist
        $other | Should -Exist
    }

    It 'writes a changed file in place of the old one, and leaves no temporary file behind' {
        $null = Invoke-Gpo
        [System.IO.File]::WriteAllText((Join-Path $script:Mod 'Public' 'Hello.ps1'), "# hello again`n")
        $null = Invoke-Gpo
        [System.IO.File]::ReadAllText((Join-Path $script:D.Netlogon 'UsaBanner' 'Public' 'Hello.ps1')) | Should -BeExactly "# hello again`n"
        @(Get-FileList $script:D.Netlogon | Where-Object { $_ -like '*.usabanner-tmp' }) | Should -HaveCount 0
    }

    It 'makes itself at home in a folder that exists and holds nothing, or only the mark and files of its own' {
        $null = New-Item -ItemType Directory -Path $script:D.Netlogon -Force
        $null = New-Item -ItemType Directory -Path (Join-Path $script:Ubuntu 'empty folder') -Force
        $r = Invoke-Gpo
        $r.Error | Should -BeNullOrEmpty
        Join-Path $script:D.Netlogon 'usabanner.json' | Should -Exist
        Join-Path $script:Ubuntu 'usabanner.json' | Should -Exist
    }
}

Describe 'Deploy-UsaBannerGPO, a run it refuses' {
    BeforeEach {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
        $script:Ubuntu = Join-Path $script:D.Ubuntu 'scripts' 'UsaBanner'
    }

    Context 'a package that turns the update channel on' {
        BeforeAll {
            $script:UpdateFile = Join-Path $TestDrive 'update-on.json'
            [System.IO.File]::WriteAllText($script:UpdateFile, '{ "update": { "mode": "notify", "source": "https://updates.example/usabanner" } }')
        }

        It 'refuses -<Case>, says why, and reads nothing from the domain and writes nothing' -ForEach @(
            @{ Case = 'Update notify'; Parameters = @{ Update = 'notify'; UpdateSource = 'https://updates.example/usabanner' }; Mode = 'notify' }
            @{ Case = 'Update install'; Parameters = @{ Update = 'install'; UpdateSource = 'https://updates.example/usabanner' }; Mode = 'install' }
            @{ Case = 'Path of a file that turns it on'; Parameters = @{ Path = 'UPDATEFILE' }; Mode = 'notify' }
        ) {
            if ($Parameters.ContainsKey('Path')) { $Parameters['Path'] = $script:UpdateFile }
            $before = @(Get-DomainState $script:D)
            $r = Invoke-Gpo $Parameters
            $r.Error | Should -BeLike '*No update channel in a package for Group Policy*'
            $r.Error | Should -BeLike "*update.mode to '$Mode'*"
            $r.Error | Should -BeLike '*the GPO is the update path*'
            $r.Error | Should -BeLike '*Nothing was read from the domain, and nothing was written*'
            $r.Lines | Should -HaveCount 0
            @(Get-DomainState $script:D) | Should -Be $before
            Should -Invoke Import-UsaBannerGroupPolicy -ModuleName UsaBanner -Times 0 -Exactly
            Should -Invoke Get-UsaBannerGpoDomain -ModuleName UsaBanner -Times 0 -Exactly
            Should -Invoke Find-UsaBannerGpo -ModuleName UsaBanner -Times 0 -Exactly
        }

        It 'runs with the channel off, which is what the refusals are checked against' {
            $r = Invoke-Gpo @{ Update = 'off'; Company = 'Contoso' }
            $r.Error | Should -BeNullOrEmpty
            Join-Path $script:D.Netlogon 'usabanner.json' | Should -Exist
            Should -Invoke Import-UsaBannerGroupPolicy -ModuleName UsaBanner -Times 1 -Exactly
        }
    }

    Context 'a destination folder that is someone else''s' {
        It 'refuses <Where>, which holds files and has no mark, names it, and writes nothing, in either copy or the GPO' -ForEach @(
            @{ Where = 'the Windows folder'; Tree = 'Netlogon'; Sub = ''; File = 'logon.bat' }
            @{ Where = 'the Ubuntu folder'; Tree = 'Ubuntu'; Sub = ''; File = 'other.sh' }
            @{ Where = 'a Windows folder with a file in a subfolder'; Tree = 'Netlogon'; Sub = 'deep/er'; File = 'x.txt' }
        ) {
            $folder = if ($Tree -eq 'Netlogon') { $script:D.Netlogon } else { $script:Ubuntu }
            Write-TestFile (Join-Path (Join-Path $folder $Sub) $File) "echo hers`n"
            $before = @(Get-DomainState $script:D)
            $r = Invoke-Gpo @{ LinkTarget = @($script:ServersOu) }
            $r.Error | Should -BeLike "*$folder already holds files*"
            $r.Error | Should -BeLike '*no .usabanner-gpo in it*'
            $r.Error | Should -BeLike '*Nothing was written*'
            $r.Lines | Should -HaveCount 0
            @(Get-DomainState $script:D) | Should -Be $before
            $script:D.Gpos.Count | Should -Be 0
        }

        It 'does not take a folder with the mark for someone else''s: it is cleaned of what is not the payload' {
            Write-TestFile (Join-Path $script:D.Netlogon '.usabanner-gpo') 'mine'
            Write-TestFile (Join-Path $script:D.Netlogon 'old.txt') 'old'
            $r = Invoke-Gpo
            $r.Error | Should -BeNullOrEmpty
            Join-Path $script:D.Netlogon 'old.txt' | Should -Not -Exist
        }
    }

    It 'refuses two GPOs of the name, names them, and writes nothing: not a file of either copy' {
        $first = Add-FakeGpo $script:D 'UsaBanner'
        $second = Add-FakeGpo $script:D 'usabanner'
        $before = @(Get-DomainState $script:D)
        $r = Invoke-Gpo @{ LinkTarget = @($script:ServersOu) }
        $r.Error | Should -BeLike "*2 GPOs are named 'UsaBanner' ($first, $second)*Nothing was written*"
        @(Get-DomainState $script:D) | Should -Be $before
        Join-Path $script:D.Netlogon 'usabanner.json' | Should -Not -Exist
    }

    It 'refuses a -LinkTarget that is not there, names it, and writes nothing, though another is' {
        $before = @(Get-DomainState $script:D)
        $r = Invoke-Gpo @{ LinkTarget = @($script:ServersOu, 'OU=Nope,DC=ad,DC=example') }
        $r.Error | Should -BeLike "*-LinkTarget 'OU=Nope,DC=ad,DC=example' is not an object*Nothing was written*"
        @(Get-DomainState $script:D) | Should -Be $before
        Should -Invoke Find-UsaBannerGpo -ModuleName UsaBanner -Times 0 -Exactly
    }

    It 'refuses a package that holds a character that is not ASCII, reads nothing from the domain, and writes nothing' {
        # Straight to the worker: the schema check that would refuse this setting first can fail quietly (Test-Json, PowerShell 7.6).
        $before = @(Get-DomainState $script:D)
        $message = InModuleScope UsaBanner {
            $config = Get-UsaBannerConfigDefault
            $config['company'] = 'Caf' + [char]0xE9
            try { $null = Invoke-UsaBannerGpoDeploy -Config $config -Name 'UsaBanner'; '' } catch { $_.Exception.Message }
        }
        $message | Should -BeLike '*the package holds a character that is not ASCII (U+00E9 at position *of usabanner.json)*'
        $message | Should -BeLike '*Nothing was read from the domain, and nothing was written*'
        @(Get-DomainState $script:D) | Should -Be $before
        Should -Invoke Import-UsaBannerGroupPolicy -ModuleName UsaBanner -Times 0 -Exactly
    }

    It 'refuses a ScheduledTasks.xml that <Why>, and does not overwrite it' -ForEach @(
        @{ Why = 'is not XML'; Text = '<ScheduledTasks><broken'; Message = '*not XML*' }
        @{ Why = 'is another kind of file'; Text = '<Files clsid="x"/>'; Message = '*<Files> root*' }
    ) {
        $guid = Add-FakeGpo $script:D 'UsaBanner' -TasksXml $Text
        $file = Join-Path $script:D.Policies $guid 'Machine' 'Preferences' 'ScheduledTasks' 'ScheduledTasks.xml'
        $before = @(Get-DomainState $script:D)
        $r = Invoke-Gpo @{ LinkTarget = @($script:ServersOu) }
        $r.Error | Should -BeLike $Message
        $r.Error | Should -BeLike '*ScheduledTasks.xml*Nothing was written*'
        [System.IO.File]::ReadAllText($file) | Should -BeExactly $Text
        @(Get-DomainState $script:D) | Should -Be $before
    }

    It 'refuses to stage the module onto itself: the module''s folder is <Where>' -ForEach @(
        @{ Where = 'the Windows copy'; Folder = 'Netlogon'; Sub = '' }
        @{ Where = 'inside the Windows copy'; Folder = 'Netlogon'; Sub = 'UsaBanner' }
        @{ Where = 'inside the Ubuntu copy'; Folder = 'Ubuntu'; Sub = 'scripts/UsaBanner/UsaBanner' }
    ) {
        $root = $script:D[$Folder]
        $at = if ($Sub) { Join-Path $root $Sub } else { $root }
        $null = New-FakeModule -At $at
        Use-FakeModule $at
        $before = @(Get-DomainState $script:D)
        $r = Invoke-Gpo
        $r.Error | Should -BeLike '*staging would copy it onto itself*Nothing was written*'
        @(Get-DomainState $script:D) | Should -Be $before
        $script:D.Gpos.Count | Should -Be 0
    }
}

Describe 'Deploy-UsaBannerGPO, a domain with no ADSys assets folder' {
    BeforeAll {
        $script:D = New-FakeDomain -NoAdsys
        Use-FakeDomain $script:D
        $script:R = Invoke-Gpo @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu) }
        $script:Gpo = Get-GpoByName $script:D
    }

    It 'warns that Ubuntu hosts get nothing, and says what to make' {
        $script:R.Warnings[0] | Should -BeLike "*$((Join-Path $script:D.Ubuntu 'GPT.INI') -replace '\\', '*') is not there, so Ubuntu hosts get nothing from this GPO*"
        $script:R.Warnings[0] | Should -BeLike '*Make the folder, and a GPT.INI in it with the two lines [[]General] and Version=1*'
        $script:R.Warnings[0] | Should -BeLike '*The Windows half goes on*'
    }

    It 'does the Windows half: the copy, the task, the extension, the version and the link' {
        $script:R.Error | Should -BeNullOrEmpty
        Join-Path $script:D.Netlogon 'usabanner.json' | Should -Exist
        Join-Path $script:D.Netlogon 'UsaBanner' 'windows' 'Sync-UsaBanner.ps1' | Should -Exist
        Join-Path $script:D.Policies $script:Gpo.Guid 'Machine' 'Preferences' 'ScheduledTasks' 'ScheduledTasks.xml' | Should -Exist
        $script:Gpo.Attr['gPCMachineExtensionNames'] | Should -BeLike "*$script:Cse*"
        $script:Gpo.Attr['versionNumber'] | Should -Be 1
        $script:D.Links[$script:ServersOu] | Should -HaveCount 1
    }

    It 'does nothing for Ubuntu: no copy, no GPT.INI made, and no startup value set' {
        Test-Path -LiteralPath $script:D.Ubuntu | Should -BeFalse
        $script:Gpo.Values.Count | Should -Be 0
        @($script:D.Writes | Where-Object { $_ -like '*value*' }) | Should -HaveCount 0
        @($script:R.Lines | Where-Object { $_ -like '*Ubuntu*' }) | Should -HaveCount 0
    }

    It 'reads back only what it did: six checks, every one ok' {
        $checks = Get-CheckLine $script:R
        $checks | Should -HaveCount 6
        @($checks | Where-Object { $_ -notlike 'ok   *' }) | Should -BeNullOrEmpty
    }
}

Describe 'Deploy-UsaBannerGPO, a GPO that exists already' {
    BeforeAll {
        $script:Old = New-TasksFile @(
            (New-TaskItem -Name 'UsaBanner sync' -Uid '{0F0F0F0F-1111-2222-3333-444444444444}' -Arguments '-File \\ad.example\SYSVOL\ad.example\old.ps1')
            (New-TaskItem -Name 'Someone else' -Uid '{0E0E0E0E-1111-2222-3333-444444444444}' -Arguments '-File other.ps1')
        )
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
        $script:Guid = Add-FakeGpo $script:D 'UsaBanner' -TasksXml $script:Old -Flags 2 -Version 3 `
            -Values @{ all = @{ Type = 'MultiString'; Value = @('Other/x.sh') }; '24.04' = @{ Type = 'MultiString'; Value = @('Other/y.sh') } } `
            -Areas @('Computer: Security Settings', 'User: Folder Redirection') `
            -Ext '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
        $script:R = Invoke-Gpo @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu) }
        $script:Gpo = $script:D.Gpos[$script:Guid]
    }

    It 'writes the files first here too: both copies and the ADSys Version were done before the first value was set' {
        $script:D.AtFirstPolicyWrite.Windows | Should -BeTrue
        $script:D.AtFirstPolicyWrite.Ubuntu | Should -BeTrue
        $script:D.AtFirstPolicyWrite.Version | Should -Be 8
    }

    It 'makes no second GPO, and writes into the one there is' {
        $script:R.Error | Should -BeNullOrEmpty
        $script:D.Gpos.Count | Should -Be 1
        @($script:D.Writes | Where-Object { $_ -like 'New-GPO*' }) | Should -HaveCount 0
        @($script:R.Lines | Where-Object { $_ -like 'made the GPO*' }) | Should -HaveCount 0
    }

    It 'warns first, with one line for each setting it holds otherwise, old and new: the task, the startup values, the computer settings' {
        $script:R.Warnings[0] | Should -BeExactly "UsaBanner: the GPO 'UsaBanner' exists already (id $script:Guid); this run overwrites these of its settings with the module's:"
        $lines = @($script:R.Warnings | Select-Object -Skip 1)
        $lines | Should -Contain "  startup value metaValues: (not set) -> '$(InModuleScope UsaBanner { Get-UsaBannerGpoStartupMeta })'"
        $lines | Should -Contain "  startup value all: 'Other/x.sh' -> 'UsaBanner/adsys-startup.sh'"
        $lines | Should -Contain "  startup value 24.04: 'Other/y.sh' -> removed"
        $lines | Should -Contain "  task 'UsaBanner sync' Kind: 'TaskV2' -> 'ImmediateTaskV2'"
        $lines | Should -Contain "  task 'UsaBanner sync' Arguments: '-File \\ad.example\SYSVOL\ad.example\old.ps1' -> '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File ""$script:TaskScript""'"
        $lines | Should -Contain "  task 'UsaBanner sync' Filters: 'none' -> 'WMI: SELECT * FROM Win32_OperatingSystem WHERE ProductType = 2 OR ProductType = 3'"
        $lines | Should -Contain '  computer settings: disabled -> enabled'
    }

    It 'warns, beside it, of what else the GPO holds and the run leaves as it is: other areas, and the task items it keeps' {
        $line = @($script:R.Warnings | Where-Object { $_ -like '*also holds settings this run does not manage*' })
        $line | Should -HaveCount 1
        $line[0] | Should -BeExactly "UsaBanner: the GPO 'UsaBanner' also holds settings this run does not manage, left as they are: Computer: Security Settings; User: Folder Redirection; Computer: Scheduled Tasks, item TaskV2 'Someone else'"
        $line[0] | Should -Not -BeLike '*Computer: Registry*'
    }

    It 'keeps the other task item as it was, and has one item of its own, in the place of the old one' {
        $file = Join-Path $script:D.Policies $script:Guid 'Machine' 'Preferences' 'ScheduledTasks' 'ScheduledTasks.xml'
        $items = @(([xml][System.IO.File]::ReadAllText($file)).DocumentElement.ChildNodes | Where-Object NodeType -eq 'Element')
        $items | Should -HaveCount 2
        $items[0].GetAttribute('name') | Should -BeExactly 'UsaBanner sync'
        $items[0].LocalName | Should -Be 'ImmediateTaskV2'
        $items[1].GetAttribute('name') | Should -BeExactly 'Someone else'
        $items[1].GetAttribute('uid') | Should -BeExactly '{0E0E0E0E-1111-2222-3333-444444444444}'
        $items[1].SelectSingleNode('Properties/Task/Actions/Exec/Arguments').InnerText | Should -BeExactly '-File other.ps1'
    }

    It 'switches the computer settings back on, keeps what the other settings registered, and sets the two values, removing the third' {
        $script:Gpo.Attr['flags'] | Should -Be 0
        $script:Gpo.Attr['gPCMachineExtensionNames'] | Should -BeExactly '[{00000000-0000-0000-0000-000000000000}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}][{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}][{AADCED64-746C-4633-A97C-D61349046527}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]'
        @($script:Gpo.Values.Keys | Sort-Object) | Should -Be @('all', 'metaValues')
        $script:Gpo.Values['all'].Value | Should -Be @('UsaBanner/adsys-startup.sh')
        $script:D.Writes | Should -Contain 'remove value 24.04'
        $script:D.Writes | Should -Contain 'set attribute flags'
    }

    It 'steps the version once itself, from where the three value changes left it (3, and one each)' {
        $script:Gpo.Attr['versionNumber'] | Should -Be 7
        Get-IniVersion (Join-Path $script:D.Policies $script:Guid 'GPT.INI') | Should -Be 7
        @($script:D.Writes | Where-Object { $_ -eq 'set attribute versionNumber' }) | Should -HaveCount 1
        $script:R.Lines | Should -Contain "raised the version of the GPO 'UsaBanner' from 6 to 7 (AD and GPT.INI)"
    }

    It 'reads it all back, every check ok' {
        $checks = Get-CheckLine $script:R
        $checks | Should -HaveCount 9
        @($checks | Where-Object { $_ -notlike 'ok   *' }) | Should -BeNullOrEmpty
    }
}

Describe 'Deploy-UsaBannerGPO, a run that changes nothing in a GPO that exists' {
    It 'gives a GPO that holds other settings a note, not a warning, when it changes none of them' {
        $d = New-FakeDomain
        Use-FakeDomain $d
        $parameters = @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu) }
        $null = Invoke-Gpo $parameters
        $gpo = Get-GpoByName $d
        $gpo.Areas = @('Computer: Security Settings')
        $r = Invoke-Gpo $parameters
        @($r.Warnings | Where-Object { $_ -like '*exists already*' -or $_ -like '*also holds*' }) | Should -HaveCount 0
        @($r.Notes | Where-Object { $_ -like "*also holds settings this run does not manage, left as they are: Computer: Security Settings" }) | Should -HaveCount 1
    }
}

Describe 'Deploy-UsaBannerGPO, a GPO that has drifted in one way' {
    BeforeEach {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
        $script:Parameters = @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu) }
        $null = Invoke-Gpo $script:Parameters
        $script:Gpo = Get-GpoByName $script:D
        $script:TasksFile = Join-Path $script:D.Policies $script:Gpo.Guid 'Machine' 'Preferences' 'ScheduledTasks' 'ScheduledTasks.xml'
        $script:GptIni = Join-Path $script:D.Policies $script:Gpo.Guid 'GPT.INI'
        Set-OldTimes $script:D
        $script:D.Writes.Clear()
    }

    It 'sets only the startup values that are gone, and leaves the version to the cmdlets that set them' {
        $script:Gpo.Values.Clear()
        $before = $script:Gpo.Attr['versionNumber']
        $r = Invoke-Gpo $script:Parameters
        $r.Error | Should -BeNullOrEmpty
        @($script:D.Writes) | Should -Be @('set value metaValues', 'set value all')
        # One each from Set-GPRegistryValue, which raises the version itself; the run adds none.
        $script:Gpo.Attr['versionNumber'] | Should -Be ($before + 2)
        Get-IniVersion $script:GptIni | Should -Be ($before + 2)
        [System.IO.File]::GetLastWriteTimeUtc($script:TasksFile).Year | Should -Be 2020
        @(Get-ChangeLine $r) | Should -HaveCount 2
        (Get-CheckLine $r) | Should -HaveCount 9
    }

    It 'registers the Scheduled Tasks extension again when it is gone, steps the version for it, and leaves the task file' {
        $script:Gpo.Attr['gPCMachineExtensionNames'] = '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
        $before = $script:Gpo.Attr['versionNumber']
        $r = Invoke-Gpo $script:Parameters
        $r.Error | Should -BeNullOrEmpty
        @($script:D.Writes) | Should -Be @('set attribute gPCMachineExtensionNames', 'set attribute versionNumber')
        $script:Gpo.Attr['gPCMachineExtensionNames'] | Should -BeLike "*$script:Cse*"
        $script:Gpo.Attr['versionNumber'] | Should -Be ($before + 1)
        Get-IniVersion $script:GptIni | Should -Be ($before + 1)
        [System.IO.File]::GetLastWriteTimeUtc($script:TasksFile).Year | Should -Be 2020
    }

    It 'switches the computer settings back on and does nothing else: the version stays, since clients take a GPO whose computer side comes back as new' {
        $script:Gpo.Attr['flags'] = 2
        $before = $script:Gpo.Attr['versionNumber']
        $r = Invoke-Gpo $script:Parameters
        $r.Error | Should -BeNullOrEmpty
        @($script:D.Writes) | Should -Be @('set attribute flags')
        $script:Gpo.Attr['flags'] | Should -Be 0
        $script:Gpo.Attr['versionNumber'] | Should -Be $before
        $r.Warnings | Should -Contain '  computer settings: disabled -> enabled'
        [System.IO.File]::GetLastWriteTimeUtc($script:TasksFile).Year | Should -Be 2020
    }

    It 'writes the task again when its file was changed by hand, and steps the version for it' {
        [System.IO.File]::WriteAllText($script:TasksFile, ([System.IO.File]::ReadAllText($script:TasksFile) -replace 'PT30M', 'PT5M'))
        Set-OldTimes $script:D
        $before = $script:Gpo.Attr['versionNumber']
        $r = Invoke-Gpo $script:Parameters
        $r.Error | Should -BeNullOrEmpty
        @($script:D.Writes) | Should -Be @('set attribute versionNumber')
        [System.IO.File]::ReadAllText($script:TasksFile) | Should -BeLike '*<ExecutionTimeLimit>PT30M</ExecutionTimeLimit>*'
        [System.IO.File]::GetLastWriteTimeUtc($script:TasksFile).Year | Should -Not -Be 2020
        $script:Gpo.Attr['versionNumber'] | Should -Be ($before + 1)
        $r.Warnings | Should -Contain "  task 'UsaBanner sync' TimeLimit: 'PT5M' -> 'PT30M'"
    }
}

Describe 'Deploy-UsaBannerGPO, an ADSys GPT.INI with no Version' {
    It 'starts the Version at 1, and keeps what else the file holds' {
        $d = New-FakeDomain
        Write-TestFile (Join-Path $d.Ubuntu 'GPT.INI') "[General]`r`nnote=ADSys assets`r`n"
        Use-FakeDomain $d
        $r = Invoke-Gpo @{ Company = 'Contoso' }
        $r.Error | Should -BeNullOrEmpty
        [System.IO.File]::ReadAllText((Join-Path $d.Ubuntu 'GPT.INI')) | Should -BeExactly "[General]`r`nVersion=1`r`nnote=ADSys assets`r`n"
        $r.Lines | Should -Contain "raised the Version in $(Join-Path $d.Ubuntu 'GPT.INI') from 0 to 1: ADSys downloads the Ubuntu folder again"
        (Get-CheckLine $r)[2] | Should -BeExactly 'ok   Ubuntu GPT.INI is at Version 1, at least 1'
    }
}

Describe 'Deploy-UsaBannerGPO, a GPO whose report cannot be read' {
    It 'says so in a note, lists no other settings, and goes on' {
        $d = New-FakeDomain
        Use-FakeDomain $d
        $null = Add-FakeGpo $d 'UsaBanner'
        Mock -ModuleName UsaBanner Get-UsaBannerGpoReportXml { throw 'Access is denied.' }
        $r = Invoke-Gpo @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu) }
        $r.Error | Should -BeNullOrEmpty
        @($r.Notes | Where-Object { $_ -eq "  note: the report of the GPO 'UsaBanner' could not be read (Access is denied.), so other settings it may hold are not listed" }) | Should -HaveCount 1
        @($r.Warnings | Where-Object { $_ -like '*also holds settings*' }) | Should -HaveCount 0
        (Get-CheckLine $r) | Should -HaveCount 9
    }
}

Describe 'Deploy-UsaBannerGPO, links' {
    BeforeEach {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
    }

    It 'enables a disabled link at a -LinkTarget, with a warning, and makes no second link' {
        $guid = Add-FakeGpo $script:D 'UsaBanner'
        $script:D.Links[$script:ServersOu].Add(@{ Guid = $guid; Flags = 1 })
        $r = Invoke-Gpo @{ LinkTarget = @($script:ServersOu) }
        $r.Error | Should -BeNullOrEmpty
        $r.Warnings | Should -Contain "UsaBanner: the link of the GPO 'UsaBanner' at $script:ServersOu is disabled; -LinkTarget names it, so it is enabled."
        $r.Lines | Should -Contain "enabled the link of the GPO 'UsaBanner' at $script:ServersOu"
        $script:D.Links[$script:ServersOu] | Should -HaveCount 1
        $script:D.Links[$script:ServersOu][0].Flags | Should -Be 0
        @($script:D.Writes | Where-Object { $_ -like 'link *' }) | Should -HaveCount 0
        $script:D.Writes | Should -Contain "enable link $script:ServersOu"
        (Get-CheckLine $r)[-1] | Should -BeExactly "ok   linked at $script:ServersOu, enabled"
    }

    It 'links a second -LinkTarget and leaves an enabled link at the first alone' {
        $guid = Add-FakeGpo $script:D 'UsaBanner'
        $script:D.Links[$script:ServersOu].Add(@{ Guid = $guid; Flags = 0 })
        $r = Invoke-Gpo @{ LinkTarget = @($script:ServersOu, $script:LinuxOu) }
        $r.Error | Should -BeNullOrEmpty
        @($script:D.Writes | Where-Object { $_ -like '*link*' }) | Should -Be @("link $script:LinuxOu")
        $script:D.Links[$script:ServersOu] | Should -HaveCount 1
        $script:D.Links[$script:LinuxOu] | Should -HaveCount 1
        @($r.Warnings | Where-Object { $_ -like '*disabled*' }) | Should -HaveCount 0
    }

    It 'with no -LinkTarget and no link, warns that no host applies it, and makes no link, not even at the domain root' {
        $r = Invoke-Gpo @{ Company = 'Contoso' }
        $r.Error | Should -BeNullOrEmpty
        $r.Warnings | Should -Contain "UsaBanner: the GPO 'UsaBanner' is linked nowhere, so no host applies it. Link it with -LinkTarget '<distinguished name>' (several are allowed), or in GPMC."
        foreach ($dn in $script:D.Links.Keys) { $script:D.Links[$dn] | Should -HaveCount 0 }
        @($script:D.Writes | Where-Object { $_ -like '*link*' }) | Should -HaveCount 0
        Should -Invoke New-UsaBannerGpoLink -ModuleName UsaBanner -Times 0 -Exactly
        (Get-CheckLine $r) | Should -HaveCount 8
    }

    It 'with no -LinkTarget, leaves the links it has as they are, and lists them without a warning' {
        $guid = Add-FakeGpo $script:D 'UsaBanner'
        $script:D.Links[$script:LinuxOu].Add(@{ Guid = $guid; Flags = 0 })
        $script:D.Links[$script:RootDn].Add(@{ Guid = $guid; Flags = 1 })
        $r = Invoke-Gpo
        $r.Error | Should -BeNullOrEmpty
        @($r.Warnings | Where-Object { $_ -like '*linked nowhere*' -or $_ -like '*only by disabled links*' }) | Should -HaveCount 0
        $r.Notes | Should -Contain "  links of the GPO 'UsaBanner', left as they are: $script:RootDn (link disabled); $script:LinuxOu"
        @($script:D.Writes | Where-Object { $_ -like '*link*' }) | Should -HaveCount 0
    }

    It 'with no -LinkTarget and only disabled links, warns that no host applies it, and enables none' {
        $guid = Add-FakeGpo $script:D 'UsaBanner'
        $script:D.Links[$script:LinuxOu].Add(@{ Guid = $guid; Flags = 1 })
        $r = Invoke-Gpo
        $r.Warnings | Should -Contain "UsaBanner: the GPO 'UsaBanner' is linked only by disabled links, so no host applies it. Link it with -LinkTarget '<distinguished name>' (several are allowed), or in GPMC."
        $script:D.Links[$script:LinuxOu][0].Flags | Should -Be 1
        @($script:D.Writes | Where-Object { $_ -like '*link*' }) | Should -HaveCount 0
    }
}

Describe 'Deploy-UsaBannerGPO, the policies beside it' {
    BeforeAll {
        $script:TodayTasks = New-TasksFile @((New-TaskItem -Name 'Manatech MOTD sync' -Uid '{0A0A0A0A-1111-2222-3333-444444444444}' -Arguments '-File x.ps1'))
        $script:SshTasks = New-TasksFile @((New-TaskItem -Name 'UsaDeploy-WinSsh' -Uid '{0B0B0B0B-1111-2222-3333-444444444444}' -Arguments '-File y.ps1'))
        $script:Registered = '[{00000000-0000-0000-0000-000000000000}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}][{AADCED64-746C-4633-A97C-D61349046527}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]'
    }

    BeforeEach {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
    }

    It 'warns, naming the GPO and where it is linked, while today''s banner is linked and enabled, and that the two undo each other' {
        $today = Add-FakeGpo $script:D 'Manatech MOTD' -TasksXml $script:TodayTasks -Ext $script:Registered
        $script:D.Links[$script:LinuxOu].Add(@{ Guid = $today; Flags = 0 })
        $script:D.Links[$script:ServersOu].Add(@{ Guid = $today; Flags = 0 })
        $script:D.Links[$script:RootDn].Add(@{ Guid = $today; Flags = 1 })
        $r = Invoke-Gpo @{ LinkTarget = @($script:LinuxOu) }
        $warning = @($r.Warnings | Where-Object { $_ -like "*delivers today's banner*" })
        $warning | Should -HaveCount 1
        $warning[0] | Should -BeLike "UsaBanner: the GPO 'Manatech MOTD' ($today) delivers today's banner (its task is 'Manatech MOTD sync') and is linked, enabled, at $script:ServersOu; $($script:LinuxOu): while it applies to a host, it and this GPO undo each other at each refresh. Take it off those hosts (D29)."
        # The link at the domain root is disabled, so the hosts under it are not reached: it is not in the list above.
    }

    It 'does not warn of today''s banner when its links are disabled or it is linked nowhere' {
        $today = Add-FakeGpo $script:D 'Manatech MOTD' -TasksXml $script:TodayTasks -Ext $script:Registered
        $script:D.Links[$script:RootDn].Add(@{ Guid = $today; Flags = 1 })
        $r = Invoke-Gpo @{ LinkTarget = @($script:LinuxOu) }
        @($r.Warnings | Where-Object { $_ -like "*today's banner*" }) | Should -HaveCount 0
    }

    It 'warns of a Windows server without PowerShell 7 when no GPO of deploy-usawinssh is linked and enabled, though one exists' {
        $ssh = Add-FakeGpo $script:D 'C-W-OpenSSH_Server' -TasksXml $script:SshTasks -Ext $script:Registered
        $script:D.Links[$script:RootDn].Add(@{ Guid = $ssh; Flags = 1 })
        $r = Invoke-Gpo @{ LinkTarget = @($script:LinuxOu) }
        $r.Warnings | Should -Contain "UsaBanner: no GPO that makes the task 'UsaDeploy-WinSsh' is linked and enabled, so Windows servers without PowerShell 7 get no banner: deploy-usawinssh installs it (D21)."
    }

    It 'warns of neither when today''s banner is off the hosts and the GPO of deploy-usawinssh is linked and enabled' {
        $ssh = Add-FakeGpo $script:D 'C-W-OpenSSH_Server' -TasksXml $script:SshTasks -Ext $script:Registered
        $script:D.Links[$script:RootDn].Add(@{ Guid = $ssh; Flags = 0 })
        $today = Add-FakeGpo $script:D 'Manatech MOTD' -TasksXml $script:TodayTasks -Ext $script:Registered
        $r = Invoke-Gpo @{ LinkTarget = @($script:LinuxOu) }
        $r.Error | Should -BeNullOrEmpty
        $r.Warnings | Should -HaveCount 0
    }

    It 'skips a GPO whose ScheduledTasks.xml it cannot read, with a note, and reads the others' {
        $broken = Add-FakeGpo $script:D 'Broken tasks' -TasksXml '<ScheduledTasks><broken' -Ext $script:Registered
        $ssh = Add-FakeGpo $script:D 'C-W-OpenSSH_Server' -TasksXml $script:SshTasks -Ext $script:Registered
        $script:D.Links[$script:RootDn].Add(@{ Guid = $ssh; Flags = 0 })
        $r = Invoke-Gpo @{ LinkTarget = @($script:LinuxOu) }
        $r.Error | Should -BeNullOrEmpty
        @($r.Notes | Where-Object { $_ -like "*the ScheduledTasks.xml of the GPO 'Broken tasks' ($broken) could not be read*skipped*" }) | Should -HaveCount 1
        $r.Warnings | Should -HaveCount 0
    }

    It 'does not count the GPO it makes, nor one with the extension and no tasks file' {
        $bare = Add-FakeGpo $script:D 'No file' -Ext $script:Registered
        $r = Invoke-Gpo @{ LinkTarget = @($script:LinuxOu) }
        $r.Error | Should -BeNullOrEmpty
        $r.Warnings | Should -HaveCount 1
        $r.Warnings[0] | Should -BeLike '*UsaDeploy-WinSsh*'
        $r.Notes | Should -HaveCount 1
    }
}

Describe 'Deploy-UsaBannerGPO -WhatIf' {
    BeforeEach {
        $script:D = New-FakeDomain
        Use-FakeDomain $script:D
    }

    It 'changes nothing in the fake domain: no file, GPO, attribute, value or link, and no folder made' {
        $before = @(Get-DomainState $script:D)
        $r = Invoke-Gpo @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu, $script:LinuxOu); WhatIf = $true }
        $r.Error | Should -BeNullOrEmpty
        @(Get-DomainState $script:D) | Should -Be $before
        $script:D.Gpos.Count | Should -Be 0
        Test-Path -LiteralPath $script:D.Netlogon | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $script:D.Ubuntu 'scripts') | Should -BeFalse
        @($script:D.Writes) | Should -HaveCount 0
        Should -Invoke New-UsaBannerGpoObject -ModuleName UsaBanner -Times 0 -Exactly
        Should -Invoke Set-UsaBannerGpoRegistryValue -ModuleName UsaBanner -Times 0 -Exactly
        Should -Invoke New-UsaBannerGpoLink -ModuleName UsaBanner -Times 0 -Exactly
    }

    It 'returns no lines, since it has made no change and reads nothing back, and shows the ScheduledTasks.xml it would write' {
        $r = Invoke-Gpo @{ Company = 'Contoso'; WhatIf = $true }
        $r.Lines | Should -HaveCount 0
        $shown = @($r.Notes | Where-Object { $_ -like '---- ScheduledTasks.xml this run would write ----*' })
        $shown | Should -HaveCount 1
        $shown[0] | Should -BeLike '*<ImmediateTaskV2 *name="UsaBanner sync"*'
        $shown[0] | Should -BeLike "*-File `"$script:TaskScript`"*"
        $shown[0] | Should -BeLike '*---- end ----'
    }

    It 'still warns of what it would do to a GPO that exists, in the future tense, and writes nothing to it' {
        $guid = Add-FakeGpo $script:D 'UsaBanner' -TasksXml (New-TasksFile @((New-TaskItem -Name 'UsaBanner sync' -Uid '{0F0F0F0F-1111-2222-3333-444444444444}' -Arguments '-File old.ps1'))) -Flags 2 -Version 3
        $before = @(Get-DomainState $script:D)
        $r = Invoke-Gpo @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu); WhatIf = $true }
        $r.Warnings[0] | Should -BeLike "*this run would overwrite these of its settings with the module's:"
        $r.Warnings | Should -Contain '  computer settings: disabled -> enabled'
        @(Get-DomainState $script:D) | Should -Be $before
        $r.Lines | Should -HaveCount 0
    }

    It 'is the same run without -WhatIf that makes the GPO and returns its lines (the positive control for the cases above)' {
        $r = Invoke-Gpo @{ Company = 'Contoso' }
        $r.Error | Should -BeNullOrEmpty
        $script:D.Gpos.Count | Should -Be 1
        $r.Lines.Count | Should -BeGreaterThan 9
    }
}

Describe 'Deploy-UsaBannerGPO, a read-back that fails' {
    It 'throws, and names the check, when an attribute write is ignored: the version in AD is not the one in GPT.INI' {
        $d = New-FakeDomain
        $d.IgnoreWrites = @('versionNumber')
        Use-FakeDomain $d
        $r = Invoke-Gpo @{ Company = 'Contoso'; LinkTarget = @($script:ServersOu) }
        $r.Error | Should -BeLike 'UsaBanner: 1 of 9 checks failed: version in AD (2) = GPT.INI (3)'
        $checks = Get-CheckLine $r
        $checks | Should -HaveCount 9
        @($checks | Where-Object { $_ -like 'FAIL *' }) | Should -Be @('FAIL version in AD (2) = GPT.INI (3)')
        @($checks | Where-Object { $_ -like 'ok   *' }) | Should -HaveCount 8
    }

    It 'names every check that fails, and the files that are wrong in a copy' {
        $d = New-FakeDomain
        $d.IgnoreWrites = @('gPCMachineExtensionNames', 'flags')
        Use-FakeDomain $d
        $r = Invoke-Gpo @{ LinkTarget = @($script:ServersOu) }
        # The throw gives what the extension list held (the Registry group the values registered), beside the check.
        $r.Error | Should -BeLike 'UsaBanner: 1 of 9 checks failed: Scheduled Tasks extension registered (*35378EAC*)'
        $checks = Get-CheckLine $r
        @($checks | Where-Object { $_ -like 'FAIL *' }) | Should -Be @('FAIL Scheduled Tasks extension registered')
    }

    It 'fails a copy that is not the payload: a file the run wrote that has changed since' {
        $d = New-FakeDomain
        Use-FakeDomain $d
        # A write that does not reach the share: the staged package reads back as another file.
        Mock -ModuleName UsaBanner Write-UsaBannerGpoTree {
            foreach ($relative in $Plan.Write) {
                $full = [System.IO.Path]::Combine($Path, $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
                $null = [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($full))
                $bytes = if ($relative -eq 'usabanner.json') { [byte[]](0x7B, 0x7D) } else { [byte[]]$Payload[$relative] }
                [System.IO.File]::WriteAllBytes($full, $bytes)
            }
        }
        $r = Invoke-Gpo @{ Company = 'Contoso' }
        $r.Error | Should -BeLike 'UsaBanner: 2 of 8 checks failed: *usabanner.json differs*'
        @((Get-CheckLine $r) | Where-Object { $_ -like 'FAIL *' }) | Should -HaveCount 2
    }
}

Describe 'Deploy-UsaBannerGPO, its parameters' {
    BeforeAll {
        $script:Command = Get-Command Deploy-UsaBannerGPO
        $script:Flags = InModuleScope UsaBanner { Get-UsaBannerDeployFlagName }
    }

    It 'takes the 19 flags of Deploy-UsaBanner, no more and no fewer: its flag parameters equal the list the configuration builder keeps' {
        $script:Flags | Should -HaveCount 19
        $common = @([System.Management.Automation.PSCmdlet]::CommonParameters) + @([System.Management.Automation.PSCmdlet]::OptionalCommonParameters)
        $own = @('Path', 'Name', 'LinkTarget', 'Domain')
        $flagParameters = @($script:Command.Parameters.Keys | Where-Object { $_ -notin $common -and $_ -notin $own })
        @($flagParameters | Sort-Object) | Should -Be @($script:Flags | Sort-Object)
    }

    # Discovery's variables are gone when tests run, so the count travels as test data.
    It 'finds the 19 flags to compare, else the next test compares nothing' -ForEach @(@{ Found = @($flagCases).Count }) {
        $Found | Should -Be 19
    }

    It 'gives each flag the type and the allowed values Deploy-UsaBanner gives it: <Flag>' -ForEach $flagCases {
        $mine = (Get-Command Deploy-UsaBannerGPO).Parameters[$Flag]
        $theirs = (Get-Command Deploy-UsaBanner).Parameters[$Flag]
        $mine.ParameterType | Should -Be $theirs.ParameterType
        $values = { param($p) @($p.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | ForEach-Object { $_.ValidValues }) }
        (& $values $mine) | Should -Be (& $values $theirs)
        @($mine.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }).Count | Should -Be @($theirs.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }).Count
    }

    It 'takes -Path, -Name (UsaBanner unless said otherwise), -LinkTarget and -Domain, and no -ReplaceOldBanner: the runners always pass it' {
        $script:Command.Parameters.Keys | Should -Contain 'Path'
        $script:Command.Parameters['Name'].ParameterType | Should -Be ([string])
        $script:Command.Parameters['LinkTarget'].ParameterType | Should -Be ([string[]])
        $script:Command.Parameters['Domain'].ParameterType | Should -Be ([string])
        $script:Command.Parameters.Keys | Should -Not -Contain 'ReplaceOldBanner'
        $script:Command.Parameters.Keys | Should -Contain 'WhatIf'
        $script:Command.Parameters.Keys | Should -Contain 'Confirm'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:ModuleRoot 'Public' 'Deploy-UsaBannerGPO.ps1'), [ref]$null, [ref]$null)
        $name = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.ParameterAst] -and $node.Name.VariablePath.UserPath -eq 'Name' }, $true)
        $name.DefaultValue.Value | Should -BeExactly 'UsaBanner'
    }

    It 'names the GPO as -Name says, and finds it again by that name' {
        $d = New-FakeDomain
        Use-FakeDomain $d
        $null = Invoke-Gpo @{ Name = 'UsaBanner (lab)'; Company = 'Contoso' }
        (Get-GpoByName $d 'UsaBanner (lab)') | Should -Not -BeNullOrEmpty
        (Get-GpoByName $d 'UsaBanner') | Should -BeNullOrEmpty
        $r = Invoke-Gpo @{ Name = 'UsaBanner (lab)'; Company = 'Contoso' }
        $r.Error | Should -BeNullOrEmpty
        $d.Gpos.Count | Should -Be 1
    }

    It 'builds the package as Deploy-UsaBanner builds a configuration: the file -Path names, with the flags on top' {
        $d = New-FakeDomain
        Use-FakeDomain $d
        $file = Join-Path $TestDrive 'base.json'
        [System.IO.File]::WriteAllText($file, '{ "company": "Base Co", "role": "From the file", "environment": "LAB" }')
        $null = Invoke-Gpo @{ Path = $file; Environment = 'PROD'; Company = 'Contoso' }
        $package = [System.IO.File]::ReadAllText((Join-Path $d.Netlogon 'usabanner.json')) | ConvertFrom-Json -AsHashtable
        $package['company'] | Should -BeExactly 'Contoso'
        $package['environment'] | Should -BeExactly 'PROD'
        $package['role'] | Should -BeExactly 'From the file'
        $package['update']['mode'] | Should -BeExactly 'off'
    }
}

Describe 'Import-UsaBannerGroupPolicy' {
    It 'loads the GroupPolicy module' {
        Mock -ModuleName UsaBanner Import-Module { }
        InModuleScope UsaBanner { Import-UsaBannerGroupPolicy }
        Should -Invoke Import-Module -ModuleName UsaBanner -Times 1 -Exactly -ParameterFilter { $Name -eq 'GroupPolicy' }
    }

    It 'says where to run the command when the module is not there' {
        Mock -ModuleName UsaBanner Import-Module { throw 'The specified module was not loaded.' }
        { InModuleScope UsaBanner { Import-UsaBannerGroupPolicy } } | Should -Throw '*the GroupPolicy module did not load (The specified module was not loaded.)*domain controller*Group Policy Management tools*'
    }
}

Describe 'Get-UsaBannerGpoPlace' {
    It 'puts the copies and the GPO''s folder on the PDC emulator, and the runner under the domain''s own name' {
        $place = InModuleScope UsaBanner {
            Get-UsaBannerGpoPlace -Domain ([pscustomobject]@{ Name = 'ad.example'; Dn = 'DC=ad,DC=example'; Pdc = 'dc01.ad.example' })
        }
        $place.Netlogon | Should -BeExactly '\\dc01.ad.example\NETLOGON\UsaBanner'
        $place.Ubuntu | Should -BeExactly '\\dc01.ad.example\SYSVOL\ad.example\Ubuntu'
        $place.Policies | Should -BeExactly '\\dc01.ad.example\SYSVOL\ad.example\Policies'
        $place.TaskScript | Should -BeExactly '\\ad.example\NETLOGON\UsaBanner\UsaBanner\windows\Sync-UsaBanner.ps1'
        # The task's script is the file the runner expects: the module folder in a folder that holds the package.
        $place.TaskScript | Should -BeExactly $script:TaskScript
    }
}

Describe 'GpoDeploy.ps1, the way it is built' {
    BeforeAll {
        $script:Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:ModuleRoot 'Private' 'GpoDeploy.ps1'), [ref]$null, [ref]$null)
        $script:Functions = @($script:Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false))
        # Every function that touches the domain, which the tests answer for.
        $script:Adapters = @(
            'Get-UsaBannerGpoModuleRoot', 'Import-UsaBannerGroupPolicy', 'Get-UsaBannerGpoDomain', 'Search-UsaBannerDirectory', 'Find-UsaBannerGpo',
            'Find-UsaBannerGpoWithTasks', 'New-UsaBannerGpoObject', 'Get-UsaBannerGpoAttribute', 'Set-UsaBannerGpoAttribute',
            'Get-UsaBannerGpoRegistryValue', 'Set-UsaBannerGpoRegistryValue', 'Remove-UsaBannerGpoRegistryValue', 'Get-UsaBannerGpoLinkAt',
            'Get-UsaBannerGpoLinkPlace', 'New-UsaBannerGpoLink', 'Enable-UsaBannerGpoLink', 'Get-UsaBannerGpoReportXml'
        )
    }

    It 'calls the GroupPolicy cmdlets, and System.DirectoryServices, only in the functions that answer for the domain' {
        $domainCommands = 'Import-Module', 'New-GPO', 'Get-GPOReport', 'Get-GPRegistryValue', 'Set-GPRegistryValue', 'Remove-GPRegistryValue', 'New-GPLink', 'Set-GPLink', 'Get-GPInheritance', 'Get-GPO'
        $found = foreach ($function in $script:Functions) {
            if ($function.Name -in $script:Adapters) { continue }
            foreach ($command in $function.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                if ($command.GetCommandName() -in $domainCommands) { "$($function.Name) calls $($command.GetCommandName())" }
            }
            if ($function.Extent.Text -match 'System\.DirectoryServices') { "$($function.Name) uses System.DirectoryServices" }
        }
        @($found) | Should -HaveCount 0
        # And the guard sees them where they are (else it checks nothing).
        $in = @($script:Functions | Where-Object { $_.Name -eq 'New-UsaBannerGpoObject' })
        $in | Should -HaveCount 1
        @($in[0].FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'New-GPO' }, $true)) | Should -HaveCount 1
    }

    It 'keeps the module import out of -WhatIf, which Import-Module would report on: the import adapter sets it off first' {
        $import = @($script:Functions | Where-Object { $_.Name -eq 'Import-UsaBannerGroupPolicy' })[0]
        $assigns = @($import.FindAll({ param($node) $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$WhatIfPreference' }, $true))
        $assigns | Should -HaveCount 1
        $assigns[0].Right.Extent.Text | Should -Be '$false'
        $importCall = @($import.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Import-Module' }, $true))
        $importCall | Should -HaveCount 1
        $assigns[0].Extent.StartOffset | Should -BeLessThan $importCall[0].Extent.StartOffset
    }

    It 'has every adapter, so that each can be mocked' {
        foreach ($name in $script:Adapters) { @($script:Functions | Where-Object { $_.Name -eq $name }) | Should -HaveCount 1 -Because $name }
        foreach ($name in 'Get-UsaBannerGpoPlace') { @($script:Functions | Where-Object { $_.Name -eq $name }) | Should -HaveCount 1 -Because $name }
    }

    It 'asks before each write it makes to a share or the domain: each sits in the body of an if that calls ShouldProcess' {
        $steps = 'Invoke-UsaBannerGpoStaging', 'Invoke-UsaBannerGpoSettings', 'Invoke-UsaBannerGpoLinking'
        $adapters = 'New-UsaBannerGpoObject', 'Set-UsaBannerGpoRegistryValue', 'Remove-UsaBannerGpoRegistryValue', 'Set-UsaBannerGpoAttribute', 'New-UsaBannerGpoLink', 'Enable-UsaBannerGpoLink', 'Write-UsaBannerGpoTree'
        $methods = 'WriteAllText', 'WriteAllBytes', 'Delete', 'Move', 'CreateDirectory'
        $found = 0
        $unasked = foreach ($name in $steps) {
            $function = @($script:Functions | Where-Object { $_.Name -eq $name })[0]
            $function.Extent.Text | Should -Match 'SupportsShouldProcess' -Because $name
            $writes = @($function.FindAll({
                        param($node)
                        ($node -is [System.Management.Automation.Language.CommandAst] -and $node.GetCommandName() -in $adapters) -or
                        ($node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $node.Member.Value -in $methods)
                    }, $true))
            $found += $writes.Count
            foreach ($write in $writes) {
                $asked = $false
                for ($parent = $write.Parent; $parent -and -not $asked; $parent = $parent.Parent) {
                    if ($parent -isnot [System.Management.Automation.Language.IfStatementAst]) { continue }
                    foreach ($clause in $parent.Clauses) {
                        if ($clause.Item1.Extent.Text -match 'ShouldProcess' -and $clause.Item2.Extent.StartOffset -le $write.Extent.StartOffset -and $write.Extent.EndOffset -le $clause.Item2.Extent.EndOffset) { $asked = $true }
                    }
                }
                if (-not $asked) { "${name}: $($write.Extent.Text)" }
            }
        }
        @($unasked) | Should -HaveCount 0
        # And the guard finds the writes where they are (else it checks nothing).
        $found | Should -BeGreaterOrEqual 13
    }
}
