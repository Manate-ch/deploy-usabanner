function Remove-UsaBanner {
    <#
    .SYNOPSIS
    Takes this host's banners off, and leaves the host as it was before
    Deploy-UsaBanner.
    .DESCRIPTION
    On Ubuntu, as root, in this order: stops and removes the periodic job;
    turns back on the stock MOTD scripts the deploy turned off, and only
    those, so a script someone else turned off stays off; takes out the
    banner after login, the SSH banner (ssh reloads, and sessions already
    open carry on) and the console's; deletes the banner's own folders
    (/etc/usabanner, /usr/local/share/usabanner and /var/lib/usabanner) and
    the module's copy the deploy made. It returns a line for each change;
    -WhatIf says what it would change, and changes nothing.

    PowerShell itself stays: it may serve more than the banner.

    Under Windows PowerShell 5.1 the command runs itself in pwsh (PowerShell
    7), and stops with what to install when there is none.
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
        if ($IsWindows) { throw 'UsaBanner: Remove-UsaBanner removes the banner from Ubuntu in this version; Windows Server comes next.' }
        Invoke-UsaBannerLinuxRemove
    }
}
