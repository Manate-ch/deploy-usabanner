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
# Needs: ldap-utils, libsasl2-modules-gssapi-mit, krb5-user. Run as root
# (the keytab is root-only).

out=/var/lib/manatech/ad-description
keytab=/etc/krb5.keytab
log() { printf 'manatech-motd: ad: %s\n' "$*"; }

for c in kinit klist ldapsearch timeout; do
	command -v "$c" >/dev/null 2>&1 || { log "$c is not installed; description not refreshed"; exit 1; }
done
[ -r "$keytab" ] || { log "no readable $keytab (not joined, or not root); description not refreshed"; exit 1; }

# The machine principal: NAME$@REALM (the account's sAMAccountName is NAME$).
principal=$(klist -k "$keytab" 2>/dev/null | awk '$2 ~ /\$@/ { print $2; exit }')
[ -n "$principal" ] || { log "no NAME\$@REALM principal in $keytab"; exit 1; }
sam=${principal%@*}
domain=$(printf '%s' "${principal#*@}" | tr A-Z a-z)
base=$(printf '%s' "$domain" | sed 's/^/DC=/; s/\./,DC=/g')

work=$(mktemp -d) || exit 1
KRB5CCNAME="FILE:$work/ccache"
export KRB5CCNAME
cleanup() {
	kdestroy -q 2>/dev/null
	rm -f "$work/ccache"
	rmdir "$work" 2>/dev/null
}
trap cleanup EXIT

if ! timeout 30 kinit -k -t "$keytab" "$principal" </dev/null >/dev/null 2>&1; then
	log "kinit as $principal failed"
	exit 1
fi

# DCs from DNS SRV (resolvectl prints "<name> IN SRV prio weight port target");
# the domain name itself (its A records are the DCs) is the fallback.
dcs=$(timeout 10 resolvectl query -t SRV "_ldap._tcp.dc._msdcs.$domain" </dev/null 2>/dev/null |
	awk '$3 == "SRV" { sub(/\.$/, "", $7); print $7 }')
[ -n "$dcs" ] || dcs=$domain

found= desc=
for dc in $dcs; do
	res=$(timeout 30 ldapsearch -LLL -Q -Y GSSAPI -o ldif-wrap=no -o nettimeout=5 -H "ldap://$dc" \
		-b "$base" "(sAMAccountName=$sam)" description </dev/null 2>/dev/null) || continue
	found=$dc
	line=$(printf '%s\n' "$res" | grep -i '^description:' | head -n 1)
	case $line in
	[Dd]escription::*) desc=$(printf '%s' "${line#*:: }" | base64 -d 2>/dev/null | head -n 1) ;;
	[Dd]escription:*) desc=${line#*: } ;;
	esac
	break
done
[ -n "$found" ] || { log "no DC answered (tried: $(echo $dcs))"; exit 1; }

mkdir -p /var/lib/manatech
printf '%s\n' "$desc" >"$out.tmp" && mv "$out.tmp" "$out"
if [ -n "$desc" ]; then log "\"$desc\" (from $found)"; else log "empty on $sam (from $found)"; fi
