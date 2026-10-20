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
Add `--ad` on a domain-joined host to take ENV and role from its AD Description. The token lives
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
