# Handoff.ps1 - the PowerShell 7 check every command makes first. Windows
# PowerShell 5.1 loads this file: 5.1 syntax only. Invoke-UsaBannerHandoff,
# which PowerShell logs whole at each import, is in Handoff.Logged.ps1
# (docs/DECISIONS.md, D30).

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
    The MSI's default location first, %ProgramFiles%\PowerShell\7\pwsh.exe,
    then pwsh on the PATH. The task a deploy registers runs this path, and a
    deploy registers it again where the text differs: a PowerShell remoting
    session over SSH puts its own folder first on its PATH in the 8.3 form
    sshd started it by (C:\progra~1\powershell\7, a production host,
    2026-10-28), while %ProgramFiles% is the long form in every session.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    if ($env:ProgramFiles) {
        $msi = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        if (Test-Path -LiteralPath $msi -PathType Leaf) { return $msi }
    }
    $onPath = @(Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue)
    if ($onPath.Count -gt 0) { return $onPath[0].Path }
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
