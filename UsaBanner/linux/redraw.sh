#!/bin/sh
# redraw.sh - runs after each sample of the periodic job (D17). The banners
# carry the host's name, its VLAN, the configuration's look, and the tier and
# role the configuration and the host's AD Description give (D29), as they
# were when they were drawn: /var/lib/usabanner/drawn holds that name, address,
# the configuration's SHA-256 and the cached AD Description's ('' for none).
# When the host's own differ, as on a VM made from a template once it is
# renamed, after an edit of /etc/usabanner/usabanner.json, or once
# ad-description.sh caches a changed Description, the module draws the banners
# again.
#
#   sh redraw.sh [RECORDS]
#
# RECORDS, a file of facts records, stands in for facts.sh: for tests.
# USABANNER_ROOT (tests only) prefixes each file it reads.

root=${USABANNER_ROOT:-}
dir=$root/var/lib/usabanner
here=$(dirname "$0")
[ -r "$dir/drawn" ] || exit 0

if [ $# -ge 1 ]; then
	records=$(cat "$1")
else
	records=$(sh "$here/facts.sh")
fi
sum=$(sha256sum "$root/etc/usabanner/usabanner.json" 2>/dev/null | cut -d ' ' -f 1)
adsum=$(sha256sum "$dir/ad-description" 2>/dev/null | cut -d ' ' -f 1)
now=$(printf '%s\n' "$records" | awk -F '\t' -v sum="$sum" -v adsum="$adsum" '
	$1 == "name" { name = $2 }
	$1 == "ip" { ip = $2 }
	END { printf "%s\t%s\t%s\t%s", name, ip, sum, adsum }')
drawn=
IFS= read -r drawn <"$dir/drawn" || true
[ "$now" = "$drawn" ] && exit 0

echo 'usabanner: the name, address, configuration or AD Description the banners were drawn with has changed: drawing them again'
exec pwsh -NoProfile -NonInteractive -Command '& (Import-Module UsaBanner -PassThru) { Update-UsaBannerDrawing }'
