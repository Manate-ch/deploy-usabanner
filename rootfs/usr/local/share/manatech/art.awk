# art.awk - print an art file in colour, with a top-to-bottom gradient.
#
# Usage: awk -v mode=MODE -f colour.awk -f art.awk ART ART
#   ART is read twice: the first pass counts lines and finds which lines use
#   the second colour, so each colour's gradient spans exactly its own rows.
#
# Every line starts in colour "c" (the moon: pale cyan fading to deep blue).
# The marker @y switches to colour "y" (the emblem: pale gold fading to
# orange) and @c switches back. Markers are removed from the output.

function pos(i, first, last) { return (last > first) ? (i - first) / (last - first) : 0 }

NR == FNR {
	n = FNR
	if (index($0, "@y")) {
		if (!yfirst) yfirst = FNR
		ylast = FNR
	}
	next
}

{
	t = pos(FNR, 1, n)
	c = fg(mix(175, 30, t), mix(235, 95, t), mix(255, 210, t), "0;36")
	u = pos(FNR, yfirst, ylast)
	y = fg(255, mix(238, 135, u), mix(150, 20, u), "1;33")
	line = $0
	gsub(/@c/, c, line)
	gsub(/@y/, y, line)
	print c line ((mode == "none") ? "" : sprintf("%c[0m", 27))
}
