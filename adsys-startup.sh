#!/bin/sh
# adsys-startup.sh - installs the Manatech MOTD from the ADSys copy of SYSVOL.
#
# Three things run it, always as root and always for the same full install
# (install.sh --retire --ssh --timer --ad):
#   - ADSys, at boot, as the "Manatech MOTD" GPO's startup script
#     (MOTD/adsys-startup.sh, relative to SYSVOL/<domain>/Ubuntu/scripts/);
#   - manatech-motd-update.timer, every 4 hours;
#   - manatech-motd-publish.path, with --if-new-version, as soon as ADSys has
#     downloaded a new publish. Publish-ManatechMotd.ps1 bumps the Version= in
#     Ubuntu/GPT.INI and ADSys refreshes its copy every 90 minutes; this run
#     does nothing when the copy's Version is the one last installed.
#
# ADSys keeps its copy in /var/cache/adsys/sysvol/assets/, with install.sh and
# the banner files next to this script in scripts/MOTD/. The copy is tried
# first, so the units point at a path that lasts, not at wherever ADSys ran
# this script from.
#
# From a terminal (sudo sh .../adsys-startup.sh) it prints each step; that is
# also how to install without waiting for a boot. Otherwise its output goes to
# the journal with the tag manatech-motd, as the units' runs do:
#     journalctl -t manatech-motd
#
# MANATECH_ADSYS_ASSETS and MANATECH_STATE_DIR move the copy and
# /var/lib/manatech for the tests; ADSys and the units never set them.

assets=${MANATECH_ADSYS_ASSETS:-/var/cache/adsys/sysvol/assets}
state=${MANATECH_STATE_DIR:-/var/lib/manatech}/installed-version

# say TEXT - one line to stderr and to the journal.
say() {
	echo "manatech-motd: $1" >&2
	logger -t manatech-motd -- "manatech-motd: $1" 2>/dev/null
}

# version - the Version= in the copy's GPT.INI (SYSVOL writes it with CRLF).
version() {
	sed -n 's/^[Vv]ersion=\([0-9][0-9]*\).*/\1/p' "$assets/GPT.INI" 2>/dev/null | head -n 1
}

# unsafe PATH - true when someone other than root could change PATH: not
# owned by root, writable by others, or group-writable with a non-root group.
unsafe() {
	set -- $(stat -c '%u %g %a' "$1" 2>/dev/null)
	[ $# -eq 3 ] && [ "$1" = 0 ] || return 0
	case ${3#${3%???}} in
	??[2367]) return 0 ;;
	?[2367]?) [ "$2" = 0 ] || return 0 ;;
	esac
	return 1
}

if_new=
[ "${1:-}" != --if-new-version ] || if_new=1

# One install at a time: a boot, the timer and a publish can coincide. Only
# root can take the lock; a run without it (the tests) goes ahead unlocked.
lock=/run/manatech-motd.lock
if command -v flock >/dev/null 2>&1 && true 2>/dev/null >>"$lock"; then
	exec 9>>"$lock"
	flock 9
fi

# Read after the lock, so a run that waited sees what the other one installed.
now=$(version)
if [ -n "$if_new" ] && [ -n "$now" ] && [ -r "$state" ] && [ "$(cat "$state")" = "$now" ]; then
	exit 0
fi

for d in "$assets/scripts/MOTD" "$(dirname "$0")"; do
	[ -f "$d/install.sh" ] || continue

	# A copy published with CRLF line endings cannot run under sh at all.
	if grep -q "$(printf '\r')" "$d/install.sh"; then
		say "$d/install.sh has CRLF line endings; publish again with the current Publish-ManatechMotd.ps1 (it writes LF)"
		exit 1
	fi
	# As root this runs whatever the copy holds: refuse a copy that anyone
	# but root could have changed.
	if [ "$(id -u)" -eq 0 ] && { unsafe "$d" || unsafe "$d/install.sh"; }; then
		say "$d or its install.sh can be changed by someone other than root; not running it"
		exit 1
	fi

	say "running $d/install.sh${now:+ (published Version $now)}"
	if [ -t 1 ]; then
		sh "$d/install.sh" --retire --ssh --timer --ad
		rc=$?
	else
		# Into the journal line by line as it runs, so a run that is stopped
		# part-way (ADSys gives startup scripts 90 seconds) shows how far it got.
		rcf=$(mktemp) || exit 1
		{
			sh "$d/install.sh" --retire --ssh --timer --ad
			echo "$?" >"$rcf"
		} 2>&1 | logger -t manatech-motd
		rc=$(cat "$rcf" 2>/dev/null)
		rm -f "$rcf"
		[ -n "$rc" ] || rc=1
	fi

	# Remember which publish is installed, so the publish watcher skips it.
	if [ "$rc" -eq 0 ] && [ -n "$now" ] && [ "$d" = "$assets/scripts/MOTD" ]; then
		mkdir -p "${state%/*}" 2>/dev/null
		if printf '%s\n' "$now" 2>/dev/null >"$state"; then
			say "publish Version $now installed"
		fi
	fi
	exit "$rc"
done
say "install.sh is neither in the ADSys cache nor next to $0"
exit 1
