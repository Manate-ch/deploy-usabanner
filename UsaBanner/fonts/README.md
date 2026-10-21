# fonts

Block-letter fonts for the company name, drawn by us (docs/DECISIONS.md,
D3). Each is a JSON file named for the font, holding:

- `title`, `artist`, `licence` and `source`, as for art;
- `height`, the rows in every glyph, and `gap`, the columns between two;
- `glyphs`: each character's rows, all as wide as each other, in printable
  ASCII. Every capital, every digit and a space are required; a lower-case
  letter is drawn as its capital.

There are two:

- **Pixel** (`pixel.json`): five rows, the company name's first choice.
- **Small** (`small.json`): three rows of lines and bars, for a name too wide
  for Pixel.

`Show-UsaBannerArt -Text 'Contoso LLC'` sets a name as the banner does, in
the welcome line's colours from left to right: in Pixel when it fits 64
columns; else in Small, on two lines if it must; else in spaced capitals;
else as written. `-Font pixel` or `-Font small` sets it in that font alone,
and then a name may come out at most 64 columns wide, as any art may.
