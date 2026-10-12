# UsaBanner V1: the plan

> What V1 does is in [SPEC.md](SPEC.md), and why each choice was made is in
> [DECISIONS.md](DECISIONS.md), referred to here as **D*n***. This file is the
> order of the work: seven milestones, each one or a few merge requests, and
> what "done" means for each.

## Where V1 is built

- **In this repository**, beside today's code, until V1 replaces it (D1).
  Then the project is renamed `deploy-usabanner`, and GitLab keeps a redirect
  from the old path.
- **`UsaBanner/` is the module:** the folder `Import-Module` loads, and the
  one an install copies whole. Its tests are in `tests/`.
- **Today's code stays the production path until M7.** `install.sh`,
  `rootfs/`, `windows/` and `adsys-startup.sh` keep getting their fixes, such
  as the apt-prompt fix (D16). V1 installs side by side under its own names
  (D23) and never adopts the old Group Policy object; `Deploy-UsaBanner`
  offers to remove an old install when it finds one.

## How every merge request is checked

- The full suite, each test file in its own process, with no skips.
- The files Windows PowerShell 5.1 loads pass `PSUseCompatibleSyntax` for 5.1
  (D18).
- Anything that runs on a host runs on lab hosts first: Ubuntu 24.04, and
  Windows Server 2022 and 2025 (D15).
- Output shown before login is ASCII 32-126 (D6), and a test says so.

## M0. Foundation

- **The module skeleton:** a manifest, and a loader that Windows PowerShell
  5.1 can read (D18). Under 5.1, each command hands itself to `pwsh` with the
  same parameters. The PowerShell 7 code lives in files that are loaded only
  under PowerShell 7.
- **The configuration:** one JSON file with a schema (D12), its defaults, and
  reading, checking and writing it.
- **The UsagiTools rabbit as data** (Appendix A): the art, its colour mask,
  the palette and the sheen.
- **One renderer** for truecolor, 256 colours, 16 colours and none (D7), and
  the choice of mode: the terminal's signals, then the host's mode, then the
  user's `USABANNER_COLOR`.
- **`Show-UsaBannerArt`**, the first command.

**Done when:** the rabbit draws in every mode exactly as Appendix A and
`docs/rabbit.svg` show it; a configuration round-trips byte for byte; and on
lab hosts, the module imports in Windows PowerShell 5.1 and hands off to
`pwsh`.

Not in M0: installing PowerShell 7 where it is missing. M0's hand-off stops
and says what to install; M6 installs it.

## M1. The art library

- **`art/base`:** the server and terminal pictograms in the OS colour (D3,
  option B, the shipped default), the shield, cloud and globe, and a
  block-letter font for the company name.
- **`art/apps`:** Tux with Larry Ewing's credit, and Windows and Ubuntu drawn
  by us. Each names its owner in its metadata and has a line in NOTICE, and
  the README carries the trademark notice (D3).
- **`New-UsaBannerArt`:** an image to art. Windows' own decoder on Windows;
  PNG on Linux, and ImageMagick for other formats there (D19).
- **The logo how-to in AGENTS.md:** from here on, a logo comes as a merge
  request (D4).

**Done when:** every piece of art passes the rabbit's checks (ASCII, the mask
the same shape as the art, a round trip through the JSON), and
`Show-UsaBannerArt` lists and draws each one.

## M2. The banners, composed

- **The three moments** (D5): pre-init (the console), pre-logon (SSH, and the
  Windows logon notice) and post-logon.
- **Borders and corners** (D6): the ASCII sets everywhere, and the Unicode
  sets after login, with the ASCII set as the fallback.
- **The legal templates** L1 to L5, and "write your own", wrapped to the box
  (D8).
- **The host name and IP before login**, each opt-in (D9).
- **The environment tier strip, the naming standard (D20) and the VLAN
  badge**, and the colour presets (D7).
- **`Show-UsaBanner`:** any moment, from a configuration, with made-up facts
  in the tests.

**Done when:** golden-frame tests cover each moment in each colour mode and
border set, and every pre-login frame is ASCII only.

## M3. Facts

- **§5.4's facts on both OSes:** uptime, CPU, memory, disks, sessions,
  addresses, pending updates, reboots pending and scheduled, and services
  (D10).
- **Minimum and maximum over the last 24 hours**, sampled every 15 minutes
  (D17).
- Today's collectors are the starting point: the Ubuntu ones in `rootfs/`,
  the Windows ones in `windows/`.

**Done when:** each fact has a test on recorded input, the lab hosts show
real values, and the login time is measured before and after (R2).

## M4. Deploy, non-interactive

- **`Deploy-UsaBanner` with flags** compiles the configuration into what each
  login renderer reads fastest (D2): `KEY=value` and TSV files for `sh` and
  `awk` on Ubuntu, a `.psd1` for the Windows module.
- **The login renderers under the new names** (D23), conffile-safe on Ubuntu
  (D16).
- **The update timer or task** (D14), and the Ubuntu `sh` bootstrap that
  installs PowerShell from Microsoft's repository, not the snap (D18).
- **`Get-UsaBanner`** (§3.3).

**Done when:** a fresh Ubuntu 24.04, and fresh Windows Server 2022 and 2025
hosts, install from flags alone; `apt upgrade` asks nothing afterwards; and
removing it leaves the host stock.

## M5. Interactive

- **The `Deploy-UsaBanner` walk-through** (§3.1) and `Set-UsaBanner` (§3.2).
- **`Get-` and `Set-UsaBannerService`**, built from the picker in
  `prototype/` (D11).
- **The colour check:** a 24-bit and a 256-colour gradient bar, and "do these
  look smooth?" (D7).
- Every interactive command checks that it has a console, and prints the
  flags to use when it does not (D11).

**Done when:** scripted-key tests play each walk-through frame by frame, as
`prototype/tests` does, and each walk-through ends by printing the
non-interactive command that builds the same setup.

## M6. Windows plumbing and Group Policy

- **PowerShell 7 installed where it is missing** (D18): interactively, the
  newest MSI, checked against the release's `hashes.sha256` and its
  signature; by policy, the MSI deploy-usawinssh stages (D21).
- **`Enter-UsaPSSession`** (§3.8).
- **`Export-UsaBanner`:** the one-file JSON package (D12).
- **`Deploy-UsaBannerGPO`:** one base policy and an OU table, a direct link
  for an OU that blocks inheritance (D13), and `-UpdatePoSHMSI`.

**Done when:** in the lab domain, a base package and an OU's own package both
reach their hosts, including through Block Inheritance.

## M7. Release

- **`Deploy-UsaBanner` moves a host off today's install** (D23).
- **The README is rewritten for V1**, and today's code retired.
- **The project is renamed `deploy-usabanner`** (D1), and `v1.0.0` is
  released once it has been validated on the Manatech hosts.

## Later

- `Deploy-UsaBannerRemote` and network devices (D22).
- UsagiTools 2.0 takes the module in (D1).
