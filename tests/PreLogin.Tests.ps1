# The banners before login (UsaBanner/Private/PreLogin.ps1, docs/DECISIONS.md
# D5 and D9): the SSH banner, the console's issue file and Windows' logon
# notice, for a made-up Contoso host. Whole frames are checked against
# tests/frames (Golden.ps1).

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force
    . (Join-Path $PSScriptRoot 'Golden.ps1')
    $schema = Get-Content -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'config' 'usabanner.schema.json') -Raw | ConvertFrom-Json -AsHashtable
    $sets = $schema['properties']['border']['properties']['set']['enum']
    $voices = $schema['properties']['voice']['enum']

    function Invoke-PreLogin {
        # In:  the moment (logon, init, notice or frame16), changes to the default
        #      configuration as 'a.b' = value, and the OS
        # Out: what that moment draws for Contoso's made-up host; frame16 is the
        #      console's frame as drawn, the host line as HOST and ADDR
        # Why: each test states only what it changes
        param([string]$Moment, [hashtable]$Change = @{}, [string]$Os = 'ubuntu')
        InModuleScope UsaBanner -Parameters @{ Moment = $Moment; Change = $Change; Os = $Os } {
            param($Moment, $Change, $Os)
            $config = Get-UsaBannerConfigDefault
            $config['company'] = 'Contoso'
            foreach ($key in $Change.Keys) {
                $parts = $key.Split('.')
                $node = $config
                for ($i = 0; $i -lt $parts.Count - 1; $i++) { $node = $node[$parts[$i]] }
                $node[$parts[-1]] = $Change[$key]
            }
            switch ($Moment) {
                'logon' { @(Get-UsaBannerPreLogon -Config $config -Os $Os -Facts @{ HostName = 'h-vsl-web1'; Ip = '10.20.40.80' }) }
                'init' { @(Get-UsaBannerPreInit -Config $config -Os $Os) }
                'notice' { Get-UsaBannerLogonNotice -Config $config }
                'frame16' { @(ConvertTo-UsaBannerFrameText -Block (New-UsaBannerPreLogin -Config $config -Os $Os -Mode '16' -HostText 'HOST' -AddressText 'ADDR') -Mode '16') }
            }
        }
    }

    function ConvertFrom-AgettyIssue {
        # In:  a line of an issue file
        # Out: what agetty prints for it: \\ as one backslash, \e as ESC, \n as
        #      HOST and \4 as ADDR, and any other escaped character as itself
        #      (util-linux 2.39, term-utils/agetty.c, output_special_char)
        # Why: the file is right only if agetty's reading gives back the frame drawn
        param([string]$Line)
        $out = [System.Text.StringBuilder]::new()
        for ($i = 0; $i -lt $Line.Length; $i++) {
            if ($Line[$i] -ne '\') { [void]$out.Append($Line[$i]); continue }
            $i++
            switch -CaseSensitive ([string]$Line[$i]) {
                'e' { [void]$out.Append([char]27) }
                'n' { [void]$out.Append('HOST') }
                '4' { [void]$out.Append('ADDR') }
                default { [void]$out.Append($Line[$i]) }
            }
        }
        $out.ToString()
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'the SSH banner' {
    It 'is <Name>, as its golden frame shows' -ForEach @(
        @{ Name = 'prelogon-default'; Change = @{} }
        @{ Name = 'prelogon-host-ip'; Change = @{ 'preLogon.hostName' = $true; 'preLogon.ip' = $true } }
        @{ Name = 'prelogon-long-name'; Change = @{ 'company' = 'Contoso Pharmaceuticals' } }
        @{ Name = 'prelogon-no-company'; Change = @{ 'company' = '' } }
        @{ Name = 'prelogon-uwu'; Change = @{ 'border.set' = 'Rounded'; 'voice' = 'uwu' } }
    ) {
        $lines = Invoke-PreLogin -Moment logon -Change $Change
        foreach ($line in $lines) {
            $line | Should -MatchExactly '^[ -~]*$'
            $line.Length | Should -BeLessOrEqual 64 -Because $line
        }
        Assert-UsaBannerGoldenFrame -Name $Name -Lines $lines
    }

    It 'shows the host name and IP only where the configuration turns them on (D9)' {
        (Invoke-PreLogin -Moment logon) -join "`n" | Should -Not -Match 'h-vsl-web1|10\.20\.40\.80'
        (Invoke-PreLogin -Moment logon -Change @{ 'preLogon.hostName' = $true }) -join "`n" | Should -Match 'h-vsl-web1'
        (Invoke-PreLogin -Moment logon -Change @{ 'preLogon.hostName' = $true }) -join "`n" | Should -Not -Match '10\.20\.40\.80'
        (Invoke-PreLogin -Moment logon -Change @{ 'preLogon.ip' = $true }) -join "`n" | Should -Match '10\.20\.40\.80'
    }

    It 'is printable ASCII within 64 columns in every border set and every voice' {
        $problems = foreach ($set in $sets) {
            foreach ($voice in $voices) {
                foreach ($line in Invoke-PreLogin -Moment logon -Change @{ 'border.set' = $set; 'voice' = $voice; 'company' = 'Contoso Systems' }) {
                    if ($line -cnotmatch '^[ -~]*$') { "${set} ${voice}: not ASCII: $line" }
                    if ($line.Length -gt 64) { "${set} ${voice}: $($line.Length) columns" }
                }
            }
        }
        @($problems) | Should -BeNullOrEmpty
    }
}

Describe 'the console''s issue file' {
    It 'is <Name>: colour as \e escapes, the host name and IP as \n and \4, as its golden frame shows' -ForEach @(
        @{ Name = 'preinit-default'; Change = @{} }
        @{ Name = 'preinit-leet-bevel'; Change = @{ 'voice' = 'leet'; 'border.set' = 'Bevel' } }
    ) {
        $lines = Invoke-PreLogin -Moment init -Change $Change
        foreach ($line in $lines) { $line | Should -MatchExactly '^[ -~]*$' }
        Assert-UsaBannerGoldenFrame -Name $Name -Lines $lines
    }

    It 'is printed by agetty as the frame drawn, every backslash kept: <Case>' -ForEach @(
        @{ Case = 'the defaults'; Change = @{} }
        @{ Case = 'leet in Bevel, backslashes in the title and the corners'; Change = @{ 'voice' = 'leet'; 'border.set' = 'Bevel' } }
        @{ Case = 'a name in the Small font, backslashes in its letters'; Change = @{ 'company' = 'Contoso Systems' } }
        @{ Case = 'OneChar drawn with a backslash'; Change = @{ 'border.set' = 'OneChar'; 'border.char' = '\' } }
    ) {
        $issue = @(Invoke-PreLogin -Moment init -Change $Change)
        $drawn = @(Invoke-PreLogin -Moment frame16 -Change $Change)
        @($issue | ForEach-Object { ConvertFrom-AgettyIssue $_ }) | Should -BeExactly $drawn
    }

    It 'is printable ASCII, and printed by agetty as the frame drawn, in every border set and every voice' {
        $problems = foreach ($set in $sets) {
            foreach ($voice in $voices) {
                $change = @{ 'border.set' = $set; 'voice' = $voice; 'company' = 'Contoso Systems' }
                $issue = @(Invoke-PreLogin -Moment init -Change $change)
                $drawn = @(Invoke-PreLogin -Moment frame16 -Change $change)
                foreach ($line in $issue) { if ($line -cnotmatch '^[ -~]*$') { "${set} ${voice}: not ASCII: $line" } }
                if ((@($issue | ForEach-Object { ConvertFrom-AgettyIssue $_ }) -join "`n") -cne ($drawn -join "`n")) { "${set} ${voice}: agetty prints another frame" }
            }
        }
        @($problems) | Should -BeNullOrEmpty
    }

    It 'leaves the host name and IP out where preInit turns them off' {
        $lines = Invoke-PreLogin -Moment init -Change @{ 'preInit.hostName' = $false; 'preInit.ip' = $false }
        ($lines -join "`n") | Should -Not -Match '\\n|\\4'
    }
}

Describe 'the Windows logon notice' {
    It 'is the legal text''s title as the caption, and its text, which Windows wraps' {
        $notice = Invoke-PreLogin -Moment notice
        $notice.Caption | Should -BeExactly 'WARNING'
        $notice.Text | Should -BeExactly 'This system is for authorized use only. Activity on this system is monitored and recorded. Unauthorized access or use is prohibited.'
    }

    It 'keeps the admin''s paragraphs, joined by CRLF' {
        $notice = Invoke-PreLogin -Moment notice -Change @{ 'legal.template' = 'custom'; 'legal.text' = @('PRIVATE: Contoso staff only.', '', 'Questions go to example.com.') }
        $notice.Caption | Should -BeExactly 'PRIVATE'
        $notice.Text | Should -BeExactly "Contoso staff only.`r`n`r`nQuestions go to example.com."
    }

    It 'speaks in the configured voice' {
        $notice = Invoke-PreLogin -Moment notice -Change @{ 'voice' = 'uwu' }
        $notice.Caption | Should -BeExactly 'W-WAWNING!! OwO'
        $notice.Text | Should -BeLikeExactly 'T-This system is fow authowized use onwy uwu.*'
    }
}
