#!/bin/sh
# demo.sh - render the MOTD from this repo the way pam_motd runs it (every
# script in rootfs/etc/update-motd.d, in order), without installing anything.
#
# Options, any order:
#   truecolor | 256 | 16 | none     colour mode (default: from demo/motd.conf)
#   ascii                           ASCII glyphs instead of box drawing
#   prod | lab | dev | test | unset preview another environment badge
#   faults                          add sample problems to the health block
#   as=NAME                         render as if this host were named NAME
#                                   (previews the schema colours)
#   ip=A.B.C.D                      use this as the primary address (VLAN badge)
#   conf=NAME                       use demo/NAME.conf (conf=tricky: values that
#                                   sourcing would get wrong or run; conf=ad: no
#                                   ENV or ROLE, so the AD Description decides)
#   ad=TEXT                         this computer's AD Description, e.g.
#                                   "ad=PROD: Hyper-V host" (ad=- : empty)

here=$(cd "$(dirname "$0")" && pwd)
MANATECH_ROOT=$here/rootfs
MANATECH_CONF=$here/demo/motd.conf
export MANATECH_ROOT MANATECH_CONF

for a in "$@"; do
	case $a in
	truecolor | 256 | 16 | none) MANATECH_COLOR=$a && export MANATECH_COLOR ;;
	ascii) MANATECH_GLYPHS=ascii && export MANATECH_GLYPHS ;;
	prod | lab | dev | test | stage | pub | unset) MANATECH_ENV=$(echo "$a" | tr a-z A-Z) && export MANATECH_ENV ;;
	ad=*) MANATECH_AD_DESC=${a#ad=} && export MANATECH_AD_DESC ;;
	faults) MANATECH_DEMO_FAULTS=1 && export MANATECH_DEMO_FAULTS ;;
	as=*) MANATECH_HOST=${a#as=} && export MANATECH_HOST ;;
	ip=*) MANATECH_IP=${a#ip=} && export MANATECH_IP ;;
	conf=*) MANATECH_CONF=$here/demo/${a#conf=}.conf ;;
	*) echo "demo.sh: unknown option: $a" >&2 && exit 2 ;;
	esac
done

for f in "$here"/rootfs/etc/update-motd.d/*; do
	sh "$f"
done
