# AdDescription.Logged.ps1 - the functions of AdDescription.ps1 that PowerShell logs whole at each import (D30).

function Get-UsaBannerAdComputerDescription {
    # In:  nothing: this computer's own name
    # Out: the description of its computer object in AD, '' for none; throws
    #      when AD cannot be asked, or has no such object
    # Why: the one place that asks AD, which the tests stand in for. As
    #      SYSTEM, the search runs as the computer account, which may read
    #      its own object
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $sam = "$([System.Environment]::MachineName)`$"
    $searcher = [adsisearcher]"(&(objectCategory=computer)(sAMAccountName=$sam))"
    $searcher.ClientTimeout = [timespan]::FromSeconds(20)
    [void]$searcher.PropertiesToLoad.Add('description')
    $found = $searcher.FindOne()
    if ($null -eq $found) { throw "AD has no computer object named $sam" }
    if ($found.Properties['description'].Count) { [string]$found.Properties['description'][0] } else { '' }
}
