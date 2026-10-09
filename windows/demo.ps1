# demo.ps1 - render the Windows banner from sample facts, on any OS, without
# installing anything. It shows the layout Get-ManatechHostFact would feed;
# the facts are invented, the data files are the repo's.
#
#   pwsh -File demo.ps1 [-HostName NAME] [-PrimaryIp A.B.C.D] [-EnvName PROD] [-Color 256] [-Glyphs ascii] [-Faults]
[CmdletBinding()]
param(
    [string]$HostName = 'h-psw-app-1.ad.example',
    [string]$PrimaryIp = '10.20.40.79',
    [string]$EnvName = 'LAB',
    [ValidateSet('truecolor', '256', '16', 'none')][string]$Color = 'truecolor',
    [ValidateSet('unicode', 'ascii')][string]$Glyphs = 'unicode',
    [switch]$Faults
)
Set-StrictMode -Version 3.0
Import-Module (Join-Path $PSScriptRoot 'ManatechBanner.psm1') -Force

$data = Join-Path (Split-Path -Parent $PSScriptRoot) 'rootfs/usr/local/share/manatech'
$config = Get-ManatechConfig -DataPath $PSScriptRoot
$config.EnvName = $EnvName
$config.Role = 'Sample Windows Server host (demo facts)'
$config.Color = $Color
$config.Glyphs = $Glyphs

$problems = @()
if ($Faults) {
    $problems = @(
        @{ Level = 'bad'; Text = '2 auto-start service(s) stopped: Spooler W32Time' }
        @{ Level = 'bad'; Text = 'Zabbix Agent 2 is stopped' }
        @{ Level = 'warn'; Text = 'D: is 91% full' }
        @{ Level = 'warn'; Text = 'reboot required (servicing or Windows Update)' }
    )
}
$fact = @{
    HostName = $HostName
    PrimaryIp = $PrimaryIp
    Os       ='Windows Server 2025 Standard, build 26100.1234'
    Uptime   = [timespan]::new(3, 4, 12, 0)
    CpuPct   = 7
    Cores    = 8
    MemPct   = 41
    MemText  = '6.5 of 16.0 GiB'
    DiskName = 'C:'
    DiskPct  = 63
    DiskText = '80G of 127G'
    Sessions = '1  (administrator)'
    Time     = '{0:ddd yyyy-MM-dd HH:mm} UTC{0:zzz}' -f (Get-Date)
    Ipv4     = @(@{ Name = 'Ethernet0'; Address = '10.20.40.79/22' })
    Problems = $problems
    Checked  = @('services', 'disks <85%', 'memory', 'sshd', 'Zabbix Agent 2', 'clock', 'reboot')
}
(Format-ManatechBanner -Fact $fact -Config $config -DataPath $data) -join [Environment]::NewLine
