# schema.awk - decode a host name with the naming schema in schema-names.tsv:
# <site:2><type><subtype><os>-<name><number>, e.g. h-vsl-web1 is
# HQ / Virtual / Server / Linux. The site is two characters, site letter then
# sub-site letter or "-" (h- = HQ, cw = Cloud West in the example rows).
#
# Usage: awk -v host=NAME -v mode=MODE -v by=FIELD \
#            -f colour.awk -f schema.awk colors.tsv schema-names.tsv
# Prints three lines:
#   1. the border colour: the colour of FIELD's code (site, type, subtype or
#      os), or empty
#   2. NAME in bold, with each schema letter in its field's colour
#   3. the decoded fields, "HQ / Virtual / Server / Linux"
#   4. the site name alone, "HQ", or empty if the site code is unknown
# A NAME that does not follow the schema gives empty lines 1, 3 and 4 and a
# plain bold line 2. An unknown code decodes as "?".

BEGIN { FS = "\t" }

/^#/ || NF < 4 { next }

FILENAME == ARGV[1] { rgb[$1] = $3 " " $4 " " $5; basic[$1] = $6; next }

{ name[$1 SUBSEP tolower($2)] = $3; colour[$1 SUBSEP tolower($2)] = $4 }

# tint(field, code) - the escape for that code's colour, or "" if it has none.
function tint(field, code,    k, p) {
	k = field SUBSEP code
	if (!(k in colour) || !(colour[k] in rgb)) return ""
	split(rgb[colour[k]], p, " ")
	return fg(p[1], p[2], p[3], basic[colour[k]])
}

# letter(field, i) - character i of the short name, tinted with the colour of
# field's code in this name.
function letter(field, i,    e) {
	e = tint(field, code(field))
	return (e == "") ? substr(short, i, 1) : e substr(short, i, 1) rst bold
}

# code(field) - field's code in this name: two characters for site, one otherwise.
function code(field) { return substr(h, at[field], (field == "site") ? 2 : 1) }

END {
	bold = (mode == "none") ? "" : sprintf("%c[1m", 27)
	rst = (mode == "none") ? "" : sprintf("%c[0m", 27)
	short = host
	sub(/\..*/, "", short)
	h = tolower(short)
	if (h !~ /^[a-z0-9][a-z0-9-][a-z0-9][a-z0-9][a-z0-9]-.*[0-9]$/) {
		print ""; print bold host rst; print ""; print ""
		exit
	}
	# Character position of each field's code in the name.
	split("site type subtype os", f, " ")
	at["site"] = 1; at["type"] = 3; at["subtype"] = 4; at["os"] = 5
	desc = ""
	for (i = 1; i <= 4; i++) {
		k = f[i] SUBSEP code(f[i])
		desc = desc ((i > 1) ? " / " : "") ((k in name) ? name[k] : "?")
	}
	print (by in at) ? tint(by, code(by)) : ""
	print bold letter("site", 1) letter("site", 2) letter("type", 3) letter("subtype", 4) letter("os", 5) substr(host, 6) rst
	print desc
	k = "site" SUBSEP code("site")
	print (k in name) ? name[k] : ""
}
