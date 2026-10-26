# GpoDeploy.Logged.ps1 - the functions of GpoDeploy.ps1 that PowerShell logs whole at each import (D30).

function Search-UsaBannerDirectory {
    # In:  the server, a base DN, an LDAP filter, the scope (OneLevel or Subtree), the
    #      attributes wanted and, for a large answer, a page size
    # Out: a hashtable for each object found: each attribute asked for, as its first value,
    #      $null where it has none
    # Why: System.DirectoryServices, not the GroupPolicy cmdlets, whose objects are copies
    #      under PowerShell 7; and one place that disposes what it opens
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Server,
        [Parameter(Mandatory)][string]$BaseDn,
        [Parameter(Mandatory)][string]$Filter,
        [Parameter(Mandatory)][ValidateSet('OneLevel', 'Subtree')][string]$Scope,
        [Parameter(Mandatory)][string[]]$Property,
        [int]$PageSize = 0
    )
    $root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$Server/$BaseDn")
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($root, $Filter)
    $searcher.SearchScope = [System.DirectoryServices.SearchScope]$Scope
    if ($PageSize) { $searcher.PageSize = $PageSize }
    foreach ($attribute in $Property) { $null = $searcher.PropertiesToLoad.Add($attribute) }
    $results = $null
    try {
        $results = $searcher.FindAll()
        foreach ($result in $results) {
            $row = @{}
            foreach ($attribute in $Property) {
                $row[$attribute] = if ($result.Properties[$attribute].Count) { $result.Properties[$attribute][0] } else { $null }
            }
            $row
        }
    }
    finally {
        if ($results) { $results.Dispose() }
        $searcher.Dispose()
        $root.Dispose()
    }
}

function Get-UsaBannerGpoAttribute {
    # In:  the domain, a GPO's guid and an attribute of its object in AD:
    #      gPCMachineExtensionNames, flags or versionNumber
    # Out: its value, read fresh from the PDC emulator; nothing where it has none
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Domain,
        [Parameter(Mandatory)][string]$Guid,
        [Parameter(Mandatory)][string]$Name
    )
    $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($Domain.Pdc)/CN=$Guid,CN=Policies,CN=System,$($Domain.Dn)")
    try { $entry.Properties[$Name].Value } finally { $entry.Dispose() }
}

function Set-UsaBannerGpoAttribute {
    # In:  the domain, a GPO's guid, an attribute of its object in AD and the value
    # Out: nothing; the PDC emulator holds it
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Domain,
        [Parameter(Mandatory)][string]$Guid,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value
    )
    $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($Domain.Pdc)/CN=$Guid,CN=Policies,CN=System,$($Domain.Dn)")
    try {
        $entry.Properties[$Name].Value = $Value
        $entry.CommitChanges()
    }
    finally { $entry.Dispose() }
}

function Get-UsaBannerGpoLinkAt {
    # In:  the domain, a distinguished name (the domain, an OU), and a GPO's guid; none to
    #      only check that the name is there
    # Out: Linked, Enabled and Flags (-1 when not linked), from the gPLink value on the PDC
    #      emulator (Test-UsaBannerGpoLinkValue). Throws, naming it, when the DN is not there
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Domain,
        [Parameter(Mandatory)][string]$TargetDn,
        [string]$Guid = ''
    )
    $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$($Domain.Pdc)/$TargetDn")
    try {
        try { $value = [string]$entry.Properties['gPLink'].Value }
        catch { throw "UsaBanner: -LinkTarget '$TargetDn' is not an object that $($Domain.Pdc) has ($($_.Exception.Message))." }
        if ($Guid) { Test-UsaBannerGpoLinkValue -GpLink $value -GpoGuid $Guid }
        else { [pscustomobject]@{ Linked = $false; Enabled = $false; Flags = -1 } }
    }
    finally { $entry.Dispose() }
}
