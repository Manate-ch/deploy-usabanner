#!/bin/sh
# ad-description.sh - cache this computer's AD Description for the banner.
#
# Reads the description attribute of this computer's own AD object and writes
# it, one line, to /var/lib/manatech/ad-description. motd-lib.sh reads that
# file at login, so a login never waits on a DC.
#
# The machine authenticates as itself: its key in /etc/krb5.keytab,
# kinit -k into a private credential cache, then ldapsearch over GSSAPI to the
# first DC (from the _ldap._tcp.dc._msdcs SRV record) that answers. Every
# command is time-limited and reads nothing from stdin. On any failure the
# previous cache is kept, so a DC outage never blanks the role.
#
# Exit status: 0 when a DC gave the description. 75 (EX_TEMPFAIL) when no DC
# could be contacted at all: a warning, which says so and leaves the time in
# /var/lib/manatech/ad-unreached for the banner's health lines; the next good
# run removes it, and install.sh does not fail on it. 1 for any other
# failure, saying which DC answered what.
#
# Needs: ldap-utils, libsasl2-modules-gssapi-mit, krb5-user. Run as root
# (the keytab is root-only). MANATECH_ROOT (tests only) prefixes its paths.

root=${MANATECH_ROOT:-}
out=$root/var/lib/manatech/ad-description
note=$root/var/lib/manatech/ad-unreached
keytab=$root/etc/krb5.keytab
log() { printf 'manatech-motd: ad: %s\n' "$*"; }

# unreached WHAT - no DC could be contacted at all: say so, note the time and
# WHAT for the banner, keep the last description, exit 75.
unreached() {
	log "WARNING: could not contact any domain controller ($*); kept the last description"
	mkdir -p "$root/var/lib/manatech"
	printf '%s\t%s\n' "$(date +%s)" "$*" >"$note.tmp" && mv -f "$note.tmp" "$note"
	exit 75
}

for c in kinit klist ldapsearch timeout; do
	command -v "$c" >/dev/null 2>&1 || { log "$c is not installed; description not refreshed"; exit 1; }
done
[ -r "$keytab" ] || { log "no readable $keytab (not joined, or not root); description not refreshed"; exit 1; }

# The machine principal: NAME$@REALM (the account's sAMAccountName is NAME$).
principal=$(klist -k "$keytab" 2>/dev/null | awk '$2 ~ /\$@/ { print $2; exit }')
[ -n "$principal" ] || { log "no NAME\$@REALM principal in $keytab"; exit 1; }
sam=${principal%@*}
realm=${principal#*@}
domain=$(printf '%s' "$realm" | tr A-Z a-z)
base=$(printf '%s' "$domain" | sed 's/^/DC=/; s/\./,DC=/g')

work=$(mktemp -d) || exit 1
KRB5CCNAME="FILE:$work/ccache"
export KRB5CCNAME
cleanup() {
	kdestroy -q 2>/dev/null
	rm -f "$work/ccache" "$work/err"
	rmdir "$work" 2>/dev/null
}
trap cleanup EXIT

# kinit reaches a DC too, as the realm's KDC. One it cannot contact at all,
# or that does not answer within the 30 seconds, is a DC out of reach; any
# other refusal is not, and fails, saying why.
err=$(LC_ALL=C timeout 30 kinit -k -t "$keytab" "$principal" </dev/null 2>&1 >/dev/null)
rc=$?
if [ "$rc" -ne 0 ]; then
	case $rc:$err in
	124:* | *'Cannot contact any KDC'*) unreached "kinit: no KDC for $realm answered" ;;
	esac
	log "kinit as $principal failed: $(printf '%s\n' "$err" | head -n 1)"
	exit 1
fi

# DCs from DNS SRV (resolvectl prints "<name> IN SRV prio weight port target");
# the domain name itself (its A records are the DCs) is the fallback.
dcs=$(timeout 10 resolvectl query -t SRV "_ldap._tcp.dc._msdcs.$domain" </dev/null 2>/dev/null |
	awk '$3 == "SRV" { sub(/\.$/, "", $7); print $7 }')
[ -n "$dcs" ] || dcs=$domain

# Each DC in turn, until one answers. ldapsearch exits 255 when it cannot
# contact the server (LDAP_SERVER_DOWN, -1), and timeout 124 when it hangs:
# a DC out of reach. Any other status is a DC that answered with an error,
# kept with the first line it printed.
found= desc= errors=
for dc in $dcs; do
	res=$(LC_ALL=C timeout 30 ldapsearch -LLL -Q -Y GSSAPI -o ldif-wrap=no -o nettimeout=5 -H "ldap://$dc" \
		-b "$base" "(sAMAccountName=$sam)" description </dev/null 2>"$work/err")
	rc=$?
	if [ "$rc" -eq 0 ]; then
		found=$dc
		line=$(printf '%s\n' "$res" | grep -i '^description:' | head -n 1)
		case $line in
		[Dd]escription::*) desc=$(printf '%s' "${line#*:: }" | base64 -d 2>/dev/null | head -n 1) ;;
		[Dd]escription:*) desc=${line#*: } ;;
		esac
		break
	fi
	case $rc in
	124 | 255) ;;
	*) errors="$errors; $dc: $(head -n 1 "$work/err") (exit $rc)" ;;
	esac
done
if [ -z "$found" ]; then
	[ -n "$errors" ] || unreached "tried: $(echo $dcs)"
	log "no DC gave the description$errors"
	exit 1
fi

mkdir -p "$root/var/lib/manatech"
printf '%s\n' "$desc" >"$out.tmp" && mv "$out.tmp" "$out"
rm -f "$note"
if [ -n "$desc" ]; then log "\"$desc\" (from $found)"; else log "empty on $sam (from $found)"; fi
