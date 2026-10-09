# vlan.awk - find the VLAN an IPv4 address is in, from vlans.tsv (the VLAN
# table). The longest matching prefix wins.
#
# Usage: awk -v ip=A.B.C.D -f vlan.awk vlans.tsv
# Prints "vlan<TAB>site<TAB>mini<TAB>colour code<TAB>short<TAB>cidr" for the
# match, or nothing.

# toint(s) - a dotted IPv4 address as a number, or -1 if it is not one.
function toint(s,    p) {
	if (split(s, p, ".") != 4) return -1
	return ((p[1] * 256 + p[2]) * 256 + p[3]) * 256 + p[4]
}

BEGIN { FS = "\t"; addr = toint(ip); best = -1 }

/^#/ || NF < 6 { next }

{
	split($2, c, "/")
	bits = c[2] + 0
	size = 2 ^ (32 - bits)
	net = toint(c[1])
	if (addr >= 0 && net >= 0 && int(addr / size) == int(net / size) && bits > best) {
		best = bits
		out = $1 FS $4 FS $5 FS $3 FS $6 FS $2
	}
}

END { if (out != "") print out }
