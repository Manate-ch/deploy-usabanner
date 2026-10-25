# Samples.ps1 - the 24-hour range (docs/DECISIONS.md, D17) on Windows: the
# periodic job's samples, in the form linux/sample.sh writes on Linux. A line
# per sample, its fields separated by tabs: the time, in seconds since 1970;
# cpu, memory or disk, with the disk's name; the percentage.

function Get-UsaBannerDataPath {
    <#
    .SYNOPSIS
    Where this host keeps one of the banner's own files.
    .DESCRIPTION
    In %ProgramData%\UsagiTools\Banner on Windows, in /var/lib/usabanner
    elsewhere. -OnWindows replaces what this host says, for tests.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Name, [bool]$OnWindows = $IsWindows)
    if ($OnWindows) { return [System.IO.Path]::Combine([string]$env:ProgramData, 'UsagiTools', 'Banner', $Name) }
    [System.IO.Path]::Combine('/var/lib/usabanner', $Name)
}

function Add-UsaBannerSample {
    <#
    .SYNOPSIS
    Adds a sample of the facts to a samples file, and drops the samples
    older than 24 hours.
    .DESCRIPTION
    In:  the facts as the banners take them, the file, and the time.
    Out: nothing. A line each for the CPU, the memory and each disk that has
         a percentage. The file is written whole beside itself, then moved
         into place, so a reader never sees half of it; its folder is made
         when missing. A line that is not a sample is dropped, and a file
         this account cannot read starts again, with a warning.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Facts,
        [Parameter(Mandatory)][string]$Path,
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )
    $time = $Now.ToUnixTimeSeconds()
    # The lab (Server 2022 and 2025, 2026-10-23): with an empty ACL on the
    # file, the next run replaced it, as the move below may; said here, so it
    # does not rest on the read's error ending only the statement it is in.
    $old = @()
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        try { $old = [System.IO.File]::ReadAllLines($Path) }
        catch [System.UnauthorizedAccessException], [System.IO.IOException] {
            Write-Warning "UsaBanner: $Path cannot be read, so the 24-hour range starts again: $($_.Exception.Message)"
        }
    }
    $kept = @(foreach ($line in $old) {
            $stamp = ($line -split "`t", 2)[0]
            if ($stamp -match '^[0-9]+$' -and [long]$stamp -gt $time - 86400) { $line }
        })
    $taken = @(
        if ($Facts['Cpu'] -and $null -ne $Facts['Cpu'].Now) { "$time`tcpu`t$($Facts['Cpu'].Now)" }
        if ($Facts['Memory'] -and $null -ne $Facts['Memory'].Pct) { "$time`tmemory`t$($Facts['Memory'].Pct)" }
        foreach ($disk in @($Facts['Disks'])) {
            if ($disk -and $null -ne $disk.Pct) { "$time`tdisk`t$($disk.Name)`t$($disk.Pct)" }
        }
    )
    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    Save-UsaBannerJobFile -Path $Path -Text (-join @(foreach ($line in $kept + $taken) { "$line`n" }))
}

function Save-UsaBannerJobFile {
    # In:  a file of the periodic job's, and its whole text
    # Out: nothing; the file holds the text, written beside itself and moved
    #      into place, so a reader never sees half of it. When the move
    #      fails, the file beside it goes and the error stops the job: in
    #      the lab (2026-10-23) a slow.tsv no one could read was never
    #      replaced, a file beside it was left at each run, and the task
    #      still said it succeeded
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyString()][string]$Text)
    $partial = "$Path.$PID"
    try {
        [System.IO.File]::WriteAllText($partial, $Text)
        [System.IO.File]::Move($partial, $Path, $true)
    }
    catch {
        if ([System.IO.File]::Exists($partial)) { [System.IO.File]::Delete($partial) }
        throw
    }
}

function Add-UsaBannerSampleRange {
    <#
    .SYNOPSIS
    Fills in the facts' 24-hour range from a samples file.
    .DESCRIPTION
    In:  the facts, the file, and the time.
    Out: nothing. The CPU, the memory and each disk get Min and Max, the
         lowest and highest of the samples newer than 24 hours and of the
         value now, as linux/facts.sh fills them. A fact without a sample
         keeps them $null, and a line that is not a sample is passed over.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Facts,
        [Parameter(Mandatory)][string]$Path,
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    # A file this user cannot read gives no range: the banner draws without
    # it, and Get-UsaBanner's periodic job check names the file.
    try { $lines = [System.IO.File]::ReadAllLines($Path) }
    catch [System.UnauthorizedAccessException], [System.IO.IOException] { return }
    $cut = $Now.ToUnixTimeSeconds() - 86400
    $lowest = @{}
    $highest = @{}
    foreach ($line in $lines) {
        $f = $line -split "`t"
        if ($f.Count -lt 3 -or $f[0] -notmatch '^[0-9]+$' -or [long]$f[0] -le $cut) { continue }
        if ($f[1] -eq 'disk') {
            $key = "disk`t$($f[2])"
            # The else matters: an if with no output gives AutomationNull,
            # and -notmatch on that gives an empty result, which is false.
            $percent = if ($f.Count -gt 3) { $f[3] } else { '' }
        }
        else {
            $key = $f[1]
            $percent = $f[2]
        }
        if ($percent -notmatch '^[0-9]+$') { continue }
        if (-not $lowest.ContainsKey($key) -or [int]$percent -lt $lowest[$key]) { $lowest[$key] = [int]$percent }
        if (-not $highest.ContainsKey($key) -or [int]$percent -gt $highest[$key]) { $highest[$key] = [int]$percent }
    }
    $widen = {
        # In:  a fact, the key of its samples, and the name of its value
        # Out: nothing; the fact's Min and Max take in its samples and its value
        # Why: the CPU, the memory and each disk are widened alike
        param([System.Collections.IDictionary]$Fact, [string]$Sampled, [string]$Field)
        if (-not $Fact -or -not $lowest.ContainsKey($Sampled) -or $null -eq $Fact[$Field]) { return }
        $Fact['Min'] = [Math]::Min($lowest[$Sampled], [int]$Fact[$Field])
        $Fact['Max'] = [Math]::Max($highest[$Sampled], [int]$Fact[$Field])
    }
    & $widen $Facts['Cpu'] 'cpu' 'Now'
    & $widen $Facts['Memory'] 'memory' 'Pct'
    foreach ($disk in @($Facts['Disks'])) {
        if ($disk) { & $widen $disk "disk`t$($disk.Name)" 'Pct' }
    }
}

function Update-UsaBannerSample {
    <#
    .SYNOPSIS
    The periodic job on Windows: this host's sample for the 24-hour range,
    its AD Description, and its slow facts.
    .DESCRIPTION
    Every 15 minutes, as SYSTEM, from the task M4 installs; linux/sample.sh
    is its twin on Linux. -Path, -SlowPath, -AdPath and -Now replace the
    files and the time, for tests.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = (Get-UsaBannerDataPath -Name 'samples.tsv' -OnWindows $true),
        [string]$SlowPath = (Get-UsaBannerDataPath -Name 'slow.tsv' -OnWindows $true),
        [string]$AdPath = (Get-UsaBannerDataPath -Name 'ad-description' -OnWindows $true),
        [datetimeoffset]$Now = [datetimeoffset]::Now
    )
    Add-UsaBannerSample -Facts (Get-UsaBannerWindowsFacts -SamplePath $Path -SlowPath $SlowPath -Now $Now) -Path $Path -Now $Now
    # The sample first: the search for updates keeps the Windows Update
    # service busy, and a CPU reading taken after it would count that. The AD
    # Description between the two, as on Linux.
    Update-UsaBannerAdDescription -Path $AdPath
    Write-UsaBannerSlowFacts -Path $SlowPath -Now $Now
}
