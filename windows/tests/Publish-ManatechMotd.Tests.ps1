# Pester 5 tests for Publish-ManatechMotd.ps1, run against a throwaway clone
# and a throwaway ADSys assets folder (-UbuntuPath) instead of SYSVOL. They
# publish the files only (-SkipGpo): the GPO half needs the GroupPolicy module
# and a domain, so it is proved on a DC, and its pure parts are tested in
# ManatechMotdGpo.Tests.ps1.

BeforeAll {
    $script:Publish = Join-Path $PSScriptRoot '../Publish-ManatechMotd.ps1'

    function Write-TestFile {
        param([string]$Path, [string]$Text)
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [System.IO.File]::WriteAllText($Path, $Text)
    }

    # A clone the way Git for Windows checks it out with core.autocrlf: some
    # files CRLF, some LF, plus files that must not be published.
    function New-Clone {
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Write-TestFile (Join-Path $repo 'install.sh') "#!/bin/sh`r`necho one`r`n"
        Write-TestFile (Join-Path $repo 'adsys-startup.sh') "#!/bin/sh`necho two`n"
        Write-TestFile (Join-Path $repo 'README.md') "# readme`r`n"
        Write-TestFile (Join-Path $repo 'rootfs/usr/local/share/manatech/envs.tsv') "PROD`tBlue`r`nLAB`tOrange`r`n"
        Write-TestFile (Join-Path $repo 'windows/ManatechBanner.psm1') "# module`n"
        Write-TestFile (Join-Path $repo 'windows/demo.ps1') "# demo`n"
        Write-TestFile (Join-Path $repo 'windows/tests/X.Tests.ps1') "# test`n"
        Write-TestFile (Join-Path $repo 'notes.txt') "not part of the payload`n"
        $repo
    }
    function New-Assets {
        $ubuntu = Join-Path (Join-Path $TestDrive ([guid]::NewGuid().ToString())) 'Ubuntu'
        Write-TestFile (Join-Path $ubuntu 'GPT.INI') "[General]`r`nVersion=7`r`n"
        $ubuntu
    }
    function Get-Version {
        param([string]$Ubuntu)
        [int]([regex]::Match([System.IO.File]::ReadAllText((Join-Path $Ubuntu 'GPT.INI')), '(?m)^Version=(\d+)').Groups[1].Value)
    }
    function Get-Motd {
        param([string]$Ubuntu, [string]$Rel)
        Join-Path (Join-Path (Join-Path $Ubuntu 'scripts') 'MOTD') $Rel
    }
    # The Windows copy's default with -UbuntuPath: scripts/MOTD beside the
    # Ubuntu folder, which on a DC's own SYSVOL path is NETLOGON\MOTD.
    function Get-Netlogon {
        param([string]$Ubuntu, [string]$Rel)
        Join-Path (Join-Path (Join-Path (Split-Path -Parent $Ubuntu) 'scripts') 'MOTD') $Rel
    }
}

Describe 'Publish-ManatechMotd.ps1' {
    It 'publishes CRLF files as LF and says how many it converted' {
        $repo = New-Clone
        $ubuntu = New-Assets
        $out = & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>&1 | Out-String
        [System.IO.File]::ReadAllText((Get-Motd $ubuntu 'install.sh')) | Should -BeExactly "#!/bin/sh`necho one`n"
        [System.IO.File]::ReadAllText((Get-Motd $ubuntu 'rootfs/usr/local/share/manatech/envs.tsv')) | Should -BeExactly "PROD`tBlue`nLAB`tOrange`n"
        [System.IO.File]::ReadAllText((Get-Motd $ubuntu 'adsys-startup.sh')) | Should -BeExactly "#!/bin/sh`necho two`n"
        $out | Should -Match '3 file\(s\) .* have CRLF line endings'
    }
    It 'leaves tests, demo.ps1 and files outside the payload out' {
        $repo = New-Clone
        $ubuntu = New-Assets
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null
        Get-Motd $ubuntu 'windows/ManatechBanner.psm1' | Should -Exist
        Get-Motd $ubuntu 'windows/demo.ps1' | Should -Not -Exist
        Get-Motd $ubuntu 'windows/tests' | Should -Not -Exist
        Get-Motd $ubuntu 'notes.txt' | Should -Not -Exist
    }
    It 'bumps GPT.INI once, and not again when nothing changed' {
        $repo = New-Clone
        $ubuntu = New-Assets
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null
        Get-Version $ubuntu | Should -Be 8
        $out = & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>&1 | Out-String
        Get-Version $ubuntu | Should -Be 8
        $out | Should -Match 'already matches'
    }
    It 'republishes a file whose published copy differs, CRLF clone or not' {
        $repo = New-Clone
        $ubuntu = New-Assets
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null
        [System.IO.File]::WriteAllText((Get-Motd $ubuntu 'install.sh'), "#!/bin/sh`r`necho one`r`n")
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null
        [System.IO.File]::ReadAllText((Get-Motd $ubuntu 'install.sh')) | Should -BeExactly "#!/bin/sh`necho one`n"
        Get-Version $ubuntu | Should -Be 9
    }
    It 'removes a published file no longer in the repo, and nothing outside MOTD' {
        $repo = New-Clone
        $ubuntu = New-Assets
        Write-TestFile (Get-Motd $ubuntu 'old-name.sh') "echo old`n"
        $other = Join-Path (Join-Path (Join-Path $ubuntu 'scripts') 'OtherPolicy') 'other-policy.sh'
        Write-TestFile $other "echo other`n"
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null
        Get-Motd $ubuntu 'old-name.sh' | Should -Not -Exist
        $other | Should -Exist
    }
    It 'writes nothing with -WhatIf' {
        $repo = New-Clone
        $ubuntu = New-Assets
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo -WhatIf 6>$null
        Get-Motd $ubuntu '' | Should -Not -Exist
        Get-Netlogon $ubuntu '' | Should -Not -Exist
        Get-Version $ubuntu | Should -Be 7
    }
    It 'refuses an assets folder without GPT.INI' {
        $repo = New-Clone
        $ubuntu = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $ubuntu | Out-Null
        { & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null } | Should -Throw '*GPT.INI*'
    }
    It 'refuses the GPO half outside Windows PowerShell 5.1, before publishing anything' -Skip:($PSVersionTable.PSEdition -eq 'Desktop') {
        $repo = New-Clone
        $ubuntu = New-Assets
        { & $Publish -RepoPath $repo -UbuntuPath $ubuntu -Domain 'example.test' 6>$null } | Should -Throw '*Windows PowerShell 5.1*'
        Get-Motd $ubuntu '' | Should -Not -Exist
        Get-Version $ubuntu | Should -Be 7
    }
}

Describe 'Publish-ManatechMotd.ps1, the Windows copy (NETLOGON\MOTD)' {
    It 'holds README, rootfs and windows as LF, without the Linux entry scripts, and is marked as this script''s' {
        $repo = New-Clone
        $ubuntu = New-Assets
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null
        Get-Netlogon $ubuntu 'windows/ManatechBanner.psm1' | Should -Exist
        Get-Netlogon $ubuntu 'README.md' | Should -Exist
        [System.IO.File]::ReadAllText((Get-Netlogon $ubuntu 'rootfs/usr/local/share/manatech/envs.tsv')) | Should -BeExactly "PROD`tBlue`nLAB`tOrange`n"
        Get-Netlogon $ubuntu 'install.sh' | Should -Not -Exist
        Get-Netlogon $ubuntu 'adsys-startup.sh' | Should -Not -Exist
        Get-Netlogon $ubuntu 'windows/demo.ps1' | Should -Not -Exist
        Get-Netlogon $ubuntu 'windows/tests' | Should -Not -Exist
        Get-Netlogon $ubuntu '.manatech-motd' | Should -Exist
    }
    It 'goes to -NetlogonPath when one is given' {
        $repo = New-Clone
        $ubuntu = New-Assets
        $net = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo -NetlogonPath $net 6>$null
        Join-Path $net 'windows/ManatechBanner.psm1' | Should -Exist
        Get-Netlogon $ubuntu '' | Should -Not -Exist
    }
    It 'repairs a changed file there without bumping GPT.INI (ADSys never reads it)' {
        $repo = New-Clone
        $ubuntu = New-Assets
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null
        [System.IO.File]::WriteAllText((Get-Netlogon $ubuntu 'windows/ManatechBanner.psm1'), "# edited`n")
        $out = & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>&1 | Out-String
        [System.IO.File]::ReadAllText((Get-Netlogon $ubuntu 'windows/ManatechBanner.psm1')) | Should -BeExactly "# module`n"
        Get-Version $ubuntu | Should -Be 8
        $out | Should -Match '1 file change\(s\) published to'
        $out | Should -Match 'SYSVOL already matches'
    }
    It 'removes a file no longer in the repo there too, and keeps its mark' {
        $repo = New-Clone
        $ubuntu = New-Assets
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null
        Write-TestFile (Get-Netlogon $ubuntu 'windows/Old.ps1') "# old`n"
        & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null
        Get-Netlogon $ubuntu 'windows/Old.ps1' | Should -Not -Exist
        Get-Netlogon $ubuntu '.manatech-motd' | Should -Exist
    }
    It 'refuses a NETLOGON\MOTD it did not create, before writing anything anywhere' {
        $repo = New-Clone
        $ubuntu = New-Assets
        $foreign = Get-Netlogon $ubuntu 'logon.cmd'
        Write-TestFile $foreign "@echo off`r`n"
        { & $Publish -RepoPath $repo -UbuntuPath $ubuntu -SkipGpo 6>$null } | Should -Throw '*not created by this script*'
        $foreign | Should -Exist
        Get-Motd $ubuntu '' | Should -Not -Exist
        Get-Version $ubuntu | Should -Be 7
    }
}
