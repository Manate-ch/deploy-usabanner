# AdDescription.ps1 - a host's tier and role from its computer object's AD
# Description (docs/DECISIONS.md, D29), as today's banner reads them. The
# periodic job reads the Description and caches it, one line, in the banner's
# own folder: linux/ad-description.sh on Linux, Update-UsaBannerAdDescription
# on Windows. The banners read only the cache, so a domain controller that
# answers slowly costs no login anything.
#
#   +-----------------------------+----------+---------------------------+
#   | AD Description              | Tier     | Role                      |
#   +-----------------------------+----------+---------------------------+
#   | PROD : Web front end        | PROD     | Web front end             |
#   | dev: build agents           | DEV-TEST | build agents              |
#   | QA: test rig                | none     | test rig                  |
#   | Web front end               | none     | Web front end             |
#   +-----------------------------+----------+---------------------------+
#
# QA is no tier this banner has, so it gives none. The configuration wins
# where it says something: an environment other than UNSET, and a role that
# is not empty. Where neither gives a tier, it is UNSET.
#
# Get-UsaBannerAdComputerDescription, which PowerShell logs whole at each
# import, is in AdDescription.Logged.ps1 (docs/DECISIONS.md, D30).

# Today's tier names, and the tier each is in this banner. STAGE is LAB, the
# nearest by what it holds.
$script:UsaAdTierNames = @{
    'PROD' = 'PROD'; 'LAB' = 'LAB'; 'PUB' = 'PUB'; 'DEV-TEST' = 'DEV-TEST'
    'DEV' = 'DEV-TEST'; 'TEST' = 'DEV-TEST'; 'STAGE' = 'LAB'
}

function ConvertFrom-UsaBannerAdDescription {
    <#
    .SYNOPSIS
    An AD Description as a tier and a role.
    .DESCRIPTION
    In:  the Description, as AD holds it.
    Out: @{ Tier; Role; Prefix }. The part before the first colon is a
         prefix when it is a letter, then letters and hyphens, the blanks
         around it not counting: Prefix is it in upper case, Tier the tier
         it names ('' for a name the table above lacks), and Role the rest.
         Without a prefix, the Description is the role, and Prefix and Tier
         are ''.
    Only the first line counts. The role is drawn in a 64-column box, which
    awk measures a byte to a column on Linux, so it is made printable ASCII
    first: a blank becomes a space, a letter loses its accent, and any other
    character becomes ?.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyString()][string]$Text = '')
    $line = ($Text -split '[\r\n]', 2)[0]
    $plain = -join @(foreach ($c in $line.Normalize([System.Text.NormalizationForm]::FormD).ToCharArray()) {
            if ([char]::IsWhiteSpace($c)) { ' ' }
            elseif ([int]$c -ge 32 -and [int]$c -le 126) { $c }
            # An accent is a mark of its own once the letter is decomposed;
            # the second half of a surrogate pair goes, so a pair is one ?.
            elseif ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -eq 'NonSpacingMark' -or [char]::IsLowSurrogate($c)) { }
            else { '?' }
        })
    if ($plain -match '^ *([A-Za-z][A-Za-z-]*) *:(.*)$') {
        $prefix = $Matches[1].ToUpperInvariant()
        $tier = if ($script:UsaAdTierNames.ContainsKey($prefix)) { $script:UsaAdTierNames[$prefix] } else { '' }
        return @{ Tier = $tier; Role = $Matches[2].Trim(); Prefix = $prefix }
    }
    @{ Tier = ''; Role = $plain.Trim(); Prefix = '' }
}

function Resolve-UsaBannerHostConfig {
    <#
    .SYNOPSIS
    A configuration with this host's tier and role in it: its own where it
    sets them, else the AD Description's (D29).
    .DESCRIPTION
    In:  the configuration, and the host's cached AD Description ('' for
         none: Read-UsaBannerAdDescription).
    Out: @{ Config; Tier; TierFrom; Role; RoleFrom }: a copy of the
         configuration whose environment and role are the host's, the two
         again, and where each came from: configuration, AD Description, or
         '' for neither. An environment other than UNSET wins, and so does a
         role that is not empty; each is decided alone. With neither, the
         tier is UNSET and the role ''.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [AllowEmptyString()][string]$Description = ''
    )
    $ad = ConvertFrom-UsaBannerAdDescription -Text $Description
    $tier = [string]$Config['environment']
    $tierFrom = 'configuration'
    if ($tier -in '', 'UNSET') {
        $tier = if ($ad.Tier) { $ad.Tier } else { 'UNSET' }
        $tierFrom = if ($ad.Tier) { 'AD Description' } else { '' }
    }
    $role = ([string]$Config['role']).Trim()
    $roleFrom = 'configuration'
    if (-not $role) {
        $role = $ad.Role
        $roleFrom = if ($role) { 'AD Description' } else { '' }
    }
    $copy = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    foreach ($key in $Config.Keys) { $copy[$key] = $Config[$key] }
    $copy['environment'] = $tier
    $copy['role'] = $role
    @{ Config = $copy; Tier = $tier; TierFrom = $tierFrom; Role = $role; RoleFrom = $roleFrom }
}

function Read-UsaBannerAdDescription {
    <#
    .SYNOPSIS
    This host's AD Description, as the periodic job last cached it.
    .DESCRIPTION
    In:  the cache; by default ad-description in the banner's own folder.
    Out: its first line, '' for a Description that is empty; $null when
         there is no cache, or this user cannot read it: then neither the
         tier nor the role comes from AD.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([string]$Path = (Get-UsaBannerDataPath -Name 'ad-description'))
    if (-not [System.IO.File]::Exists($Path)) { return $null }
    try { $lines = [System.IO.File]::ReadAllLines($Path) }
    catch [System.UnauthorizedAccessException], [System.IO.IOException] { return $null }
    if ($lines.Count) { $lines[0] } else { '' }
}

function Update-UsaBannerAdDescription {
    <#
    .SYNOPSIS
    The periodic job's read of this host's AD Description, on Windows.
    .DESCRIPTION
    In:  the cache; by default ad-description in the banner's own folder.
    Out: nothing. The Description's first line goes to the cache, an empty
         line for none, so a Description someone cleared clears the role;
         the file is written beside itself and moved into place. Where AD
         cannot be asked (no domain, no domain controller answering), the
         cache stays as it was, so an outage never blanks the tier or the
         role, and a warning says why. linux/ad-description.sh is its twin.
    #>
    [CmdletBinding()]
    param([string]$Path = (Get-UsaBannerDataPath -Name 'ad-description' -OnWindows $true))
    try { $text = Get-UsaBannerAdComputerDescription }
    catch {
        Write-Warning "UsaBanner: the AD Description was not read, so the last one is kept: $($_.Exception.Message)"
        return
    }
    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    Save-UsaBannerJobFile -Path $Path -Text "$(($text -split '[\r\n]', 2)[0])`n"
}
