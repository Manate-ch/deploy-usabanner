# UsaBanner: specification

> Written up from the author's spec on 2026-10-09. The questions it raised are
> decided in [DECISIONS.md](DECISIONS.md), referred to here as **D*n***; where
> a decision says more than the text here, the decision wins. The examples use
> a made-up company (Contoso) and made-up services. The order of the work is
> in [V1-PLAN.md](V1-PLAN.md).

## 1. What this is

A set of cmdlets, written in PowerShell 7, that deploy a cross-platform banner
for three moments - pre-init, pre-logon and post-logon - as part of the
UsagiTools module. It gives systems admins and DevOps teams a functional and
stylish way to see useful information at logon, in COLOUR where possible
(it's 2026: Linux obsessives have already bounded past Windows gurus in style
points while we're all asking Microsoft to stop writing new O365 commands,
and sweet GODS someone needs to take the keyboard from whoever decided Graph
needs 60+ character cmdlets), while still showing relevant information before
logon.

## 2. Platforms

- **Ubuntu 24.04**: tested, and written so it should keep working on later
  releases.
- **Windows Server 2022 and later** (D15). The lab has checked both 2022 and
  2025 for SSH colour and `System.Drawing` (D15, D19). 2019 is out of scope.

## 3. Cmdlets

| Cmdlet | Purpose |
|---|---|
| `Deploy-UsaBanner` | the main entry point: an interactive walk-through, or flags |
| `Set-UsaBanner` | change an existing deployment |
| `Get-UsaBanner` | show what is deployed, and how |
| `Export-UsaBanner` | package the current setup for `Deploy-UsaBannerGPO` |
| `Deploy-UsaBannerGPO` | deploy a package domain-wide |
| `Get-UsaBannerService` | list the monitored services |
| `Set-UsaBannerService` | choose the monitored services |
| `New-UsaBannerArt` | turn an image into banner art |
| `Enter-UsaPSSession` | enter a PowerShell session that shows the banner |

### 3.1 Deploy-UsaBanner

**Interactive** (no flags, or only `-Company <name>`):

1. If a banner is already installed, ask whether to reconfigure it. Yes goes
   to `Set-UsaBanner`.
2. Walk the user through:
   1. **Company name**, for "Welcome to <company>".
   2. **SSH**: whether they have it, or want it set up.
   3. **Logo**: one of the built-in options (D3); "use my own", from a path,
      with a few basic colour and gradient choices; or "make my own", which
      runs `New-UsaBannerArt` and comes back with its output before going on
      (see §8 for a sentence that breaks off here).
   4. **Border style**, from lines and corners chosen so that nobody SSHing in
      from SecureCRT or the like sees baffling non-ASCII characters (D6).
      Ideas so far:
      - lines: one repeated character (`o`, `O`, `x`, `X`, `+`, `*`, or any
        other single character); `|` with `_`; `|` with alternating `-` and
        `_` (wavy); `■` blocks, or anything similar that renders the same in
        most common console fonts; other suggestions welcome;
      - corners: the same single characters, plain-ASCII emoticons that work
        in most terminals, other suggestions welcome.
   5. **Environment tier**: DEV-TEST, LAB, PROD or PUB.
   6. **Colours**: a few options, ours as the default, and "custom" to try
      one. A preview in the console, preferably; a small local HTML page only
      if the console cannot do it, because this has to work on a host you are
      SSHed into (D7).
   7. **VLANs**: User Devices, Printers, Servers, Management and IoT, each
      with an editable name, VLAN tag and IP/mask. The defaults are an example
      that encourages filling it in (`10.7.1.0/24` to `10.7.5.0/24`). Rows can
      be added, and a CSV or TSV file can be given instead.
   8. **Pre-init legal template**: one of five, scaling from "hey, this is a
      home PC, please don't hack me, buddy" to "ATTENTION: UNDER [the US
      statute on unauthorized access], ACCESS TO THIS SYSTEM WITHOUT
      AUTHORIZATION IS A CRIME PUNISHABLE BY LAW", or "write your own" (D8).
   9. **Monitored services**: the defaults, checked, with "search for
      services" and "add a service", by running `Set-UsaBannerService`
      (§3.6).
   10. **What the pre-init and pre-logon banners show**: the host name, the
       IP, or both. The thinking: anyone breaking in probably knew the system
       name long before a banner told them (D9).
3. Show a preview of each banner, switched with the arrow keys, ask for
   confirmation, and show the exact non-interactive command that would build
   this same setup.
4. Deploy: the banners, SSH configuration as needed, and so on.
5. Offer a small cron job or scheduled task that keeps the banner updated
   from a GitHub URL (the maintainer's GitLab for the first internal checks,
   GitHub once it is public), with a CLEAR warning: this is the maintainer's
   public repo, but it is still **a** public repo, and by turning this on you
   agree the maintainer holds no liability for issues it causes. Later this
   becomes "update UsagiTools on a similar cadence" (D14).

**Non-interactive** (any flag):

- Defaults to an ASCII-safe banner, with the middle option of each group.
- The art is OS-relevant: the Windows logo in blue on Windows, the Ubuntu logo
  in orange on Ubuntu, Tux on other Linux, and the like for any OS added
  later (D3).
- (§8: the list ended in an empty bullet here.)

### 3.2 Set-UsaBanner

- **Interactive** (no flags): the whole `Deploy-UsaBanner` walk-through after
  the reconfigure question, prefilled with the current settings. Fails when no
  deployment is found.
- **Non-interactive** (any flag): changes each value `Deploy-UsaBanner` sets,
  except the services, and only the values given. `-BannerImage Minecraft`
  changes only the image, to a prebuilt ASCII Minecraft dirt block;
  `-Company 'Contoso LLC' -BannerImage MSSQL` changes every company reference
  to Contoso LLC and the logo to a grey and red ASCII SQL logo (D3).

### 3.3 Get-UsaBanner

Shows:

- the current pre-init, pre-logon and post-logon banners, with a flag to pick
  one;
- whether SSH is open for use;
- whether the banners are installed properly;
- the settings chosen for this install;
- the colour-to-VLAN mappings;
- the monitored services.

### 3.4 Export-UsaBanner

Takes `Get-UsaBanner`'s output and builds a package for
`Deploy-UsaBannerGPO`: one JSON file (D12).

### 3.5 Get-UsaBannerService

Lists the monitored services. Given a service name, returns `$true` or
`$false`.

### 3.6 Set-UsaBannerService

- **Without flags**: an interactive picker. Appendix A walks through it frame
  by frame. It shows the depth wanted for every interactive mode: these should
  work like PowerShell-driven TOOLS more than like ordinary prompts.
- **`-Add <name>`** adds a service and checks that it is visible; an error if
  it is not, unless `-Force` is given too. **`-Remove <name>`** likewise.
  Other ideas welcome.

### 3.7 Deploy-UsaBannerGPO

- Much as today: offers to deploy a GPO when run against a domain controller.
- The one real difference: it REQUIRES an `Export-UsaBanner` package as its
  seed.
- The package overwrites the existing config, so one base config can run
  company-wide. An OU that should differ gets its own package, matched
  through the one GPO's table of OUs. Enforced stays a manual tool, and an OU
  that blocks inheritance gets a direct link (D13).
- Does NOT enable SSH on its own, and DOES require `deploy-usawinssh` to be
  active in the domain (D21).

### 3.8 Enter-UsaPSSession

The proper cmdlet for entering a session with the banner's formatting
(today's `Enter-ManatechPSSession`).

### 3.9 New-UsaBannerArt

Turns an image into banner art; named in the walk-through, §3.1 step 2.3
(D19).

## 4. Rules for every banner

- **R1** Every banner displays properly in the native tools, as far as
  possible. Failing that, it has a safe fallback. Odd broken characters that
  run off the screen at a normal size count as it breaking: they panic users.
- **R2** Load FAST and let the user in, while being as INFORMATIVE as
  possible.
- **R3** Install PowerShell 7 if it is missing: interactively when run
  interactively, automatically otherwise (D18).

## 5. What the banners show

### 5.1 All banners

1. An ASCII banner image, before ANYTHING else on this list: an image the
   user provided, converted to text, or ASCII art the user provided directly.

### 5.2 Pre-init

1. The company name.
2. The big scary legal warning the user chose.

### 5.3 Pre-logon

1. The company name.
2. The server name, if the company opted for it.
3. The domain the server is joined to, if any.
4. The big scary legal box.

### 5.4 On logon

1. The server name and the domain it is in.
2. A tier banner, DEV-TEST / LAB / PROD / PUB, in a colour each: it separates
   sandbox and development boxes from larger-scale testing, from production,
   and from public-facing devices.
3. The host name decoded with the naming standard (the author is fine with
   publishing it):
   1. characters 1-2: the site name;
   2. character 3: (P)hysical, (V)irtual, an (A)zure server, an Ama(z)on AWS
      one, a shared VPS at a (C)loud provider, a (D)edicated server at a cloud
      provider, or a device dedicated to temporary dev-test (L)ab work;
   3. character 4: an (A)ppliance black box, a (B)ackup server or device, a
      (F)irewall, a (H)andheld device such as a Steam Deck, a (L)aptop, a
      (N)AS, a dedicated (P)roxy, a (R)outer, a (S)erver OS device, a
      (V)oice-enabled smartphone, a dedicated S(Q)L or other database, a
      network switch (X: it cross-connects; nothing cleverer came up), a
      (W)ireless access point, a (2)D printer, a (3)D printer. Most of these
      will not run the banner soon, but the table should have them;
   4. character 5, the OS: (A)ndroid, (C)ontainer-based, (F)ortiOS, Apple or
      Cisco (I)OS (funny, and the X/V split makes it obvious), (K)ubernetes
      node, (L)inux flavour, (M)acOS, (U)nifi OS, (W)indows, e(X)tra/misc.
4. The VLAN the device is on.
5. The running OS.
6. The device's role, from AD or set by hand.
7. Uptime.
8. CPU load over time, plus model and core count where possible.
9. RAM use, min/max, and speed where possible.
10. Each disk: use, min/max, mount point and type (HDD, SSD, NVMe,
    removable), where possible.
11. The number of logged-on sessions.
12. The local system time at logon.
13. Each network adapter's IP and subnet mask, filterable in the config; by
    default VPN and loopback interfaces are left out.
14. Whether system updates are pending.
15. Whether a reboot is pending, and for what.
16. Whether a reboot is scheduled.
17. Any critical service that is not running; possibly any non-standard
    automatic service that is not running, though doing that without a TON of
    edge cases is unclear.

## 6. OS-specific requirements

### 6.1 Windows

- A manual install sets up Windows SSH with PowerShell settings.
- An interactive install, when it sets up sessions, asks whether to add a
  public key, and enables public keys in the config if so.

### 6.2 Ubuntu

- Should not get in the way of updates, if at all possible. Today an
  `apt update && apt upgrade` asks to replace banner files, and that has to be
  declined each time: a mild annoyance, but worth avoiding (D16).
- Cleans up the stock MOTD packages that are more advert than use.
- Shows the full logon banner on TTY sessions.

## 7. Stretch goals

`Deploy-UsaBannerRemote`: push to an existing SSH or `Enter-PSSession`
endpoint, detect Linux or Windows, and for anything else install the
equivalent - Cisco Nexus or Catalyst switches, Palo Alto, OPNsense and so on -
until this MOTDs basically anything it can. The stats differ per device: on a
Cisco core switch, vPC state, ports up versus down, flaps in the last hour.
Later, unless it turns out INCREDIBLY easy (D22).

## 8. Gaps in the original text

- §3.1 step 2.3: a sentence breaks off: "...what you made with a warning it
  doesn't work in all consoles if we can't figure out a fall". Read here as:
  `New-UsaBannerArt` returns the art it made, with a warning when it will not
  render in every console and no fallback was found.
- §3.1, non-interactive: the list ends in an empty bullet.
- The two open questions it left are decided: the min/max window (D17) and
  whether Enforced is needed for an OU to differ (D13).

## Appendix A. Set-UsaBannerService, frame by frame

How to read it: each frame gives the time since the menu opened and what the
user did, then the screen. `<=x=>` / `<= =>` is the row under the cursor
(highlighted in the real UI), `<x>` a checked row, `< >` an unchecked one, and
`=Name=` a highlighted button.

**T+0 s.** The menu opens.

```text
--------------
|UsagiTools Banner Setup
|> Please select services for the banner to monitor. Note: a service name that CANNOT be monitored WILL slow down logon.
      Service Name       Display Name                     Status
      ------------       ------------                     ------
<=x=> Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
< >   Add your own: _
<Search for Services>
<Done>
[Spacebar=Select Item, Up/Down arrows to scroll]
```

**T+5 s.** Space: Netlogon is unchecked.

```text
<= => Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
< >   Add your own: _
<Search for Services>
<Done>
[Spacebar=Select Item, Up/Down arrows to scroll]
```

**T+7 s.** Down.

```text
< >   Netlogon           Netlogon                         Running
<=x=> w32time            Windows Time                     Running
< >   Add your own: _
<Search for Services>
<Done>
[Spacebar=Select Item, Up/Down arrows to scroll]
```

**T+8 s.** Down: the cursor is on the input row, and the key hint changes.

```text
< >   Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
<= => Add your own: _
<Search for Services>
<Done>
[Enter=Add Service, Up/Down arrows to scroll]
```

**T+10 s.** The user types a service name, here an RMM agent's.

```text
<= => Add your own: RmmAgent_
[Enter=Add Service, Up/Down arrows to scroll]
```

**T+12 s.** Enter: the new row is checked, and checking starts.

```text
< >   Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
<=x=> RmmAgent           checking...                      checking...
< >   Add your own: _
<Search for Services>
<Done>
[Spacebar=Select Item, Enter=Add Service, Up/Down arrows to scroll]
```

**T+15 s.** No input; the check resolves within 3 seconds.

```text
<=x=> RmmAgent           RMM Agent                        Running
```

**T+17 s.** Down, then the user types a name that does not exist.

```text
<x>   RmmAgent           RMM Agent                        Running
<= => Add your own: 11AmazingThings_
[Enter=Add Service, Up/Down arrows to scroll]
```

**T+20 s.** Enter: checking.

```text
<=x=> 11AmazingThings    checking...                      checking...
< >   Add your own: _
[Spacebar=Select Item, Up/Down arrows to scroll]
```

**T+22 s.** No input; the service is not found.

```text
<=x=> 11AmazingThings    NOTFOUND                         NOTFOUND
```

**T+25 s / T+27 s.** Down twice: the cursor reaches the search button.

```text
< >   Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
<x>   RmmAgent           RMM Agent                        Running
<x>   11AmazingThings    NOTFOUND                         NOTFOUND
< >   Add your own: _
<=Search for Services=>
<Done>
[Enter=Search for Service, Up/Down arrows to scroll]
```

**T+29 s.** Enter: the service list opens, sorted by name, ten rows at a
time; long names are cut with `...`.

```text
--------------
|UsagiTools Banner Setup
|> Please select services for the banner to monitor.
|> SERVICE SELECTION MENU
      Service Name       Display Name                     Status
      ------------       ------------                     ------
<= => 11AmazonThings     Amazon Tool Things               Running
< >   AarSvc_7fe7ef      Agent Activation Runtime_7fe7ef  Stopped
< >   ADPSvc             Aggregated Data Platform Serv... Stopped
< >   ALG                Application Layer Gateway Ser... Stopped
< >   AMD Crash Defen... AMD Crash Defender Service       Running
< >   AMD External Ev... AMD External Events Utility      Running
< >   amd3dvcacheSvc     AMD 3D V-Cache Performance Se... Stopped
< >   AmdAppCompatSvc    AMD Application Compatibility... Stopped
< >   AmdPpkgSvc         AMD Provisioning Packages Ser... Running
< >   AppIDSvc           Application Identity             Stopped
vScrollv
[Spacebar=Select Item, Esc=Back and add, Up/Down arrows to scroll]
```

**T+30 s.** Space: 11AmazonThings is checked.

```text
<=x=> 11AmazonThings     Amazon Tool Things               Running
```

**T+32 s.** Down five times; the window scrolls to keep the cursor in view.

```text
^Scroll^
< >   ADPSvc             Aggregated Data Platform Serv... Stopped
< >   ALG                Application Layer Gateway Ser... Stopped
< >   AMD Crash Defen... AMD Crash Defender Service       Running
<= => AMD External Ev... AMD External Events Utility      Running
< >   amd3dvcacheSvc     AMD 3D V-Cache Performance Se... Stopped
< >   AmdAppCompatSvc    AMD Application Compatibility... Stopped
< >   AmdPpkgSvc         AMD Provisioning Packages Ser... Running
< >   AppIDSvc           Application Identity             Stopped
< >   Appinfo            Application Information          Running
vScrollv
[Spacebar=Select Item, Esc=Back and add, Up/Down arrows to scroll]
```

**T+35 s.** Space: checked.

```text
<=x=> AMD External Ev... AMD External Events Utility      Running
```

**T+38 s.** Esc: back to the first menu, with both picks added.

```text
--------------
|UsagiTools Banner Setup
|> Please select services for the banner to monitor. Note: a service name that CANNOT be monitored WILL slow down logon.
      Service Name       Display Name                     Status
      ------------       ------------                     ------
< >   Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
<x>   RmmAgent           RMM Agent                        Running
<x>   11AmazingThings    NOTFOUND                         NOTFOUND
<x>   11AmazonThings     Amazon Tool Things               Running
<x>   AMD External Ev... AMD External Events Utility      Running
< >   Add your own: _
<=Search for Services=>
<Done>
[Enter=Search for Service, Up/Down arrows to scroll]
```

**T+40 s.** Up four times, then Space: the not-found service is unchecked.

```text
<= => 11AmazingThings    NOTFOUND                         NOTFOUND
[Spacebar=Select Item, Up/Down arrows to scroll]
```

**T+43 s.** Down five times, to Done.

```text
< >   Add your own: _
<Search for Services>
<=Done=>
[Enter=Finish Selection, Up/Down arrows to scroll]
```

**T+46 s.** Enter: a confirmation lists only the checked services, with the
cursor on Back.

```text
--------------
|UsagiTools Banner Setup
|> Please select services for the banner to monitor. Note: a service name that CANNOT be monitored WILL slow down logon.
      Service Name       Display Name                     Status
      ------------       ------------                     ------
<x>   w32time            Windows Time                     Running
<x>   RmmAgent           RMM Agent                        Running
<x>   11AmazonThings     Amazon Tool Things               Running
<x>   AMD External Ev... AMD External Events Utility      Running
|>DO YOU WISH TO SAVE THE FOLLOWING SERVICES TO BANNER MONITOR
<=Back=> <Done>
[Enter=Back, Left/Right arrows to scroll]
```

**T+47 s.** Enter on the default, Back, returns to the menu (so nobody
commits too soon). An Enter on Done (not shown) reopens the confirmation.

**T+49 s.** Right: Done is highlighted.

```text
|>DO YOU WISH TO SAVE THE FOLLOWING SERVICES TO BANNER MONITOR
<Back> <=Done=>
[Enter=Commit Changes and Save, Left/Right arrows to scroll]
```

**T+50 s.** Enter: saved. One second later the walk-through moves on.

```text
--------------
|UsagiTools Banner Setup
|> THE BELOW WILL BE CHECKED ON LOGON
      Service Name       Display Name                     Status
      ------------       ------------                     ------
<x>   w32time            Windows Time                     Running
<x>   RmmAgent           RMM Agent                        Running
<x>   11AmazonThings     Amazon Tool Things               Running
<x>   AMD External Ev... AMD External Events Utility      Running
|>THE ABOVE WILL BE CHECKED ON LOGON
```
