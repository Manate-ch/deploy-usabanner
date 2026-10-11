# conffiles.sh - keep Ubuntu's banner conffiles stock, so apt never asks about
# them. Sourced by install.sh, which defines log().
#
# dpkg asks before it replaces a conffile that was changed locally, and
# base-files ships new /etc/issue and /etc/issue.net at every point release.
# Older versions of install.sh overwrote both, and set ENABLED=0 in
# /etc/default/motd-news, so every point release asked. This one leaves them
# stock; the functions here put back the stock versions those older versions
# changed, byte for byte, without apt or the network.

# conffile_md5 PACKAGE PATH
# Out: the md5 dpkg recorded for PATH as one of PACKAGE's conffiles; nothing
#      when PACKAGE does not list it.
conffile_md5() {
	dpkg-query -W -f='${Conffiles}\n' "$1" 2>/dev/null | awk -v p="$2" '$1 == p { print $2; exit }'
}

# file_md5 PATH
# Out: PATH's md5; nothing when it is not a file.
file_md5() {
	[ -f "$1" ] && md5sum "$1" | awk '{ print $1 }'
}

# The stock texts. base-files 13ubuntu10.4 and 13ubuntu10.5 (Ubuntu 24.04.4 and
# 24.04.5) ship exactly these, for their PRETTY_NAME: their md5 sums are the
# ones dpkg records.
stock_issue() { printf '%s \\n \\l\n\n' "$1"; }
stock_issue_net() { printf '%s\n' "$1"; }
# Older versions changed one line of /etc/default/motd-news: undo just that.
stock_motd_news() { sed 's/^ENABLED=0/ENABLED=1/' "$1"; }

# restore_conffile PACKAGE PATH STOCK [ARG]
# In:  PATH, one of PACKAGE's conffiles, and STOCK, a function that prints its
#      stock text (given ARG).
# Out: PATH stock again: when it differs from the md5 dpkg recorded, and
#      STOCK's text has exactly that md5, the text replaces it (644, by rename).
#      Returns 1 when PATH is still changed: the stock text does not match,
#      because someone else edited it or this release is one STOCK does not
#      know. Then PATH is left as it is.
# Why: a stock conffile is one dpkg never asks about.
restore_conffile() {
	_want=$(conffile_md5 "$1" "$2")
	[ -n "$_want" ] || return 0
	[ "$(file_md5 "$2")" = "$_want" ] && return 0
	_tmp=$2.manatech-tmp
	"$3" "${4-}" >"$_tmp"
	if [ "$(file_md5 "$_tmp")" = "$_want" ]; then
		chmod 644 "$_tmp"
		mv -f "$_tmp" "$2"
		log "$2: the stock $1 version is back"
		return 0
	fi
	rm -f "$_tmp"
	log "$2: changed, but not as this installer changes it; left as it is (dpkg will ask about it at the next $1 upgrade)"
	return 1
}

# retire_landscape [LINK]
# In:  the landscape-sysinfo MOTD script, by default
#      /etc/update-motd.d/50-landscape-sysinfo.
# Out: it no longer runs, and a landscape-common upgrade cannot turn it back on.
# Why: LINK is a symlink dpkg does not own, to a file it does
#      (/usr/share/landscape/landscape-sysinfo.wrapper). chmod -x lands on that
#      file, and dpkg sets a package file's mode back on every upgrade - unless
#      a statoverride says otherwise.
retire_landscape() {
	_link=${1:-/etc/update-motd.d/50-landscape-sysinfo}
	[ -e "$_link" ] || return 0
	_file=$(readlink -f "$_link")
	if ! dpkg -S "$_file" >/dev/null 2>&1; then
		chmod -x "$_file"
		return 0
	fi
	dpkg-statoverride --list "$_file" >/dev/null 2>&1 ||
		dpkg-statoverride --update --add root root 0644 "$_file"
}
