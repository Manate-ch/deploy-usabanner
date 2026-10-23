# bootstrap.ps1 - the second half of bootstrap.sh, which runs it with pwsh -File: it
# imports the module this file belongs to, and runs Deploy-UsaBanner with the flags
# bootstrap.sh was given. pwsh -File hands over each value as one string, a list too
# (-Services ssh,cron arrives as 'ssh,cron'), so the values of the flags that take a list
# of names are split at their commas. Every other value goes as it came: legal text of
# your own, whose lines may hold commas, comes from a configuration file (-Path).

$ErrorActionPreference = 'Stop'
Import-Module -Name (Join-Path $PSScriptRoot '..' 'UsaBanner.psd1')
$lists = @('-Services', '-PreInit', '-PreLogon')
$flags = @(for ($i = 0; $i -lt $args.Count; $i++) {
        if ($i -gt 0 -and $args[$i - 1] -in $lists -and $args[$i] -is [string]) {
            # The comma keeps the list one value: the flag's.
            , [string[]]@($args[$i] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }
        else { $args[$i] }
    })
Deploy-UsaBanner @flags
