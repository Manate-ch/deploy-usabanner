# motd-lib.sh - settings, colours and layout helpers for the Manatech MOTD.
#
# Sourced (not run) by /etc/update-motd.d/05-manatech-banner and
# 15-manatech-health. pam_motd runs those as root under dash with an empty
# environment, so this file is POSIX sh and assumes no locale: every string
# whose width gets measured must be ASCII, because ${#var} counts bytes.
#
# MANATECH_ROOT (demo only) prefixes every path so the repo can be rendered
# without installing. MANATECH_CONF (demo only) points at another motd.conf.

MT_ROOT=${MANATECH_ROOT:-}
MT_SHARE=$MT_ROOT/usr/local/share/manatech
MT_CONF=${MANATECH_CONF:-$MT_ROOT/etc/manatech/motd.conf}

# Defaults. motd.conf may override any of these.
ENV_NAME=UNSET      # PROD, LAB, DEV, TEST, STAGE, or anything (grey badge)
ROLE=               # one line describing what this host is for; blank = no row
WATCH=              # space-separated service names that must be active
COLOR=truecolor     # truecolor, 256, 16 or none
GLYPHS=unicode      # unicode or ascii (for a client that is not UTF-8)
DISK_WARN=85        # percent used at which a local filesystem is reported
MEM_WARN=90         # percent of memory in use at which it is reported
IFACE_HIDE='^(docker|br-|veth|virbr|lxcbr|cni|flannel)'  # ERE; matching interfaces are not listed
BORDER_BY=type      # schema field whose colour draws the border: site, type, subtype, os, or none
BADGE=site-vlan     # top-right badge: site-vlan ("HQ - 40-Servers") or env (ENV_NAME)
ENV_SHOW="strip row" # where the environment shows: strip (above the panel), row (env row), both, or none

# motd.conf is read as data, never sourced: KEY=VALUE lines, known keys only,
# one pair of surrounding quotes stripped, the rest of the line is the value.
# So `ROLE=Grafana server` (unquoted) is the role "Grafana server" instead of
# a command named "server", and nothing in the file can run.
if [ -r "$MT_CONF" ]; then
	while IFS= read -r _line || [ -n "$_line" ]; do
		case $_line in *=*) ;; *) continue ;; esac
		_key=${_line%%=*} _val=${_line#*=}
		case $_key in '' | *[!A-Z_]*) continue ;; esac
		case $_val in
		\"*\") _val=${_val#\"} _val=${_val%\"} ;;
		\'*\') _val=${_val#\'} _val=${_val%\'} ;;
		esac
		case $_key in
		ENV_NAME | ROLE | WATCH | COLOR | GLYPHS | DISK_WARN | MEM_WARN | IFACE_HIDE | BORDER_BY | BADGE | ENV_SHOW)
			eval "$_key=\$_val" ;;
		esac
	done <"$MT_CONF"
fi
case $DISK_WARN in '' | *[!0-9]*) DISK_WARN=85 ;; esac
case $MEM_WARN in '' | *[!0-9]*) MEM_WARN=90 ;; esac

# demo.sh previews other variants through these; pam_motd never sets them.
COLOR=${MANATECH_COLOR:-$COLOR}
GLYPHS=${MANATECH_GLYPHS:-$GLYPHS}
ENV_NAME=${MANATECH_ENV:-$ENV_NAME}

# This computer's AD Description, cached by ad-description.sh (install.sh
# --ad): "<ENV>: <role>" gives the environment and the role, a Description
# without a letters-only prefix is the role alone. Spaces and tabs around
# the Description, the prefix and the colon do not count ("PROD : role" is
# PROD), as in Windows' Get-ManatechConfig. motd.conf wins for either:
# an ENV_NAME other than UNSET, a non-empty ROLE. MANATECH_AD_DESC is demo.sh's
# ad=TEXT preview ("-" = an empty Description); pam_motd never sets it.
AD_DESC=
if [ -n "${MANATECH_AD_DESC:-}" ]; then
	[ "$MANATECH_AD_DESC" = - ] || AD_DESC=$MANATECH_AD_DESC
elif [ -r "$MT_ROOT/var/lib/manatech/ad-description" ]; then
	IFS= read -r AD_DESC <"$MT_ROOT/var/lib/manatech/ad-description" || true
fi
# _ws: a space and a tab. ${v#"${v%%[!$_ws]*}"} drops v's leading run of
# them, ${v%"${v##*[!$_ws]}"} its trailing run.
_ws=$(printf ' \t')
_d=${AD_DESC#"${AD_DESC%%[!$_ws]*}"}
_d=${_d%"${_d##*[!$_ws]}"}
AD_ENV= AD_ROLE=$_d
case $_d in
[A-Za-z]*:*)
	_p=${_d%%:*}
	_p=${_p%"${_p##*[!$_ws]}"}
	case $_p in
	*[!A-Za-z]*) ;;
	*)
		AD_ENV=$(printf '%s' "$_p" | tr a-z A-Z)
		AD_ROLE=${_d#*:}
		AD_ROLE=${AD_ROLE#"${AD_ROLE%%[!$_ws]*}"}
		;;
	esac
	;;
esac

ENV_SRC= ROLE_SRC=
if [ "$ENV_NAME" != UNSET ]; then ENV_SRC=motd.conf
elif [ -n "$AD_ENV" ]; then ENV_NAME=$AD_ENV ENV_SRC="AD Description"; fi
if [ -n "$ROLE" ]; then ROLE_SRC=motd.conf
elif [ -n "$AD_ROLE" ]; then ROLE=$AD_ROLE ROLE_SRC="AD Description"; fi

ESC=$(printf '\033')
RST="$ESC[0m" MT_BOLD="$ESC[1m"
[ "$COLOR" = none ] && RST= MT_BOLD=

# Inner width of the summary panel, in columns. 62 matches the art, and the
# full panel (64) fits an 80-column terminal.
W=62

if [ "$GLYPHS" = ascii ]; then
	G_TL=+ G_TR=+ G_BL=+ G_BR=+ G_H=- G_V='|'
	G_FULL='#' G_EMPTY='.' G_OK='[ok]' G_WARN='[!!]' G_BAD='[XX]' G_SEP='-'
else
	G_TL='╭' G_TR='╮' G_BL='╰' G_BR='╯' G_H='─' G_V='│'
	G_FULL='━' G_EMPTY='─' G_OK='✔' G_WARN='▲' G_BAD='✖' G_SEP='·'
fi

# mt_cube R G B - the xterm-256 colour-cube index nearest to an RGB colour.
mt_cube() {
	echo $((16 + 36 * (($1 * 5 + 127) / 255) + 6 * (($2 * 5 + 127) / 255) + ($3 * 5 + 127) / 255))
}

# mt_fg R G B BASIC - foreground escape for an RGB colour in the COLOR mode.
# BASIC is the SGR code used in 16-colour mode, e.g. "0;36" or "1;33".
mt_fg() {
	case $COLOR in
	truecolor) printf '%s[38;2;%d;%d;%dm' "$ESC" "$1" "$2" "$3" ;;
	256) printf '%s[38;5;%dm' "$ESC" "$(mt_cube "$1" "$2" "$3")" ;;
	16) printf '%s[%sm' "$ESC" "$4" ;;
	esac
}

# mt_bg R G B BASIC - background escape; BASIC as for mt_fg, e.g. "43;30".
mt_bg() {
	case $COLOR in
	truecolor) printf '%s[48;2;%d;%d;%dm' "$ESC" "$1" "$2" "$3" ;;
	256) printf '%s[48;5;%dm' "$ESC" "$(mt_cube "$1" "$2" "$3")" ;;
	16) printf '%s[%sm' "$ESC" "$4" ;;
	esac
}

# mt_rep TEXT COUNT - TEXT repeated COUNT times (TEXT may be multibyte).
mt_rep() {
	_i=0 _s=
	while [ "$_i" -lt "$2" ]; do _s=$_s$1; _i=$((_i + 1)); done
	printf '%s' "$_s"
}

# mt_grad TEXT R1 G1 B1 R2 G2 B2 BASIC - TEXT (ASCII) coloured with a
# left-to-right gradient; in 16-colour mode, all of it in BASIC.
mt_grad() {
	case $COLOR in
	truecolor | 256)
		awk -v s="$1" -v mode="$COLOR" -v a="$2 $3 $4" -v b="$5 $6 $7" 'BEGIN {
			split(a, p); split(b, q); n = length(s)
			for (i = 1; i <= n; i++) {
				t = (n > 1) ? (i - 1) / (n - 1) : 0
				r = int(p[1] + (q[1] - p[1]) * t + 0.5)
				g = int(p[2] + (q[2] - p[2]) * t + 0.5)
				v = int(p[3] + (q[3] - p[3]) * t + 0.5)
				if (mode == "truecolor") printf "%c[38;2;%d;%d;%dm", 27, r, g, v
				else printf "%c[38;5;%dm", 27, 16 + 36 * int((r * 5 + 127) / 255) + 6 * int((g * 5 + 127) / 255) + int((v * 5 + 127) / 255)
				printf "%s", substr(s, i, 1)
			}
			printf "%c[0m", 27
		}'
		;;
	16) printf '%s[%sm%s%s' "$ESC" "$8" "$1" "$RST" ;;
	*) printf '%s' "$1" ;;
	esac
}

# Environment colour: envs.tsv names a colors.tsv colour for ENV_NAME, or the
# * row for any other. MT_ENV_BG + MT_ENV_FG (black or white text, by
# brightness) draw the strip, the env tag and a badge whose VLAN has no colour
# code; MT_EDGE is the border for a host name outside the naming schema.
set -- $(awk -F '\t' -v e="$ENV_NAME" '
	FNR == NR { if ($0 !~ /^#/ && NF >= 2) { if ($1 == e) want = $2; if ($1 == "*") dflt = $2 }; next }
	$0 !~ /^#/ && $1 == (want != "" ? want : dflt) { print $3, $4, $5, $6; exit }
' "$MT_SHARE/envs.tsv" "$MT_SHARE/colors.tsv" 2>/dev/null)
[ $# -eq 4 ] || set -- 140 145 155 90
MT_ENV_BG=$(mt_bg "$1" "$2" "$3" $(($4 + 10)))
if [ $((($1 * 299 + $2 * 587 + $3 * 114) / 1000)) -gt 140 ]; then
	MT_ENV_FG=$(mt_fg 20 20 20 30)
else
	MT_ENV_FG=$(mt_fg 255 255 255 97)
fi
MT_EDGE=$(mt_fg "$1" "$2" "$3" "$4")
set --

MT_LABEL=$(mt_fg 120 200 235 "0;36")
MT_DIM=$(mt_fg 110 120 135 "0;90")
MT_GOOD=$(mt_fg 110 210 140 "0;32")
MT_WARN=$(mt_fg 255 190 60 "0;33")
MT_BAD=$(mt_fg 240 80 80 "1;31")

# mt_level PERCENT WARN - the colour for a usage percentage: good below WARN,
# warn from WARN, bad from 95.
mt_level() {
	if [ "$1" -ge 95 ]; then printf '%s' "$MT_BAD"
	elif [ "$1" -ge "$2" ]; then printf '%s' "$MT_WARN"
	else printf '%s' "$MT_GOOD"; fi
}

# mt_bar PERCENT WARN - a 10-cell meter, coloured by mt_level. Always 10 columns.
mt_bar() {
	_f=$((($1 + 5) / 10))
	[ "$_f" -gt 10 ] && _f=10
	printf '%s%s%s%s%s' "$(mt_level "$1" "$2")" "$(mt_rep "$G_FULL" "$_f")" \
		"$MT_DIM" "$(mt_rep "$G_EMPTY" $((10 - _f)))" "$RST"
}

# mt_mem_pct - percent of memory in use (MemTotal - MemAvailable).
mt_mem_pct() {
	awk '/^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 }
		END { if (t) printf "%d", (t - a) * 100 / t; else print 0 }' /proc/meminfo
}
