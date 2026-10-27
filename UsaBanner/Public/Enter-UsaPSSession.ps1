function Enter-UsaPSSession {
    <#
    .SYNOPSIS
    Enters a PowerShell session on a host, with the host's banner after login
    printed first.
    .DESCRIPTION
    PowerShell remoting runs no profile, and over SSH a session carries only
    PowerShell's own traffic, so no remote session shows the banner after
    login by itself. This command opens the session, has the host draw that
    banner over it as the host's own logins draw it, prints the lines here,
    where this terminal draws the colours, then enters the session.

    The host draws with Get-UsaBanner -Moment PostLogon, so UsaBanner must be
    deployed there: on Windows, the banner the profile block shows at an SSH
    login; on Ubuntu, the one pam_motd shows. A host with no banner, or a draw
    that fails, gives one warning, and the session is entered all the same.

    -ColorMode and -Glyphs say what this terminal draws, as USABANNER_COLOR
    and USABANNER_GLYPHS do in a user's environment, and default to those two
    here. The host draws with them set and puts its own back after. A Windows
    host's banner follows them; an Ubuntu host's is the one its logins show,
    drawn at deploy.

    -HostName opens the session over SSH, -ComputerName over WinRM, with the
    parameters New-PSSession takes for each; -Session uses one already open.
    A session this command opens stays open after Exit-PSSession, as one from
    New-PSSession does: Remove-PSSession closes it.

    The command runs in the PowerShell that calls it, as a session can only be
    entered there. Under Windows PowerShell 5.1 it enters over WinRM, and
    -HostName, which needs PowerShell 7, is refused.
    .PARAMETER ComputerName
    The host to reach over WinRM.
    .PARAMETER Credential
    The account for WinRM; the one running this command by default.
    .PARAMETER Port
    The port: WinRM's, or SSH's; New-PSSession's own by default.
    .PARAMETER UseSSL
    WinRM over HTTPS.
    .PARAMETER ConfigurationName
    The WinRM endpoint on the host, such as PowerShell.7; Windows
    PowerShell's by default.
    .PARAMETER Authentication
    The WinRM authentication mechanism.
    .PARAMETER SessionOption
    WinRM session options, from New-PSSessionOption.
    .PARAMETER HostName
    The host to reach over SSH, in PowerShell 7.
    .PARAMETER UserName
    The SSH user.
    .PARAMETER KeyFilePath
    The SSH private key file.
    .PARAMETER Subsystem
    The SSH subsystem PowerShell runs as on the host; powershell by default.
    .PARAMETER ConnectingTimeout
    How long the SSH connection may take to open, in milliseconds;
    New-PSSession's own limit by default.
    .PARAMETER Options
    SSH options, as a hashtable, as New-PSSession takes them.
    .PARAMETER Session
    A session already open, from New-PSSession.
    .PARAMETER ColorMode
    The colours this terminal draws: truecolor, 256, 16 or none.
    .PARAMETER Glyphs
    Whether this terminal draws Unicode: unicode or ascii.
    .EXAMPLE
    Enter-UsaPSSession -HostName h-vsw-app1.ad.example -UserName admin@ad.example
    .EXAMPLE
    Enter-UsaPSSession h-vsw-app1.ad.example -ColorMode 16
    .EXAMPLE
    Enter-UsaPSSession -Session (New-PSSession -HostName h-vsw-app1.ad.example)
    #>
    [CmdletBinding(DefaultParameterSetName = 'ComputerName')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'ComputerName')]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [pscredential]$Credential,

        [Parameter(ParameterSetName = 'ComputerName')]
        [Parameter(ParameterSetName = 'SSHHost')]
        [int]$Port,

        [Parameter(ParameterSetName = 'ComputerName')]
        [switch]$UseSSL,

        [Parameter(ParameterSetName = 'ComputerName')]
        [string]$ConfigurationName,

        [Parameter(ParameterSetName = 'ComputerName')]
        [System.Management.Automation.Runspaces.AuthenticationMechanism]$Authentication,

        [Parameter(ParameterSetName = 'ComputerName')]
        [System.Management.Automation.Remoting.PSSessionOption]$SessionOption,

        [Parameter(Mandatory, ParameterSetName = 'SSHHost')]
        [ValidateNotNullOrEmpty()]
        [string]$HostName,

        [Parameter(ParameterSetName = 'SSHHost')]
        [string]$UserName,

        [Parameter(ParameterSetName = 'SSHHost')]
        [string]$KeyFilePath,

        [Parameter(ParameterSetName = 'SSHHost')]
        [string]$Subsystem,

        [Parameter(ParameterSetName = 'SSHHost')]
        [int]$ConnectingTimeout,

        [Parameter(ParameterSetName = 'SSHHost')]
        [hashtable]$Options,

        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Session')]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [ValidateSet('truecolor', '256', '16', 'none')]
        [string]$ColorMode,

        [ValidateSet('unicode', 'ascii')]
        [string]$Glyphs
    )
    begin {
        # No hand-off to pwsh: a session is entered only in the PowerShell
        # that asks. So nothing of the module runs here but this check, and
        # Windows PowerShell 5.1 opens sessions over WinRM alone.
        $windowsPowerShell = Test-UsaBannerHandoff
        if ($windowsPowerShell -and $PSCmdlet.ParameterSetName -eq 'SSHHost') {
            throw 'UsaBanner: Enter-UsaPSSession -HostName is PowerShell remoting over SSH, which needs PowerShell 7: run it in pwsh. Windows PowerShell 5.1 enters over WinRM, with -ComputerName.'
        }
    }
    end {
        $remote = $Session
        $name = $ComputerName
        if ($PSCmdlet.ParameterSetName -eq 'SSHHost') { $name = $HostName }
        if ($PSCmdlet.ParameterSetName -eq 'Session') { $name = [string]$Session.ComputerName }
        else {
            $open = @{}
            foreach ($key in 'ComputerName', 'Credential', 'Port', 'UseSSL', 'ConfigurationName', 'Authentication', 'SessionOption', 'HostName', 'UserName', 'KeyFilePath', 'Subsystem', 'ConnectingTimeout', 'Options') {
                if ($PSBoundParameters.ContainsKey($key)) { $open[$key] = $PSBoundParameters[$key] }
            }
            $remote = New-PSSession @open -ErrorAction Stop
        }

        $color = $ColorMode
        if (-not $color) { $color = $env:USABANNER_COLOR }
        $glyph = $Glyphs
        if (-not $glyph) { $glyph = $env:USABANNER_GLYPHS }
        try {
            # Runs on the host, under whatever PowerShell its endpoint starts.
            $lines = @(Invoke-Command -Session $remote -ArgumentList $color, $glyph -ErrorAction Stop -ScriptBlock {
                    param([string]$ColorMode, [string]$Glyphs)
                    $own = @{ Color = $env:USABANNER_COLOR; Glyphs = $env:USABANNER_GLYPHS }
                    try {
                        if ($ColorMode) { $env:USABANNER_COLOR = $ColorMode }
                        if ($Glyphs) { $env:USABANNER_GLYPHS = $Glyphs }
                        Import-Module -Name UsaBanner -ErrorAction Stop
                        Get-UsaBanner -Moment PostLogon
                    }
                    finally {
                        $env:USABANNER_COLOR = $own.Color
                        $env:USABANNER_GLYPHS = $own.Glyphs
                    }
                })
            $lines | ForEach-Object { [string]$_ } | Out-Host
        }
        catch {
            Write-Warning ('UsaBanner: no banner from {0}: {1}' -f $name, ($_.Exception.Message -replace '^UsaBanner: ', ''))
        }
        Enter-PSSession -Session $remote
    }
}
