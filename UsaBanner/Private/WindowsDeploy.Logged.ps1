# WindowsDeploy.Logged.ps1 - the functions of WindowsDeploy.ps1 that PowerShell logs whole at each import (D30).

function Read-UsaBannerLogonNoticeValue {
    <#
    .SYNOPSIS
    The logon notice as the registry holds it.
    .DESCRIPTION
    Out: @{ Caption; Text; Exists }: LegalNoticeCaption and LegalNoticeText
         under the Policies\System key, '' where one is missing; Exists says
         whether both values are there at all.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $key = Get-ItemProperty -LiteralPath $script:UsaNoticeKey -ErrorAction SilentlyContinue
    $caption = if ($key -and $key.PSObject.Properties['LegalNoticeCaption']) { [string]$key.LegalNoticeCaption } else { $null }
    $text = if ($key -and $key.PSObject.Properties['LegalNoticeText']) { [string]$key.LegalNoticeText } else { $null }
    @{ Caption = [string]$caption; Text = [string]$text; Exists = ($null -ne $caption -and $null -ne $text) }
}

function New-UsaBannerProfileBlock {
    <#
    .SYNOPSIS
    The block an all-users profile holds to show the banner after an SSH
    login.
    .DESCRIPTION
    In:  the configuration's data file (usabanner.psd1).
    Out: the block's lines. It shows the banner once in a session, at an
         interactive SSH login only: not at the console (D2), and not for
         scp, sftp or a command run over SSH, which start PowerShell with
         -Command, -File or -NonInteractive. A failure is one warning, and
         the login goes on. Windows PowerShell 5.1 reads it too, so it is
         5.1 syntax; there Show-UsaBanner runs itself in pwsh.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$DataFile)
    $path = $DataFile.Replace("'", "''")
    $script:UsaProfileBegin
    '# Shown once a session, at an interactive SSH login only. Remove-UsaBanner takes this block out.'
    'if ($env:SSH_CONNECTION -and -not $env:USABANNER_SHOWN -and -not @([Environment]::GetCommandLineArgs() | Where-Object { $_ -match ''^[-/](c|command|e|ec|encodedcommand|f|file|noni|noninteractive)$'' }).Count) {'
    '    $env:USABANNER_SHOWN = ''1'''
    "    try { Show-UsaBanner -Path '$path' | Out-Host }"
    '    catch { Write-Warning "UsaBanner: $($_.Exception.Message)" }'
    '}'
    $script:UsaProfileEnd
}
