# Voice.ps1 - meme voices, for a lab VM (docs/DECISIONS.md, D25). The
# configuration's voice rewrites the banner's own words: the legal box and
# its text, the welcome line, the panel's labels, the tier's meaning, all
# clear. Facts never change: names, addresses, numbers and the company stay
# as they are, so the banner still tells the truth. plain, the default, is
# no voice at all.
#
#   +--------+-----------------------------------------------------------+
#   | Voice  | Rules                                                     |
#   +--------+-----------------------------------------------------------+
#   | uwu    | r and l to w; n before a vowel at a word's start to ny.   |
#   |        | In prose, each sentence's first word stutters, and a face |
#   |        | goes before its end, the faces taken in turn              |
#   | random | whole words: the to teh, for to 4, to to 2, you to u,     |
#   |        | your to ur. In prose, an interjection follows each        |
#   |        | sentence, taken in turn                                   |
#   | leet   | capitals, then A 4, E 3, I 1, O 0, S 5, T 7. In prose, a  |
#   |        | sign-off from the BBS days ends the text                  |
#   +--------+-----------------------------------------------------------+
#
# Every rule gives ASCII, and the same text the same way every time, so a
# voice shows before login and its frames can be golden.

# Each voice's own words: the box's cap and hint (and a short hint for a top
# line that is full), the welcome line's words around the company, all
# clear, and a label for each row of the panel, nine columns at most.
$script:UsaVoices = [ordered]@{
    uwu    = @{
        Cap = '(>w<)'; Hint = 'pwease wog in fow mowe info uwu~'; ShortHint = 'wog in uwu~'
        Welcome = 'Wewcome to'; WelcomeTail = ' ^w^'; AllClear = 'aww cweaw ^w^'
        Labels = @{ schema = 'scheemy'; vlan = 'vwan'; tier = 'tiew'; os = 'os-chan'; role = 'wowe'; uptime = 'upwime'; cpu = 'cpu-kun'; memory = 'mewmowy'; disk = 'diwk'; sessions = 'fwiends'; time = 'twime'; ipv4 = 'ipv4~'; updates = 'upwates'; reboot = 'weboot'; services = 'sewvices' }
    }
    random = @{
        Cap = '*holds up spork*'; Hint = 'log in 4 moar lolz XD'; ShortHint = 'log in lolz'
        Welcome = 'OMG welcome 2'; WelcomeTail = '!!1 XD'; AllClear = 'all clear!!1 XD'
        Labels = @{ schema = 'skeema'; vlan = 'vlan lol'; tier = 'lvl'; os = 'os lolz'; role = 'job XD'; uptime = 'uptime XD'; cpu = 'brainz'; memory = 'memoriez'; disk = 'dsk'; sessions = 'peeps'; time = 'time!!1'; ipv4 = 'ipv4 :3'; updates = 'upd8z'; reboot = 'reboot!!'; services = 'servicez' }
    }
    leet   = @{
        Cap = 'k-r4d 31337'; Hint = 'N0 L4M3RZ! PH34R 7H3 5Y50P!'; ShortHint = 'L0G 1N!'
        Welcome = '\/\/3LC0M3 2'; WelcomeTail = ', D00D'; AllClear = '4LL CL34R, D00D'
        Labels = @{ schema = '5CH3M4'; vlan = 'VL4N'; tier = '713R'; os = '05'; role = 'R0L3'; uptime = 'UP71M3'; cpu = 'CPU'; memory = 'M3M0RY'; disk = 'D15K'; sessions = 'U53RZ'; time = '71M3'; ipv4 = '1PV4'; updates = 'UPD473Z'; reboot = 'R3B007'; services = '53RV1C3Z' }
    }
}

function Get-UsaBannerVoice {
    <#
    .SYNOPSIS
    A voice's own words, or $null for plain.
    .DESCRIPTION
    In:  the configuration's voice: plain, uwu, random or leet.
    Out: the voice's entry in $script:UsaVoices; $null for plain, which
         changes nothing.
    Throws on a voice it does not know, naming the ones there are.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyString()][string]$Voice = 'plain')
    if (-not $Voice -or $Voice -eq 'plain') { return $null }
    if (-not $script:UsaVoices.Contains($Voice)) { throw "UsaBanner: there is no voice called '$Voice'. There is: plain, $(@($script:UsaVoices.Keys) -join ', ')." }
    $script:UsaVoices[$Voice]
}

function ConvertTo-UsaBannerVoiced {
    <#
    .SYNOPSIS
    Text in a voice.
    .DESCRIPTION
    In:  the text, the voice, and -Prose for running sentences, such as the
         legal text.
    Out: the text by the voice's rules, in the table at the top of this
         file; with -Prose, each sentence's flourish too. A sentence ends at
         ., ! or ? before a capital letter, so "18 U.S.C. 1030" stays whole.
         plain gives the text back unchanged.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyString()][string]$Text,
        [AllowEmptyString()][string]$Voice = 'plain',
        [switch]$Prose
    )
    $null = Get-UsaBannerVoice -Voice $Voice
    $sentenceBreak = '(?<=[.!?])\s+(?=[A-Z])'
    switch ($Voice) {
        'uwu' {
            $voiced = $Text -creplace '[rl]', 'w' -creplace '[RL]', 'W'
            $voiced = [regex]::Replace($voiced, '\b([Nn])([aeiouAEIOU])', {
                    param($m)
                    $y = if ($m.Groups[2].Value -cmatch '[A-Z]') { 'Y' } else { 'y' }
                    $m.Groups[1].Value + $y + $m.Groups[2].Value
                })
            if (-not $Prose) { return $voiced }
            $faces = @('uwu', 'owo', '>w<', '^w^', 'UwU')
            $i = 0
            $sentences = foreach ($sentence in ($voiced -split $sentenceBreak)) {
                if (-not $sentence) { continue }
                $body = $sentence
                $end = ''
                if ($body -match '^(.*?)([.!?]+)$') { $body = $Matches[1]; $end = $Matches[2] }
                if ($body -cmatch '^([A-Za-z])') { $body = $Matches[1] + '-' + $body }
                "$body $($faces[$i % $faces.Count])$end"
                $i++
            }
            return ($sentences -join ' ')
        }
        'random' {
            $voiced = $Text -replace '\bthe\b', 'teh' -replace '\bfor\b', '4' -replace '\bto\b', '2' -replace '\byou\b', 'u' -replace '\byour\b', 'ur'
            if (-not $Prose) { return $voiced }
            $interjections = @('XD', 'lolz', '*holds up spork*', 'rawr!!', 'i like waffles', 'random!!1')
            $i = 0
            $sentences = foreach ($sentence in ($voiced -split $sentenceBreak)) {
                if (-not $sentence) { continue }
                "$sentence $($interjections[$i % $interjections.Count])"
                $i++
            }
            return ($sentences -join ' ')
        }
        'leet' {
            $voiced = -join @(foreach ($ch in $Text.ToUpperInvariant().ToCharArray()) {
                    switch -CaseSensitive ([string]$ch) { 'A' { '4' } 'E' { '3' } 'I' { '1' } 'O' { '0' } 'S' { '5' } 'T' { '7' } default { [string]$ch } }
                })
            if ($Prose) { $voiced += ' -=[ 0WN3D BY 7H3 5Y50P ]=-' }
            return $voiced
        }
    }
    $Text
}

function Get-UsaBannerVoiceTitle {
    <#
    .SYNOPSIS
    The legal text's title in a voice.
    .DESCRIPTION
    +--------+---------------------------------------------------+
    | Voice  | WARNING becomes                                   |
    +--------+---------------------------------------------------+
    | uwu    | W-WAWNING!! OwO: the rules, a stutter, and OwO     |
    | random | WARNING!!1!one                                     |
    | leet   | \/\/4RN1NG!!: the rules, and W written as \/\/      |
    +--------+---------------------------------------------------+
    plain gives the title back unchanged.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$Title, [AllowEmptyString()][string]$Voice = 'plain')
    $null = Get-UsaBannerVoice -Voice $Voice
    switch ($Voice) {
        'uwu' { $voiced = ConvertTo-UsaBannerVoiced -Text $Title -Voice uwu; return "$($voiced[0])-$voiced!! OwO" }
        'random' { return "$Title!!1!one" }
        'leet' { return ((ConvertTo-UsaBannerVoiced -Text $Title -Voice leet) -creplace 'W', '\/\/') + '!!' }
    }
    $Title
}

function Get-UsaBannerVoiceLabel {
    <#
    .SYNOPSIS
    A panel row's label in a voice.
    .DESCRIPTION
    In:  a label, such as uptime or "disk /var", and the voice.
    Out: the voice's word for it; a disk's mount point stays as it is, being
         a fact. A label the voice has no word for, and plain, come back
         unchanged.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()][string]$Label, [AllowEmptyString()][string]$Voice = 'plain')
    $words = Get-UsaBannerVoice -Voice $Voice
    if ($null -eq $words -or -not $Label) { return $Label }
    $word, $rest = $Label -split ' ', 2
    if (-not $words.Labels.ContainsKey($word)) { return $Label }
    if ($rest) { return "$($words.Labels[$word]) $rest" }
    $words.Labels[$word]
}
