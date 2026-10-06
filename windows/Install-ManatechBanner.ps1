#Requires -RunAsAdministrator
<#
.SYNOPSIS
Installs the Manatech login banner on Windows Server 2022 or later.

.DESCRIPTION
1. Copies the module and its data files (art, colours, naming schema, VLANs,
   environments) to -Destination, after rendering this host's banner with
   them: if that fails, nothing is replaced. motd.psd1 is copied only when
   absent, or with -Force, so a host's settings survive a re-install.
   -AdDescription first caches this computer's AD Description
   (ad-description.txt; "<ENV>: <role>") from its own AD object, read as the
   computer account; a failed read keeps the previous cache.
2. Adds a marked block to the all-users profile of each installed PowerShell
   (Windows PowerShell 5.1 and PowerShell 7) that shows the banner at SSH
   login. Re-running replaces the block; nothing else in the profile changes.
3. -DefaultShell sets the OpenSSH default shell. The banner lives in a
   PowerShell profile, so with the stock default (cmd.exe) it never shows.
   any: keep a PowerShell that is set already (Windows PowerShell or
   PowerShell 7, whatever set it) and set Windows PowerShell only where the
   default is another shell - so a policy that owns the default shell (the
   OpenSSH Server GPO setting pwsh) and this install never take turns.
4. -SshBanner installs the plain pre-login banner and makes
   "Banner __PROGRAMDATA__/ssh/manatech-banner.txt" the only global Banner in
   sshd_config: any other global Banner line is commented out (kept, dated)
   and ours goes in before the first Match block (after one there, it would
   apply only to that match). A Banner inside a Match block is reported and
   left alone. sshd_config is backed up first and checked with sshd -t after;
   if sshd -t rejects it, the backup is put back.
   sshd is not restarted: do that yourself, then test from a new session
   before closing the current one.
5. -UpdateTask registers "Manatech banner update": daily as SYSTEM, it runs
   Update-ManatechBanner.ps1 (git pull, render check, reinstall files). It
   needs -RepoPath to be a git clone and git.exe on the PATH, and it limits
   the clone to Administrators and SYSTEM, because the clone URL can carry
   a deploy token.

Every change honours -WhatIf.

.EXAMPLE
.\Install-ManatechBanner.ps1 -DefaultShell powershell -SshBanner -UpdateTask -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    # The repo root (the folder holding windows\ and rootfs\).
    [string]$RepoPath = (Split-Path -Parent $PSScriptRoot),
    [string]$Destination = (Join-Path $env:ProgramData 'Manatech'),
    [ValidateSet('keep', 'any', 'powershell', 'pwsh')][string]$DefaultShell = 'keep',
    [switch]$SshBanner,
    [switch]$AdDescription,
    [switch]$UpdateTask,
    [switch]$Force
)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
# A relative -RepoPath/-Destination is resolved against the PowerShell
# location, which .NET file calls would not do.
$RepoPath = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($RepoPath)
$Destination = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Destination)

if (-not (Test-Path -LiteralPath $Destination)) { New-Item -ItemType Directory -Path $Destination | Out-Null }

# 1a. AD Description of this computer's own object. SYSTEM authenticates to AD
# as the computer account, which can read its own attributes.
if ($AdDescription) {
    try {
        $searcher = [adsisearcher]"(&(objectCategory=computer)(sAMAccountName=$($env:COMPUTERNAME)`$))"
        $searcher.ClientTimeout = [timespan]::FromSeconds(20)
        [void]$searcher.PropertiesToLoad.Add('description')
        $found = $searcher.FindOne()
        if ($null -eq $found) {
            Write-Warning "AD Description not refreshed: no computer object named $($env:COMPUTERNAME)`$"
        } else {
            $desc = if ($found.Properties['description'].Count) { [string]$found.Properties['description'][0] } else { '' }
            $cache = Join-Path $Destination 'ad-description.txt'
            if ($PSCmdlet.ShouldProcess($cache, "cache AD Description '$desc'")) {
                Set-Content -LiteralPath $cache -Value $desc -Encoding UTF8
            }
        }
    } catch {
        Write-Warning "AD Description not refreshed (previous cache kept): $($_.Exception.Message)"
    }
}

# 1b. Render check: the module and data about to be installed must draw this
# host's banner with this host's settings, or nothing is replaced.
$share = Join-Path $RepoPath 'rootfs\usr\local\share\manatech'
try {
    $candidate = Import-Module (Join-Path $PSScriptRoot 'ManatechBanner.psm1') -Force -PassThru
    $cfg = & $candidate { param($d) Get-ManatechConfig -DataPath $d } $Destination
    $fact = & $candidate { param($c) Get-ManatechHostFact -Config $c } $cfg
    $null = & $candidate { param($f, $c, $s) Format-ManatechBanner -Fact $f -Config $c -DataPath $s } $fact $cfg $share
} catch {
    # Where it broke, so the one log line names the module line to look at.
    $at = $_.InvocationInfo
    $where = if ($at -and $at.ScriptName) { " (at $(Split-Path -Leaf $at.ScriptName):$($at.ScriptLineNumber))" } else { '' }
    throw "the banner from $RepoPath fails to render on this host, so nothing was replaced: $($_.Exception.Message)$where"
}

# 1c. Files.
$files = @(
    (Join-Path $PSScriptRoot 'ManatechBanner.psm1')
    (Join-Path $share 'manatech.art')
    (Join-Path $share 'colors.tsv')
    (Join-Path $share 'schema-names.tsv')
    (Join-Path $share 'vlans.tsv')
    (Join-Path $share 'envs.tsv')
)
foreach ($f in $files) { Copy-Item -LiteralPath $f -Destination $Destination -Force }
$conf = Join-Path $Destination 'motd.psd1'
if ($Force -or -not (Test-Path -LiteralPath $conf)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'motd.psd1') -Destination $conf -Force
} else {
    Write-Host "kept existing $conf (use -Force to replace it)"
}

# 2. Profile block, in every installed PowerShell.
$begin = '# >>> Manatech banner (Install-ManatechBanner.ps1) >>>'
$end = '# <<< Manatech banner <<<'
$module = Join-Path $Destination 'ManatechBanner.psm1'
$block = @(
    $begin
    "if (Test-Path -LiteralPath '$module') {"
    "    Import-Module '$module'"
    '    Show-ManatechBanner -SshOnly'
    '}'
    $end
) -join "`r`n"
$pattern = '(?s)' + [regex]::Escape($begin) + '.*?' + [regex]::Escape($end)
$profiles = @(
    (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\profile.ps1')
    (Join-Path $env:ProgramFiles 'PowerShell\7\profile.ps1')
) | Where-Object { Test-Path -LiteralPath (Split-Path -Parent $_) }
foreach ($p in $profiles) {
    $text = if (Test-Path -LiteralPath $p) { [string](Get-Content -LiteralPath $p -Raw) } else { '' }
    $new = if ($text -match $pattern) {
        [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator] { param($m) $block })
    } elseif ($text.Trim()) {
        $text.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
    } else {
        $block + "`r`n"
    }
    if ($new -ne $text -and $PSCmdlet.ShouldProcess($p, 'write the Manatech banner block')) {
        Set-Content -LiteralPath $p -Value $new -Encoding UTF8 -NoNewline
    }
}

# Get-ShellChoice WANTED CURRENT - keep, powershell or pwsh: what -DefaultShell
# asks for, given the DefaultShell value the registry holds now ('' for none).
# 'any' means a PowerShell, whichever: one already set (Windows PowerShell or
# PowerShell 7, whoever set it) is kept, and anything else - cmd.exe, the
# stock default, included - becomes Windows PowerShell. The banner needs a
# PowerShell; which one may be another policy's call.
function Get-ShellChoice {
    param([string]$Wanted, [AllowEmptyString()][string]$Current)
    if ($Wanted -ne 'any') { return $Wanted }
    # The file name, split on either slash by hand: [IO.Path] splits only on
    # the running OS's separator, and the tests run where '\' is not one.
    $leaf = if ($Current) { @($Current.Trim().Trim('"') -split '[\\/]')[-1] } else { '' }
    if ($leaf -in 'powershell.exe', 'pwsh.exe') { 'keep' } else { 'powershell' }
}

# 3. OpenSSH default shell.
$current = ''
$openSsh = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\OpenSSH' -ErrorAction SilentlyContinue
if ($openSsh -and $openSsh.PSObject.Properties['DefaultShell']) { $current = [string]$openSsh.DefaultShell }
$shell = Get-ShellChoice -Wanted $DefaultShell -Current $current
if ($shell -ne 'keep') {
    $exe = if ($shell -eq 'pwsh') {
        Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    } else {
        Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }
    if (-not (Test-Path -LiteralPath $exe)) { throw "default shell not found: $exe" }
    if (-not (Test-Path -LiteralPath 'HKLM:\SOFTWARE\OpenSSH')) { New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' | Out-Null }
    New-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value $exe -PropertyType String -Force | Out-Null
}

# 4. Pre-login banner.
if ($SshBanner) {
    $sshDir = Join-Path $env:ProgramData 'ssh'
    $sshdConfig = Join-Path $sshDir 'sshd_config'
    if (-not (Test-Path -LiteralPath $sshdConfig)) {
        throw "${sshdConfig} not found: install the OpenSSH Server capability and start sshd once, which writes it"
    }
    # sshd.exe as the service runs it: System32\OpenSSH for the Windows
    # capability, Program Files\OpenSSH for Microsoft's MSI.
    $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
    $sshdExe = if ($svc -and $svc.PathName -match '^"?([^"]+?\.exe)') { $Matches[1] } else { Join-Path $env:windir 'System32\OpenSSH\sshd.exe' }
    Copy-Item -LiteralPath (Join-Path $RepoPath 'rootfs\etc\issue.net') -Destination (Join-Path $sshDir 'manatech-banner.txt') -Force

    # sshd uses the FIRST Banner it reads. Lines before the first Match block
    # are global; a Banner inside a Match block applies only to sessions that
    # match it, so those are reported and left alone. Any other global Banner
    # is commented out (kept, dated) and ours goes in before the first Match.
    $lines = [string[]][System.IO.File]::ReadAllLines($sshdConfig)
    $entry = 'Banner __PROGRAMDATA__/ssh/manatech-banner.txt'
    $isBanner = { param($l) $l -match '^\s*Banner\s' }
    $firstMatch = [array]::FindIndex($lines, [Predicate[string]] { param($l) $l -match '^\s*Match\s' })
    $globalEnd = if ($firstMatch -lt 0) { $lines.Count } else { $firstMatch }
    $global = @(for ($i = 0; $i -lt $globalEnd; $i++) { if (& $isBanner $lines[$i]) { $i } })
    $scoped = @(for ($i = $globalEnd; $i -lt $lines.Count; $i++) { if (& $isBanner $lines[$i]) { $lines[$i].Trim() } })
    if ($scoped) {
        Write-Warning "Banner inside a Match block, left as it is (it replaces this banner for matching sessions): $($scoped -join '; ')"
    }

    if ($global.Count -eq 1 -and $lines[$global[0]].Trim() -eq $entry) {
        Write-Host 'sshd_config already uses the Manatech banner; unchanged'
    } else {
        $new = [System.Collections.Generic.List[string]]::new($lines)
        $note = "# replaced by Install-ManatechBanner.ps1 on $(Get-Date -Format yyyy-MM-dd): "
        foreach ($i in $global) { $new[$i] = $note + $lines[$i].Trim() }
        $new.Insert($globalEnd, $entry)
        $new.Insert($globalEnd + 1, '')
        $what = if ($global) { "replace $($global.Count) global Banner line(s) with '$entry'" } else { "insert '$entry' before line $($globalEnd + 1)" }
        if ($PSCmdlet.ShouldProcess($sshdConfig, $what)) {
            $backup = "$sshdConfig.manatech-bak"
            Copy-Item -LiteralPath $sshdConfig -Destination $backup -Force
            [System.IO.File]::WriteAllLines($sshdConfig, $new, [System.Text.UTF8Encoding]::new($false))
            # sshd -t reports on standard error. Read that as text under this
            # call's own preference: in Windows PowerShell 5.1 a redirected
            # standard-error line is an error record, and under Stop the first
            # one would end the run before the backup is put back.
            $check = & { $ErrorActionPreference = 'Continue'; & $sshdExe -t 2>&1 }
            if ($LASTEXITCODE -ne 0) {
                Copy-Item -LiteralPath $backup -Destination $sshdConfig -Force
                $said = @($check | ForEach-Object { "$_".Trim() } | Where-Object { $_ }) -join '; '
                Write-Warning "sshd -t rejected the new config ($said), so the previous sshd_config was put back (copy kept at $backup)"
            } else {
                Write-Host 'sshd_config checks out. Restart-Service sshd, then test from a NEW session before closing this one.'
            }
        }
    }
}

# 5. Daily update task.
if ($UpdateTask) {
    if (-not (Get-Command -Name git.exe -ErrorAction SilentlyContinue)) {
        throw 'git.exe not found: the update task pulls with git (winget install Git.Git), or leave -UpdateTask off'
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
        throw "$RepoPath is not a git clone; clone the repo there to use -UpdateTask"
    }
    # Administrators (S-1-5-32-544) and SYSTEM (S-1-5-18) only, by SID so a
    # localised Windows resolves them too.
    if ($PSCmdlet.ShouldProcess($RepoPath, 'limit access to Administrators and SYSTEM')) {
        & icacls.exe $RepoPath /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' /T /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls failed on $RepoPath (exit $LASTEXITCODE)" }
    }
    $ps = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $updateScript = Join-Path $RepoPath 'windows\Update-ManatechBanner.ps1'
    $action = New-ScheduledTaskAction -Execute $ps -Argument "-NoProfile -NonInteractive -File `"$updateScript`""
    $trigger = New-ScheduledTaskTrigger -Daily -At 3am -RandomDelay (New-TimeSpan -Hours 1)
    $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
    if ($PSCmdlet.ShouldProcess('Manatech banner update', 'register a daily scheduled task running as SYSTEM')) {
        Register-ScheduledTask -TaskName 'Manatech banner update' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
        Write-Host "update task registered; test it now: Start-ScheduledTask 'Manatech banner update', then read $(Join-Path $Destination 'update.log')"
    }
}
