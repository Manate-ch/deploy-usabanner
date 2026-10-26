# Update.Logged.ps1 - the functions of Update.ps1 that PowerShell logs whole at each import (D30).

function Update-UsaBannerRelease {
    <#
    .SYNOPSIS
    The update job (D14): looks for a newer release, and says so at login or
    installs it, as this host's configuration sets.
    .DESCRIPTION
    Out: a line saying what it found or did. Throws when the release cannot
    be read or installed: update.json then says what failed, and the host
    keeps the version it had.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $paths = Get-UsaBannerUpdatePaths
    $config = Read-UsaBannerConfig -Path $paths.Config
    $mode = [string]$config['update']['mode']
    if ($mode -eq 'off') {
        Remove-UsaBannerStateFile -Name 'notice'
        return 'the update channel is off'
    }
    $source = ([string]$config['update']['source']).TrimEnd('/')
    $installed = Get-UsaBannerModuleVersion -Folder $paths.Modules
    # checked: seconds since 1970, as the samples keep time; ConvertFrom-Json would turn a
    # date in words into a DateTime of its own choosing.
    $state = [ordered]@{ checked = [System.DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); mode = $mode; source = $source; installed = [string]$installed; latest = ''; error = '' }
    $staging = [System.IO.Path]::Combine($paths.State, 'update')
    $save = {
        # Out: nothing; update.json holds the state, as Get-UsaBanner reads it
        Write-UsaBannerStateFile -Name 'update.json' -Text (((ConvertTo-Json -InputObject $state) -replace "`r`n", "`n") + "`n")
    }
    try {
        Reset-UsaBannerStaging -Path $staging
        $sumsFile = [System.IO.Path]::Combine($staging, 'SHA256SUMS')
        Invoke-UsaBannerDownload -Uri "$source/SHA256SUMS" -OutFile $sumsFile
        $archive = Select-UsaBannerReleaseArchive -Sums (Read-UsaBannerReleaseSums -Text ([System.IO.File]::ReadAllText($sumsFile)))
        if (-not $archive) { throw "UsaBanner: $source/SHA256SUMS names no UsaBanner-<version>.zip." }
        $state.latest = [string]$archive.Version
        if ($installed -and $archive.Version -le $installed) {
            Remove-UsaBannerStateFile -Name 'notice'
            & $save
            Reset-UsaBannerStaging -Path $staging -Remove
            return "UsaBanner $installed is the newest release"
        }
        if ($mode -eq 'notify') {
            Write-UsaBannerStateFile -Name 'notice' -Text (($script:UsaUpdateNotice -f (Get-UsaBannerUpdatePage -Source $source)) + "`n")
            & $save
            Reset-UsaBannerStaging -Path $staging -Remove
            return "UsaBanner $($archive.Version) is out, and this host has $installed`: the banner after login says so"
        }

        $zip = [System.IO.Path]::Combine($staging, $archive.Name)
        Invoke-UsaBannerDownload -Uri "$source/$($archive.Name)" -OutFile $zip
        $sum = Get-UsaBannerSha256 -Bytes ([System.IO.File]::ReadAllBytes($zip))
        if ($sum -ne $archive.Sha) { throw "UsaBanner: $($archive.Name) does not match its line in SHA256SUMS (its SHA-256 is $sum), so nothing is installed." }
        $unpacked = [System.IO.Path]::Combine($staging, 'unpacked')
        Add-Type -AssemblyName System.IO.Compression.ZipFile
        # It refuses an entry that would land outside the folder [fetched: ZipFile.ExtractToDirectory].
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $unpacked)
        $manifest = [System.IO.Path]::Combine($unpacked, 'UsaBanner', 'UsaBanner.psd1')
        $entry = [System.IO.Path]::Combine($unpacked, 'UsaBanner', 'linux', 'bootstrap.ps1')
        if (-not ([System.IO.File]::Exists($manifest) -and [System.IO.File]::Exists($entry))) { throw "UsaBanner: $($archive.Name) holds no UsaBanner module with its linux/bootstrap.ps1, so nothing is installed." }
        $version = [version](Import-PowerShellDataFile -LiteralPath $manifest).ModuleVersion
        if ($version -ne $archive.Version) { throw "UsaBanner: $($archive.Name) holds UsaBanner $version, not $($archive.Version), so nothing is installed." }

        $had = [System.IO.Directory]::Exists([System.IO.Path]::Combine($paths.Modules, 'UsaBanner', [string]$version))
        $run = Invoke-UsaBannerNative -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile', '-NonInteractive', '-File', $entry, '-Path', $paths.Config
        if ($run.ExitCode -ne 0) {
            # The new version's folder goes, and the old version puts back what the new one's deploy changed.
            if (-not $had) { Remove-UsaBannerModuleVersion -Version $version -What "UsaBanner $version, whose deploy failed" }
            $back = ''
            try {
                if ((Get-UsaBannerHostOs) -eq 'windows') { $null = @(Invoke-UsaBannerWindowsDeploy -Config $config -WhatIf:$false -Confirm:$false) }
                else { $null = @(Invoke-UsaBannerLinuxDeploy -Config $config -WhatIf:$false -Confirm:$false) }
            }
            catch { $back = " UsaBanner $installed could not deploy the configuration again either: $($_.Exception.Message)" }
            throw "UsaBanner: UsaBanner $version's deploy failed (exit code $($run.ExitCode)), so this host keeps UsaBanner ${installed}: $(@($run.Output) -join ' ').$back"
        }
        if ($installed -and $installed -ne $version) { Remove-UsaBannerModuleVersion -Version $installed -What "UsaBanner $installed, which $version replaced" }
        Remove-UsaBannerStateFile -Name 'notice'
        $state.installed = [string]$version
        & $save
        Reset-UsaBannerStaging -Path $staging -Remove
        "installed UsaBanner $version, which deployed this host's configuration in place of UsaBanner $installed"
    }
    catch {
        $state.error = $_.Exception.Message
        & $save
        Reset-UsaBannerStaging -Path $staging -Remove
        throw
    }
}
