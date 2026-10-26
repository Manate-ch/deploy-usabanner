# WindowsFacts.Logged.ps1 - the functions of WindowsFacts.ps1 that PowerShell logs whole at each import (D30).

function Get-UsaBannerWinSystem {
    <#
    .SYNOPSIS
    What CIM and the registry say about this Windows host.
    .DESCRIPTION
    Out: @{ Caption; Build; Ubr; BootTime; MemoryKiB; FreeKiB; DnsHostName;
         Domain; PartOfDomain; Cores; SystemDrive }. Ubr is $null where the
         registry holds none.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $version = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    @{
        Caption      = [string]$os.Caption
        Build        = [string]$os.BuildNumber
        Ubr          = $(if ($version -and $version.PSObject.Properties['UBR']) { [string]$version.UBR })
        BootTime     = [datetimeoffset]$os.LastBootUpTime
        MemoryKiB    = [double]$os.TotalVisibleMemorySize
        FreeKiB      = [double]$os.FreePhysicalMemory
        DnsHostName  = [string]$cs.DNSHostName
        Domain       = [string]$cs.Domain
        PartOfDomain = [bool]$cs.PartOfDomain
        Cores        = [int]$cs.NumberOfLogicalProcessors
        SystemDrive  = [string]$env:SystemDrive
    }
}

function Get-UsaBannerWinInterface {
    <#
    .SYNOPSIS
    This host's network adapters, as .NET sees them.
    .DESCRIPTION
    Out: @(@{ Name; Type; Up; Addresses = @('a.b.c.d/n') }), with each
         adapter's IPv4 addresses only. Through .NET, not Get-NetIPAddress,
         whose module loads at its first call: 0.6 s of every login for
         today's banner.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()
    foreach ($nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        @{
            Name      = $nic.Name
            Type      = [string]$nic.NetworkInterfaceType
            Up        = $nic.OperationalStatus -eq [System.Net.NetworkInformation.OperationalStatus]::Up
            Addresses = @(foreach ($unicast in $nic.GetIPProperties().UnicastAddresses) {
                    if ($unicast.Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { "$($unicast.Address)/$($unicast.PrefixLength)" }
                })
        }
    }
}
