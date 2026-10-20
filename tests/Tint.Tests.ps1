# The OS colours: the colour art takes where its palette names a tint instead
# of a colour (D3, option B: our own art in the OS colour), and which OS this
# host is.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'UsaBanner' 'UsaBanner.psd1') -Force

    function Get-FirstRgb {
        # In:  lines a renderer drew in truecolor
        # Out: the red, green and blue of the first 24-bit colour in them
        # Why: tells which OS colour a piece was drawn in
        param([string[]]$Lines)
        $found = [regex]::Match(($Lines -join "`n"), "$([char]27)\[38;2;(\d+);(\d+);(\d+)m")
        $found.Success | Should -BeTrue -Because 'the art has a coloured cell'
        @([int]$found.Groups[1].Value, [int]$found.Groups[2].Value, [int]$found.Groups[3].Value)
    }
}

AfterAll { Remove-Module UsaBanner -ErrorAction SilentlyContinue }

Describe 'a tint' {
    It 'gives <Os> its own colour, a lighter one for os-light, and darker ones for os-dark and os-fill' -ForEach @(@{ Os = 'windows' }, @{ Os = 'ubuntu' }, @{ Os = 'linux' }) {
        InModuleScope UsaBanner -Parameters @{ Os = $Os } {
            param($Os)
            $sum = {
                # In:  '#RRGGBB'
                # Out: its three channels added up
                # Why: lighter and darker compare by it
                param([string]$Hex)
                (@(ConvertFrom-UsaBannerHex -Hex $Hex) | Measure-Object -Sum).Sum
            }
            $base = Get-UsaBannerTintColor -Tint os -Os $Os
            $light = Get-UsaBannerTintColor -Tint os-light -Os $Os
            $dark = Get-UsaBannerTintColor -Tint os-dark -Os $Os
            $fill = Get-UsaBannerTintColor -Tint os-fill -Os $Os
            "$($base['from']) $($base['to'])" | Should -BeExactly "$($script:UsaOsTint[$Os]['from']) $($script:UsaOsTint[$Os]['to'])"
            foreach ($end in 'from', 'to') {
                (& $sum $light[$end]) | Should -BeGreaterThan (& $sum $base[$end]) -Because "os-light $end"
                (& $sum $dark[$end]) | Should -BeLessThan (& $sum $base[$end]) -Because "os-dark $end"
                (& $sum $fill[$end]) | Should -BeLessThan (& $sum $dark[$end]) -Because "os-fill $end"
            }
            foreach ($entry in $base, $light, $dark, $fill) { $script:UsaBasicSgr.ContainsKey($entry['basic']) | Should -BeTrue }
        }
    }

    It 'works out the shades as its table says, for Windows blue' {
        InModuleScope UsaBanner {
            (Get-UsaBannerTintColor -Tint os-light -Os windows)['from'] | Should -BeExactly '#AAD6FF'   # each channel 35% of the way to 255
            (Get-UsaBannerTintColor -Tint os-dark -Os windows)['from'] | Should -BeExactly '#4D779E'    # times 0.62
            (Get-UsaBannerTintColor -Tint os-fill -Os windows)['from'] | Should -BeExactly '#34516B'    # times 0.42
        }
    }
}

Describe 'art in the OS colour' {
    It 'gives a tinted entry its OS''s colours, keeps its other keys, and leaves the art handed in alone' {
        InModuleScope UsaBanner {
            $art = [ordered]@{ palette = [ordered]@{ f = [ordered]@{ label = 'edge'; tint = 'os-dark'; sheen = $true } } }
            $entry = (Resolve-UsaBannerArtTint -Art $art -Os windows)['palette']['f']
            $expected = Get-UsaBannerTintColor -Tint os-dark -Os windows
            $entry['label'] | Should -BeExactly 'edge'
            $entry['sheen'] | Should -BeTrue
            $entry.Contains('tint') | Should -BeFalse
            foreach ($key in 'from', 'to', 'basic') { $entry[$key] | Should -BeExactly $expected[$key] -Because $key }
            $art['palette']['f'].Contains('tint') | Should -BeTrue
        }
    }

    It 'leaves art with no tint exactly as it was' {
        InModuleScope UsaBanner {
            $rabbit = Get-UsaBannerArtData -Name 'rabbit'
            $resolved = Resolve-UsaBannerArtTint -Art $rabbit -Os ubuntu
            (ConvertTo-Json -InputObject $resolved -Depth 10) | Should -BeExactly (ConvertTo-Json -InputObject $rabbit -Depth 10)
        }
    }

    It 'keeps classes that differ only in case apart' {
        InModuleScope UsaBanner {
            $palette = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
            $palette['f'] = [ordered]@{ tint = 'os' }
            $palette['F'] = [ordered]@{ rgb = '#FFFFFF' }
            $resolved = (Resolve-UsaBannerArtTint -Art ([ordered]@{ palette = $palette }) -Os ubuntu)['palette']
            $resolved.Count | Should -Be 2
            $resolved['F']['rgb'] | Should -BeExactly '#FFFFFF'
            $resolved['f']['from'] | Should -BeExactly '#FFA45C'
        }
    }
}

Describe 'Show-UsaBannerArt -Os' {
    It 'draws the server in blue for Windows, orange for Ubuntu and grey for any other Linux' {
        $windows = Get-FirstRgb @(Show-UsaBannerArt -Name server -ColorMode truecolor -Os windows)
        $ubuntu = Get-FirstRgb @(Show-UsaBannerArt -Name server -ColorMode truecolor -Os ubuntu)
        $linux = Get-FirstRgb @(Show-UsaBannerArt -Name server -ColorMode truecolor -Os linux)
        $windows[2] | Should -BeGreaterThan $windows[0] -Because 'Windows blue has more blue than red'
        $ubuntu[0] | Should -BeGreaterThan $ubuntu[2] -Because 'Ubuntu orange has more red than blue'
        [Math]::Abs($linux[0] - $linux[2]) | Should -BeLessThan 40 -Because 'grey has about as much red as blue'
    }

    It 'gives a 16-colour terminal the OS''s basic colours' {
        $esc = [char]27
        $ubuntu = @(Show-UsaBannerArt -Name server -ColorMode 16 -Os ubuntu) -join "`n"
        $windows = @(Show-UsaBannerArt -Name server -ColorMode 16 -Os windows) -join "`n"
        $ubuntu | Should -Match ([regex]::Escape("$esc[33m"))    # front edges: yellow
        $ubuntu | Should -Match ([regex]::Escape("$esc[93m"))    # top: bright yellow
        $windows | Should -Match ([regex]::Escape("$esc[94m"))   # front edges: bright blue
        $windows | Should -Match ([regex]::Escape("$esc[96m"))   # top: bright cyan
    }

    It 'draws the same plain art, as shown before login, for every OS' {
        $art = (Get-Content -LiteralPath (Join-Path $repoRoot 'UsaBanner' 'art' 'base' 'server.json') -Raw | ConvertFrom-Json -AsHashtable)['art']
        foreach ($system in 'windows', 'ubuntu', 'linux') {
            (@(Show-UsaBannerArt -Name server -ColorMode none -Os $system) -join "`n") | Should -BeExactly ($art -join "`n") -Because $system
        }
    }

    It 'draws in this host''s OS colour when -Os is auto, the default' {
        Mock -ModuleName UsaBanner Get-UsaBannerHostOs { 'ubuntu' }
        (@(Show-UsaBannerArt -Name server -ColorMode truecolor) -join "`n") | Should -BeExactly (@(Show-UsaBannerArt -Name server -ColorMode truecolor -Os ubuntu) -join "`n")
        Should -Invoke -ModuleName UsaBanner Get-UsaBannerHostOs -Times 1 -Exactly
    }
}

Describe 'which OS this host is' {
    It 'is <Expected> for <Case>' -ForEach @(
        @{ Case = 'Windows'; OnWindows = $true; Release = $null; Expected = 'windows' }
        @{ Case = 'Ubuntu'; OnWindows = $false; Release = "NAME=`"Ubuntu`"`nID=ubuntu`nID_LIKE=debian"; Expected = 'ubuntu' }
        @{ Case = 'Ubuntu, its ID quoted'; OnWindows = $false; Release = "ID=`"ubuntu`""; Expected = 'ubuntu' }
        @{ Case = 'Debian'; OnWindows = $false; Release = 'ID=debian'; Expected = 'linux' }
        @{ Case = 'a system based on Ubuntu'; OnWindows = $false; Release = "ID=linuxmint`nID_LIKE=`"ubuntu debian`""; Expected = 'linux' }
        @{ Case = 'no os-release file'; OnWindows = $false; Release = $null; Expected = 'linux' }
    ) {
        $path = Join-Path $TestDrive (($Case -replace '[^A-Za-z]', '-') + '.os-release')
        if ($null -ne $Release) { Set-Content -LiteralPath $path -Value $Release }
        InModuleScope UsaBanner -Parameters @{ OnWindows = $OnWindows; Path = $path } {
            param($OnWindows, $Path)
            Get-UsaBannerHostOs -OnWindows $OnWindows -OsReleasePath $Path
        } | Should -BeExactly $Expected
    }
}
