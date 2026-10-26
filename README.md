# deploy-usamotd

The Manatech MOTD: a colour login banner for Ubuntu 24.04, and the same
banner for Windows Server 2022 and later in `windows/`. Art, then a host
panel: the host name decoded with a naming schema, the VLAN and the
environment, OS, role, load, memory, disk and addresses, and one line per
problem the health check finds. `rootfs/` mirrors the target filesystem:
each file goes to the same path under `/`.

The data files hold **example** values (a naming schema, VLANs, colours).
Replace them with your own before the first host: see "Your own data".

**V1 is being built beside this code**, as the PowerShell 7 module in
`UsaBanner/`: what it will do is in `docs/SPEC.md`, the order of the work in
`docs/V1-PLAN.md`. Until it is done, everything below is how to install. To
see how far it has got, from a clone:

    Import-Module ./UsaBanner/UsaBanner.psd1
    Show-UsaBannerArt                  # or -ColorMode truecolor, 256, 16 or none
    Show-UsaBannerArt -List            # every piece of art there is
    Show-UsaBannerArt server -Os ubuntu   # in an OS's colour: windows, ubuntu or linux
    Show-UsaBannerArt -Text 'Contoso LLC' # a name in block letters
    Show-UsaBannerArt tux              # a logo: tux, windows or ubuntu
    New-UsaBannerArt ./logo.png        # an image as art; -OutFile ./logo.json saves it
    Show-UsaBannerArt -Path ./logo.json   # art saved in a file
    Show-UsaBanner                     # the banner after login, from the defaults
    Show-UsaBanner PreLogon -Path ./usabanner.json   # the SSH banner a configuration sets
    Show-UsaBanner PreInit             # the console's banner; on Windows, the logon notice

Each command, and every flag it takes, is in the [command reference](#command-reference) below.

`Show-UsaBanner` draws a banner as a configuration file sets it, with the
defaults for anything the file leaves out. The module does not read a host's
facts yet, so the banner after login shows the ones `-Facts` hands it, and
otherwise only the host's name: `Get-Help Show-UsaBanner -Full` lists them.

`New-UsaBannerArt` reads PNG itself, on every system. It reads JPEG, GIF, BMP
and TIFF through Windows' own decoder, and on Linux any other format through
ImageMagick (`sudo apt install imagemagick`). How it draws:
`Get-Help New-UsaBannerArt -Full`.

The logos are drawn by this project, to identify what a host runs, and show
only where an admin turns them on. Windows is a trademark of the Microsoft
group of companies, and Ubuntu a registered trademark of Canonical Ltd. Tux
was originally drawn by Larry Ewing using The GIMP. This project is not
affiliated with or endorsed by their owners; `UsaBanner/NOTICE` has the
details.

Bugs, ideas and logos are welcome, as issues and merge requests:
`CONTRIBUTING.md` says how, and how to add your own logo to the art.

## Quickstart

For a host that Group Policy does not reach: off the domain, at another
site, a test box. It clones the repo, installs from its clone and keeps
itself current from it. Domain hosts get the same from Group Policy (see
"Group Policy delivery").

These lines clone this project anonymously. A private fork carrying your own
data needs a deploy token instead: see "Install on one host".

**Ubuntu 24.04**, with sudo (needs `git`):

    sudo git clone https://gitlab.manate.ch/usagitools/deploy-usamotd.git /opt/manatech-motd
    sudo sh /opt/manatech-motd/install.sh --all
    sudoedit /etc/manatech/motd.conf        # ENV_NAME=LAB  ROLE="what this host is for"

**Windows Server 2022 or later**, in an elevated PowerShell. You need Git
for Windows for the update task. The banner shows at SSH login, so OpenSSH
Server comes first; skip the first two lines where `sshd` already runs:

    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Set-Service -Name sshd -StartupType Automatic; Start-Service sshd    # the first start writes sshd_config
    git clone https://gitlab.manate.ch/usagitools/deploy-usamotd.git C:\ProgramData\Manatech\repo
    C:\ProgramData\Manatech\repo\windows\Install-ManatechBanner.ps1 -DefaultShell any -SshBanner -UpdateTask -WhatIf
    C:\ProgramData\Manatech\repo\windows\Install-ManatechBanner.ps1 -DefaultShell any -SshBanner -UpdateTask
    notepad C:\ProgramData\Manatech\motd.psd1    # EnvName = 'LAB'; Role = 'what this host is for'
    Restart-Service sshd                         # then test from a NEW session

The capability comes with an enabled firewall rule, `OpenSSH-Server-In-TCP`,
that lets TCP 22 in from any address. Narrow it where that is too wide.

**Windows without Git for Windows:** the same banner from a download, with no
update task. To update, run the block again:

    $src = Join-Path $env:TEMP ('manatech-motd-' + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $src
    Invoke-WebRequest -Uri https://gitlab.manate.ch/usagitools/deploy-usamotd/-/archive/main/deploy-usamotd-main.zip -OutFile "$src\motd.zip" -UseBasicParsing
    Unblock-File -LiteralPath "$src\motd.zip"
    Expand-Archive -LiteralPath "$src\motd.zip" -DestinationPath $src
    $repo = (Get-ChildItem -LiteralPath $src -Directory | Select-Object -First 1).FullName
    & "$repo\windows\Install-ManatechBanner.ps1" -DefaultShell any -SshBanner
    Remove-Item -LiteralPath $src -Recurse
    Restart-Service sshd

`--all` and `-UpdateTask` pull `main` again on a schedule, and the banner runs
as root (SYSTEM) at every login. Set them up only from a copy whose `main` you
trust. "Install on one host" says what each sets up and how to check a host;
"Environments" lists the environment names.

## Your own data

The data files in `rootfs/usr/local/share/manatech/` ship with **example**
values, so the banner draws something sensible out of the box:

| File | Holds | Example rows |
|---|---|---|
| `schema-names.tsv` | the naming schema host names are decoded with | an `HQ` site, a branch, a cloud site, two labs |
| `vlans.tsv` | the VLAN table behind the badge and the `vlan` row | `10.20.x.x` VLANs at `HQ` |
| `envs.tsv` | environment -> colour | PROD, LAB, DEV, TEST, STAGE, PUB |
| `colors.tsv` | the named colours the other files refer to | a 16-colour palette |
| `manatech.art` | the art above the panel | the Manatech emblem |
| `welcome.tsv` | the welcome line under the art: the name and its two gradient colours | Manatech |

The company shows in two more places, outside that folder: the art again,
uncoloured, in `rootfs/etc/issue.net` (the pre-login SSH banner; a test keeps
it the same as `manatech.art`), and the name in the console banner
`rootfs/etc/issue.d/50-manatech.issue`.

A name outside the schema only loses the `schema` row, and an address in no
VLAN row only loses the `vlan` row (the badge then shows the environment).
The rest of the panel is the same.

**Keep your real data in a private fork.** `vlans.tsv` and `schema-names.tsv`
are plain text in the repo and ship to every host that installs the banner,
so a real network belongs in a copy only your hosts can read:

1. Fork this project into a private group. GitLab allows a private fork of a
   public project, and a merge request opened in the fork then targets the
   fork itself, not this project.
2. In the fork, replace the example rows with your own (the art too, if you
   like). Changes from this project merge in as usual: the data files rarely
   change here, so they rarely conflict.
3. Hosts clone the fork with a read-only deploy token (see "Install on one
   host"). Domain hosts get it from Group Policy, published from a clone of
   the fork (see "Group Policy delivery").

## Environments

The environment is the coloured strip above the panel and the `env` row.
Its colour comes from `envs.tsv`:

| Environment | Colour |
|---|---|
| `PROD` | Blue |
| `LAB` | Orange |
| `DEV`, `TEST`, `STAGE` | Black |
| `PUB` | Pink |
| any other name | Grey |

`UNSET`, the template's value, shows grey: nobody has set it yet. Set it per
host with `ENV_NAME` in `/etc/manatech/motd.conf` or `EnvName` in
`C:\ProgramData\Manatech\motd.psd1`. A domain host can leave it at `UNSET`
and take the environment from its AD Description instead, written
`<ENV>: <role>` (see "Group Policy delivery").

## What shows where

| When | Where it comes from | Colour? |
|---|---|---|
| Console, before login | Ubuntu's own `/etc/issue` (the OS line), then `/etc/issue.d/50-manatech.issue`, which agetty expands (`\e{cyan}`, `\4`) | yes: agetty adds it |
| SSH, before login | `/etc/manatech/issue.net` via sshd `Banner` | **no.** sshd sends it raw, and OpenSSH, PuTTY and MobaXterm strip or expose escape codes in it on purpose, because the server has not authenticated yet |
| SSH or console, after login | `pam_motd` runs `/etc/update-motd.d/*` as root and prints the output | yes: raw ANSI works in every modern client |

So the styling lives after login. The pre-login banner is the same art in
plain ASCII (your terminal's default colour) above a 64-column warning box
labelled "Login for more information", so logging in reads as the art lighting
up. It says nothing useful to a scanner: no OS, version or addresses. A Pester
check keeps it ASCII-only, the box 64 wide, and the art identical to
`manatech.art`.

Ubuntu's `/etc/issue` and `/etc/issue.net` stay stock: they are conffiles
that base-files replaces at every point release, and apt asks before it
replaces a changed one. Older versions overwrote them, so every point
release asked. `install.sh --ssh` now puts the stock versions back, byte for
byte, writing each only when its md5 is the one dpkg recorded. It does so only
over a banner an older version wrote (or the original it replaced, installed
by hand): it knows each by its md5. Anything else in those files is someone
else's, stays as it is, and the log says so.

## Files

| Repo path | Installed as | Purpose |
|---|---|---|
| `rootfs/etc/update-motd.d/05-manatech-banner` | same, mode 755 | art with gradient, welcome line, host panel with env badge |
| `rootfs/etc/update-motd.d/15-manatech-health` | same, mode 755 | one line per problem, or a green "all clear" naming each check that ran |
| `rootfs/usr/local/share/manatech/motd-lib.sh` | same, 644 | settings, colour modes, glyphs, meters |
| `rootfs/usr/local/share/manatech/art.awk` | same, 644 | renders the art file with per-colour vertical gradients |
| `rootfs/usr/local/share/manatech/colour.awk` | same, 644 | colour functions shared by the two awk scripts |
| `rootfs/usr/local/share/manatech/schema.awk` | same, 644 | decodes the host name with the naming schema; letter tints and border colour |
| `rootfs/usr/local/share/manatech/schema-names.tsv` | same, 644 | the naming schema: one row per code, with the colour it is drawn in (example rows) |
| `rootfs/usr/local/share/manatech/colors.tsv` | same, 644 | the named colours, with the RGB each is drawn in |
| `rootfs/usr/local/share/manatech/vlans.tsv` + `vlan.awk` | same, 644 | the VLAN table (example rows); finds the primary address's VLAN for the badge |
| `rootfs/usr/local/share/manatech/envs.tsv` | same, 644 | environment -> colour name (the strip and env row) |
| `rootfs/usr/local/share/manatech/ad-description.sh` | same, 644 | caches this computer's AD Description (`install.sh --ad`) |
| `rootfs/usr/local/share/manatech/units.sh` | same, 644 | the systemd units `install.sh` writes: the 4-hourly timer and, for Group Policy delivery, the publish watcher |
| `adsys-startup.sh` | runs from the ADSys cache | the Group Policy startup script (see "Group Policy delivery") |
| `windows/Publish-ManatechMotd.ps1`, `windows/Sync-ManatechBanner.ps1` | DC / GPO task | publish to SYSVOL (Ubuntu) and NETLOGON (Windows) and build the GPO; the Windows side of the GPO, run from NETLOGON |
| `windows/ManatechMotdGpo.psm1` | DC, loaded by the publisher | what the GPO should hold and how it differs from an existing one: the task XML, the merge with tasks already there, the warnings' wording; no domain calls, so it is tested anywhere (`windows/tests/ManatechMotdGpo.Tests.ps1`) |
| `install.sh` | run from the clone | install, retire stock scripts, SSH banner, daily update timer |
| `windows/` | see "Windows Server" | the same banner for Windows: module, config, installer, demo, Pester tests |
| `rootfs/usr/local/share/manatech/manatech.art` | same, 644 | the art. `@y` switches to the emblem colour, `@c` back to the moon colour |
| `rootfs/usr/local/share/manatech/welcome.tsv` | same, 644 | the welcome line under the art: the company name, the two colours of its gradient and its 16-colour code. Windows reads the same file, so a fork renames the line with data alone |
| `rootfs/etc/manatech/motd.conf` | same, 644 | **per host**: `ENV_NAME`, `ROLE`, `WATCH`, colour mode, thresholds |
| `rootfs/etc/issue.net` + `rootfs/etc/ssh/sshd_config.d/00-manatech-banner.conf` | `/etc/manatech/issue.net` and the drop-in, 644 | plain pre-login SSH banner (`00-`: sshd uses the first Banner it reads; `install.sh --ssh` checks the effective one with `sshd -T`) |
| `rootfs/etc/issue.d/50-manatech.issue` | same, 644 | console banner, printed after Ubuntu's `/etc/issue` (the OS line comes from that stock file) |
| `rootfs/usr/local/share/manatech/conffiles.sh` | same, 644 | keeps Ubuntu's banner conffiles stock: puts back what older versions changed, and keeps landscape-sysinfo off across upgrades (`windows/tests/Conffiles.Tests.ps1`) |
| `rootfs/usr/local/share/manatech/plan.sh` | same, 644 | what `install.sh` would change, without changing it: `--whatif`, and the note of waiting setup changes that `15-manatech-health` shows at login (`windows/tests/Plan.Tests.ps1`, `Health.Tests.ps1`) |
| `demo.sh`, `demo/motd.conf` | not installed | render from the repo without touching `/etc` |

The template ships `ENV_NAME=UNSET`, which shows a grey badge. Seeing that
grey badge after cloning is the reminder to set the environment and role.

## Preview

From a clone, nothing installed:

    sh demo.sh                # this host, with demo/motd.conf
    sh demo.sh prod faults    # the PROD strip, sample problems
    sh demo.sh 256 ascii      # older client fallbacks
    sh demo.sh as=s-pfw-edge1 # another name: schema row + colours
    pwsh -NoProfile -File windows/demo.ps1 -Faults   # Windows layout, sample facts

Run it from a MobaXterm, PuTTY or Windows Terminal session to the host to see
the colours. Options: `truecolor|256|16|none`, `ascii`,
`prod|lab|dev|test|stage|pub|unset`, `faults`, `as=NAME`, `ip=A.B.C.D`,
`conf=NAME`, `ad=TEXT` (e.g. `demo.sh as=H-PSW-APP-1 ip=10.20.40.79`).

## Naming schema and the border colour

The banner decodes the host name with the naming schema in
`schema-names.tsv`: `<site:2><type><subtype><os>-<name><number>`, where the
site is two characters: the site letter, then the sub-site letter or `-`.
With the example rows (`h-` HQ, `be` Branch East, `cw` Cloud West, `la`
Lab A, `lb` Lab B), `h-vsl-web1` becomes a `schema` row reading
**HQ / Virtual / Server / Linux**. Each of those four
letters in the title is drawn in its code's colour, and the panel border is
drawn in the colour of the field named by `BORDER_BY` (default `type`: tell
physical, virtual, cloud and lab hosts apart at a glance). A name outside the
schema gets no schema row and keeps the environment colour for the border.

- The `colour` column of `schema-names.tsv` names a row of `colors.tsv`.
  Change a code's colour there.
- A site pair that is not listed (`s-` with the example rows) decodes as `?`,
  and so does any other unknown code.
- `colors.tsv` lists Purple twice (A and D); either code works.

## The badge: site and VLAN

The top-right badge reads `<site> - <vlan>-<mini>`, e.g. **HQ - 40-Servers**
for `H-PSW-APP-1` at `10.20.40.79` with the example rows, and a `vlan` row in
the panel carries the short description and subnet (`40  Servers  (10.20.40.0/22)`):

- **site**: from the host name (the schema above), or else the VLAN row's site.
- **VLAN**: the primary address (source of the default route; Windows: the
  lowest-metric default route's interface), looked up in `vlans.tsv`. The
  longest matching prefix wins. The badge uses the row's `mini` description,
  the vlan row its `short` one.
- **colour**: the VLAN's colour code (a `colors.tsv` code, so VLAN 40 = C =
  Teal), with black or white text by brightness. A VLAN with no code keeps
  the environment colour.
- **fit**: when host name and badge do not both fit 64 columns, the domain is
  dropped from the name first, then the badge text is cut with `~`.
- `BADGE=env` (`Badge = 'env'` on Windows) brings back the plain environment
  badge.

`vlans.tsv` ships to every host that installs the banner: VLAN ids, subnets,
colour codes, sites and the two short descriptions. Mind that before filling
it with a real network (see "Your own data").

## Windows Server (2022 and later)

What exists on Windows, and where the banner can live:

| Moment | Mechanism | Colour? |
|---|---|---|
| SSH, before login | Win32-OpenSSH `Banner` in `C:\ProgramData\ssh\sshd_config`, the same plain `issue.net` | no, same reason as on Linux |
| SSH, after login | nothing like pam_motd exists. The banner runs from the **all-users PowerShell profile**, which requires the OpenSSH default shell to be PowerShell (it is `cmd.exe` by default) | yes: VT sequences pass through ConPTY |
| PS-Remoting (`Enter-PSSession`) | no banner and no profile on the remote side, by design | the workaround below |

Install: see "Quickstart", or "Install on one host" below.

The banner shows once per SSH login. It does not show for `ssh host 'command'`
(PowerShell started with `-c`), for scp/sftp (no shell), or in a nested
shell. It checks: stopped auto-start services, fixed disks, memory, each
`Watch` service, the Windows Time source, and a pending reboot. The "all
clear" line lists only checks that produced an answer. w32tm's output is
localised, so on a non-English host "clock" is left off that line instead of
being claimed as passing.

Stopped auto-start services leave out three kinds that are stopped by
design: trigger-start services (Windows starts them when their trigger fires
and stops them when idle, e.g. AppXSvc), the module's own list of others
(`InventorySvc`, delayed-start, stopped on every Server 2025 host checked),
and the host's `ServiceIgnore` in `motd.psd1`, which adds to that list.

**A slow login?** `Measure-ManatechBanner.ps1` times the banner on the host
itself, probe by probe, and changes nothing; it ends with the host's stopped
auto-start services and whether the banner reports each one:

    powershell -NoProfile -ExecutionPolicy Bypass -File \\<domain>\NETLOGON\MOTD\windows\Measure-ManatechBanner.ps1

On a Server 2025 test VM, a whole banner (module load, facts, drawing) in a
fresh process, as every login is, went from 2.8 s to 1.4 s in Windows
PowerShell 5.1 and to 1.1 s in PowerShell 7 (2026-10-03).

**PS-Remoting:** `Enter-ManatechPSSession <host>` (or `-HostName` for PowerShell 7
remoting over SSH) opens the session, asks the remote host for its banner
text, prints it locally, where your terminal draws the colours, then enters
the session. The module has to be installed on the remote host. Import it
locally from your profile to have the command.

The banner is drawn for your terminal, not the remote host's settings:
`-Color truecolor|256|16|none` and `-Glyphs unicode|ascii`, defaulting to
`$env:MANATECH_BANNER_COLOR` / `$env:MANATECH_BANNER_GLYPHS`. A local
PowerShell tab in MobaXterm passes only the 16 console colours (24-bit
colours arrive rounded to the nearest of those, which washes them out), so
its profile wants:

    $env:MANATECH_BANNER_COLOR = '16'

Windows Terminal draws 24-bit colour and needs nothing. Box glyphs: start
`pwsh` on the remote side and the box drawing comes out garbled (its UTF-8
is read back as the console code page); `Enter-ManatechPSSession` asks for
the text instead, so it arrives intact.

### What has been checked on Windows, and what not yet

Checked on 2026-10-03 in a test domain, on a Windows Server 2025 member (Windows
PowerShell 5.1) and its DC: the GPO task's script as SYSTEM with nobody logged
on, from NETLOGON and from the older SYSVOL path (exit 0); the AD Description
read as the computer account; replacing an existing global `Banner` in
sshd_config, with `sshd -t`; the profile block; a second run changing
nothing; and the publisher on the DC, `-WhatIf` and real, to both copies.
Before that, a real SSH login on a production server showed the banner, so
Win32-OpenSSH does set `SSH_CONNECTION` (the `-SshOnly` gate).

Not verified yet:
1. A server without the OpenSSH Server: the sync should log that it skipped
   the default shell and the pre-login banner, and exit 0 (covered by a test
   on Linux only).
2. Truecolor through ConPTY on 2022. Fallback: `Color = '256'`.
3. `Enter-PSSession` behaving interactively when called from inside a function.
4. The Zabbix agent's service name (`Get-Service *zabbix*`), and which
   auto-start services a clean 2022 host normally has stopped (Server 2025:
   AppXSvc, trigger-start, and InventorySvc, both left out now).
5. Git for Windows accepting a clone owned by Administrators when SYSTEM
   pulls it (the update task). If `update.log` shows "dubious ownership", run
   `git config --system --add safe.directory C:/ProgramData/Manatech/repo`.

## Group Policy, with the V1 module

`Deploy-UsaBannerGPO` makes one Group Policy object, "UsaBanner", that puts the
V1 module and one configuration (the package) on the domain's Windows servers
and Ubuntu hosts, and keeps them current. It is for the V1 module in
`UsaBanner/`; today's banner has its own publisher (next section), and a host
must not get both, since each undoes the other at every refresh.

Run it on a domain controller, or a domain member with the Group Policy
Management tools, as someone who may edit Group Policy objects and write
NETLOGON and SYSVOL. Windows PowerShell 5.1 hands the work to PowerShell 7. The
package is built from the flags `Deploy-UsaBanner` takes, or from the
configuration file `-Path` names; each host takes its tier and role from its
own AD Description unless the package sets them. A package that turns the
update channel on is refused: the GPO is the update path.

A first run with `-WhatIf` changes nothing and says what it would do. Then a
real one, which links the GPO where you name:

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
  changes. Ubuntu needs the ADSys assets folder, `SYSVOL\<domain>\Ubuntu` with
  a `GPT.INI` in it; without it the run warns and does the Windows half only.
  The `Version` in that `GPT.INI` goes up when the Ubuntu copy changed, so ADSys
  downloads it again.
- Links the GPO at each `-LinkTarget`. Without one the links stay as they are,
  and a GPO linked nowhere applies to no host: the run warns, and links nothing.
- Warns while today's banner GPO is still linked and enabled anywhere, and when
  no deploy-usawinssh GPO is linked (a server without PowerShell 7 gets no
  banner until that policy installs it). Then it reads everything back, a line
  each.

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

<!-- command reference: begin. build/Update-UsaBannerReadme.ps1 writes what is between these two lines, from the commands' help: edit the help, then run it -->
## Command reference

The module's commands and every flag they take, from each command's own help, which `Get-Help <command> -Full` shows too.

- [Deploy-UsaBanner](#deploy-usabanner): Deploys this host's banners: the console's before login, the SSH banner before authentication, and the banner after login.
  - [-Path](#-path), [-Company](#-company), [-Environment](#-environment), [-Role](#-role), [-BannerImage](#-bannerimage), [-Border](#-border), [-BorderChar](#-borderchar), [-BorderCap](#-bordercap), [-ColorPreset](#-colorpreset), [-ColorMode](#-colormode), [-Glyphs](#-glyphs), [-Legal](#-legal), [-LegalText](#-legaltext), [-Voice](#-voice), [-PreInit](#-preinit), [-PreLogon](#-prelogon), [-VlanFile](#-vlanfile), [-Services](#-services), [-Update](#-update), [-UpdateSource](#-updatesource), [-ReplaceOldBanner](#-replaceoldbanner), [-WhatIf](#-whatif), [-Confirm](#-confirm)
- [Deploy-UsaBannerGPO](#deploy-usabannergpo): Makes the Group Policy that deploys the banners on the domain's Windows servers and Ubuntu hosts, and keeps them current.
  - [-Path](#-path-1), [-Company](#-company-1), [-Environment](#-environment-1), [-Role](#-role-1), [-BannerImage](#-bannerimage-1), [-Border](#-border-1), [-BorderChar](#-borderchar-1), [-BorderCap](#-bordercap-1), [-ColorPreset](#-colorpreset-1), [-ColorMode](#-colormode-1), [-Glyphs](#-glyphs-1), [-Legal](#-legal-1), [-LegalText](#-legaltext-1), [-Voice](#-voice-1), [-PreInit](#-preinit-1), [-PreLogon](#-prelogon-1), [-VlanFile](#-vlanfile-1), [-Services](#-services-1), [-Update](#-update-1), [-UpdateSource](#-updatesource-1), [-Name](#-name), [-LinkTarget](#-linktarget), [-Domain](#-domain), [-WhatIf](#-whatif-1), [-Confirm](#-confirm-1)
- [Get-UsaBanner](#get-usabanner): Shows the banners Deploy-UsaBanner put on this host, and whether each part of them is in place.
  - [-Moment](#-moment)
- [New-UsaBannerArt](#new-usabannerart): Turns an image into banner art: plain ASCII characters, with a colour for each part where the terminal has colour.
  - [-Path](#-path-2), [-Width](#-width), [-Height](#-height), [-Colors](#-colors), [-Background](#-background), [-Fill](#-fill), [-Style](#-style), [-ColorMode](#-colormode-2), [-OutFile](#-outfile), [-Force](#-force), [-Title](#-title), [-Artist](#-artist), [-Licence](#-licence), [-Source](#-source)
- [Remove-UsaBanner](#remove-usabanner): Takes this host's banners off, and leaves the host as it was before Deploy-UsaBanner.
  - [-WhatIf](#-whatif-2), [-Confirm](#-confirm-2)
- [Show-UsaBanner](#show-usabanner): Draws one of this host's banners, as a configuration sets it.
  - [-Moment](#-moment-1), [-Path](#-path-3), [-Facts](#-facts), [-Os](#-os), [-ColorMode](#-colormode-3), [-Glyphs](#-glyphs-2)
- [Show-UsaBannerArt](#show-usabannerart): Draws one of the module's pieces of art, an art file, or a name in block letters, in colour where the terminal has it; or lists the art there is.
  - [-Name](#-name-1), [-ColorMode](#-colormode-4), [-Os](#-os-1), [-Text](#-text), [-Font](#-font), [-Path](#-path-4), [-List](#-list)

### Deploy-UsaBanner

Deploys this host's banners: the console's before login, the SSH banner
before authentication, and the banner after login.

#### Syntax

```
Deploy-UsaBanner [[-Path] <string>] [[-Company] <string>] [[-Environment] <string>] [[-Role] <string>] [[-BannerImage] <string>] [[-Border] <string>] [[-BorderChar] <string>] [[-BorderCap] <string>] [[-ColorPreset] <string>] [[-ColorMode] <string>] [[-Glyphs] <string>] [[-Legal] <string>] [[-LegalText] <string[]>] [[-Voice] <string>] [[-PreInit] <string[]>] [[-PreLogon] <string[]>] [[-VlanFile] <string>] [[-Services] <string[]>] [[-Update] <string>] [[-UpdateSource] <string>] [-ReplaceOldBanner] [-WhatIf] [-Confirm] [<CommonParameters>]
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

A host with the old banner, which this repository's install.sh or
Install-ManatechBanner.ps1 installs, is refused unless -ReplaceOldBanner
takes that banner off first.

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

The art: a piece of the module's art (Show-UsaBannerArt -List), or os
for the pictogram in the host's OS colour.

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

##### -Border

The box's lines and corners. The Unicode sets show after login only,
with Classic before login.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: Classic, Hash, Star, Equals, Round, Bevel, PipeUnderscore, Wavy, OneChar, Rounded, Single, Double, Heavy, Block

Required: False
Position: 5
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
Position: 6
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
Position: 7
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
Position: 8
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
Position: 9
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
Position: 10
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
Position: 11
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
Position: 12
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
Position: 13
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
Position: 14
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
Position: 15
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
Position: 16
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
Position: 17
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
Position: 18
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -UpdateSource

The https address the releases' files are downloaded from: SHA256SUMS
and UsaBanner-\<version\>.zip are under it, as under a GitHub repository's
.../releases/latest/download.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 19
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -ReplaceOldBanner

Takes the old banner off first: the one this repository's install.sh
(Ubuntu) or Install-ManatechBanner.ps1 (Windows) installs. Its files and
jobs go, and what it changed comes back as the OS ships it; then this
banner deploys. It runs after every banner is drawn, so a configuration
that fails leaves the old banner in place. A Group Policy that delivers
the old banner puts it back at the next boot or refresh: take that GPO
off the host first. Get-UsaBanner's old banner check says when it is
back.

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
Deploy-UsaBannerGPO [[-Path] <string>] [[-Company] <string>] [[-Environment] <string>] [[-Role] <string>] [[-BannerImage] <string>] [[-Border] <string>] [[-BorderChar] <string>] [[-BorderCap] <string>] [[-ColorPreset] <string>] [[-ColorMode] <string>] [[-Glyphs] <string>] [[-Legal] <string>] [[-LegalText] <string[]>] [[-Voice] <string>] [[-PreInit] <string[]>] [[-PreLogon] <string[]>] [[-VlanFile] <string>] [[-Services] <string[]>] [[-Update] <string>] [[-UpdateSource] <string>] [[-Name] <string>] [[-LinkTarget] <string[]>] [[-Domain] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
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

The art: a piece of the module's art (Show-UsaBannerArt -List), or os
for the pictogram in the host's OS colour.

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

##### -Border

The box's lines and corners. The Unicode sets show after login only,
with Classic before login.

```yaml
Type: String
Parameter Sets: (All)
Aliases:
Accepted values: Classic, Hash, Star, Equals, Round, Bevel, PipeUnderscore, Wavy, OneChar, Rounded, Single, Double, Heavy, Block

Required: False
Position: 5
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
Position: 6
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
Position: 7
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
Position: 8
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
Position: 9
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
Position: 10
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
Position: 11
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
Position: 12
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
Position: 13
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
Position: 14
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
Position: 15
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
Position: 16
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
Position: 17
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
Position: 18
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
Position: 19
Default value: None
Accept pipeline input: False
Accept wildcard characters: False
```

##### -Name

The GPO's display name; UsaBanner by default.

```yaml
Type: String
Parameter Sets: (All)
Aliases:

Required: False
Position: 20
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
Position: 21
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
Position: 22
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
task and the update job's; takes the block out of each all-users
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

## Group Policy delivery (domain hosts)

For domain-joined hosts, the banner comes from SYSVOL instead of GitLab: no
deploy token and no GitLab access on the hosts, and only accounts that can
write SYSVOL can change what runs at login.

**The AD Description drives the environment and the role.** Write it as
`<ENV>: <role>`, e.g. `PROD: Hyper-V host` or `PUB: Public web front end`.
The prefix is letters only; a Description without one is the role alone.
Spaces around the prefix and the colon do not count: Linux and Windows both
read `PROD : Hyper-V host` as PROD. The names and
colours are in "Environments". The environment shows as
a strip above the panel and an `env` row (`ENV_SHOW` / `EnvShow`). A host
with an empty Description shows an amber "(set this computer's AD
Description)" role row. `motd.conf` / `motd.psd1` still win per host: an
`ENV_NAME` other than UNSET, or a non-empty `ROLE`.

**Publish** (on a DC, or a machine with the Group Policy Management tools,
in Windows PowerShell 5.1, from a clone checked out at `main` after a merge):

    .\windows\Publish-ManatechMotd.ps1 -WhatIf
    .\windows\Publish-ManatechMotd.ps1 -LinkTarget 'OU=Linux,DC=ad,DC=example', 'OU=Servers,DC=ad,DC=example'

One run copies the files and builds the GPO; nothing is clicked in GPMC.
`-LinkTarget` is needed only to add links (see "The GPO" below); a re-publish
is just `.\windows\Publish-ManatechMotd.ps1`. `-SkipGpo` copies the files
only, and is the one mode that also runs under PowerShell 7 (there the
GroupPolicy module works through a compatibility session, so the GPO step
refuses to run).

The files go to two places, and that is the whole update step for hosts:

| Copy | For | Why there |
|---|---|---|
| `\\<domain>\SYSVOL\<domain>\Ubuntu\scripts\MOTD\` | Ubuntu hosts | ADSys downloads only the `Ubuntu\` tree of SYSVOL. `Ubuntu\GPT.INI` is bumped when this copy changed, so ADSys downloads again |
| `\\<domain>\NETLOGON\MOTD\` | Windows hosts (the GPO's scheduled task) | logon scripts live in NETLOGON, with its own share permissions. This copy holds `README.md`, `rootfs\` and `windows\` |

Unchanged files are skipped, and files no longer in the repo are removed from
those two folders only. The NETLOGON folder carries a `.manatech-motd` file
that marks it as this script's: an existing `NETLOGON\MOTD` without it is
someone else's, and the run stops before writing anything (`-NetlogonPath`
publishes the Windows copy elsewhere). Every file is written with LF line
endings whatever the clone holds: Git for Windows (`core.autocrlf`) checks
files out as CRLF, and `sh` cannot run a CRLF script at all. The run says
when it had to convert. (The repo's `.gitattributes` makes a fresh clone LF
on Windows too.)

**The GPO, "Manatech MOTD"** (`-GpoName` for another name). The publisher
creates it when no GPO has that name, and makes it hold this - each OS
ignores the other's half:

1. Ubuntu (ADSys, needs Ubuntu Pro): the values the ADSys administrative
   template writes for Computer Configuration > Policies > Administrative
   Templates > Ubuntu > Client management > Computer Scripts > **Startup
   scripts**: `all` = `MOTD/adsys-startup.sh`, and `metaValues` with the
   append strategy for every release, so every other GPO's startup scripts
   still run. No other value stays under that key (a release-specific list
   would replace `all` on that release).
2. Windows: a Group Policy Preferences task, **Manatech MOTD sync**
   (Computer Configuration > Preferences > Control Panel Settings > Scheduled
   Tasks): `NT AUTHORITY\System` with highest privileges; **at startup**, and
   **daily**, repeating every 4 hours for the day; stopped after 30 minutes;
   it runs `powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass
   -File "\\<domain>\NETLOGON\MOTD\windows\Sync-ManatechBanner.ps1"`
   (Bypass: a script on a UNC path counts as remote under RemoteSigned).

**A GPO of that name that exists already is overwritten, with warnings.**
Before anything is written, one warning per setting it holds differently
gives the old and the new value - a hand-built task still on the SYSVOL copy
shows as `Arguments: '...\Ubuntu\scripts\MOTD\...' -> '...\NETLOGON\MOTD\...'`
- and another lists what else the GPO holds (tasks of other names, other
kinds of settings), which is left as it is. A publish that changes nothing
in the GPO gives no overwrite warning. Run `-WhatIf` first to read the
warnings, and the task the publisher would write, without changing anything.

**Links.** `-LinkTarget` links the GPO to each OU it is not linked to yet (a
disabled link there is enabled, with a warning). Without it, links stay as
they are, and a GPO linked nowhere gets a warning instead of a default link:
the task runs on every Windows machine under a link, so where the GPO goes is
a choice, not a default.

Everything is read back at the end, one line per check, and the run fails if
a check does. The GPO's version goes up in AD and in its `GPT.INI` together,
and only when the publish changed something in it.

What each side then does:

- **Ubuntu**: `adsys-startup.sh` runs `install.sh --retire --ssh --timer
  --ad` from the ADSys copy of SYSVOL (`/var/cache/adsys/sysvol/assets/scripts/MOTD/`):
  render check, files, stock scripts retired, pre-login banner, and the AD
  Description (read with the machine's own Kerberos key; needs `ldap-utils`,
  `libsasl2-modules-gssapi-mit`, `krb5-user`). Three
  things run it: ADSys at boot; `manatech-motd-update.timer` every 4 hours;
  and **`manatech-motd-publish.path` as soon as ADSys has downloaded a new
  publish** (it watches the copy's `GPT.INI`, waits 30 s for the rest of the
  files, and skips a Version already installed). The first install on a host
  still needs one boot at which ADSys runs startup scripts (not every boot
  does: see "ADSys skips startup scripts at some boots" below), or one
  `sudo adsysctl update -m`, or one
  `sudo sh /var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh`.
- **Windows**: the task runs `Sync-ManatechBanner.ps1` from NETLOGON: AD
  Description (ADSI, as the computer account), render check, files, profile
  block, and where the OpenSSH Server is set up, a PowerShell default shell
  and the pre-login banner (a host without it gets the rest, and one log line
  saying so). Log: `C:\ProgramData\Manatech\sync.log`. A changed pre-login
  banner takes effect at the next sshd restart.
  The default shell is `-DefaultShell any`: a PowerShell already set there
  (Windows PowerShell or PowerShell 7) is kept, and only another shell
  (`cmd.exe`, the stock default) becomes Windows PowerShell. A policy that
  owns the default shell, such as the OpenSSH Server GPO from
  `usagitools/usagideploy/deploy-usawinssh` setting pwsh, keeps it: the sync
  only makes sure the banner has a PowerShell to show in, so the two never
  take turns.

A host moved from the GitLab install to Group Policy keeps working: both use
the same timer unit, and the ADSys run points it at the cache instead.
`/opt/manatech-motd` can then be deleted.

**Publishing without a reboot.** What ADSys does, from its source (`systemd/`
and `internal/policies/scripts/` in github.com/ubuntu/adsys) and from hosts:

- `adsys-gpo-refresh.timer` runs `adsysctl update --all` 90 minutes after
  boot and every 90 minutes after that, and that refresh **does** download a
  new publish: on 2026-09-25 a host nobody touched had the same `GPT.INI`
  Version as SYSVOL (49) within the 90 minutes.
- Startup scripts, though, run **only at boot**. ADSys stages them into
  `/run/adsys/machine/scripts/` on every refresh, but only
  `adsys-machine-scripts.service` runs them, and it is a one-shot with
  `RemainAfterExit=yes`: once active after boot, starting it again does
  nothing. The same host had the new files in its copy and no install.
- So the publish watcher closes the gap: a path unit on the copy's `GPT.INI`
  (`manatech-motd-publish.path`) runs the install when a publish lands. On
  systemd 255, the version Ubuntu 24.04 ships, measured on 2026-09-25 with a
  throwaway watcher: it fires when the file is created (also when its folders
  appear first, three levels deep), replaced by a rename (how ADSys writes)
  or rewritten; not when the folders appear or another file in the folder
  changes; once per event, no loops.

So after a publish: ADSys downloads it within 90 minutes, and the watcher
installs it 30 seconds later - no reboot, nobody logged in. A host set up by an
earlier version gets the watcher from its next 4-hourly timer run (every run
from the ADSys copy rewrites its units when they changed). Only a host that
has never run the startup script needs its first boot, or the manual run below.

### ADSys skips startup scripts at some boots

On a machine that **is** attached to Ubuntu Pro (`pro status`), ADSys can
still drop every startup script for a boot - this repo's and any other GPO's,
the Zabbix agent's included. The boot's journal then has:

    adsysd: Rules from the following policy types will be filtered out as the machine is not enrolled to Ubuntu Pro: scripts
    systemd: adsys-machine-scripts.service ... was skipped because of an unmet condition check (ConditionPathExists=/run/adsys/machine/scripts/.ready)

Why, from the source: ADSys reads Pro's `Attached` once per refresh, from
`ubuntu-advantage-desktop-daemon`, with no retry (`GetSubscriptionState`,
`internal/policies/manager.go` in github.com/ubuntu/adsys). It starts that
daemon on demand, and the daemon answers "not attached" until it has parsed
the Pro status, which it does only after taking its D-Bus name
(`src/ua-daemon.c`, `src/ua-status-monitor.c` in
github.com/canonical/ubuntu-advantage-desktop-daemon). At boot ADSys often
asks inside that gap. On an Ubuntu 24.04 test VM (ADSys 0.16.3) on
2026-10-03, 2 of 12 boots lost it.

- **Right away**, on a host where it happened: `sudo adsysctl update -m`.
  With the daemon up by then, ADSys stages the scripts and starts the skipped
  unit itself; on the test VM the install ran within a second. ADSys's own
  refresh does the same within 90 minutes of a boot, if nobody reboots first.
- **For good**: not in this repo. The fix belongs in a standalone Group Policy
  for every Ubuntu machine that makes ADSys's boot refresh wait until Ubuntu
  Pro says attached, so every GPO's startup scripts run, not only this one's.

### Template images

In an Ubuntu template, before VMs are made from it, one command sets up the
units without installing anything (the template is not joined yet):

    sudo sh /path/to/clone/install.sh --template

The units point at the ADSys copy of SYSVOL and do nothing until it exists.
A VM made from the template then installs everything as soon as it has joined
the domain and ADSys has downloaded the `Ubuntu/` tree (the watcher fires when
`GPT.INI` first appears): no boot and no startup script needed.

### Checking an Ubuntu host

    journalctl -t manatech-motd                  # every run: boot, timer, publish watcher
    journalctl -b -u adsys-machine-scripts       # did ADSys run the startup scripts this boot?
    journalctl -b | grep 'filtered out'          # ADSys dropped them this boot (section above)
    sudo grep -e 'name:' -e '\.sh' /var/cache/adsys/policies/*/policies   # the GPOs and scripts ADSys last applied
    sudo grep -i '^version' /var/cache/adsys/sysvol/assets/GPT.INI   # the published version this host has
    cat /var/lib/manatech/installed-version      # the published version installed here
    sudo ls -l /var/cache/adsys/sysvol/assets/scripts/MOTD/   # ADSys keeps its copy root-only
    systemctl list-timers manatech-motd-update.timer
    systemctl status manatech-motd-publish.path  # the publish watcher
    cat /var/lib/manatech/ad-description         # the cached AD Description
    cat /var/lib/manatech/ad-unreached           # there only when the last run reached no DC: when, and what it tried
    pro status                                   # ADSys scripts need Ubuntu Pro attached

Install or re-run now, without a reboot (it prints every step):

    sudo adsysctl update -m                      # if the cache still has an older Version=
    sudo sh /var/cache/adsys/sysvol/assets/scripts/MOTD/adsys-startup.sh

A copy published before the line-ending fix is CRLF and cannot run;
`adsys-startup.sh` says so, and publishing again with the current script
fixes it. (`adsysctl policy applied` cannot show the GPO list on ADSys
0.16.3: "couldn't retrieve user", for root and for the machine alike. The
policies file above is ADSys's own record of the same thing.)

### Checking a Windows host

    Get-Content C:\ProgramData\Manatech\sync.log -Tail 20   # every run; a failure ends "sync FAILED: <cause> (at <script>:<line>)"
    Get-ScheduledTaskInfo -TaskName 'Manatech MOTD sync'   # LastTaskResult: 0 fine, 1 failed (see sync.log)

Task Scheduler shows a failed run as Last Run Result `0x1`, and in the
task's History as return code `2147942401`: that is 0x80070001, the same exit
code 1. To run exactly what the task runs, as an administrator:

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \\<domain>\NETLOGON\MOTD\windows\Sync-ManatechBanner.ps1

A `sync.log` ending in `fails to render ... No User exists for *` comes from a
copy published before 2026-10-03: run as SYSTEM with nobody logged on (which
is when the task runs), `quser` reports that on standard error, and the old
module let it end the run. Publishing again fixes it.

### The banner stops after "Welcome to Manatech" in MobaXterm only

That is Ubuntu's pam_motd, not the banner: at every SSH login it
regenerates the MOTD into one shared file, `/run/motd.dynamic.new`, and
renames it into place. When two logins start at once, the second wipes the
first one's file, and the first login shows only as much as the second has
written so far (Ubuntu bug 1686878, open since 2017:
https://bugs.launchpad.net/ubuntu/+source/pam/+bug/1686878). MobaXterm's
SSH-browser opens that second login in the background, over SFTP
(write-up of the same symptom: https://blog.rico-j.de/update-motd-fail/).
Signs: `/run/motd.dynamic` is complete, `cat` shows it all, and a PowerShell
`ssh` login shows it all.

- The banner keeps its own run short so the two runs rarely overlap: nothing
  at login waits on the network (the FQDN comes from `/var/lib/manatech/fqdn`,
  which `install.sh` refreshes).
- In MobaXterm, per session: Edit Session > Advanced SSH settings >
  SSH-browser type: `None`, or `SCP (enhanced speed)`, which the write-up
  found also avoids it.
- Only a change to pam_motd itself, or to how `/etc/pam.d/sshd` calls it,
  removes the race entirely.

## Install on one host

Every host pulls the repo and installs from its own clone. A 4-hourly job pulls
again and reinstalls when the commit changed, but only after the new
checkout has rendered with that host's config. A bad commit leaves the working
banner in place. The per-host config (`motd.conf` / `motd.psd1`) is never
overwritten.

**Before the first host:** the banner runs as root (SYSTEM) at every login
on every host that pulls it, so whoever can push the tracked branch can run
code as root on all of them. Keep `main` protected (maintainers only;
changes arrive by MR). Hosts read a private fork with a **project deploy
token with `read_repository` only** (Settings > Repository > Deploy tokens),
never a personal token.

The commands below clone a private fork with such a token (`<gitlab>`,
`<group>` and `<fork>` are yours). From this public project, clone without
one, as in "Quickstart".

### Ubuntu

    read -r -p 'deploy token user: ' U; read -rs -p 'deploy token: ' T; echo
    sudo git clone "https://$U:$T@<gitlab>/<group>/<fork>.git" /opt/manatech-motd
    unset T
    sudo sh /opt/manatech-motd/install.sh --all
    sudoedit /etc/manatech/motd.conf                     # ENV_NAME, ROLE, WATCH

`--all` installs the banner, retires the stock scripts it replaces (`chmod -x`,
and the motd-news timer masked), sets the pre-login banners (the console's in
`/etc/issue.d`; the plain SSH one with `sshd -t` first, then a reload, which
leaves open sessions alone), and enables
`manatech-motd-update.timer` (every 4 hours, up to 20 min random delay).
The timer runs `install.sh --update`, which pulls and reinstalls the MOTD
scripts only. A change to the pre-login banners, the retired scripts or the
timer's own unit reaches the host when `install.sh --all` runs again. (Group
Policy hosts run the full set every time.) So after each of its runs,
`install.sh` notes what `--all` would still change here, and the login banner
shows it (with a triangle in a UTF-8 terminal):

      [!!] 3 setup changes wait: sh /opt/manatech-motd/install.sh --all --whatif
        shows them; sudo sh /opt/manatech-motd/install.sh --all makes them

`--whatif` takes any options, lists what that run would change, one line each,
and changes nothing; it needs no sudo. The note covers only the parts this host
has (stock scripts retired, our sshd drop-in, the timer), and carries `--ad`
when the timer uses it.
Add `--ad` on a domain-joined host to take ENV and role from its AD Description. When no domain
controller can be contacted at all, that step warns instead of failing: it keeps the last
description, and the banner says so until a run reaches one. A DC that answers with an error
still fails the run, and the journal says which DC said what. The token lives
in `/opt/manatech-motd/.git/config`, which `install.sh` makes root-only. It is
also visible in the process list for the few seconds the clone runs.

Check: `sudo run-parts --lsbsysinit /etc/update-motd.d` shows the banner
without logging in; `sudo systemctl start manatech-motd-update` runs an
update now; `journalctl -u manatech-motd-update` shows what it did.
A package upgrade keeps the stock scripts off, and apt never asks about them.
They are conffiles, and dpkg judges a conffile by its content, not its mode,
and copies its mode onto the new version. The one exception is
`50-landscape-sysinfo`: a symlink dpkg does not own, to a file it does, whose
mode an upgrade would reset. `--retire` gives that file a `dpkg-statoverride`
(mode 644) instead.

### Windows Server (elevated; needs Git for Windows for the update task)

    $c = Get-Credential -Message 'deploy token user + token'
    git clone "https://$($c.UserName):$($c.GetNetworkCredential().Password)@<gitlab>/<group>/<fork>.git" C:\ProgramData\Manatech\repo
    C:\ProgramData\Manatech\repo\windows\Install-ManatechBanner.ps1 -DefaultShell any -SshBanner -UpdateTask -WhatIf
    C:\ProgramData\Manatech\repo\windows\Install-ManatechBanner.ps1 -DefaultShell any -SshBanner -UpdateTask
    notepad C:\ProgramData\Manatech\motd.psd1           # EnvName, Role, Watch
    Restart-Service sshd                                # then test from a NEW session

The task "Manatech banner update" runs daily at 03:00 (plus up to 1 h) as
SYSTEM and logs to `C:\ProgramData\Manatech\update.log`.
`Start-ScheduledTask 'Manatech banner update'` runs it now.

## The stock scripts, read from source (Ubuntu 24.04, 2026-09-22)

They are Ubuntu's own, in `/etc/update-motd.d/` on a stock install.

| Script | What it actually does | Keep? |
|---|---|---|
| `00-header` | `Welcome to <distro> (GNU/Linux <kernel> x86_64)` | no, the panel covers it |
| `10-help-text` | three hard-coded Canonical links: help.ubuntu.com, landscape, ubuntu.com/pro | no |
| `50-landscape-sysinfo` | runs the Python `landscape-sysinfo`: load, disk, memory, users, IPs. Cached for 1 minute, skipped under load | no, the panel covers it |
| `50-motd-news` | prints `/var/cache/motd-news`, at most 10 lines of 80 characters with control characters stripped. `motd-news.timer` refreshes it from `https://motd.ubuntu.com`, sending a user agent with the wget version, Ubuntu release, kernel, **CPU model** and cloud ID | **no**, see below |
| `85-fwupd` | firmware updates available (fwupd writes `/run/motd.d/85-fwupd`) | yes, silent unless there is something |
| `90-updates-available` | "N updates can be applied, M are security updates" from update-notifier's stamp | **yes, this is the real security signal** |
| `91-contract-ua-esm-status` | Ubuntu Pro stamps: "ESM Apps is not enabled, N more security updates available with Pro" | optional: an upsell, but it does count real unpatched universe CVEs |
| `91-release-upgrade` | "New release X available" (root only) | yes |
| `92-unattended-upgrades` | whether unattended-upgrades is holding or has failed | yes |
| `95-hwe-eol` | the hardware-enablement kernel stack is reaching end of life | yes, rare and silent otherwise |
| `97-overlayroot` | shows overlayroot mounts (read-only root setups) | harmless; prints a blank line |
| `98-fsck-at-reboot` | a filesystem check will run at next boot | yes |
| `98-reboot-required` | `*** System restart required ***` | no, 15-manatech-health reports it with the package names |

### "What news?"

The cache on a test host on 2026-09-22 held, in full:

> Canonical Workshop gives developers fast, composable, reproducible, and
> secure developer environments that are perfect for agentic workflows.

It is Canonical's announcement channel: products, releases, and now and then a
headline CVE. It is not a security feed, and no advisory arrives only
through it. The security signal you care about is `90-updates-available`
(counts from your own apt metadata) and USNs. Turning it off also stops a
timer that sends Canonical your CPU model and kernel each time it refreshes
(`systemctl cat motd-news.timer` shows the schedule).
