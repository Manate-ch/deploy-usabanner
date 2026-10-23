#!/bin/sh
# update.sh - the update job (docs/DECISIONS.md, D14), once a day as root,
# where the configuration turns the update channel on. The module looks for a
# newer release at the configured source, and says so at login or installs it
# (Update-UsaBannerRelease, UsaBanner/Private/Update.ps1).

exec pwsh -NoProfile -NonInteractive -Command '& (Import-Module UsaBanner -PassThru) { Update-UsaBannerRelease }'
