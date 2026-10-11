# Service picker prototype

A runnable example of the "built in" option of D11 (docs/DECISIONS.md, MR !2):
the interactive picker of the planned `Set-UsaBannerService`, in plain
PowerShell 7 with no other module. It is the walk-through in docs/SPEC.md,
Appendix A, working.

It changes nothing on the machine. Where the real cmdlet would save the list,
this prints it and returns the names.

## Run it

```powershell
pwsh ./prototype/Select-UsaBannerService.ps1 -Demo   # the walk-through's made-up services
pwsh ./prototype/Select-UsaBannerService.ps1         # this machine's services, read only
```

It needs PowerShell 7.2 or later and an interactive terminal: Windows
Terminal, a console over SSH, or any Linux terminal. With its input or output
redirected, it refuses to start instead of waiting for keys that never come.
It reads services with `Get-Service` on Windows, and with `systemctl` on Linux.

## Keys

| Key | First screen | Service list | Confirmation |
|---|---|---|---|
| Up, Down | move | move | |
| PageUp, PageDown, Home, End | | move by ten, or to either end | |
| Space | check or uncheck a service | check or uncheck | |
| Typing | the "Add your own" row | filters by name or display name | |
| Backspace | edits the "Add your own" row | edits the filter | |
| Enter | adds the typed service, opens the list, or finishes | | Back or Done |
| Left, Right | | | choose Back or Done |
| Esc | cancels: nothing is saved | back to the first screen, with the picks | back to the first screen |
| Ctrl+C | cancels | cancels | cancels |

## Where it differs from the walk-through

The tests check every frame of the walk-through. These differences are on
purpose, and the test for each frame they touch says so:

1. **A service that is not found starts unchecked** (D10), so a typo is never
   saved by accident. Space checks it anyway, as `-Force` keeps one for
   `-Add`. A service that was monitored before the picker opened stays checked
   even when it is missing, so opening the picker and saving changes nothing
   you did not touch.
2. **No slow-logon note** in the title. D10 adds it only once a lab
   measurement shows the slowdown.
3. **The checking frame** shows the row's own hint, as at T+20 (T+12 also
   listed Enter=Add Service).
4. **The list scrolls only when the cursor would leave its ten rows**, one row
   at a time. After five Downs (T+32) it has not scrolled yet.
5. **ADPSvc's display name** is exactly the column's 32 characters, so it fits
   and is not cut (T+29 cut it).
6. **Esc and Ctrl+C**, which the walk-through left open: Esc on the first
   screen cancels, Esc in the confirmation goes back, and Ctrl+C cancels from
   anywhere.

Added beyond the walk-through:
- **Typing in the list filters it**, since Windows lists well over a hundred
  services. A `|> Filter: win_` line shows while a filter is set.
- **PageUp, PageDown, Home and End** in the list.
- **No service is listed twice.** Typing a listed name checks that row. On
  Windows a display name finds the service too, as `Get-Service` does
  ("Windows Time" finds w32time).

## How it is built

- `UsaBannerPicker.psm1`, about 600 lines with comments, is a small state
  machine. Keys come in through one scriptblock and frames go out through
  another. Nothing in it touches the console. Each frame is plain text, twice:
  - in the walk-through's notation, where `<=x=>` marks the row under the
    cursor and `<=Done=>` a selected button. The tests compare this;
  - as the screen shows it: the `=` are notation only, so on screen there are
    none. The row under the cursor is highlighted whole, and a button on its
    own.
- `Select-UsaBannerService.ps1` draws the frames: on the alternate screen,
  the highlight in reverse video, each frame over the last one in place.
  While it runs it reads Ctrl+C as a key, because PowerShell cannot stop a
  script that is waiting in `ReadKey`, and it restores the screen and the
  terminal on the way out.
- `tests/Picker.Tests.ps1` plays the walk-through with scripted keys and
  compares each frame with the spec's. Whole frames must match exactly; the
  spec's partial frames must show their lines, in order.

```powershell
Invoke-Pester ./prototype/tests
```

## What it shows for D11

- **No dependency**, and the same code on Windows and Linux.
- **Testable without a terminal**: the whole walk-through runs in the tests in
  about a second.
- **Fit for SSH**: it needs only VT escape sequences and `ReadKey`.

What the real cmdlet still needs: saving to the config (D12), a time limit on
a slow lookup, and a redraw when the terminal is resized.
