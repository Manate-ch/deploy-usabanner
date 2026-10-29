function Remove-UsaBanner {
    <#
    .SYNOPSIS
    Takes this host's banners off, and leaves the host as it was before
    Deploy-UsaBanner.
    .DESCRIPTION
    On Ubuntu, as root, in this order: stops and removes the periodic job
    and the update job;
    turns back on the stock MOTD scripts the deploy turned off, and only
    those, so a script someone else turned off stays off; takes out the
    banner after login, the SSH banner (ssh reloads, and sessions already
    open carry on) and the console's; deletes the banner's own folders
    (/etc/usabanner, /usr/local/share/usabanner and /var/lib/usabanner) and
    the module's copy the deploy made. It returns a line for each change;
    -WhatIf says what it would change, and changes nothing.

    On Windows Server, as an administrator: unregisters the periodic job's
    task and the update job's, and deletes their folder in the task
    scheduler, \UsagiTools\, once no other task is in it; takes the block
    out of each all-users
    profile, and the Banner
    line out of sshd_config, turning back on any Banner the deploy turned
    off (sshd -t checks it; restart sshd yourself); puts the logon notice
    back as it was, where it still holds the banner's text; deletes
    %ProgramData%\UsagiTools\Banner and the module's copy the deploy made.
    It refuses, before anything changes, where UsagiTools or Banner is a
    link, or someone else owns it or may delete what is in it, as the
    deploy does: the record it reads there says what to delete.

    PowerShell itself stays: it may serve more than the banner.

    Under Windows PowerShell 5.1 the command runs itself in pwsh (PowerShell
    7). Where there is none, it offers to install it first: the newest 7.6
    MSI from GitHub, checked against its release's SHA-256 and Microsoft's
    signature. That takes an elevated PowerShell; the answer no, or -WhatIf,
    installs nothing.
    .EXAMPLE
    Remove-UsaBanner -WhatIf
    .EXAMPLE
    Remove-UsaBanner
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param()
    begin {
        $handedOff = Test-UsaBannerHandoff
        if ($handedOff) { Invoke-UsaBannerHandoff -Command 'Remove-UsaBanner' -Parameters $PSBoundParameters }
    }
    end {
        if ($handedOff) { return }
        # A -WhatIf or -Confirm given to a script that calls this command reaches it too.
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) { $WhatIfPreference = $PSCmdlet.GetVariableValue('WhatIfPreference') }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = $PSCmdlet.GetVariableValue('ConfirmPreference') }
        if ((Get-UsaBannerHostOs) -eq 'windows') { Invoke-UsaBannerWindowsRemove }
        else { Invoke-UsaBannerLinuxRemove }
    }
}
