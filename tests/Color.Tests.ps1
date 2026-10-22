# Which colour mode a terminal gets: the order of the sources, and what each
# terminal signal means.

BeforeAll {
    Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'UsaBanner' 'UsaBanner.psd1') -Force
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'choosing the colour mode' {
    It '<Case>' -ForEach @(
        @{ Case = 'a mode asked for wins over everything'; Requested = '16'; HostMode = 'truecolor'; Vars = @{ USABANNER_COLOR = 'none'; COLORTERM = 'truecolor' }; Expected = '16' }
        @{ Case = 'USABANNER_COLOR wins over NO_COLOR and the host''s mode'; HostMode = '256'; Vars = @{ USABANNER_COLOR = 'truecolor'; NO_COLOR = '1' }; Expected = 'truecolor' }
        @{ Case = 'USABANNER_COLOR in any case'; Vars = @{ USABANNER_COLOR = 'TrueColor' }; Expected = 'truecolor' }
        @{ Case = 'NO_COLOR means mono, over the host''s mode: no colour, bold and reverse kept (D7)'; HostMode = 'truecolor'; Vars = @{ NO_COLOR = '1' }; Expected = 'mono' }
        @{ Case = 'an empty NO_COLOR counts as not set'; Vars = @{ NO_COLOR = ''; TERM = 'xterm-256color' }; Expected = '256' }
        @{ Case = 'the host''s mode wins over the terminal''s signals'; HostMode = 'truecolor'; Vars = @{ TERM = 'xterm-256color' }; Expected = 'truecolor' }
        @{ Case = 'COLORTERM=truecolor'; Vars = @{ COLORTERM = 'truecolor'; TERM = 'xterm' }; Expected = 'truecolor' }
        @{ Case = 'COLORTERM=24bit'; Vars = @{ COLORTERM = '24bit' }; Expected = 'truecolor' }
        @{ Case = 'WT_SESSION, set by Windows Terminal'; Vars = @{ WT_SESSION = '5c3fd1d2-3e41-4b8f-9d0a-0e3f2a1b7c66' }; Expected = 'truecolor' }
        @{ Case = 'TERM=dumb'; Vars = @{ TERM = 'dumb' }; Expected = 'none' }
        @{ Case = 'TERM=xterm-256color'; Vars = @{ TERM = 'xterm-256color' }; Expected = '256' }
        @{ Case = 'TERM=screen-256color'; Vars = @{ TERM = 'screen-256color' }; Expected = '256' }
        @{ Case = 'TERM=xterm'; Vars = @{ TERM = 'xterm' }; Expected = '16' }
        @{ Case = 'TERM=linux, the Linux console'; Vars = @{ TERM = 'linux' }; Expected = '16' }
        @{ Case = 'no TERM on Windows: its console and sshd pass 24-bit colour'; Vars = @{}; Windows = $true; Expected = 'truecolor' }
        @{ Case = 'no TERM elsewhere: not a terminal'; Vars = @{}; Expected = 'none' }
    ) {
        $arguments = @{
            Requested   = $(if ($Requested) { $Requested } else { 'auto' })
            HostMode    = $(if ($HostMode) { $HostMode } else { 'auto' })
            Environment = $Vars
            OnWindows   = [bool]$Windows
        }
        InModuleScope UsaBanner -Parameters $arguments {
            param($Requested, $HostMode, $Environment, $OnWindows)
            Resolve-UsaBannerColorMode -Requested $Requested -HostMode $HostMode -Environment $Environment -OnWindows $OnWindows
        } | Should -BeExactly $Expected
    }

    It 'ignores a USABANNER_COLOR it does not know, and says so' {
        $result = InModuleScope UsaBanner {
            $mode = Resolve-UsaBannerColorMode -Environment @{ USABANNER_COLOR = 'rainbow'; TERM = 'xterm' } -OnWindows $false -WarningVariable warned -WarningAction SilentlyContinue
            @{ Mode = $mode; Warned = "$warned" }
        }
        $result.Mode | Should -BeExactly '16'
        $result.Warned | Should -BeLike "*USABANNER_COLOR is 'rainbow'. It takes truecolor, 256, 16 or none*"
    }

    It 'draws art plain under NO_COLOR: art has no bold or reverse to keep' {
        $saved = @{ NO_COLOR = $env:NO_COLOR; USABANNER_COLOR = $env:USABANNER_COLOR }
        try {
            $env:NO_COLOR = '1'
            $env:USABANNER_COLOR = $null
            (@(Show-UsaBannerArt -Name rabbit) -join "`n") | Should -BeExactly (@(Show-UsaBannerArt -Name rabbit -ColorMode none) -join "`n")
        }
        finally {
            $env:NO_COLOR = $saved.NO_COLOR
            $env:USABANNER_COLOR = $saved.USABANNER_COLOR
        }
    }

    It 'reads the process environment when none is handed in' {
        $saved = $env:USABANNER_COLOR
        try {
            $env:USABANNER_COLOR = '256'
            InModuleScope UsaBanner { Resolve-UsaBannerColorMode } | Should -BeExactly '256'
        }
        finally { $env:USABANNER_COLOR = $saved }
    }
}

Describe 'choosing Unicode or ASCII' {
    It '<Case>' -ForEach @(
        @{ Case = 'glyphs asked for win over everything'; Requested = 'ascii'; Vars = @{ USABANNER_GLYPHS = 'unicode'; LANG = 'C.UTF-8' }; Expected = 'ascii' }
        @{ Case = 'USABANNER_GLYPHS wins over the locale'; Vars = @{ USABANNER_GLYPHS = 'ascii'; LANG = 'en_US.UTF-8' }; Expected = 'ascii' }
        @{ Case = 'USABANNER_GLYPHS in any case'; Vars = @{ USABANNER_GLYPHS = 'Unicode'; LANG = 'C' }; Expected = 'unicode' }
        @{ Case = 'Windows, as today''s Windows banner draws'; Vars = @{}; Windows = $true; Expected = 'unicode' }
        @{ Case = 'LANG=en_US.UTF-8'; Vars = @{ LANG = 'en_US.UTF-8' }; Expected = 'unicode' }
        @{ Case = 'LANG=C.utf8, as some systems spell it'; Vars = @{ LANG = 'C.utf8' }; Expected = 'unicode' }
        @{ Case = 'LC_ALL wins over LANG'; Vars = @{ LC_ALL = 'C'; LANG = 'en_US.UTF-8' }; Expected = 'ascii' }
        @{ Case = 'LC_CTYPE wins over LANG'; Vars = @{ LC_CTYPE = 'en_US.UTF-8'; LANG = 'C' }; Expected = 'unicode' }
        @{ Case = 'LANG=C, the C locale'; Vars = @{ LANG = 'C' }; Expected = 'ascii' }
        @{ Case = 'no locale at all'; Vars = @{}; Expected = 'ascii' }
    ) {
        $arguments = @{
            Requested   = $(if ($Requested) { $Requested } else { 'auto' })
            Environment = $Vars
            OnWindows   = [bool]$Windows
        }
        InModuleScope UsaBanner -Parameters $arguments {
            param($Requested, $Environment, $OnWindows)
            Resolve-UsaBannerGlyphs -Requested $Requested -Environment $Environment -OnWindows $OnWindows
        } | Should -BeExactly $Expected
    }

    It 'ignores a USABANNER_GLYPHS it does not know, and says so' {
        $result = InModuleScope UsaBanner {
            $glyphs = Resolve-UsaBannerGlyphs -Environment @{ USABANNER_GLYPHS = 'emoji'; LANG = 'C.UTF-8' } -OnWindows $false -WarningVariable warned -WarningAction SilentlyContinue
            @{ Glyphs = $glyphs; Warned = "$warned" }
        }
        $result.Glyphs | Should -BeExactly 'unicode'
        $result.Warned | Should -BeLike "*USABANNER_GLYPHS is 'emoji'. It takes unicode or ascii*"
    }
}
