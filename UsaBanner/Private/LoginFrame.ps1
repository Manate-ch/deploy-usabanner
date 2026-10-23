# LoginFrame.ps1 - the banner after login, pre-drawn for Linux's login
# renderer (docs/DECISIONS.md, D2). At deploy, PowerShell draws what only the
# configuration changes; at each login, linux/postlogin.sh has awk draw the
# facts into it, so a login never waits on PowerShell.
#
# The frame is text, a line each, its fields separated by tabs, the first
# saying what the line is:
#
#   +------+-------------------------------------------------------------+
#   | Kind | Holds                                                       |
#   +------+-------------------------------------------------------------+
#   | H    | a line drawn above the facts' rows: the art, the welcome    |
#   |      | line, the tier strip, the panel's top line, and its schema, |
#   |      | VLAN, tier and role rows                                    |
#   | F    | the panel's bottom line                                     |
#   | T    | a key and its value: what awk draws the facts in (below)    |
#   +------+-------------------------------------------------------------+
#
# T's keys: reset, and the escape of each style (label, value, dim, good,
# warn, bad, edge), '' where the mode draws none; the box's sides (left,
# right); the panel's glyphs (full, empty, sep, ok, markwarn, markbad); the
# voice (voice) and its word for each row awk draws (word.os ... word.services)
# and for all clear (allclear); and the sizes (width, inside, inner,
# labelmax). No drawn line holds a tab.
#
# The tier and the role come from the configuration and the host's AD
# Description (D29), so they are drawn here, never at a login: a change to
# either draws the frame again (linux/redraw.sh).

function New-UsaBannerLoginFrame {
    <#
    .SYNOPSIS
    The banner after login, pre-drawn for linux/postlogin.sh.
    .DESCRIPTION
    In:  the configuration, the OS whose colour the art takes, the host's
         name and primary address (the panel's title and badge, the schema
         and VLAN rows), the colour mode and -AsciiOnly. pam_motd gives its
         scripts no terminal to ask, so these are the host's.
    Out: the frame's lines (the table at the top of this file). What
         postlogin.sh draws from it with a host's facts is, byte for byte,
         what Get-UsaBannerPostLogon draws from the same facts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][ValidateSet('ubuntu', 'linux')][string]$Os,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$Ip = '',
        [Parameter(Mandatory)][ValidateSet('truecolor', '256', '16', 'mono', 'none')][string]$Mode,
        [switch]$AsciiOnly
    )
    $look = Resolve-UsaBannerPreset -Preset ([string]$Config['color']['preset']) -Mode $Mode
    $palette = $look.Palette
    $static = @{ Name = $Name }
    if ($Ip) { $static['Ip'] = $Ip }
    # Drawn without a fact that changes, the banner ends at the panel's
    # bottom line: what comes before it is the head.
    $lines = @(ConvertTo-UsaBannerFrameText -Block (New-UsaBannerPostLogin -Config $Config -Os $Os -Facts $static -Palette $palette -Mode $look.Mode -AsciiOnly:$AsciiOnly) -Mode $look.Mode)
    for ($i = 0; $i -lt $lines.Count - 1; $i++) { "H`t$($lines[$i])" }
    "F`t$($lines[-1])"

    $voice = [string]$Config['voice']
    $glyphs = if ($AsciiOnly) { $script:UsaPanelGlyphs['Ascii'] } else { $script:UsaPanelGlyphs['Unicode'] }
    $border = $Config['border']
    $char = if ($border['char']) { [string]$border['char'] } else { 'o' }
    $set = Get-UsaBannerBorderSet -Name ([string]$border['set']) -Char $char -AsciiOnly:$AsciiOnly
    $identity = Resolve-UsaBannerHostName -Name $Name -Naming $Config['naming']
    $edge = Get-UsaBannerPanelEdge -Palette $palette -Identity $identity -TierRow (Get-UsaBannerTier -Name ([string]$Config['environment']))
    $words = Get-UsaBannerVoice -Voice $voice
    $theme = [ordered]@{ reset = "$script:UsaEsc[0m" }
    foreach ($role in 'Label', 'Value', 'Dim', 'Good', 'Warn', 'Bad') { $theme[$role.ToLowerInvariant()] = ConvertTo-UsaBannerStyleSgr -Style $palette[$role] -Mode $look.Mode }
    $theme['edge'] = ConvertTo-UsaBannerStyleSgr -Style $edge -Mode $look.Mode
    $theme['left'] = $set.L
    $theme['right'] = $set.R
    $theme['full'] = $glyphs.Full
    $theme['empty'] = $glyphs.Empty
    $theme['sep'] = $glyphs.Sep
    $theme['ok'] = $glyphs.Ok
    $theme['markwarn'] = $glyphs.Warn
    $theme['markbad'] = $glyphs.Bad
    $theme['voice'] = if ($words) { $voice } else { 'plain' }
    foreach ($word in 'os', 'uptime', 'cpu', 'memory', 'disk', 'sessions', 'time', 'ipv4', 'updates', 'reboot', 'services') { $theme["word.$word"] = Get-UsaBannerVoiceLabel -Label $word -Voice $voice }
    $theme['allclear'] = if ($words) { $words.AllClear } else { 'all clear' }
    $theme['width'] = $script:UsaBannerWidth
    $theme['inside'] = $script:UsaBannerWidth - 5
    $theme['inner'] = $script:UsaBannerWidth - 2
    $theme['labelmax'] = $script:UsaLabelMax
    foreach ($key in $theme.Keys) { "T`t$key`t$($theme[$key])" }
}
