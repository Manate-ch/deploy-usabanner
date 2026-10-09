# Pester 5 tests for the service-picker prototype, UsaBannerPicker.psm1. The first block plays the
# walk-through in docs/SPEC.md, Appendix A, key by key against the same made-up services, and checks
# the screen at each moment against the spec's frame. Where the prototype differs on purpose
# (prototype/README.md says why), the expected lines are the prototype's and the test name says so.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '../UsaBannerPicker.psm1') -Force

    # ConvertTo-PickerKey STEP
    # In:  'Up', 'Down', 'Left', 'Right', 'Space', 'Enter', 'Esc', 'Backspace', 'PageDown', 'Home',
    #      'End', 'CtrlC', or 'type:TEXT'.
    # Out: the key presses a console reports for it, as [ConsoleKeyInfo].
    function ConvertTo-PickerKey {
        param([string]$Step)
        if ($Step -like 'type:*') {
            foreach ($c in $Step.Substring(5).ToCharArray()) {
                $key = if ($c -eq ' ') { [ConsoleKey]::Spacebar }
                elseif ($c -match '[A-Za-z0-9]') { [ConsoleKey][int][char]::ToUpperInvariant($c) }
                else { [ConsoleKey]::OemMinus }
                [System.ConsoleKeyInfo]::new($c, $key, $false, $false, $false)
            }
            return
        }
        $keys = @{
            Up = [ConsoleKey]::UpArrow; Down = [ConsoleKey]::DownArrow; Left = [ConsoleKey]::LeftArrow
            Right = [ConsoleKey]::RightArrow; Space = [ConsoleKey]::Spacebar; Enter = [ConsoleKey]::Enter
            Esc = [ConsoleKey]::Escape; Backspace = [ConsoleKey]::Backspace; PageDown = [ConsoleKey]::PageDown
            Home = [ConsoleKey]::Home; End = [ConsoleKey]::End; CtrlC = [ConsoleKey]::C
        }
        $chars = @{ Space = ' '; Enter = "`r"; Esc = [char]27; Backspace = [char]8; CtrlC = [char]3 }
        if (-not $keys.ContainsKey($Step)) { throw "Unknown step: $Step" }
        $char = if ($chars.ContainsKey($Step)) { [char]$chars[$Step] } else { [char]0 }
        [System.ConsoleKeyInfo]::new($char, $keys[$Step], $false, $false, ($Step -eq 'CtrlC'))
    }

    # Invoke-PickerScript -Steps STEP... [-Monitored NAME...]
    # In:  steps for ConvertTo-PickerKey; '@LABEL' names the frame on screen at that point.
    # Out: Result (Invoke-ServicePicker's, or $null when the steps ran out first), Frames (every
    #      frame drawn), At (LABEL -> an index into Frames) and KeysLeft.
    function Invoke-PickerScript {
        param([string[]]$Steps, [string[]]$Monitored = @('Netlogon', 'w32time'))
        $queue = [System.Collections.Generic.Queue[object]]::new()
        foreach ($step in $Steps) {
            if ($step.StartsWith('@')) { $queue.Enqueue($step.Substring(1)) }
            else { foreach ($key in ConvertTo-PickerKey $step) { $queue.Enqueue($key) } }
        }
        $frames = [System.Collections.Generic.List[object]]::new()
        $at = @{}
        $outOfKeys = 'The steps ran out before the picker finished.'
        $readKey = {
            while ($queue.Count -and $queue.Peek() -is [string]) { $at[$queue.Dequeue()] = $frames.Count - 1 }
            if (-not $queue.Count) { throw $outOfKeys }
            $queue.Dequeue()
        }.GetNewClosure()
        $render = { param($Frame) $frames.Add($Frame) }.GetNewClosure()
        $result = $null
        try { $result = Invoke-ServicePicker -Monitored $Monitored -Source (Get-PickerServiceSource -Demo) -ReadKey $readKey -Render $render }
        catch { if ($_.Exception.Message -ne $outOfKeys) { throw } }
        # Labels after the last key name the last frame.
        while ($queue.Count -and $queue.Peek() -is [string]) { $at[$queue.Dequeue()] = $frames.Count - 1 }
        [pscustomobject]@{ Result = $result; Frames = $frames.ToArray(); At = $at; KeysLeft = $queue.Count }
    }

    # Get-FrameText FRAME
    # Out: the frame as one string, a line per line.
    function Get-FrameText {
        param([object]$Frame)
        $Frame.Lines -join "`n"
    }

    # Get-MissingLine FRAME EXPECTED
    # In:  a frame, and lines it should show; like the spec's partial frames, they may skip lines
    #      that did not change.
    # Out: nothing when every expected line is in the frame, in the same order; otherwise the first
    #      one that is not.
    function Get-MissingLine {
        param([object]$Frame, [string]$Expected)
        $next = 0
        foreach ($line in $Expected -split '\r?\n') {
            while ($next -lt $Frame.Lines.Count -and $Frame.Lines[$next] -cne $line) { $next++ }
            if ($next -ge $Frame.Lines.Count) { return $line }
            $next++
        }
    }
}

Describe 'the check for partial frames' {
    It 'catches a line that is not on screen, one out of order, and one in another case' {
        $frame = [pscustomobject]@{ Lines = 'one', 'two', 'three' }
        Get-MissingLine $frame "one`nthree" | Should -BeNullOrEmpty
        Get-MissingLine $frame "one`nfour" | Should -Be 'four'
        Get-MissingLine $frame "three`none" | Should -Be 'one'
        Get-MissingLine $frame 'TWO' | Should -BeExactly 'TWO'
    }
}

Describe 'the walk-through in docs/SPEC.md, Appendix A' {
    BeforeAll {
        $run = Invoke-PickerScript -Steps @(
            '@T+0'
            'Space', '@T+5'
            'Down', '@T+7'
            'Down', '@T+8'
            'type:RmmAgent', '@T+10'
            'Enter', '@T+15'
            'Down', 'type:11AmazingThings', '@T+17'
            'Enter', '@T+22'
            'Down', 'Down', '@T+27'
            'Enter', '@T+29'
            'Space', '@T+30'
            'Down', 'Down', 'Down', 'Down', 'Down', '@T+32'
            'Space', '@T+35'
            'Esc', '@T+38'
            # T+40 unchecks the service that was not found; here it is unchecked already (D10).
            'Down', '@T+43'
            'Enter', '@T+46'
            'Enter', '@T+47'
            'Enter', 'Right', '@T+49'
            'Enter', '@T+50'
        )
        # Enter on "Add your own" draws two frames: the lookup under way, then its result.
        $run.At['T+12'] = $run.At['T+15'] - 1
        $run.At['T+20'] = $run.At['T+22'] - 1
    }

    It 'plays to the end with every key used, and saves the four services of T+50' {
        $run.KeysLeft | Should -Be 0
        $run.Result.Saved | Should -BeTrue
        $run.Result.Services | Should -Be 'w32time', 'RmmAgent', '11AmazonThings', 'AMD External Events Utility'
    }

    It 'highlights, in every frame, the line marked as under the cursor' {
        foreach ($frame in $run.Frames) {
            $marked = @(for ($i = 0; $i -lt $frame.Lines.Count; $i++) { if ($frame.Lines[$i].Contains('<=')) { $i } })
            $marked.Count | Should -BeLessOrEqual 1
            $frame.CursorLine | Should -Be $(if ($marked.Count) { $marked[0] } else { -1 })
        }
    }

    # A frame that starts with the top border is the whole screen and must match exactly. The
    # spec's other frames show only the lines that changed; those must be on screen, in order.
    It '<Label> s: <Says>' -ForEach @(
        @{ Label = 'T+0'; Says = 'the menu opens on the monitored services (no slow-logon note: D10)'; Lines = @'
--------------
|UsagiTools Banner Setup
|> Please select services for the banner to monitor.
      Service Name       Display Name                     Status
      ------------       ------------                     ------
<=x=> Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
< >   Add your own: _
<Search for Services>
<Done>
[Spacebar=Select Item, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+5'; Says = 'Space: Netlogon is unchecked'; Lines = @'
<= => Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
< >   Add your own: _
<Search for Services>
<Done>
[Spacebar=Select Item, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+7'; Says = 'Down'; Lines = @'
< >   Netlogon           Netlogon                         Running
<=x=> w32time            Windows Time                     Running
< >   Add your own: _
<Search for Services>
<Done>
[Spacebar=Select Item, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+8'; Says = 'Down: the cursor is on the input row, and the key hint changes'; Lines = @'
< >   Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
<= => Add your own: _
<Search for Services>
<Done>
[Enter=Add Service, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+10'; Says = 'the user types a service name'; Lines = @'
<= => Add your own: RmmAgent_
[Enter=Add Service, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+12'; Says = 'Enter: the new row is checked, and checking starts (with the row hint, as at T+20)'; Lines = @'
< >   Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
<=x=> RmmAgent           checking...                      checking...
< >   Add your own: _
<Search for Services>
<Done>
[Spacebar=Select Item, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+15'; Says = 'the check resolves'; Lines = @'
<=x=> RmmAgent           RMM Agent                        Running
'@ }
        @{ Label = 'T+17'; Says = 'Down, then a name that does not exist'; Lines = @'
<x>   RmmAgent           RMM Agent                        Running
<= => Add your own: 11AmazingThings_
[Enter=Add Service, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+20'; Says = 'Enter: checking'; Lines = @'
<=x=> 11AmazingThings    checking...                      checking...
< >   Add your own: _
[Spacebar=Select Item, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+22'; Says = 'not found, so unchecked (D10)'; Lines = @'
<= => 11AmazingThings    NOTFOUND                         NOTFOUND
'@ }
        @{ Label = 'T+27'; Says = 'Down twice: the search button (the not-found service unchecked: D10)'; Lines = @'
< >   Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
<x>   RmmAgent           RMM Agent                        Running
< >   11AmazingThings    NOTFOUND                         NOTFOUND
< >   Add your own: _
<=Search for Services=>
<Done>
[Enter=Search for Service, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+29'; Says = 'Enter: the list, by name, ten rows at a time (a 32-character display name fits)'; Lines = @'
--------------
|UsagiTools Banner Setup
|> Please select services for the banner to monitor.
|> SERVICE SELECTION MENU
      Service Name       Display Name                     Status
      ------------       ------------                     ------
<= => 11AmazonThings     Amazon Tool Things               Running
< >   AarSvc_7fe7ef      Agent Activation Runtime_7fe7ef  Stopped
< >   ADPSvc             Aggregated Data Platform Service Stopped
< >   ALG                Application Layer Gateway Ser... Stopped
< >   AMD Crash Defen... AMD Crash Defender Service       Running
< >   AMD External Ev... AMD External Events Utility      Running
< >   amd3dvcacheSvc     AMD 3D V-Cache Performance Se... Stopped
< >   AmdAppCompatSvc    AMD Application Compatibility... Stopped
< >   AmdPpkgSvc         AMD Provisioning Packages Ser... Running
< >   AppIDSvc           Application Identity             Stopped
vScrollv
[Spacebar=Select Item, Esc=Back and add, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+30'; Says = 'Space: 11AmazonThings is checked'; Lines = @'
<=x=> 11AmazonThings     Amazon Tool Things               Running
'@ }
        @{ Label = 'T+32'; Says = 'Down five times (not scrolled yet: the cursor is still in the ten rows)'; Lines = @'
<x>   11AmazonThings     Amazon Tool Things               Running
< >   AarSvc_7fe7ef      Agent Activation Runtime_7fe7ef  Stopped
< >   ADPSvc             Aggregated Data Platform Service Stopped
< >   ALG                Application Layer Gateway Ser... Stopped
< >   AMD Crash Defen... AMD Crash Defender Service       Running
<= => AMD External Ev... AMD External Events Utility      Running
< >   amd3dvcacheSvc     AMD 3D V-Cache Performance Se... Stopped
< >   AmdAppCompatSvc    AMD Application Compatibility... Stopped
< >   AmdPpkgSvc         AMD Provisioning Packages Ser... Running
< >   AppIDSvc           Application Identity             Stopped
vScrollv
[Spacebar=Select Item, Esc=Back and add, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+35'; Says = 'Space: checked'; Lines = @'
<=x=> AMD External Ev... AMD External Events Utility      Running
'@ }
        @{ Label = 'T+38'; Says = 'Esc: back to the first menu, with both picks added'; Lines = @'
--------------
|UsagiTools Banner Setup
|> Please select services for the banner to monitor.
      Service Name       Display Name                     Status
      ------------       ------------                     ------
< >   Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
<x>   RmmAgent           RMM Agent                        Running
< >   11AmazingThings    NOTFOUND                         NOTFOUND
<x>   11AmazonThings     Amazon Tool Things               Running
<x>   AMD External Ev... AMD External Events Utility      Running
< >   Add your own: _
<=Search for Services=>
<Done>
[Enter=Search for Service, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+43'; Says = 'Down, to Done (no T+40: nothing to uncheck, D10)'; Lines = @'
< >   Add your own: _
<Search for Services>
<=Done=>
[Enter=Finish Selection, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+46'; Says = 'Enter: a confirmation lists only the checked services, the cursor on Back'; Lines = @'
--------------
|UsagiTools Banner Setup
|> Please select services for the banner to monitor.
      Service Name       Display Name                     Status
      ------------       ------------                     ------
<x>   w32time            Windows Time                     Running
<x>   RmmAgent           RMM Agent                        Running
<x>   11AmazonThings     Amazon Tool Things               Running
<x>   AMD External Ev... AMD External Events Utility      Running
|>DO YOU WISH TO SAVE THE FOLLOWING SERVICES TO BANNER MONITOR
<=Back=> <Done>
[Enter=Back, Left/Right arrows to scroll]
'@ }
        @{ Label = 'T+47'; Says = 'Enter on Back returns to the menu, the cursor on Done'; Lines = @'
|> Please select services for the banner to monitor.
< >   Add your own: _
<Search for Services>
<=Done=>
[Enter=Finish Selection, Up/Down arrows to scroll]
'@ }
        @{ Label = 'T+49'; Says = 'Enter reopens the confirmation; Right: Done is highlighted'; Lines = @'
|>DO YOU WISH TO SAVE THE FOLLOWING SERVICES TO BANNER MONITOR
<Back> <=Done=>
[Enter=Commit Changes and Save, Left/Right arrows to scroll]
'@ }
        @{ Label = 'T+50'; Says = 'Enter: saved'; Lines = @'
--------------
|UsagiTools Banner Setup
|> THE BELOW WILL BE CHECKED ON LOGON
      Service Name       Display Name                     Status
      ------------       ------------                     ------
<x>   w32time            Windows Time                     Running
<x>   RmmAgent           RMM Agent                        Running
<x>   11AmazonThings     Amazon Tool Things               Running
<x>   AMD External Ev... AMD External Events Utility      Running
|>THE ABOVE WILL BE CHECKED ON LOGON
'@ }
    ) {
        $frame = $run.Frames[$run.At[$Label]]
        if ($Lines.StartsWith('--------------')) {
            Get-FrameText $frame | Should -BeExactly ($Lines -replace "`r")
        } else {
            Get-MissingLine $frame $Lines | Should -BeNullOrEmpty -Because "each line the spec shows at $Label is on screen, in order. The screen:`n$(Get-FrameText $frame)`n"
        }
    }
}

Describe 'the first screen, past the walk-through' {
    It 'Esc cancels, and nothing is saved' {
        $run = Invoke-PickerScript -Steps 'Esc'
        $run.Result.Saved | Should -BeFalse
        $run.Result.Services.Count | Should -Be 0
        Get-FrameText $run.Frames[-1] | Should -BeExactly "--------------`n|UsagiTools Banner Setup`n|> Cancelled. Nothing was saved."
    }

    It 'Ctrl+C cancels from <Screen>, and nothing is saved' -ForEach @(
        @{ Screen = 'the first screen'; Steps = @('Space', 'CtrlC') }
        @{ Screen = 'the service list'; Steps = @('Down', 'Down', 'Down', 'Enter', 'Space', 'CtrlC') }
        @{ Screen = 'the confirmation'; Steps = @('Down', 'Down', 'Down', 'Down', 'Enter', 'Right', 'CtrlC') }
    ) {
        $run = Invoke-PickerScript -Steps $Steps
        $run.KeysLeft | Should -Be 0
        $run.Result.Saved | Should -BeFalse
        $run.Result.Services.Count | Should -Be 0
        $run.Frames[-1].Lines[-1] | Should -BeExactly '|> Cancelled. Nothing was saved.'
    }

    It 'a name typed that is listed already checks that row, instead of listing it twice' {
        $run = Invoke-PickerScript -Steps 'Space', 'Down', 'Down', 'type:NETLOGON', 'Enter'
        Get-MissingLine $run.Frames[-1] @'
<=x=> Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
< >   Add your own: _
'@ | Should -BeNullOrEmpty
        $run.Frames[-1].Lines | Should -HaveCount 11
        @($run.Frames.Lines) -match 'checking' | Should -BeNullOrEmpty
    }

    It 'a display name finds the service listed under its service name, as Get-Service does' {
        $run = Invoke-PickerScript -Steps 'Down', 'Space', 'Down', 'type:Windows Time', 'Enter'
        Get-MissingLine $run.Frames[-1] @'
<x>   Netlogon           Netlogon                         Running
<=x=> w32time            Windows Time                     Running
< >   Add your own: _
'@ | Should -BeNullOrEmpty
        $run.Frames[-1].Lines | Should -HaveCount 11
    }

    It 'a name that is not found starts unchecked (D10); Space checks it anyway, as -Force does for -Add' {
        $run = Invoke-PickerScript -Steps 'Down', 'Down', 'type:NoSuchService', 'Enter', '@added', 'Space', '@checked'
        $run.Frames[$run.At['added']].Lines | Should -Contain '<= => NoSuchService      NOTFOUND                         NOTFOUND'
        $run.Frames[$run.At['checked']].Lines | Should -Contain '<=x=> NoSuchService      NOTFOUND                         NOTFOUND'
    }

    It 'the name of a service that was not found, typed again, is looked up again' {
        $run = Invoke-PickerScript -Steps 'Down', 'Down', 'type:NoSuchService', 'Enter', 'Down', 'type:nosuchservice', 'Enter'
        $run.Frames[-2].Lines | Should -Contain '<=x=> NoSuchService      checking...                      checking...'
        @($run.Frames[-1].Lines -match 'NoSuchService') | Should -HaveCount 1
    }

    It 'Backspace erases what was typed' {
        $run = Invoke-PickerScript -Steps 'Down', 'Down', 'type:RmmAgentX', 'Backspace', '@erased', 'Enter'
        $run.Frames[$run.At['erased']].Lines | Should -Contain '<= => Add your own: RmmAgent_'
        $run.Frames[-1].Lines | Should -Contain '<=x=> RmmAgent           RMM Agent                        Running'
    }

    It 'a monitored service that is not found stays checked, so saving changes nothing untouched' {
        $run = Invoke-PickerScript -Monitored 'Netlogon', 'GoneSvc' -Steps '@open', 'Down', 'Down', 'Down', 'Down', 'Enter', 'Right', 'Enter'
        $run.Frames[$run.At['open']].Lines | Should -Contain '<x>   GoneSvc            NOTFOUND                         NOTFOUND'
        $run.Result.Services | Should -Be 'Netlogon', 'GoneSvc'
    }
}

Describe 'the service list' {
    It 'scrolls one row at a time to keep the cursor on screen; End and Home jump' {
        $run = Invoke-PickerScript -Steps (@('Down', 'Down', 'Down', 'Enter') + @('Down') * 10 + @('@ten', 'End', '@end', 'Home', '@top'))
        $ten = $run.Frames[$run.At['ten']]
        Get-MissingLine $ten @'
^Scroll^
< >   AarSvc_7fe7ef      Agent Activation Runtime_7fe7ef  Stopped
<= => Appinfo            Application Information          Running
vScrollv
'@ | Should -BeNullOrEmpty
        @($ten.Lines -match '^<') | Should -HaveCount 10
        $end = $run.Frames[$run.At['end']]
        Get-MissingLine $end @'
^Scroll^
<x>   Netlogon           Netlogon                         Running
<x>   w32time            Windows Time                     Running
<= => WinRM              Windows Remote Management (WS... Running
'@ | Should -BeNullOrEmpty
        $end.Lines | Should -Not -Contain 'vScrollv'
        $top = $run.Frames[$run.At['top']]
        $top.Lines | Should -Not -Contain '^Scroll^'
        $top.Lines | Should -Contain '<= => 11AmazonThings     Amazon Tool Things               Running'
    }

    It 'typing filters on name or display name, and Backspace widens it again' {
        $run = Invoke-PickerScript -Steps 'Down', 'Down', 'Down', 'Enter', 'type:win', '@win', 'Backspace', 'Backspace', 'Backspace', '@all'
        $win = $run.Frames[$run.At['win']]
        $win.Lines | Should -Contain '|> Filter: win_'
        @($win.Lines -match '^<' | ForEach-Object { $_.Substring(6, 18).TrimEnd() }) | Should -Be 'AudioEndpointBu...', 'EventLog', 'w32time', 'WinRM'
        $win.Lines | Should -Contain '<x>   w32time            Windows Time                     Running'
        $all = $run.Frames[$run.At['all']]
        @($all.Lines -like '|> Filter*').Count | Should -Be 0
        @($all.Lines -match '^<') | Should -HaveCount 10
    }

    It 'Space unchecks a monitored service in the list, and Esc carries that back' {
        $run = Invoke-PickerScript -Steps 'Down', 'Down', 'Down', 'Enter', 'type:w32', 'Space', 'Esc'
        Get-MissingLine $run.Frames[-1] @'
< >   w32time            Windows Time                     Running
< >   Add your own: _
<=Search for Services=>
'@ | Should -BeNullOrEmpty
    }
}

Describe "reading a machine's services" {
    It 'reads systemctl list-units, with or without the bullet before a failed unit' {
        $services = InModuleScope UsaBannerPicker {
            ConvertFrom-SystemctlUnitList @(
                'cron.service              loaded    active   running   Regular background program processing daemon'
                "$([char]0x25CF) example-update.service loaded failed failed Pull and install the login banner"
                'example-oneshot.service   loaded    active   exited    Apply the example settings'
                'example-gone.service      not-found inactive dead      example-gone.service'
                'ssh.socket                loaded    active   listening OpenBSD Secure Shell server socket'
            )
        }
        $services.Name | Should -Be 'cron', 'example-update', 'example-oneshot', 'example-gone'
        $services.Status | Should -Be 'Running', 'Failed', 'Exited', 'Stopped'
        $services[0].Display | Should -Be 'Regular background program processing daemon'
    }

    It 'lists the services of the machine it runs on, and finds one of them by name' {
        $source = Get-PickerServiceSource
        $listed = @(& $source.List)
        $listed.Count | Should -BeGreaterThan 0
        $found = & $source.Find $listed[0].Name
        $found.Name | Should -Be $listed[0].Name
        $found.Status | Should -Not -BeNullOrEmpty
    }

    It 'finds nothing for a name no service has, or one holding a wildcard' {
        $source = Get-PickerServiceSource
        @(& $source.Find 'NoSuchService-0f3a').Count | Should -Be 0
        @(& $source.Find '*').Count | Should -Be 0
    }
}

Describe 'Select-UsaBannerService.ps1' {
    It 'refuses to start without an interactive terminal, instead of waiting for keys' {
        $pwsh = (Get-Process -Id $PID).Path
        $wrapper = Join-Path $PSScriptRoot '../Select-UsaBannerService.ps1'
        $output = '' | & $pwsh -NoProfile -NonInteractive -File $wrapper -Demo 2>&1
        $LASTEXITCODE | Should -Be 1
        ($output -join "`n") | Should -Match 'interactive'
    }
}
