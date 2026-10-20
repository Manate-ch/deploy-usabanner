# fonts

Block-letter fonts for the company name, drawn by us (docs/DECISIONS.md,
D3). Each is a JSON file named for the font, holding:

- `title`, `artist`, `licence` and `source`, as for art;
- `height`, the rows in every glyph, and `gap`, the columns between two;
- `glyphs`: each character's rows, all as wide as each other, in printable
  ASCII. Every capital, every digit and a space are required; a lower-case
  letter is drawn as its capital.

`Show-UsaBannerArt -Text 'Contoso LLC'` sets a name in the Pixel font, in
the welcome line's colours from left to right. A name may come out at most
64 columns wide, as any art may.
