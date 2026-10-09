# UsaBanner: decisions

> Companion to [SPEC.md](SPEC.md), 2026-10-09. Each decision has an ID, the
> question, the options, a recommendation and why. Answer per ID ("D3: B,
> but...") in chat or in an MR thread on the line. Facts are tagged
> **[measured]** (on a test host), **[fetched]** (read at the cited source on
> 2026-10-09) or **[known]** (from experience, not re-checked).

## Contents

| ID | Decision | Needs your call? |
|---|---|---|
| D1 | Where the code lives, and its name | yes |
| D2 | What runs at login: PowerShell everywhere, or native renderers | recommendation |
| D3 | Default logos, and what may ship in a public repo | yes |
| D4 | AGENTS.md | yes |
| D5 | What pre-init, pre-logon and post-logon mean on each OS | yes |
| D6 | Border and corner sets | recommendation |
| D7 | Colour presets and the preview | recommendation |
| D8 | The five legal templates | yes |
| D9 | Host name and IP before login | yes |
| D10 | Default services, and services that are not found | recommendation |
| D11 | The interactive UI: built in, or a module | recommendation |
| D12 | The Export-UsaBanner package format | recommendation |
| D13 | GPO layering: one base, OU overrides | yes |
| D14 | The update channel | yes |
| D15 | Windows Server 2019 | needs a test VM |
| D16 | Ubuntu: stop the apt prompts | recommendation |
| D17 | Slow facts, and min/max over what window | yes |
| D18 | Installing PowerShell 7 before the module can run | recommendation |
| D19 | New-UsaBannerArt: which image formats | recommendation |
| D20 | The naming standard as the shipped default | recommendation |
| D21 | Who owns SSH: this module or deploy-usawinssh | recommendation |
| D22 | Network devices (stretch) | later |
| D23 | Names and paths without "Manatech" | recommendation |
| D24 | A LICENSE | yes |

## D1. Where the code lives, and its name

The spec calls the cmdlets `*-UsaBanner` and puts them in the UsagiTools
module. Today's public code is `usagitools/deploy-usamotd` (MR !1, not merged
yet): POSIX shell for Ubuntu, Windows PowerShell 5.1-compatible scripts for
Windows, Manatech names throughout.

- **A.** Grow `deploy-usamotd` into a PowerShell module, `UsaBanner`, and
  rename the project to `deploy-usabanner` once the module exists (GitLab
  redirects an old path after a rename) [known]. It folds into UsagiTools 2.0
  later.
- **B.** A new repository for the module; `deploy-usamotd` stays as it is.

**Recommendation: A.** One history; !1's code and tests are the base; the
rename lands before anything goes to GitHub. Merge !1 first, as the baseline
the redesign is measured against.

## D2. What runs at login: PowerShell everywhere, or native renderers

R2 says FAST. The spec says the cmdlets are PowerShell 7. Those are two
different jobs:

| Job | When | Proposed |
|---|---|---|
| Configure, preview, deploy, export, GPO (`*-UsaBanner`) | when an admin runs it | PowerShell 7, both OSes |
| Draw the banner | at every login, as root/SYSTEM | Ubuntu: POSIX `sh` + `awk`, as today. Windows: the PowerShell module in the profile, as today |

Why not PowerShell at login on Ubuntu: `pam_motd` runs the scripts on every
SSH and TTY login. A `pwsh` cold start adds a noticeable pause to each one,
where today's shell renderer is quick [known]. And PowerShell on Linux logs
to syslog by default:
- every script block it judges "suspicious", at Warning level, whatever the
  script-block-logging policy says;
- Informational engine events too [fetched: about_Logging_Non-Windows;
  PowerShell source, `CompiledScriptBlock.cs`].

On this VM that came to about 21 GB from the Pester runs, until an rsyslog
rule dropped it [measured, 2026-10-06].

**Recommendation:** PowerShell 7 for everything an admin runs; native
renderers for what runs at login. One canonical configuration (JSON, D12)
that `Deploy-UsaBanner` compiles into what each renderer reads fastest: flat
`KEY=value` and TSV files for the shell, a `.psd1` for the Windows module.
Today's code already splits this way.

## D3. Default logos, and what may ship in a public repo

The spec's defaults are OS logos (Windows in blue, Ubuntu in orange, Tux),
plus named extras (a Minecraft dirt block, an SQL Server logo). An ASCII
rendering of a logo is still that logo, so the owner's terms apply:

| Logo | The owner's terms | Ship it publicly? |
|---|---|---|
| Tux | "Permission to use and/or modify this image is granted provided you acknowledge me lewing@isc.tamu.edu and The GIMP if someone asks." (Larry Ewing); the Linux kernel tree: "freely usable as long as you acknowledge Larry as the original artist" [fetched: kernel `Documentation/images/COPYING-logo`] | **yes**, with the credit in the art's metadata |
| Windows, SQL Server and other Microsoft logos | "Don't use Microsoft's logos, icons, or designs, in any manner" (Microsoft Trademark and Brand Guidelines). The Windows apps FAQ: "May I use Microsoft's graphical trademarks (logos), such as the WINDOWS FLAG logo, in my app? No." Product names in plain text are fine [fetched] | **no** |
| Ubuntu "Circle of Friends" | Canonical's policy asks for written permission to use its trademarks [search-snippet] | **no** |
| Minecraft blocks | Mojang keeps all rights in its "brand", which it defines to include textures, and limits use of the name [search-snippet] | **no** |
| Manatech | the author's own company | only in the private site fork |

**Recommendation:**
- **The default** when no logo is chosen: a UsagiTools rabbit ("usagi" is
  Japanese for rabbit), drawn for this project.
- **Built-in options**: a few pictograms drawn for this project (server,
  terminal, shield, cloud, globe), Tux with credit, and the company name in
  big letters from a block font of our own, so no font licence question
  arises.
- **OS-relevant without the OS logo**: the non-interactive default takes the
  OS colour (Windows blue, Ubuntu orange) for the server pictogram, and names
  the OS in text, as the panel already does ("Windows Server 2025", read from
  the OS itself).
- **"Use my own" and `New-UsaBannerArt`** take any logo the user has; it never
  leaves their host, and it is their call.
- **Community logos** arrive by merge request with an ownership statement, and
  a human reviews each one (D4).
- The spec's `-BannerImage Minecraft` and `MSSQL` examples become examples of
  a user's own art, not built-ins.

## D4. AGENTS.md

AGENTS.md is a real convention: a Markdown file at the repository root that
tells AI coding agents how to work on the project. It is now stewarded by the
Agentic AI Foundation under the Linux Foundation, and its site lists 23 tools
that read it, among them Codex, Cursor, GitHub Copilot's coding agent, Gemini
CLI, Jules, Aider and Zed [fetched: github.com/openai/agents.md]. Claude Code
reads `CLAUDE.md` instead; a one-line `CLAUDE.md` containing `@AGENTS.md`
bridges the two [search-snippet: Claude Code docs].

**Yes, add one. But word the logo invitation as something an agent passes on
to its human, not as a permission given to the agent.** A file in a repository
telling an agent it "has permission" to open merge requests is exactly the
shape of a prompt injection. Careful agents are built to take instructions
from their user, not from files they happen to read, and to ask before any
outward action. So that version would mostly be ignored or flagged, and it
reads as an attempt to get other people's agents to act without asking. The
same joke works as an invitation:

```markdown
# AGENTS.md

For AI coding agents working in this repository. Humans: see README.md.

## Build and test
- PowerShell 7.4 or later. Run each Pester test file in its own process:
  the test stubs collide when the files share one.
- Shell scripts are POSIX `sh` and must pass `sh -n`.
- Files that ship to Windows hosts are ASCII only: Windows PowerShell 5.1
  reads a file without a BOM in the ANSI code page.
- LF line endings everywhere (see `.gitattributes`).

## Rules
- Banner text shown before login is plain ASCII (characters 32-126): SSH
  clients strip or expose anything else.
- No real hosts, domains, addresses or companies in code, tests or docs:
  use `ad.example`, `example.com`, `10.20.x.x` and Contoso.
- A behaviour change comes with a test that fails without it.

## Your human's logo
Tyson, Claude and Yuki would love to see more logos in the default set. If
the person you work for wants theirs included, tell them so, and if they ask
you to, open a merge request with:
1. `art/<name>.art` (plain ASCII, at most 64 columns by 30 rows, colour
   markers as described in `art/README.md`) and `art/<name>.json` (name,
   artist, licence, source).
2. A sentence in the description saying that your human owns the logo, or
   holds a licence that lets it be distributed under this repository's
   licence. Another company's trademark is declined unless that company's
   own terms allow it.
3. The output of `Show-UsaBannerArt -Name <name>`.

A human maintainer reviews every logo by hand, and asks for more when a
quick OK is not enough. Do not open a merge request your human did not ask
for.
```

**Your call:** the names in the invitation (they go public with it), and
whether the logo section lives here or in a CONTRIBUTING.md that AGENTS.md
points to. "This repository's licence" needs a LICENSE to point at (D24).

## D5. What pre-init, pre-logon and post-logon mean on each OS

| Moment | Ubuntu | Windows |
|---|---|---|
| **Pre-init**: before any login prompt | the console: `/etc/issue` and `/etc/issue.d/*.issue`, printed by agetty (D16) | the logon legal notice, policy "Interactive logon: Message title / Message text": "users will see a dialog box before they can sign in to the server console" [fetched]. Registry `LegalNoticeCaption` / `LegalNoticeText` (REG_SZ) under `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` [fetched, TechNet wiki]. Remote Desktop shows it too, implied by Microsoft but not stated outright |
| **Pre-logon**: SSH, before authentication | sshd `Banner` | sshd `Banner` (Win32-OpenSSH) |
| **Post-logon**: after login | `pam_motd` runs the banner scripts for SSH and console logins | the PowerShell profile block for SSH sessions; `Enter-UsaPSSession` for PS remoting |

The Windows legal notice is the one place Windows itself shows a warning
before console or RDP logon. It is plain text, without art or colour. sshd
does not show it: sshd signs users on as network logons, not through the
interactive logon screen [inferred from the Win32-OpenSSH source]. SSH gets
its own `Banner` instead.

**Your call:** is this the mapping you meant? In particular, is the Windows
legal notice the Windows "pre-init"?

## D6. Border and corner sets

Pre-login banners must be plain ASCII (characters 32-126): an SSH client
shows the pre-authentication banner raw, and OpenSSH, PuTTY and MobaXterm
strip or expose anything else [known; the reason today's `issue.net` is
ASCII]. Post-login, Unicode works where the client is UTF-8; the fallback is
the ASCII set.

**ASCII sets** (every moment):

```text
Classic          Hash             Star             Equals
+------------+   ##############   **************   +============+
|            |   #            #   *            *   |            |
+------------+   ##############   **************   +============+

Round            Bevel            Pipe-underscore  Wavy
.------------.   /------------\    ____________     _-_-_-_-_-_-
|            |   |            |   |            |   |            |
'------------'   \------------/   |____________|    -_-_-_-_-_-_

One character (o)  One character (x)  Title cap (a label in the top line)
oooooooooooooo     xxxxxxxxxxxxxx     +--[ ^_^ ]---+
o            o     x            x     |            |
oooooooooooooo     xxxxxxxxxxxxxx     +------------+
```

- **One character**: any printable ASCII character, `o x O X + * #` as quick
  picks. Corners default to the same character; `+ * o # .'` and `/\` are the
  corner options.
- **Emoticons**: an ASCII emoticon (`^_^`, `o_O`, `:)`, `>_>`) fits as a
  **title cap** in the top line, where it cannot misalign anything. Emoji do
  not: most terminals draw them two cells wide, some one, and some fonts have
  none, so a box with emoji corners comes out ragged (R1) [known].

**Unicode sets** (post-login only, ASCII fallback):

```text
Rounded (today)  Single           Double           Heavy            Block
╭────────────╮   ┌────────────┐   ╔════════════╗   ┏━━━━━━━━━━━━┓   ██████████████
│            │   │            │   ║            ║   ┃            ┃   █            █
╰────────────╯   └────────────┘   ╚════════════╝   ┗━━━━━━━━━━━━┛   ██████████████
```

`■` (U+25A0) draws a small square, so a line of them looks dotted; the full
block `█` (U+2588) joins up. Both, like the box-drawing characters, have
"ambiguous" East Asian width, so a terminal set to treat those as wide (common
with CJK locales) misaligns them [known]. That is one more reason the ASCII
set is the fallback.

**Recommendation:** ship all of the above. The non-interactive default is
**Classic**; the interactive default is **Rounded**, falling back to Classic.

## D7. Colour presets and the preview

| Preset | What | Works on |
|---|---|---|
| UsagiTools (default) | today's palette (24-bit) | truecolor terminals; nearest of 256 or 16 elsewhere |
| Classic 16 | only the 16 ANSI colours | every colour terminal, the same everywhere |
| High contrast | bright text, saturated colours, bold labels | low-quality projectors, bad eyes, bright rooms |
| Mono | no colour; bold and reverse only | `NO_COLOR` set, or colour turned off |
| Custom | a hex value per role: art gradient, border, labels, values, ok/warn/bad | depends on the colours picked |

**The preview runs in the console**, no HTML needed: each preset draws a
sample banner and a 24-bit gradient bar. When the bar looks smooth, truecolor
works; when it bands into steps, the terminal is on 256 or 16 colours, and the
preview says which mode would be picked (an SSH session often does not pass
`COLORTERM` on, so asking beats guessing) [known]. Honour the `NO_COLOR`
environment variable (no-color.org) as "Mono" [known].

## D8. The five legal templates

Drafts, mildest first. All plain ASCII, because they show before login: so
`18 U.S.C. 1030`, not the section sign. 18 U.S.C. § 1030 is the Computer
Fraud and Abuse Act [search-snippet: Cornell LII, uscode.house.gov]. **Not
legal advice.** Have counsel
read L4 and L5 before they go on a company's machines, and outside the US
replace the statute with the local one. L1 and L2 claim nothing legal at all.

```text
L1  Friendly
Hey there. This is a private home machine.
Please don't hack me, buddy.

L2  Private
Private system. Authorized users only.
If you are not supposed to be here, please disconnect now.

L3  Business
WARNING: This system is for authorized use only. Activity on
this system is monitored and recorded. Unauthorized access or
use is prohibited.

L4  Strong
WARNING: AUTHORIZED USE ONLY. Unauthorized access to this
computer system is prohibited and may be a crime under state
and federal law, including the Computer Fraud and Abuse Act,
18 U.S.C. 1030. All activity is monitored and logged, and
evidence of unauthorized use may be given to law enforcement.

L5  Maximum
ATTENTION: THIS IS A PRIVATE COMPUTER SYSTEM. ACCESS IS LIMITED
TO AUTHORIZED USERS FOR AUTHORIZED PURPOSES. BY CONTINUING, YOU
CONSENT TO THE MONITORING, RECORDING AND SEARCH OF ALL ACTIVITY
AND DATA ON THIS SYSTEM, AND YOU HAVE NO EXPECTATION OF PRIVACY
IN IT. UNAUTHORIZED ACCESS OR USE IS A CRIME UNDER 18 U.S.C.
1030 (THE COMPUTER FRAUD AND ABUSE ACT) AND OTHER LAWS, AND
WILL BE REPORTED TO LAW ENFORCEMENT.
```

- L3 to L5 claim that activity is monitored. Only ship that line where it is
  true, or say "may be monitored".
- "Write your own" takes text, checks it is ASCII, and wraps it to the
  64-column box.

**Your call:** the wording, and which one is the non-interactive default.
Proposed default: **L3**, the middle of the group.

## D9. Host name and IP before login

The spec's thinking: anyone breaking in knew the host name long before a
banner told them. That holds for a targeted attacker on the inside. Two
things weigh the other way for the **SSH** banner:

- **Anyone can read it, without credentials.** OpenSSH sends it with the
  first authentication request: "The contents of the specified file are sent
  to the remote user before authentication is allowed" [fetched:
  openssh-portable `sshd_config.5`, `auth2.c`]. RFC 4252 §5.4 allows the
  banner at any time before authentication succeeds [search-snippet]. So a
  mass scanner that merely starts to log in collects it. On an
  internet-facing host, a host name tells it the naming standard (site, kind
  of device, OS), and an internal IP tells it the address plan behind NAT.
- **The console is different.** The pre-init banner (`/etc/issue`) shows only
  at the machine's own console, physical or virtual, where the host name and
  IP help whoever is standing there [known].

**Recommendation:**
- pre-init (console): host name and IP on by default;
- pre-logon (SSH): company and legal text only by default, the host name
  opt-in, the IP opt-in, and both off for a **PUB** host whatever the setting.

## D10. Default services, and services that are not found

| OS | Default, checked | Only when |
|---|---|---|
| Windows | `sshd`, `W32Time` | |
| Windows | `Netlogon` | the host is domain-joined (on a workgroup host it is manual and stopped, so it would report every login) |
| Ubuntu | `ssh`, `cron`, the time sync unit in use (`systemd-timesyncd` or `chrony`) | |
| Ubuntu | `sssd`, `adsysd` | the host is AD-joined |

- **Not found**: the frame-by-frame picker keeps an unknown name checked until
  the user unchecks it. Proposed: keep it listed, but **unchecked**, and
  `-Force` to keep it anyway. A missing service is then reported at every
  login, which is noise unless it is meant.
- **"A service that cannot be monitored will slow down logon"**: not what
  today's code shows. A lookup for a missing service fails at once on both
  OSes [known]; the slow parts are broad queries (all services through
  WMI/CIM). Proposed: measure it in the lab before the UI warns about it.
- The Ubuntu picker lists systemd service units, the same UI.
- §5.4 item 17 (a non-standard automatic service not running) is what today's
  Windows module does: auto-start services that are stopped, minus
  trigger-start services, minus a built-in list of services that stop by
  design, plus the host's own ignore list. Keep that rule.

## D11. The interactive UI: built in, or a module

The frame-by-frame picker needs a checkbox list that scrolls, a text-entry
row, buttons, and a confirm step, all driven by arrow keys, Space, Enter and
Esc, in a console that may be a remote SSH session.

- **A. Built in**: a small terminal UI in the module: read keys with
  `[Console]::ReadKey($true)` and redraw with VT escape sequences. A few
  hundred lines; no dependency; it does exactly what the frame-by-frame
  picker shows. Tests drive it with a scripted key source instead of the
  keyboard.
- **B. `Microsoft.PowerShell.ConsoleGuiTools`** (`Out-ConsoleGridView`): a
  cross-platform grid under the MIT licence. It multi-selects with Space and
  confirms with Enter [fetched: its README and help]. But:
  - Microsoft has frozen it: "feature complete, so v0.7.7 is the last feature
    release", and it points users to a community fork [fetched].
  - It is a dependency from the PowerShell Gallery, which servers without
    internet access cannot fetch.
  - It looks like its own UI, not the one in the spec.

**Recommendation: A.** Every interactive cmdlet also checks that it really has
a console to talk to (not redirected input, VT available). If it does not, it
stops and prints the flags to use instead.

## D12. The Export-UsaBanner package format

- **A. One JSON file** (`usabanner.json`): the settings, the art as lines of
  text, the VLAN rows, the services, the legal text. Readable, diffable in an
  MR, a few KB, and easy to pin with a hash.
- **B. A ZIP** of the same pieces as separate files.

**Recommendation: A.** Nothing in it is binary: `New-UsaBannerArt` turns an
image into text when the art is made, so the package never needs the image.
A ZIP would only add a step to read it, and hide the content from a diff.

## D13. GPO layering: one base, OU overrides

The spec: one base package company-wide, and when an OU should differ, a
second policy with Enforced on.

**Precedence works the other way round.** Group Policy applies local, then
site, then domain, then each OU from the top down. When two GPOs set the same
thing, the one applied last wins. So a GPO linked at an OU already beats one
linked at the domain, with no Enforced flag at all. "Enforced" on a link makes
that GPO win over everything linked below it, and it ignores Block
Inheritance. In Microsoft's words: "The AD container closest to the computer
or user overrides Group Policy set in a higher-level AD container", and
Enforced means "GPOs linked to the lower-level OUs can't override that
enforced domain Group Policy" [fetched: learn.microsoft.com, Group Policy
processing]. Enforced
on the OU policy therefore changes nothing against the root policy, and
Enforced on the root policy would stop OU overrides from working.

**And precedence is not quite what is needed here.** It settles conflicting
registry values. This policy's payload is a scheduled task that copies a
package, plus, for Ubuntu, an ADSys startup script. ADSys has no generic
key/value policy that could carry "use this package" [known].

- **A. A GPO per OU**, each carrying its own task or script, and trusting the
  order they apply in. That works, but it is fragile, and it is a different
  rule on each OS.
- **B. One GPO, with the overrides as data.** The package holds an
  "OU -> package" table. Each host reads its own computer object's
  distinguished name (both OSes already read that object for the AD
  Description) and uses the most specific match.
  `Deploy-UsaBannerGPO -Package lab.json -OU 'OU=Lab,DC=ad,DC=example'` adds
  a row, and `Get-UsaBanner` says which row a host matched.

**Recommendation: B.** There is one place to look, the same rule on both OSes,
and no precedence to reason about.

## D14. The update channel

What the job does is run code from a public repository as root/SYSTEM at
every login on every host that has it, so whoever can change what it pulls
can run code on all of them.

- **A. Follow `main`**: pull and install whatever is on the default branch.
- **B. Follow releases**: install only a tagged release, after checking each
  file against the release's `SHA256SUMS`; optionally pinned to a version.
- **C. Follow the module**: once UsagiTools is on the PowerShell Gallery,
  `Update-Module` on a schedule, with the module signed.

**Recommendation: B now, C later.** A is fine for the maintainer's own lab, as
an explicit `-Channel main`. The warning text proposed for the opt-in:

```text
This keeps the banner updated from a public repository. The update runs as
root (SYSTEM) on this host, at every login. Anyone who can change that
repository's releases can change what runs here. The code is provided as is,
without warranty; its authors are not liable for any damage it causes.
Type YES to turn updates on.
```

The "not liable" part needs a LICENSE behind it to mean anything (D24).

## D15. Windows Server 2019

Today's Windows code says Server 2022 and later, and the lab has only Server
2025. What 2019 (build 17763) needs:

- **Colour in the console:** VT escape sequences, and 24-bit colour since
  build 14931, which shipped as Windows 10 1703 [search-snippet: Microsoft's
  console blog].
- **ConPTY:** its minimum server is Windows Server 2019 [fetched:
  `CreatePseudoConsole` requirements].
- **OpenSSH Server:** "added to Windows Server ... starting with Windows
  Server 2019" [fetched].

**One real open question, for every Windows version, not just 2019: does
24-bit colour survive an SSH session?** The Win32-OpenSSH wiki says sshd uses
ConPTY. But the terminal-emulation code in its current source writes only the
16 console colours [fetched: `shell-host.c`; the wiki and the source
disagree]. Today's banner may therefore arrive over SSH rounded to 16
colours, which the README already lists as unverified.

**What it takes:**
- One line in an SSH session on each Windows version:
  `"$([char]27)[38;2;255;100;0mORANGE$([char]27)[0m"`.
  If that comes out orange rather than the nearest of 16 colours, 24-bit
  works over SSH. The lab's 2025 nodes can answer it today.
- A Server 2019 VM for one pass of the test plan; an evaluation image is
  enough. Until then, the README says "2019: expected to work, not yet
  tested".

## D16. Ubuntu: stop the apt prompts

**What asks, and why.** dpkg asks before it replaces a package's
configuration file (a conffile) that was changed locally. On Ubuntu 24.04
these banner-related files are conffiles [measured: `/var/lib/dpkg/info/*.conffiles`
on a 24.04 host]:

| Package (version measured) | Conffiles |
|---|---|
| base-files 13ubuntu10.5 | `/etc/issue`, `/etc/issue.net`, `/etc/update-motd.d/00-header`, `10-help-text`, `50-motd-news` |
| motd-news-config 13ubuntu10.5 | `/etc/default/motd-news` |
| update-notifier-common 3.192.68.2 | `/etc/update-motd.d/90-updates-available`, `95-hwe-eol`, `98-fsck-at-reboot`, `98-reboot-required` |

Today's `install.sh` overwrites `/etc/issue` and `/etc/issue.net` and edits
`/etc/default/motd-news` [measured: install.sh]. `/etc/issue` and
`/etc/issue.net` name the point release ("Ubuntu 24.04.x LTS"), so base-files
ships new ones at each point release, and each time dpkg asks. That matches
the prompt that has to be declined on every `apt upgrade`. Unattended
upgrades skip a package whose upgrade would ask, too, so base-files security
updates could sit waiting [known].

**The fix is to stop changing conffiles:**

- **Console (pre-init):** leave `/etc/issue` alone and add
  `/etc/issue.d/50-usabanner.issue`. agetty prints the `*.issue` files there,
  in version order, after `/etc/issue`. It has done so since util-linux 2.32;
  Ubuntu 24.04 ships 2.39.3 [fetched: agetty.8 at util-linux v2.39; measured:
  the version on a 24.04 host]. The stock one-line `/etc/issue` still prints
  first. One catch: agetty reads `/etc/issue.d` only while `/etc/issue`
  exists [fetched].
- **SSH (pre-logon):** the `sshd_config.d` drop-in this repo already ships
  points `Banner` at `/etc/issue.net`. Point it at a file of our own
  (`/etc/usabanner/issue.net`) instead of overwriting that one.
- **Stock MOTD scripts:** `chmod -x` can stay. dpkg detects a changed conffile
  by its content, not its mode, and on upgrade it copies the installed file's
  mode onto the new version [fetched: dpkg 1.22.6 source,
  `deferred_configure_conffile`]. So the scripts stay off and nothing asks.
  For the one that is not a conffile (`50-landscape-sysinfo`),
  `dpkg-statoverride --update --add root root 0644 <path>` makes dpkg install
  it that way [fetched: dpkg-statoverride(1)].
- **motd-news:** the documented switch is `ENABLED=0` in
  `/etc/default/motd-news`, which is the conffile edit that can ask. Instead:
  leave the file alone, run `systemctl mask motd-news.timer`, and `chmod -x
  50-motd-news`. Masking is not a documented switch. A Launchpad bug says the
  service is still scheduled when only the script is turned off, and one
  forum report has a base-files upgrade erroring after the units were deleted
  (not masked) [search-snippet]. So this one gets a lab test before it ships.
- **Diverting the conffiles (`dpkg-divert`) is not the answer.** It works
  mechanically, but Debian Policy says not to divert a conffile [search-snippet:
  Debian Policy, diversions appendix; mechanism fetched from dpkg 1.22.6
  source].
- **Hosts already installed:** the installer puts the stock files back once:
  delete them, then `apt-get install --reinstall -o
  Dpkg::Options::=--force-confmiss base-files`, which reinstalls missing
  conffiles [known]. After that it never touches them again.

**The lab test:** install on a 24.04 VM, then run `apt-get install
--reinstall base-files motd-news-config`. Check that nothing asks, that the
scripts are still off, the timer is still masked, and the banner is intact.

## D17. Slow facts, and min/max over what window

§5.4 asks for things that are slow to read or need history: CPU model, RAM
speed, disk type, pending updates, a scheduled reboot, and min/max for RAM
and disks.

- **Two tiers.** At login, read only what is fast and live: uptime, load,
  memory and disk in use, sessions, time, addresses. Everything slow is
  collected by the periodic job (every 15 minutes, say) into a small cache
  file the renderer reads. The cache line says when it was taken.
- **Where each fact comes from:**

| Fact | Ubuntu | Windows |
|---|---|---|
| CPU model, cores | `/proc/cpuinfo` | `Win32_Processor` |
| RAM speed | `dmidecode -t memory` (root) | `Win32_PhysicalMemory` (Speed, ConfiguredClockSpeed) |
| Disk type | `lsblk -d -o NAME,ROTA,TRAN` (rotational, NVMe, USB) | `Get-PhysicalDisk` (MediaType, BusType) |
| Pending updates | apt's update-notifier stamp (as `90-updates-available` reads it) | Windows Update agent COM API (slow: cache only) |
| Reboot pending, and why | `/run/reboot-required(.pkgs)` | the usual registry keys (CBS, Windows Update, pending file renames) |
| Reboot scheduled | `shutdown --show` | scheduled tasks and Windows Update's restart schedule |

**Your call: min/max over what window?** Since boot, over the last 24 hours,
or something else? Anything but "now" needs the job to sample between logins
and keep the samples. Proposed: the last 24 hours, sampled every 15 minutes
(96 samples, a few KB).

## D18. Installing PowerShell 7 before the module can run

R3 says to install PowerShell 7 when it is missing, but the cmdlets that
would do it are PowerShell 7 themselves. So each OS needs a small bootstrap
that runs first:

- **Windows**: a Windows PowerShell 5.1 script. `deploy-usawinssh` already
  installs PowerShell 7 from a pinned, hash-checked MSI; reuse that code.
- **Ubuntu**: a POSIX `sh` script that installs PowerShell from Microsoft's
  package repository (packages.microsoft.com), **not the snap**. Every
  install logs suspicious script blocks to syslog by default (D2). That is
  set in `powershell.config.json` in `$PSHOME`, which is read-only in a snap,
  so only a non-snap install lets the module turn it down [fetched:
  about_Logging_Non-Windows, about_PowerShell_Config].

`Deploy` is an approved verb only since PowerShell 6 [fetched: approved
verbs]. That is no problem for a PowerShell 7 module, but the Windows
PowerShell 5.1 bootstrap must not name a function `Deploy-*`.

Then: install or import the module, and run `Deploy-UsaBanner`. The
Quickstart becomes one bootstrap line per OS.

## D19. New-UsaBannerArt: which image formats

PowerShell 7 on Linux has no image decoder of its own. "Starting in .NET 7,
... you can no longer use the System.Drawing.Common package on non-Windows
operating systems" [fetched: .NET breaking changes]. PowerShell 7.4 runs on
.NET 8, and 7.6 LTS on .NET 10 [fetched].

- **A. PNG only, decoded in plain PowerShell.** PNG is zlib-compressed rows,
  and .NET's `ZLibStream` reads those, so a small decoder handles 8-bit RGB
  and RGBA, non-interlaced, with no dependency.
- **B. A, plus anything ImageMagick can read**, when ImageMagick is installed:
  convert to a simple bitmap format, then decode that.
- **C. Windows only**, through `System.Drawing`.

**Recommendation: A and B.** The output comes in two versions:
- **ASCII**: a character ramp, no colour, safe for pre-login banners.
- **Colour**: the upper half block `▀` with a foreground and a background
  colour, which gives two pixels per character cell. Post-login only, with
  the ASCII version as its fallback.

The art is stored as text either way (D12).

## D20. The naming standard as the shipped default

The author is fine with publishing the naming standard (SPEC §5.4). Today's
public copy, MR !1, replaced two OS codes with generic names ("Firewall OS",
"Network OS" instead of FortiOS and Unifi), to be careful.

**Recommendation:** ship the standard as written, as the default
`schema-names.tsv`: types, subtypes and OS codes. Keep the site codes as
examples, since every user's sites differ.

## D21. Who owns SSH: this module or deploy-usawinssh

The spec has `Deploy-UsaBanner` set up SSH where asked, and the Windows
install configure SSH and offer to add a public key. `Deploy-UsaBannerGPO`, in
contrast, requires deploy-usawinssh in the domain. `deploy-usawinssh` already
installs OpenSSH Server and PowerShell 7, sets the default shell, and writes
a firewall rule limited to a list of sources.

**Recommendation: one owner, deploy-usawinssh.** `Deploy-UsaBanner` calls its
host script (vendored, or as a module dependency) when SSH is wanted, instead
of writing a second, different OpenSSH setup. The banner module adds only:
- its `Banner` line;
- a check that the default shell is a PowerShell;
- the optional public key.

For an administrator, the key goes in
`C:\ProgramData\ssh\administrators_authorized_keys`. Microsoft: "This file
only applies to administrator accounts. You must use it instead of the
user-specific file within the user's profile location". The file "must only
have permission entries for the NT Authority\SYSTEM account and
BUILTIN\Administrators security group" [fetched: Win32-OpenSSH key management
and server configuration pages].

A key in an administrator's own profile is silently ignored, which is the
classic trap, so the module sets those permissions itself. It uses the SID
form (`*S-1-5-32-544`), which works on localized Windows. Microsoft Entra ID
accounts cannot use key authentication at all [fetched].

## D22. Network devices (stretch)

Most network OSes have a static banner command: Cisco IOS and NX-OS have
`banner motd`, `banner login` and `banner exec`; PAN-OS has a login banner
setting [known]. A static banner is easy to push. Live stats (vPC state,
ports up and down, flaps in the last hour) are not something a banner can
compute on the device. They need either device-side scripting (EEM on
Cisco) or a collector that rewrites the banner every few minutes.
**Recommendation: later**, after the two OSes ship. Start with static
banners pushed by `Deploy-UsaBannerRemote`.

## D23. Names and paths without "Manatech"

The public copy still carries the Manatech art, "Welcome to Manatech", and
Manatech in every path, unit, task and function name. Proposed:

| Today | Proposed |
|---|---|
| `/etc/manatech/motd.conf` | `/etc/usabanner/usabanner.conf` |
| `/usr/local/share/manatech/` | `/usr/local/share/usabanner/` |
| `C:\ProgramData\Manatech\` | `C:\ProgramData\UsagiTools\Banner\` |
| `manatech-motd-update.timer` | `usabanner-update.timer` |
| `Show-ManatechBanner`, `Enter-ManatechPSSession` | `Show-UsaBanner`, `Enter-UsaPSSession` |
| "Welcome to Manatech", the Manatech art | "Welcome to <company>" from the configuration; the art per D3 |

The new module installs side by side with the old one and does not adopt its
GPO. A Manatech host moves when its old install is removed, by a step that
`Deploy-UsaBanner` offers when it finds one. The Manatech art and name live
only in the private site fork.

## D24. A LICENSE

The public repository has no LICENSE, and neither does deploy-usawinssh.
Without one, others may read the code but have no right to use or change it.
It also leaves "no liability" (D14) without a basis, and gives a logo
contribution (D4) no terms to be given under [known].

**Your call.** MIT is the common choice for PowerShell tools: short,
permissive, with a warranty disclaimer. Apache-2.0 adds an explicit patent
grant.
