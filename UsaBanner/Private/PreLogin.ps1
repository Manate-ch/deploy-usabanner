# PreLogin.ps1 - the banners shown before login (docs/DECISIONS.md, D5):
#
#   +-------------+--------------------------------+------------------------+
#   | Moment      | Where                          | Drawn                  |
#   +-------------+--------------------------------+------------------------+
#   | pre-logon   | sshd's Banner file, sent       | plain ASCII (D6)       |
#   |             | before authentication          |                        |
#   | pre-init    | an /etc/issue.d file, which    | 16 colours, as agetty  |
#   |             | agetty prints at the console   | escapes                |
#   | pre-init on | the logon notice's caption and | plain text, no art     |
#   | Windows     | text                           |                        |
#   +-------------+--------------------------------+------------------------+
#
# The arrangement picked in the M2 gallery: the art on the left, the company
# name beside it in block letters (Get-UsaBannerNameForm), the host line
# under the name, and the legal box below. A name that would come out only in
# spaced capitals or as written beside the art, but in block letters on a line
# of its own, goes under the art instead. The host name and the IP show only
# where the configuration turns them on (D9).

# Stand-ins for agetty's \n (the host name) and \4 (the IPv4 address) while
# the console's frame is drawn; ConvertTo-UsaBannerIssueLine puts the escapes
# in. Control characters, so no art or text can hold them.
$script:UsaIssueHost = "$([char]1)n$([char]1)"
$script:UsaIssueAddress = "$([char]1)4$([char]1)"

function New-UsaBannerPreLogin {
    <#
    .SYNOPSIS
    The banner before login, as a block.
    .DESCRIPTION
    In:  the configuration (Read-UsaBannerConfig), the OS whose colour the
         art takes, the mode (none over SSH, 16 at the console), and the
         host line's two parts, each left out when empty.
    Out: the block, 64 columns at most: the art and the company name, the
         host line, then the legal box in the configured border set (its
         ASCII form: Classic stands in for a Unicode set), cap and voice.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu', 'linux')][string]$Os,
        [Parameter(Mandatory)][ValidateSet('none', '16')][string]$Mode,
        [AllowEmptyString()][string]$HostText = '',
        [AllowEmptyString()][string]$AddressText = ''
    )
    $edge = New-UsaBannerStyle -FgBasic (Get-UsaBannerTintColor -Tint os -Os $Os)['basic']
    $titleStyle = New-UsaBannerStyle -FgBasic 'bright-yellow' -Bold
    $hintStyle = New-UsaBannerStyle -FgBasic 'bright-black'

    $artName = [string]$Config['art']['name']
    if ($artName -eq 'os') { $artName = 'server' }
    $art = New-UsaBannerArtBlock -Art (Resolve-UsaBannerArtTint -Art (Get-UsaBannerArtData -Name $artName) -Os $Os) -Mode $Mode

    $hostLine = $null
    if ($HostText -or $AddressText) {
        $hostLine = New-UsaBannerBlock
        $spans = [System.Collections.Generic.List[object]]::new()
        if ($HostText) { $spans.Add((New-UsaBannerSpan -Text $HostText -Style (New-UsaBannerStyle -FgBasic 'bright-white' -Bold))) }
        if ($HostText -and $AddressText) { $spans.Add((New-UsaBannerSpan -Text '   ')) }
        if ($AddressText) { $spans.Add((New-UsaBannerSpan -Text $AddressText -Style (New-UsaBannerStyle -FgBasic 'bright-white'))) }
        Add-UsaBannerLine -Block $hostLine -Spans $spans.ToArray()
    }

    $company = [string]$Config['company']
    $blockForms = @('pixel', 'small', 'small2')
    $beside = $true
    $name = $null
    if ($company) {
        $room = $script:UsaBannerWidth - $art.Width - 4
        $width = $room
        if ((Get-UsaBannerNameForm -Name $company -Width $room).Form -notin $blockForms -and (Get-UsaBannerNameForm -Name $company).Form -in $blockForms) {
            $beside = $false
            $width = $script:UsaBannerWidth
        }
        $name = New-UsaBannerArtBlock -Art (ConvertTo-UsaBannerNameArt -Name $company -Width $width) -Mode $Mode
    }
    # A blank line above the host line, when there is one.
    $hostGap = if ($hostLine) { New-UsaBannerTextBlock -Lines @('') } else { $null }
    $head = if ($name -and $beside) {
        Join-UsaBannerBeside -Blocks @($art, (Join-UsaBannerStack -Blocks @($name, $hostGap, $hostLine))) -Gap 4
    }
    else {
        Join-UsaBannerStack -Blocks @($art, $(if ($name) { New-UsaBannerTextBlock -Lines @('') }), $name, $hostGap, $hostLine) -Align center
    }

    $border = $Config['border']
    $char = if ($border['char']) { [string]$border['char'] } else { 'o' }
    $legal = Get-UsaBannerLegal -Template ([string]$Config['legal']['template']) -Text @($Config['legal']['text'])
    $box = New-UsaBannerLegalBox -Legal $legal -Set (Get-UsaBannerBorderSet -Name ([string]$border['set']) -Char $char -AsciiOnly) -Cap ([string]$border['cap']) -Voice ([string]$Config['voice']) `
        -Edge $edge -TitleStyle $titleStyle -CapStyle $titleStyle -HintStyle $hintStyle
    Join-UsaBannerStack -Blocks @($head, (New-UsaBannerTextBlock -Lines @('')), $box) -Align center -Width $script:UsaBannerWidth
}

function Get-UsaBannerPreLogon {
    <#
    .SYNOPSIS
    The SSH banner: what sshd sends before authentication.
    .DESCRIPTION
    In:  the configuration, the OS, and the facts: HostName and Ip, read
         only when preLogon shows them.
    Out: its lines, plain ASCII: SSH clients strip or show raw anything
         else (D6). Anyone who starts to log in can read it (D9).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu', 'linux')][string]$Os,
        [System.Collections.IDictionary]$Facts
    )
    $hostText = if ($Config['preLogon']['hostName']) { [string]$Facts['HostName'] } else { '' }
    $addressText = if ($Config['preLogon']['ip']) { [string]$Facts['Ip'] } else { '' }
    ConvertTo-UsaBannerFrameText -Block (New-UsaBannerPreLogin -Config $Config -Os $Os -Mode none -HostText $hostText -AddressText $addressText) -Mode none
}

function Get-UsaBannerPreInit {
    <#
    .SYNOPSIS
    The console's banner: an issue file, which agetty prints before the
    login prompt.
    .DESCRIPTION
    In:  the configuration, and the OS.
    Out: the file's lines, printable ASCII: colour as agetty's \e escapes,
         every backslash of the banner doubled, and the host name and IP,
         where preInit shows them, as agetty's \n and \4, which it fills in
         when it prints.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu', 'linux')][string]$Os
    )
    $hostText = if ($Config['preInit']['hostName']) { $script:UsaIssueHost } else { '' }
    $addressText = if ($Config['preInit']['ip']) { $script:UsaIssueAddress } else { '' }
    foreach ($line in ConvertTo-UsaBannerFrameText -Block (New-UsaBannerPreLogin -Config $Config -Os $Os -Mode '16' -HostText $hostText -AddressText $addressText) -Mode '16') {
        ConvertTo-UsaBannerIssueLine -Line $line
    }
}

function Get-UsaBannerConsoleBanner {
    <#
    .SYNOPSIS
    The console's banner as agetty prints it: the issue file's frame with
    the host name and IP filled in.
    .DESCRIPTION
    In:  the configuration, the OS, the host's short name and IPv4 address,
         and the mode: 16, the console's, or none for a terminal without
         colour.
    Out: the lines, in that mode. The host name and IP show where preInit
         turns them on, as in the issue file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Config,
        [Parameter(Mandatory)][ValidateSet('windows', 'ubuntu', 'linux')][string]$Os,
        [AllowEmptyString()][string]$HostName = '',
        [AllowEmptyString()][string]$Ip = '',
        [ValidateSet('none', '16')][string]$Mode = '16'
    )
    $hostText = if ($Config['preInit']['hostName']) { $HostName } else { '' }
    $addressText = if ($Config['preInit']['ip']) { $Ip } else { '' }
    ConvertTo-UsaBannerFrameText -Block (New-UsaBannerPreLogin -Config $Config -Os $Os -Mode $Mode -HostText $hostText -AddressText $addressText) -Mode $Mode
}

function ConvertTo-UsaBannerNoticeText {
    <#
    .SYNOPSIS
    Windows' logon notice as lines to read at a terminal.
    .DESCRIPTION
    In:  the notice (Get-UsaBannerLogonNotice).
    Out: the caption, a blank line, then the text, each paragraph wrapped at
         64 columns and blank lines kept. Windows wraps the notice to its own
         dialog; these lines show what it says.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Notice)
    [string]$Notice.Caption
    ''
    foreach ($paragraph in ([string]$Notice.Text -split "`r`n")) {
        if (-not $paragraph.Trim()) {
            ''
            continue
        }
        ConvertTo-UsaBannerWrapped -Text $paragraph -Width $script:UsaBannerWidth
    }
}

function ConvertTo-UsaBannerIssueLine {
    <#
    .SYNOPSIS
    One line of a drawn banner as agetty reads it from an issue file.
    .DESCRIPTION
    agetty takes every backslash in an issue file as an escape, and for one
    it does not know prints the next character and drops the backslash
    (util-linux 2.39, term-utils/agetty.c, output_special_char), so:
    - each backslash is written \\, which prints one;
    - each escape character becomes \e, which agetty prints as ESC: the
      colour escapes reach the console exactly as drawn;
    - the stand-ins for the host name and IP become \n and \4.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Line)
    $Line.Replace('\', '\\').Replace([string][char]27, '\e').Replace($script:UsaIssueHost, '\n').Replace($script:UsaIssueAddress, '\4')
}

function Get-UsaBannerLogonNotice {
    <#
    .SYNOPSIS
    Windows' logon notice: the caption and the text that policy shows before
    a console or RDP sign-in (D5).
    .DESCRIPTION
    In:  the configuration.
    Out: @{ Caption; Text }: the legal text's title, and its paragraphs
         joined by CRLF; Windows wraps the text itself. A voice rewrites
         both, as it does the box.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $voice = [string]$Config['voice']
    $legal = Get-UsaBannerLegal -Template ([string]$Config['legal']['template']) -Text @($Config['legal']['text'])
    $paragraphs = foreach ($paragraph in $legal.Paragraphs) {
        if ($paragraph.Trim()) { ConvertTo-UsaBannerVoiced -Text $paragraph -Voice $voice -Prose } else { '' }
    }
    @{ Caption = (Get-UsaBannerVoiceTitle -Title $legal.Title -Voice $voice); Text = (@($paragraphs) -join "`r`n") }
}
