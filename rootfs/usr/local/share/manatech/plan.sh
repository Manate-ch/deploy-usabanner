# plan.sh - what install.sh would change on this host, found without changing
# anything. Sourced by install.sh after units.sh and conffiles.sh. It serves
# --whatif, and the note of waiting setup changes that 15-manatech-health shows
# at login.
#
# Each plan_* function prints one "would ..." line per change it finds, and a
# "note: ..." line for something it would leave alone; only the "would" lines
# count as changes. PLAN_ROOT, empty on a host, prefixes every host path, so
# the tests can point it at a copy of one; install.sh empties it for every run
# that changes things.

PLAN_ROOT=${PLAN_ROOT:-}

# The stock MOTD scripts --retire turns off (with chmod -x).
MANATECH_RETIRED='00-header 10-help-text 50-motd-news 98-reboot-required'

# plan_file SRC DEST WHAT
# Out: "would install DEST (WHAT)" when DEST is missing or its content differs
#      from SRC. Content only: install.sh sets the mode too, but a mode alone is
#      not reported.
plan_file() {
	if ! cmp -s "$1" "$PLAN_ROOT$2"; then
		echo "would install $2 ($3)"
	fi
}

# plan_files SRC
# Out: what a plain run, or --update after a pull, would change: the banner code
#      in /usr/local/share/manatech, the two login scripts, and a missing
#      /etc/manatech/motd.conf (created from the template; never overwritten).
plan_files() {
	for _f in "$1"/usr/local/share/manatech/*; do
		plan_file "$_f" "/usr/local/share/manatech/${_f##*/}" 'banner code'
	done
	for _s in 05-manatech-banner 15-manatech-health; do
		plan_file "$1/etc/update-motd.d/$_s" "/etc/update-motd.d/$_s" 'login script'
	done
	if [ ! -e "$PLAN_ROOT/etc/manatech/motd.conf" ]; then
		echo 'would create /etc/manatech/motd.conf from the template'
	fi
}

# plan_retire
# Out: what --retire would change: a stock script still on; landscape-sysinfo
#      without its statoverride (or still on, where no package owns its file);
#      an older ENABLED=0 in /etc/default/motd-news; motd-news.timer not masked.
plan_retire() {
	for _s in $MANATECH_RETIRED; do
		if [ -x "$PLAN_ROOT/etc/update-motd.d/$_s" ]; then
			echo "would turn off /etc/update-motd.d/$_s (chmod -x)"
		fi
	done
	_link=$PLAN_ROOT/etc/update-motd.d/50-landscape-sysinfo
	if [ -e "$_link" ]; then
		_file=$(readlink -f "$_link")
		if dpkg -S "$_file" >/dev/null 2>&1; then
			if ! dpkg-statoverride --list "$_file" >/dev/null 2>&1; then
				echo "would keep landscape-sysinfo off across upgrades (a 644 statoverride on $_file)"
			fi
		elif [ -x "$_file" ]; then
			echo "would turn off landscape-sysinfo (chmod -x $_file)"
		fi
	fi
	case $(conffile_state motd-news-config "$PLAN_ROOT/etc/default/motd-news" stock_motd_news "$PLAN_ROOT/etc/default/motd-news") in
	restore) echo 'would put back the stock /etc/default/motd-news (ENABLED=1; the masked timer keeps it off)' ;;
	changed) echo 'note: /etc/default/motd-news was changed, not as this installer changes it; it stays as it is' ;;
	esac
	if [ "$(systemctl is-enabled motd-news.timer 2>/dev/null)" != masked ]; then
		echo 'would mask motd-news.timer'
	fi
}

# plan_conffile PATH STOCK ARG OURS
# Out: what --ssh does with base-files' conffile PATH, as install.sh calls
#      restore_conffile: "would put back" when it replaces an older version's
#      banner with the stock text; a "note" saying why when it leaves PATH.
plan_conffile() {
	case $(conffile_state base-files "$PLAN_ROOT$1" "$2" "$3" "$4") in
	restore) echo "would put back the stock $1" ;;
	theirs) echo "note: $1 holds someone else's text; it stays as it is, and dpkg will ask about it at the next base-files upgrade" ;;
	missing) echo "note: $1 is missing; it stays missing, and agetty shows /etc/issue.d only while /etc/issue exists" ;;
	changed) echo "note: $1 holds a banner this installer wrote, but this release's stock text is not known; it stays as it is" ;;
	esac
}

# plan_ssh SRC
# Out: what --ssh would change: our console banner in /etc/issue.d, our SSH
#      banner text in /etc/manatech, the stock /etc/issue and /etc/issue.net an
#      older version overwrote, the sshd drop-in (installed, then checked with
#      sshd -t and reloaded), and the drop-in's old name.
plan_ssh() {
	plan_file "$1/etc/issue.d/50-manatech.issue" /etc/issue.d/50-manatech.issue 'the console banner'
	plan_file "$1/etc/issue.net" /etc/manatech/issue.net 'the SSH banner'
	_pretty=$(. "$PLAN_ROOT/etc/os-release" 2>/dev/null && printf '%s' "${PRETTY_NAME-}") || _pretty=
	if [ -n "$_pretty" ]; then
		plan_conffile /etc/issue stock_issue "$_pretty" "$OURS_ISSUE"
		plan_conffile /etc/issue.net stock_issue_net "$_pretty" "$OURS_ISSUE_NET"
	fi
	plan_file "$1/etc/ssh/sshd_config.d/00-manatech-banner.conf" /etc/ssh/sshd_config.d/00-manatech-banner.conf 'the sshd drop-in; then sshd -t and a reload'
	if [ -e "$PLAN_ROOT/etc/ssh/sshd_config.d/10-manatech-banner.conf" ]; then
		echo 'would remove /etc/ssh/sshd_config.d/10-manatech-banner.conf (the old name)'
	fi
}

# plan_units GENERATOR [ARGS]
# Out: what install_units GENERATOR ARGS would write (a unit missing from
#      /etc/systemd/system, or different there), and each timer or path unit
#      it writes that is not enabled.
plan_units() {
	_gen=$1
	shift
	_tmp=$(mktemp -d)
	"$_gen" "$_tmp" "$@"
	for _f in "$_tmp"/*; do
		_unit=${_f##*/}
		if ! cmp -s "$_f" "$PLAN_ROOT/etc/systemd/system/$_unit"; then
			echo "would write /etc/systemd/system/$_unit"
		fi
		case $_unit in
		*.timer | *.path)
			if [ "$(systemctl is-enabled "$_unit" 2>/dev/null)" != enabled ]; then
				echo "would enable $_unit"
			fi
			;;
		esac
	done
	rm -f "$_tmp"/*
	rmdir "$_tmp"
}

# host_parts REPO
# Out: the install.sh options for the parts set up on this host, read from the
#      host: --retire when a stock script it turns off is off, --ssh when our
#      sshd drop-in is there (under either name), --timer when the update
#      service runs REPO's install.sh. All three print as --all.
host_parts() {
	_parts=
	for _s in $MANATECH_RETIRED; do
		if [ -e "$PLAN_ROOT/etc/update-motd.d/$_s" ] && [ ! -x "$PLAN_ROOT/etc/update-motd.d/$_s" ]; then
			_parts=--retire
			break
		fi
	done
	if [ -e "$PLAN_ROOT/etc/ssh/sshd_config.d/00-manatech-banner.conf" ] || [ -e "$PLAN_ROOT/etc/ssh/sshd_config.d/10-manatech-banner.conf" ]; then
		_parts="${_parts:+$_parts }--ssh"
	fi
	if grep -qF "$1/install.sh" "$PLAN_ROOT/etc/systemd/system/manatech-motd-update.service" 2>/dev/null; then
		_parts="${_parts:+$_parts }--timer"
	fi
	[ "$_parts" != '--retire --ssh --timer' ] || _parts=--all
	echo "$_parts"
}

# note_pending REPO SRC RUN
# Writes $PLAN_ROOT/var/lib/manatech/pending for 15-manatech-health to show at
# login: the options that bring this host's parts up to REPO's copy, the copy,
# and how many changes they would make. Removes it when none would.
# RUN is the timer's own options (--update, --ad), so the unit is judged
# against the one install.sh would write. Only for a copy whose update timer
# runs it (--timer, or --all): that timer installs new banner code but never
# runs --retire, --ssh or --timer, so without the note those fall behind
# unseen. Any other copy returns at once, and leaves a note it did not write.
note_pending() {
	_state=$PLAN_ROOT/var/lib/manatech
	_parts=$(host_parts "$1")
	case " $_parts " in
	*' --timer '* | ' --all ') ;;
	*) return 0 ;;
	esac
	_changes=$(
		case " $_parts " in *' --retire '* | ' --all ') plan_retire ;; esac
		case " $_parts " in *' --ssh '* | ' --all ') plan_ssh "$2" ;; esac
		plan_units units_clone "$1" "$3"
	)
	_count=$(printf '%s\n' "$_changes" | grep -c '^would ') || _count=0
	if [ "$_count" -eq 0 ]; then
		rm -f "$_state/pending"
		return 0
	fi
	# The timer's --ad goes into the advice too: a run without it would write
	# the unit without it.
	case " $3 " in *' --ad '*) _parts="$_parts --ad" ;; esac
	mkdir -p "$_state"
	printf 'options=%s\nrepo=%s\nchanges=%s\n' "$_parts" "$1" "$_count" >"$_state/pending.tmp"
	mv -f "$_state/pending.tmp" "$_state/pending"
}
