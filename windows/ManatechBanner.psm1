# ManatechBanner.psm1 - the Manatech login banner for Windows Server: the
# same art, host panel and health line as the Linux update-motd.d scripts,
# drawn from the same data files (manatech.art, colors.tsv, schema-names.tsv),
# which sit next to this module once installed.
#
#   Show-ManatechBanner      called by the all-users profile: gathers, formats
#                            and writes, once per session; -SshOnly skips
#                            anything that is not an interactive SSH login
#   Get-ManatechBannerText   gathers and formats; returns the text
#   Enter-ManatechPSSession  PS-Remoting has no login banner, so this asks the
#                            remote host for its banner text, prints it here,
#                            then enters the session
#   Get-ManatechHostFact     reads this host (CIM, registry, services); Windows only
#   Format-ManatechBanner    facts in, text out; reads only the data files, so
#                            it runs and is tested on any OS
#
# The source is ASCII on purpose: Windows PowerShell 5.1 reads a file without
# a BOM in the ANSI code page, so each non-ASCII glyph is built from its code
# point instead of written literally.

Set-StrictMode -Version 3.0

$script:Esc = [string][char]27
$script:W = 62   # inner width of the panel; the whole panel (64) fits 80 columns

function Get-ManatechConfig {
    <#
    .SYNOPSIS
    Banner settings: the defaults, overridden by motd.psd1 in DataPath, with
    EnvName and Role filled from this computer's AD Description where
    motd.psd1 leaves them unset.
    .DESCRIPTION
    ad-description.txt in DataPath is the cached Description (written by
    Install-ManatechBanner.ps1 -AdDescription). "<ENV>: <role>" gives both;
    a Description without a letters-only prefix is the role alone. An
    EnvName other than UNSET, or a non-empty Role, in motd.psd1 wins.
    EnvSource and RoleSource say where each came from ('' = nowhere).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$DataPath)

    $config = @{
        EnvName       = 'UNSET'
        EnvShow       = @('strip', 'row')
        Role          = ''
        Watch         = @('sshd')
        Color         = 'truecolor'
        Glyphs        = 'unicode'
        DiskWarn      = 85
        MemWarn       = 90
        CpuWarn       = 85
        BorderBy      = 'type'
        Badge         = 'site-vlan'
        IfaceHide     = '^(vEthernet|Loopback|isatap)'
        ServiceIgnore = @()   # on top of $script:ServiceStopsByDesign
    }
    $file = Join-Path $DataPath 'motd.psd1'
    if (Test-Path -LiteralPath $file) {
        $local = Import-PowerShellDataFile -LiteralPath $file
        foreach ($key in $local.Keys) { $config[$key] = $local[$key] }
    }

    $desc = ''
    $adFile = Join-Path $DataPath 'ad-description.txt'
    if (Test-Path -LiteralPath $adFile) { $desc = [string](@(Get-Content -LiteralPath $adFile -TotalCount 1) -join '') }
    $adEnv = ''
    $adRole = $desc.Trim()
    if ($desc -match '^\s*([A-Za-z]+)\s*:(.*)$') { $adEnv = $Matches[1].ToUpper(); $adRole = $Matches[2].Trim() }

    $config.EnvSource = ''
    if ($config.EnvName -ne 'UNSET') { $config.EnvSource = 'motd.psd1' }
    elseif ($adEnv) { $config.EnvName = $adEnv; $config.EnvSource = 'AD Description' }
    $config.RoleSource = ''
    if ($config.Role) { $config.RoleSource = 'motd.psd1' }
    elseif ($adRole) { $config.Role = $adRole; $config.RoleSource = 'AD Description' }
    $config
}

function Get-ManatechGlyph {
    param([string]$Set)
    if ($Set -eq 'ascii') {
        return @{ TL = '+'; TR = '+'; BL = '+'; BR = '+'; H = '-'; V = '|'
            Full = '#'; Empty = '.'; Ok = '[ok]'; Warn = '[!!]'; Bad = '[XX]'; Sep = '-' }
    }
    @{
        TL = [string][char]0x256D; TR = [string][char]0x256E; BL = [string][char]0x2570; BR = [string][char]0x256F
        H = [string][char]0x2500; V = [string][char]0x2502; Full = [string][char]0x2501; Empty = [string][char]0x2500
        Ok = [string][char]0x2714; Warn = [string][char]0x25B2; Bad = [string][char]0x2716; Sep = [string][char]0x00B7
    }
}

# ConvertTo-ManatechSgr R G B BASIC MODE [-Background] - the escape for an RGB
# colour in MODE (truecolor, 256, 16, none). BASIC is the SGR code used in
# 16-colour mode. The same arithmetic as colour.awk, so both OSes match.
function ConvertTo-ManatechSgr {
    param([int]$R, [int]$G, [int]$B, [string]$Basic, [string]$Mode, [switch]$Background)
    $layer = if ($Background) { 48 } else { 38 }
    switch ($Mode) {
        'truecolor' { return "$Esc[$layer;2;$R;$G;${B}m" }
        '256' {
            $i = 16 + 36 * [math]::Floor(($R * 5 + 127) / 255) + 6 * [math]::Floor(($G * 5 + 127) / 255) + [math]::Floor(($B * 5 + 127) / 255)
            return "$Esc[$layer;5;${i}m"
        }
        '16' { return "$Esc[${Basic}m" }
        default { return '' }
    }
}

function Get-ManatechMix {
    param([double]$From, [double]$To, [double]$T)
    [int][math]::Floor($From + ($To - $From) * $T + 0.5)
}

function Measure-ManatechWidth {
    param([string]$Text)
    ($Text -replace "$Esc\[[0-9;]*m", '').Length
}

# Read-ManatechTable PATH - each non-comment line of a TSV file, as a string array.
function Read-ManatechTable {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(#|$)') { continue }
        , ($line -split "`t")
    }
}

function Format-ManatechGradient {
    param([string]$Text, [int[]]$From, [int[]]$To, [string]$Basic, [string]$Mode)
    if ($Mode -eq '16') { return "$Esc[${Basic}m$Text$Esc[0m" }
    if ($Mode -ne 'truecolor' -and $Mode -ne '256') { return $Text }
    $n = $Text.Length
    $sb = [System.Text.StringBuilder]::new()
    for ($i = 0; $i -lt $n; $i++) {
        $t = if ($n -gt 1) { $i / ($n - 1) } else { 0 }
        $sgr = ConvertTo-ManatechSgr (Get-ManatechMix $From[0] $To[0] $t) (Get-ManatechMix $From[1] $To[1] $t) (Get-ManatechMix $From[2] $To[2] $t) $Basic $Mode
        [void]$sb.Append($sgr).Append($Text[$i])
    }
    [void]$sb.Append("$Esc[0m")
    $sb.ToString()
}

# Format-ManatechArt PATH MODE - the art file in colour, as art.awk draws it:
# the moon fades pale cyan to deep blue over all lines, the emblem (after @y)
# pale gold to orange over its own lines.
function Format-ManatechArt {
    param([string]$Path, [string]$Mode)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = @(Get-Content -LiteralPath $Path)
    $n = $lines.Count
    $y = @(for ($i = 0; $i -lt $n; $i++) { if ($lines[$i].Contains('@y')) { $i } })
    $rst = if ($Mode -eq 'none') { '' } else { "$Esc[0m" }
    for ($i = 0; $i -lt $n; $i++) {
        $t = if ($n -gt 1) { $i / ($n - 1) } else { 0 }
        $c = ConvertTo-ManatechSgr (Get-ManatechMix 175 30 $t) (Get-ManatechMix 235 95 $t) (Get-ManatechMix 255 210 $t) '0;36' $Mode
        $u = if ($y.Count -gt 1) { ($i - $y[0]) / ($y[-1] - $y[0]) } else { 0 }
        $yc = ConvertTo-ManatechSgr 255 (Get-ManatechMix 238 135 $u) (Get-ManatechMix 150 20 $u) '1;33' $Mode
        $c + $lines[$i].Replace('@c', $c).Replace('@y', $yc) + $rst
    }
}

function Resolve-ManatechHostName {
    <#
    .SYNOPSIS
    Decodes a host name with the naming schema: <site:2><type><subtype><os>-<name><number>.
    The site is two characters, site letter then sub-site letter or "-"
    (h- = HQ, cw = Cloud West in the example rows).
    .OUTPUTS
    An object with Codes (site, type, subtype, os letters) and Decoded
    ("HQ / Virtual / Server / Windows"), or $null for a name outside the schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Schema
    )
    $short = ($Name -split '\.')[0].ToLower()
    if ($short -notmatch '^([a-z0-9][a-z0-9-])([a-z0-9])([a-z0-9])([a-z0-9])-.*[0-9]$') { return $null }
    $codes = [ordered]@{ site = $Matches[1]; type = $Matches[2]; subtype = $Matches[3]; os = $Matches[4] }
    $names = foreach ($field in $codes.Keys) {
        $entry = $Schema["$field|$($codes[$field])"]
        if ($entry) { $entry.Name } else { '?' }
    }
    $site = $Schema["site|$($codes.site)"]
    [pscustomobject]@{
        Codes    = $codes
        Decoded  = $names -join ' / '
        SiteName = if ($site) { $site.Name } else { '' }
    }
}

function Find-ManatechVlan {
    <#
    .SYNOPSIS
    The VLAN an IPv4 address is in, from vlans.tsv (the VLAN table); the
    longest matching prefix wins. Same rule as vlan.awk.
    .OUTPUTS
    @{ Id; Site; Mini; Short; Cidr; Colour } or $null.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Address,
        [Parameter(Mandatory)][string]$Path
    )
    $toNumber = {
        param($text)
        $ip = $null
        if (-not [System.Net.IPAddress]::TryParse($text, [ref]$ip) -or $ip.AddressFamily -ne 'InterNetwork') { return $null }
        $b = $ip.GetAddressBytes()
        [uint64]$b[0] * 16777216 + [uint64]$b[1] * 65536 + [uint64]$b[2] * 256 + [uint64]$b[3]
    }
    $addr = & $toNumber $Address
    if ($null -eq $addr) { return $null }
    $best = $null
    $bestBits = -1
    foreach ($f in Read-ManatechTable $Path) {
        if ($f.Count -lt 6) { continue }
        $net, $bits = $f[1] -split '/'
        $bits = [int]$bits
        $size = [uint64][math]::Pow(2, 32 - $bits)
        $n = & $toNumber $net
        if ($null -ne $n -and [math]::Floor($addr / $size) -eq [math]::Floor($n / $size) -and $bits -gt $bestBits) {
            $bestBits = $bits
            $best = @{ Id = $f[0]; Site = $f[3]; Mini = $f[4]; Short = $f[5]; Cidr = $f[1]; Colour = $f[2] }
        }
    }
    $best
}

function Format-ManatechBanner {
    <#
    .SYNOPSIS
    Renders the banner from a facts table; returns one string per line.
    .DESCRIPTION
    Fact keys: HostName, PrimaryIp, Os, Uptime ([timespan]), CpuPct, Cores, MemPct, MemText,
    DiskName, DiskPct, DiskText, Sessions, Time, Ipv4 (@{Name; Address}
    list), Problems (@{Level = 'bad'|'warn'; Text} list), Checked (names).
    Get-ManatechHostFact produces exactly this shape.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][hashtable]$Fact,
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][string]$DataPath
    )
    $mode = $Config.Color
    $g = Get-ManatechGlyph -Set $Config.Glyphs
    $rst = if ($mode -eq 'none') { '' } else { "$Esc[0m" }
    $bold = if ($mode -eq 'none') { '' } else { "$Esc[1m" }
    $cLabel = ConvertTo-ManatechSgr 120 200 235 '0;36' $mode
    $cDim = ConvertTo-ManatechSgr 110 120 135 '0;90' $mode
    $cGood = ConvertTo-ManatechSgr 110 210 140 '0;32' $mode
    $cWarn = ConvertTo-ManatechSgr 255 190 60 '0;33' $mode
    $cBad = ConvertTo-ManatechSgr 240 80 80 '1;31' $mode

    $colors = @{}        # by name, for the schema's and envs.tsv's colour columns
    $colorByCode = @{}   # by 0-F code, for the VLAN colour code
    foreach ($f in Read-ManatechTable (Join-Path $DataPath 'colors.tsv')) {
        if (-not $colors.ContainsKey($f[0])) { $colors[$f[0]] = $f }
        $colorByCode[$f[1]] = $f
    }

    # Environment colour: envs.tsv names a colors.tsv colour for EnvName, or
    # the * row for any other; Grey if neither resolves. It draws the strip,
    # the env tag and a badge whose VLAN has no colour code, with black or
    # white text by brightness, and the border for a name outside the schema.
    $envColour = $null
    $envRows = @{}
    foreach ($f in Read-ManatechTable (Join-Path $DataPath 'envs.tsv')) { if ($f.Count -ge 2) { $envRows[$f[0]] = $f[1] } }
    $envColourName = if ($envRows.ContainsKey($Config.EnvName)) { $envRows[$Config.EnvName] } elseif ($envRows.ContainsKey('*')) { $envRows['*'] } else { '' }
    if ($envColourName -and $colors.ContainsKey($envColourName)) { $envColour = $colors[$envColourName] }
    $er, $eg, $eb, $ebasic = if ($envColour) { [int]$envColour[2], [int]$envColour[3], [int]$envColour[4], [int]$envColour[5] } else { 140, 145, 155, 90 }
    $envBg = ConvertTo-ManatechSgr $er $eg $eb ([string]($ebasic + 10)) $mode -Background
    $envFg = if (($er * 299 + $eg * 587 + $eb * 114) / 1000 -gt 140) { ConvertTo-ManatechSgr 20 20 20 '30' $mode } else { ConvertTo-ManatechSgr 255 255 255 '97' $mode }
    $edge = ConvertTo-ManatechSgr $er $eg $eb ([string]$ebasic) $mode

    # Naming schema: letter tints, decoded row, and the border colour.
    $schema = @{}
    foreach ($f in Read-ManatechTable (Join-Path $DataPath 'schema-names.tsv')) {
        $schema["$($f[0])|$($f[1].ToLower())"] = @{ Name = $f[2]; Color = $f[3] }
    }
    $tint = {
        param($field, $code)
        $entry = $schema["$field|$code"]
        if ($entry -and $colors.ContainsKey($entry.Color)) {
            $c = $colors[$entry.Color]
            ConvertTo-ManatechSgr ([int]$c[2]) ([int]$c[3]) ([int]$c[4]) $c[5] $mode
        } else { '' }
    }
    $name = $Fact.HostName
    $id = Resolve-ManatechHostName -Name $name -Schema $schema
    if ($id -and $id.Codes.Contains($Config.BorderBy)) {
        $e = & $tint $Config.BorderBy $id.Codes[$Config.BorderBy]
        if ($e) { $edge = $e }
    }

    # Badge: "<site> - <vlan>-<mini>" (HQ - 40-Servers) in the VLAN's colour (Badge = 'site-vlan'; the
    # site from the host name, else from the VLAN row). A VLAN without a
    # colour code keeps the environment colour; Badge = 'env', or nothing
    # known, shows EnvName.
    $vlan = $null
    if ($Fact.ContainsKey('PrimaryIp')) { $vlan = Find-ManatechVlan -Address $Fact.PrimaryIp -Path (Join-Path $DataPath 'vlans.tsv') }
    $site = if ($id -and $id.SiteName) { $id.SiteName } elseif ($vlan) { $vlan.Site } else { '' }
    $badgeText = $Config.EnvName
    $badgeColour = "$envBg$envFg"
    if ($Config.Badge -ne 'env' -and ($site -or $vlan)) {
        $vlanName = if ($vlan) { "$($vlan.Id)-$($vlan.Mini)" } else { '' }
        $badgeText = if ($vlan -and $site) { "$site - $vlanName" } elseif ($vlan) { $vlanName } else { $site }
        $c = if ($vlan -and $vlan.Colour) { $colorByCode[$vlan.Colour] }
        if ($c) {
            $r, $gr, $b, $basic = [int]$c[2], [int]$c[3], [int]$c[4], [int]$c[5]
            $ink = if (($r * 299 + $gr * 587 + $b * 114) / 1000 -gt 140) { @(20, 20, 20, '30') } else { @(255, 255, 255, '97') }
            $badgeColour = (ConvertTo-ManatechSgr $r $gr $b ([string]($basic + 10)) $mode -Background) + (ConvertTo-ManatechSgr $ink[0] $ink[1] $ink[2] $ink[3] $mode)
        }
    }

    # Title and badge share the top border: when both do not fit, the domain
    # goes first, then the badge text is cut with "~".
    $shown = $name
    if (2 + ($shown.Length + 2) + ($badgeText.Length + 2) -ge $W) { $shown = ($name -split '\.')[0] }
    $max = $W - 3 - ($shown.Length + 2)
    $badge = " $badgeText "
    if ($badge.Length -gt $max) { $badge = ' ' + $badgeText.Substring(0, [math]::Max(0, $max - 3)) + '~ ' }
    if ($id) {
        $letter = {
            param($field, $i)
            $e = & $tint $field $id.Codes[$field]
            if ($e) { "$e$($shown[$i])$rst$bold" } else { [string]$shown[$i] }
        }
        $title = $bold + (& $letter site 0) + (& $letter site 1) + (& $letter type 2) + (& $letter subtype 3) + (& $letter os 4) + $shown.Substring(5) + $rst
    } else {
        $title = "$bold$shown$rst"
    }

    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Format-ManatechArt -Path (Join-Path $DataPath 'manatech.art') -Mode $mode) { $out.Add($line) }
    $out.Add('')
    $out.Add('  Welcome to ' + (Format-ManatechGradient 'Manatech' @(120, 200, 255) @(255, 200, 80) '1;34' $mode))
    $out.Add('')

    # Environment strip (EnvShow contains 'strip'): the full panel width in the
    # environment's colour, the name spaced out like the pre-login M A N A T E C H.
    if (@($Config.EnvShow) -contains 'strip') {
        $word = ($Config.EnvName.ToCharArray() -join ' ')
        $pad = [math]::Max(0, $W + 2 - $word.Length)
        $left = [math]::Floor($pad / 2)
        $out.Add("$bold$envBg$envFg$(' ' * $left)$word$(' ' * ($pad - $left))$rst")
    }

    $fill = [math]::Max(1, $W - 2 - ($shown.Length + 2) - $badge.Length)
    $out.Add("$edge$($g.TL)$($g.H)$rst $title $edge$($g.H * $fill)$rst$bold$badgeColour$badge$rst$edge$($g.H)$($g.TR)$rst")

    $vw = $W - 13
    $row = {
        param($label, $text)
        if ($text -notmatch $Esc -and $text.Length -gt $vw) { $text = $text.Substring(0, $vw - 1) + '~' }
        $pad = [math]::Max(0, $vw - (Measure-ManatechWidth $text))
        $out.Add("$edge$($g.V)$rst  $cLabel$($label.PadRight(9))$rst $text$(' ' * $pad) $edge$($g.V)$rst")
    }
    $level = {
        param($pct, $at)
        if ($pct -ge 95) { $cBad } elseif ($pct -ge $at) { $cWarn } else { $cGood }
    }
    $bar = {
        param($pct, $at)
        $n = [int][math]::Min(10, [math]::Floor(($pct + 5) / 10))
        "$(& $level $pct $at)$($g.Full * $n)$cDim$($g.Empty * (10 - $n))$rst"
    }

    if ($id) { & $row 'schema' $id.Decoded }
    if ($vlan) { & $row 'vlan' "$($vlan.Id)  $($vlan.Short)  ($($vlan.Cidr))" }
    # env row (EnvShow contains 'row'): the name as a tag in its colour, which
    # stays readable for any colour (Black is charcoal), and where it came from.
    if (@($Config.EnvShow) -contains 'row') {
        $src = if ($Config['EnvSource']) { "from $($Config['EnvSource'])" } else { 'none: prefix the AD Description' }
        & $row 'env' "$bold$envBg$envFg $($Config.EnvName) $rst  $cDim$src$rst"
    }
    & $row 'os' $Fact.Os
    # The role comes from motd.psd1 or the AD Description; with neither, the
    # row asks for the Description instead of disappearing.
    if ($Config.Role) { & $row 'role' $Config.Role }
    else { & $row 'role' "$cWarn(set this computer's AD Description)$rst" }
    $up = $Fact.Uptime
    $ut = '{0}h {1}m' -f $up.Hours, $up.Minutes
    if ($up.Days -gt 0) { $ut = "$($up.Days)d $ut" }
    # CpuPct is $null when the performance counters could not be read.
    $cpuText = if ($null -eq $Fact.CpuPct) { "$cDim-$rst" } else { "$(& $level $Fact.CpuPct $Config.CpuWarn)$($Fact.CpuPct)%$rst" }
    & $row 'uptime' "$ut   ${cDim}cpu$rst $cpuText $cDim/ $($Fact.Cores) cores$rst"
    & $row 'memory' "$(& $bar $Fact.MemPct $Config.MemWarn) $(& $level $Fact.MemPct $Config.MemWarn)$($Fact.MemPct)%$rst  $($Fact.MemText)"
    & $row "disk $($Fact.DiskName)" "$(& $bar $Fact.DiskPct $Config.DiskWarn) $(& $level $Fact.DiskPct $Config.DiskWarn)$($Fact.DiskPct)%$rst  $($Fact.DiskText)"
    & $row 'sessions' $Fact.Sessions
    & $row 'time' $Fact.Time
    $label = 'ipv4'
    if (-not $Fact.Ipv4) { & $row $label 'none' }
    foreach ($ip in $Fact.Ipv4) {
        & $row $label ('{0,-10} {1}' -f $ip.Name, $ip.Address)
        $label = ''
    }
    $out.Add("$edge$($g.BL)$($g.H * $W)$($g.BR)$rst")

    $out.Add('')
    if (@($Fact.Problems).Count) {
        foreach ($p in $Fact.Problems) {
            $mark = if ($p.Level -eq 'bad') { "$cBad$($g.Bad)" } else { "$cWarn$($g.Warn)" }
            $out.Add("  $mark$rst $($p.Text)")
        }
    } else {
        $out.Add("  $cGood$($g.Ok) all clear$rst   $cDim$($Fact.Checked -join " $($g.Sep) ")$rst")
    }
    $out.Add('')
    $out.ToArray()
}

# Invoke-ManatechNative EXE [ARGS] - the standard output lines of a console
# tool. Its exit code is left in $LASTEXITCODE; its standard error is dropped
# and can never stop the caller. quser writes "No User exists for *" to
# standard error whenever nobody is logged on, and Windows PowerShell 5.1
# turns each redirected standard-error line into an error record. Under
# ErrorActionPreference Stop that record ends the run - and a script started
# with powershell.exe -File, such as the GPO task's Sync-ManatechBanner.ps1,
# sets its preference for the whole session, this module included.
function Invoke-ManatechNative {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$ArgumentList = @())
    $ErrorActionPreference = 'Continue'
    & $FilePath @ArgumentList 2>$null
}

# Auto-start services that stop by design, ignored on every host on top of
# its ServiceIgnore. Most are trigger-start, which Get-ManatechStoppedService
# leaves out anyway; InventorySvc is delayed-start and was stopped on every
# Server 2025 host checked, healthy lab nodes included (2026-10-03).
$script:ServiceStopsByDesign = @('InventorySvc', 'gupdate', 'edgeupdate', 'sppsvc', 'RemoteRegistry', 'MapsBroker', 'CDPSvc', 'tiledatamodelsvc', 'WbioSrvc')

# The probes Get-ManatechHostFact makes, one function each, so
# Measure-ManatechBanner.ps1 times exactly what a login runs. Each was chosen
# by timing on a lab Server 2025 node in a fresh process, which is what every
# login is (2026-10-03).

# Get-ManatechCpuSample - the raw counters behind CPU %: the processors' idle
# time (PERF_100NSEC_TIMER_INV, averaged over all of them for _Total), the
# counter's clock, and this process's own processor time, all in 100 ns
# units. $null when the performance counters cannot be read.
function Get-ManatechCpuSample {
    $s = Get-CimInstance -ClassName Win32_PerfRawData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
    if (-not $s) { return $null }
    @{
        Idle  = [double]$s.PercentProcessorTime
        Clock = [double]$s.Timestamp_Sys100NS
        Own   = [double][System.Diagnostics.Process]::GetCurrentProcess().TotalProcessorTime.Ticks
    }
}

# Get-ManatechCpuPct FROM TO CORES - how busy the processors were between two
# samples, in whole percent, without what this process used meanwhile (it
# should be idle in the window; this keeps a stray .NET background thread
# from counting). $null without two samples.
function Get-ManatechCpuPct {
    param($From, $To, [int]$Cores)
    if ($null -eq $From -or $null -eq $To -or $Cores -lt 1) { return $null }
    $span = $To.Clock - $From.Clock
    if ($span -le 0) { return $null }
    $busy = 1 - ($To.Idle - $From.Idle) / $span
    $own = ($To.Own - $From.Own) / ($span * $Cores)
    # 1.0 and 0.0, not 1 and 0: an integer first argument makes PowerShell
    # pick Math.Min(int, int), which truncates 0.016 to 0.
    [int][math]::Round(100 * [math]::Min(1.0, [math]::Max(0.0, $busy - $own)))
}

# Get-ManatechInterface [HIDE] - each interface that is up and has IPv4, as
# @{ Name; Address = 'a.b.c.d/n ...' }: loopback and link-local left out, and
# interfaces whose name matches the regex HIDE. Through .NET, not
# Get-NetIPAddress, whose module Windows PowerShell 5.1 loads at its first
# call: 0.6 s of every login.
function Get-ManatechInterface {
    param([string]$Hide)
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
        if ($Hide -and $nic.Name -match $Hide) { continue }
        $addresses = @(foreach ($u in $nic.GetIPProperties().UnicastAddresses) {
            if ($u.Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
            $text = $u.Address.ToString()
            if ($text -match '^(127\.|169\.254\.)') { continue }
            "$text/$($u.PrefixLength)"
        })
        if ($addresses.Count) { @{ Name = $nic.Name; Address = $addresses -join ' ' } }
    }
}

# Get-ManatechPrimaryIp - the IPv4 address this host would send from on its
# default route: a UDP socket asked to "connect" consults the routing table
# and sends nothing (192.0.2.1 is a documentation address). '' with no route.
function Get-ManatechPrimaryIp {
    $sock = [System.Net.Sockets.Socket]::new([System.Net.Sockets.AddressFamily]::InterNetwork, [System.Net.Sockets.SocketType]::Dgram, [System.Net.Sockets.ProtocolType]::Udp)
    try { $sock.Connect('192.0.2.1', 9); [string]$sock.LocalEndPoint.Address } catch { '' } finally { $sock.Dispose() }
}

# Get-ManatechStoppedService [IGNORE] - the names of Automatic services that
# are not running, less IGNORE, less $script:ServiceStopsByDesign, and less
# trigger-start services: Windows starts those when their trigger fires and
# stops them when idle, so stopped is their normal state. Through .NET, not
# Win32_Service: a third of the time.
function Get-ManatechStoppedService {
    param([string[]]$Ignore = @())
    Add-Type -AssemblyName System.ServiceProcess
    $skip = @($script:ServiceStopsByDesign) + @($Ignore)
    foreach ($s in [System.ServiceProcess.ServiceController]::GetServices()) {
        if ($s.StartType -ne [System.ServiceProcess.ServiceStartMode]::Automatic) { continue }
        if ($s.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running) { continue }
        if ($skip -contains $s.ServiceName) { continue }
        if (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.ServiceName)\TriggerInfo") { continue }
        $s.ServiceName
    }
}

function Get-ManatechHostFact {
    <#
    .SYNOPSIS
    Reads this Windows host into the facts table Format-ManatechBanner takes,
    including the health checks: stopped auto-start services (minus
    ServiceIgnore, the services that stop by design and trigger-start ones),
    fixed disks at DiskWarn, memory at MemWarn, each Watch service, the
    Windows Time source, and a pending reboot.
    .NOTES
    Checked lists only the checks that actually produced an answer: when the
    time source cannot be parsed (w32tm output is localised), "clock" is left
    out instead of being reported as passing.
    CPU % is read last, over a quiet window of 200 ms; Win32_Processor's
    LoadPercentage sampled for a whole second, a third of every login.
    $null when it cannot be measured.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][hashtable]$Config)

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $name = $env:COMPUTERNAME.ToLower()
    if ($cs.PartOfDomain) { $name = "$name.$($cs.Domain.ToLower())" }

    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $ubr = if ($cv -and $cv.PSObject.Properties['UBR']) { ".$($cv.UBR)" } else { '' }

    $memTotal = [double]$os.TotalVisibleMemorySize
    $memUsed = $memTotal - [double]$os.FreePhysicalMemory
    $memPct = [int][math]::Floor(100 * $memUsed / $memTotal)

    $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [System.IO.DriveType]::Fixed -and $_.IsReady -and $_.TotalSize })
    $sys = @($drives | Where-Object { $_.Name.TrimEnd('\') -eq $env:SystemDrive })
    $sysPct = if ($sys.Count) { [int][math]::Floor(100 * ($sys[0].TotalSize - $sys[0].TotalFreeSpace) / $sys[0].TotalSize) } else { 0 }

    # quser lists console and RDP logons; an SSH logon is not a Remote Desktop
    # session, so it does not appear here.
    $users = @()
    if (Get-Command -Name quser.exe -ErrorAction SilentlyContinue) {
        $users = @(Invoke-ManatechNative quser.exe | Select-Object -Skip 1 | ForEach-Object { (($_.Trim() -replace '^>', '') -split '\s+')[0] } | Sort-Object -Unique)
    }

    $ipv4 = @(Get-ManatechInterface -Hide $Config.IfaceHide)

    # Primary address: the one the default route sends from, else the first
    # one listed.
    $primary = Get-ManatechPrimaryIp
    if (-not $primary -and $ipv4.Count) { $primary = ($ipv4[0].Address -split '[/ ]')[0] }

    $problems = [System.Collections.Generic.List[hashtable]]::new()
    $checked = [System.Collections.Generic.List[string]]::new()

    $stopped = @(Get-ManatechStoppedService -Ignore $Config.ServiceIgnore)
    if ($stopped.Count) { $problems.Add(@{ Level = 'bad'; Text = "$($stopped.Count) auto-start service(s) stopped: $($stopped -join ' ')" }) }
    $checked.Add('services')

    foreach ($d in $drives) {
        $pct = [int][math]::Floor(100 * ($d.TotalSize - $d.TotalFreeSpace) / $d.TotalSize)
        if ($pct -ge $Config.DiskWarn) { $problems.Add(@{ Level = $(if ($pct -ge 95) { 'bad' } else { 'warn' }); Text = "$($d.Name.TrimEnd('\')) is $pct% full" }) }
    }
    $checked.Add("disks <$($Config.DiskWarn)%")

    if ($memPct -ge $Config.MemWarn) { $problems.Add(@{ Level = 'warn'; Text = "memory $memPct% in use" }) }
    $checked.Add('memory')

    foreach ($s in $Config.Watch) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if (-not $svc) { $problems.Add(@{ Level = 'warn'; Text = "$s is not installed (listed in Watch)" }) }
        elseif ($svc.Status -ne 'Running') { $problems.Add(@{ Level = 'bad'; Text = "$s is $($svc.Status.ToString().ToLower())" }) }
        $checked.Add($s)
    }

    $w32 = @(Invoke-ManatechNative w32tm.exe '/query', '/status')
    if ($LASTEXITCODE -ne 0) {
        $problems.Add(@{ Level = 'warn'; Text = 'Windows Time service is not answering' })
        $checked.Add('clock')
    } else {
        $source = $null
        foreach ($l in $w32) { if ($l -match '^Source:\s*(.+)$') { $source = $Matches[1].Trim(); break } }
        if ($source) {
            if ($source -match 'Local CMOS Clock|Free-running System Clock') { $problems.Add(@{ Level = 'warn'; Text = "clock is not synchronised (source: $source)" }) }
            $checked.Add('clock')
        }
    }

    $pending = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    ) | Where-Object { Test-Path -LiteralPath $_ }
    if ($pending) { $problems.Add(@{ Level = 'warn'; Text = 'reboot required (servicing or Windows Update)' }) }
    $checked.Add('reboot')

    # CPU % over a quiet window, after the probes rather than across them: they
    # make WMI, the service manager, quser and w32tm work in processes of their
    # own, which the subtraction of this process's time cannot see. Across
    # them an idle 4-core node read 24%; a quiet window read 3%, and
    # LoadPercentage 1-2% (lab, 2026-10-03).
    $cpuFrom = Get-ManatechCpuSample
    Start-Sleep -Milliseconds 200
    $cpu = Get-ManatechCpuPct -From $cpuFrom -To (Get-ManatechCpuSample) -Cores $cs.NumberOfLogicalProcessors

    $now = Get-Date
    @{
        HostName = $name
        PrimaryIp = [string]$primary
        Os       ="$($os.Caption -replace '^Microsoft ', ''), build $($os.BuildNumber)$ubr"
        Uptime   = $now - $os.LastBootUpTime
        CpuPct   = $cpu
        Cores    = $cs.NumberOfLogicalProcessors
        MemPct   = $memPct
        MemText  = '{0:N1} of {1:N1} GiB' -f ($memUsed / 1MB), ($memTotal / 1MB)
        DiskName = $env:SystemDrive
        DiskPct  = $sysPct
        DiskText = if ($sys.Count) { '{0:N0}G of {1:N0}G' -f (($sys[0].TotalSize - $sys[0].TotalFreeSpace) / 1GB), ($sys[0].TotalSize / 1GB) } else { '?' }
        Sessions = "$($users.Count)  ($($users -join ' '))"
        Time     = '{0:ddd yyyy-MM-dd HH:mm} UTC{0:zzz}' -f $now
        Ipv4     = $ipv4
        Problems = $problems.ToArray()
        Checked  = $checked.ToArray()
    }
}

function Get-ManatechBannerText {
    <#
    .SYNOPSIS
    The banner for this host as one string (lines joined with LF).
    .DESCRIPTION
    -Color and -Glyphs override this host's motd.psd1 for this call only: the
    terminal that will draw the text is the caller's, and only the caller
    knows what it can draw (Enter-ManatechPSSession passes them).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$DataPath = $PSScriptRoot,
        [ValidateSet('truecolor', '256', '16', 'none')][string]$Color,
        [ValidateSet('unicode', 'ascii')][string]$Glyphs
    )
    $config = Get-ManatechConfig -DataPath $DataPath
    if ($Color) { $config.Color = $Color }
    if ($Glyphs) { $config.Glyphs = $Glyphs }
    $fact = Get-ManatechHostFact -Config $config
    (Format-ManatechBanner -Fact $fact -Config $config -DataPath $DataPath) -join "`n"
}

function Show-ManatechBanner {
    <#
    .SYNOPSIS
    Writes the banner once per session; the all-users profile calls this.
    .DESCRIPTION
    Skips when the banner was already shown in this session (a nested shell),
    when PowerShell was started to run a command (ssh host 'cmd' runs
    "powershell -c cmd"), and with -SshOnly, when the session is not over SSH.
    Output encoding is switched to UTF-8 for the box-drawing glyphs and put
    back afterwards. A failure prints one warning and never blocks the login.
    #>
    [CmdletBinding()]
    param(
        [string]$DataPath = $PSScriptRoot,
        [switch]$SshOnly
    )
    if ($env:MANATECH_BANNER_SHOWN) { return }
    if ($SshOnly -and -not $env:SSH_CONNECTION) { return }
    $cmdArgs = [Environment]::GetCommandLineArgs()
    if ($cmdArgs | Where-Object { $_ -match '^[-/](c|command|e|ec|encodedcommand|f|file|noni|noninteractive)$' }) { return }
    $env:MANATECH_BANNER_SHOWN = '1'

    $previous = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        [Console]::Out.Write((Get-ManatechBannerText -DataPath $DataPath) + [Environment]::NewLine)
    } catch {
        Write-Warning "Manatech banner: $($_.Exception.Message)"
    } finally {
        [Console]::OutputEncoding = $previous
    }
}

# What Enter-ManatechPSSession runs on the remote host: the banner text, drawn
# with -Color and -Glyphs only when the remote module has those options; an
# older one draws with its own settings.
$script:RemoteBannerBlock = {
    param($color, $glyphs)
    Import-Module (Join-Path $env:ProgramData 'Manatech\ManatechBanner.psm1') -ErrorAction Stop
    $known = (Get-Command -Name Get-ManatechBannerText).Parameters
    $draw = @{}
    if ($color -and $known.ContainsKey('Color')) { $draw.Color = $color }
    if ($glyphs -and $known.ContainsKey('Glyphs')) { $draw.Glyphs = $glyphs }
    Get-ManatechBannerText @draw
}

# Get-ManatechClientSetting NAME ALLOWED - the environment variable NAME when
# it holds one of ALLOWED (spelled as in ALLOWED); '' when it is unset, and ''
# with a warning when it holds anything else.
function Get-ManatechClientSetting {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string[]]$Allowed)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if (-not $value) { return '' }
    $match = @($Allowed | Where-Object { $_ -eq $value })
    if ($match.Count) { return $match[0] }
    Write-Warning "$Name='$value' is not one of: $($Allowed -join ', '); ignored"
    ''
}

function Enter-ManatechPSSession {
    <#
    .SYNOPSIS
    Enter-PSSession with the remote host's banner printed first.
    .DESCRIPTION
    PS-Remoting has no login banner and runs no profile, so the banner cannot
    come from the remote side unprompted. This opens the session, asks the
    remote host for its banner text (the module must be installed there),
    prints it here, where the local terminal draws the colours, then enters
    the session. -HostName uses PowerShell 7 remoting over SSH instead of WinRM.

    -Color and -Glyphs say what THIS terminal can draw, and the banner is
    drawn for it whatever the remote host's motd.psd1 says. They default to
    $env:MANATECH_BANNER_COLOR and $env:MANATECH_BANNER_GLYPHS, so one line in
    a terminal's profile settles it for that terminal. A local PowerShell tab
    in MobaXterm passes only the 16 console colours - 24-bit colours arrive
    rounded to the nearest of those - so '16' draws it as designed there. A
    remote module from before these options draws with its own settings.
    .EXAMPLE
    Enter-ManatechPSSession h-vsw-app1
    .EXAMPLE
    Enter-ManatechPSSession -HostName h-vsw-app1 -UserName administrator -Color 16
    #>
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ComputerName')][string]$ComputerName,
        [Parameter(ParameterSetName = 'ComputerName')][pscredential]$Credential,
        [Parameter(Mandatory, ParameterSetName = 'HostName')][string]$HostName,
        [Parameter(ParameterSetName = 'HostName')][string]$UserName,
        [ValidateSet('truecolor', '256', '16', 'none')][string]$Color,
        [ValidateSet('unicode', 'ascii')][string]$Glyphs
    )
    # Assigned only when there is a value: ValidateSet also checks later
    # assignments, and '' is not in either set.
    if (-not $Color) { $fromEnv = Get-ManatechClientSetting -Name 'MANATECH_BANNER_COLOR' -Allowed 'truecolor', '256', '16', 'none'; if ($fromEnv) { $Color = $fromEnv } }
    if (-not $Glyphs) { $fromEnv = Get-ManatechClientSetting -Name 'MANATECH_BANNER_GLYPHS' -Allowed 'unicode', 'ascii'; if ($fromEnv) { $Glyphs = $fromEnv } }

    $sessionArgs = @{}
    foreach ($key in 'ComputerName', 'Credential', 'HostName', 'UserName') {
        if ($PSBoundParameters.ContainsKey($key)) { $sessionArgs[$key] = $PSBoundParameters[$key] }
    }
    $session = New-PSSession @sessionArgs -ErrorAction Stop
    try {
        $text = Invoke-Command -Session $session -ErrorAction Stop -ArgumentList $Color, $Glyphs -ScriptBlock $script:RemoteBannerBlock
        Write-Host $text
    } catch {
        Write-Warning "no banner from $($session.ComputerName): $($_.Exception.Message)"
    }
    Enter-PSSession -Session $session
}

Export-ModuleMember -Function Get-ManatechConfig, Resolve-ManatechHostName, Find-ManatechVlan, Format-ManatechBanner,
    Get-ManatechHostFact, Get-ManatechBannerText, Show-ManatechBanner, Enter-ManatechPSSession
