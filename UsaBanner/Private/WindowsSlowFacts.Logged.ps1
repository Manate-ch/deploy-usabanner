# WindowsSlowFacts.Logged.ps1 - the functions of WindowsSlowFacts.ps1 that PowerShell logs whole at each import (D30).

function Get-UsaBannerWinRestartEvent {
    <#
    .SYNOPSIS
    The newest restart event this Windows host wrote since it booted, read
    live at login.
    .DESCRIPTION
    In:  the time the host booted.
    Out: @{ Id = 1074; Time; Type; User } for User32's event 1074, written
         the moment a restart or shutdown is set (Type is its shutdown type,
         restart or power off), or @{ Id = 1075; Time; User } for its 1075,
         written when one is called off; nothing when neither was written
         since the boot. On Server 2022 and 2025 a restart set for an hour
         wrote 1074 at once, with its comment but not when it was due, and
         calling it off wrote 1075 (D17). The fields are the event's
         properties, never its message. Throws when the System log cannot be
         read, as an account that is not an administrator may not over SSH.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][datetimeoffset]$Since)
    $filter = @{ LogName = 'System'; ProviderName = 'User32'; Id = 1074, 1075; StartTime = $Since.LocalDateTime }
    try { $newest = Get-WinEvent -FilterHashtable $filter -MaxEvents 1 -ErrorAction Stop }
    catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*') { return }
        throw
    }
    $values = @($newest.Properties | ForEach-Object { [string]$_.Value })
    $time = [datetimeoffset]$newest.TimeCreated
    if ($newest.Id -eq 1074) { return @{ Id = 1074; Time = $time; Type = $values[4]; User = $values[6] } }
    @{ Id = 1075; Time = $time; User = $values[1] }
}
