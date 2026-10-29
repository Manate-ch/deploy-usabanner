# PowerShell 7 for a hand-off that finds none (UsaBanner/Bootstrap/PwshInstall.ps1, D18): the
# newest 7.6 MSI GitHub lists, checked by its release's SHA-256 and Microsoft's signature, then
# installed by msiexec, asking first. The tests stand in for GitHub, the signature check and
# msiexec; Windows PowerShell 5.1 and a real install are the lab's.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $manifest = Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1'
    Import-Module $manifest -Force

    function New-TestRelease {
        # In:  a tag, the names of its files, and whether it is a pre-release or a draft
        # Out: a release as GitHub's API lists it
        # Why: each test names only the releases it needs
        param([string]$Tag, [string[]]$Files, [switch]$Prerelease, [switch]$Draft, [string]$Root = 'https://github.com/PowerShell/PowerShell/releases/download/')
        [pscustomobject]@{
            tag_name   = $Tag
            prerelease = [bool]$Prerelease
            draft      = [bool]$Draft
            assets     = @(foreach ($f in $Files) { [pscustomobject]@{ name = $f; browser_download_url = "$Root$Tag/$f" } })
        }
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'Get-UsaBannerPwshRelease' {
    BeforeAll {
        $releases = @(
            New-TestRelease 'v7.7.0' 'PowerShell-7.7.0-win-x64.msix', 'PowerShell-7.7.0-win-x64.zip', 'hashes.sha256'
            New-TestRelease 'v7.6.12' 'PowerShell-7.6.12-win-x64.msi', 'hashes.sha256' -Draft
            New-TestRelease 'v7.6.11' 'PowerShell-7.6.11-win-x64.msi', 'hashes.sha256' -Prerelease
            New-TestRelease 'v7.6.10' 'PowerShell-7.6.10-win-x64.msi', 'PowerShell-7.6.10-win-x64.msix', 'hashes.sha256'
            New-TestRelease 'v7.6.9' 'PowerShell-7.6.9-win-x64.msi', 'PowerShell-7.6.9-win-arm64.msi', 'hashes.sha256'
            New-TestRelease 'v7.5.4' 'PowerShell-7.5.4-win-x64.msi', 'PowerShell-7.5.4-win-arm64.msi', 'hashes.sha256'
        )
    }

    It 'takes the newest 7.6 that has an MSI, by number (7.6.10 after 7.6.9), and never 7.7 (no MSI), a pre-release or a draft' {
        $r = InModuleScope UsaBanner -Parameters @{ Releases = $releases } { param($Releases) Get-UsaBannerPwshRelease -Releases $Releases -Architecture 'AMD64' }
        $r.Version | Should -Be ([version]'7.6.10')
        $r.Name | Should -BeExactly 'PowerShell-7.6.10-win-x64.msi'
        $r.Url | Should -BeExactly 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.10/PowerShell-7.6.10-win-x64.msi'
        $r.HashesUrl | Should -BeExactly 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.10/hashes.sha256'
    }

    It 'takes the arm64 MSI on an ARM64 machine, from the newest 7.6 release that has one' {
        $r = InModuleScope UsaBanner -Parameters @{ Releases = $releases } { param($Releases) Get-UsaBannerPwshRelease -Releases $Releases -Architecture 'ARM64' }
        $r.Name | Should -BeExactly 'PowerShell-7.6.9-win-arm64.msi'
    }

    It 'reads a 32-bit PowerShell on 64-bit Windows as x64' {
        $saved = $env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432
        try {
            $env:PROCESSOR_ARCHITECTURE = 'x86'
            $env:PROCESSOR_ARCHITEW6432 = 'AMD64'
            $r = InModuleScope UsaBanner -Parameters @{ Releases = $releases } { param($Releases) Get-UsaBannerPwshRelease -Releases $Releases }
            $r.Name | Should -BeExactly 'PowerShell-7.6.10-win-x64.msi'
        }
        finally { $env:PROCESSOR_ARCHITECTURE, $env:PROCESSOR_ARCHITEW6432 = $saved }
    }

    It 'refuses an architecture PowerShell publishes no MSI for' {
        { InModuleScope UsaBanner -Parameters @{ Releases = $releases } { param($Releases) Get-UsaBannerPwshRelease -Releases $Releases -Architecture 'x86' } } |
            Should -Throw "*PowerShell publishes no MSI for this machine's architecture, x86.*"
    }

    It 'refuses a download that is not one of the PowerShell project''s own' {
        $elsewhere = @(New-TestRelease 'v7.6.10' 'PowerShell-7.6.10-win-x64.msi', 'hashes.sha256' -Root 'https://example.com/mirror/')
        { InModuleScope UsaBanner -Parameters @{ Releases = $elsewhere } { param($Releases) Get-UsaBannerPwshRelease -Releases $Releases -Architecture 'AMD64' } } |
            Should -Throw "*GitHub listed https://example.com/mirror/v7.6.10/PowerShell-7.6.10-win-x64.msi for PowerShell 7.6.10, which is not one of the PowerShell project's release downloads.*"
    }

    It 'says so when no 7.6 release has an MSI for the machine' {
        $none = @(New-TestRelease 'v7.7.0' 'PowerShell-7.7.0-win-x64.msix', 'hashes.sha256')
        { InModuleScope UsaBanner -Parameters @{ Releases = $none } { param($Releases) Get-UsaBannerPwshRelease -Releases $Releases -Architecture 'AMD64' } } |
            Should -Throw '*GitHub lists no PowerShell 7.6 release with an MSI for x64.*'
    }

    It 'asks GitHub''s API for the list, as basic parsing' {
        Mock -ModuleName UsaBanner Invoke-RestMethod { $global:UsaPwshTestReleases }
        $global:UsaPwshTestReleases = $releases
        try {
            $r = InModuleScope UsaBanner { Get-UsaBannerPwshRelease -Architecture 'AMD64' }
            $r.Version | Should -Be ([version]'7.6.10')
            Should -Invoke -ModuleName UsaBanner Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=100' -and $UseBasicParsing
            }
        }
        finally { Remove-Variable -Name UsaPwshTestReleases -Scope Global -ErrorAction SilentlyContinue }
    }

    It 'says so when GitHub''s list cannot be read' {
        Mock -ModuleName UsaBanner Invoke-RestMethod { throw 'API rate limit exceeded' }
        { InModuleScope UsaBanner { Get-UsaBannerPwshRelease -Architecture 'AMD64' } } |
            Should -Throw "*GitHub's list of PowerShell releases could not be read (API rate limit exceeded).*"
    }
}

Describe 'Get-UsaBannerReleaseHash' {
    It 'reads the hash on the line that names the file exactly: <Case>' -ForEach @(
        @{ Case = 'hash first, binary mode'; Lines = @("$('ab' * 32) *PowerShell-7.6.10-win-x64.msix", "$('cd' * 32) *PowerShell-7.6.10-win-x64.msi") }
        @{ Case = 'hash first, two spaces'; Lines = @("$('cd' * 32)  PowerShell-7.6.10-win-x64.msi", "$('ab' * 32)  PowerShell-7.6.10-win-x64.msix") }
        @{ Case = 'name first'; Lines = @("PowerShell-7.6.10-win-x64.msix $('ab' * 32)", "PowerShell-7.6.10-win-x64.msi $('cd' * 32)") }
    ) {
        $file = Join-Path $TestDrive 'hashes.sha256'
        [System.IO.File]::WriteAllLines($file, [string[]]$Lines)
        InModuleScope UsaBanner -Parameters @{ File = $file } { param($File) Get-UsaBannerReleaseHash -Path $File -Name 'PowerShell-7.6.10-win-x64.msi' } |
            Should -BeExactly ('CD' * 32)
    }

    It 'says so when the release lists no hash for the file' {
        $file = Join-Path $TestDrive 'hashes.sha256'
        [System.IO.File]::WriteAllLines($file, [string[]]@("$('ab' * 32) *PowerShell-7.6.10-win-x64.msix"))
        { InModuleScope UsaBanner -Parameters @{ File = $file } { param($File) Get-UsaBannerReleaseHash -Path $File -Name 'PowerShell-7.6.10-win-x64.msi' } } |
            Should -Throw "*the release's hashes.sha256 lists no SHA-256 for PowerShell-7.6.10-win-x64.msi.*"
    }
}

Describe 'Install-UsaBannerPwsh' {
    BeforeAll {
        # The MSI that "GitHub" serves, and the SHA-256 its hashes.sha256 lists.
        $global:UsaPwshTestMsi = [byte[]](1..200)
        $sample = Join-Path $TestDrive 'sample.msi'
        [System.IO.File]::WriteAllBytes($sample, $global:UsaPwshTestMsi)
        $global:UsaPwshTestHash = (Get-FileHash -LiteralPath $sample -Algorithm SHA256).Hash
    }

    AfterAll { Remove-Variable -Name UsaPwshTestMsi, UsaPwshTestHash, UsaPwshTestListed, UsaPwshTestFolder -Scope Global -ErrorAction SilentlyContinue }

    BeforeEach {
        $global:UsaPwshTestListed = $global:UsaPwshTestHash
        $global:UsaPwshTestFolder = $null
        Mock -ModuleName UsaBanner Test-UsaBannerElevated { $true }
        Mock -ModuleName UsaBanner Get-UsaBannerPwshRelease {
            [pscustomobject]@{
                Version   = [version]'7.6.10'
                Name      = 'PowerShell-7.6.10-win-x64.msi'
                Url       = 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.10/PowerShell-7.6.10-win-x64.msi'
                HashesUrl = 'https://github.com/PowerShell/PowerShell/releases/download/v7.6.10/hashes.sha256'
            }
        }
        Mock -ModuleName UsaBanner Save-UsaBannerWebFile {
            $global:UsaPwshTestFolder = Split-Path $OutFile -Parent
            if ($Uri -like '*/hashes.sha256') {
                [System.IO.File]::WriteAllLines($OutFile, [string[]]@("$('ab' * 32) *PowerShell-7.6.10-win-x64.msix", "$global:UsaPwshTestListed *PowerShell-7.6.10-win-x64.msi"))
            }
            else { [System.IO.File]::WriteAllBytes($OutFile, $global:UsaPwshTestMsi) }
        }
        Mock -ModuleName UsaBanner Test-UsaBannerMicrosoftSignature { $true }
        Mock -ModuleName UsaBanner Invoke-UsaBannerPwshMsi { 0 }
        Mock -ModuleName UsaBanner Find-UsaBannerPwsh { 'C:\Program Files\PowerShell\7\pwsh.exe' }
    }

    It 'downloads the MSI and its release''s hashes, checks both, installs it and returns pwsh''s path, with -Confirm:$false' {
        InModuleScope UsaBanner { Install-UsaBannerPwsh -Command 'Deploy-UsaBanner' -Confirm:$false } | Should -BeExactly 'C:\Program Files\PowerShell\7\pwsh.exe'
        Should -Invoke -ModuleName UsaBanner Save-UsaBannerWebFile -Times 2 -Exactly
        Should -Invoke -ModuleName UsaBanner Test-UsaBannerMicrosoftSignature -Times 1 -Exactly -ParameterFilter { (Split-Path $Path -Leaf) -eq 'PowerShell-7.6.10-win-x64.msi' }
        Should -Invoke -ModuleName UsaBanner Invoke-UsaBannerPwshMsi -Times 1 -Exactly -ParameterFilter {
            (Split-Path $MsiPath -Leaf) -eq 'PowerShell-7.6.10-win-x64.msi' -and (Split-Path $LogPath -Leaf) -eq 'msiexec.log'
        }
        $global:UsaPwshTestFolder | Should -Not -BeNullOrEmpty
        Test-Path -LiteralPath $global:UsaPwshTestFolder | Should -BeFalse -Because 'the downloads go once it is installed'
    }

    It 'takes msiexec''s 3010 as installed: Windows asks for a restart to finish' {
        Mock -ModuleName UsaBanner Invoke-UsaBannerPwshMsi { 3010 }
        InModuleScope UsaBanner { Install-UsaBannerPwsh -Command 'Deploy-UsaBanner' -Confirm:$false } | Should -BeExactly 'C:\Program Files\PowerShell\7\pwsh.exe'
    }

    It 'downloads and installs nothing under -WhatIf' {
        InModuleScope UsaBanner { Install-UsaBannerPwsh -Command 'Deploy-UsaBanner' -WhatIf } | Should -BeNullOrEmpty
        Should -Invoke -ModuleName UsaBanner Save-UsaBannerWebFile -Times 0 -Exactly
        Should -Invoke -ModuleName UsaBanner Invoke-UsaBannerPwshMsi -Times 0 -Exactly
    }

    It 'needs an administrator, and says so before it downloads anything' {
        Mock -ModuleName UsaBanner Test-UsaBannerElevated { $false }
        { InModuleScope UsaBanner { Install-UsaBannerPwsh -Command 'Deploy-UsaBanner' -Confirm:$false } } |
            Should -Throw '*Deploy-UsaBanner needs PowerShell 7, and none was found. Installing it takes an administrator: run Deploy-UsaBanner again in an elevated PowerShell, or install PowerShell 7 yourself*'
        Should -Invoke -ModuleName UsaBanner Save-UsaBannerWebFile -Times 0 -Exactly
    }

    It 'installs nothing when the MSI''s SHA-256 is not the one its release lists' {
        $global:UsaPwshTestListed = '00' * 32
        { InModuleScope UsaBanner { Install-UsaBannerPwsh -Command 'Deploy-UsaBanner' -Confirm:$false } } |
            Should -Throw "*PowerShell-7.6.10-win-x64.msi has SHA-256 $global:UsaPwshTestHash, but its release lists $('00' * 32): nothing was installed.*"
        Should -Invoke -ModuleName UsaBanner Invoke-UsaBannerPwshMsi -Times 0 -Exactly
    }

    It 'installs nothing without Microsoft''s signature' {
        Mock -ModuleName UsaBanner Test-UsaBannerMicrosoftSignature { $false }
        { InModuleScope UsaBanner { Install-UsaBannerPwsh -Command 'Deploy-UsaBanner' -Confirm:$false } } |
            Should -Throw '*PowerShell-7.6.10-win-x64.msi carries no valid Microsoft signature that this machine can check: nothing was installed.*'
        Should -Invoke -ModuleName UsaBanner Invoke-UsaBannerPwshMsi -Times 0 -Exactly
    }

    It 'says msiexec''s exit code, and keeps its log, when the install fails' {
        Mock -ModuleName UsaBanner Invoke-UsaBannerPwshMsi { 1603 }
        { InModuleScope UsaBanner { Install-UsaBannerPwsh -Command 'Deploy-UsaBanner' -Confirm:$false } } |
            Should -Throw '*installing PowerShell 7.6.10 failed: msiexec exit code 1603. Its log is *msiexec.log.*'
        Test-Path -LiteralPath $global:UsaPwshTestFolder | Should -BeTrue -Because 'the log stays for whoever reads the failure'
        Remove-Item -LiteralPath $global:UsaPwshTestFolder -Recurse -Force
    }

    It 'says so when pwsh is not where its MSI puts it' {
        Mock -ModuleName UsaBanner Find-UsaBannerPwsh { }
        { InModuleScope UsaBanner { Install-UsaBannerPwsh -Command 'Deploy-UsaBanner' -Confirm:$false } } |
            Should -Throw '*PowerShell 7.6.10 installed, but pwsh is not where its MSI puts it.*'
        Remove-Item -LiteralPath $global:UsaPwshTestFolder -Recurse -Force
    }
}

Describe 'Install-UsaBannerPwsh where no one can answer' {
    It 'stops, saying what to do instead, in a non-interactive pwsh, and downloads nothing' {
        # Its own process, -NonInteractive, whatever host runs these tests: a prompt in an interactive
        # one would wait for a key. The stand-ins replace the module's own functions in its scope.
        $marker = Join-Path $TestDrive 'downloaded.txt'
        $script = Join-Path $TestDrive 'ask.ps1'
        Set-Content -LiteralPath $script -Value @(
            '$ErrorActionPreference = ''Stop'''
            ('Import-Module -Name ''{0}''' -f $manifest.Replace("'", "''"))
            '$module = Get-Module -Name UsaBanner'
            '& $module {'
            '    function script:Test-UsaBannerElevated { $true }'
            '    function script:Get-UsaBannerPwshRelease { [pscustomobject]@{ Version = [version]''7.6.10''; Name = ''PowerShell-7.6.10-win-x64.msi''; Url = ''https://github.com/x''; HashesUrl = ''https://github.com/y'' } }'
            ('    function script:Save-UsaBannerWebFile {{ param($Uri, $OutFile) Set-Content -LiteralPath ''{0}'' -Value $Uri }}' -f $marker.Replace("'", "''"))
            '}'
            'try { $null = & $module { Install-UsaBannerPwsh -Command ''Show-UsaBanner'' }; ''returned'' }'
            'catch { ''threw: '' + $_.Exception.Message }'
        )
        $out = @(& (Get-Process -Id $PID).Path -NoProfile -NonInteractive -File $script 2>&1 | ForEach-Object { "$_" })
        ($out -join "`n") | Should -BeLike "*threw: UsaBanner: Show-UsaBanner needs PowerShell 7, and none was found; this PowerShell cannot ask whether to install it (*): install PowerShell 7 yourself*"
        Test-Path -LiteralPath $marker | Should -BeFalse
    }
}

Describe 'Invoke-UsaBannerHandoff where no pwsh is found' {
    It 'installs PowerShell 7, then hands the command to it' {
        Mock -ModuleName UsaBanner Find-UsaBannerPwsh { }
        Mock -ModuleName UsaBanner Install-UsaBannerPwsh { (Get-Process -Id $PID).Path }
        $direct = @(Show-UsaBannerArt -ColorMode none)
        $handed = @(InModuleScope UsaBanner { Invoke-UsaBannerHandoff -Command 'Show-UsaBannerArt' -Parameters @{ ColorMode = 'none' } })
        ($handed -join "`n") | Should -BeExactly ($direct -join "`n")
        Should -Invoke -ModuleName UsaBanner Install-UsaBannerPwsh -Times 1 -Exactly -ParameterFilter { $Command -eq 'Show-UsaBannerArt' }
    }

    It 'says what to install when the answer is no' {
        Mock -ModuleName UsaBanner Find-UsaBannerPwsh { }
        Mock -ModuleName UsaBanner Install-UsaBannerPwsh { }
        { InModuleScope UsaBanner { Invoke-UsaBannerHandoff -Command 'Show-UsaBannerArt' } } |
            Should -Throw '*Show-UsaBannerArt needs PowerShell 7, and none was found. Install it (deploy-usawinssh does, or the MSI from https://github.com/PowerShell/PowerShell/releases), then run Show-UsaBannerArt again.*'
    }

    It 'says that -WhatIf installs nothing, under -WhatIf' {
        Mock -ModuleName UsaBanner Find-UsaBannerPwsh { }
        Mock -ModuleName UsaBanner Install-UsaBannerPwsh { }
        { InModuleScope UsaBanner { $WhatIfPreference = $true; Invoke-UsaBannerHandoff -Command 'Deploy-UsaBanner' } } |
            Should -Throw '*Deploy-UsaBanner needs PowerShell 7, and none was found. -WhatIf installs nothing, so this stops here: run Deploy-UsaBanner again without -WhatIf to install it.*'
    }

    It 'carries a command''s -WhatIf to the install, which then downloads nothing' {
        Mock -ModuleName UsaBanner Find-UsaBannerPwsh { }
        Mock -ModuleName UsaBanner Test-UsaBannerElevated { $true }
        Mock -ModuleName UsaBanner Get-UsaBannerPwshRelease { [pscustomobject]@{ Version = [version]'7.6.10'; Name = 'PowerShell-7.6.10-win-x64.msi'; Url = 'https://github.com/x'; HashesUrl = 'https://github.com/y' } }
        Mock -ModuleName UsaBanner Save-UsaBannerWebFile { }
        { InModuleScope UsaBanner { $WhatIfPreference = $true; Invoke-UsaBannerHandoff -Command 'Deploy-UsaBanner' } } | Should -Throw '*-WhatIf installs nothing*'
        Should -Invoke -ModuleName UsaBanner Save-UsaBannerWebFile -Times 0 -Exactly
    }
}
