#!/bin/sh
# ad-description.sh - caches this computer's AD Description for the banner.
# sample.sh, the periodic job (docs/DECISIONS.md, D17), runs it every 15
# minutes as root. The module takes the host's tier and role from the cache
# (D29), so a login never waits on a domain controller.
#
# It reads the description attribute of this computer's own AD object. It
# writes the first line of it, and a newline, to
# /var/lib/usabanner/ad-description. It writes a file beside that one first
# and moves it into place, so a login never reads half of it. An empty
# Description is cached too, as an empty line: a Description someone cleared
# must clear the banner's role. Every user can read the file.
#
# The computer signs in as itself. It runs kinit -k with its key in
# /etc/krb5.keytab, into a private credential cache. Then it runs ldapsearch
# over GSSAPI against the first domain controller that answers. The
# controllers come from the _ldap._tcp.dc._msdcs SRV record, or from the
# domain's own name when DNS gives none. Each call to the Kerberos and LDAP
# tools and to resolvectl is time-limited and reads nothing from stdin. On any
# failure the previous cache is kept, so an outage never blanks the role.
#
# Exit status:
#   0   a domain controller gave the Description, empty or not.
#   75  no domain controller could be contacted at all (EX_TEMPFAIL). The line
#       printed is a warning. A later run may find one.
#   1   any other failure, such as a host that is not joined (no keytab). The
#       line printed says what failed.
#
# Needs krb5-user (kinit, klist, kdestroy), ldap-utils (ldapsearch),
# libsasl2-modules-gssapi-mit (GSSAPI for ldapsearch) and timeout (coreutils).
# Run it as root: only root reads the keytab.
#
# USABANNER_ROOT (tests only) prefixes the keytab's and the cache's paths.

root=${USABANNER_ROOT:-}
dir=$root/var/lib/usabanner
out=$dir/ad-description
keytab=$root/etc/krb5.keytab
log() { printf 'usabanner: ad: %s\n' "$*"; }

# unreached WHAT - no DC could be contacted at all: say so, keep the last
# description, exit 75.
unreached() {
	log "WARNING: could not contact any domain controller ($*); kept the last description"
	exit 75
}

# A user's Show-UsaBanner reads the cache too.
umask 022

for c in kinit klist kdestroy ldapsearch timeout; do
	command -v "$c" >/dev/null 2>&1 && continue
	case $c in
	ldapsearch) from='ldap-utils; GSSAPI also needs libsasl2-modules-gssapi-mit' ;;
	timeout) from=coreutils ;;
	*) from=krb5-user ;;
	esac
	log "$c is not installed (package $from); description not refreshed"
	exit 1
done
[ -r "$keytab" ] || { log "no readable $keytab (not joined, or not root); description not refreshed"; exit 1; }

# The machine principal: NAME$@REALM (the account's sAMAccountName is NAME$).
principal=$(timeout 10 klist -k "$keytab" </dev/null 2>/dev/null | awk '$2 ~ /\$@/ { print $2; exit }')
[ -n "$principal" ] || { log "no NAME\$@REALM principal in $keytab"; exit 1; }
sam=${principal%@*}
realm=${principal#*@}
domain=$(printf '%s' "$realm" | tr A-Z a-z)
base=$(printf '%s' "$domain" | sed 's/^/DC=/; s/\./,DC=/g')

work=$(mktemp -d) || { log "mktemp could not make a temporary folder; description not refreshed"; exit 1; }
KRB5CCNAME="FILE:$work/ccache"
export KRB5CCNAME
cleanup() {
	timeout 10 kdestroy -q </dev/null 2>/dev/null
	rm -f "$work/ccache" "$work/err"
	rmdir "$work" 2>/dev/null
}
trap cleanup EXIT
# A run stopped part way (systemd stops a unit with TERM) exits through the
# trap above too: sh would otherwise end at once and leave the machine's
# ticket in its folder.
trap 'exit 1' HUP INT TERM

# kinit reaches a DC too, as the realm's KDC. One it cannot find (DNS names
# none), cannot contact at all, or that does not answer within the 30 seconds,
# is a DC out of reach. Any other refusal is not, and fails, saying why.
err=$(LC_ALL=C timeout 30 kinit -k -t "$keytab" "$principal" </dev/null 2>&1 >/dev/null)
rc=$?
if [ "$rc" -ne 0 ]; then
	case $rc:$err in
	124:* | *'Cannot contact any KDC'* | *'Cannot find KDC'*) unreached "kinit: no KDC for $realm answered" ;;
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
# kept with the first line it printed and its "additional info", which holds
# AD's own reason.
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
	*)
		why=$(head -n 1 "$work/err")
		more=$(sed -n 's/^[[:space:]]*additional info: //p' "$work/err" | head -n 1)
		[ -n "$more" ] && why="$why: $more"
		errors="$errors; $dc: $why (exit $rc)"
		;;
	esac
done
if [ -z "$found" ]; then
	[ -n "$errors" ] || unreached "tried: $(echo $dcs)"
	log "no DC gave the description$errors"
	exit 1
fi
# An answer without the object (it was deleted or renamed, or the domain is
# not the realm's) is no empty Description: the last one stays, as on Windows.
printf '%s\n' "$res" | grep -q '^dn:' || {
	log "$found has no computer object $sam under $base; kept the last description"
	exit 1
}

# The cache: written beside itself, then moved into place.
mkdir -p "$dir" && printf '%s\n' "$desc" >"$out.$$" && mv -f "$out.$$" "$out" || {
	rm -f "$out.$$"
	log "cannot write $out; kept the last description"
	exit 1
}
if [ -n "$desc" ]; then log "\"$desc\" (from $found)"; else log "empty on $sam (from $found)"; fi
