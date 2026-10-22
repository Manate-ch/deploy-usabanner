# Facts fixture: Ubuntu 24.04.5

What `UsaBanner/linux/facts.sh` reads on an Ubuntu 24.04.5 server, for
`tests/Facts.Tests.ps1`. Recorded on 2026-10-22 at 02:18 UTC from a lab
virtual machine with 2 CPUs and 4 GiB of memory, each command run on its own
over SSH.

| File | Recorded with | Changed |
|---|---|---|
| `root/etc/os-release` | `cat /etc/os-release` | nothing |
| `root/proc/uptime`, `loadavg`, `meminfo` | `cat` | nothing |
| `commands/uname-r.txt` | `uname -r` | nothing |
| `commands/getconf.txt` | `getconf _NPROCESSORS_ONLN` | nothing |
| `commands/ip-route-get.txt` | `ip -4 route get 1.1.1.1` | the addresses, to the repository's example network |
| `commands/ip-addr.txt` | `ip -br -4 addr show scope global` | the address, as above; a `docker0` line added, for the adapters left out |
| `commands/df.txt` | `df -P -k -l -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs` | a `/var` line added, for the order and for sizes in whole GiB |
| `commands/who.txt` | written in `who`'s format | the recording had no sessions: a command run over SSH logs none |

iproute2 printed the route's first line with a space at its end; no line
here ends in one. The host name and the time come from the test's stubs, not
from the recording.
