# postlogin.awk - the banner after login on Linux (docs/DECISIONS.md, D2):
# the frame Deploy-UsaBanner pre-drew (Private/LoginFrame.ps1), with the
# facts linux/facts.sh gives (D26) drawn into it as the module draws them
# (Private/PostLogin.ps1), byte for byte: a row per fact, a label nine
# columns wide, a value cut to the room left, then the health lines and the
# notices.
#
#   USABANNER_FRAME=FRAME LC_ALL=C awk -F '\t' -f postlogin.awk [RECORDS]
#
# POSIX awk only: Ubuntu's is mawk. Under LC_ALL=C it counts bytes, so a
# width counts a character by its first byte, leaving out UTF-8's
# continuation bytes, 0x80 to 0xBF.

# width TEXT - its columns: its characters, each one wide.
function width(s,   t) { t = s; gsub(CONT, "", t); return length(t) }

# first TEXT N - its first N characters.
function first(s, n,   i, c, out, k, keep) {
	out = ""; k = 0; keep = 0
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c ~ CONT) { if (keep) out = out c; continue }
		if (++k > n) break
		keep = 1
		out = out c
	}
	return out
}

# rest TEXT N - what follows its first N characters.
function rest(s, n) { return substr(s, length(first(s, n)) + 1) }

function spaces(n,   s) { s = ""; while (n-- > 0) s = s " "; return s }
function repeat(s, n,   out) { out = ""; while (n-- > 0) out = out s; return out }

# pad TEXT N - TEXT, with spaces after it to N columns.
function pad(s, n) { return s spaces(n - width(s)) }

# number FIELD - the whole number it holds, or "" for none.
function number(f) { return (f ~ /^-?[0-9]+$/) ? f + 0 : "" }

function percent_style(p, from) { p += 0; return p >= 95 ? T["bad"] : (p >= from ? T["warn"] : T["good"]) }
function level_style(l) { l = tolower(l); return l == "bad" ? T["bad"] : (l == "warn" ? T["warn"] : T["good"]) }

# A line is spans, each text in one style's escape; emit prints them with
# an escape only where the style changes and a reset at the end of a line
# that ends in a style (ConvertTo-UsaBannerFrameText).
function span(text, sgr) { ns++; st[ns] = text; ss[ns] = sgr }
function emit(   i, out, active) {
	out = ""; active = ""
	for (i = 1; i <= ns; i++) {
		if (st[i] == "") continue
		if (ss[i] != active) {
			if (active != "") out = out T["reset"]
			if (ss[i] != "") out = out ss[i]
			active = ss[i]
		}
		out = out st[i]
	}
	if (active != "") out = out T["reset"]
	print out
	ns = 0
}

# A row is given its value's spans, then spans of detail that go first when
# the row is too wide; row draws it and starts the next.
function value(text, sgr) { nv++; vt[nv] = text; vs[nv] = sgr; nt = nv }
function detail(text, sgr) { nt++; vt[nt] = text; vs[nt] = sgr }
function row(label,   lt, room, total, i, used, w, left) {
	lt = label
	if (width(lt) > LABELMAX) lt = first(lt, LABELMAX - 1) "~"
	lt = pad(lt, 9)
	room = INSIDE - width(lt) - 1
	total = 0
	for (i = 1; i <= nt; i++) total += width(vt[i])
	span(T["left"], T["edge"]); span("  ", ""); span(lt, T["label"]); span(" ", "")
	used = 0
	if (total > room) {
		# Limit-UsaBannerLine: the value's spans that fit whole, then the
		# first that does not, cut to the columns left, ending in ~.
		for (i = 1; i <= nv; i++) {
			w = width(vt[i])
			if (used + w <= room) { span(vt[i], vs[i]); used += w; continue }
			left = room - used
			if (left > 0) { span(first(vt[i], left - 1) "~", vs[i]); used += left }
			break
		}
	} else {
		for (i = 1; i <= nt; i++) { span(vt[i], vs[i]); used += width(vt[i]) }
	}
	span(spaces(INNER - 2 - width(lt) - 1 - used), ""); span(T["right"], T["edge"])
	emit()
	nv = 0; nt = 0
}

# The 24-hour range, when both ends are known (D17).
function range(mn, mx) { if (mn != "" && mx != "") detail("  24h " mn "-" mx "%", T["dim"]) }
function range_value(mn, mx) { if (mn != "" && mx != "") value("  24h " mn "-" mx "%", T["dim"]) }

# usage LABEL PCT MIN MAX TEXT KIND FROM - memory or a disk: a ten-cell bar,
# the percentage, the size, and the range as detail.
function usage(label, pct, mn, mx, text, kind, from,   p, full, size) {
	p = pct + 0
	full = int((p + 5) / 10)
	if (full < 0) full = 0
	if (full > 10) full = 10
	size = text
	if (kind != "") size = size "  " kind
	value(repeat(T["full"], full), percent_style(p, from))
	value(repeat(T["empty"], 10 - full), T["dim"])
	value(" ", "")
	value(pct "%", percent_style(p, from))
	value("  " size, T["value"])
	range(mn, mx)
	row(label)
}

# wrap TEXT N - into WL[1..], N columns at most, between words; a word wider
# than that is cut into pieces that fit (ConvertTo-UsaBannerWrapped).
function wrap(text, n,   k, i, words, cur, word, count) {
	count = split(text, words, /[ \t\r\n\f\v]+/)
	k = 0; cur = ""
	for (i = 1; i <= count; i++) {
		word = words[i]
		if (word == "") continue
		while (width(word) > n) {
			if (cur != "") { WL[++k] = cur; cur = "" }
			WL[++k] = first(word, n)
			word = rest(word, n)
		}
		if (cur == "") cur = word
		else if (width(cur) + 1 + width(word) <= n) cur = cur " " word
		else { WL[++k] = cur; cur = word }
	}
	if (cur != "") WL[++k] = cur
	return k
}

# health - each problem, wrapped under itself; else all clear with the
# checks that ran; nothing when nothing was checked.
function health(   p, bad, mark, indent, k, j, clear, room, cur, c, nxt) {
	if (np == 0 && nc == 0) return
	print ""
	for (p = 1; p <= np; p++) {
		bad = tolower(plevel[p]) == "bad"
		mark = bad ? T["markbad"] : T["markwarn"]
		indent = 3 + width(mark)
		k = wrap(ptext[p], WIDTH - indent)
		for (j = 1; j <= k; j++) {
			if (j == 1) { span("  ", ""); span(mark, bad ? T["bad"] : T["warn"]); span(" ", "") }
			else span(spaces(indent), "")
			span(WL[j], T["value"])
			emit()
		}
	}
	if (np > 0) return
	clear = T["ok"] " " T["allclear"]
	indent = 2 + width(clear) + 3
	room = WIDTH - indent
	k = 0; cur = ""
	for (c = 1; c <= nc; c++) {
		nxt = (cur != "") ? cur " " T["sep"] " " check[c] : check[c]
		if (width(nxt) > room && cur != "") { CL[++k] = cur; cur = check[c] }
		else cur = nxt
	}
	if (cur != "") CL[++k] = cur
	span("  ", ""); span(clear, T["good"])
	if (k > 0) span("   " CL[1], T["dim"])
	emit()
	for (j = 2; j <= k; j++) { span(spaces(indent), ""); span(CL[j], T["dim"]); emit() }
}

# notices - each line about the banner itself, as the update channel's
# (D14), wrapped two columns in, under a line of its own.
function notices(   n, k, j) {
	if (nn == 0) return
	print ""
	for (n = 1; n <= nn; n++) {
		k = wrap(note[n], WIDTH - 2)
		for (j = 1; j <= k; j++) { span("  ", ""); span(WL[j], T["label"]); emit() }
	}
}

BEGIN {
	CONT = "[" sprintf("%c", 128) "-" sprintf("%c", 191) "]"
	frame = ENVIRON["USABANNER_FRAME"]
	while ((getline line < frame) > 0) {
		kind = substr(line, 1, 2)
		if (kind == "H\t") head[++nh] = substr(line, 3)
		else if (kind == "F\t") foot = substr(line, 3)
		else if (kind == "T\t") {
			key = substr(line, 3)
			key = substr(key, 1, index(key, "\t") - 1)
			T[key] = substr(line, length(key) + 4)
		}
	}
	close(frame)
	# Numbers, not text: a number compared with text is compared as text.
	WIDTH = T["width"] + 0; INSIDE = T["inside"] + 0; INNER = T["inner"] + 0; LABELMAX = T["labelmax"] + 0
}

# The records (D26): the last of a kind wins, as in the module; disks,
# addresses, problems, checks and notices are kept in order.
NF == 0 { next }
$1 == "os" { os = $2; next }
$1 == "uptime" { uptime = $2; next }
$1 == "sessions" { sessions = $2; next }
$1 == "time" { time = $2; next }
$1 == "cpu" { has_cpu = 1; cpu_now = number($2); cpu_min = number($3); cpu_max = number($4); cpu_text = $5; next }
$1 == "memory" { has_mem = 1; mem_pct = number($2); mem_min = number($3); mem_max = number($4); mem_text = $5; mem_kind = $6; next }
$1 == "disk" { nd++; dname[nd] = $2; dpct[nd] = number($3); dmin[nd] = number($4); dmax[nd] = number($5); dtext[nd] = $6; dkind[nd] = $7; next }
$1 == "ipv4" { na++; aname[na] = $2; aaddr[na] = $3; next }
$1 == "updates" { has_upd = 1; upd_text = $2; upd_level = $3; next }
$1 == "reboot" { has_reb = 1; reb_text = $2; reb_level = $3; next }
$1 == "services" { if (NF >= 3) { has_svc = 1; svc_text = $2; svc_level = $3 }; next }
$1 == "problem" { if (NF >= 3 && $3 != "") { np++; plevel[np] = $2; ptext[np] = $3 }; next }
$1 == "check" { if (NF >= 2 && $2 != "") check[++nc] = $2; next }
$1 == "notice" { if (NF >= 2 && $2 != "") note[++nn] = $2; next }

END {
	if (frame == "" || nh == 0) exit
	for (i = 1; i <= nh; i++) print head[i]

	if (os != "") { value(os, T["value"]); row(T["word.os"]) }
	if (uptime != "") { value(uptime, T["value"]); row(T["word.uptime"]) }
	if (has_cpu) {
		value(cpu_now "%", percent_style(cpu_now, 85))
		range_value(cpu_min, cpu_max)
		if (cpu_text != "") detail("  " cpu_text, T["value"])
		row(T["word.cpu"])
	}
	if (has_mem) usage(T["word.memory"], mem_pct, mem_min, mem_max, mem_text, mem_kind, 90)
	for (i = 1; i <= nd; i++) {
		# The voice's word for disk; the mount point stays as it is, being a fact.
		label = "disk " dname[i]
		if (T["voice"] != "plain") label = (dname[i] != "") ? T["word.disk"] " " dname[i] : T["word.disk"]
		usage(label, dpct[i], dmin[i], dmax[i], dtext[i], dkind[i], 85)
	}
	if (sessions != "") { value(sessions, T["value"]); row(T["word.sessions"]) }
	if (time != "") { value(time, T["value"]); row(T["word.time"]) }
	label = T["word.ipv4"]
	for (i = 1; i <= na; i++) {
		value(pad(aname[i], 10) " " aaddr[i], T["value"])
		row(label)
		label = ""
	}
	if (has_upd) { value(upd_text, level_style(upd_level)); row(T["word.updates"]) }
	if (has_reb) { value(reb_text, level_style(reb_level)); row(T["word.reboot"]) }
	if (has_svc) { value(svc_text, level_style(svc_level)); row(T["word.services"]) }
	print foot
	health()
	notices()
}
