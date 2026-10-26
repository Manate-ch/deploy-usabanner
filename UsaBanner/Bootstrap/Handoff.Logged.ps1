# Handoff.Logged.ps1 - the functions of Handoff.ps1 that PowerShell logs whole at each import (D30).
# Windows PowerShell 5.1 loads this file: 5.1 syntax only.

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
