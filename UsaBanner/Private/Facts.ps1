# Facts.ps1 - a host's facts for its banners (docs/DECISIONS.md, D26). On
# Linux they come from linux/facts.sh, the collector Ubuntu's login renderer
# reads too (D2), as records: one fact a line, fields separated by tabs, the
# kind first. ConvertFrom-UsaBannerFactRecord turns the records into the
# facts hashtable described at the top of PostLogin.ps1.

function ConvertFrom-UsaBannerFactRecord {
    <#
    .SYNOPSIS
    Facts records as the facts hashtable the banners draw from.
    .DESCRIPTION
    In:  the records' lines.
    Out: a hashtable with a key for each kind of record there is: Name, Ip,
         Os, Uptime, Sessions and Time as text; Cpu and Memory as
         @{ Now or Pct; Min; Max; Text; (Kind) }; Updates, Reboot and
         Services as @{ Text; Level }; Disks and Ipv4 as a row per record;
         Problems as @{ Level; Text } and Checked as names, in the records'
         order. An empty field is $null, so the banner leaves it out, and a
         problem or a check without its text is passed over.
         A kind it does not know is passed over: an older module reads a
         newer collector.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyString()][string[]]$Line = @())
    $asNumber = {
        # In:  a field
        # Out: the whole number it holds, or $null
        # Why: percentages are compared with thresholds; text is not
        param([string]$Field)
        if ($Field -match '^-?[0-9]+$') { [int]$Field } else { $null }
    }
    $asText = {
        # In:  a field
        # Out: the field, or $null when it is empty
        # Why: an empty field is a fact the collector could not know
        param([string]$Field)
        if ($Field) { $Field } else { $null }
    }
    $facts = @{}
    $disks = [System.Collections.Generic.List[object]]::new()
    $adapters = [System.Collections.Generic.List[object]]::new()
    $problems = [System.Collections.Generic.List[object]]::new()
    $checks = [System.Collections.Generic.List[string]]::new()
    $textKinds = @{ name = 'Name'; ip = 'Ip'; os = 'Os'; uptime = 'Uptime'; sessions = 'Sessions'; time = 'Time' }
    foreach ($record in $Line) {
        if (-not $record) { continue }
        $f = $record -split "`t"
        if ($textKinds.ContainsKey($f[0])) {
            $facts[$textKinds[$f[0]]] = & $asText $f[1]
            continue
        }
        switch -CaseSensitive ($f[0]) {
            'cpu' { $facts['Cpu'] = @{ Now = & $asNumber $f[1]; Min = & $asNumber $f[2]; Max = & $asNumber $f[3]; Text = & $asText $f[4] } }
            'memory' { $facts['Memory'] = @{ Pct = & $asNumber $f[1]; Min = & $asNumber $f[2]; Max = & $asNumber $f[3]; Text = & $asText $f[4]; Kind = & $asText $f[5] } }
            'disk' { $disks.Add(@{ Name = $f[1]; Pct = & $asNumber $f[2]; Min = & $asNumber $f[3]; Max = & $asNumber $f[4]; Text = & $asText $f[5]; Kind = & $asText $f[6] }) }
            'updates' { $facts['Updates'] = @{ Text = & $asText $f[1]; Level = & $asText $f[2] } }
            'reboot' { $facts['Reboot'] = @{ Text = & $asText $f[1]; Level = & $asText $f[2] } }
            'ipv4' { $adapters.Add(@{ Name = $f[1]; Address = $f[2] }) }
            'services' { if ($f.Count -ge 3) { $facts['Services'] = @{ Text = & $asText $f[1]; Level = & $asText $f[2] } } }
            'problem' { if ($f.Count -ge 3 -and $f[2]) { $problems.Add(@{ Level = $f[1]; Text = $f[2] }) } }
            'check' { if ($f.Count -ge 2 -and $f[1]) { $checks.Add($f[1]) } }
        }
    }
    if ($disks.Count) { $facts['Disks'] = $disks.ToArray() }
    if ($adapters.Count) { $facts['Ipv4'] = $adapters.ToArray() }
    if ($problems.Count) { $facts['Problems'] = $problems.ToArray() }
    if ($checks.Count) { $facts['Checked'] = $checks.ToArray() }
    $facts
}

function Get-UsaBannerHostFacts {
    <#
    .SYNOPSIS
    This host's facts.
    .DESCRIPTION
    On Linux: the records linux/facts.sh prints, read by
    ConvertFrom-UsaBannerFactRecord. On Windows: what
    Get-UsaBannerWindowsFacts reads (WindowsFacts.ps1). Records without a
    name take the host's own, so the panel always has a title. -Services is
    the configuration's: default, or the names; the collector gets them as
    USABANNER_SERVICES, so no names watches none.
    -OnWindows and -Collector replace what this host says, and -Environment
    adds variables to the collector's: for tests.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [bool]$OnWindows = $IsWindows,
        [string]$Collector = (Join-Path $script:UsaBannerRoot 'linux' 'facts.sh'),
        [System.Collections.IDictionary]$Environment = @{},
        [object]$Services = 'default'
    )
    if ($OnWindows) { return Get-UsaBannerWindowsFacts }
    $watched = 'default'
    if ($Services -is [System.Collections.IEnumerable] -and $Services -isnot [string]) { $watched = @($Services) -join ' ' }
    elseif ($Services) { $watched = [string]$Services }
    $assignments = @("USABANNER_SERVICES=$watched") + @(foreach ($key in $Environment.Keys) { "$key=$($Environment[$key])" })
    $facts = ConvertFrom-UsaBannerFactRecord -Line @(& env @assignments sh $Collector)
    if (-not $facts['Name']) { $facts['Name'] = [Environment]::MachineName }
    $facts
}
