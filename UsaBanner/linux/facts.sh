#!/bin/sh
# facts.sh - this host's facts for its banners, as records on standard
# output: one fact a line, its fields separated by tabs, its kind first
# (docs/DECISIONS.md, D26). Ubuntu's login renderer reads them with awk (D2);
# the PowerShell module reads them for Show-UsaBanner.
#
#   +----------+--------------------------------------------------------+
#   | Kind     | Fields after the kind                                  |
#   +----------+--------------------------------------------------------+
#   | name     | the host name, with its domain where one is cached     |
#   | ip       | the primary IPv4 address                               |
#   | os       | the OS and its kernel                                  |
#   | uptime   | how long the host has been up, as 12d 6h 40m           |
#   | cpu      | now, min, max (percent), text                          |
#   | memory   | percent in use, min, max, text, kind                   |
#   | disk     | mount point, percent in use, min, max, text, kind      |
#   | sessions | how many, and whose                                    |
#   | time     | the local time                                         |
#   | ipv4     | an adapter, and its addresses                          |
#   +----------+--------------------------------------------------------+
#
# A field this script cannot know at login is empty: min and max come from
# the 24-hour samples (D17), the memory's and disks' kinds from the periodic
# job's cache. cpu is the 1-minute load as a share of the online CPUs, so it
# can pass 100. A fact it cannot read gets no record. Nothing here waits on
# the network, and each command that could stall is time-boxed: pam_motd
# runs the renderer at every login.
#
# USABANNER_ROOT (tests only) prefixes each file it reads.
# USABANNER_IFACE_HIDE replaces the adapters it leaves out: an ERE, matched
# against the adapter's name; empty leaves none out.

root=${USABANNER_ROOT:-}
hide=${USABANNER_IFACE_HIDE-'^(docker|br-|veth|virbr|lxcbr|cni|flannel|tun|tap|wg|tailscale|zt)'}
tab=$(printf '\t')

# out KIND FIELD... - one record. A field loses its tabs and control
# characters, so it can never split the record or end its line; only a field
# holding one starts tr, so a login pays for none.
out() {
	_line=$1
	shift
	for _f in "$@"; do
		case $_f in
		*[[:cntrl:]]*) _f=$(printf '%s' "$_f" | tr '\t' ' ' | tr -d '\000-\037\177') ;;
		esac
		_line="$_line$tab$_f"
	done
	printf '%s\n' "$_line"
}

# The name: the FQDN the periodic job caches, else the kernel's. Looking the
# FQDN up here could wait on DNS.
host=
if [ -r "$root/var/lib/usabanner/fqdn" ]; then
	IFS= read -r host <"$root/var/lib/usabanner/fqdn" || true
fi
[ -n "$host" ] || host=$(hostname 2>/dev/null)
out name "$host"

# The primary address: the source of the route out (route get asks the kernel;
# nothing is sent), else the first global address.
ip=$(timeout 2 ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }')
[ -n "$ip" ] || ip=$(timeout 2 ip -br -4 addr show scope global 2>/dev/null | awk 'NR == 1 { sub(/\/.*/, "", $3); print $3 }')
[ -n "$ip" ] && out ip "$ip"

# The OS, read from os-release as text: the file is never run. Its value may
# be in double or single quotes (os-release(5)).
q="'"
os=
for f in "$root/etc/os-release" "$root/usr/lib/os-release"; do
	[ -r "$f" ] || continue
	os=$(sed -n "/^PRETTY_NAME=/{s///;s/^\"\(.*\)\"\$/\1/;s/^$q\(.*\)$q\$/\1/;p;q;}" "$f")
	break
done
kernel=$(uname -r 2>/dev/null)
out os "${os:-Linux}${kernel:+, kernel $kernel}"

# Whole seconds only: a malformed file must not reach $((...)), where dash
# stops the script.
up=
[ -r "$root/proc/uptime" ] && read -r up _ <"$root/proc/uptime"
up=${up%%.*}
case $up in
'' | *[!0-9]*) ;;
*)
	ut="$((up % 86400 / 3600))h $((up % 3600 / 60))m"
	[ "$up" -ge 86400 ] && ut="$((up / 86400))d $ut"
	out uptime "$ut"
	;;
esac

# The online CPUs: nproc would follow OMP_NUM_THREADS from a user's shell.
cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
case $cores in '' | *[!0-9]* | 0) cores= ;; esac
if [ -n "$cores" ] && [ -r "$root/proc/loadavg" ]; then
	read -r load _ <"$root/proc/loadavg"
	now=$(awk -v l="$load" -v c="$cores" 'BEGIN { printf "%d", l * 100 / c + 0.5 }')
	unit=cores
	[ "$cores" -eq 1 ] && unit=core
	out cpu "$now" '' '' "$cores $unit"
fi

# Memory in use: MemTotal less MemAvailable, as free(1) counts it, the
# percentage cut as today's banner cuts it.
if [ -r "$root/proc/meminfo" ]; then
	set -- $(awk 'BEGIN { a = -1 } /^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 }
		END { if (t > 0 && a >= 0) printf "%d %.1f %.1f", (t - a) * 100 / t, (t - a) / 1048576, t / 1048576 }' "$root/proc/meminfo")
	[ $# -eq 3 ] && out memory "$1" '' '' "$2 of $3 GiB" ''
fi

# Local filesystems only (-l), so an unreachable NFS server cannot hang df,
# in KiB (-k) whatever BLOCK_SIZE says; /boot and below are left out. / first,
# then by mount point, which may hold spaces.
timeout 2 df -P -k -l -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | awk -v tab="$tab" '
	NR == 1 { next }
	{
		m = $6
		for (i = 7; i <= NF; i++) m = m " " $i
		gsub(/\t/, " ", m)
		gsub(/[[:cntrl:]]/, "", m)
		pct = $5
		sub(/%$/, "", pct)
		if (m ~ /^\/boot(\/|$)/ || pct !~ /^[0-9]+$/) next
		if ($2 >= 1073741824) text = sprintf("%.1f of %.1f TiB", $3 / 1073741824, $2 / 1073741824)
		else if ($2 >= 10485760) text = sprintf("%d of %d GiB", $3 / 1048576 + 0.5, $2 / 1048576 + 0.5)
		else text = sprintf("%.1f of %.1f GiB", $3 / 1048576, $2 / 1048576)
		print (m == "/" ? "" : m) tab "disk" tab m tab pct tab tab tab text tab
	}' | LC_ALL=C sort | cut -f2-

if sessions=$(timeout 2 who 2>/dev/null); then
	count=$(printf '%s\n' "$sessions" | awk 'NF { n++ } END { print n + 0 }')
	users=$(printf '%s\n' "$sessions" | awk 'NF { print $1 }' | LC_ALL=C sort -u | tr '\n' ' ')
	users=${users% }
	out sessions "$count${users:+  ($users)}"
fi

# The weekday in English, whatever the login's locale.
out time "$(LC_ALL=C date '+%a %Y-%m-%d %H:%M %Z')"

# One record per adapter with a global IPv4 address, less the hidden ones.
timeout 2 ip -br -4 addr show scope global 2>/dev/null | awk -v hide="$hide" -v tab="$tab" '
	hide != "" && $1 ~ hide { next }
	{
		a = $3
		for (i = 4; i <= NF; i++) a = a " " $i
		print "ipv4" tab $1 tab a
	}'

exit 0
