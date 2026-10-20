# art/apps

Other owners' logos, drawn by us and never copied (docs/DECISIONS.md, D3):
the OS logos and application logos, shown only to identify what a host runs.
Each piece is a JSON file like those in `../base/`, with two more keys:

- `owner`: whose trademark the logo is;
- `notice`: the line NOTICE carries for it.

A host shows one only where an admin turned it on: the default art is ours,
from `../base/`. `Show-UsaBannerArt -List` shows each one with its owner.
Keeping them in this folder means that, if an owner objects, it can go
without touching anything else.

What ships, each with its line in `../../NOTICE`:

- `tux.json`: Tux sitting, after Larry Ewing's Tux (drawn with The GIMP);
- `windows.json`: the Windows logo, four panes;
- `ubuntu.json`: the Ubuntu Circle of Friends.

Tux and the Circle of Friends were drawn from our own description of their
shapes, at 2 x 4 dots a character, the density of Braille art, in plain
ASCII.
