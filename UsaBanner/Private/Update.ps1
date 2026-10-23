# Update.ps1 - the update channel (docs/DECISIONS.md, D14). Where the
# configuration turns it on, the update job runs Update-UsaBannerRelease once
# a day, as root (SYSTEM). It reads SHA256SUMS at the configured source, and
# when that names a newer UsaBanner than the one installed, says so at login
# (notify), or installs it (install):
#
#   +-------------------------+-------------------------------------------+
#   | At the source           | Holds                                     |
#   +-------------------------+-------------------------------------------+
#   | SHA256SUMS              | a line per file: its SHA-256, then its    |
#   |                         | name, as sha256sum writes them            |
#   | UsaBanner-<version>.zip | the module, its folder UsaBanner at the   |
#   |                         | archive's root, as                        |
#   |                         | build/New-UsaBannerRelease.ps1 builds it  |
#   +-------------------------+-------------------------------------------+
#
# Only https, and no redirect from https to http. The archive is checked
# against SHA256SUMS before it is unpacked, and its manifest's version
# against its name after. Then the new version deploys the host's own
# configuration itself (its linux/bootstrap.ps1 -Path), and the old version's
# folder goes. When that deploy fails, the new version's folder goes instead,
# and the old version deploys the configuration again. The job's state is
# update.json in the banner's own folder, and the notice the banner after
# login shows is the file notice beside it.

# D14's words for the line the banner adds; {0} is the releases page.
$script:UsaUpdateNotice = 'This banner has an update available. See {0} for more info!'

# D14's warning, said when a deploy turns on install; {0} is the source.
$script:UsaUpdateWarning = 'UsaBanner: the update channel installs new releases from {0} by itself. The update job runs as root (SYSTEM) on this host, once a day: anyone who can change the releases there can change what runs here. The code is provided as is, without warranty; its authors are not liable for any damage it causes. -Update notify only says when a release is out.'

function Write-UsaBannerUpdateWarning {
    # In:  the configuration a deploy builds
    # Out: nothing; D14's warning, where it turns on install
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    if ([string]$Config['update']['mode'] -eq 'install') { Write-Warning ($script:UsaUpdateWarning -f [string]$Config['update']['source']) }
}

function Read-UsaBannerReleaseSums {
    # In:  the text of a release's SHA256SUMS
    # Out: an ordered map of each file it names to its SHA-256, in lower
    #      case; a line that is not a SHA-256 and a name, as sha256sum
    #      writes them, is passed over
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([AllowEmptyString()][string]$Text = '')
    $sums = [ordered]@{}
    foreach ($line in $Text -split "\r?\n") {
        if ($line -match '^([0-9A-Fa-f]{64}) [ *](\S.*)$') { $sums[$Matches[2]] = $Matches[1].ToLowerInvariant() }
    }
    $sums
}

function Select-UsaBannerReleaseArchive {
    # In:  a release's sums (Read-UsaBannerReleaseSums)
    # Out: @{ Name; Version; Sha } of the newest UsaBanner-<version>.zip they
    #      name; nothing when they name none
    # Why: the name is all a version and a file name, so no line of
    #      SHA256SUMS can point a download outside the staging folder
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Sums)
    $best = $null
    foreach ($name in $Sums.Keys) {
        if ([string]$name -cnotmatch '^UsaBanner-([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?)\.zip$') { continue }
        $version = [version]$Matches[1]
        if ($null -eq $best -or $version -gt $best.Version) { $best = @{ Name = [string]$name; Version = $version; Sha = [string]$Sums[$name] } }
    }
    $best
}

function Get-UsaBannerUpdatePage {
    # In:  the update channel's source
    # Out: the releases page it belongs to, for the notice: the address up to
    #      /releases, as a GitHub repository's and a GitLab project's run;
    #      the source itself where it holds no such part
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Source)
    if ($Source -match '^(.*?/releases)(/|$)') { return $Matches[1] }
    $Source
}

function Invoke-UsaBannerDownload {
    <#
    .SYNOPSIS
    Downloads one file of a release.
    .DESCRIPTION
    In:  its https address, and the file to write.
    Throws on an address that is not https, and when the download fails.
    PowerShell 7 refuses a redirect from https to http unless told to
    [fetched: Invoke-WebRequest, PowerShell 7.6, -AllowInsecureRedirect], and
    this never tells it to. The tests stand in for it with files.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$OutFile)
    if (-not $Uri.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "UsaBanner: $Uri is not an https address: the update channel downloads over https only."
    }
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -TimeoutSec 120 -ErrorAction Stop
}

function Get-UsaBannerUpdatePaths {
    # Out: @{ Config; State; Modules }: this host's configuration file, the
    #      banner's own folder (the job's state, notice and staging), and the
    #      modules folder for every user, as this process reads them
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    if ((Get-UsaBannerHostOs) -eq 'windows') {
        $layout = Get-UsaBannerWindowsLayout
        return @{ Config = [System.IO.Path]::Combine($layout.Data, 'usabanner.json'); State = $layout.Data; Modules = $layout.Modules }
    }
    $root = Get-UsaBannerHostRoot
    @{ Config = "$root$script:UsaLinuxEtc/usabanner.json"; State = "$root$script:UsaLinuxState"; Modules = "$root$script:UsaLinuxModules" }
}

function Write-UsaBannerStateFile {
    # In:  a file's name in the banner's own folder, and its text
    # Out: nothing; the file holds the text, written whole, as the banner's
    #      other files are: 644 on Linux, the folder's ACL on Windows
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string]$Text)
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    if ((Get-UsaBannerHostOs) -eq 'windows') {
        $null = Set-UsaBannerHostFile -Root '' -Path ([System.IO.Path]::Combine((Get-UsaBannerWindowsLayout).Data, $Name)) -Bytes $bytes -Mode $null -What "the update job's $Name" -WhatIf:$false
    }
    else { $null = Set-UsaBannerHostFile -Root (Get-UsaBannerHostRoot) -Path "$script:UsaLinuxState/$Name" -Bytes $bytes -What "the update job's $Name" -WhatIf:$false }
}

function Remove-UsaBannerStateFile {
    # In:  a file's name in the banner's own folder
    # Out: nothing; the file is gone
    param([Parameter(Mandatory)][string]$Name)
    $path = [System.IO.Path]::Combine((Get-UsaBannerUpdatePaths).State, $Name)
    if ([System.IO.File]::Exists($path)) { [System.IO.File]::Delete($path) }
}

function Remove-UsaBannerModuleVersion {
    # In:  a version of the module, and what it is
    # Out: nothing; that version's folder in the modules folder for every
    #      user is gone, by the removal that deletes only the banner's own
    #      folders
    param([Parameter(Mandatory)][version]$Version, [Parameter(Mandatory)][string]$What)
    if ((Get-UsaBannerHostOs) -eq 'windows') {
        $path = [System.IO.Path]::Combine((Get-UsaBannerWindowsLayout).Modules, 'UsaBanner', [string]$Version)
        $null = Remove-UsaBannerWindowsFolder -Path $path -Allowed $path -What $What -WhatIf:$false -Confirm:$false
    }
    else { $null = Remove-UsaBannerHostFolder -Root (Get-UsaBannerHostRoot) -Path "$script:UsaLinuxModules/UsaBanner/$Version" -What $What -WhatIf:$false -Confirm:$false }
}

function Reset-UsaBannerStaging {
    # In:  the staging folder, and -Remove to leave none
    # Out: nothing; the folder is there and empty, or gone
    # Why: each run starts from nothing a run before left
    param([Parameter(Mandatory)][string]$Path, [switch]$Remove)
    if ([System.IO.Directory]::Exists($Path)) { [System.IO.Directory]::Delete($Path, $true) }
    if (-not $Remove) { $null = [System.IO.Directory]::CreateDirectory($Path) }
}

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
