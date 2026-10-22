#!/bin/sh
# sample.sh - the periodic job (docs/DECISIONS.md, D17), every 15 minutes as
# root. It samples this host's CPU, memory and disks for the banner's 24-hour
# range, and caches the host's FQDN, which a login must not wait on DNS for.
#
#   +-----------------------------------+------------------------------------+
#   | File, under /var/lib/usabanner    | Holds                              |
#   +-----------------------------------+------------------------------------+
#   | samples.tsv                       | a line per sample: the time, in    |
#   |                                   | seconds since 1970; cpu, memory or |
#   |                                   | disk, with the disk's mount point; |
#   |                                   | the percentage, as facts.sh gives  |
#   |                                   | it now                             |
#   | fqdn                              | the name hostname -f gives         |
#   +-----------------------------------+------------------------------------+
#
# Samples older than 24 hours are dropped at every run. Each file is written
# whole and moved into place, so a login never reads half of one.
#
# USABANNER_ROOT (tests only) prefixes each file it reads and writes.
# USABANNER_NOW (tests only) is the time, in seconds since 1970.

root=${USABANNER_ROOT:-}
dir=$root/var/lib/usabanner
here=$(dirname "$0")
now=${USABANNER_NOW:-$(date +%s)}
case $now in '' | *[!0-9]*) exit 1 ;; esac

# A user's Show-UsaBanner reads these files too.
umask 022
mkdir -p "$dir" || exit 1

# The FQDN: only a name that starts with the host's own and goes on to a
# domain, so a hosts file's localhost.localdomain is never cached. hostname
# -f that answers the short name alone means no domain: the cache goes. One
# that fails or stalls leaves the cache as it was.
short=$(hostname 2>/dev/null)
if fqdn=$(timeout 5 hostname -f 2>/dev/null) && [ -n "$short" ]; then
	case $fqdn in
	"$short".?*)
		printf '%s\n' "$fqdn" >"$dir/fqdn.$$" && mv -f "$dir/fqdn.$$" "$dir/fqdn"
		;;
	"$short") rm -f "$dir/fqdn" ;;
	esac
fi

# The samples of the last 24 hours, then this one.
{
	[ -r "$dir/samples.tsv" ] && awk -F '\t' -v cut=$((now - 86400)) '$1 ~ /^[0-9]+$/ && $1 + 0 > cut' "$dir/samples.tsv"
	sh "$here/facts.sh" | awk -F '\t' -v t="$now" -v OFS='\t' '
		($1 == "cpu" || $1 == "memory") && $2 ~ /^[0-9]+$/ { print t, $1, $2 }
		$1 == "disk" && $3 ~ /^[0-9]+$/ { print t, $1, $2, $3 }'
} >"$dir/samples.tsv.$$" && mv -f "$dir/samples.tsv.$$" "$dir/samples.tsv"
