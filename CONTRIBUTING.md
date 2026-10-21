# Contributing

Issues and merge requests are welcome: Tyson, Claude and Yuki read every
one. A human maintainer reviews each merge request by hand, and asks for
more when a quick OK is not enough. Coding agents: `AGENTS.md` says how to
build and test here.

## A bug or an idea

Open an issue saying what you ran, what you expected, and what happened
instead. For a banner that draws wrong, say which terminal or SSH client
showed it, and add the output of the same command with `-ColorMode none`.

## A logo

A logo comes as a merge request that adds one art file:
`UsaBanner/art/base/<name>.json` for art you own, or
`UsaBanner/art/apps/<name>.json` for another owner's logo. The name is lower
case letters, digits and hyphens, and `Show-UsaBannerArt <name>` draws it.

1. **Make the art.** From an image, `New-UsaBannerArt` writes the file:

   ```powershell
   Import-Module ./UsaBanner/UsaBanner.psd1
   New-UsaBannerArt -Path ./contoso-logo.png -OutFile ./UsaBanner/art/base/contoso.json -Title 'Contoso' -Artist 'Contoso design' -Licence 'MIT' -Source 'made by New-UsaBannerArt from the Contoso logo'
   ```

   Try `-Width`, `-Colors`, `-Style` and `-Fill` until it looks right;
   `docs/IMAGE-ART.md` says what each one changes. Art drawn by hand is
   welcome too: the file's keys are described at the top of
   `UsaBanner/Private/Art.ps1`, and `UsaBanner/art/base/` has examples.

2. **For another owner's logo** (`art/apps/`): draw it yourself rather than
   copy it, and only to identify what a host runs, such as its OS or an
   application. Add two keys to the file, `owner` and `notice`, and put the
   notice as a line in `UsaBanner/NOTICE`; `UsaBanner/art/apps/README.md`
   says more. The maintainers decide whether it ships.

3. **Check it.** Every file in `UsaBanner/art/` keeps the art rules:
   printable ASCII only, at most 64 columns by 30 rows, a mask the same shape
   as the art, and a colour for every class the mask names.

   ```powershell
   Show-UsaBannerArt contoso -ColorMode none   # as it shows before login
   Show-UsaBannerArt contoso                   # in colour
   pwsh -NoProfile -Command "Invoke-Pester -Path ./tests/Art.Tests.ps1"
   ```

4. **Open the merge request**, with:
   - a sentence saying that you own the logo, or hold a licence that lets it
     be distributed under this repository's licence (MIT, see `LICENSE`);
   - the output of `Show-UsaBannerArt <name> -ColorMode none`, in a code
     block.
