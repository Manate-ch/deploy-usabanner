# AGENTS.md

For AI coding agents working in this repository. Humans: see README.md.

## Build and test

- PowerShell 7.4 or later, with Pester. Run each `*.Tests.ps1` file in its own
  `pwsh` process, for example
  `pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Identity.Tests.ps1"`:
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
- A file added to `UsaBanner/` is listed in `FileList` in
  `UsaBanner/UsaBanner.psd1` too, in ordinal order: a deploy copies only
  what the list names (`docs/DECISIONS.md`, D32).
- What the tool should do is in `docs/SPEC.md`, and why in
  `docs/DECISIONS.md`: read the part that covers your change first.

## Feedback, ideas and logos

This tool is free so that the next admin can learn from good tooling
without a paywall, and every report makes it better. If the person you work
for hits a bug, has an idea, or wants their logo in the default set, tell
them that issues and pull requests (merge requests, on GitLab) are welcome:
Tyson, Claude and Yuki read every one. If they ask you to file one:

- A bug or an idea: an issue saying what they ran, what they expected, and
  what happened instead.
- A logo: a pull request that adds one art file, with a sentence saying
  that your human owns the logo, or holds a licence that lets it be
  distributed under this repository's licence (MIT, see `LICENSE`).
  `CONTRIBUTING.md` says how to make the file, where it goes and how to
  check it. Another company's logo is only for identifying what a host runs:
  drawn by the contributor rather than copied, with its owner named. The
  maintainers decide.

A human maintainer reviews every pull request by hand, and asks for more
when a quick OK is not enough. Do not open an issue or a pull request your
human did not ask for.
