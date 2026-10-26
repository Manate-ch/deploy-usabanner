#!/bin/sh
# adsys-startup.sh - deploys the banner on Ubuntu from the Group Policy package
# that ADSys keeps (docs/DECISIONS.md, D29). It runs as root. It copies the
# package aside, hands the deploy to a systemd unit, and ends: it does not wait.
#
# Three things run it:
#   - ADSys, at boot, as the GPO's startup script (UsaBanner/adsys-startup.sh,
#     relative to SYSVOL/<domain>/Ubuntu/scripts/);
#   - usabanner-publish.service, with --if-new-version, as soon as ADSys has
#     downloaded a new publish. The publisher raises the Version= in
#     Ubuntu/GPT.INI, and ADSys refreshes its copy every 90 minutes but runs
#     startup scripts only at boot; a run with --if-new-version does nothing
#     when the copy's Version is the one last deployed;
#   - a person, with sudo, to deploy without waiting for a boot.
#
# ADSys keeps its copy in /var/cache/adsys/sysvol/assets/. Its scripts/UsaBanner/
# holds this script, usabanner.json (the package: a UsaBanner configuration
# file) and UsaBanner/ (the module, with linux/bootstrap.sh). The copy is tried
# first, so the Version read from its GPT.INI and the files deployed come from
# the same fetch; the folder this script sits in is the fallback.
#
# In this order; a refusal or a failure ends the run, but for step 6:
#   1. One run at a time (flock): a boot and a publish can coincide. The
#      Version is read after the lock, so a run that waited sees what the
#      other one deployed.
#   2. A Version deployed already ends a run that has --if-new-version.
#   3. A copy that sh cannot read (CRLF line endings in the module's linux/
#      folder), or that anyone but root could have changed, is refused: the
#      deploy runs as root, and runs whatever the copy holds.
#   4. While the unit of an earlier run is still going, this run ends: its
#      files must not change under it, and a new publish waits for the next
#      trigger.
#   5. The module and the package are copied into /var/lib/usabanner/gpo, a
#      folder only root can change, before anything runs. ADSys refreshes its
#      copy whenever it likes, and a deploy must not run files that change
#      under it. An earlier copy there is replaced whole.
#   6. The publish watcher is written, each file when it is missing or
#      differs: usabanner-publish.path watches the copy's GPT.INI (on systemd
#      255 a new file, a rename over it and a rewrite all fire it), and
#      usabanner-publish.service waits 30 seconds for the rest of the publish
#      to land, then runs this script with --if-new-version. If the watcher
#      cannot be set up, the deploy goes on and the exit status says so.
#   7. The deploy, bootstrap.sh -Path <package> -ReplaceOldBanner, goes to the
#      transient unit usabanner-gpo, and this script ends.
#
# It does not wait for the deploy, because ADSys gives its startup scripts 90
# seconds (adsys-machine-scripts.service, Type=notify) and runs every GPO's in
# that one service: a wait holds up the others, and a first deploy installs
# PowerShell, which takes longer. The unit outlives this script. It is ordered
# after the network, stops itself after 30 minutes if it hangs (else it would
# keep every later run waiting for it), and writes the Version into
# /var/lib/usabanner/gpo-installed-version only when the deploy succeeded, so
# a failed deploy is tried again by the next run.
#
# Exit status: 0 when the deploy was handed over, was not needed, or has to
# wait for the unit of an earlier run; 1 when a refusal or a failure ended the
# run, or the publish watcher could not be set up; 2 for an argument it does
# not know.
#
# Everything this script says goes to stderr and to the journal, and the unit's
# output goes to the journal under the same tag:
#     journalctl -t usabanner
# Under usabanner-publish.service, stderr is the journal already, under that
# tag: the service sets USABANNER_STDERR_JOURNAL=1, and the script then says
# each line to stderr alone, so the journal holds it once.
#
# USABANNER_ADSYS_ASSETS, USABANNER_STATE_DIR, USABANNER_UNIT_DIR and
# USABANNER_LOCK_FILE move ADSys's copy, /var/lib/usabanner, /etc/systemd/system
# and the lock for the tests; ADSys and the units never set them.

assets=${USABANNER_ADSYS_ASSETS:-/var/cache/adsys/sysvol/assets}
state=${USABANNER_STATE_DIR:-/var/lib/usabanner}
unitdir=${USABANNER_UNIT_DIR:-/etc/systemd/system}
lock=${USABANNER_LOCK_FILE:-/run/usabanner-gpo.lock}
tag=usabanner
unit=usabanner-gpo
copy=$assets/scripts/UsaBanner
stage=$state/gpo
record=$state/gpo-installed-version
uid=$(id -u)
gid=$(id -g)

# say TEXT - one line to stderr and to the journal; to stderr alone where that
# is the journal (USABANNER_STDERR_JOURNAL, above).
say() {
	printf 'usabanner: %s\n' "$1" >&2
	[ -n "${USABANNER_STDERR_JOURNAL:-}" ] || logger -t "$tag" -- "usabanner: $1" 2>/dev/null
}

# version - the Version= in the copy's GPT.INI (SYSVOL writes it with CRLF).
version() {
	sed -n 's/^[Vv]ersion=\([0-9][0-9]*\).*/\1/p' "$assets/GPT.INI" 2>/dev/null | head -n 1
}

# unsafe PATH [-prune] - true when anything under PATH (PATH alone, with
# -prune) is not a plain file or folder, or could be changed by someone other
# than root: owned by another user, writable by others, or writable by a
# group other than root's. Sets bad to the first such path, or to PATH when
# find fails. ("root" is the user running this: ADSys and the units run it as
# root, and the tests as themselves.)
unsafe() {
	if bad=$(find "$1" $2 \( ! -type f ! -type d -o ! -user "$uid" -o -perm -0002 -o \( -perm -0020 ! -group "$gid" \) \) -print 2>/dev/null); then
		bad=$(printf '%s\n' "$bad" | head -n 1)
		[ -n "$bad" ]
	else
		bad=$1
	fi
}

# unit_file NAME - the text on stdin is the systemd unit NAME in $unitdir. It
# is written when the file is missing or differs, and then sets changed.
unit_file() {
	_text=$(cat)
	if [ -f "$unitdir/$1" ] && [ "$(cat "$unitdir/$1")" = "$_text" ]; then
		return 0
	fi
	if printf '%s\n' "$_text" >"$unitdir/$1.new" && chmod 644 "$unitdir/$1.new" && mv -f "$unitdir/$1.new" "$unitdir/$1"; then
		changed=1
	else
		rm -f "$unitdir/$1.new"
		say "could not write $unitdir/$1"
		return 1
	fi
}

if_new=
[ "${1:-}" != --if-new-version ] || { if_new=1; shift; }
if [ $# -gt 0 ]; then
	printf 'usage: sh %s [--if-new-version]\n' "$0" >&2
	exit 2
fi

# One run at a time: a boot and a publish can coincide. Only root can take the
# lock; a run without it (the tests, where the lock file moves) goes ahead.
if command -v flock >/dev/null 2>&1 && true 2>/dev/null >>"$lock"; then
	exec 9>>"$lock"
	flock 9
fi

# Read after the lock, so a run that waited sees what the other one deployed.
now=$(version)
if [ -n "$if_new" ] && [ -n "$now" ] && [ -r "$record" ] && [ "$(cat "$record")" = "$now" ]; then
	say "publish Version $now is deployed already; nothing to do"
	exit 0
fi

src=
for d in "$copy" "$(dirname "$0")"; do
	if [ -f "$d/UsaBanner/linux/bootstrap.sh" ] && [ -f "$d/usabanner.json" ]; then
		src=$d
		break
	fi
done
if [ -z "$src" ]; then
	say "UsaBanner/linux/bootstrap.sh and usabanner.json are neither in the ADSys copy ($copy) nor next to $0"
	exit 1
fi

# A copy published with CRLF line endings cannot run under sh at all.
cr=$(printf '\r')
for f in "$src"/UsaBanner/linux/*; do
	if [ -f "$f" ] && grep -q "$cr" "$f"; then
		say "$f has CRLF line endings, which sh cannot read; publish again from files with LF line endings"
		exit 1
	fi
done
# As root this runs whatever the copy holds: refuse a copy that anyone but root
# could have changed.
if unsafe "$src"; then
	say "$bad is not a plain file or folder, or can be changed by someone other than root; not running the copy in $src"
	exit 1
fi

# The unit of an earlier run is still going (or about to start): its files must
# not change under it. A new publish waits for the next trigger.
if [ -n "$(systemctl list-units --all --no-legend --plain --no-pager "$unit.service" 2>/dev/null)" ]; then
	say "$unit.service is still deploying an earlier run, so its copy in $stage is left alone; when it has ended, run: systemctl start usabanner-publish.service"
	exit 0
fi

# The module and the package, copied aside whole, into a folder only root can
# change. The new copy is built next to the old one and replaces it in one move.
if ! mkdir -p -m 755 "$state"; then
	say "could not make $state"
	exit 1
fi
if unsafe "$state" -prune; then
	say "$bad can be changed by someone other than root; not copying into it"
	exit 1
fi
new=$stage.new
rm -rf -- "$new"
if ! { mkdir -m 700 "$new" && cp -R "$src/UsaBanner" "$new/" && cp "$src/usabanner.json" "$new/"; }; then
	rm -rf -- "$new"
	say "could not copy the module and the package from $src into $state; the copy in $stage is as it was"
	exit 1
fi
rm -rf -- "$stage"
if ! mv "$new" "$stage"; then
	say "could not move the copy into place at $stage"
	exit 1
fi
say "copied the module and the package from $src${now:+ (published Version $now)} into $stage"

# The publish watcher. A step of it that fails does not stop the deploy, only
# the exit status says so.
rc=0
changed=
unit_file usabanner-publish.path <<EOF || rc=1
[Unit]
Description=UsaBanner: watch the ADSys copy of SYSVOL for a new publish

[Path]
PathChanged=$assets/GPT.INI
Unit=usabanner-publish.service

[Install]
WantedBy=paths.target
EOF
unit_file usabanner-publish.service <<EOF || rc=1
[Unit]
Description=UsaBanner: deploy a new publish from the ADSys copy of SYSVOL
Wants=network-online.target
After=network-online.target
ConditionPathExists=$copy/adsys-startup.sh

[Service]
Type=oneshot
# ADSys writes its copy file by file (each one atomically). GPT.INI changing
# is the signal; the wait lets the rest of the publish land before deploying.
ExecStartPre=/bin/sleep 30
ExecStart=/bin/sh $copy/adsys-startup.sh --if-new-version
SyslogIdentifier=$tag
# The script's stderr is the journal here, under the tag above: it says each
# line there once, not through logger as well.
Environment=USABANNER_STDERR_JOURNAL=1
EOF
if [ -n "$changed" ] && ! systemctl daemon-reload; then
	say "systemctl daemon-reload failed"
	rc=1
fi
if systemctl enable --now usabanner-publish.path >/dev/null; then
	[ -z "$changed" ] || say "publish watcher on: systemctl status usabanner-publish.path"
else
	say "systemctl could not enable usabanner-publish.path, so a new publish waits for the next boot"
	rc=1
fi

# The deploy, in a unit of its own. Everything it needs is in this one command,
# for the unit has none of this script's variables: bootstrap.sh from the copy
# made above, and then the Version, which is the cache's only when the files
# came from the cache.
run="sh '$stage/UsaBanner/linux/bootstrap.sh' -Path '$stage/usabanner.json' -ReplaceOldBanner"
if [ -n "$now" ] && [ "$src" = "$copy" ]; then
	run="$run && echo '$now' >'$record'"
fi
if ! systemd-run --unit="$unit" --collect --no-block \
	--description='UsaBanner: deploy the Group Policy package' \
	--property=After=network-online.target --property=Wants=network-online.target \
	--property=RuntimeMaxSec=1800 --property=SyslogIdentifier="$tag" \
	/bin/sh -c "$run"; then
	say "systemd-run could not start $unit.service"
	exit 1
fi
say "handed the deploy over to $unit.service; follow it with: journalctl -t $tag -f"
exit "$rc"
