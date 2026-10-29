# Contributing

Issues and pull requests are welcome: Tyson, Claude and Yuki read every
one. A human maintainer reviews each pull request by hand, and asks for
more when a quick OK is not enough. Coding agents: `AGENTS.md` says how to
build and test here.

This repository is a mirror: the maintainers work in their own GitLab, and
it pushes here. A pull request is reviewed here, then merged there with its
commits as you wrote them, and arrives back with the next push; GitHub then
shows it closed rather than merged.

## A bug or an idea

Open an issue saying what you ran, what you expected, and what happened
instead. For a banner that draws wrong, say which terminal or SSH client
showed it, and add the output of the same command with `-ColorMode none`.

## A logo

A logo comes as a pull request that adds one art file:
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
   Then list the file in `FileList` in `UsaBanner/UsaBanner.psd1`, in its
   place in ordinal order (capitals before lower case): the tests hold the
   module's folder to that list, and a deploy copies only what it names
   (`docs/DECISIONS.md`, D32).

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

4. **Open the pull request**, with:
   - a sentence saying that you own the logo, or hold a licence that lets it
     be distributed under this repository's licence (MIT, see `LICENSE`);
   - the output of `Show-UsaBannerArt <name> -ColorMode none`, in a code
     block.

### A logo you keep

A logo you cannot, do not or will not contribute stays yours: make the file
with `New-UsaBannerArt -OutFile ./contoso-logo.json` anywhere outside the
module, look at it with `Show-UsaBannerArt -Path ./contoso-logo.json`, and
deploy with `-ArtPath ./contoso-logo.json`. The art goes into your
configuration, never into the module, and reaches every host the
configuration does, through Group Policy too (`docs/DECISIONS.md`, D31). It
keeps the art rules of step 3, and no two of its colour classes may differ
only in case. Keep the file, and your configuration, outside the module's
folder: a deploy leaves out a file its manifest does not list, and the Group
Policy publish refuses the folder (D32).
