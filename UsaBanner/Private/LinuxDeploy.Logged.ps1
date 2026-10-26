# LinuxDeploy.Logged.ps1 - the functions of LinuxDeploy.ps1 that PowerShell logs whole at each import (D30).

function Get-UsaBannerSha256 {
    # In:  bytes
    # Out: their SHA-256 in lower-case hex, as sha256sum prints it
    param([byte[]]$Bytes)
    [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}
