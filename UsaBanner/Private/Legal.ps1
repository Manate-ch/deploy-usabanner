# Legal.ps1 - the legal text shown before login (docs/DECISIONS.md, D8): the
# five templates or the admin's own, and the box it sits in.
#
# The box's top line holds the text's title on the left and a hint on the
# right, as the gallery of M2 picked (D8): the title is the word the text
# would open with, so the text drops it. The configuration's border.cap, an
# ASCII face such as (^_^), sits centred between the two.

# D8's templates, word for word, with the title each box carries.
$script:UsaLegalTemplates = [ordered]@{
    L1 = @{ Title = 'HELLO'; Text = "Hey there. This is a private home machine. Please don't hack me, buddy." }
    L2 = @{ Title = 'PRIVATE'; Text = 'Private system. Authorized users only. If you are not supposed to be here, please disconnect now.' }
    L3 = @{ Title = 'WARNING'; Text = 'WARNING: This system is for authorized use only. Activity on this system is monitored and recorded. Unauthorized access or use is prohibited.' }
    L4 = @{ Title = 'WARNING'; Text = 'WARNING: AUTHORIZED USE ONLY. Unauthorized access to this computer system is prohibited and may be a crime under state and federal law, including the Computer Fraud and Abuse Act, 18 U.S.C. 1030. All activity is monitored and logged, and evidence of unauthorized use may be given to law enforcement.' }
    L5 = @{ Title = 'ATTENTION'; Text = 'ATTENTION: THIS IS A PRIVATE COMPUTER SYSTEM. ACCESS IS LIMITED TO AUTHORIZED USERS FOR AUTHORIZED PURPOSES. BY CONTINUING, YOU CONSENT TO THE MONITORING, RECORDING AND SEARCH OF ALL ACTIVITY AND DATA ON THIS SYSTEM, AND YOU HAVE NO EXPECTATION OF PRIVACY IN IT. UNAUTHORIZED ACCESS OR USE IS A CRIME UNDER 18 U.S.C. 1030 (THE COMPUTER FRAUD AND ABUSE ACT) AND OTHER LAWS, AND WILL BE REPORTED TO LAW ENFORCEMENT.' }
}

# The right of the top line: logging in shows the rest of the banner.
$script:UsaLegalHint = 'Log in for more information'

function Get-UsaBannerLegal {
    <#
    .SYNOPSIS
    The legal text to show, and its title.
    .DESCRIPTION
    In:  a template, L1 to L5 or custom, and for custom the admin's lines
         (the configuration's legal.text).
    Out: @{ Title; Paragraphs }. A template is one paragraph; its title is
         the word it opens with (WARNING, ATTENTION), or for L1 and L2,
         which open with none, HELLO and PRIVATE. The text drops a lead such
         as "WARNING: " that its title already says.
         The admin's own text keeps its lines as paragraphs, an empty line
         as a blank one. A first line that opens with a word in capitals and
         a colon, such as "PRIVATE: ", gives the title; NOTICE otherwise.
    Throws when custom has no text, and on a line that is not printable
    ASCII: the text shows before login (D6).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][ValidateSet('L1', 'L2', 'L3', 'L4', 'L5', 'custom')][string]$Template,
        [AllowEmptyString()][string[]]$Text = @()
    )
    if ($Template -ne 'custom') {
        $entry = $script:UsaLegalTemplates[$Template]
        $body = $entry.Text
        if ($body.StartsWith("$($entry.Title): ")) { $body = $body.Substring($entry.Title.Length + 2) }
        return @{ Title = $entry.Title; Paragraphs = @($body) }
    }
    $lines = @($Text | Where-Object { $null -ne $_ })
    if (@($lines | Where-Object { $_.Trim() }).Count -eq 0) { throw 'UsaBanner: legal.template is custom, but legal.text holds no text.' }
    foreach ($line in $lines) {
        if ($line -cnotmatch '^[ -~]*$') { throw "UsaBanner: the legal text shows before login, so printable ASCII only: '$line'." }
    }
    $title = 'NOTICE'
    $first = 0
    while (-not $lines[$first].Trim()) { $first++ }
    if ($lines[$first] -cmatch '^\s*([A-Z][A-Z -]{0,15}[A-Z]):\s*(.*)$') {
        $title = $Matches[1]
        $lines[$first] = $Matches[2]
    }
    @{ Title = $title; Paragraphs = $lines }
}

function New-UsaBannerLegalBox {
    <#
    .SYNOPSIS
    The legal text in its box.
    .DESCRIPTION
    In:  the text (Get-UsaBannerLegal), the border set
         (Get-UsaBannerBorderSet), the cap for the middle of the top line,
         the box's width, and the styles of the border, the title, the cap
         and the hint.
    Out: the box as a block, exactly -Width wide: the title on the left of
         the top line, the hint on its right, the cap centred between them,
         and the text wrapped to the room inside, a blank line above and
         below it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][hashtable]$Legal,
        [Parameter(Mandatory)][hashtable]$Set,
        [AllowEmptyString()][string]$Cap = '',
        [int]$Width = $script:UsaBannerWidth,
        [System.Collections.IDictionary]$Edge,
        [System.Collections.IDictionary]$TitleStyle,
        [System.Collections.IDictionary]$CapStyle,
        [System.Collections.IDictionary]$HintStyle
    )
    $room = $Width - 6
    $lines = foreach ($paragraph in $Legal.Paragraphs) {
        if ($paragraph.Trim()) { ConvertTo-UsaBannerWrapped -Text $paragraph -Width $room } else { '' }
    }
    $middle = if ($Cap) { @(New-UsaBannerLabel -Text $Cap -Style $CapStyle) } else { @() }
    New-UsaBannerBox -Sections @(New-UsaBannerTextBlock -Lines @($lines)) -Set $Set -Width $Width -Edge $Edge `
        -LeftLabel @(New-UsaBannerLabel -Text $Legal.Title -Style $TitleStyle) -MiddleLabel $middle `
        -RightLabel @(New-UsaBannerLabel -Text $script:UsaLegalHint -Style $HintStyle)
}
