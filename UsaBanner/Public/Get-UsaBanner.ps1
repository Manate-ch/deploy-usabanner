function Get-UsaBanner {
    <#
    .SYNOPSIS
    Shows the banners Deploy-UsaBanner put on this host, and whether each
    part of them is in place.
    .DESCRIPTION
    Without -Moment, one object for this host:

    +---------------+-------------------------------------------------------+
    | Property      | Holds                                                 |
    +---------------+-------------------------------------------------------+
    | HostName      | this host's name, as its banners show it              |
    | Os            | ubuntu, linux or windows                              |
    | Version       | the version of the module every user and the periodic |
    |               | job load                                              |
    | Deployed      | whether a banner is deployed here                     |
    | Healthy       | deployed, and no check missing, differs, stale or     |
    |               | invalid                                               |
    | Ssh           | open when sshd runs or systemd listens for it; closed |
    |               | when not; not installed (a firewall is not checked)   |
    | Services      | the services the banner after login watches, in their |
    |               | state now                                             |
    | Tier          | the tier the banners show, and TierFrom where it came |
    |               | from: configuration, AD Description, or '' for        |
    |               | neither (then it is UNSET)                            |
    | Role          | the role the banner after login shows, '' for none,   |
    |               | and RoleFrom where it came from, as TierFrom          |
    | AdDescription | this host's AD Description, as the periodic job last  |
    |               | cached it; $null when none is cached (no domain, or   |
    |               | not read yet)                                         |
    | Checks        | each part of the deploy: State, Check and Detail      |
    | Vlans         | the colour-to-VLAN rows: Tag, Name, Cidr, Color,      |
    |               | Short, and ThisHost for the one this host is in       |
    | Settings      | what the configuration sets otherwise than the        |
    |               | defaults, a setting a line                            |
    | Configuration | the whole configuration                               |
    +---------------+-------------------------------------------------------+

    A check is ok; off, when a part is not in place for a reason outside
    the banner (no OpenSSH server, a logon notice someone else set, another
    shell for SSH logins); missing; differs, when it is not as a deploy
    leaves it; stale, when it was drawn for another name, address,
    configuration or AD Description, when the periodic job has not sampled
    for 20 minutes, or when sshd on Windows started before sshd_config last
    changed (a deploy leaves its restart to you); invalid, when the
    configuration cannot be read; or unknown, when this session cannot tell.
    On Ubuntu, which banner sshd sends needs root to read; on Windows, a
    user may not see the periodic job's task. Run it as root, or as an
    administrator, for every answer.

    With -Moment, a banner as installed, a string per line:

    +-----------+-----------------------------------------------------------+
    | Moment    | Shows                                                     |
    +-----------+-----------------------------------------------------------+
    | PostLogon | the banner after login, as a login draws it now: on       |
    |           | Ubuntu, /etc/update-motd.d/05-usabanner, which pam_motd   |
    |           | runs as root (another user's run may see fewer facts); on |
    |           | Windows, what the profiles' block shows                   |
    | PreLogon  | the SSH banner, as sshd sends it                          |
    | PreInit   | the console's banner as agetty prints it, with this       |
    |           | host's name and address; on Windows, the logon notice     |
    +-----------+-----------------------------------------------------------+

    It changes nothing. Under Windows PowerShell 5.1 the command runs itself
    in pwsh (PowerShell 7), and its answer comes back as text.
    .PARAMETER Moment
    PostLogon, PreLogon or PreInit: show that banner as installed.
    .EXAMPLE
    Get-UsaBanner
    .EXAMPLE
    (Get-UsaBanner).Checks | Where-Object State -ne ok
    .EXAMPLE
    Get-UsaBanner PreLogon
    #>
    [CmdletBinding()]
    [OutputType('UsaBanner.Status', [string])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('PostLogon', 'PreLogon', 'PreInit')]
        [string]$Moment
    )
    begin {
        $handedOff = Test-UsaBannerHandoff
        if ($handedOff) { Invoke-UsaBannerHandoff -Command 'Get-UsaBanner' -Parameters $PSBoundParameters }
    }
    end {
        if ($handedOff) { return }
        if ($Moment) { return Get-UsaBannerInstalled -Moment $Moment }
        if ((Get-UsaBannerHostOs) -eq 'windows') { Get-UsaBannerWindowsStatus }
        else { Get-UsaBannerLinuxStatus }
    }
}
