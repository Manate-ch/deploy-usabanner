# colour.awk - colour functions shared by art.awk and schema.awk. Load it
# first: awk -v mode=MODE -f colour.awk -f art.awk ...
# MODE is truecolor, 256, 16 or none (COLOR in motd.conf).

# cube(r, g, b) - the xterm-256 colour-cube index nearest to an RGB colour.
function cube(r, g, b) {
	return 16 + 36 * int((r * 5 + 127) / 255) + 6 * int((g * 5 + 127) / 255) + int((b * 5 + 127) / 255)
}

# fg(r, g, b, basic) - foreground escape in MODE; BASIC is the SGR code used
# in 16-colour mode, e.g. "0;36".
function fg(r, g, b, basic) {
	if (mode == "truecolor") return sprintf("%c[38;2;%d;%d;%dm", 27, r, g, b)
	if (mode == "256") return sprintf("%c[38;5;%dm", 27, cube(r, g, b))
	if (mode == "16") return sprintf("%c[%sm", 27, basic)
	return ""
}

# mix(a, b, t) - a blended toward b by t (0..1), rounded.
function mix(a, b, t) { return int(a + (b - a) * t + 0.5) }
