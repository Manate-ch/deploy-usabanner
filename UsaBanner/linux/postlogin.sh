#!/bin/sh
# postlogin.sh - the banner after login on Linux (docs/DECISIONS.md, D2): the
# records linux/facts.sh gives, drawn by postlogin.awk into the frame
# Deploy-UsaBanner pre-drew. A login waits on sh and awk alone.
#
#   sh postlogin.sh FRAME [RECORDS]
#
# RECORDS, a file of facts records, stands in for facts.sh: for tests. A
# frame that is missing or empty prints nothing, so a host part-way through
# its deploy shows no half-drawn banner.

frame=${1:?usage: postlogin.sh FRAME [RECORDS]}
here=$(dirname "$0")
[ -s "$frame" ] || exit 0
USABANNER_FRAME=$frame
export USABANNER_FRAME
if [ $# -ge 2 ]; then
	LC_ALL=C awk -F '\t' -f "$here/postlogin.awk" "$2"
else
	sh "$here/facts.sh" | LC_ALL=C awk -F '\t' -f "$here/postlogin.awk"
fi
