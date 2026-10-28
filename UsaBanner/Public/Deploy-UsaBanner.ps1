function Deploy-UsaBanner {
    <#
    .SYNOPSIS
    Deploys this host's banners: the console's before login, the SSH banner
    before authentication, and the banner after login.
    .DESCRIPTION
    Builds the configuration from the flags, each of which sets one setting
    (docs/DECISIONS.md, D27), on the defaults or on the file -Path names,
    and deploys it. The same command builds the same banners on every host,
    and running it again changes nothing. It returns a line for each change
    it makes, with the settings that differ from what the host held; -WhatIf
    says what it would change, and changes nothing.

    On Ubuntu (24.04 and later) it runs as root, and puts in place:
    - the configuration, /etc/usabanner/usabanner.json;
    - the console's banner in /etc/issue.d; the SSH banner,
      /etc/usabanner/issue.net, with sshd's Banner line in
      /etc/ssh/sshd_config.d where sshd is installed;
    - the banner after login, /etc/update-motd.d/05-usabanner: sh and awk
      draw this host's facts at each login into a frame drawn now;
    - a periodic job every 15 minutes (usabanner-sample.timer), which keeps
      the 24-hour ranges and the slow facts, and draws the banners again
      when the host's name, address or configuration changes;
    - where -Update turns it on, the update job once a day
      (usabanner-update.timer);
    - the module, in PowerShell's module folder for every user.
    Ubuntu's own banner files stay as they are, so apt never asks about
    them. The stock MOTD scripts the banner replaces are turned off, and
    Remove-UsaBanner turns them back on.

    On Windows Server (2022 and later) it runs as an administrator, and
    puts in place:
    - the module, in Windows PowerShell's modules folder, which PowerShell 7
      reads too;
    - %ProgramData%\UsagiTools\Banner, which only Administrators and SYSTEM
      may change: the configuration, as JSON and as the data file each
      login reads, the SSH banner, and the record of the deploy. It and
      UsagiTools are refused, before anything changes, where they are a
      link, or someone else owns them or may delete what is in them: the
      deploy and the periodic job write there as SYSTEM;
    - a block in each PowerShell's all-users profile, which shows the
      banner after an interactive SSH login, never at the console;
    - sshd_config's Banner line, checked with sshd -t; sshd is not
      restarted, so a session over SSH stays up: restart it yourself;
    - the logon notice before a console or RDP sign-in, where no other is
      set;
    - the periodic job, a task that runs as SYSTEM every 15 minutes;
    - where -Update turns it on, the update job, a task that runs as SYSTEM
      once a day.
    OpenSSH, PowerShell 7 and the SSH default shell belong to
    deploy-usawinssh: the deploy checks them, and says what is missing.

    The update channel is off unless -Update turns it on. Then, once a day,
    the update job reads the release's SHA256SUMS at -UpdateSource. When it
    names a newer UsaBanner than the one installed, notify has the banner
    after login say so, and install installs it: the archive checked against
    SHA256SUMS, then the new version deploys this host's own configuration.
    The job runs as root (SYSTEM), so whoever can change the releases at the
    source can change what runs on this host.

    The banner after login is drawn alike for every login: pam_motd gives it
    no terminal to ask. -ColorMode and -Glyphs say what the clients of this
    host show; auto draws 256 colours and ASCII, which nearly every client
    shows.

    A host with the old banner, which this repository's install.sh or
    Install-ManatechBanner.ps1 installs, is refused unless -ReplaceOldBanner
    takes that banner off first.

    Under Windows PowerShell 5.1 the command runs itself in pwsh (PowerShell
    7), and stops with what to install when there is none.
    .PARAMETER Path
    A configuration file to start from, instead of the defaults; the flags
    change it setting by setting. The naming standard comes from a file
    alone.
    .PARAMETER Company
    The company name, for "Welcome to <company>": printable ASCII, 48
    characters at most.
    .PARAMETER Environment
    The tier: UNSET, DEV-TEST, LAB, PROD or PUB. UNSET, the default, takes
    the tier from this host's AD Description, as "PROD : Web front end"
    gives PROD.
    .PARAMETER Role
    What this host is for, in a few words, shown after login: printable
    ASCII, 64 characters at most. Empty, the default, takes the role from
    this host's AD Description, as "PROD : Web front end" gives Web front
    end.
    .PARAMETER BannerImage
    The art: a piece of the module's art (Show-UsaBannerArt -List), os for
    the pictogram in the host's OS colour, or os-logo for the logo of the OS
    the host runs (Windows, Ubuntu, or Tux on any other Linux).
    .PARAMETER ArtPath
    Art of your own, drawn in place of the module's: a .json file as
    New-UsaBannerArt -OutFile saves it (look at it first with
    Show-UsaBannerArt -Path). The art goes into the configuration, so it
    reaches every host the configuration does, and never into the module:
    for a logo you cannot or will not contribute. It keeps the rules of the
    module's own art. Not with -BannerImage.
    .PARAMETER Border
    The box's lines and corners. The Unicode sets show after login only,
    with Classic before login.
    .PARAMETER BorderChar
    The character the OneChar set draws with: given with -Border OneChar, or
    a -Path file whose set is OneChar. With any other set it is refused, as
    nothing would draw it.
    .PARAMETER BorderCap
    An ASCII face for the top line, such as (^_^).
    .PARAMETER ColorPreset
    The colour scheme: UsagiTools, Classic16, HighContrast, Mono or Custom.
    .PARAMETER ColorMode
    The colours the clients of this host show: auto, truecolor, 256, 16 or
    none.
    .PARAMETER Glyphs
    Whether the clients of this host show Unicode: auto, unicode or ascii.
    .PARAMETER Legal
    The legal text before login: L1 (friendly) to L5 (maximum).
    .PARAMETER LegalText
    Your own legal text, a string per line, printable ASCII.
    .PARAMETER Voice
    A meme voice for a lab VM: plain, uwu, random or leet.
    .PARAMETER PreInit
    What the console shows before login besides the company and the legal
    text: HostName, Ip, both, or None.
    .PARAMETER PreLogon
    The same for the SSH banner, which anyone who starts to log in can read.
    .PARAMETER VlanFile
    A CSV or TSV file of the VLANs: name, tag and cidr, then color and short
    (the badge's name) where wanted.
    .PARAMETER Services
    The services the banner after login watches, by name; default for the
    OS's own list.
    .PARAMETER Update
    The update channel: off (the default), notify or install.
    .PARAMETER UpdateSource
    The https address the releases' files are downloaded from: SHA256SUMS
    and UsaBanner-<version>.zip are under it, as under a GitHub repository's
    .../releases/latest/download.
    .PARAMETER ReplaceOldBanner
    Takes the old banner off first: the one this repository's install.sh
    (Ubuntu) or Install-ManatechBanner.ps1 (Windows) installs. Its files and
    jobs go, and what it changed comes back as the OS ships it; then this
    banner deploys. It runs after every banner is drawn, so a configuration
    that fails leaves the old banner in place. A Group Policy that delivers
    the old banner puts it back at the next boot or refresh: take that GPO
    off the host first. Get-UsaBanner's old banner check says when it is
    back.
    .EXAMPLE
    Deploy-UsaBanner -Company Contoso -Environment PROD -WhatIf
    .EXAMPLE
    Deploy-UsaBanner -Company Contoso -Environment LAB -VlanFile ./vlans.csv -ColorMode truecolor -Glyphs unicode
    .EXAMPLE
    Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource https://releases.example.com/usabanner
    .EXAMPLE
    Deploy-UsaBanner -Path ./contoso.json -Environment DEV-TEST
    .EXAMPLE
    Deploy-UsaBanner -Path ./contoso.json -ArtPath ./contoso-logo.json
    .EXAMPLE
    Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [string]$Company,

        [ValidateSet('UNSET', 'DEV-TEST', 'LAB', 'PROD', 'PUB')]
        [string]$Environment,

        [string]$Role,

        [ValidateNotNullOrEmpty()]
        [string]$BannerImage,

        [ValidateNotNullOrEmpty()]
        [string]$ArtPath,

        [ValidateSet('Classic', 'Hash', 'Star', 'Equals', 'Round', 'Bevel', 'PipeUnderscore', 'Wavy', 'OneChar', 'Rounded', 'Single', 'Double', 'Heavy', 'Block')]
        [string]$Border,

        [string]$BorderChar,

        [string]$BorderCap,

        [ValidateSet('UsagiTools', 'Classic16', 'HighContrast', 'Mono', 'Custom')]
        [string]$ColorPreset,

        [ValidateSet('auto', 'truecolor', '256', '16', 'none')]
        [string]$ColorMode,

        [ValidateSet('auto', 'unicode', 'ascii')]
        [string]$Glyphs,

        [ValidateSet('L1', 'L2', 'L3', 'L4', 'L5', 'custom')]
        [string]$Legal,

        [string[]]$LegalText,

        [ValidateSet('plain', 'uwu', 'random', 'leet')]
        [string]$Voice,

        [ValidateSet('HostName', 'Ip', 'None')]
        [string[]]$PreInit,

        [ValidateSet('HostName', 'Ip', 'None')]
        [string[]]$PreLogon,

        [ValidateNotNullOrEmpty()]
        [string]$VlanFile,

        [string[]]$Services,

        [ValidateSet('off', 'notify', 'install')]
        [string]$Update,

        [string]$UpdateSource,

        [switch]$ReplaceOldBanner
    )
    begin {
        $handedOff = Test-UsaBannerHandoff
        if ($handedOff) { Invoke-UsaBannerHandoff -Command 'Deploy-UsaBanner' -Parameters $PSBoundParameters }
    }
    end {
        if ($handedOff) { return }
        # A -WhatIf or -Confirm given to a script that calls this command reaches it too.
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) { $WhatIfPreference = $PSCmdlet.GetVariableValue('WhatIfPreference') }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = $PSCmdlet.GetVariableValue('ConfirmPreference') }
        $flags = @{}
        foreach ($name in (Get-UsaBannerDeployFlagName)) {
            if ($PSBoundParameters.ContainsKey($name)) { $flags[$name] = $PSBoundParameters[$name] }
        }
        if ($Path) { $config = New-UsaBannerDeployConfig -Flags $flags -Path $Path }
        else { $config = New-UsaBannerDeployConfig -Flags $flags }
        Write-UsaBannerUpdateWarning -Config $config
        if ((Get-UsaBannerHostOs) -eq 'windows') { Invoke-UsaBannerWindowsDeploy -Config $config -ReplaceOld:$ReplaceOldBanner }
        else { Invoke-UsaBannerLinuxDeploy -Config $config -ReplaceOld:$ReplaceOldBanner }
    }
}
