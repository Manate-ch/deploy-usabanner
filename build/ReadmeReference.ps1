# ReadmeReference.ps1 - README.md's command reference, built from the commands' own help (docs/DECISIONS.md,
# D27): a jump list, then a section for each command in the style of learn.microsoft.com's. Dot-sourced by
# build/Update-UsaBannerReadme.ps1, which writes it into README.md, and by tests/Docs.Tests.ps1, which fails
# when the two differ. Import the module first.

$ReferenceBegin = '<!-- command reference: begin. build/Update-UsaBannerReadme.ps1 writes what is between these two lines, from the commands'' help: edit the help, then run it -->'
$ReferenceEnd = '<!-- command reference: end -->'

function ConvertTo-ReferenceInline {
    # In:  a line of help text, which Get-Help shows as written
    # Out: that line in Markdown that GitLab and GitHub show as the same text: what Markdown reads as a tag
    #      (<version>), emphasis, a link, a table cell or a reference (#12, @name) is escaped with a backslash,
    #      and so is what would start a heading, a list or a rule
    param([string]$Text)
    $out = $Text.Trim() -replace '([\\`*_\[\]<>|])', '\$1'
    $out = $out -replace '([#!@~%$&^])(?=[0-9A-Za-z])', '\$1'
    if ($out -match '^(#{1,6}|[-+]|=+|-+)(\s|$)') { $out = '\' + $out }
    elseif ($out -match '^\d{1,9}[.)](\s|$)') { $out = $out -replace '^(\d{1,9})([.)])', '$1\$2' }
    $out
}

function ConvertTo-ReferenceBlock {
    # In:  help text as Get-Help gives it: paragraphs apart by a blank line, a list as lines that start with "- "
    #      (an item's further lines indented), a table drawn with +, - and |
    # Out: its Markdown lines, a blank line between a paragraph and a list either side of it, which Markdown
    #      would otherwise run together; a drawn table as a block of text, kept as drawn
    param([string]$Text)
    $out = [System.Collections.Generic.List[string]]::new()
    $kind = ''
    foreach ($line in @($Text -split '\r?\n')) {
        $line = $line.TrimEnd()
        $next = if (-not $line) { '' }
        elseif ($line -match '^[+|]') { 'table' }
        elseif ($line -match '^- ') { 'list' }
        elseif ($kind -eq 'list' -and $line -match '^\s') { 'list' }
        else { 'paragraph' }
        if ($next -ne $kind) {
            if ($kind -eq 'table') { $out.Add('```') }
            if ($next -and $out.Count) { $out.Add('') }
            if ($next -eq 'table') { $out.Add('```text') }
        }
        if ($next -eq 'table') { $out.Add($line) }
        elseif ($next -eq 'list') { $out.Add($(if ($line -match '^- ') { '- ' + (ConvertTo-ReferenceInline $line.Substring(2)) } else { '  ' + (ConvertTo-ReferenceInline $line) })) }
        elseif ($next) { $out.Add((ConvertTo-ReferenceInline $line)) }
        $kind = $next
    }
    if ($kind -eq 'table') { $out.Add('```') }
    $out.ToArray()
}

function Get-ReferenceHeadingId {
    # In:  Markdown lines, and whose rules: GitLab's, or GitHub's (VS Code's preview follows GitHub's)
    # Out: for each heading outside a code block, in order, its line's index and the id a link reaches it by. A
    #      heading's text the second time gets -1, the third -2, under both
    # Why: GitLab drops a run of - to one, and GitHub keeps it; a link must reach its heading on both
    param([string[]]$Lines, [ValidateSet('GitLab', 'GitHub')][string]$Rules)
    $seen = @{}
    $fence = ''
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line -match '^ {0,3}(`{3,}|~{3,})') {
            if (-not $fence) { $fence = $Matches[1].Substring(0, 3) }
            elseif ($Matches[1].StartsWith($fence)) { $fence = '' }
            continue
        }
        if ($fence -or $line -notmatch '^ {0,3}#{1,6}[ \t]+(.+?)[ \t]*$') { continue }
        # The text the heading shows: no closing #s, no code marks, a link's text alone, no escapes.
        $text = $Matches[1] -replace '[ \t]+#+$', '' -replace '`', '' -replace '\[([^\]]*)\]\([^)]*\)', '$1' -replace '\\([!-/:-@\[-`{-~])', '$1'
        $id = $text.Trim().ToLowerInvariant()
        if ($Rules -eq 'GitLab') {
            $id = $id -replace '[^\p{L}\p{M}\p{Nd}\p{Pc} -]', '' -replace ' ', '-' -replace '-{2,}', '-'
            if ($id -match '^\d+$') { $id = "anchor-$id" }
        }
        else { $id = $id -replace '[^\p{L}\p{M}\p{Nd}\p{Nl}_ -]', '' -replace ' ', '-' }
        $n = [int]$seen[$id]
        $seen[$id] = $n + 1
        [pscustomobject]@{ Line = $i; Id = $(if ($n) { "$id-$n" } else { $id }) }
    }
}

function Get-ReferenceParameterYaml {
    # In:  a parameter as Get-Command has it, and its default as Get-Help gives it
    # Out: learn.microsoft.com's block of what it takes, one for each group of sets it is the same in
    param([System.Management.Automation.ParameterMetadata]$Parameter, [string]$Default)
    $accepted = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | ForEach-Object { $_.ValidValues })
    $wildcards = @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.SupportsWildcardsAttribute] }).Count -gt 0
    $groups = @($Parameter.ParameterSets.GetEnumerator() | Sort-Object Key | Group-Object { $m = $_.Value; "$($m.IsMandatory)|$($m.Position)|$($m.ValueFromPipeline)|$($m.ValueFromPipelineByPropertyName)" })
    foreach ($group in $groups) {
        $m = $group.Group[0].Value
        $sets = @($group.Group | ForEach-Object Key)
        $pipeline = @(if ($m.ValueFromPipelineByPropertyName) { 'ByPropertyName' }; if ($m.ValueFromPipeline) { 'ByValue' })
        '```yaml'
        "Type: $($Parameter.ParameterType.Name)"
        "Parameter Sets: $(if ($sets -contains '__AllParameterSets') { '(All)' } else { $sets -join ', ' })"
        'Aliases:' + $(if ($Parameter.Aliases.Count) { ' ' + ($Parameter.Aliases -join ', ') })
        if ($accepted.Count) { "Accepted values: $($accepted -join ', ')" }
        ''
        "Required: $($m.IsMandatory)"
        "Position: $(if ($m.Position -ge 0) { $m.Position } else { 'Named' })"
        "Default value: $(if ($Default) { $Default } else { 'None' })"
        "Accept pipeline input: $(if ($pipeline.Count) { 'True (' + ($pipeline -join ', ') + ')' } else { 'False' })"
        "Accept wildcard characters: $wildcards"
        '```'
        ''
    }
}

function New-UsaBannerReference {
    # In:  README.md's lines before the reference: a heading there numbers one of the same text in the
    #      reference, as GitLab and GitHub number a heading's second use
    # Out: the reference's lines, its two markers first and last
    param([string[]]$Preceding = @())
    $standard = @{
        WhatIf  = 'Shows what would happen if the command runs. The command is not run.'
        Confirm = 'Prompts you for confirmation before running the command.'
    }
    $body = [System.Collections.Generic.List[string]]::new()
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($command in @(Get-Command -Module UsaBanner -CommandType Function | Sort-Object Name)) {
        $help = Get-Help $command.Name -Full
        $entry = [pscustomobject]@{ Name = $command.Name; Line = $body.Count; Synopsis = "$($help.Synopsis)"; Parameters = [System.Collections.Generic.List[object]]::new() }
        $targets.Add($entry)
        $body.Add("### $($command.Name)")
        $body.Add('')
        $body.AddRange([string[]]@(ConvertTo-ReferenceBlock $entry.Synopsis))
        $body.Add('')
        $body.Add('#### Syntax')
        $body.Add('')
        $sets = @($command.ParameterSets | Sort-Object { -not $_.IsDefault })
        foreach ($set in $sets) {
            if ($sets.Count -gt 1) {
                $body.Add("**$($set.Name)$(if ($set.IsDefault) { ' (Default)' })**")
                $body.Add('')
            }
            # The set's syntax as Get-Command -Syntax gives it.
            $body.AddRange([string[]]@('```', "$($command.Name) $set", '```', ''))
        }
        $body.Add('#### Description')
        $body.Add('')
        $body.AddRange([string[]]@(ConvertTo-ReferenceBlock ((@($help.description) | ForEach-Object Text) -join "`n`n")))
        $body.Add('')
        $body.Add('#### Examples')
        $body.Add('')
        $number = 0
        foreach ($example in @($help.examples.example)) {
            $number++
            $body.AddRange([string[]]@("**Example $number**", '', '```powershell', "$($example.code)".Trim(), '```', ''))
            $remarks = ((@($example.remarks) | ForEach-Object Text) -join "`n").Trim()
            if ($remarks) { $body.AddRange([string[]]@(ConvertTo-ReferenceBlock $remarks)); $body.Add('') }
        }
        $body.Add('#### Parameters')
        $body.Add('')
        $skip = @([System.Management.Automation.Cmdlet]::CommonParameters) + @([System.Management.Automation.Cmdlet]::OptionalCommonParameters)
        $names = @($command.Parameters.Keys | Where-Object { $skip -notcontains $_ }) + @('WhatIf', 'Confirm' | Where-Object { $command.Parameters.ContainsKey($_) })
        foreach ($name in $names) {
            $entry.Parameters.Add([pscustomobject]@{ Name = $name; Line = $body.Count })
            $body.Add("##### -$name")
            $body.Add('')
            $parameterHelp = Get-Help $command.Name -Parameter $name
            $text = if ($standard.ContainsKey($name)) { $standard[$name] } else { (@($parameterHelp.description) | ForEach-Object Text) -join "`n`n" }
            $body.AddRange([string[]]@(ConvertTo-ReferenceBlock $text))
            $body.Add('')
            $default = if ($standard.ContainsKey($name)) { 'False' } else { "$($parameterHelp.defaultValue)".Trim() }
            $body.AddRange([string[]]@(Get-ReferenceParameterYaml -Parameter $command.Parameters[$name] -Default $default))
        }
        $body.Add('##### CommonParameters')
        $body.Add('')
        $body.Add('This command takes the common parameters too, such as -Verbose and -ErrorAction: `Get-Help about_CommonParameters` says what each does.')
        $body.Add('')
    }

    # The ids each heading gets, counting the README's headings before the reference and the reference's own.
    $head = @($ReferenceBegin, '## Command reference')
    $ids = @{}
    foreach ($heading in @(Get-ReferenceHeadingId -Lines (@($Preceding) + $head + $body.ToArray()) -Rules GitLab)) { $ids[$heading.Line] = $heading.Id }
    $offset = @($Preceding).Count + $head.Count
    $jump = foreach ($entry in $targets) {
        "- [$($entry.Name)](#$($ids[$offset + $entry.Line])): " + ((@(ConvertTo-ReferenceBlock $entry.Synopsis) | Where-Object { $_ }) -join ' ')
        '  - ' + ((@($entry.Parameters) | ForEach-Object { "[-$($_.Name)](#$($ids[$offset + $_.Line]))" }) -join ', ')
    }
    @($head) + @(
        ''
        'The module''s commands and every flag they take, from each command''s own help, which `Get-Help <command> -Full` shows too.'
        ''
    ) + @($jump) + @('') + $body.ToArray() + @($ReferenceEnd)
}
