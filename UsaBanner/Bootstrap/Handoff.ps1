# Handoff.ps1 - the PowerShell 7 check every command makes first. Windows
# PowerShell 5.1 loads this file: 5.1 syntax only.

function Test-UsaBannerHandoff {
    <#
    .SYNOPSIS
    True when this PowerShell cannot run the module's commands, so a command
    must hand itself to pwsh.
    .DESCRIPTION
    In:  a version to judge; this PowerShell's by default.
    Out: $false under PowerShell 7 or later; $true under anything older.
    Throws when a hand-off is needed in a process a hand-off started
    (USABANNER_HANDOFF is set there): the pwsh it ran is not PowerShell 7,
    and handing off again would loop.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([version]$Version = $PSVersionTable.PSVersion)
    if ($Version.Major -ge 7) { return $false }
    if ($env:USABANNER_HANDOFF) {
        throw "UsaBanner: '$env:USABANNER_HANDOFF' was run as PowerShell 7, but it is PowerShell $Version."
    }
    $true
}

function Find-UsaBannerPwsh {
    <#
    .SYNOPSIS
    The path of pwsh (PowerShell 7), or nothing.
    .DESCRIPTION
    pwsh on the PATH first, then the MSI's default location,
    %ProgramFiles%\PowerShell\7\pwsh.exe.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $onPath = @(Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue)
    if ($onPath.Count -gt 0) { return $onPath[0].Path }
    if ($env:ProgramFiles) {
        $msi = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        if (Test-Path -LiteralPath $msi -PathType Leaf) { return $msi }
    }
}

function ConvertTo-UsaBannerHandoffScript {
    <#
    .SYNOPSIS
    The script a hand-off runs in pwsh: import this module, then run one of
    its commands with the parameters it was given.
    .DESCRIPTION
    In:  the command's name, its bound parameters, the module manifest's
         path, and the pwsh path (kept in USABANNER_HANDOFF for the loop
         check in Test-UsaBannerHandoff).
    Out: the script's text.
    The parameters travel as CLIXML, PowerShell's own serialization, encoded
    as base64, so no value is ever read as code and no quote can break out.
    A switch goes as a boolean: a deserialized SwitchParameter would not
    bind to a switch. pwsh writes its output in UTF-8, which
    Invoke-UsaBannerHandoff reads it as. Throws on a name that is not
    Verb-Usa<Noun>.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Command,
        [System.Collections.IDictionary]$Parameters = @{},
        [Parameter(Mandatory)][string]$Manifest,
        [Parameter(Mandatory)][string]$Pwsh
    )
    if ($Command -cnotmatch '^[A-Z][a-z]+-Usa[A-Za-z]+$') {
        throw "UsaBanner: '$Command' is not a command of this module."
    }
    $plain = @{}
    foreach ($key in $Parameters.Keys) {
        $value = $Parameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) { $value = $value.IsPresent }
        $plain[$key] = $value
    }
    $clixml = [System.Management.Automation.PSSerializer]::Serialize($plain, 8)   # 8: the depth kept; parameters nest far less
    $payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($clixml))
    $lines = @(
        '$ErrorActionPreference = ''Stop'''
        '[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)'
        ('$env:USABANNER_HANDOFF = ''{0}''' -f $Pwsh.Replace("'", "''"))
        ('Import-Module -Name ''{0}''' -f $Manifest.Replace("'", "''"))
        ('$parameters = [System.Management.Automation.PSSerializer]::Deserialize([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(''{0}'')))' -f $payload)
        ('{0} @parameters' -f $Command)
    )
    $lines -join "`n"
}

function Invoke-UsaBannerHandoff {
    <#
    .SYNOPSIS
    Runs one of this module's commands in pwsh, with the parameters it was
    given, and passes its output on.
    .DESCRIPTION
    Called from a command's begin {} block when Test-UsaBannerHandoff is
    true. pwsh's output comes back as lines of text, through a pipe; at the
    console they print as they arrive. Windows PowerShell decodes that pipe
    in the console's encoding, the OEM code page, where a bar such as
    U+2501 has no place and came back as ? (IBM437 on Server 2022 and 2025,
    measured 2026-10-21); so the console reads UTF-8 for the call, as pwsh
    writes it, and gets its own encoding back after. A process without a
    console keeps its encoding.
    Throws when no pwsh is found, saying what to install, and when pwsh
    exits with an error. A command that reads keys would need pwsh on the
    console rather than behind a pipe; none does yet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,
        [System.Collections.IDictionary]$Parameters = @{},
        [string]$Pwsh,
        [string]$Manifest = $script:UsaBannerManifest
    )
    if (-not $Pwsh) { $Pwsh = Find-UsaBannerPwsh }
    if (-not $Pwsh) {
        throw "UsaBanner: $Command needs PowerShell 7, and none was found. Install it (deploy-usawinssh does, or the MSI from https://github.com/PowerShell/PowerShell/releases), then run $Command again."
    }
    $script = ConvertTo-UsaBannerHandoffScript -Command $Command -Parameters $Parameters -Manifest $Manifest -Pwsh $Pwsh
    $encoded = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($script))   # -EncodedCommand takes UTF-16LE
    $consoleEncoding = $null
    try {
        $consoleEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
    }
    catch { $consoleEncoding = $null }
    try {
        # -OutputFormat Text: started with -EncodedCommand, pwsh writes its errors to stderr as CLIXML
        # ('#< CLIXML <Objs ...'), which Windows PowerShell 5.1 prints raw.
        & $Pwsh -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $encoded
    }
    finally {
        if ($null -ne $consoleEncoding) { [Console]::OutputEncoding = $consoleEncoding }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "UsaBanner: $Command failed in PowerShell 7 ($Pwsh), exit code $LASTEXITCODE."
    }
}
