function Show-UsaBanner {
    <#
    .SYNOPSIS
    Draws one of this host's banners, as a configuration sets it.
    .DESCRIPTION
    Returns one string per line, with the colour escapes in it; at the
    console the lines print as the banner.

    +-----------+-------------------------------------------------------+
    | Moment    | Draws                                                 |
    +-----------+-------------------------------------------------------+
    | PostLogon | the banner after login: the default                   |
    | PreLogon  | the SSH banner, in plain ASCII, as sshd sends it      |
    |           | before authentication                                 |
    | PreInit   | the console's banner before login, in 16 colours, as  |
    |           | agetty prints it; on Windows, the logon notice: its   |
    |           | caption, then its text                                |
    +-----------+-------------------------------------------------------+

    The configuration is the file -Path names, with the defaults for every
    setting it leaves out; without -Path, the defaults alone.

    -Facts is what the banner shows about the host, as a hashtable: Name
    (the host name, with its domain), Ip, Os, Uptime, Cpu, Memory, Disks,
    Sessions, Time, Ipv4, Updates, Reboot, Services, Problems and Checked,
    in the shapes UsaBanner\Private\PostLogin.ps1 gives. A fact left out
    gets no row. Without -Facts, the banner shows this host's own: on Linux,
    what UsaBanner/linux/facts.sh collects; on Windows, what the module
    reads from CIM, the registry and .NET. The SSH banner and the console
    show the name without its domain.

    The tier and the role are the configuration's environment and role.
    Where it leaves them unset, this host's own banner, drawn without
    -Facts, takes them from the AD Description the periodic job cached, as
    "PROD : Web front end" gives both.

    -ColorMode is as for Show-UsaBannerArt; auto also takes the mode the
    configuration sets for this host. -Glyphs auto reads USABANNER_GLYPHS,
    then the glyphs the configuration sets for this host, then the locale
    (LC_ALL, LC_CTYPE, LANG): a client that is not UTF-8 gets ascii, which
    draws a Unicode border set as Classic. On Windows, the locale is not
    read: unicode.

    Under Windows PowerShell 5.1 the command runs itself in pwsh
    (PowerShell 7), and stops with what to install when there is none.
    .PARAMETER Moment
    PostLogon, PreLogon or PreInit; PostLogon by default.
    .PARAMETER Path
    A configuration file. Without it, the defaults.
    .PARAMETER Facts
    What the banner shows about the host, as a hashtable.
    .PARAMETER Os
    Whose colour the art takes, and for PreInit, whose console: windows,
    ubuntu or linux (any other system); auto, the default, is this host's.
    .PARAMETER ColorMode
    auto, truecolor, 256, 16 or none; auto by default.
    .PARAMETER Glyphs
    auto, unicode or ascii; auto by default.
    .EXAMPLE
    Show-UsaBanner
    .EXAMPLE
    Show-UsaBanner PreLogon -Path ./usabanner.json
    .EXAMPLE
    Show-UsaBanner -Path ./usabanner.json -Facts @{ Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80'; Uptime = '12d 6h 40m' }
    .EXAMPLE
    Show-UsaBanner PreInit -Os windows
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('PostLogon', 'PreLogon', 'PreInit')]
        [string]$Moment = 'PostLogon',

        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [System.Collections.IDictionary]$Facts,

        [ValidateSet('auto', 'windows', 'ubuntu', 'linux')]
        [string]$Os = 'auto',

        [ValidateSet('auto', 'truecolor', '256', '16', 'none')]
        [string]$ColorMode = 'auto',

        [ValidateSet('auto', 'unicode', 'ascii')]
        [string]$Glyphs = 'auto'
    )
    begin {
        $handedOff = Test-UsaBannerHandoff
        if ($handedOff) { Invoke-UsaBannerHandoff -Command 'Show-UsaBanner' -Parameters $PSBoundParameters }
    }
    end {
        if ($handedOff) { return }
        if ($Path) { $config = Read-UsaBannerConfig -Path $Path }
        else { $config = Get-UsaBannerConfigDefault }
        $hostOs = $Os
        if ($hostOs -eq 'auto') { $hostOs = Get-UsaBannerHostOs }
        $hostFacts = $Facts
        if (-not $hostFacts) { $hostFacts = Get-UsaBannerHostFacts -Services $config['services'] }
        $shortName = ([string]$hostFacts['Name'] -split '\.')[0]
        $ip = [string]$hostFacts['Ip']
        $mode = Resolve-UsaBannerColorMode -Requested $ColorMode -HostMode ([string]$config['color']['mode'])

        if ($Moment -eq 'PreLogon') {
            return Get-UsaBannerPreLogon -Config $config -Os $hostOs -Facts @{ HostName = $shortName; Ip = $ip }
        }
        if ($Moment -eq 'PreInit') {
            if ($hostOs -eq 'windows') { return ConvertTo-UsaBannerNoticeText -Notice (Get-UsaBannerLogonNotice -Config $config) }
            $consoleMode = '16'
            if ($mode -eq 'none' -or $mode -eq 'mono') { $consoleMode = 'none' }
            return Get-UsaBannerConsoleBanner -Config $config -Os $hostOs -HostName $shortName -Ip $ip -Mode $consoleMode
        }
        $ascii = (Resolve-UsaBannerGlyphs -Requested $Glyphs -HostGlyphs ([string]$config['glyphs'])) -eq 'ascii'
        # Made-up facts are no host's: they take the configuration's tier
        # and role alone.
        $description = ''
        if (-not $Facts) { $description = [string](Read-UsaBannerAdDescription) }
        $config = (Resolve-UsaBannerHostConfig -Config $config -Description $description).Config
        Get-UsaBannerPostLogon -Config $config -Os $hostOs -Facts $hostFacts -Mode $mode -AsciiOnly:$ascii
    }
}
