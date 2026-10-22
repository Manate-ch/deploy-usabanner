# UsaBanner: decisions

> Companion to [SPEC.md](SPEC.md). Each decision has an ID, the question, the
> options, the recommendation and why, and what was decided. All 26 are
> decided; the table below sums them up. Facts are tagged **[measured]** (on a
> test host), **[fetched]** (read at the cited source on 2026-10-09, unless a
> date says otherwise) or **[known]** (from experience, not re-checked).

## Decided (2026-10-09 and 10-10)

| ID | Decision |
|---|---|
| D1 | Stage in `deploy-usamotd` until V1, then V1 lives at `deploy-usabanner` (the name is open either way) |
| D2 | Native renderers at login. PowerShell 7 for admin work, and on Windows the banner shows only in remote sessions |
| D4 | AGENTS.md as an invitation that encourages feedback of every kind, never a "permission"; the logo how-to in CONTRIBUTING.md |
| D9 | Host name and IP before login: opt-in, the admin's choice |
| D13 | One GPO plus an OU -> package table. Enforced stays a manual tool, for pushing an OU's policy through Block Inheritance below it |
| D16 | Leave conffiles alone, and mask the motd-news timer. Done and lab-tested 2026-10-11 |
| D24 | MIT, as in deploy-usawinssh |
| D3 | B: our own OS-coloured art by default. Art lives in `art/base` (ours and generics) and `art/apps` (third-party logos, opt-in) |
| D5 | Windows pre-init is the logon legal notice. The legal text shows both before login and before SSH authentication |
| D6, D7 | as recommended |
| D8 | all five templates as drafted; L3 is the default |
| D10 | an unknown service starts unchecked. `-Force` keeps it, and it is then an error line at every login |
| D11 | built in. A runnable example of the picker follows in its own MR |
| D12 | one JSON file |
| D14 | B, plus an "update available" line, and installed files writable only by root/SYSTEM |
| D15 | Windows Server 2022 and later |
| D17 | min/max over the last 24 hours, sampled every 15 minutes. A scheduled reboot is read live at every login |
| D18 | One entry point on Windows: each command checks for PowerShell 7 in `begin {}`, installs it when missing and runs itself again in `pwsh`. A GPO uses deploy-usawinssh's staged MSI, and `-UpdatePoSHMSI` refreshes it |
| D19 | A and B, with Windows' own decoder on Windows. On Linux, formats other than PNG need ImageMagick, and the cmdlet says so |
| D20 | Ship the naming standard as written. FortiOS and Unifi go back into the public `schema-names.tsv` |
| D21 | deploy-usawinssh owns SSH and the PowerShell 7 install. This module calls it |
| D22 | later |
| D23 | as proposed |
| D25 | meme voices for a lab VM (uwu, random, leet): the banner's own words, never its facts; `voice` is plain unless set, on any tier (2026-10-21) |
| D26 | the facts as records, one a line, tab-separated, kind first; on Linux from `linux/facts.sh`, which the login renderer and the module both read; on Windows the module reads the same facts itself (2026-10-22) |

## Contents

| ID | Decision | Status |
|---|---|---|
| D1 | Where the code lives, and its name | decided |
| D2 | What runs at login: PowerShell everywhere, or native renderers | decided |
| D3 | Default logos, and what may ship in a public repo | decided: B |
| D4 | AGENTS.md | decided |
| D5 | What pre-init, pre-logon and post-logon mean on each OS | decided |
| D6 | Border and corner sets | decided |
| D7 | Colour presets and the preview | decided |
| D8 | The five legal templates | decided: L3 default |
| D9 | Host name and IP before login | decided |
| D10 | Default services, and services that are not found | decided |
| D11 | The interactive UI: built in, or a module | decided: built in |
| D12 | The Export-UsaBanner package format | decided: JSON |
| D13 | GPO layering: one base, OU overrides | decided |
| D14 | The update channel | decided: B |
| D15 | Windows Server 2019 | decided: 2022 and later |
| D16 | Ubuntu: stop the apt prompts | decided; done 2026-10-11 |
| D17 | Slow facts, and min/max over what window | decided: 24 h |
| D18 | Installing PowerShell 7 before the module can run | decided: one entry point |
| D19 | New-UsaBannerArt: which image formats | decided: A and B |
| D20 | The naming standard as the shipped default | decided |
| D21 | Who owns SSH: this module or deploy-usawinssh | decided: deploy-usawinssh |
| D22 | Network devices (stretch) | decided: later |
| D23 | Names and paths without "Manatech" | decided |
| D24 | A LICENSE | decided: MIT |
| D25 | Meme voices | decided: plain unless set |
| D26 | The facts record | decided |

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

**Decided:** stage here until V1 is clean and ready, then V1 lives at
`deploy-usabanner`.

**How to get there: rename this project rather than starting a new one.**
GitLab's Settings > General > Advanced > Change path keeps:
- the history;
- every MR thread, which is the review record;
- the issues;
- the old URL, as a redirect for existing clones [known].

A fresh repository would make sense only if the history must not travel. That
is why the site copy became a new public repo: its history held a network
map. Nothing of that kind is here: this repository was public-clean from its
first commit.

**The name:** `deploy-usabanner`. It matches the cmdlet noun, and it covers
all three moments, where "MOTD" is only the post-login one.

Merge !1 first, as the baseline the redesign is measured against.

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

**Decided:** PowerShell 7 for everything an admin runs, and native renderers
for what runs at login. On Windows, the banner shows only in remote sessions
(SSH, `Enter-UsaPSSession`), never in a local console, because it would only
slow PowerShell's start. That is today's `-SshOnly` behaviour. One canonical configuration (JSON, D12)
that `Deploy-UsaBanner` compiles into what each renderer reads fastest: flat
`KEY=value` and TSV files for the shell, a `.psd1` for the Windows module.
Today's code already splits this way.

**Decided for M4 (2026-10-22): on Ubuntu, `pwsh` pre-draws and `awk` fills in
the dynamic data.** `Deploy-UsaBanner` draws in PowerShell what only the
configuration changes. At each login, `awk` fills in what changes between
logins: the facts (D26) and the health. A login waits on `sh` and `awk`
alone, and the banner keeps the module's look.

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

**Your aim (2026-10-09):** the legally distinct, historically reasonable way
for a free tool to show these logos, even if that means a line like "the
Windows logo is property of Microsoft Corporation". Mostly so that a host
whose admin picked no company logo still gets something good-looking and
informative, by policy.

**The precedent is real.** fastfetch, an MIT-licensed tool, ships built-in
ASCII logos for "Windows Server 2025", "Windows 11, Windows Server 2022",
"... Windows Server 2016, Windows Server 2019" and a dozen Ubuntu variants,
with no trademark notice in its logo source [fetched: fastfetch
`src/logo/ascii/w.inc`, `u.inc`, `LICENSE`]. neofetch did the same for years,
and the major distributions package both [known].

That is tolerance, not permission. A notice line grants no licence, and
Microsoft's own text still says not to use its logos. What keeps the risk low
is the use: identifying the OS a host runs, in a free tool, without implying
any endorsement.

**The default when no company logo is chosen:**

- **A. The OS logo**, in our own ASCII rendition, in the fastfetch tradition,
  with the trademark notice below.
- **B. Our own OS-coloured art**: a server pictogram in the OS colour, with
  the OS name in text; the OS logos one setting away.

**Decided: B.** Our own OS-coloured art is the shipped default. A third
party's logo shows only where an admin turned it on: `-BannerImage OS`, or an
app logo by name.

**The art folder, as you laid it out:**

- **`art/base/`** holds ours: the UsagiTools rabbit, the pictograms, and the
  company name in block letters from a font of our own.
- **`art/apps/`** holds third-party logos, drawn by us and never copied:
  - the OS logos: Windows, Ubuntu, and Tux with its credit;
  - application logos, such as SQL Server.

  Each one names its owner in its metadata and has a line in NOTICE. They are
  there to identify what a host runs, its OS or its role: the use that
  fastfetch's precedent covers. Keeping them in one folder means that, if an
  owner ever objects, the folder can go without touching anything else.
- **A trademark notice** for everything in `art/apps/` goes in NOTICE and the
  README, for example: "Windows and Windows Server are trademarks of the
  Microsoft group of companies. Ubuntu is a registered trademark of Canonical
  Ltd. These logos are shown only to identify what a host runs; this project
  is not affiliated with or endorsed by their owners." A one-line version on
  the banner itself is an option, off by default, because a line on every
  login is noise.
- **"Use my own" and `New-UsaBannerArt`** take anything the admin has; that
  is their call.
- **Community logos** arrive by merge request and a human reviews each one
  (D4).

**The pictograms are mock-ups only so far.** Appendix A has rough ones for the
rabbit, a server and a terminal. Shield, cloud and globe are names on a list,
not drawings yet. The final art gets drawn in V1, under the same plain-ASCII
rule.

**Drawn in M1 (2026-10-20).** The server, terminal, shield, cloud and globe
are in `art/base`, each picked from a gallery of candidates. Where a part
should take the OS colour, its palette entry names a tint instead of a
colour: `os`, or a shade of it, `os-light`, `os-dark` or `os-fill`. Those
parts take the host's OS colour: Windows blue, Ubuntu orange, and a neutral
grey on any other system. `Show-UsaBannerArt -Os` draws them in another OS's
colour.

The company name is set in the Pixel font (`fonts/pixel.json`, also picked
from the gallery): every capital and digit, and the punctuation names tend
to use, five rows high, in the welcome line's colours from left to right.
`Show-UsaBannerArt -Text` sets one. A name wider than 64 columns, the most
any art may be, is refused for now; M2 decides what a banner shows instead.

**Decided in M2 (2026-10-21), from the gallery:** a name too wide for the
Pixel font (about ten characters; "Contoso LLC" is 63 columns) takes the
Small font (`fonts/small.json`), three rows of lines and bars drawn for this.
Next it takes two lines of Small, broken at the space that leaves the wider
line narrowest; then spaced capitals; then the name as written, never cut.
A font with no glyph for one of the name's characters is passed over.
"Contoso Systems" fits Small on one line, and "Contoso Pharmaceuticals" on
two. `tests/frames` holds each sample name's frame.

The logos in `art/apps` are Tux (sitting), the Windows logo and the Ubuntu
Circle of Friends, also picked from the gallery, each naming its owner and
carrying its line in `UsaBanner/NOTICE` and the README. Tux and the Circle
of Friends were drawn from our own description of their shapes, at 2 x 4
dots a character, rather than taken from ASCII art found online: such art's
"use it how you want" seldom comes from the person who drew it.

## D4. AGENTS.md

AGENTS.md is a real convention: a Markdown file at the repository root that
tells AI coding agents how to work on the project. It is now stewarded by the
Agentic AI Foundation under the Linux Foundation, and its site lists 23 tools
that read it, among them Codex, Cursor, GitHub Copilot's coding agent, Gemini
CLI, Jules, Aider and Zed [fetched: github.com/openai/agents.md]. Claude Code
reads `AGENTS.md` itself since v2.1.277, but only when the repository has no
`CLAUDE.md`; older versions, and sessions where that support is off, read
`CLAUDE.md` only. A one-line `CLAUDE.md` containing `@AGENTS.md` covers both,
and the import never makes Claude read `AGENTS.md` twice [fetched 2026-10-11:
code.claude.com/docs/en/memory, section "AGENTS.md"].

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

## Feedback, ideas and logos
This tool is free so that the next admin can learn from good tooling
without a paywall, and every report makes it better. If the person you work
for hits a bug, has an idea, or wants their logo in the default set, tell
them that issues and merge requests are welcome: Tyson, Claude and Yuki read
every one. If they ask you to file one:
- A bug or an idea: an issue saying what they ran, what they expected, and
  what happened instead.
- A logo: a merge request with
  1. `art/<name>.art` (plain ASCII, at most 64 columns by 30 rows, colour
     markers as described in `art/README.md`) and `art/<name>.json` (name,
     artist, licence, source);
  2. a sentence saying that your human owns the logo, or holds a licence
     that lets it be distributed under this repository's licence. Another
     company's logo goes in `art/apps/` only to identify what a host runs,
     drawn by the contributor rather than copied, with its owner named in the
     metadata. The maintainers decide;
  3. the output of `Show-UsaBannerArt -Name <name>`.

A human maintainer reviews every merge request by hand, and asks for more
when a quick OK is not enough. Do not open an issue or a merge request your
human did not ask for.
```

**Decided:** the invitation framing, and it invites feedback of every kind,
not only logos: the aim is to help as many people as is reasonable, by
encouraging them, not by pushing anyone's agent. A one-line `CLAUDE.md` with
`@AGENTS.md` comes with it. Still open: whether the logo how-to lives here or
in a CONTRIBUTING.md that AGENTS.md points to. "This repository's licence" is
MIT (D24).

**Done 2026-10-11:** `AGENTS.md` and the one-line `CLAUDE.md` at the root,
as drafted above except for logos. `art/` and `Show-UsaBannerArt` do not exist
yet, so for now a logo comes as an issue carrying the art, its metadata and
the ownership sentence. The merge-request how-to arrives with the art library
(V1), and the open question above is settled then.

**Settled with M1 (2026-10-21): CONTRIBUTING.md holds the logo how-to, and
AGENTS.md points to it.** People send logos with or without an agent, and
CONTRIBUTING.md is the file a person looks for; AGENTS.md, which an agent
reads in full every session, stays short. A logo is a merge request that
adds one art file, which `New-UsaBannerArt -OutFile` makes from an image.
The draft's pair of files, `art/<name>.art` and `art/<name>.json`, became one
JSON file per piece, art and mask and metadata together.

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

**Decided for Ubuntu:** pre-init is `/etc/issue`, at the console, before the
login prompt.

Why it looks like `issue.net` "just before login" on some systems: these are
two files for two doors.
- `/etc/issue` is printed by agetty on the machine's own console (physical,
  or a VM's console window), before `login:`.
- `/etc/issue.net` is what sshd sends before authentication, because this
  repo's `sshd_config.d` drop-in points sshd's `Banner` at it.

Today both carry the same art (`issue.net` is the plain-ASCII copy). So an
SSH login shows the `issue.net` version just before the password prompt, but
only on hosts where the SSH banner was installed (`install.sh --ssh`, or the
Group Policy run). Same art, different moment: on SSH that is the pre-logon
banner.

**Decided for Windows:** pre-init is the logon legal notice (console and
RDP). On both OSes the legal text shows in two places: before login, and
before SSH authentication (the SSH `Banner`). That is where you saw the
original one pop up on the VMs it reached.

**Drawn in M2 (2026-10-21).** One arrangement for all three, picked from the
M2 gallery: the art on the left, the company name beside it in block
letters, the host line under the name (D9), and the legal box below, 64
columns at most. A name that comes out in block letters only on a line of its
own goes under the art instead.

- **SSH** (`Get-UsaBannerPreLogon`): plain ASCII, in the border set's ASCII
  form; Classic stands in for a Unicode set (D6).
- **Console** (`Get-UsaBannerPreInit`): the same frame in 16 colours, as an
  issue file. agetty reads every backslash in that file as an escape: `\e`
  prints ESC, `\n` the host name and `\4` an IPv4 address, and any other
  escape prints the character after the backslash. So the file writes each
  backslash of the art and the border as `\\` and each ESC as `\e`, and
  leaves the host name and IP to agetty, which fills them in each time it
  prints. agetty has read the file this way since util-linux 2.32, the
  version that brought `/etc/issue.d` (D16) [fetched: `term-utils/agetty.c`
  at v2.32 and v2.39.3]. `tests/PreLogin.Tests.ps1` reads each file back as
  agetty does and compares the result with the frame drawn.
- **Windows** (`Get-UsaBannerLogonNotice`): the legal text's title as the
  caption, and its paragraphs, joined by CRLF, as the text; Windows wraps it.
  That is the single string the registry ends up holding. Group Policy
  carries the text as one string per line, and there an empty string ends
  the value, so whatever writes the policy sends a blank line as one space
  [measured: Server 2025, 2026-10-18].

A voice (D25) speaks in all three.

**After login** (`Get-UsaBannerPostLogon`), arrangement A from the gallery,
today's order: the art; "Welcome to <company>"; the tier strip; the panel,
titled with the host name and its badge, a row per fact; then the health
lines, each problem, or all clear with the checks that ran. Those lines wrap
at 64 columns, where today's all-clear line runs to 70 with six checks. A
client that is not UTF-8 gets Classic and today's ASCII marks (`#`, `.`,
`[ok]`, `[!!]`, `[XX]`). A fact the host does not give gets no row, so M3
can add facts one at a time.

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

**Decided, as recommended:** ship all of the above. The non-interactive
default is **Classic**; the interactive default is **Rounded**, falling back to
Classic.

**Drawn in M2 (2026-10-21).** All fourteen sets are in
`UsaBanner/Private/Frame.ps1`, each marked as right in the M2 gallery. The
Unicode ones are written as code points, so the module stays ASCII, and Block
is the full block, which joins up. A Unicode set asked for where the text
shows before login draws as Classic. The title cap moved to where you asked
for a kaomoji: `border.cap`, an ASCII face such as `(^_^)`, sits centred in
the top line between the title and the hint. ASCII keeps it whole before
login, where Unicode kaomoji would break the box for the reason above.
`tests/frames` holds each set's box as a golden frame.

After login, a client that is not UTF-8 gets Classic too. Which clients are
UTF-8 is read as `Show-UsaBanner -Glyphs auto` does: `USABANNER_GLYPHS`
(unicode or ascii) when set, as `USABANNER_COLOR` overrides the colour mode;
else Windows counts as UTF-8, as today's Windows banner does; else the locale,
the first of `LC_ALL`, `LC_CTYPE` and `LANG` that is set; with none set, the
C locale, which is not.

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

**Your question: can it detect what the terminal draws, and fall back on its
own? Partly.**

- **What it can read:**
  - `TERM`: `xterm-256color` means at least 256 colours, and `dumb` means
    none;
  - `COLORTERM`: `truecolor` or `24bit` means 24-bit;
  - `NO_COLOR` means none;
  - on Windows, `WT_SESSION` means Windows Terminal, which does 24-bit
    [known].
- **What gets in the way:**
  - SSH forwards `TERM` but not `COLORTERM`, unless both ends are set up for
    it (`SendEnv` / `AcceptEnv`), so most SSH sessions only ever say "256"
    [known].
  - Asking the terminal itself, with an escape-sequence query, is unreliable:
    many clients do not answer, and on Ubuntu the banner runs under
    `pam_motd`, which cannot read an answer back [known].
  - Windows sshd passes 24-bit colour through on 2022 and 2025 [measured
    2026-10-10, D15].
- **So, three layers**, the last one winning:
  1. **Auto-downgrade** on every signal the banner does have.
  2. **A per-host colour mode the admin picks at setup.** The colour step has
     the compatibility check you describe: a 24-bit gradient bar and a
     256-colour bar, and "do these look smooth?". The answer sets the mode.
  3. **A per-user override**, `USABANNER_COLOR=16` in a profile or SSH client
     setting, for the one admin on an old client.

**Decided:** the presets, the console preview and the three layers, as
recommended.

**Drawn in M2 (2026-10-21).** A preset is a style for each role the banner
after login draws: labels, values, dim text, ok, warn and bad, the border,
and the welcome gradient.

- **UsagiTools** is today's palette.
- **Classic 16** is the same palette drawn in 16 colours at most, so it
  looks the same on every colour terminal.
- **High contrast** has bold yellow labels, white values and a white border.
- **Mono** keeps bold and reverse only: the tier strip, the tier and the
  badge in reverse video.
- **Custom** draws as UsagiTools for now: the configuration has nowhere to
  keep its colours until the colour step (M5) asks for them.

`NO_COLOR` now gives the mono mode, which draws Mono's palette whatever the
preset, since no other one shows without colour. M0 had read it as none,
which drops bold and reverse too. Art has neither, so `Show-UsaBannerArt`
under `NO_COLOR` still draws it plain.

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

**Decided:** all five as drafted, and **L3** is the default.

**Drawn in M2 (2026-10-21).** The box's top line keeps today's shape, picked
from the M2 gallery: the text's title on the left and "Log in for more
information" on the right. The title is the word the text opens with,
WARNING (L3, L4) or ATTENTION (L5), and the text then drops it; L1 and L2
open with none, so they get HELLO and PRIVATE. Text you write yourself keeps
its lines as paragraphs, and takes its title from an opening word in capitals
with a colon, such as "PRIVATE PROPERTY:", or else NOTICE.
`tests/Legal.Tests.ps1` holds the templates to the text above, word for word.

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

**Decided:** opt-in; the admin decides.
- **Pre-init (console):** the host name and IP are offered, as a soft
  default.
- **Pre-logon (SSH):** the company name and legal text by default; the host
  name and the IP are each opt-in.
- **On a PUB host:** turning either on shows a warning that anyone who starts
  to log in can read it, and then the admin's choice stands.

**Drawn in M2 (2026-10-21).** The configuration's `preInit` and `preLogon`
each hold `hostName` and `ip`: on at the console and off over SSH unless
set. The host line goes under the company name. Over SSH the two values go in
when the banner is drawn. At the console agetty fills them in as it prints
(D5), so a renamed or readdressed host shows its new name and address with no
redraw. agetty picks that address itself: the first interface that is up,
running and not loopback, or else the address the host name resolves to
[fetched: `term-utils/agetty.c` at v2.32].

## D10. Default services, and services that are not found

| OS | Default, checked | Only when |
|---|---|---|
| Windows | `sshd`, `W32Time` | |
| Windows | `Netlogon` | the host is domain-joined (on a workgroup host it is manual and stopped, so it would report every login) |
| Ubuntu | `ssh`, `cron`, the time sync unit in use (`systemd-timesyncd` or `chrony`) | |
| Ubuntu | `sssd`, `adsysd` | the host is AD-joined |

- **Not found**: the frame-by-frame picker keeps an unknown name checked until
  the user unchecks it. **Decided:** keep it listed, but **unchecked**, with
  `-Force` to keep it anyway. A kept one is then an error line at every
  login ("ERROR: service ABC not found"). That is the point when a
  post-install script expects the service: if it is missing, the banner says
  so.
- **"A service that cannot be monitored will slow down logon"**: not what
  today's code shows. A lookup for a missing service fails at once on both
  OSes [known]; the slow parts are broad queries (all services through
  WMI/CIM). **Decided:** measure it in the lab before the UI warns about it.
- The Ubuntu picker lists systemd service units, the same UI.
- §5.4 item 17 (a non-standard automatic service not running) is what today's
  Windows module does: auto-start services that are stopped, minus
  trigger-start services, minus a built-in list of services that stop by
  design, plus the host's own ignore list. Keep that rule.

**Watched on Ubuntu (M3, 2026-10-22).** The configuration's `services` is
`default` or the names. `linux/facts.sh` asks systemd about all of them in
one `systemctl show`, and gives the panel's services row and a problem line
for each one down.

- **The time sync daemon in use** is the first installed of chrony, ntpsec,
  ntp, openntpd and systemd-timesyncd: the lab's Ubuntu 24.04 host keeps
  time with ntpsec, neither of the two named above [measured].
- **A host joined to AD** is one with `/etc/sssd/sssd.conf`. sssd is then
  watched, and adsysd where it is installed: logins through AD need sssd,
  not ADSys, so a host without ADSys is not broken. A host whose ADSys was
  removed by mistake does not show.
- **On demand:** a service that is not running while its socket listens is
  idle by design, and counts as up; systemd starts it at the first
  connection. adsysd is one [measured]; ssh is one on Ubuntu 24.04 until
  its first connection [known].
- **Not found** is bad, as decided above: `service nginx not found`.
- **Today's banner's other checks** come along, each named on the all-clear
  line only when it ran: the units that failed; the disks from 85% full and
  the memory from 90% in use, each bad from 95%, the panel's levels (today's
  memory line was never bad); the clock, when `timedatectl` answers; a
  reboot pending. Today's note of setup changes waiting belongs to its
  `install.sh`; V1's deploy (M4) brings its own.

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

**Decided: A, built in.** A frozen dependency that needs its own install is
not worth it, short of forking it into the project. Every interactive cmdlet
also checks that it really has a console to talk to (not redirected input, VT
available). If it does not, it stops and prints the flags to use instead. A
runnable example of the frame-by-frame picker comes in its own MR, with
tests that drive it by scripted keys.

## D12. The Export-UsaBanner package format

- **A. One JSON file** (`usabanner.json`): the settings, the art as lines of
  text, the VLAN rows, the services, the legal text. Readable, diffable in an
  MR, a few KB, and easy to pin with a hash.
- **B. A ZIP** of the same pieces as separate files.

**Decided: A, one JSON file.** Nothing in it is binary: `New-UsaBannerArt`
turns an image into text when the art is made, so the package never needs
the image. A ZIP would only add a step to read it, and hide the content from a
diff.

Custom art is no obstacle. Each line of art is a JSON string, and
`ConvertTo-Json` escapes backslashes and quotes, so `\_/` is stored as
`\\_/` and reads back exactly. Colour markers stay plain text. Two details:
`-Depth 10` (the default depth of 2 would flatten nested settings), and a
test that round-trips every built-in piece of art byte for byte.

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

**Decided: B**, with Enforced as a manual tool when a case needs it. The use
you had in mind is the right one: Enforced on a non-root OU's link pushes
that OU's policy through a Block Inheritance set further down. As Microsoft
puts it, "Enforced is a link property and takes precedence over block policy
inheritance, a container property" [fetched: learn.microsoft.com, Group
Policy processing].

**Block Inheritance matters to B in its own way.** With one GPO linked at the
root, an OU that blocks inheritance never receives that GPO at all, so its
hosts get no banner. There are two ways through:

- **Link the same GPO directly at the blocked OU.** A direct link is not
  inherited, so the block does not stop it [known].
- **Set Enforced on the root link**, which goes through every block below it.

`Deploy-UsaBannerGPO` can list the OUs under its links that block
inheritance, and add the direct links with `-LinkTarget`. Enforced stays a
manual choice, as decided.

## D14. The update channel

What the job does is run code from a public repository as root/SYSTEM at
every login on every host that has it, so whoever can change what it pulls
can run code on all of them.

- **A. Follow `main`**: pull and install whatever is on the default branch.
- **B. Follow releases**: install only a tagged release, after checking each
  file against the release's `SHA256SUMS`; optionally pinned to a version.
- **C. Follow the module**: once UsagiTools is on the PowerShell Gallery,
  `Update-Module` on a schedule, with the module signed.

**Decided: B now, C later.** A is fine for the maintainer's own lab, as an
explicit `-Channel main`. Two additions:

- **An "update available" line.** When the job sees a newer release than the
  one installed, and is not set to install it, the banner adds one line:
  "This banner has an update available. See <releases page> for more info!"
  Until the GitHub home exists, that is this project's GitLab releases page.
- **Only root / SYSTEM and Administrators may change the installed files.**
  Everyone may read them, because the banner runs as whoever logs in. On
  Ubuntu that already holds: root owns the files, mode 644/755. On Windows,
  today's install leaves `C:\ProgramData\Manatech` with the ACL it inherits
  from `C:\ProgramData`, which lets ordinary users create new files in
  subfolders [known]. A user could then plant a file the banner reads when
  it is missing, such as `ad-description.txt` on a host outside the domain,
  and show other admins whatever text they like. The install sets the folder's
  ACL explicitly: Administrators and SYSTEM full control, Users read and
  execute only, inheritance off. The update job and its staging area get the
  same.

The warning text proposed for the opt-in:

```text
This keeps the banner updated from a public repository. The update runs as
root (SYSTEM) on this host, at every login. Anyone who can change that
repository's releases can change what runs here. The code is provided as is,
without warranty; its authors are not liable for any damage it causes.
Type YES to turn updates on.
```

The "not liable" part needs a LICENSE behind it to mean anything (D24).

## D15. Windows Server 2019

**Decided: Windows Server 2022 and later.** For the record, 2019 is not
end-of-life yet. It left mainstream support on 2024-01-10, and extended
support runs to 2029-01-10 [fetched: Microsoft Lifecycle]. But 2022 and later
is the line, and it matches today's Windows code. The notes below are kept for
the colour question, which applies to every version.

What 2019 (build 17763) would have needed:

- **Colour in the console:** VT escape sequences, and 24-bit colour since
  build 14931, which shipped as Windows 10 1703 [search-snippet: Microsoft's
  console blog].
- **ConPTY:** its minimum server is Windows Server 2019 [fetched:
  `CreatePseudoConsole` requirements].
- **OpenSSH Server:** "added to Windows Server ... starting with Windows
  Server 2019" [fetched].

**The open question was: does 24-bit colour survive an SSH session?** The
Win32-OpenSSH wiki says sshd uses ConPTY, but the terminal-emulation code in
its source writes only the 16 console colours [fetched: `shell-host.c`].

**Answered: it does [measured 2026-10-10, lab].** In a forced terminal
(`ssh -tt`), pwsh 7.6 wrote three codes: 24-bit orange `ESC[38;2;255;100;0m`,
256-colour `ESC[38;5;208m`, and 16-colour `ESC[33m`. All three arrived
unchanged from Windows Server 2022 (build 20348) and 2025 (build 26100).
Windows' pseudo-console (ConPTY) redraws the output and drops redundant
resets, but passes the colours through as written. So the 16-colour path in
`shell-host.c` is not the one in use there.

One trap for anyone testing this: on 2025, the pseudo-console shuts down when
the client's input closes, and the output is lost with it. A script that runs
`ssh -tt` with its input already at end of file sees nothing come back. With
the input held open, everything arrives. 2022 delivered either way. No Server
2019 VM is needed.

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
  `deferred_configure_conffile`; measured: the lab test below]. So the scripts
  stay off and nothing asks. The exception is `50-landscape-sysinfo`, which is
  not a conffile. It is a symlink that no package owns, to
  `/usr/share/landscape/landscape-sysinfo.wrapper`, which landscape-common
  owns [measured]. `chmod -x` on the link changes that file, and a
  landscape-common reinstall resets its mode to 755 [measured]; an upgrade
  unpacks it the same way. So the
  statoverride goes on the wrapper, not on the link (a link has no mode of its
  own): `dpkg-statoverride --update --add root root 0644
  /usr/share/landscape/landscape-sysinfo.wrapper` makes dpkg install it that
  way [fetched: dpkg-statoverride(1); measured]. (The first draft of this
  decision put it on the link.)
- **motd-news:** the documented switch is `ENABLED=0` in
  `/etc/default/motd-news`, which is the conffile edit that can ask. Instead:
  leave the file alone, run `systemctl mask motd-news.timer`, and `chmod -x
  50-motd-news`. Masking is not a documented switch. A Launchpad bug says the
  service is still scheduled when only the script is turned off, and one
  forum report has a base-files upgrade erroring after the units were deleted
  (not masked) [search-snippet]. The lab test covered it: with the timer
  masked, a point-release upgrade of base-files raised no error [measured].
- **Diverting the conffiles (`dpkg-divert`) is not the answer.** It works
  mechanically, but Debian Policy says not to divert a conffile [search-snippet:
  Debian Policy, diversions appendix; mechanism fetched from dpkg 1.22.6
  source].
- **Hosts already installed:** the installer puts the stock files back. The
  first plan was to delete them and reinstall base-files with
  `--force-confmiss`, which needs apt and the network. What shipped needs
  neither: `conffiles.sh` rebuilds each stock text (`/etc/issue` is
  `<PRETTY_NAME> \n \l` and a blank line, `/etc/issue.net` is the
  `PRETTY_NAME` alone, and `/etc/default/motd-news` is the current file with
  `ENABLED=1`), and writes it only when its md5 is the one dpkg recorded
  [measured: equal to the md5s base-files 13ubuntu10.4 and 13ubuntu10.5
  record]. A file it cannot rebuild is left as it is, and the log says so;
  dpkg asks about that one at its next upgrade, as before. And for
  `/etc/issue` and `/etc/issue.net` it writes only over a banner an older
  version wrote: `conffiles.sh` lists the md5 of each such version, and of
  the original banner they replaced, installed by hand. Anyone else's text
  stays, because the stock text would fit over it just as well and would
  erase it.

**The lab test (2026-10-11) [measured]:** a 24.04.4 VM that the old
installer had set up, where `dpkg --verify` flagged `/etc/issue`,
`/etc/issue.net` and `/etc/default/motd-news` as changed.

| Step | Result |
|---|---|
| `install.sh --retire --ssh` with the fix | all three back to stock, md5 equal to dpkg's records. The console shows the OS line once, then the banner; sshd's effective Banner is `/etc/manatech/issue.net`; the timer is masked; the wrapper has a 644 statoverride |
| `apt-get install --reinstall base-files motd-news-config`, stdin closed | became a real point-release upgrade, 24.04.4 to 24.04.5 (base-files 13ubuntu10.4 to 10.5): exit 0, no prompt, no `.dpkg-dist`. The scripts stayed off, and the masked timer caused no error |
| the same again, now the same version | exit 0, no prompt |
| `landscape-common` reinstalled | with the statoverride, the wrapper stays 644. Without it (the control), the reinstall resets it to 755: the old `chmod -x` came undone at every landscape-common upgrade |

**Decided:** leave the conffiles alone, and mask the motd-news timer.
**Done 2026-10-11** in this repo's `install.sh`, under today's names
(`/etc/issue.d/50-manatech.issue`, `/etc/manatech/issue.net`); V1 renames them
per D23.

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
| Reboot scheduled | **live at every login**: `/run/systemd/shutdown/scheduled`, the file `shutdown --show` reads (when and why) | **live at every login**: the last restart-initiated event (System log, event 1074) since boot. Administrators can read the System log over SSH; for other users, the job's cached value. Windows Update's own restart schedule comes from the cache [known; to measure] |

**Your call: min/max over what window?** Since boot, over the last 24 hours,
or something else? Anything but "now" needs the job to sample between logins
and keep the samples. Proposed: the last 24 hours, sampled every 15 minutes
(96 samples, a few KB).

**Decided:** the last 24 hours, sampled every 15 minutes. A scheduled reboot
is not sampled at all: it is read live at every login (table above), so a
reboot set for five minutes from now shows the moment it is scheduled. That
is the point of the one-minute idea, without a job running every minute. On
Windows, a PowerShell task every minute would be a lot of churn for one fact.

**How the samples are kept (M3, 2026-10-22):**

- **The periodic job** is `UsaBanner/linux/sample.sh` on Linux, as root,
  and `Update-UsaBannerSample` in the module on Windows, as SYSTEM. M4
  installs the timer and the task.
- **The samples** are in `/var/lib/usabanner/samples.tsv` or
  `%ProgramData%\UsagiTools\Banner\samples.tsv`. Each line is a sample, its
  fields separated by tabs: the time in seconds since 1970; `cpu`, `memory`
  or `disk` with the disk's mount point or drive; the percentage. Samples
  older than 24 hours go at every run. The file is written whole and moved
  into place, so a login never reads half of it, and every user can read
  it: `Show-UsaBanner` does.
- **A sample takes the measure a login takes:** on Linux, the 1-minute load
  as a share of the CPUs; on Windows, the busy percentage over 200 ms (D26).
- **The range at login** is the lowest and highest of the samples newer than
  24 hours and of the value now, so it always holds the value shown. Until
  the first sample there is no range.
- **On Linux the job also caches the FQDN** (D26) in
  `/var/lib/usabanner/fqdn`, looking it up for 5 seconds at most. A name is
  cached only when it is the host's own name followed by a domain, so a
  hosts file's `localhost.localdomain` never shows; when the lookup gives
  the short name alone, the cache goes.

**The slow facts on Linux (M3, 2026-10-22).** The job writes them anew at
every run to `/var/lib/usabanner/slow.tsv`, a line each with its time, and a
login takes those less than 24 hours old:

- **the memory's kind and speed**, as `DDR4-3200`, from `dmidecode`: the
  first module with a type, at its configured speed. A virtual machine's
  firmware gives none: Hyper-V says Unknown for both [measured on a lab VM];
- **each local filesystem's kind**, from the disk under it through LVM, RAID
  and partitions: removable, NVMe, SSD or HDD. A virtual machine's disks get
  none, because the storage behind them cannot be known: a Hyper-V virtual
  disk says it is rotational [measured];
- **the updates waiting**, from `apt-check`, which gives all of them, then
  the security ones. The row warns only while security updates wait: other
  updates are routine, and a row that is always amber stops being read.

At login, the CPU's rated speed comes from the model name (`@ 3.10GHz`), else
cpufreq. A reboot is read live, as decided above: pending, by
`/run/reboot-required` and the packages that asked for it, a kernel shown as
`kernel 6.8.0-88`; scheduled, by `/run/systemd/shutdown/scheduled`, the file
`shutdown --show` reads. Its `USEC=` is microseconds since 1970 and its
`MODE=` is reboot, poweroff or the like [fetched: systemd v255,
`src/login/logind-dbus.c`, `update_schedule_file`].

**The slow facts on Windows (M3, 2026-10-22).** `Update-UsaBannerSample`
writes them anew at every run, after its sample, to
`%ProgramData%\UsagiTools\Banner\slow.tsv`, in the same form with one kind
more, `cpu-speed`: Linux reads its CPU's speed at login, where on Windows it
would be one more CIM query for every login to wait on.

- **the CPU's rated speed**, from `Win32_Processor`'s name (`@ 3.10GHz`),
  else its `MaxClockSpeed`: a Hyper-V guest gave 2195 MHz for a CPU named
  `@ 3.10GHz` [measured on two lab VMs];
- **the memory's kind and speed**, from `Win32_PhysicalMemory`: the first
  module whose SMBIOS type is a DDR one, named as dmidecode names it
  [fetched: dmidecode, `dmi_memory_device_type`], at its configured speed,
  else its rated one. Hyper-V gives type 2, Unknown, and no speed [measured];
- **each fixed drive's kind**, from the physical disk under its partition
  (`Get-Partition`, `Get-PhysicalDisk`): removable or NVMe by its bus, else
  SSD or HDD by its media, Linux's order. A Hyper-V virtual disk is
  `Unspecified` on a `SAS` bus [measured];
- **the updates waiting**, from the Windows Update agent: the software
  updates neither installed, hidden nor optional (`BrowseOnly=0`), and those
  in the Security Updates classification, by its id [fetched:
  `IUpdateSearcher::Search`; WSUS Classification GUIDs]. The searcher has
  `Online` off, so it does not go online [fetched:
  `IUpdateSearcher::Online`]: it answers from the agent's own last scan, as
  `apt-check` answers from apt's lists, and the job adds no scan to an update
  server's load. How long the search takes, and that its count is the one
  Settings shows, are measured in the lab run (M3's last merge request).

A virtual machine's memory and drives get no kind, as on Linux. Windows has
no `systemd-detect-virt`, and `HypervisorPresent` cannot tell: it was true on
both lab VMs [measured], and it is true on a Hyper-V host, or on any host
running virtualization-based security [known]. So the job goes by the
computer's maker and model: Hyper-V's guests are Microsoft Corporation's
`Virtual Machine` [measured]; QEMU, KVM, Xen, VMware, VirtualBox and the
large clouds name themselves in one or the other [known, not measured].

A reboot pending is read live at login from the two registry keys today's
banner reads: Component Based Servicing's `RebootPending`, shown as
`servicing`, and Windows Update's `RebootRequired`. Pending file renames, in
the table above, are left out for now, as today's banner leaves them: an
installer replacing a file in use queues one, but so does one deleting a
temporary file [known], and how often the key is set on a host where no
restart is planned is counted in the lab run before they are added. A
restart scheduled is not read yet either: event 1074 and Windows Update's
own schedule are measured in the lab run first. Until then the row says
`none pending`, never `none scheduled`.

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

**Decided (2026-10-09): one entry point on Windows, no separate bootstrap.**
Each command checks the PowerShell it runs in from `begin {}`, instead of
`#Requires -PSEdition Core`. Under Windows PowerShell 5.1 it installs
PowerShell 7 when it is missing, then runs itself again in `pwsh` with the
same parameters, so a 5.1 console just works.

- **Interactive**: the newest MSI, checked against the release's
  `hashes.sha256` and its Microsoft signature, the way deploy-usawinssh
  checks an unpinned MSI today [fetched: the v7.6.6 release lists
  `hashes.sha256`].
- **GPO**: the MSI deploy-usawinssh stages, installed unattended at startup
  (D21). `Deploy-UsaBannerGPO -UpdatePoSHMSI` downloads the newest MSI, checks
  it, and stages it through deploy-usawinssh's own `-PwshMsi` code, so both
  policies share one MSI and one installer.
- **The `Deploy` verb**: Windows PowerShell 5.1 warns about it when the module
  loads. Accepted, and documented.
- **Ubuntu** keeps its `sh` bootstrap: it has no older PowerShell to run a
  check in.

What makes it work: Windows PowerShell 5.1 parses a whole file before it runs
any of it [known], so one PowerShell 7 operator anywhere in that file (`??`,
`? :`, `&&`) stops it before `begin {}` runs. The module's loader and the
check stay 5.1-safe, and the PowerShell 7 code lives in files the loader
dot-sources only under `pwsh`. PSScriptAnalyzer's `PSUseCompatibleSyntax`
rule, aimed at 5.1, can hold the loader to that in the tests [known].

**The MSI has an end date.** "Beginning with the PowerShell 7.7.0 release,
there is no MSI package available. WinGet only installs the MSIX package"
[fetched: Install PowerShell 7 on Windows, updated 2026-09-22]. 7.6 is the
current LTS, supported until 14 November 2028 [fetched: PowerShell Support
Lifecycle]. WinGet isn't available on Windows Server 2022, and the MSIX
package installs for one user, in a sandbox that blocks changes to `$PSHOME`
[fetched], so it can't be every admin's SSH shell. The MSI line carries V1 to
late 2028. After that the ZIP package (machine-wide, the PATH set by us, no
Microsoft Update) is the fallback, to decide then.

Until then the MSI opts in to Microsoft Update by default (`USE_MU=1`,
`ENABLE_MU=1`), "whether that's with Windows Update for Business, WSUS,
Microsoft Endpoint Configuration Manager" [fetched]. So 7.6 patches arrive
the way Windows patches do, and `-UpdatePoSHMSI` mostly sets what a new host
installs.

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

**Decided (2026-10-09): A and B, with option C's decoder on Windows.** Windows
needs nothing extra. PowerShell 7 on Windows ships `System.Drawing`: it loads
and makes a bitmap in pwsh 7.6 on Server 2022 and 2025 with nothing installed
[measured 2026-10-10, lab]. Through it the cmdlet reads PNG, JPEG, GIF, BMP
and TIFF [known]. On Linux, PNG works out of the box, and any other format needs
ImageMagick. When it is missing, the cmdlet says so with the install line
(`sudo apt install imagemagick`) instead of a bare "unsupported format".

**Built in M1 (2026-10-20), and what that settled:**
- A PNG goes through the module's own decoder on Windows as well, so one PNG
  makes the same art on every system. System.Drawing takes the other formats.
- The ASCII version has two styles. *Shape*, for logos, picks each character
  by its shape, sampling each cell as 2 x 4 dots: the method M1's logos were
  drawn with. *Ramp*, for photos, is the character ramp above. auto picks
  shape for an image with a background and few colours.
- The colour version is a colour class per character, in the art file's mask
  and palette, as the module's own art has: every colour mode draws it, and
  its plain version is the one shown before login. The half-block version
  needs two colours per cell, which the art format does not have; it waits
  for a decision.

## D20. The naming standard as the shipped default

The author is fine with publishing the naming standard (SPEC §5.4). Today's
public copy, MR !1, replaced two OS codes with generic names ("Firewall OS",
"Network OS" instead of FortiOS and Unifi), to be careful.

**Recommendation:** ship the standard as written, as the default
`schema-names.tsv`: types, subtypes and OS codes. Keep the site codes as
examples, since every user's sites differ.

**Decided (2026-10-09): as recommended.** FortiOS and Unifi go back into the
public `schema-names.tsv`, exactly as the private copy has them, in their own
small MR. They are vendor names, not lab details.

**Built in M2 (2026-10-21).** The table lives in the configuration as
`naming`: four lists, `sites`, `types`, `subtypes` and `os`, each row a code,
a name and a colour. The defaults are today's `schema-names.tsv` row for row,
and `tests/Identity.Tests.ps1` holds them to it while the old scripts ship.
A list replaces its default whole, so a host's own `sites` take the place of
the five examples and the shipped types, subtypes and OS codes stay. Two
rules are new:

- A name is decoded only when its type, subtype and OS are all in the table;
  a site the table lacks shows as `?`, as today. Today's scripts decode any
  name of the right shape, which in a public tool would show `proxy-01` as
  "? / ? / Networking Switch / ?".
- An empty `types` list turns decoding off, for a host named by another
  standard.

The VLAN rows (SPEC §3.1) gain two of the columns today's `vlans.tsv` has
beyond the name, tag and network: a colour for the badge, and a short name
for it (`Mgmt` in "HQ - 10-Mgmt"). The site column stays out, since the host
name gives the site; a host whose name is not decoded gets a badge without
one. The named colours are today's `colors.tsv`, and the tiers keep today's
`envs.tsv` colours: UNSET grey, DEV-TEST charcoal, LAB orange, PROD blue and
PUB pink.

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

**Decided (2026-10-09): as recommended.** deploy-usawinssh owns SSH, and with
it the PowerShell 7 install (D18). This module calls it rather than carrying a
second OpenSSH setup.

## D22. Network devices (stretch)

Most network OSes have a static banner command: Cisco IOS and NX-OS have
`banner motd`, `banner login` and `banner exec`; PAN-OS has a login banner
setting [known]. A static banner is easy to push. Live stats (vPC state,
ports up and down, flaps in the last hour) are not something a banner can
compute on the device. They need either device-side scripting (EEM on
Cisco) or a collector that rewrites the banner every few minutes.
**Recommendation: later**, after the two OSes ship. Start with static
banners pushed by `Deploy-UsaBannerRemote`.

**Decided (2026-10-09): later**, as recommended.

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

**Decided (2026-10-09): as proposed.**

## D24. A LICENSE

**Decided: MIT**, with the same text as deploy-usawinssh ("Copyright (c)
2026 Tyson C Rasanen"). The LICENSE goes into !1, so the baseline lands with
it.

A correction: this entry first said deploy-usawinssh had no LICENSE either.
That was wrong. It has one on `main`; the check read a stale local checkout.

Without a licence, others may read the code but have no right to use or
change it. MIT's warranty disclaimer is also what gives D14's "not liable"
its footing, and it gives a logo contribution (D4) terms to be given under
[known].

## D25. Meme voices

Asked for in the M2 gallery (2026-10-21), for a lab VM: the banner in a meme
voice, as an engineering prank or a newcomer's first lab box. Three voices,
each drawn in the gallery and marked as right:

| Voice | WARNING becomes | The rules |
|---|---|---|
| `uwu` | `W-WAWNING!! OwO` | r and l to w, ny before a vowel; a stutter and a face on every sentence |
| `random` | `WARNING!!1!one` | the to teh, for to 4, to to 2, you to u; `XD`, `lolz`, `*holds up spork*` after every sentence |
| `leet` | `\/\/4RN1NG!!` | capitals, then A 4, E 3, I 1, O 0, S 5, T 7; a BBS sign-off at the end |

**Decided (2026-10-21):**

- **A voice rewrites the banner's own words, never its facts.** It changes
  the legal box and its text, the welcome line, the panel's labels, the
  tier's meaning and all clear. Names, addresses, numbers and the company
  stay as they are, so the banner still tells the truth.
- **The voices are rules, not word lists,** so text the admin writes gets
  them too. They give ASCII, and the same text the same way every time, so a
  voice can show before login and its frames can be golden.
- **It takes a deliberate setting:** `voice` in the configuration, `plain`
  unless set. A voice is allowed on any tier, PROD and PUB included. Turning
  one on is a manual change; a lab's PROD or PUB host may still be a friend's
  server, and someone turning a voice on in production has a bigger question
  to answer than the banner.
- **When a voiced top line is full,** the cap gives way first, then the hint
  shortens: the same rule as for any box.

## D26. The facts record

M3 gathers what the banner after login shows about its host (SPEC §5.4). Two
readers want it: Ubuntu's login renderer, in `sh` and `awk` (D2), and the
module, for `Show-UsaBanner`.

**Decided (2026-10-22):** one record for every reader. Each fact is a line,
its fields separated by tabs, its kind first:

| Kind | Fields after the kind |
|---|---|
| `name` | the host name, with its domain where the periodic job cached one |
| `ip` | the primary IPv4 address: the source of the route out |
| `os` | the OS and its kernel |
| `uptime` | as `12d 6h 40m` |
| `cpu` | now, min, max (percent), text |
| `memory` | percent in use, min, max, text, kind |
| `disk` | mount point, percent in use, min, max, text, kind |
| `updates` | the updates waiting, as text; a level, `good` or `warn` (D17) |
| `reboot` | a reboot pending or scheduled, as text; a level |
| `sessions` | how many, and whose |
| `time` | the local time |
| `ipv4` | an adapter, and its addresses |
| `services` | the services watched, as text; a level, `good` or `bad` (D10) |
| `problem` | a level, `warn` or `bad`; what is wrong, as text (D10) |
| `check` | the name of a check that ran, for the all-clear line |

- **Tabs and lines,** because `awk -F '\t'` reads them as they are, and a
  value with spaces (`6 of 121 GiB`, an OS name) stays one field. The
  collector turns a tab inside a value into a space and drops control
  characters, so no value can split its record or start another.
- **An empty field is a fact not known at login.** Min and max come from the
  24-hour samples (D17), and the kinds (`DDR4`, `SSD`) from the periodic
  job's cache. The banner leaves out what is empty, so there is no `24h`
  range until samples exist. A fact that cannot be read gets no record, and
  so no row.
- **A reader passes over a kind it does not know,** so an older module reads
  a newer collector.
- **On Linux the collector is `UsaBanner/linux/facts.sh`,** POSIX `sh`, for
  the login renderer and the module alike. It reads only what is fast and
  local (D17's first tier). Each command that could stall is cut off after
  2 seconds, and the domain comes from the periodic job's cache, because
  looking it up could wait on DNS. Its sources are today's banner's. What
  differs:
  - `getconf _NPROCESSORS_ONLN` counts the CPUs: `nproc` follows
    `OMP_NUM_THREADS`, which a user's shell may set (with
    `OMP_NUM_THREADS=1`, `nproc` gave 1 on a 16-CPU host [measured,
    2026-10-22]);
  - a record for every local filesystem but `/boot` and below, where
    today's panel shows `/` alone, read with `df -k` so `BLOCK_SIZE` cannot
    change the unit;
  - the adapters left out by default add tunnels and VPNs (`tun`, `tap`,
    `wg`, `tailscale`, `zt`) to today's container bridges, as SPEC §5.4
    asks;
  - the weekday in English, whatever the locale;
  - os-release is read as text, never run.
- **`cpu` on Linux is the 1-minute load as a share of the online CPUs**, the
  load D17 reads at login: a busy percentage needs two readings apart, a
  wait at every login. It can pass 100, when more work waits than there are
  CPUs to run it. Windows reads a busy percentage over 200 ms, as today.
- **On Windows the module reads the same facts itself**
  (`UsaBanner/Private/WindowsFacts.ps1`), from CIM, the registry and .NET,
  through today's probes, each chosen by timing a fresh process, as a login
  is. Where it differs from Linux, or from today's Windows banner:
  - `cpu` is the processors' busy percentage over a quiet 200 ms window,
    read after the other probes: across them an idle 4-core node read 24%,
    and a quiet window 3% [measured for today's banner, 2026-10-03];
  - the time carries its UTC offset (`-05:00`): .NET knows no zone
    abbreviations;
  - the name is the DNS host name in the case the host gives it, where
    today's banner lower-cases it; a domain stays in lower case;
  - every fixed drive gets a record, where today's panel shows the system
    drive alone; a CD drive gets none;
  - adapters are left out by type (loopback, tunnel, PPP), and by name only
    the NAT adapters of WSL, the Default Switch and containers. Today's
    banner leaves out every `vEthernet` adapter, and on a Hyper-V host that
    is where the host's own addresses are;
  - sessions count quser's lines and each user once, as Linux counts
    `who`'s; no session is `0`, where today's banner said `0  ()`. quser
    lists no SSH logon;
  - a reboot pending is its own row, naming why (`servicing`,
    `Windows Update`), where today's banner raised one problem for either;
    the CPU's speed, the memory's and drives' kinds and the updates come
    from the periodic job's `slow.tsv` (D17).

## Appendix A. Art mock-ups (rough)

Plain ASCII, so each works before login too. Final art gets drawn properly
in V1.

**The UsagiTools rabbit**, as the author redrew it (2026-10-09): pointed ears,
because it is a hare (nousagi), three eyes, and USAGITOOLS 2 down the side.

```text
   ^^       ^^    U
  /  \     /  \   S
 |    |   |    |  A
 |    |   |    |  G
  \   |   |   /   I
 .-\__/---\__/-.  T
/   oo (o) oo   \ O
| (o)       (o) | O
|      ,',      | L
|    \_/ \_/    | S
 '-.__________.-' 2
```

In colour (post-login, D7), the rabbit takes the UsagiTools palette. Right and
left are the rabbit's own, so its right eye is the one on your left:

| Part | Colour | 256-colour fallback | 16-colour fallback |
|---|---|---|---|
| right eye (on your left), and the `oo` on that side of centre | `#FF9900` | 208 (`#FF8700`) | yellow |
| centre eye | `#99FFFF` | 123 (`#87FFFF`) | bright cyan |
| left eye (on your right), and the `oo` on that side of centre | `#0099FF` | 33 (`#0087FF`) | bright blue |
| nose | `#FF99FF` | 213 (`#FF87FF`) | bright magenta |
| mouth | `#FFFFFF` | 231 (`#FFFFFF`) | bright white |
| fur outline | blonde, a gradient by row from `#FFF3C4` at the ear tips to `#E1B95C` at the chin | 230 (`#FFFFD7`) to 179 (`#D7AF5F`) | bright yellow |
| fur fill: a `:` in every cell inside the head and ears | a darker blonde, by row from `#C8A050` to `#8C6428` | 179 (`#D7AF5F`) to 94 (`#875F00`) | dark grey, so it stays apart from the yellow eye |

**Sheen** (the author's pick, 2026-10-10): each fur colour, outline and fill,
is multiplied by a factor that is 1.15 down the middle of each ear and of the
head, and 0.85 at their edges, so the hare looks rounded and lit.
- For a cell, the factor is 1.15 − 0.3 × d. Here d is the cell's distance
  from that middle, divided by 3.5 for an ear or by 8.5 for the head, and
  capped at 1.
- The ears are the top five rows, with their middles at columns 3.5 and 12.5
  (counting from 0). The head's middle is column 8.
- A channel the factor pushes past 255 stays at 255.
- In 256 colours each cell takes the nearest of the 256; the 16-colour
  fallback has no sheen.

The colours sit beside the art, not inside it. A mask of the same shape marks
each character:
- `f` for the fur outline, and `#` for the fur fill;
- `R`, `C` and `L` for the right, centre and left eyes;
- `n` for the nose, and `m` for the mouth;
- `t` for the side text.

So a colour scheme is data, as D12 stores it, and the art stays plain ASCII
for the pre-login banners.

In colour, a fill cell is a `:` in its row's darker blonde, so the fill reads
as background, and the eyes, nose and mouth stay the stars. Without colour,
and before login, it is a space, so the art is unchanged. The author chose
`:` on 2026-10-10 over `*`, the light shade `░` and a background colour,
which all made the fill heavier than the face:

```text
   ff       ff    t
  f##f     f##f   t
 f####f   f####f  t
 f####f   f####f  t
  f###f   f###f   t
 fffffffffffffff  t
f###RR#CCC#LL###f t
f#RRR#######LLL#f t
f######nnn######f t
f####mmm#mmm####f t
 ffffffffffffffff t
```

![The UsagiTools rabbit as a 24-bit terminal draws it](rabbit.svg)

**A server and a terminal** take the OS colour (Windows blue, Ubuntu orange:
D3, option B):

```text
A server                       A terminal

.------------------------.     .------------------------.
| [=====]  o o o   ..... |     | > usabanner_           |
|------------------------|     |                        |
| [=====]  o o o   ..... |     |                        |
|------------------------|     '------------------------'
| [=====]  o o o   ..... |            _____||_____
'------------------------'
```
