# PwshInstall.ps1 - PowerShell 7 for a hand-off that finds none (docs/DECISIONS.md,
# D18): under Windows PowerShell 5.1 a command of the module installs it, asking
# first, then hands itself over as it would have. Windows PowerShell 5.1 loads
# this file: 5.1 syntax only.

# Where the releases are listed, and the one place their files may come from.
$script:UsaPwshReleasesApi = 'https://api.github.com/repos/PowerShell/PowerShell/releases?per_page=100'
$script:UsaPwshDownloadRoot = 'https://github.com/PowerShell/PowerShell/releases/download/'

function Test-UsaBannerElevated {
    # In:  nothing
    # Out: $true when this process runs as an administrator
    # Why: the MSI installs for every user, which takes one
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    ([System.Security.Principal.WindowsPrincipal]$identity).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-UsaBannerReleaseHash {
    # In:  a release's hashes.sha256, and the name of a file in that release
    # Out: the file's SHA-256 as the release lists it, uppercase hex; a throw when it lists none
    # Why: read by the line whose words name exactly that file (a leading * marks binary mode),
    #      so neither the column order nor the separator matters, and the .msi is never
    #      taken for a .msix of the same name
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $words = @($line.Trim() -split '\s+' | ForEach-Object { $_.TrimStart('*') })
        if (-not @($words | Where-Object { $_ -eq $Name }).Count) { continue }
        $hash = @($words | Where-Object { $_ -match '^[0-9A-Fa-f]{64}$' })
        if ($hash.Count -eq 1) { return $hash[0].ToUpperInvariant() }
    }
    throw "UsaBanner: the release's hashes.sha256 lists no SHA-256 for ${Name}."
}

function Test-UsaBannerMicrosoftSignature {
    # In:  a file's path
    # Out: $true when it carries a valid Authenticode signature from Microsoft Corporation;
    #      $false where Windows cannot check one
    # Why: hashes.sha256 comes from the same release as the file, so it shows the download is
    #      whole; the signature shows who made it (deploy-usawinssh's Test-MicrosoftSignature)
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Get-Command -Name Get-AuthenticodeSignature -ErrorAction SilentlyContinue)) { return $false }
    $signature = Get-AuthenticodeSignature -FilePath $Path
    ([string]$signature.Status -eq 'Valid') -and ($null -ne $signature.SignerCertificate) -and
        ($signature.SignerCertificate.Subject -match 'O=Microsoft Corporation')
}

function Get-UsaBannerPwshRelease {
    <#
    .SYNOPSIS
    The newest PowerShell 7.6 release's MSI for this machine, as GitHub lists it.
    .DESCRIPTION
    In:  the releases as GitHub's API gives them (asked for when none are given),
         and the machine's architecture.
    Out: Version, Name, Url and HashesUrl: the MSI and its release's
         hashes.sha256.
    7.6 is the long-term release, and the last with an MSI: 7.7 and later ship
    none (D18). A pre-release or a draft is never taken, nor a file from
    anywhere but the PowerShell project's own release downloads. Throws when
    the list cannot be read, and when no 7.6 release has an MSI for this
    machine.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Releases,
        [string]$Architecture = $(if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE })
    )
    $arch = switch ($Architecture) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } default { '' } }
    if (-not $arch) { throw "UsaBanner: PowerShell publishes no MSI for this machine's architecture, $Architecture." }
    if (-not $PSBoundParameters.ContainsKey('Releases')) {
        try { $Releases = Invoke-RestMethod -Uri $script:UsaPwshReleasesApi -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop }
        catch { throw "UsaBanner: GitHub's list of PowerShell releases could not be read ($($_.Exception.Message))." }
    }
    $best = $null
    foreach ($release in $Releases) {
        if ($release.prerelease -or $release.draft) { continue }
        $tag = [regex]::Match([string]$release.tag_name, '^v(7\.6\.\d+)$')
        if (-not $tag.Success) { continue }
        $version = [version]$tag.Groups[1].Value
        if ($best -and $version -le $best.Version) { continue }
        $name = 'PowerShell-{0}-win-{1}.msi' -f $version, $arch
        $msi = @($release.assets | Where-Object { $_.name -eq $name }) | Select-Object -First 1
        $hashes = @($release.assets | Where-Object { $_.name -eq 'hashes.sha256' }) | Select-Object -First 1
        if (-not $msi -or -not $hashes) { continue }
        foreach ($url in [string]$msi.browser_download_url, [string]$hashes.browser_download_url) {
            if (-not $url.StartsWith($script:UsaPwshDownloadRoot, [System.StringComparison]::Ordinal)) {
                throw "UsaBanner: GitHub listed $url for PowerShell $version, which is not one of the PowerShell project's release downloads."
            }
        }
        $best = [pscustomobject]@{ Version = $version; Name = $name; Url = [string]$msi.browser_download_url; HashesUrl = [string]$hashes.browser_download_url }
    }
    if (-not $best) { throw "UsaBanner: GitHub lists no PowerShell 7.6 release with an MSI for $arch." }
    $best
}

function Save-UsaBannerWebFile {
    # In:  an https address, and the file to write
    # Out: nothing; the file, or a throw saying why not
    # Why: -UseBasicParsing, so Windows PowerShell 5.1 needs no Internet Explorer engine (Server
    #      Core has none); and no progress bar, which slows 5.1's downloads
    param([Parameter(Mandatory)][string]$Uri, [Parameter(Mandatory)][string]$OutFile)
    if (-not $Uri.StartsWith('https://', [System.StringComparison]::Ordinal)) { throw "UsaBanner: $Uri is not an https address." }
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
}

function Invoke-UsaBannerPwshMsi {
    # In:  the MSI's path, and the log's
    # Out: msiexec's exit code
    # Why: deploy-usawinssh's install, the same arguments: ADD_PATH puts pwsh on the machine
    #      PATH, REGISTER_MANIFEST its event-log manifest; USE_MU and ENABLE_MU (on by default,
    #      named so it is plain) let Microsoft Update or WSUS bring its patches (D18)
    param([Parameter(Mandatory)][string]$MsiPath, [Parameter(Mandatory)][string]$LogPath)
    $msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'
    $arguments = '/i "{0}" /qn /norestart /l*v "{1}" ADD_PATH=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1' -f $MsiPath, $LogPath
    [int](Start-Process -FilePath $msiexec -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden).ExitCode
}

function Install-UsaBannerPwsh {
    <#
    .SYNOPSIS
    Installs PowerShell 7 for a hand-off that found none, asking first, and
    returns pwsh's path.
    .DESCRIPTION
    In:  the command that needs it.
    Out: pwsh's path once it is installed; nothing under -WhatIf, or when the
         answer is no.
    The newest 7.6 MSI (Get-UsaBannerPwshRelease) and its release's
    hashes.sha256 go to a folder of their own under TEMP. Its SHA-256 must be
    the one hashes.sha256 lists, and it must carry Microsoft's signature, or
    nothing is installed. msiexec installs it for every user, quietly; its log
    stays when it fails, and the folder goes when it works. It asks first: an
    install is more than the command was asked to do. -Confirm:$false answers
    yes, for a script; -WhatIf says what it would do, and does nothing.
    Throws, saying what to do instead, when this PowerShell is not elevated,
    when it cannot ask (no one is at the console), and when a check or the
    install fails.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Command)
    $instead = "install PowerShell 7 yourself (the MSI from https://github.com/PowerShell/PowerShell/releases, or deploy-usawinssh by Group Policy), then run $Command again"
    if (-not (Test-UsaBannerElevated)) {
        throw "UsaBanner: $Command needs PowerShell 7, and none was found. Installing it takes an administrator: run $Command again in an elevated PowerShell, or $instead."
    }
    $release = Get-UsaBannerPwshRelease
    $action = "Download $($release.Name) from GitHub, check its SHA-256 and Microsoft's signature, and install it for every user (msiexec, quiet)"
    try { $go = $PSCmdlet.ShouldProcess("PowerShell $($release.Version)", $action) }
    catch { throw "UsaBanner: $Command needs PowerShell 7, and none was found; this PowerShell cannot ask whether to install it ($($_.Exception.Message)): $instead." }
    if (-not $go) { return }

    $folder = Join-Path ([System.IO.Path]::GetTempPath()) ('UsaBanner-pwsh-' + [guid]::NewGuid().ToString('N'))
    $null = [System.IO.Directory]::CreateDirectory($folder)
    $msi = Join-Path $folder $release.Name
    $hashes = Join-Path $folder 'hashes.sha256'
    $log = Join-Path $folder 'msiexec.log'
    Save-UsaBannerWebFile -Uri $release.HashesUrl -OutFile $hashes
    Save-UsaBannerWebFile -Uri $release.Url -OutFile $msi
    $expected = Get-UsaBannerReleaseHash -Path $hashes -Name $release.Name
    # Never under -WhatIf, where 5.1's Get-FileHash returns nothing: by here the answer was yes.
    $actual = (Get-FileHash -LiteralPath $msi -Algorithm SHA256 -ErrorAction Stop).Hash
    if ($actual -ne $expected) {
        throw "UsaBanner: $($release.Name) has SHA-256 $actual, but its release lists ${expected}: nothing was installed. Its copy is in $folder."
    }
    if (-not (Test-UsaBannerMicrosoftSignature -Path $msi)) {
        throw "UsaBanner: $($release.Name) carries no valid Microsoft signature that this machine can check: nothing was installed. Its copy is in $folder."
    }
    $code = Invoke-UsaBannerPwshMsi -MsiPath $msi -LogPath $log
    # 0: installed; 3010: installed, and Windows asks for a restart to finish (Windows Installer's codes).
    if ($code -ne 0 -and $code -ne 3010) {
        throw "UsaBanner: installing PowerShell $($release.Version) failed: msiexec exit code $code. Its log is $log."
    }
    $pwsh = Find-UsaBannerPwsh
    if (-not $pwsh) { throw "UsaBanner: PowerShell $($release.Version) installed, but pwsh is not where its MSI puts it. msiexec's log is $log." }
    [System.IO.Directory]::Delete($folder, $true)
    $pwsh
}
