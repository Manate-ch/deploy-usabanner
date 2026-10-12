#!/bin/sh
# install.sh - install or update the Manatech login banner on this host, from
# the copy this script sits in: a git clone (e.g. /opt/manatech-motd), or the
# ADSys cache of SYSVOL (/var/cache/adsys/sysvol/assets/scripts/MOTD, where
# adsys-startup.sh runs it from).
#
#   sudo sh install.sh --all       first setup from a git clone: --retire --ssh --timer
#   sudo sh install.sh             banner files only
#   sudo sh install.sh --retire    disable the stock MOTD scripts it replaces, and motd-news
#   sudo sh install.sh --ssh       pre-login banners: console (/etc/issue.d) and a
#                                  plain SSH one (checked with sshd -t)
#   sudo sh install.sh --ad        cache this computer's AD Description (ENV prefix + role)
#   sudo sh install.sh --timer     4-hourly timer: install.sh --update in a git clone
#                                  (plus --ad when given)
#   sudo sh install.sh --update    git pull --ff-only, then reinstall the banner
#                                  files if the commit changed
#   sudo sh install.sh --template  prepare an image (a VM template) for Group
#                                  Policy delivery: only the units below, pointing
#                                  at the ADSys copy of SYSVOL it will have once
#                                  joined; nothing is installed until then
#   sh install.sh --all --whatif   with any options: list what that run would
#                                  change, one line each, and change nothing
#                                  (no sudo needed)
#
# A git clone's timer runs only --update: it installs new banner code, never
# --retire, --ssh or --timer. So at the end of every run, a copy whose timer
# runs it notes in /var/lib/manatech/pending what those would still change
# here (rootfs/usr/local/share/manatech/plan.sh), and 15-manatech-health shows
# that at login with the commands to run.
#
# Run from the ADSys copy of SYSVOL (Group Policy delivery), it always
# (re)writes its units: the 4-hourly timer running adsys-startup.sh, and a
# publish watcher that runs it as soon as ADSys has downloaded a new publish
# (rootfs/usr/local/share/manatech/units.sh has the details). So a host set up
# by an older version picks the watcher up on its next timer run, no reboot.
#
# The per-host /etc/manatech/motd.conf is created from the template once and
# never overwritten. Before any banner file is replaced, the checkout is
# rendered with this host's config: if that fails, the installed banner is
# left exactly as it was, so a bad commit cannot break every login.

set -eu

repo=$(cd "$(dirname "$0")" && pwd)
src=$repo/rootfs
log() { printf 'manatech-motd: %s\n' "$*"; }

files=1 retire= ssh= timer= update= ad= template= whatif=
for a in "$@"; do
	case $a in
	--all) retire=1 ssh=1 timer=1 ;;
	--retire) retire=1 ;;
	--ssh) ssh=1 ;;
	--timer) timer=1 ;;
	--update) update=1 ;;
	--ad) ad=1 ;;
	--template) template=1 timer=1 files= ;;
	--whatif) whatif=1 ;;
	*) log "unknown option: $a" && exit 2 ;;
	esac
done

[ -n "$whatif" ] || [ "$(id -u)" -eq 0 ] || { log "run as root (sudo)"; exit 1; }

# The unit definitions, and where ADSys keeps its copy of SYSVOL.
. "$src/usr/local/share/manatech/units.sh"
# Keeping Ubuntu's banner conffiles stock.
. "$src/usr/local/share/manatech/conffiles.sh"
# What a run would change, for --whatif and the note at the end.
. "$src/usr/local/share/manatech/plan.sh"
# PLAN_ROOT points --whatif at a copy of a host (the tests); never a real run.
[ -n "$whatif" ] || PLAN_ROOT=

# Group Policy delivery: this copy is the ADSys one (or --template prepares
# an image for it). Its units are then always kept current.
adsys=
if [ "$repo" = "$ADSYS_MOTD" ] || [ -n "$template" ]; then
	adsys=1
	timer=1
fi

# The options a clone's timer runs install.sh with: --update for a git clone
# (any other copy is only reinstalled from), plus --ad where the AD
# Description is in use (it was asked for now).
run=
[ ! -d "$repo/.git" ] || run=--update
[ -z "$ad" ] || run="${run:+$run }--ad"

if [ -n "$whatif" ]; then
	# Read only from here: say what this run would change, then stop.
	[ -z "$update" ] || log "--update: no pull under --whatif; below is what this copy would change"
	[ -z "$ad" ] || log "--ad: a real run refreshes /var/lib/manatech/ad-description"
	plan=$(
		[ -z "$files" ] || plan_files "$src"
		[ -z "$retire" ] || plan_retire
		[ -z "$ssh" ] || plan_ssh "$src"
		if [ -n "$timer" ]; then
			if [ -n "$adsys" ]; then plan_units units_adsys; else plan_units units_clone "$repo" "$run"; fi
		fi
	)
	[ -z "$plan" ] || printf '%s\n' "$plan" | sed 's/^/manatech-motd: /'
	n=$(printf '%s\n' "$plan" | grep -c '^would ') || n=0
	if [ "$n" -eq 0 ]; then
		log "--whatif: nothing to change"
	else
		log "--whatif: $n change(s); run it again without --whatif, as root, to make them"
	fi
	exit 0
fi

# The clone URL can carry a deploy token; keep .git readable by root only.
[ -d "$repo/.git" ] && chmod 700 "$repo/.git"

if [ -n "$update" ]; then
	old=$(git -C "$repo" rev-parse HEAD)
	git -C "$repo" pull --ff-only --quiet
	new=$(git -C "$repo" rev-parse HEAD)
	if [ "$old" = "$new" ]; then
		log "up to date at $new"
		files=
	else
		log "pulled $old -> $new"
	fi
fi

if [ -n "$files" ]; then
	for s in 05-manatech-banner 15-manatech-health; do
		# Keep stderr: it is the reason, when the render fails.
		if ! err=$(MANATECH_ROOT=$src MANATECH_CONF=/etc/manatech/motd.conf sh "$src/etc/update-motd.d/$s" 2>&1 >/dev/null); then
			log "$s from the checkout fails to render; installed banner left unchanged"
			[ -n "$err" ] && printf '%s\n' "$err" | sed 's/^/    /'
			exit 1
		fi
	done
	install -d -m 755 /usr/local/share/manatech /etc/manatech
	install -m 644 "$src"/usr/local/share/manatech/* /usr/local/share/manatech/
	install -m 755 "$src/etc/update-motd.d/05-manatech-banner" "$src/etc/update-motd.d/15-manatech-health" /etc/update-motd.d/
	if [ ! -e /etc/manatech/motd.conf ]; then
		install -m 644 "$src/etc/manatech/motd.conf" /etc/manatech/motd.conf
		log "created /etc/manatech/motd.conf: set ENV_NAME, ROLE and WATCH"
	fi
	log "banner installed from $(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo 'a non-git copy')"
fi

# The FQDN for the banner title, looked up here, where waiting on DNS harms
# nothing, so the login-time banner never resolves anything (the note in
# 05-manatech-banner says why). A failed lookup keeps the previous value.
# Not in a template: every VM made from it would inherit the template's name.
fqdn=
[ -n "$template" ] || fqdn=$(timeout 5 hostname -f 2>/dev/null) || fqdn=
if [ -n "$fqdn" ]; then
	install -d -m 755 /var/lib/manatech
	printf '%s\n' "$fqdn" >/var/lib/manatech/fqdn.tmp
	mv -f /var/lib/manatech/fqdn.tmp /var/lib/manatech/fqdn
fi

if [ -n "$retire" ]; then
	# chmod -x, not rm: run-parts skips them, and chmod +x undoes it. These are
	# conffiles: dpkg notices a change by content, not mode, and keeps the
	# mode on an upgrade, so they stay off and apt never asks about them.
	for s in $MANATECH_RETIRED; do
		[ -e "/etc/update-motd.d/$s" ] && chmod -x "/etc/update-motd.d/$s"
	done
	retire_landscape || log "50-landscape-sysinfo: could not add its statoverride"
	# motd-news: the timer masked, rather than ENABLED=0 written into
	# /etc/default/motd-news, a conffile. Older versions did write it: undo that.
	restore_conffile motd-news-config /etc/default/motd-news stock_motd_news /etc/default/motd-news || true
	systemctl mask --now motd-news.timer >/dev/null 2>&1 || true
	log "stock header, help text, sysinfo, motd-news and reboot-required retired"
fi

rc=0

if [ -n "$ssh" ]; then
	# Our own pre-login files. Ubuntu's /etc/issue and /etc/issue.net are
	# conffiles that base-files replaces at every point release, so they stay
	# stock and apt never asks. agetty prints /etc/issue.d/*.issue after
	# /etc/issue (only while /etc/issue exists); sshd sends the drop-in's Banner.
	install -d -m 755 /etc/issue.d /etc/manatech
	install -m 644 "$src/etc/issue.d/50-manatech.issue" /etc/issue.d/
	install -m 644 "$src/etc/issue.net" /etc/manatech/issue.net
	# Older versions wrote over the stock ones: put those back.
	pretty=$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME-}") || pretty=
	if [ -n "$pretty" ]; then
		restore_conffile base-files /etc/issue stock_issue "$pretty" || true
		restore_conffile base-files /etc/issue.net stock_issue_net "$pretty" || true
	fi
	# sshd uses the FIRST Banner it reads, and Ubuntu's sshd_config includes
	# sshd_config.d/*.conf at its top, in name order: 00- sorts ahead of
	# other drop-ins. The earlier name (10-) is removed.
	dropin=/etc/ssh/sshd_config.d/00-manatech-banner.conf
	install -m 644 "$src/etc/ssh/sshd_config.d/00-manatech-banner.conf" "$dropin"
	rm -f /etc/ssh/sshd_config.d/10-manatech-banner.conf
	# sshd -t refuses any config without /run/sshd. ssh.service creates it
	# (RuntimeDirectory=sshd, 0755) and systemd deletes it whenever the service
	# stops - which on 24.04 happens while ssh.socket keeps listening and open
	# sessions carry on - so create it the same way first.
	install -d -m 755 /run/sshd
	if sshd -t; then
		# try-reload-or-restart does nothing when ssh.service is inactive; the
		# next connection then starts it with the new config via ssh.socket.
		systemctl try-reload-or-restart ssh
		# What sshd will actually use: another file may still set a Banner
		# ahead of ours (a drop-in sorting before 00-, or lines placed above
		# the Include). Those are someone else's; report them, do not edit.
		effective=$(sshd -T 2>/dev/null | awk '$1 == "banner" { print $2 }')
		if [ "$effective" = /etc/manatech/issue.net ]; then
			log "pre-login SSH banner on (open sessions are unaffected)"
		else
			log "sshd uses Banner ${effective:-none}, not /etc/manatech/issue.net; set by:"
			grep -il '^[[:space:]]*banner[[:space:]]' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null |
				grep -v "^$dropin$" | sed 's/^/    /'
			rc=1
		fi
	else
		rm -f "$dropin"
		log "sshd -t rejected the config; banner drop-in removed again"
		rc=1
	fi
fi

if [ -n "$ad" ]; then
	# The banner reads the cache at login; a failure keeps the previous one.
	sh "$src/usr/local/share/manatech/ad-description.sh" || rc=1
fi

# install_units GENERATOR [ARGS] - write the units GENERATOR (from units.sh)
# produces into /etc/systemd/system, replacing only the files whose content
# changed, and reload systemd only when one did. Sets units_changed.
install_units() {
	_gen=$1
	shift
	_tmp=$(mktemp -d)
	"$_gen" "$_tmp" "$@"
	units_changed=
	for _f in "$_tmp"/*; do
		if ! cmp -s "$_f" "/etc/systemd/system/${_f##*/}"; then
			install -m 644 "$_f" /etc/systemd/system/
			units_changed=1
		fi
	done
	rm -f "$_tmp"/*
	rmdir "$_tmp"
	[ -z "$units_changed" ] || systemctl daemon-reload
}

if [ -n "$timer" ]; then
	if [ -n "$adsys" ]; then
		install_units units_adsys
		systemctl enable --now manatech-motd-update.timer manatech-motd-publish.path >/dev/null
		[ -z "$units_changed" ] ||
			log "4-hourly timer and publish watcher on: systemctl list-timers manatech-motd-update.timer; systemctl status manatech-motd-publish.path"
	else
		install_units units_clone "$repo" "$run"
		systemctl enable --now manatech-motd-update.timer >/dev/null
		log "4-hourly update timer on (install.sh${run:+ $run}): systemctl list-timers manatech-motd-update.timer"
	fi
fi

# A copy whose timer runs it: note what --retire, --ssh and --timer would still
# change here, for 15-manatech-health to show at login. Group Policy hosts run
# all three every time, so they never need the note.
[ -n "$adsys" ] || note_pending "$repo" "$src" "$run" || log "could not note the waiting setup changes"

# A failed step (the SSH banner) no longer skips the steps after it; the exit
# status still reports it.
exit "$rc"
