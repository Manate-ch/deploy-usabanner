#!/bin/sh
# sample.sh - the periodic job (docs/DECISIONS.md, D17), every 15 minutes as
# root. It samples this host's CPU, memory and disks for the banner's 24-hour
# range, and keeps what is too slow to read at a login: the host's FQDN,
# which could wait on DNS, and the slow facts.
#
#   +-----------------------------------+------------------------------------+
#   | File, under /var/lib/usabanner    | Holds                              |
#   +-----------------------------------+------------------------------------+
#   | samples.tsv                       | a line per sample: the time, in    |
#   |                                   | seconds since 1970; cpu, memory or |
#   |                                   | disk, with the disk's mount point; |
#   |                                   | the percentage, as facts.sh gives  |
#   |                                   | it now                             |
#   | slow.tsv                          | a line per slow fact: the time;    |
#   |                                   | memory-kind and the kind; or       |
#   |                                   | disk-kind, a mount point and its   |
#   |                                   | kind; or updates, how many wait    |
#   |                                   | and how many of those for security |
#   | fqdn                              | the name hostname -f gives         |
#   +-----------------------------------+------------------------------------+
#
# Samples older than 24 hours are dropped at every run, and slow.tsv is
# written anew. Each file is written whole and moved into place, so a login
# never reads half of one.
#
# USABANNER_ROOT (tests only) prefixes each file it reads and writes, and
# apt-check's path.
# USABANNER_NOW (tests only) is the time, in seconds since 1970.

root=${USABANNER_ROOT:-}
dir=$root/var/lib/usabanner
here=$(dirname "$0")
tab=$(printf '\t')
now=${USABANNER_NOW:-$(date +%s)}
case $now in '' | *[!0-9]*) exit 1 ;; esac

# A user's Show-UsaBanner reads these files too.
umask 022
mkdir -p "$dir" || exit 1

# The FQDN: only a name that starts with the host's own and goes on to a
# domain, so a hosts file's localhost.localdomain is never cached. DNS names
# ignore case, and a host can be H-WEB1 to the kernel and h-web1.ad.example
# to DNS: the cache keeps the host's own case and the domain in lower case,
# as Windows shows its name. hostname -f that answers the short name alone
# means no domain: the cache goes. One that fails or stalls leaves the cache
# as it was.
short=$(hostname 2>/dev/null)
if fqdn=$(timeout 5 hostname -f 2>/dev/null) && [ -n "$short" ]; then
	lower=$(printf '%s\n' "$short" | tr '[:upper:]' '[:lower:]')
	fqdn=$(printf '%s\n' "$fqdn" | tr '[:upper:]' '[:lower:]')
	case $fqdn in
	"$lower".?*)
		printf '%s.%s\n' "$short" "${fqdn#"$lower".}" >"$dir/fqdn.$$" && mv -f "$dir/fqdn.$$" "$dir/fqdn"
		;;
	"$lower") rm -f "$dir/fqdn" ;;
	esac
fi

# The samples of the last 24 hours, then this one.
{
	[ -r "$dir/samples.tsv" ] && awk -F '\t' -v cut=$((now - 86400)) '$1 ~ /^[0-9]+$/ && $1 + 0 > cut' "$dir/samples.tsv"
	sh "$here/facts.sh" | awk -F '\t' -v t="$now" -v OFS='\t' '
		($1 == "cpu" || $1 == "memory") && $2 ~ /^[0-9]+$/ { print t, $1, $2 }
		$1 == "disk" && $3 ~ /^[0-9]+$/ { print t, $1, $2, $3 }'
} >"$dir/samples.tsv.$$" && mv -f "$dir/samples.tsv.$$" "$dir/samples.tsv"

# The slow facts, for the logins of the next 24 hours.
{
	# The memory as DDR4-3200: the type and speed of the first module that has
	# a type. A virtual machine's firmware gives none (Hyper-V: Unknown).
	timeout 5 dmidecode -t memory 2>/dev/null | awk -v t="$now" -v OFS='\t' '
		function emit() {
			if (!device || type == "" || type == "Unknown" || type == "Other") return
			speed = (configured != "") ? configured : rated
			print t, "memory-kind", type (speed != "" ? "-" speed : "")
			found = 1
			exit
		}
		/^Memory Device/ { device = 1; type = rated = configured = ""; next }
		/^$/ { emit(); device = 0; next }
		!device { next }
		/^\tSize: No Module Installed/ { device = 0 }
		/^\tType: / { type = substr($0, index($0, ": ") + 2) }
		/^\tSpeed: [0-9]/ { split(substr($0, index($0, ": ") + 2), s, " "); rated = s[1] }
		/^\tConfigured (Memory|Clock) Speed: [0-9]/ { split(substr($0, index($0, ": ") + 2), s, " "); configured = s[1] }
		END { if (!found) emit() }'

	# Each local filesystem's kind, from the disk under it through LVM, RAID
	# and partitions: removable, NVMe, SSD or HDD. In a virtual machine the
	# storage behind a disk cannot be known, so there is none. The mount
	# point is cleaned as facts.sh cleans it.
	if ! systemd-detect-virt --quiet --vm 2>/dev/null; then
		timeout 2 df -P -k -l -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | awk -v tab="$tab" '
			NR > 1 {
				m = $6
				for (i = 7; i <= NF; i++) m = m " " $i
				gsub(/\t/, " ", m)
				gsub(/[[:cntrl:]]/, "", m)
				print $1 tab m
			}' |
			while IFS="$tab" read -r source mount; do
				kind=$(timeout 2 lsblk -s -n -r -o TYPE,RM,ROTA,TRAN "$source" 2>/dev/null | awk '
					$1 == "disk" { k = ($2 == 1) ? "removable" : ($4 == "nvme") ? "NVMe" : ($3 == 0) ? "SSD" : "HDD" }
					END { print k }')
				[ -n "$kind" ] && printf '%s\tdisk-kind\t%s\t%s\n' "$now" "$mount" "$kind"
			done
	fi

	# The updates waiting, as apt-check counts them on its standard error:
	# all of them, then the security ones.
	check=$root/usr/lib/update-notifier/apt-check
	if [ -x "$check" ]; then
		counts=$(timeout 60 "$check" 2>&1 >/dev/null)
		case $counts in
		*[!0-9\;]*) ;;
		[0-9]*\;[0-9]*) printf '%s\tupdates\t%s\t%s\n' "$now" "${counts%%;*}" "${counts#*;}" ;;
		esac
	fi
} >"$dir/slow.tsv.$$" && mv -f "$dir/slow.tsv.$$" "$dir/slow.tsv"
