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
#   | updates  | the updates waiting, as text; a level, good or warn    |
#   | reboot   | a reboot pending or scheduled, as text; a level        |
#   | sessions | how many, and whose                                    |
#   | time     | the local time                                         |
#   | ipv4     | an adapter, and its addresses                          |
#   +----------+--------------------------------------------------------+
#
# What is slow to read comes from the periodic job (sample.sh, D17): min and
# max are the lowest and highest of its samples of the last 24 hours, the
# value now included; the memory's and disks' kinds and the updates come
# from its cache, when that is less than 24 hours old. Until the job has
# run, those fields are empty and there is no updates record. cpu is the
# 1-minute load as a share of the online CPUs, so it can pass 100. A fact it
# cannot read gets no record. Nothing here waits on the network, and each
# command that could stall is time-boxed: pam_motd runs the renderer at
# every login.
#
# USABANNER_ROOT (tests only) prefixes each file it reads.
# USABANNER_NOW (tests only) is the time, in seconds since 1970.
# USABANNER_IFACE_HIDE replaces the adapters it leaves out: an ERE, matched
# against the adapter's name; empty leaves none out.

root=${USABANNER_ROOT:-}
hide=${USABANNER_IFACE_HIDE-'^(docker|br-|veth|virbr|lxcbr|cni|flannel|tun|tap|wg|tailscale|zt)'}
tab=$(printf '\t')
now=${USABANNER_NOW:-$(date +%s)}
case $now in '' | *[!0-9]*) now=0 ;; esac

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

# fill - its input's cpu, memory and disk records with what the periodic job
# keeps filled in: min and max, the lowest and highest of the samples of the
# last 24 hours and of the value now; and the memory's and disks' kinds from
# its cache, when that is less than 24 hours old. A record the job knows
# nothing of keeps those fields empty.
fill() {
	awk -F '\t' -v OFS='\t' -v cut=$((now - 86400)) -v samples="$root/var/lib/usabanner/samples.tsv" -v slow="$root/var/lib/usabanner/slow.tsv" '
	function widen(key, at) {
		if (!(key in lo) || $at !~ /^[0-9]+$/) return
		$(at + 1) = (lo[key] < $at + 0) ? lo[key] : $at + 0
		$(at + 2) = (hi[key] > $at + 0) ? hi[key] : $at + 0
	}
	BEGIN {
		while ((getline line < samples) > 0) {
			n = split(line, f, "\t")
			if (n < 3 || f[1] !~ /^[0-9]+$/ || f[1] + 0 <= cut) continue
			if (f[2] == "disk") { key = "disk" SUBSEP f[3]; v = f[4] }
			else { key = f[2]; v = f[3] }
			if (v !~ /^[0-9]+$/) continue
			if (!(key in lo) || v + 0 < lo[key]) lo[key] = v + 0
			if (!(key in hi) || v + 0 > hi[key]) hi[key] = v + 0
		}
		while ((getline line < slow) > 0) {
			n = split(line, f, "\t")
			if (n < 3 || f[1] !~ /^[0-9]+$/ || f[1] + 0 <= cut) continue
			if (f[2] == "memory-kind") kind["memory"] = f[3]
			else if (f[2] == "disk-kind" && n >= 4) kind["disk" SUBSEP f[3]] = f[4]
		}
	}
	$1 == "cpu" { widen("cpu", 2) }
	$1 == "memory" {
		widen("memory", 2)
		if ("memory" in kind) $6 = kind["memory"]
	}
	$1 == "disk" {
		widen("disk" SUBSEP $2, 3)
		if (("disk" SUBSEP $2) in kind) $7 = kind["disk" SUBSEP $2]
	}
	{ print }'
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

# The CPU, the memory and the disks, each with its 24-hour range and kind.
{
	# The online CPUs: nproc would follow OMP_NUM_THREADS from a user's shell.
	cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null)
	case $cores in '' | *[!0-9]* | 0) cores= ;; esac
	if [ -n "$cores" ] && [ -r "$root/proc/loadavg" ]; then
		read -r load _ <"$root/proc/loadavg"
		share=$(awk -v l="$load" -v c="$cores" 'BEGIN { printf "%d", l * 100 / c + 0.5 }')
		unit=cores
		[ "$cores" -eq 1 ] && unit=core
		# Their rated speed: the model name's "@ 3.10GHz" where it has one, as
		# Intel's do, else the highest speed cpufreq knows.
		ghz=
		[ -r "$root/proc/cpuinfo" ] && ghz=$(awk -F '@' '/^model name/ && NF > 1 && match($NF, /[0-9.]+ *GHz/) { printf "%.1f", substr($NF, RSTART, RLENGTH) + 0; exit }' "$root/proc/cpuinfo")
		max=$root/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq
		[ -z "$ghz" ] && [ -r "$max" ] && ghz=$(awk '$1 ~ /^[0-9]+$/ && $1 > 0 { printf "%.1f", $1 / 1000000 }' "$max")
		out cpu "$share" '' '' "$cores $unit${ghz:+ @ $ghz GHz}"
	fi

	# Memory in use: MemTotal less MemAvailable, as free(1) counts it, the
	# percentage cut as today's banner cuts it.
	if [ -r "$root/proc/meminfo" ]; then
		set -- $(awk 'BEGIN { a = -1 } /^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 }
			END { if (t > 0 && a >= 0) printf "%d %.1f %.1f", (t - a) * 100 / t, (t - a) / 1048576, t / 1048576 }' "$root/proc/meminfo")
		[ $# -eq 3 ] && out memory "$1" '' '' "$2 of $3 GiB" ''
	fi

	# Local filesystems only (-l), so an unreachable NFS server cannot hang
	# df, in KiB (-k) whatever BLOCK_SIZE says; /boot and below are left out.
	# / first, then by mount point, which may hold spaces.
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
} | fill

# The updates waiting, as the job last counted them (apt-check is too slow
# for a login): a warning while security updates wait.
[ -r "$root/var/lib/usabanner/slow.tsv" ] && awk -F '\t' -v cut=$((now - 86400)) -v tab="$tab" '
	$2 == "updates" && $1 ~ /^[0-9]+$/ && $1 + 0 > cut && $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ { waiting = $3; security = $4 }
	END {
		if (waiting == "") exit
		if (waiting == 0) print "updates" tab "none pending" tab "good"
		else if (security == 0) print "updates" tab waiting " pending" tab "good"
		else print "updates" tab waiting " pending, " security " security" tab "warn"
	}' "$root/var/lib/usabanner/slow.tsv"

# A reboot, read live (D17): pending, by Ubuntu's flag file and the packages
# that asked for it, a kernel shortened to its version; scheduled, by the file
# shutdown --show reads (systemd 255, logind-dbus.c: USEC= in microseconds,
# MODE= reboot, poweroff and the like).
pending=
if [ -e "$root/run/reboot-required" ]; then
	why=
	[ -r "$root/run/reboot-required.pkgs" ] && why=$(LC_ALL=C sort -u "$root/run/reboot-required.pkgs" | sed 's/^linux-image-\(.*\)-generic$/kernel \1/' | awk 'NF { printf "%s%s", (n++ ? ", " : ""), $0 }')
	pending="pending${why:+: $why}"
fi
scheduled=
if [ -r "$root/run/systemd/shutdown/scheduled" ]; then
	set -- $(awk -F '=' '$1 == "USEC" && $2 ~ /^[0-9]+$/ { usec = $2 } $1 == "MODE" { mode = $2 } END { if (usec != "") print int(usec / 1000000), (mode == "" ? "reboot" : mode) }' "$root/run/systemd/shutdown/scheduled")
	if [ $# -eq 2 ]; then
		at=$(LC_ALL=C date -d "@$1" '+%a %H:%M' 2>/dev/null)
		what=scheduled
		[ "$2" = reboot ] || what="$2 scheduled"
		[ -n "$at" ] && scheduled="$what $at"
	fi
fi
if [ -z "$pending$scheduled" ]; then
	out reboot 'none pending, none scheduled' good
elif [ -z "$scheduled" ]; then
	out reboot "$pending" warn
elif [ -z "$pending" ]; then
	out reboot "none pending; $scheduled" warn
else
	out reboot "$pending; $scheduled" warn
fi

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
