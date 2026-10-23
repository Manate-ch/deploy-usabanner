# The Ubuntu bootstrap (UsaBanner/linux/bootstrap.sh and bootstrap.ps1, docs/DECISIONS.md D18).
# bootstrap.sh runs under sh with a PATH of stand-ins alone, each logging its call as a line, its
# arguments separated by tabs: nothing is downloaded or installed, and PowerShell is missing
# unless a test puts its stand-in there. bootstrap.ps1 runs in a real pwsh against a stand-in
# module, whose Deploy-UsaBanner has the real one's parameters and says what it was given.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $script:ModuleRoot = Join-Path $repoRoot 'UsaBanner'
    $script:Tab = "`t"
}

Describe 'bootstrap.sh' -Skip:$IsWindows {
    BeforeAll {
        $script:Script = Join-Path $ModuleRoot 'linux' 'bootstrap.sh'
        $script:Here = Join-Path $ModuleRoot 'linux'
        $script:EnvTool = (Get-Command -Name env -CommandType Application)[0].Source
        $script:Url = 'https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb'

        function Write-StandIn {
            # In:  a folder, a program's name, what it does after logging its call; -Quiet for
            #      one that logs nothing, -Frontend to log DEBIAN_FRONTEND too
            # Out: nothing; the folder holds the stand-in, executable
            param([string]$Folder, [string]$Name, [string]$Body = '', [switch]$Quiet, [switch]$Frontend)
            $extra = if ($Frontend) { "${Tab}DEBIAN_FRONTEND=`${DEBIAN_FRONTEND:-}" } else { '' }
            $lines = @('#!/bin/sh')
            if (-not $Quiet) { $lines += "(IFS='$Tab'; printf '%s\n' `"`${0##*/}$Tab`$*$extra`") >>`"`$STUB_LOG`"" }
            $path = Join-Path $Folder $Name
            [System.IO.File]::WriteAllText($path, (($lines + $Body.Replace("`r`n", "`n")) -join "`n") + "`n")
            [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute, OtherRead, OtherExecute')
        }

        function Set-OsRelease {
            # In:  the ID and VERSION_ID the host's os-release gives
            param([string]$Id, [string]$Version)
            [System.IO.File]::WriteAllText((Join-Path $Root 'etc/os-release'), "PRETTY_NAME=`"Test`"`nID=$Id`nID_LIKE=debian`nVERSION_ID=`"$Version`"`n")
        }

        function Invoke-Bootstrap {
            # In:  the flags, and variables for the stand-ins, as NAME=value
            # Out: @{ ExitCode; Output; Calls }: bootstrap.sh's exit code, what it printed, and
            #      the stand-ins' calls, a line each
            param([string[]]$Arguments = @(), [string[]]$Variables = @())
            $output = @(& $EnvTool -i "PATH=$Bin" "STUB_LOG=$Log" "STUB_BIN=$Bin" "STUB_SPARE=$Spare" "USABANNER_ROOT=$Root" @Variables /bin/sh $Script @Arguments 2>&1 | ForEach-Object { "$_" })
            @{
                ExitCode = $LASTEXITCODE
                Output   = $output
                Calls    = @(if (Test-Path -LiteralPath $Log) { Get-Content -LiteralPath $Log })
            }
        }
    }

    BeforeEach {
        $work = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $script:Bin = Join-Path $work 'bin'
        $script:Spare = Join-Path $work 'spare'
        $script:Root = Join-Path $work 'host'
        $script:Log = Join-Path $work 'calls.log'
        foreach ($folder in $Bin, $Spare, (Join-Path $Root 'etc')) { $null = New-Item -ItemType Directory -Path $folder -Force }
        # The tools bootstrap.sh and the stand-ins use, as they are.
        foreach ($tool in 'sed', 'tr', 'dirname', 'mktemp', 'rm', 'cp') {
            $null = New-Item -ItemType SymbolicLink -Path (Join-Path $Bin $tool) -Target (Get-Command -Name $tool -CommandType Application)[0].Source
        }
        Write-StandIn $Bin 'id' 'printf ''%s\n'' "${STUB_UID:-0}"' -Quiet
        # apt-get installs a package by putting its stand-in on the PATH.
        Write-StandIn $Bin 'apt-get' -Frontend -Body @'
case $1:$3 in
install:powershell)
	[ -n "${STUB_FAIL_INSTALL:-}" ] && exit 100
	cp "$STUB_SPARE/pwsh" "$STUB_BIN/pwsh"
	;;
install:wget) cp "$STUB_SPARE/wget" "$STUB_BIN/wget" ;;
esac
exit 0
'@
        Write-StandIn $Bin 'dpkg' '[ -s "$2" ]'
        Write-StandIn $Spare 'pwsh' 'exit "${STUB_PWSH_EXIT:-0}"'
        Write-StandIn $Spare 'wget' "[ -n `"`${STUB_FAIL_DOWNLOAD:-}`" ] && exit 8`nprintf 'deb\n' >`"`$3`""
        Write-StandIn $Spare 'curl' "[ -n `"`${STUB_FAIL_DOWNLOAD:-}`" ] && exit 22`nprintf 'deb\n' >`"`$3`""
        Set-OsRelease 'ubuntu' '24.04'
    }

    It 'parses under sh -n' {
        $out = & sh -n $Script 2>&1 | Out-String
        "$out`nexit=$LASTEXITCODE" | Should -Match 'exit=0$'
    }

    It 'runs Deploy-UsaBanner through pwsh with the flags as given, where PowerShell is installed: nothing else' {
        Copy-Item -LiteralPath (Join-Path $Spare 'pwsh') -Destination $Bin
        $result = Invoke-Bootstrap -Arguments @('-Company', 'Contoso LLC', '-Environment', 'PROD')
        $result.ExitCode | Should -Be 0
        $result.Calls | Should -Be @("pwsh${Tab}-NoProfile${Tab}-NonInteractive${Tab}-File${Tab}$Here/bootstrap.ps1${Tab}-Company${Tab}Contoso LLC${Tab}-Environment${Tab}PROD")
    }

    It 'installs PowerShell from Microsoft''s package repository where it is missing, downloading with curl, then deploys' {
        Copy-Item -LiteralPath (Join-Path $Spare 'curl') -Destination $Bin
        $result = Invoke-Bootstrap -Arguments @('-Company', 'Contoso')
        $result.ExitCode | Should -Be 0
        $deb = ($result.Calls[0] -split $Tab)[3]
        $result.Calls | Should -Be @(
            "curl${Tab}-fsSL${Tab}-o${Tab}$deb${Tab}$Url"
            "dpkg${Tab}-i${Tab}$deb"
            "apt-get${Tab}update${Tab}DEBIAN_FRONTEND=noninteractive"
            "apt-get${Tab}install${Tab}-y${Tab}powershell${Tab}DEBIAN_FRONTEND=noninteractive"
            "pwsh${Tab}-NoProfile${Tab}-NonInteractive${Tab}-File${Tab}$Here/bootstrap.ps1${Tab}-Company${Tab}Contoso"
        )
        $deb | Should -Not -Exist
        $result.Output | Should -Contain "bootstrap.sh: installing PowerShell 7 from Microsoft's package repository (packages-microsoft-prod, powershell)"
    }

    It 'downloads with wget where there is no curl' {
        Copy-Item -LiteralPath (Join-Path $Spare 'wget') -Destination $Bin
        $result = Invoke-Bootstrap
        $result.ExitCode | Should -Be 0
        $result.Calls[0] | Should -BeLike "wget${Tab}-q${Tab}-O${Tab}*${Tab}$Url"
    }

    It 'installs wget first where the host has neither wget nor curl' {
        $result = Invoke-Bootstrap
        $result.ExitCode | Should -Be 0
        @($result.Calls | ForEach-Object { ($_ -split $Tab)[0..1] -join ' ' }) | Should -Be @(
            'apt-get update', 'apt-get install', 'wget -q', 'dpkg -i', 'apt-get update', 'apt-get install', 'pwsh -NoProfile')
        ($result.Calls[1] -split $Tab)[3] | Should -BeExactly 'wget'
    }

    It 'stops, naming the address, where Microsoft publishes no package for the release; and leaves no download behind' {
        Copy-Item -LiteralPath (Join-Path $Spare 'curl') -Destination $Bin
        Set-OsRelease 'ubuntu' '25.10'
        $result = Invoke-Bootstrap -Variables @('STUB_FAIL_DOWNLOAD=1')
        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match ([regex]::Escape('could not download https://packages.microsoft.com/config/ubuntu/25.10/packages-microsoft-prod.deb. Microsoft publishes it for the Ubuntu releases it supports'))
        $result.Calls.Count | Should -Be 1
        ($result.Calls[0] -split $Tab)[3] | Should -Not -Exist
    }

    It 'stops when apt-get cannot install powershell, and runs no pwsh' {
        Copy-Item -LiteralPath (Join-Path $Spare 'curl') -Destination $Bin
        $result = Invoke-Bootstrap -Variables @('STUB_FAIL_INSTALL=1')
        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'apt-get could not install powershell'
        @($result.Calls | Where-Object { $_ -like "pwsh$Tab*" }) | Should -BeNullOrEmpty
    }

    It 'runs as root only, and runs nothing for another user' {
        $result = Invoke-Bootstrap -Variables @('STUB_UID=1000')
        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'so it runs as root: sudo sh bootstrap.sh'
        $result.Calls | Should -BeNullOrEmpty
    }

    It 'refuses a host that is not Ubuntu, and runs nothing' {
        Set-OsRelease 'debian' '12'
        $result = Invoke-Bootstrap
        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'this host is not Ubuntu'
        $result.Calls | Should -BeNullOrEmpty
    }

    It 'ends with the deploy''s own exit code' {
        Copy-Item -LiteralPath (Join-Path $Spare 'pwsh') -Destination $Bin
        (Invoke-Bootstrap -Variables @('STUB_PWSH_EXIT=1')).ExitCode | Should -Be 1
    }
}

Describe 'bootstrap.ps1' {
    BeforeAll {
        $script:Pwsh = (Get-Process -Id $PID).Path
        $script:Mod = Join-Path $TestDrive 'module'
        $null = New-Item -ItemType Directory -Path (Join-Path $Mod 'linux') -Force
        Copy-Item -LiteralPath (Join-Path $ModuleRoot 'linux' 'bootstrap.ps1') -Destination (Join-Path $Mod 'linux')
        # The stand-in's Deploy-UsaBanner takes the real one's parameters, with their checks.
        Import-Module (Join-Path $ModuleRoot 'UsaBanner.psd1') -Force
        $meta = [System.Management.Automation.CommandMetadata]::new((Get-Command -Module UsaBanner -Name Deploy-UsaBanner))
        Remove-Module UsaBanner
        $standIn = @(
            'function Deploy-UsaBanner {'
            [System.Management.Automation.ProxyCommand]::GetCmdletBindingAttribute($meta)
            "param($([System.Management.Automation.ProxyCommand]::GetParamBlock($meta)))"
            "if (`$Company -eq 'fail') { throw 'UsaBanner: the deploy failed' }"
            "foreach (`$key in @(`$PSBoundParameters.Keys | Sort-Object)) { '{0}={1}' -f `$key, (@(`$PSBoundParameters[`$key]) -join '|') }"
            '}'
        ) -join "`n"
        [System.IO.File]::WriteAllText((Join-Path $Mod 'UsaBanner.psm1'), "$standIn`n")
        [System.IO.File]::WriteAllText((Join-Path $Mod 'UsaBanner.psd1'), "@{ RootModule = 'UsaBanner.psm1'; ModuleVersion = '0.0.1'; FunctionsToExport = @('Deploy-UsaBanner') }`n")

        function Invoke-SecondHalf {
            # In:  the flags, as bootstrap.sh passes them on
            # Out: @{ ExitCode; Output }: what the stand-in deploy was given, a line per parameter
            param([string[]]$Arguments)
            $output = @(& $Pwsh -NoProfile -NonInteractive -File (Join-Path $Mod 'linux' 'bootstrap.ps1') @Arguments 2>&1 | ForEach-Object { "$_" })
            @{ ExitCode = $LASTEXITCODE; Output = $output }
        }
    }

    It 'gives Deploy-UsaBanner each flag by its name: a value with a space, and a switch' {
        $result = Invoke-SecondHalf @('-Company', 'Contoso LLC', '-Environment', 'PROD', '-WhatIf')
        $result.Output | Should -Be @('Company=Contoso LLC', 'Environment=PROD', 'WhatIf=True')
        $result.ExitCode | Should -Be 0
    }

    It 'splits a list at its commas, so that each name passes its check' {
        (Invoke-SecondHalf @('-Services', 'ssh, cron', '-PreInit', 'HostName,Ip', '-PreLogon', 'None')).Output | Should -Be @(
            'PreInit=HostName|Ip', 'PreLogon=None', 'Services=ssh|cron')
    }

    It 'leaves the value of any other flag whole, commas and all' {
        (Invoke-SecondHalf @('-LegalText', 'One, two.', '-BorderCap', '(o,o)')).Output | Should -Be @('BorderCap=(o,o)', 'LegalText=One, two.')
    }

    It 'gives a value that is a dash as the value it is' {
        (Invoke-SecondHalf @('-Border', 'OneChar', '-BorderChar', '-')).Output | Should -Be @('Border=OneChar', 'BorderChar=-')
    }

    It 'ends with exit code 1 when the deploy fails, and says why' {
        $result = Invoke-SecondHalf @('-Company', 'fail')
        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'the deploy failed'
    }
}
