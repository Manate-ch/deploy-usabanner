# art/apps

Other owners' logos, drawn by us and never copied (docs/DECISIONS.md, D3):
the OS logos and application logos, shown only to identify what a host runs.
Each piece is a JSON file like those in `../base/`, with two more keys:

- `owner`: whose trademark the logo is;
- `notice`: the line NOTICE carries for it.

A host shows one only where an admin turned it on: the default art is ours,
from `../base/`. `Show-UsaBannerArt -List` shows each one with its owner.
Keeping them in this folder means that, if an owner objects, it can go
without touching anything else. None is shipped yet.
