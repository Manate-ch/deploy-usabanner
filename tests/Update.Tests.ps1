# The update channel (UsaBanner/Private/Update.ps1, docs/DECISIONS.md D14): the job a deploy
# installs where the configuration turns it on, what it does with a release, the release that
# build/New-UsaBannerRelease.ps1 builds, and Get-UsaBanner's check of it. Releases are built
# from copies of the module with the version set; downloads come from their folder, never the
# network; the new version's deploy is stood in for, as the fake hosts stand in for the rest.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $moduleRoot = Join-Path $repoRoot 'UsaBanner'
    Import-Module (Join-Path $moduleRoot 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'FakeHosts.ps1')
    $script:Build = Join-Path $repoRoot 'build' 'New-UsaBannerRelease.ps1'
    $script:Source = 'https://releases.example.com/usabanner'
    $script:Installed = (Import-PowerShellDataFile -LiteralPath (Join-Path $moduleRoot 'UsaBanner.psd1')).ModuleVersion
    # A release newer than the module, and another version again, both from its manifest: a
    # version bump leaves the tests below true.
    $installedVersion = [version]$script:Installed
    $script:Newer = '{0}.{1}.0' -f $installedVersion.Major, ($installedVersion.Minor + 1)
    $script:Other = '{0}.{1}.0' -f $installedVersion.Major, ($installedVersion.Minor + 2)

    function New-Release {
        # In:  the version the archive's name gives, and the one its manifest says
        # Out: the folder of a release built by build/New-UsaBannerRelease.ps1, from a copy of the
        #      module with that manifest version: UsaBanner-<version>.zip and SHA256SUMS
        param([string]$Version, [string]$ManifestVersion = $Version)
        $work = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $null = New-Item -ItemType Directory -Path (Join-Path $work 'src') -Force
        Copy-Item -LiteralPath $moduleRoot -Destination (Join-Path $work 'src') -Recurse
        $manifest = Join-Path $work 'src' 'UsaBanner' 'UsaBanner.psd1'
        $text = [System.IO.File]::ReadAllText($manifest) -replace "(?m)^(\s*ModuleVersion\s*=\s*)'[^']*'", ('${1}' + "'$ManifestVersion'")
        [System.IO.File]::WriteAllText($manifest, $text)
        $out = Join-Path $work 'release'
        $null = & $Build -OutDir $out -ModulePath (Join-Path $work 'src' 'UsaBanner')
        if ($Version -ne $ManifestVersion) {
            # The archive named for one version and holding another, with SHA256SUMS to match.
            $name = "UsaBanner-$Version.zip"
            Move-Item -LiteralPath (Join-Path $out "UsaBanner-$ManifestVersion.zip") -Destination (Join-Path $out $name)
            $sha = (Get-FileHash -LiteralPath (Join-Path $out $name) -Algorithm SHA256).Hash.ToLowerInvariant()
            [System.IO.File]::WriteAllText((Join-Path $out 'SHA256SUMS'), "$sha  $name`n")
        }
        $out
    }

    function Use-Release {
        # In:  a release's folder (New-Release)
        # Out: nothing; the update job downloads from that folder, and each address it asked
        #      for is in $global:UsaDownloads
        param([string]$Folder)
        $global:UsaRelease = $Folder
        $global:UsaDownloads = [System.Collections.Generic.List[string]]::new()
        Mock -ModuleName UsaBanner Invoke-UsaBannerDownload {
            $global:UsaDownloads.Add($Uri)
            $file = Join-Path $global:UsaRelease $Uri.Substring($Uri.LastIndexOf('/') + 1)
            if (-not (Test-Path -LiteralPath $file)) { throw "404: $Uri" }
            Copy-Item -LiteralPath $file -Destination $OutFile
        }
    }

    function Get-UpdateState {
        # Out: the update job's update.json, as a hashtable
        param([string]$Folder)
        [System.IO.File]::ReadAllText((Join-Path $Folder 'update.json')) | ConvertFrom-Json -AsHashtable
    }

    function Get-Check {
        # In:  Get-UsaBanner's answer, and a check's name
        # Out: that check
        param($Status, [string]$Name)
        @($Status.Checks | Where-Object { $_.Check -eq $Name })[0]
    }
}

AfterAll {
    Remove-Variable -Name UsaDeployCalls, UsaDeployAnswers, UsaDeployUnits, UsaDeployRoot, UsaRelease, UsaDownloads -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name UsaWinRoot, UsaWinCalls, UsaWinAnswers, UsaWinNotice, UsaWinShell, UsaWinTasks, UsaWinAcl -Scope Global -ErrorAction SilentlyContinue
    Remove-Module UsaBanner -ErrorAction SilentlyContinue
}

Describe 'a release' {
    It 'is an archive named for the module''s version, the module at its root, and a SHA256SUMS that sha256sum checks' -Skip:$IsWindows {
        $out = Join-Path $TestDrive 'dist'
        $written = @(& $Build -OutDir $out)
        $written | Should -Be @((Join-Path $out "UsaBanner-$Installed.zip"), (Join-Path $out 'SHA256SUMS'))
        Push-Location -LiteralPath $out
        try { $check = @(& sha256sum --check SHA256SUMS 2>&1) }
        finally { Pop-Location }
        $check | Should -Be @("UsaBanner-${Installed}.zip: OK")
        Add-Type -AssemblyName System.IO.Compression.ZipFile
        $archive = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $out "UsaBanner-$Installed.zip"))
        try { $entries = @($archive.Entries | ForEach-Object { $_.FullName }) }
        finally { $archive.Dispose() }
        $entries | Should -Contain 'UsaBanner/UsaBanner.psd1'
        $entries | Should -Contain 'UsaBanner/linux/bootstrap.ps1'
        @($entries | Where-Object { $_ -notlike 'UsaBanner/*' }) | Should -BeNullOrEmpty
    }

    It 'is not written over: a release does not change under the same name' {
        $out = Join-Path $TestDrive 'twice'
        $null = & $Build -OutDir $out
        { & $Build -OutDir $out } | Should -Throw '*is there already, and a release does not change under the same name*'
    }

    It 'is refused from a module folder that is not the files its manifest lists, naming each, and nothing is written (D32)' {
        # A file left in the folder would ship in the archive, as a production domain's publish staged one (2026-10-28).
        $work = Join-Path $TestDrive 'stray'
        $null = New-Item -ItemType Directory -Path $work -Force
        Copy-Item -LiteralPath $moduleRoot -Destination $work -Recurse
        $copy = Join-Path $work 'UsaBanner'
        [System.IO.File]::WriteAllText((Join-Path $copy 'usabanner-contoso.json'), '{}')
        Remove-Item -LiteralPath (Join-Path $copy 'NOTICE')
        $out = Join-Path $TestDrive 'stray-dist'
        { & $Build -OutDir $out -ModulePath $copy } | Should -Throw "*$copy is not the module its manifest lists (FileList): not listed: usabanner-contoso.json; missing: NOTICE.*"
        Test-Path -LiteralPath $out | Should -BeFalse
    }
}

Describe 'reading a release' {
    It 'reads SHA256SUMS as sha256sum writes it: text or binary, in either case, passing over the rest' {
        $a = 'A' * 64
        $b = 'b' * 64
        $sums = InModuleScope UsaBanner -Parameters @{ Text = "$a  UsaBanner-0.2.0.zip`r`n$b *UsaBanner-0.1.0.zip`nnot a line`n" } { param($Text) Read-UsaBannerReleaseSums -Text $Text }
        @($sums.Keys) | Should -Be @('UsaBanner-0.2.0.zip', 'UsaBanner-0.1.0.zip')
        $sums['UsaBanner-0.2.0.zip'] | Should -BeExactly ('a' * 64)
    }

    It 'takes the newest archive it names, and only a name that is a version and nothing more' {
        $sums = [ordered]@{ 'UsaBanner-0.2.0.zip' = 'a'; 'UsaBanner-0.10.0.zip' = 'b'; '../UsaBanner-9.0.0.zip' = 'c'; 'usabanner-8.0.0.zip' = 'd'; 'UsaBanner-7.0.0.zip.sig' = 'e' }
        $archive = InModuleScope UsaBanner -Parameters @{ Sums = $sums } { param($Sums) Select-UsaBannerReleaseArchive -Sums $Sums }
        $archive.Name | Should -BeExactly 'UsaBanner-0.10.0.zip'
        $archive.Version | Should -Be ([version]'0.10.0')
    }

    It 'names the releases page of <Case> in its notice' -ForEach @(
        @{ Case = 'a GitLab project'; Source = 'https://git.example.com/contoso/usabanner/-/releases/permalink/latest/downloads'; Page = 'https://git.example.com/contoso/usabanner/-/releases' }
        @{ Case = 'a GitHub repository'; Source = 'https://forge.example.com/contoso/usabanner/releases/latest/download'; Page = 'https://forge.example.com/contoso/usabanner/releases' }
        @{ Case = 'any other source'; Source = 'https://releases.example.com/usabanner'; Page = 'https://releases.example.com/usabanner' }
    ) {
        InModuleScope UsaBanner -Parameters @{ Source = $Source } { param($Source) Get-UsaBannerUpdatePage -Source $Source } | Should -BeExactly $Page
    }

    It 'downloads over https only' {
        $file = Join-Path $TestDrive 'never'
        { InModuleScope UsaBanner -Parameters @{ File = $file } { param($File) Invoke-UsaBannerDownload -Uri 'http://releases.example.com/usabanner/SHA256SUMS' -OutFile $File } } |
            Should -Throw '*is not an https address: the update channel downloads over https only*'
        $file | Should -Not -Exist
    }
}

Describe 'the update channel on Ubuntu' -Skip:$IsWindows {
    BeforeEach {
        Use-LinuxHost -Root (New-StockHost)
        $script:State = Join-Path $global:UsaDeployRoot 'var/lib/usabanner'
        $script:Modules = Join-Path $global:UsaDeployRoot 'usr/local/share/powershell/Modules/UsaBanner'
    }

    It 'is off unless a flag turns it on: no job, and the job looks for nothing' {
        $null = Deploy-UsaBanner -Company Contoso
        Join-Path $global:UsaDeployRoot 'etc/systemd/system/usabanner-update.timer' | Should -Not -Exist
        Use-Release (New-Release -Version $Newer)
        InModuleScope UsaBanner { Update-UsaBannerRelease } | Should -BeExactly 'the update channel is off'
        $global:UsaDownloads | Should -BeNullOrEmpty
        (Get-Check (Get-UsaBanner) 'update channel').Detail | Should -BeExactly 'off: no release is looked for'
    }

    It 'says, where a deploy turns on install, that the job runs as root what the source holds; and not for notify' {
        $null = Deploy-UsaBanner -Company Contoso -Update install -UpdateSource $Source -WarningVariable warned -WarningAction SilentlyContinue
        @($warned | ForEach-Object { $_.Message } | Where-Object { $_ -like '*update channel installs*' }) | Should -Be @(
            "UsaBanner: the update channel installs new releases from $Source by itself. The update job runs as root (SYSTEM) on this host, once a day: anyone who can change the releases there can change what runs here. The code is provided as is, without warranty; its authors are not liable for any damage it causes. -Update notify only says when a release is out.")
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source -WarningVariable quiet -WarningAction SilentlyContinue
        @($quiet | ForEach-Object { $_.Message } | Where-Object { $_ -like '*update channel installs*' }) | Should -BeNullOrEmpty
    }

    It 'installs the update job where a flag turns it on, and takes it away where a flag turns it off' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        $units = InModuleScope UsaBanner { Get-UsaBannerUpdateUnits }
        foreach ($unit in $units.Keys) { [System.IO.File]::ReadAllText((Join-Path $global:UsaDeployRoot "etc/systemd/system/$unit")) | Should -BeExactly $units[$unit] }
        Get-Calls -Changes | Should -Contain 'systemctl enable --now usabanner-update.timer'
        $global:UsaDeployCalls.Clear()
        $null = Deploy-UsaBanner -Company Contoso -Update off
        Get-Calls -Changes | Should -Contain 'systemctl disable --now usabanner-update.timer'
        foreach ($unit in $units.Keys) { Join-Path $global:UsaDeployRoot "etc/systemd/system/$unit" | Should -Not -Exist }
    }

    It 'writes units systemd-analyze verify accepts: the update job runs update.sh, once a day' -Skip:(-not (Get-Command systemd-analyze -ErrorAction SilentlyContinue)) {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        $units = Join-Path $global:UsaDeployRoot 'etc/systemd/system'
        $out = & systemd-analyze verify (Join-Path $units 'usabanner-update.service') (Join-Path $units 'usabanner-update.timer') 2>&1 | Out-String
        "$out`nexit=$LASTEXITCODE" | Should -Match 'exit=0$'
        [System.IO.File]::ReadAllText((Join-Path $units 'usabanner-update.timer')) | Should -Match '(?m)^OnUnitActiveSec=1d$'
        [System.IO.File]::ReadAllText((Join-Path $units 'usabanner-update.service')) | Should -Match '(?m)^ExecStart=/bin/sh /usr/local/share/usabanner/update\.sh$'
        $out = & sh -n (Join-Path $moduleRoot 'linux' 'update.sh') 2>&1 | Out-String
        "$out`nexit=$LASTEXITCODE" | Should -Match 'exit=0$'
    }

    It 'goes with Remove-UsaBanner, which leaves the host as it was before the deploy' {
        $before = Get-HostState $global:UsaDeployRoot
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        Use-Release (New-Release -Version $Newer)
        $null = InModuleScope UsaBanner { Update-UsaBannerRelease }
        $global:UsaDeployCalls.Clear()
        $null = Remove-UsaBanner
        Get-Calls -Changes | Should -Contain 'systemctl disable --now usabanner-update.timer'
        Get-HostState $global:UsaDeployRoot | Should -Be $before
    }

    It 'notify: says nothing where the release is not newer than the module' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        Use-Release (New-Release -Version $Installed)
        InModuleScope UsaBanner { Update-UsaBannerRelease } | Should -BeExactly "UsaBanner $Installed is the newest release"
        Join-Path $State 'notice' | Should -Not -Exist
        $state = Get-UpdateState $State
        $state['latest'] | Should -BeExactly $Installed
        $state['error'] | Should -BeExactly ''
        $global:UsaDownloads | Should -Be @("$Source/SHA256SUMS")
        Join-Path $State 'update' | Should -Not -Exist
    }

    It 'notify: has the banner after login say a newer release is out, naming the releases page, and downloads nothing more' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        Use-Release (New-Release -Version $Newer)
        InModuleScope UsaBanner { Update-UsaBannerRelease } | Should -BeExactly "UsaBanner $Newer is out, and this host has ${Installed}: the banner after login says so"
        [System.IO.File]::ReadAllText((Join-Path $State 'notice')) | Should -BeExactly "This banner has an update available. See $Source for more info!`n"
        $global:UsaDownloads | Should -Be @("$Source/SHA256SUMS")
        Join-Path $Modules $Installed | Should -Exist
        (Get-Check (Get-UsaBanner) 'update channel').Detail | Should -BeExactly "notify, from ${Source}; UsaBanner $Newer is out, and this host has ${Installed}: the banner after login says so"
    }

    It 'notify: the collector the deploy installed gives the notice the job wrote, for the banner at login' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        Use-Release (New-Release -Version $Newer)
        $null = InModuleScope UsaBanner { Update-UsaBannerRelease }
        $collector = Join-Path $global:UsaDeployRoot 'usr/local/share/usabanner/facts.sh'
        $records = @(& env -i 'PATH=/usr/bin:/bin' "USABANNER_ROOT=$global:UsaDeployRoot" 'USABANNER_SERVICES=' sh $collector)
        @($records | Where-Object { $_.StartsWith("notice`t") }) | Should -BeExactly @("notice`tThis banner has an update available. See $Source for more info!")
    }

    It 'takes the notice away with the job where a flag turns the channel off: nothing else would' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        Use-Release (New-Release -Version $Newer)
        $null = InModuleScope UsaBanner { Update-UsaBannerRelease }
        Join-Path $State 'notice' | Should -Exist
        $lines = @(Deploy-UsaBanner -Company Contoso -Update off)
        $lines | Should -Contain "deleted /var/lib/usabanner/notice: the update job's notice"
        Join-Path $State 'notice' | Should -Not -Exist
    }

    It 'install: checks the archive, unpacks it, has the new version deploy this host''s configuration, and takes the old version away' {
        $null = Deploy-UsaBanner -Company Contoso -Update install -UpdateSource $Source -WarningAction SilentlyContinue
        Use-Release (New-Release -Version $Newer)
        Mock -ModuleName UsaBanner Invoke-UsaBannerNative -ParameterFilter { $ArgumentList -contains '-File' } {
            $global:UsaNewDeploy = @($ArgumentList)
            # As the new version's deploy does: it copies itself where every user's PowerShell finds it.
            Copy-Item -LiteralPath (Split-Path (Split-Path $ArgumentList[3])) -Destination (Join-Path $global:UsaDeployRoot "usr/local/share/powershell/Modules/UsaBanner/$Newer") -Recurse
            @{ ExitCode = 0; Output = @() }
        }
        InModuleScope UsaBanner { Update-UsaBannerRelease } | Should -BeExactly "installed UsaBanner $Newer, which deployed this host's configuration in place of UsaBanner $Installed"
        $global:UsaNewDeploy | Should -Be @('-NoProfile', '-NonInteractive', '-File', (Join-Path $State 'update/unpacked/UsaBanner/linux/bootstrap.ps1'), '-Path', (Join-Path $global:UsaDeployRoot 'etc/usabanner/usabanner.json'))
        Join-Path $Modules $Newer | Should -Exist
        Join-Path $Modules $Installed | Should -Not -Exist
        (Get-UpdateState $State)['installed'] | Should -BeExactly $Newer
        Join-Path $State 'notice' | Should -Not -Exist
        Join-Path $State 'update' | Should -Not -Exist
        $global:UsaDownloads | Should -Be @("$Source/SHA256SUMS", "$Source/UsaBanner-$Newer.zip")
    }

    It 'install: refuses an archive SHA256SUMS does not match, and installs nothing' {
        $null = Deploy-UsaBanner -Company Contoso -Update install -UpdateSource $Source -WarningAction SilentlyContinue
        $release = New-Release -Version $Newer
        [System.IO.File]::AppendAllText((Join-Path $release "UsaBanner-$Newer.zip"), 'x')
        Use-Release $release
        { InModuleScope UsaBanner { Update-UsaBannerRelease } } | Should -Throw "*UsaBanner-$Newer.zip does not match its line in SHA256SUMS*so nothing is installed*"
        @(Get-Calls | Where-Object { $_ -like '* -File *' }) | Should -BeNullOrEmpty
        @(Get-ChildItem -LiteralPath $Modules -Name) | Should -Be @($Installed)
        (Get-UpdateState $State)['error'] | Should -BeLike '*does not match its line in SHA256SUMS*'
        Join-Path $State 'update' | Should -Not -Exist
    }

    It 'install: refuses an archive whose module is another version than its name says' {
        $null = Deploy-UsaBanner -Company Contoso -Update install -UpdateSource $Source -WarningAction SilentlyContinue
        Use-Release (New-Release -Version $Newer -ManifestVersion $Other)
        { InModuleScope UsaBanner { Update-UsaBannerRelease } } | Should -Throw "*UsaBanner-$Newer.zip holds UsaBanner $Other, not $Newer, so nothing is installed*"
        @(Get-ChildItem -LiteralPath $Modules -Name) | Should -Be @($Installed)
    }

    It 'install: keeps the old version when the new one''s deploy fails, and puts back what that deploy changed' {
        $null = Deploy-UsaBanner -Company Contoso -Update install -UpdateSource $Source -WarningAction SilentlyContinue
        Use-Release (New-Release -Version $Newer)
        Mock -ModuleName UsaBanner Invoke-UsaBannerNative -ParameterFilter { $ArgumentList -contains '-File' } {
            # A deploy cut short: half of the new module in place, and a script of the renderer changed.
            $null = New-Item -ItemType Directory -Path (Join-Path $global:UsaDeployRoot "usr/local/share/powershell/Modules/UsaBanner/$Newer") -Force
            [System.IO.File]::WriteAllText((Join-Path $global:UsaDeployRoot 'usr/local/share/usabanner/facts.sh'), "half`n")
            @{ ExitCode = 1; Output = @('the art broke') }
        }
        { InModuleScope UsaBanner { Update-UsaBannerRelease } } | Should -Throw "*UsaBanner ${Newer}'s deploy failed (exit code 1), so this host keeps UsaBanner ${Installed}: the art broke*"
        @(Get-ChildItem -LiteralPath $Modules -Name) | Should -Be @($Installed)
        (Get-FileHash -LiteralPath (Join-Path $global:UsaDeployRoot 'usr/local/share/usabanner/facts.sh')).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $moduleRoot 'linux' 'facts.sh')).Hash
        $check = Get-Check (Get-UsaBanner) 'update channel'
        $check.State | Should -BeExactly 'stale'
        $check.Detail | Should -BeLike "the last look, at *Z, failed: UsaBanner: UsaBanner ${Newer}'s deploy failed*"
    }

    It 'stops at a SHA256SUMS that names no archive' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        $release = Join-Path $TestDrive 'empty-release'
        $null = New-Item -ItemType Directory -Path $release -Force
        [System.IO.File]::WriteAllText((Join-Path $release 'SHA256SUMS'), "$('0' * 64)  README.md`n")
        Use-Release $release
        { InModuleScope UsaBanner { Update-UsaBannerRelease } } | Should -Throw "*$Source/SHA256SUMS names no UsaBanner-<version>.zip*"
    }

    It 'has Get-UsaBanner find the update job''s units missing' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        [System.IO.File]::Delete((Join-Path $global:UsaDeployRoot 'etc/systemd/system/usabanner-update.timer'))
        $check = Get-Check (Get-UsaBanner) 'update channel'
        $check.State | Should -BeExactly 'missing'
        $check.Detail | Should -BeLike '/etc/systemd/system/usabanner-update.timer is missing*'
    }
}

Describe 'the update channel on Windows Server' {
    BeforeEach {
        Use-WindowsHost (New-WindowsHost)
        $script:Data = Join-Path $global:UsaWinRoot 'ProgramData/UsagiTools/Banner'
    }

    It 'registers the update task where a flag turns it on, and unregisters it where a flag turns it off' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        $task = $global:UsaWinTasks['UsaBanner update']
        $task.Arguments | Should -BeExactly '-NoProfile -NonInteractive -Command "& (Import-Module UsaBanner -PassThru) { Update-UsaBannerRelease }"'
        $task.Schedule | Should -BeExactly 'daily'
        $null = Deploy-UsaBanner -Company Contoso -Update off
        $global:UsaWinCalls | Should -Contain 'task unregistered: UsaBanner update'
        @($global:UsaWinTasks.Keys) | Should -Be @('UsaBanner sample')
    }

    It 'notify: writes the notice into the banner''s own folder' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        Use-Release (New-Release -Version $Newer)
        $null = InModuleScope UsaBanner { Update-UsaBannerRelease }
        [System.IO.File]::ReadAllText((Join-Path $Data 'notice')) | Should -BeExactly "This banner has an update available. See $Source for more info!`n"
        (Get-Check (Get-UsaBanner) 'update channel').State | Should -BeExactly 'ok'
    }

    It 'notify: the banner after login reads the notice the job wrote' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        Use-Release (New-Release -Version $Newer)
        $null = InModuleScope UsaBanner { Update-UsaBannerRelease }
        InModuleScope UsaBanner -Parameters @{ Path = (Join-Path $Data 'notice') } { param($Path) @(Read-UsaBannerNotice -Path $Path) } | Should -BeExactly @("This banner has an update available. See $Source for more info!")
    }

    It 'takes the notice away with the task where a flag turns the channel off: nothing else would' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        Use-Release (New-Release -Version $Newer)
        $null = InModuleScope UsaBanner { Update-UsaBannerRelease }
        Join-Path $Data 'notice' | Should -Exist
        $lines = @(Deploy-UsaBanner -Company Contoso -Update off)
        $lines | Should -Contain "deleted $(Join-Path $Data 'notice'): the update job's notice"
        Join-Path $Data 'notice' | Should -Not -Exist
    }

    It 'goes with Remove-UsaBanner: both tasks unregistered' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        $null = Remove-UsaBanner
        $global:UsaWinTasks.Count | Should -Be 0
        $global:UsaWinCalls | Should -Contain 'task unregistered: UsaBanner update'
    }

    It 'has Get-UsaBanner find the update task missing' {
        $null = Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource $Source
        $global:UsaWinTasks.Remove('UsaBanner update')
        $check = Get-Check (Get-UsaBanner) 'update channel'
        $check.State | Should -BeExactly 'missing'
        $check.Detail | Should -BeExactly 'there is no task \UsagiTools\UsaBanner update'
    }
}
