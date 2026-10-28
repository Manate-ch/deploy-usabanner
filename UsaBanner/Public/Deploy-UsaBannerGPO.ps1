function Deploy-UsaBannerGPO {
    <#
    .SYNOPSIS
    Makes the Group Policy that deploys the banners on the domain's Windows
    servers and Ubuntu hosts, and keeps them current.
    .DESCRIPTION
    Run it on a domain controller, or a domain member with the Group Policy
    Management tools, as someone who may edit Group Policy objects and write
    NETLOGON and SYSVOL. Windows PowerShell 5.1 hands the work to pwsh
    (PowerShell 7), where the GroupPolicy module answers through the Windows
    PowerShell compatibility session. Everything is read from and written to
    the PDC emulator, so the GPO in AD, its folder in SYSVOL and the staged
    files are all in one place.

    The package is the configuration every host deploys, built from the flags
    as Deploy-UsaBanner builds one (docs/DECISIONS.md, D27): the defaults, or
    the file -Path names, with each flag given on top. The tier and the role
    stay what each host's own AD Description says, unless the package sets
    them (D29). A package that turns the update channel on is refused: the GPO
    is the update path, since an update job beside it would install a release
    that the next policy refresh puts back to the staged one.

    A run works out everything it will do before it writes anything, so a
    refusal leaves the domain as it was. Then, in this order:
    - The package, the module folder (whole) and the mark file .usabanner-gpo
      go to NETLOGON\UsaBanner, for Windows; the same, with the ADSys startup
      script, to SYSVOL\<domain>\Ubuntu\scripts\UsaBanner, for Ubuntu. A file is
      written only where its bytes differ, a file with CRLF line ends is
      written with LF (the run says how many), and a file that is not in the
      payload is removed. A folder that holds files and has no mark is
      someone else's, and is refused, as is a module folder that is, or is
      inside, a place it stages into. The Ubuntu half needs the ADSys assets
      folder (SYSVOL\<domain>\Ubuntu with its GPT.INI): without it a warning
      says what to make, and the Windows half goes on. The Version in that
      GPT.INI goes up by one when the Ubuntu copy changed: ADSys downloads
      again only when it moves.
    - The GPO -Name is made where no GPO has the name; two with the name are
      refused. It holds an immediate task for servers only (never a
      workstation) that runs the module's runner from NETLOGON as SYSTEM at each
      policy refresh, and the ADSys startup values that run the Ubuntu runner at
      boot. A GPO of that name that exists already is overwritten: before
      anything changes, a warning lists each setting it holds otherwise, old and
      new, and another what else it holds, which is left alone. A run that
      changes nothing in it warns of nothing.
    - Each -LinkTarget gets a link, enabled. Without it the links stay as they
      are: no link is made at the domain root or anywhere else, since a link is
      your act. A GPO linked nowhere applies to no host, and a warning says so.
    - It warns while today's banner GPO, the one with the task "Manatech MOTD
      sync", is linked and enabled anywhere (on a host that both apply to, the
      two undo each other at each refresh), and when no GPO of deploy-usawinssh
      is linked and enabled (a server without PowerShell 7 then gets no banner).
    - Everything is read back, a line each: 'ok' or 'FAIL' and the check. The
      run fails if one does.

    It returns a line for each change it makes; -WhatIf says what it would
    change, shows the ScheduledTasks.xml it would write, and changes nothing.
    Servers act at their next policy refresh (or gpupdate /force), Ubuntu hosts
    once ADSys has downloaded the new Version and at boot.
    .PARAMETER Path
    A configuration file to start from, instead of the defaults; the flags
    change it setting by setting. The naming standard comes from a file
    alone.
    .PARAMETER Company
    The company name, for "Welcome to <company>": printable ASCII, 48
    characters at most.
    .PARAMETER Environment
    The tier: UNSET, DEV-TEST, LAB, PROD or PUB. UNSET, the default, takes
    the tier from each host's AD Description, as "PROD : Web front end"
    gives PROD.
    .PARAMETER Role
    What a host is for, in a few words, shown after login: printable ASCII,
    64 characters at most. Empty, the default, takes the role from each
    host's AD Description, as "PROD : Web front end" gives Web front end.
    .PARAMETER BannerImage
    The art: a piece of the module's art (Show-UsaBannerArt -List), os for
    the pictogram in each host's OS colour, or os-logo for the logo of the
    OS each host runs (Windows, Ubuntu, or Tux on any other Linux).
    .PARAMETER ArtPath
    Art of your own, drawn in place of the module's: a .json file as
    New-UsaBannerArt -OutFile saves it (look at it first with
    Show-UsaBannerArt -Path). The art goes into the package, so it reaches
    every host the GPO does, and never into the module: for a logo you
    cannot or will not contribute. It keeps the rules of the module's own
    art. Not with -BannerImage.
    .PARAMETER Border
    The box's lines and corners. The Unicode sets show after login only,
    with Classic before login.
    .PARAMETER BorderChar
    The character the OneChar set draws with.
    .PARAMETER BorderCap
    An ASCII face for the top line, such as (^_^).
    .PARAMETER ColorPreset
    The colour scheme: UsagiTools, Classic16, HighContrast, Mono or Custom.
    .PARAMETER ColorMode
    The colours the clients of a host show: auto, truecolor, 256, 16 or
    none.
    .PARAMETER Glyphs
    Whether the clients of a host show Unicode: auto, unicode or ascii.
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
    (the badge's name) where wanted. It is read now, and the package holds
    the rows.
    .PARAMETER Services
    The services the banner after login watches, by name; default for the
    OS's own list.
    .PARAMETER Update
    The update channel. Group Policy takes off only: a package that turns it
    on is refused.
    .PARAMETER UpdateSource
    The https address of the update channel's releases. Not for Group Policy.
    .PARAMETER Name
    The GPO's display name; UsaBanner by default.
    .PARAMETER LinkTarget
    The distinguished names to link the GPO at, as 'OU=Servers,DC=ad,DC=example'
    or the domain's own. Each must exist. A link that exists is left as it is
    (a disabled one is enabled, with a warning); without this, no link is
    made.
    .PARAMETER Domain
    The domain's DNS name; by default, the domain of the computer this runs
    on.
    .EXAMPLE
    Deploy-UsaBannerGPO -Company Contoso -Environment PROD -WhatIf
    .EXAMPLE
    Deploy-UsaBannerGPO -Company Contoso -LinkTarget 'OU=Servers,DC=ad,DC=example', 'OU=Linux,DC=ad,DC=example'
    .EXAMPLE
    Deploy-UsaBannerGPO -Path ./contoso.json -Name 'UsaBanner (lab)' -LinkTarget 'OU=Lab,DC=ad,DC=example'
    .EXAMPLE
    Deploy-UsaBannerGPO -Path ./contoso.json -Domain ad.example -WhatIf
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

        [ValidateNotNullOrEmpty()]
        [string]$Name = 'UsaBanner',

        [string[]]$LinkTarget,

        [string]$Domain
    )
    begin {
        $handedOff = Test-UsaBannerHandoff
        if ($handedOff) { Invoke-UsaBannerHandoff -Command 'Deploy-UsaBannerGPO' -Parameters $PSBoundParameters }
    }
    end {
        if ($handedOff) { return }
        # A -WhatIf or -Confirm given to a script that calls this command reaches it too.
        if (-not $PSBoundParameters.ContainsKey('WhatIf')) { $WhatIfPreference = $PSCmdlet.GetVariableValue('WhatIfPreference') }
        if (-not $PSBoundParameters.ContainsKey('Confirm')) { $ConfirmPreference = $PSCmdlet.GetVariableValue('ConfirmPreference') }
        $flags = @{}
        foreach ($flag in (Get-UsaBannerDeployFlagName)) {
            if ($PSBoundParameters.ContainsKey($flag)) { $flags[$flag] = $PSBoundParameters[$flag] }
        }
        if ($Path) { $config = New-UsaBannerDeployConfig -Flags $flags -Path $Path }
        else { $config = New-UsaBannerDeployConfig -Flags $flags }
        Invoke-UsaBannerGpoDeploy -Config $config -Name $Name -LinkTarget @($LinkTarget | Where-Object { $_ }) -Domain ([string]$Domain)
    }
}
