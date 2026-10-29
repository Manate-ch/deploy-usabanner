# deploy-usabanner

**Deploy-UsaBanner** puts information rich *COLORED* login banners on both Windows Server (2022 and later) and Ubuntu
(24.04 and later) via the magic of self installing *PowerShell Core* for cohesive administration-over-ssh options for admins.

Deployed idempotently, this script both gives you options to manually deploy via `Deploy-UsaBanner` and via Windows Group Policy to support Win Server / Ubuntu ADSys powered devices via a `Deploy-UsaBannerGPO` cmdlet.


Also starring: A series of various lovely artworks (Submit yours today!) or the option to straight convert your own art automatically via `New-UsaBannerArt` to put your own Art in your banners 

### Part of the UsagiTools 2 series. 
```
   ^^       ^^    U
  /::\     /::\   S
 |::::|   |::::|  A
 |::::|   |::::|  G
  \:::|   |:::/   I
 .-\__/---\__/-.  T
/:::oo:(o):oo:::\ O
|:(o):::::::(o):| O
|::::::,',::::::| L
|::::\_/:\_/::::| S
 '-.__________.-' 2
 ```
Each host gets three banners:

| When | Ubuntu | Windows Server |
|---|---|---|
| At the console, before login | `/etc/issue.d/50-usabanner.issue`, printed after Ubuntu's own `/etc/issue` | the logon notice, the text before a console or RDP sign-in |
| SSH, before authentication | `/etc/usabanner/issue.net`, sshd's `Banner` | `C:\ProgramData\UsagiTools\Banner\sshd-banner.txt`, the `Banner` line of `sshd_config` |
| After login | `/etc/update-motd.d/05-usabanner`, which pam_motd runs at each login | a block in each PowerShell's all-users profile, shown at an SSH login |

The banner before authentication is plain ASCII on purpose: SSH clients strip
or expose anything else that a server sends before it has authenticated. The
banner after login is the colour one: art, the company's name, the host's name
decoded with your naming standard, the tier strip, the host's role, its OS,
load, memory, disks and addresses, the services it watches, and one line for
each problem its health check finds.

What the module does is in [docs/SPEC.md](docs/SPEC.md), and why each choice
was made in [docs/DECISIONS.md](docs/DECISIONS.md). To look before installing
anything, from a clone:

    Import-Module ./UsaBanner/UsaBanner.psd1
    Show-UsaBanner                     # the banner after login, from the defaults
    Show-UsaBanner PreLogon            # the SSH banner
    Show-UsaBanner PreInit             # the console's banner; on Windows, the logon notice
    Show-UsaBannerArt -List            # every piece of art there is
    Show-UsaBannerArt -Text 'Contoso LLC'   # a name in block letters
    New-UsaBannerArt ./logo.png -OutFile ./logo.json   # your own logo as art
    Show-UsaBannerArt -Path ./logo.json

Each command, and every flag it takes, is in the [command reference](#command-reference).

## Install from a release

A release is two files: `UsaBanner-<version>.zip`, the module, and
`SHA256SUMS`. The lines below take the latest release and check the archive
against `SHA256SUMS` before anything else. Every deploy takes `-WhatIf`, which
says what it would change and changes nothing: run it first to verify before you try!

### Ubuntu (Without Powershell Core installed)

As a user who may `sudo`:

    d=$(mktemp -d); cd "$d"
    base=https://github.com/Manate-ch/deploy-usabanner/releases/latest/download
    curl -fsSLO "$base/SHA256SUMS"
    zip=$(awk '{ print $2 }' SHA256SUMS)
    curl -fsSLO "$base/$zip"
    sha256sum --check SHA256SUMS
    python3 -m zipfile -e "$zip" .
    sudo sh ./UsaBanner/linux/bootstrap.sh -Company Contoso -WhatIf
    sudo sh ./UsaBanner/linux/bootstrap.sh -Company Contoso

`bootstrap.sh` installs PowerShell 7 from Microsoft's package repository where
the host has none (never the snap), and on a domain-joined host the tools that
read its AD Description (`ldap-utils`, `krb5-user`,
`libsasl2-modules-gssapi-mit`) where they are missing. Those installs happen
under `-WhatIf` too; only the deploy is a dry run. Then it runs
`Deploy-UsaBanner` with the flags it was given. The deploy copies the module
to `/usr/local/share/powershell/Modules`, writes the three banners, turns off
the stock MOTD scripts the banner replaces (`-WhatIf` names each one;
`docs/DECISIONS.md`, D16), reloads
ssh for the SSH banner (sessions already open carry on), and starts a periodic
job that samples the host every 15 minutes. `sudo pwsh -c Get-UsaBanner` then
says whether each part is in place.

### Windows Server

In an elevated PowerShell 7. The module needs PowerShell 7 (the MSI from
Microsoft), and the SSH banners need the OpenSSH Server
(`Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`, then start
`sshd` once so that it writes its `sshd_config`):

    $base = 'https://github.com/Manate-ch/deploy-usabanner/releases/latest/download'
    $dir = Join-Path $env:TEMP ('usabanner-' + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $dir
    Invoke-WebRequest -Uri "$base/SHA256SUMS" -OutFile "$dir\SHA256SUMS"
    $sha, $zip = -split (Get-Content -LiteralPath "$dir\SHA256SUMS" -TotalCount 1)
    Invoke-WebRequest -Uri "$base/$zip" -OutFile "$dir\$zip"
    if ((Get-FileHash -LiteralPath "$dir\$zip").Hash -ne $sha) { throw "$zip does not match SHA256SUMS" }
    Unblock-File -LiteralPath "$dir\$zip"
    Expand-Archive -LiteralPath "$dir\$zip" -DestinationPath $dir
    Import-Module "$dir\UsaBanner\UsaBanner.psd1"
    Deploy-UsaBanner -Company Contoso -WhatIf
    Deploy-UsaBanner -Company Contoso
    Get-UsaBanner

The deploy copies the module to Windows PowerShell's modules folder for every
user, writes the banners, sets OpenSSH's default shell to a PowerShell where it
is not one (the banner after login lives in the PowerShell profile, which
`cmd.exe` never runs), and registers a periodic job,
`\UsagiTools\UsaBanner sample`, that samples the host every 15 minutes as
SYSTEM. It never restarts sshd, so that a deploy over SSH keeps its own
session: the SSH banner shows from sshd's next start. Restart it from a
console or a WinRM session, then try a new SSH session before closing the old
one.

## Group Policy, for a domain's hosts

`Deploy-UsaBannerGPO` makes one Group Policy object, `UsaBanner` by default
(`-Name` for another), that puts the module and one configuration (the
package) on the domain's Windows servers and Ubuntu hosts, and keeps them
current: a new publish is the update path.

Run it on a domain controller, or a domain member with the Group Policy
Management tools, as someone who may edit Group Policy objects and write
NETLOGON and SYSVOL. Windows PowerShell 5.1 hands the work to PowerShell 7. The
package is built from the flags `Deploy-UsaBanner` takes, or from the
configuration file `-Path` names; each host takes its tier and role from its
own AD Description unless the package sets them. A package that turns the
update channel on is refused: the GPO is the update path.

Unpack each release into a fresh folder, and keep your configuration outside
it: the publish stages the module's folder, and refuses one that holds a file
the module's manifest does not list (`docs/DECISIONS.md`, D32). A first run
with `-WhatIf` changes nothing and says what it would do. Then a real one,
which links the GPO where you name:

    Import-Module ./UsaBanner/UsaBanner.psd1
    Deploy-UsaBannerGPO -Company Contoso -Environment PROD -WhatIf
    Deploy-UsaBannerGPO -Company Contoso -Environment PROD -LinkTarget 'OU=Servers,DC=ad,DC=example', 'OU=Linux,DC=ad,DC=example'

A run reads and checks everything before it writes anything, then:

- Stages on the PDC emulator, for Windows in `\\<pdc>\NETLOGON\UsaBanner` and for
  Ubuntu in `\\<pdc>\SYSVOL\<domain>\Ubuntu\scripts\UsaBanner`: the package
  (`usabanner.json`), the module folder, and a `.usabanner-gpo` file that marks
  the folder as the command's. Ubuntu also gets `adsys-startup.sh`. Only files
  that differ are written, each with LF line endings; files that are no longer in
  the module are removed; a folder that holds files and has no mark is someone
  else's, and the run stops before writing anything.
- Makes the GPO, or overwrites the one of that name with warnings that say what
  changes. It finds the GPO by its name, so after a rename every publish needs
  `-Name`: where no GPO has the name and another one carries the banner's task,
  `UsaBanner sync`, the run stops and names it. Ubuntu needs the ADSys assets
  folder, `SYSVOL\<domain>\Ubuntu` with a `GPT.INI` in it; without it the run
  warns and does the Windows half only. The `Version` in that `GPT.INI` goes up
  when the Ubuntu copy changed, so ADSys downloads it again.
- Links the GPO at each `-LinkTarget`. Without one the links stay as they are,
  and a GPO linked nowhere applies to no host: the run warns, and links nothing.
- Warns while a GPO of the banner before V1 is still linked and enabled anywhere,
  and when no deploy-usawinssh GPO is linked (a server without PowerShell 7 gets
  no banner until that policy installs it). Then it reads everything back, a
  line each.

Whoever can write NETLOGON and SYSVOL can change what runs as SYSTEM, or as root,
on every host the GPO reaches: keep those rights narrow.

What each OS does after that:

- **Windows servers**, at their next policy refresh (or `gpupdate /force`): an
  immediate task, "UsaBanner sync", runs once as SYSTEM, on servers and domain
  controllers only. It runs `Sync-UsaBanner.ps1` from NETLOGON in Windows
  PowerShell 5.1, which hands over to pwsh and deploys the package; a deploy that
  changes nothing writes nothing. Its log is `%SystemRoot%\Logs\UsaBanner\sync.log`.
- **Ubuntu hosts** (Ubuntu Pro, ADSys): `adsys-startup.sh` runs at boot as a
  startup script and hands the deploy to a systemd unit. A path unit on ADSys's
  copy of `GPT.INI` runs it again once ADSys has downloaded a new publish (it
  refreshes every 90 minutes), so a new publish needs no reboot. The log is
  `journalctl -t usabanner`.

## Custom settings

Every setting is a flag of `Deploy-UsaBanner` and `Deploy-UsaBannerGPO`, and a
deploy keeps them in the host's configuration, `/etc/usabanner/usabanner.json`
or `C:\ProgramData\UsagiTools\Banner\usabanner.json`. A deploy with other
flags says each setting it changes, old and new. For many hosts, keep one
configuration file and give it to every deploy and publish with `-Path`; flags
beside `-Path` change only what they name.

- **The host's identity.** The naming standard that decodes a host's name into
  site, kind and OS comes from a configuration file alone; its defaults are
  examples (`docs/DECISIONS.md`, D20). The VLANs come from `-VlanFile`, a CSV
  or TSV of name, tag and CIDR, with a colour and a short name for the badge.
- **Tier and role.** `-Environment` (UNSET, DEV-TEST, LAB, PROD or PUB) and
  `-Role`. Left at UNSET and empty, a domain-joined host takes both from its AD
  Description, written `<TIER> : <role>`, as `PROD : Web front end`.
- **Art.** `-BannerImage` picks the art: `os`, the default, a server pictogram
  in the OS's colour; `os-logo`, the logo of the OS the host runs; or any name
  `Show-UsaBannerArt -List` shows. A logo you cannot or will not contribute
  stays yours: make it with `New-UsaBannerArt -OutFile` and deploy it with
  `-ArtPath`, which carries it in your configuration to every host the
  configuration reaches, and never into the module (D31).

## Check, update and remove

- **`Get-UsaBanner`** says what is deployed on the host and whether each part
  is in place, as a login would see it now: the configuration, each banner, the
  SSH banner's line in sshd's configuration and whether sshd has read it, the
  stock scripts, the periodic job, the module's copy, the update channel, and
  any part of the banner before V1 still on the host.
- **The update channel** is off unless `-Update notify` or `-Update install`
  turns it on: a daily job that looks for a newer release at the address
  `-UpdateSource` gives (this project's releases on GitHub when it gives
  none), checks its archive against `SHA256SUMS`, and either
  says at login that an update is there or installs it (`docs/DECISIONS.md`,
  D14). Under Group Policy the GPO is the update path, and a package that turns
  the channel on is refused.
- **`Remove-UsaBanner`** takes the banners off and leaves the host as it was
  before the first deploy: only what the deploy's record says it changed is
  changed back, so a stock script someone else turned off stays off.

## Moving off the banner before V1

This project's first banner, which `install.sh` installed on Ubuntu and
`windows/Install-ManatechBanner.ps1` on Windows Server, is replaced by
UsaBanner: `Deploy-UsaBanner -ReplaceOldBanner` takes it off a host first (its
jobs, its files, its sshd lines, the copy of this repository its update job
pulled), turns back on what it turned off, then deploys UsaBanner. The Group
Policy runners pass `-ReplaceOldBanner` at every run. Its code left this
repository on 2026-10-29; its own documentation, as it last stood, is
[docs/OLD-BANNER.md at 7bae2be](https://github.com/Manate-ch/deploy-usabanner/blob/7bae2bef729f940dd208f38c965a34003646364b/docs/OLD-BANNER.md).

## Bugs, ideas and logos

Issues and pull requests are welcome: `CONTRIBUTING.md` says how, and how to
add a logo to the art.

The logos are drawn by this project, to identify what a host runs, and show
only where an admin turns them on. Windows is a trademark of the Microsoft
group of companies, and Ubuntu a registered trademark of Canonical Ltd. Tux
was originally drawn by Larry Ewing using The GIMP. This project is not
affiliated with or endorsed by their owners; `UsaBanner/NOTICE` has the
details. The code is under the MIT licence (`LICENSE`).
<!-- command reference: begin. build/Update-UsaBannerReadme.ps1 writes what is between these two lines, from the commands' help: edit the help, then run it -->
## Command reference

The module's commands and every flag they take, from each command's own help, which `Get-Help <command> -Full` shows too.

- [Deploy-UsaBanner](#deploy-usabanner-1): Deploys this host's banners: the console's before login, the SSH banner before authentication, and the banner after login.
  - [-Path](#-path), [-Company](#-company), [-Environment](#-environment), [-Role](#-role), [-BannerImage](#-bannerimage), [-ArtPath](#-artpath), [-Border](#-border), [-BorderChar](#-borderchar), [-BorderCap](#-bordercap), [-ColorPreset](#-colorpreset), [-ColorMode](#-colormode), [-Glyphs](#-glyphs), [-Legal](#-legal), [-LegalText](#-legaltext), [-Voice](#-voice), [-PreInit](#-preinit), [-PreLogon](#-prelogon), [-VlanFile](#-vlanfile), [-Services](#-services), [-Update](#-update), [-UpdateSource](#-updatesource), [-ReplaceOldBanner](#-replaceoldbanner), [-WhatIf](#-whatif), [-Confirm](#-confirm)
- [Deploy-UsaBannerGPO](#deploy-usabannergpo): Makes the Group Policy that deploys the banners on the domain's Windows servers and Ubuntu hosts, and keeps them current.
  - [-Path](#-path-1), [-Company](#-company-1), [-Environment](#-environment-1), [-Role](#-role-1), [-BannerImage](#-bannerimage-1), [-ArtPath](#-artpath-1), [-Border](#-border-1), [-BorderChar](#-borderchar-1), [-BorderCap](#-bordercap-1), [-ColorPreset](#-colorpreset-1), [-ColorMode](#-colormode-1), [-Glyphs](#-glyphs-1), [-Legal](#-legal-1), [-LegalText](#-legaltext-1), [-Voice](#-voice-1), [-PreInit](#-preinit-1), [-PreLogon](#-prelogon-1), [-VlanFile](#-vlanfile-1), [-Services](#-services-1), [-Update](#-update-1), [-UpdateSource](#-updatesource-1), [-Name](#-name), [-LinkTarget](#-linktarget), [-Domain](#-domain), [-WhatIf](#-whatif-1), [-Confirm](#-confirm-1)
- [Enter-UsaPSSession](#enter-usapssession): Enters a PowerShell session on a host, with the host's banner after login printed first.
  - [-ComputerName](#-computername), [-Credential](#-credential), [-Port](#-port), [-UseSSL](#-usessl), [-ConfigurationName](#-configurationname), [-Authentication](#-authentication), [-SessionOption](#-sessionoption), [-HostName](#-hostname), [-UserName](#-username), [-KeyFilePath](#-keyfilepath), [-Subsystem](#-subsystem), [-ConnectingTimeout](#-connectingtimeout), [-Options](#-options), [-Session](#-session), [-ColorMode](#-colormode-2), [-Glyphs](#-glyphs-2)
- [Get-UsaBanner](#get-usabanner): Shows the banners Deploy-UsaBanner put on this host, and whether each part of them is in place.
  - [-Moment](#-moment)
- [New-UsaBannerArt](#new-usabannerart): Turns an image into banner art: plain ASCII characters, with a colour for each part where the terminal has colour.
  - [-Path](#-path-2), [-Width](#-width), [-Height](#-height), [-Colors](#-colors), [-Background](#-background), [-Fill](#-fill), [-Style](#-style), [-ColorMode](#-colormode-3), [-OutFile](#-outfile), [-Force](#-force), [-Title](#-title), [-Artist](#-artist), [-Licence](#-licence), [-Source](#-source)
- [Remove-UsaBanner](#remove-usabanner): Takes this host's banners off, and leaves the host as it was before Deploy-UsaBanner.
  - [-WhatIf](#-whatif-2), [-Confirm](#-confirm-2)
- [Show-UsaBanner](#show-usabanner): Draws one of this host's banners, as a configuration sets it.
  - [-Moment](#-moment-1), [-Path](#-path-3), [-Facts](#-facts), [-Os](#-os), [-ColorMode](#-colormode-4), [-Glyphs](#-glyphs-3)
- [Show-UsaBannerArt](#show-usabannerart): Draws one of the module's pieces of art, an art file, or a name in block letters, in colour where the terminal has it; or lists the art there is.
  - [-Name](#-name-1), [-ColorMode](#-colormode-5), [-Os](#-os-1), [-Text](#-text), [-Font](#-font), [-Path](#-path-4), [-List](#-list)

### Deploy-UsaBanner

Deploys this host's banners: the console's before login, the SSH banner
before authentication, and the banner after login.

#### Syntax

```
Deploy-UsaBanner [[-Path] <string>] [[-Company] <string>] [[-Environment] <string>] [[-Role] <string>] [[-BannerImage] <string>] [[-ArtPath] <string>] [[-Border] <string>] [[-BorderChar] <string>] [[-BorderCap] <string>] [[-ColorPreset] <string>] [[-ColorMode] <string>] [[-Glyphs] <string>] [[-Legal] <string>] [[-LegalText] <string[]>] [[-Voice] <string>] [[-PreInit] <string[]>] [[-PreLogon] <string[]>] [[-VlanFile] <string>] [[-Services] <string[]>] [[-Update] <string>] [[-UpdateSource] <string>] [-ReplaceOldBanner] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

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
  /etc/ssh/sshd\_config.d where sshd is installed;
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
- \%ProgramData%\\UsagiTools\\Banner, which only Administrators and SYSTEM
  may change: the configuration, as JSON and as the data file each
  login reads, the SSH banner, and the record of the deploy. It and
  UsagiTools are refused, before anything changes, where they are a
  link, or someone else owns them or may delete what is in them: the
  deploy and the periodic job write there as SYSTEM;
- a block in each PowerShell's all-users profile, which shows the
  banner after an interactive SSH login, never at the console;
- sshd\_config's Banner line, checked with sshd -t; sshd is not
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

The banner after login is drawn alike for every login: pam\_motd gives it
no terminal to ask. -ColorMode and -Glyphs say what the clients of this
host show; auto draws 256 colours and ASCII, which nearly every client
shows.

A host with the old banner, which this project's install.sh or
Install-ManatechBanner.ps1 installed before V1, is refused unless
-ReplaceOldBanner takes that banner off first.

Under Windows PowerShell 5.1 the command runs itself in pwsh (PowerShell
7), and stops with what to install when there is none.

#### Examples

**Example 1**

```powershell
Deploy-UsaBanner -Company Contoso -Environment PROD -WhatIf
```

**Example 2**

```powershell
Deploy-UsaBanner -Company Contoso -Environment LAB -VlanFile ./vlans.csv -ColorMode truecolor -Glyphs unicode
```

**Example 3**

```powershell
Deploy-UsaBanner -Company Contoso -Update notify -UpdateSource https://releases.example.com/usabanner
```

**Example 4**

```powershell
Deploy-UsaBanner -Path ./contoso.json -Environment DEV-TEST
```

**Example 5**

```powershell
Deploy-UsaBanner -Path ./contoso.json -ArtPath ./contoso-logo.json
```

**Example 6**

```powershell
Deploy-UsaBanner -Company Contoso -ReplaceOldBanner -WhatIf
```

#### Parameters

##### -Path

A configuration file to start from, instead of the defaults; the flags
change it setting by setting. The naming standard comes from a file
alone.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Company

The company name, for "Welcome to \<company\>": printable ASCII, 48
characters at most.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Environment

The tier: UNSET, DEV-TEST, LAB, PROD or PUB. UNSET, the default, takes
the tier from this host's AD Description, as "PROD : Web front end"
gives PROD.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: UNSET, DEV-TEST, LAB, PROD, PUB

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Role

What this host is for, in a few words, shown after login: printable
ASCII, 64 characters at most. Empty, the default, takes the role from
this host's AD Description, as "PROD : Web front end" gives Web front
end.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -BannerImage

The art: a piece of the module's art (Show-UsaBannerArt -List), os for
the pictogram in the host's OS colour, or os-logo for the logo of the OS
the host runs (Windows, Ubuntu, or Tux on any other Linux).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ArtPath

Art of your own, drawn in place of the module's: a .json file as
New-UsaBannerArt -OutFile saves it (look at it first with
Show-UsaBannerArt -Path). The art goes into the configuration, so it
reaches every host the configuration does, and never into the module:
for a logo you cannot or will not contribute. It keeps the rules of the
module's own art. Not with -BannerImage.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Border

The box's lines and corners. The Unicode sets show after login only,
with Classic before login.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: Classic, Hash, Star, Equals, Round, Bevel, PipeUnderscore, Wavy, OneChar, Rounded, Single, Double, Heavy, Block

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -BorderChar

The character the OneChar set draws with: given with -Border OneChar, or
a -Path file whose set is OneChar. With any other set it is refused, as
nothing would draw it.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -BorderCap

An ASCII face for the top line, such as (^\_^).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 8
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ColorPreset

The colour scheme: UsagiTools, Classic16, HighContrast, Mono or Custom.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: UsagiTools, Classic16, HighContrast, Mono, Custom

Required: False
Position: 9
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ColorMode

The colours the clients of this host show: auto, truecolor, 256, 16 or
none.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: auto, truecolor, 256, 16, none

Required: False
Position: 10
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Glyphs

Whether the clients of this host show Unicode: auto, unicode or ascii.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: auto, unicode, ascii

Required: False
Position: 11
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Legal

The legal text before login: L1 (friendly) to L5 (maximum).

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: L1, L2, L3, L4, L5, custom

Required: False
Position: 12
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -LegalText

Your own legal text, a string per line, printable ASCII.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 13
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Voice

A meme voice for a lab VM: plain, uwu, random or leet.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: plain, uwu, random, leet

Required: False
Position: 14
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -PreInit

What the console shows before login besides the company and the legal
text: HostName, Ip, both, or None.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:
Accepted values: HostName, Ip, None

Required: False
Position: 15
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -PreLogon

The same for the SSH banner, which anyone who starts to log in can read.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:
Accepted values: HostName, Ip, None

Required: False
Position: 16
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -VlanFile

A CSV or TSV file of the VLANs: name, tag and cidr, then color and short
(the badge's name) where wanted.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 17
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Services

The services the banner after login watches, by name; default for the
OS's own list.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 18
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Update

The update channel: off (the default), notify or install.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: off, notify, install

Required: False
Position: 19
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -UpdateSource

The https address the releases' files are downloaded from: SHA256SUMS
and UsaBanner-\<version\>.zip are under it, as under a GitHub repository's
.../releases/latest/download. With the channel on and none given, this
project's: https://github.com/Manate-ch/deploy-usabanner/releases/latest/download.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 20
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ReplaceOldBanner

Takes the old banner off first: the one this project's install.sh
(Ubuntu) or Install-ManatechBanner.ps1 (Windows) installed before V1.
Its files and jobs go, and what it changed comes back as the OS ships
it; then this banner deploys. It runs after every banner is drawn, so a
configuration that fails leaves the old banner in place. A Group Policy
that delivers the old banner puts it back at the next boot or refresh:
take that GPO off the host first. Get-UsaBanner's old banner check says
when it is back.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### -WhatIf

Shows what would happen if the command runs. The command is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Confirm

Prompts you for confirmation before running the command.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### CommonParameters

This command takes the common parameters too, such as -Verbose and -ErrorAction: `Get-Help about_CommonParameters` says what each does.

### Deploy-UsaBannerGPO

Makes the Group Policy that deploys the banners on the domain's Windows
servers and Ubuntu hosts, and keeps them current.

#### Syntax

```
Deploy-UsaBannerGPO [[-Path] <string>] [[-Company] <string>] [[-Environment] <string>] [[-Role] <string>] [[-BannerImage] <string>] [[-ArtPath] <string>] [[-Border] <string>] [[-BorderChar] <string>] [[-BorderCap] <string>] [[-ColorPreset] <string>] [[-ColorMode] <string>] [[-Glyphs] <string>] [[-Legal] <string>] [[-LegalText] <string[]>] [[-Voice] <string>] [[-PreInit] <string[]>] [[-PreLogon] <string[]>] [[-VlanFile] <string>] [[-Services] <string[]>] [[-Update] <string>] [[-UpdateSource] <string>] [[-Name] <string>] [[-LinkTarget] <string[]>] [[-Domain] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

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
  go to NETLOGON\\UsaBanner, for Windows; the same, with the ADSys startup
  script, to SYSVOL\\\<domain\>\\Ubuntu\\scripts\\UsaBanner, for Ubuntu. A file is
  written only where its bytes differ, a file with CRLF line ends is
  written with LF (the run says how many), and a file that is not in the
  payload is removed. A folder that holds files and has no mark is
  someone else's, and is refused, as is a module folder that is, or is
  inside, a place it stages into. The Ubuntu half needs the ADSys assets
  folder (SYSVOL\\\<domain\>\\Ubuntu with its GPT.INI): without it a warning
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
- It warns while the old banner's GPO, the one with the task "Manatech
  MOTD sync", is linked and enabled anywhere (on a host that both apply
  to, the two undo each other at each refresh), and when no GPO of
  deploy-usawinssh is linked and enabled (a server without PowerShell 7
  then gets no banner).
- Everything is read back, a line each: 'ok' or 'FAIL' and the check. The
  run fails if one does.

It returns a line for each change it makes; -WhatIf says what it would
change, shows the ScheduledTasks.xml it would write, and changes nothing.
Servers act at their next policy refresh (or gpupdate /force), Ubuntu hosts
once ADSys has downloaded the new Version and at boot.

#### Examples

**Example 1**

```powershell
Deploy-UsaBannerGPO -Company Contoso -Environment PROD -WhatIf
```

**Example 2**

```powershell
Deploy-UsaBannerGPO -Company Contoso -LinkTarget 'OU=Servers,DC=ad,DC=example', 'OU=Linux,DC=ad,DC=example'
```

**Example 3**

```powershell
Deploy-UsaBannerGPO -Path ./contoso.json -Name 'UsaBanner (lab)' -LinkTarget 'OU=Lab,DC=ad,DC=example'
```

**Example 4**

```powershell
Deploy-UsaBannerGPO -Path ./contoso.json -Domain ad.example -WhatIf
```

#### Parameters

##### -Path

A configuration file to start from, instead of the defaults; the flags
change it setting by setting. The naming standard comes from a file
alone.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Company

The company name, for "Welcome to \<company\>": printable ASCII, 48
characters at most.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 1
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Environment

The tier: UNSET, DEV-TEST, LAB, PROD or PUB. UNSET, the default, takes
the tier from each host's AD Description, as "PROD : Web front end"
gives PROD.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: UNSET, DEV-TEST, LAB, PROD, PUB

Required: False
Position: 2
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Role

What a host is for, in a few words, shown after login: printable ASCII,
64 characters at most. Empty, the default, takes the role from each
host's AD Description, as "PROD : Web front end" gives Web front end.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 3
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -BannerImage

The art: a piece of the module's art (Show-UsaBannerArt -List), os for
the pictogram in each host's OS colour, or os-logo for the logo of the
OS each host runs (Windows, Ubuntu, or Tux on any other Linux).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 4
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ArtPath

Art of your own, drawn in place of the module's: a .json file as
New-UsaBannerArt -OutFile saves it (look at it first with
Show-UsaBannerArt -Path). The art goes into the package, so it reaches
every host the GPO does, and never into the module: for a logo you
cannot or will not contribute. It keeps the rules of the module's own
art. Not with -BannerImage.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 5
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Border

The box's lines and corners. The Unicode sets show after login only,
with Classic before login.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: Classic, Hash, Star, Equals, Round, Bevel, PipeUnderscore, Wavy, OneChar, Rounded, Single, Double, Heavy, Block

Required: False
Position: 6
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -BorderChar

The character the OneChar set draws with.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 7
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -BorderCap

An ASCII face for the top line, such as (^\_^).

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 8
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ColorPreset

The colour scheme: UsagiTools, Classic16, HighContrast, Mono or Custom.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: UsagiTools, Classic16, HighContrast, Mono, Custom

Required: False
Position: 9
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ColorMode

The colours the clients of a host show: auto, truecolor, 256, 16 or
none.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: auto, truecolor, 256, 16, none

Required: False
Position: 10
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Glyphs

Whether the clients of a host show Unicode: auto, unicode or ascii.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: auto, unicode, ascii

Required: False
Position: 11
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Legal

The legal text before login: L1 (friendly) to L5 (maximum).

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: L1, L2, L3, L4, L5, custom

Required: False
Position: 12
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -LegalText

Your own legal text, a string per line, printable ASCII.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 13
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Voice

A meme voice for a lab VM: plain, uwu, random or leet.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: plain, uwu, random, leet

Required: False
Position: 14
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -PreInit

What the console shows before login besides the company and the legal
text: HostName, Ip, both, or None.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:
Accepted values: HostName, Ip, None

Required: False
Position: 15
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -PreLogon

The same for the SSH banner, which anyone who starts to log in can read.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:
Accepted values: HostName, Ip, None

Required: False
Position: 16
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -VlanFile

A CSV or TSV file of the VLANs: name, tag and cidr, then color and short
(the badge's name) where wanted. It is read now, and the package holds
the rows.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 17
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Services

The services the banner after login watches, by name; default for the
OS's own list.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 18
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Update

The update channel. Group Policy takes off only: a package that turns it
on is refused.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: off, notify, install

Required: False
Position: 19
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -UpdateSource

The https address of the update channel's releases. Not for Group Policy.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 20
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Name

The GPO's display name; UsaBanner by default. A GPO this command made and
someone renamed is found only by its new name: where no GPO has this one
and another carries the task UsaBanner sync, the run stops and names it.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 21
Default value: UsaBanner
Accept pipeline input: False
Accept wildcard characters: False
```

##### -LinkTarget

The distinguished names to link the GPO at, as 'OU=Servers,DC=ad,DC=example'
or the domain's own. Each must exist. A link that exists is left as it is
(a disabled one is enabled, with a warning); without this, no link is
made.

```yaml
Type: String[]
Parameter Sets: (All)
Aliases:

Required: False
Position: 22
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Domain

The domain's DNS name; by default, the domain of the computer this runs
on.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 23
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -WhatIf

Shows what would happen if the command runs. The command is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Confirm

Prompts you for confirmation before running the command.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### CommonParameters

This command takes the common parameters too, such as -Verbose and -ErrorAction: `Get-Help about_CommonParameters` says what each does.

### Enter-UsaPSSession

Enters a PowerShell session on a host, with the host's banner after login
printed first.

#### Syntax

**ComputerName (Default)**

```
Enter-UsaPSSession [-ComputerName] <string> [-Credential <pscredential>] [-Port <int>] [-UseSSL] [-ConfigurationName <string>] [-Authentication <AuthenticationMechanism>] [-SessionOption <PSSessionOption>] [-ColorMode <string>] [-Glyphs <string>] [<CommonParameters>]
```

**SSHHost**

```
Enter-UsaPSSession -HostName <string> [-Port <int>] [-UserName <string>] [-KeyFilePath <string>] [-Subsystem <string>] [-ConnectingTimeout <int>] [-Options <hashtable>] [-ColorMode <string>] [-Glyphs <string>] [<CommonParameters>]
```

**Session**

```
Enter-UsaPSSession [-Session] <PSSession> [-ColorMode <string>] [-Glyphs <string>] [<CommonParameters>]
```

#### Description

PowerShell remoting runs no profile, and over SSH a session carries only
PowerShell's own traffic, so no remote session shows the banner after
login by itself. This command opens the session, has the host draw that
banner over it as the host's own logins draw it, prints the lines here,
where this terminal draws the colours, then enters the session.

The host draws with Get-UsaBanner -Moment PostLogon, so UsaBanner must be
deployed there: on Windows, the banner the profile block shows at an SSH
login; on Ubuntu, the one pam\_motd shows. A host with no banner, or a draw
that fails, gives one warning, and the session is entered all the same.

-ColorMode and -Glyphs say what this terminal draws, as USABANNER\_COLOR
and USABANNER\_GLYPHS do in a user's environment, and default to those two
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

#### Examples

**Example 1**

```powershell
Enter-UsaPSSession -HostName h-vsw-app1.ad.example -UserName admin@ad.example
```

**Example 2**

```powershell
Enter-UsaPSSession h-vsw-app1.ad.example -ColorMode 16
```

**Example 3**

```powershell
Enter-UsaPSSession -Session (New-PSSession -HostName h-vsw-app1.ad.example)
```

#### Parameters

##### -ComputerName

The host to reach over WinRM.

```yaml
Type: String
Parameter Sets: ComputerName
Aliases:

Required: True
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Credential

The account for WinRM; the one running this command by default.

```yaml
Type: PSCredential
Parameter Sets: ComputerName
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Port

The port: WinRM's, or SSH's; New-PSSession's own by default.

```yaml
Type: Int32
Parameter Sets: ComputerName, SSHHost
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

##### -UseSSL

WinRM over HTTPS.

```yaml
Type: SwitchParameter
Parameter Sets: ComputerName
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ConfigurationName

The WinRM endpoint on the host, such as PowerShell.7; Windows
PowerShell's by default.

```yaml
Type: String
Parameter Sets: ComputerName
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Authentication

The WinRM authentication mechanism.

```yaml
Type: AuthenticationMechanism
Parameter Sets: ComputerName
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -SessionOption

WinRM session options, from New-PSSessionOption.

```yaml
Type: PSSessionOption
Parameter Sets: ComputerName
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -HostName

The host to reach over SSH, in PowerShell 7.

```yaml
Type: String
Parameter Sets: SSHHost
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -UserName

The SSH user.

```yaml
Type: String
Parameter Sets: SSHHost
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -KeyFilePath

The SSH private key file.

```yaml
Type: String
Parameter Sets: SSHHost
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Subsystem

The SSH subsystem PowerShell runs as on the host; powershell by default.

```yaml
Type: String
Parameter Sets: SSHHost
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ConnectingTimeout

How long the SSH connection may take to open, in milliseconds;
New-PSSession's own limit by default.

```yaml
Type: Int32
Parameter Sets: SSHHost
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Options

SSH options, as a hashtable, as New-PSSession takes them.

```yaml
Type: Hashtable
Parameter Sets: SSHHost
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Session

A session already open, from New-PSSession.

```yaml
Type: PSSession
Parameter Sets: Session
Aliases:

Required: True
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ColorMode

The colours this terminal draws: truecolor, 256, 16 or none.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: truecolor, 256, 16, none

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Glyphs

Whether this terminal draws Unicode: unicode or ascii.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: unicode, ascii

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### CommonParameters

This command takes the common parameters too, such as -Verbose and -ErrorAction: `Get-Help about_CommonParameters` says what each does.

### Get-UsaBanner

Shows the banners Deploy-UsaBanner put on this host, and whether each
part of them is in place.

#### Syntax

```
Get-UsaBanner [[-Moment] <string>] [<CommonParameters>]
```

#### Description

Without -Moment, one object for this host:

```text
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
```

A check is ok; off, when a part is not in place for a reason outside
the banner (no OpenSSH server, a logon notice someone else set, another
shell for SSH logins); missing; differs, when it is not as a deploy
leaves it; stale, when it was drawn for another name, address,
configuration or AD Description, when the periodic job has not sampled
for 20 minutes, or when sshd on Windows started before sshd\_config last
changed (a deploy leaves its restart to you); invalid, when the
configuration cannot be read; or unknown, when this session cannot tell.
On Ubuntu, which banner sshd sends needs root to read; on Windows, a
user may not see the periodic job's task. Run it as root, or as an
administrator, for every answer.

With -Moment, a banner as installed, a string per line:

```text
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
```

It changes nothing. Under Windows PowerShell 5.1 the command runs itself
in pwsh (PowerShell 7), and its answer comes back as text.

#### Examples

**Example 1**

```powershell
Get-UsaBanner
```

**Example 2**

```powershell
(Get-UsaBanner).Checks | Where-Object State -ne ok
```

**Example 3**

```powershell
Get-UsaBanner PreLogon
```

#### Parameters

##### -Moment

PostLogon, PreLogon or PreInit: show that banner as installed.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: PostLogon, PreLogon, PreInit

Required: False
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### CommonParameters

This command takes the common parameters too, such as -Verbose and -ErrorAction: `Get-Help about_CommonParameters` says what each does.

### New-UsaBannerArt

Turns an image into banner art: plain ASCII characters, with a colour for
each part where the terminal has colour.

#### Syntax

```
New-UsaBannerArt [-Path] <string> [-Width <int>] [-Height <int>] [-Colors <int>] [-Background <string>] [-Fill <string>] [-Style <string>] [-ColorMode <string>] [-OutFile <string>] [-Force] [-Title <string>] [-Artist <string>] [-Licence <string>] [-Source <string>] [<CommonParameters>]
```

#### Description

Returns one string per line of the art, with the colour escapes in it, as
Show-UsaBannerArt does; at the console the lines print as the picture.
-OutFile saves the art too, as a JSON file Show-UsaBannerArt -Path draws.

```text
+------------------+----------------------------------------------------+
| Image            | Read by                                            |
+------------------+----------------------------------------------------+
| PNG              | the module itself, on every system                 |
| JPEG, GIF, BMP,  | Windows' own decoder, System.Drawing; on Linux,    |
| TIFF             | ImageMagick (sudo apt install imagemagick)         |
| other formats    | ImageMagick, on Linux only                         |
+------------------+----------------------------------------------------+
```

How the image becomes art:

- The background is left out: transparent pixels; or else, when one
  colour holds half of the image's edge or more, the pixels of that colour
  the edge reaches. -Background names the colour instead, or none keeps
  every pixel that is not transparent.
- Colours: at most -Colors, taken from the image. A colour too dark for a
  dark terminal is lightened until it shows.
- Shape style, for logos: each character's shape follows the outline, each
  character cell read as 2 x 4 dots. The largest part the picture
  encloses, such as the disc inside a badge's ring, is drawn as fill: a
  gap before login, and solid in colour (-Fill).
- Ramp style, for photos: each character by brightness, from . to @, the
  brightest densest, for terminals with a dark background.
- auto, the default style, is shape for an image with a background and
  few colours, and ramp for any other. -Verbose says which it took, with
  the colours and the background.

The art is 40 columns wide unless -Width or -Height says otherwise, or
narrower for a small image, at a column to two pixels. Its rows keep the
image's shape: a character cell is about twice as tall as it is wide. Art
may take 64 columns and 30 rows; a picture that would take more is made
smaller, with a warning when -Width or -Height asked for the size.

Under Windows PowerShell 5.1 the command runs itself in pwsh (PowerShell
7), and stops with what to install when there is none.

#### Examples

**Example 1**

```powershell
New-UsaBannerArt -Path ./logo.png
```

**Example 2**

```powershell
New-UsaBannerArt -Path ./logo.png -Width 30 -Colors 3 -OutFile ./logo.json
```

**Example 3**

```powershell
New-UsaBannerArt -Path ./logo.jpg -Background '#FFFFFF' -ColorMode none
```

#### Parameters

##### -Path

The image file.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: True
Position: 0
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Width

The art's width in characters, 1 to 64.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Height

The art's height in rows, 1 to 30. Given with -Width, the picture is
stretched to fit both.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 0
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Colors

The most colours, 1 to 16; 6 by default.

```yaml
Type: Int32
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: 6
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Background

auto, the default; none, to keep every pixel that is not transparent; or a
colour as \#RRGGBB, to leave out the pixels of about that colour that the
image's edge reaches.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: auto
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Fill

Shape style: the part drawn as fill, a gap before login and solid in
colour. auto, the default, is the largest part the picture encloses;
none draws no part as fill; a colour as \#RRGGBB picks the part nearest
it.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: auto
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Style

auto, the default; shape; or ramp.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: auto, shape, ramp

Required: False
Position: Named
Default value: auto
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ColorMode

How the lines returned are coloured, as for Show-UsaBannerArt; auto by
default. The saved file holds the colours whatever the mode.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: auto, truecolor, 256, 16, none

Required: False
Position: Named
Default value: auto
Accept pipeline input: False
Accept wildcard characters: False
```

##### -OutFile

A JSON file to save the art in.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Force

Replace the -OutFile file when there is one.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Title

The art's title in the saved file; the image's name by default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Artist

Who made the image, in the saved file; unknown by default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Licence

The image's licence, in the saved file; unknown by default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Source

Where the art came from, in the saved file; by default, the image's file
name and how the art was made.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### CommonParameters

This command takes the common parameters too, such as -Verbose and -ErrorAction: `Get-Help about_CommonParameters` says what each does.

### Remove-UsaBanner

Takes this host's banners off, and leaves the host as it was before
Deploy-UsaBanner.

#### Syntax

```
Remove-UsaBanner [-WhatIf] [-Confirm] [<CommonParameters>]
```

#### Description

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
scheduler, \\UsagiTools\\, once no other task is in it; takes the block
out of each all-users
profile, and the Banner
line out of sshd\_config, turning back on any Banner the deploy turned
off (sshd -t checks it; restart sshd yourself); puts the logon notice
back as it was, where it still holds the banner's text; deletes
\%ProgramData%\\UsagiTools\\Banner and the module's copy the deploy made.
It refuses, before anything changes, where UsagiTools or Banner is a
link, or someone else owns it or may delete what is in it, as the
deploy does: the record it reads there says what to delete.

PowerShell itself stays: it may serve more than the banner.

Under Windows PowerShell 5.1 the command runs itself in pwsh (PowerShell
7), and stops with what to install when there is none.

#### Examples

**Example 1**

```powershell
Remove-UsaBanner -WhatIf
```

**Example 2**

```powershell
Remove-UsaBanner
```

#### Parameters

##### -WhatIf

Shows what would happen if the command runs. The command is not run.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: wi

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Confirm

Prompts you for confirmation before running the command.

```yaml
Type: SwitchParameter
Parameter Sets: (All)
Aliases: cf

Required: False
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### CommonParameters

This command takes the common parameters too, such as -Verbose and -ErrorAction: `Get-Help about_CommonParameters` says what each does.

### Show-UsaBanner

Draws one of this host's banners, as a configuration sets it.

#### Syntax

```
Show-UsaBanner [[-Moment] <string>] [-Path <string>] [-Facts <IDictionary>] [-Os <string>] [-ColorMode <string>] [-Glyphs <string>] [<CommonParameters>]
```

#### Description

Returns one string per line, with the colour escapes in it; at the
console the lines print as the banner.

```text
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
```

The configuration is the file -Path names, with the defaults for every
setting it leaves out; without -Path, the defaults alone.

-Facts is what the banner shows about the host, as a hashtable: Name
(the host name, with its domain), Ip, Os, Uptime, Cpu, Memory, Disks,
Sessions, Time, Ipv4, Updates, Reboot, Services, Problems and Checked,
in the shapes UsaBanner\\Private\\PostLogin.ps1 gives. A fact left out
gets no row. Without -Facts, the banner shows this host's own: on Linux,
what UsaBanner/linux/facts.sh collects; on Windows, what the module
reads from CIM, the registry and .NET. The SSH banner and the console
show the name without its domain.

The tier and the role are the configuration's environment and role.
Where it leaves them unset, this host's own banner, drawn without
-Facts, takes them from the AD Description the periodic job cached, as
"PROD : Web front end" gives both.

-ColorMode is as for Show-UsaBannerArt; auto also takes the mode the
configuration sets for this host. -Glyphs auto reads USABANNER\_GLYPHS,
then the glyphs the configuration sets for this host, then the locale
(LC\_ALL, LC\_CTYPE, LANG): a client that is not UTF-8 gets ascii, which
draws a Unicode border set as Classic. On Windows, the locale is not
read: unicode.

Under Windows PowerShell 5.1 the command runs itself in pwsh
(PowerShell 7), and stops with what to install when there is none.

#### Examples

**Example 1**

```powershell
Show-UsaBanner
```

**Example 2**

```powershell
Show-UsaBanner PreLogon -Path ./usabanner.json
```

**Example 3**

```powershell
Show-UsaBanner -Path ./usabanner.json -Facts @{ Name = 'h-vsl-web1.ad.example'; Ip = '10.20.40.80'; Uptime = '12d 6h 40m' }
```

**Example 4**

```powershell
Show-UsaBanner PreInit -Os windows
```

#### Parameters

##### -Moment

PostLogon, PreLogon or PreInit; PostLogon by default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: PostLogon, PreLogon, PreInit

Required: False
Position: 0
Default value: PostLogon
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Path

A configuration file. Without it, the defaults.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Facts

What the banner shows about the host, as a hashtable.

```yaml
Type: IDictionary
Parameter Sets: (All)
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Os

Whose colour the art takes, and for PreInit, whose console: windows,
ubuntu or linux (any other system); auto, the default, is this host's.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: auto, windows, ubuntu, linux

Required: False
Position: Named
Default value: auto
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ColorMode

auto, truecolor, 256, 16 or none; auto by default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: auto, truecolor, 256, 16, none

Required: False
Position: Named
Default value: auto
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Glyphs

auto, unicode or ascii; auto by default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: auto, unicode, ascii

Required: False
Position: Named
Default value: auto
Accept pipeline input: False
Accept wildcard characters: False
```

##### CommonParameters

This command takes the common parameters too, such as -Verbose and -ErrorAction: `Get-Help about_CommonParameters` says what each does.

### Show-UsaBannerArt

Draws one of the module's pieces of art, an art file, or a name in block
letters, in colour where the terminal has it; or lists the art there is.

#### Syntax

**Draw (Default)**

```
Show-UsaBannerArt [[-Name] <string>] [-ColorMode <string>] [-Os <string>] [<CommonParameters>]
```

**File**

```
Show-UsaBannerArt -Path <string> [-ColorMode <string>] [-Os <string>] [<CommonParameters>]
```

**Text**

```
Show-UsaBannerArt -Text <string> [-ColorMode <string>] [-Font <string>] [<CommonParameters>]
```

**List**

```
Show-UsaBannerArt -List [<CommonParameters>]
```

#### Description

Returns one string per line of the art, with the colour escapes in it;
at the console the lines print as the picture.

```text
+-----------+------------------------------------------------------+
| ColorMode | Draws                                                |
+-----------+------------------------------------------------------+
| auto      | the user's USABANNER_COLOR; else plain when NO_COLOR |
|           | is set; else what the terminal says it supports      |
| truecolor | 24-bit colour, with the gradients and the sheen      |
| 256       | each cell in the nearest of the 256 xterm colours    |
| 16        | one basic colour per part, no gradient               |
| none      | the plain ASCII art, exactly as shown before login   |
+-----------+------------------------------------------------------+
```

Art drawn in the OS colour takes this host's: Windows blue, Ubuntu
orange, or a neutral grey on any other system. -Os draws it in another
OS's colour instead.

With -Text, a name set in block letters instead, as the banner sets the
company's: in the welcome line's colours from left to right, in the
Pixel font when it fits 64 columns; else in the Small font, on two lines
if it must; else in spaced capitals; else as written. Lower case comes
out in capitals. With -Font too, the name is set in that font alone, and
may come out at most 64 columns wide.

With -Path, the art in a file instead, such as one New-UsaBannerArt
saved; it must keep the same rules as the module's own art.

With -List, one line per piece instead: its name, its folder (base for
ours, apps for another owner's logo, drawn by us), its size in columns by
rows, its title, who drew it (and whose logo it is), and its licence.

Under Windows PowerShell 5.1 the command runs itself in pwsh
(PowerShell 7), and stops with what to install when there is none.

#### Examples

**Example 1**

```powershell
Show-UsaBannerArt
```

**Example 2**

```powershell
Show-UsaBannerArt -Name rabbit -ColorMode 256
```

**Example 3**

```powershell
Show-UsaBannerArt -Name server -Os ubuntu
```

**Example 4**

```powershell
Show-UsaBannerArt -Text 'Contoso LLC'
```

**Example 5**

```powershell
Show-UsaBannerArt -Text 'Contoso Pharmaceuticals' -ColorMode none
```

**Example 6**

```powershell
Show-UsaBannerArt -Path ./logo.json -ColorMode none
```

**Example 7**

```powershell
Show-UsaBannerArt -List
```

#### Parameters

##### -Name

The art to draw; -List shows what there is.

```yaml
Type: String
Parameter Sets: Draw
Aliases:

Required: False
Position: 0
Default value: rabbit
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ColorMode

One of the modes in the table; auto by default.

```yaml
Type: String
Parameter Sets: Draw, File, Text
Aliases:
Accepted values: auto, truecolor, 256, 16, none

Required: False
Position: Named
Default value: auto
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Os

Whose colour art drawn in the OS colour takes: windows, ubuntu or linux
(any other system); auto, the default, is this host's.

```yaml
Type: String
Parameter Sets: Draw, File
Aliases:
Accepted values: auto, windows, ubuntu, linux

Required: False
Position: Named
Default value: auto
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Text

A name to set in block letters instead of drawing a piece of art.

```yaml
Type: String
Parameter Sets: Text
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Font

One font to set -Text in: pixel or small. Without it, the name takes
the first form that fits, as on the banner.

```yaml
Type: String
Parameter Sets: Text
Aliases:

Required: False
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Path

An art file to draw instead of a piece of the module's art.

```yaml
Type: String
Parameter Sets: File
Aliases:

Required: True
Position: Named
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -List

List every piece of art instead of drawing one.

```yaml
Type: SwitchParameter
Parameter Sets: List
Aliases:

Required: True
Position: Named
Default value: False
Accept pipeline input: False
Accept wildcard characters: False
```

##### CommonParameters

This command takes the common parameters too, such as -Verbose and -ErrorAction: `Get-Help about_CommonParameters` says what each does.

<!-- command reference: end -->
