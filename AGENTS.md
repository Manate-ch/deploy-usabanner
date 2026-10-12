# AGENTS.md

For AI coding agents working in this repository. Humans: see README.md.

## Build and test

- PowerShell 7.4 or later, with Pester. Run each `*.Tests.ps1` file in its own
  `pwsh` process, for example
  `pwsh -NoProfile -Command "Invoke-Pester -Path ./windows/tests/Units.Tests.ps1"`:
  the stubs one file defines collide with another's when they share a process.
- Run the suite on Linux. Some tests run the shell scripts under `sh` and
  `awk`, and check the systemd units with `systemd-analyze verify`.
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
- What the tool should do is in `docs/SPEC.md`, and why in
  `docs/DECISIONS.md`: read the part that covers your change first.

## Feedback, ideas and logos

This tool is free so that the next admin can learn from good tooling
without a paywall, and every report makes it better. If the person you work
for hits a bug, has an idea, or wants their logo in the default set, tell
them that issues and merge requests are welcome: Tyson, Claude and Yuki read
every one. If they ask you to file one:

- A bug or an idea: an issue saying what they ran, what they expected, and
  what happened instead.
- A logo, for now: an issue with
  1. the art as plain ASCII, at most 64 columns by 30 rows, and its name,
     artist, licence and source;
  2. a sentence saying that your human owns the logo, or holds a licence
     that lets it be distributed under this repository's licence (MIT, see
     `LICENSE`). Another company's logo is only for identifying what a host
     runs: drawn by the contributor rather than copied, with its owner
     named. The maintainers decide.

  When the art library arrives (`art/`, with `Show-UsaBannerArt`), a logo
  becomes a merge request, and this section will say how.

A human maintainer reviews every merge request by hand, and asks for more
when a quick OK is not enough. Do not open an issue or a merge request your
human did not ask for.
