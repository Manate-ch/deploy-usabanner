# UsaBannerPicker.psm1 - a prototype of the interactive service picker of the
# planned Set-UsaBannerService: the "built in" option of D11 in
# docs/DECISIONS.md. Plain PowerShell 7; no other module.
#
# The picker is a small state machine. Keys come in through one scriptblock
# and every frame goes out through another, so the same code runs in a
# terminal (Select-UsaBannerService.ps1) and in a test that drives it with
# scripted keys and reads each frame back. A frame is plain text, twice:
# - in the notation of the spec's walk-through (docs/SPEC.md, Appendix A),
#   where <=x=> marks the row under the cursor, <x> a checked row, < > an
#   unchecked one and <=Done=> a selected button; the tests compare this;
# - as a terminal shows it: no '=' markers, and the row or button under the
#   cursor drawn in reverse video instead.

Set-StrictMode -Version 3.0

$script:NameWidth = 18
$script:DisplayWidth = 32
# Rows of the service list on screen at once.
$script:WindowRows = 10

# Format-PickerCell TEXT WIDTH
# In:  a cell's text and its column's width.
# Out: the text padded to the width, or cut to fit and ended with "...".
function Format-PickerCell {
    param([string]$Text, [int]$Width)
    if ($Text.Length -gt $Width) { $Text = $Text.Substring(0, $Width - 3) + '...' }
    $Text.PadRight($Width)
}

# Format-PickerRow SERVICE CURSOR [-Screen]
# In:  a service (Name, Display, Status, Checked) and whether the cursor is on it.
# Out: its line: the check mark, then the three columns. The walk-through marks
#      the cursor's row <=x=>; with -Screen the line is as a terminal shows it,
#      without the '=', since there the highlight marks the cursor instead.
function Format-PickerRow {
    param([object]$Service, [bool]$Cursor, [switch]$Screen)
    $mark = if ($Cursor -and -not $Screen) {
        if ($Service.Checked) { '<=x=>' } else { '<= =>' }
    } elseif ($Service.Checked) { '<x>' } else { '< >' }
    '{0} {1} {2} {3}' -f $mark.PadRight(5), (Format-PickerCell $Service.Name $script:NameWidth),
    (Format-PickerCell $Service.Display $script:DisplayWidth), $Service.Status
}

# Get-PickerColumnHeader
# Out: the two lines over the service rows.
function Get-PickerColumnHeader {
    $format = '      {0} {1} {2}'
    $format -f (Format-PickerCell 'Service Name' $script:NameWidth), (Format-PickerCell 'Display Name' $script:DisplayWidth), 'Status'
    $format -f (Format-PickerCell '------------' $script:NameWidth), (Format-PickerCell '------------' $script:DisplayWidth), '------'
}

# Get-PickerHint STATE
# In:  the picker state, on its first screen.
# Out: the key hint for the row under the cursor.
function Get-PickerHint {
    param([object]$State)
    $n = $State.Items.Count
    if ($State.Cursor -lt $n) { '[Spacebar=Select Item, Up/Down arrows to scroll]' }
    elseif ($State.Cursor -eq $n) { '[Enter=Add Service, Up/Down arrows to scroll]' }
    elseif ($State.Cursor -eq $n + 1) { '[Enter=Search for Service, Up/Down arrows to scroll]' }
    else { '[Enter=Finish Selection, Up/Down arrows to scroll]' }
}

# Get-PickerItemIndex STATE NAME
# In:  the picker state and a service name.
# Out: the index of the first-screen row with that name (any case), or -1.
function Get-PickerItemIndex {
    param([object]$State, [string]$Name)
    for ($i = 0; $i -lt $State.Items.Count; $i++) {
        if ([string]::Equals($State.Items[$i].Name, $Name, [System.StringComparison]::OrdinalIgnoreCase)) { return $i }
    }
    -1
}

function New-PickerState {
    <#
    .SYNOPSIS
    The picker's state. On the first screen, rows 0 to n-1 are the services,
    row n is "Add your own", n+1 the search button and n+2 Done.
    #>
    param([object[]]$Services = @(), [Parameter(Mandatory)][object]$Source)
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($service in $Services) { $items.Add($service) }
    [pscustomobject]@{
        Mode         = 'Main'   # Main, Search, Confirm, Saved or Cancelled
        Items        = $items   # the first screen's services
        Cursor       = 0
        Input        = ''       # typed on the "Add your own" row
        Source       = $Source
        Search       = $null    # the service list, sorted, while it is open
        Filter       = ''       # typed in the service list
        View         = $null    # the rows of Search that match Filter
        SearchCursor = 0        # an index into View
        SearchOffset = 0        # View's first row on screen
        OnDone       = $false   # the confirmation's button: Back, or Done
    }
}

function Format-PickerFrame {
    <#
    .SYNOPSIS
    The screen for the picker's current state, in two forms.
    .OUTPUTS
    Lines: the text in the walk-through's notation, where <=x=> marks the row
    under the cursor and <=Name=> a selected button. The tests compare these
    with the spec.
    Screen: the same text as a terminal shows it, without those '=' markers.
    Highlight: what the terminal draws in reverse video. Line, Start and
    Length index into Screen. A row is highlighted whole, a button on its own;
    Line is -1 when nothing is.
    CursorLine: Highlight.Line, kept for callers that read only Lines.
    #>
    param([Parameter(Mandatory)][object]$State)
    $lines = [System.Collections.Generic.List[string]]::new()
    # Not $screen: names ignore case, and $add's own $Screen would hide it.
    $screenLines = [System.Collections.Generic.List[string]]::new()
    $highlight = @{ Line = -1; Start = 0; Length = 0 }
    # One line of the frame. SCREEN defaults to the notation's text. -Row
    # highlights the whole screen line; -Button highlights that text in it.
    $add = {
        param([string]$Notation, [string]$Screen = $Notation, [switch]$Row, [string]$Button = '')
        if ($Row) {
            $highlight.Line = $lines.Count; $highlight.Start = 0; $highlight.Length = $Screen.Length
        } elseif ($Button) {
            $highlight.Line = $lines.Count
            $highlight.Start = $Screen.IndexOf($Button, [System.StringComparison]::Ordinal)
            $highlight.Length = $Button.Length
        }
        $lines.Add($Notation)
        $screenLines.Add($Screen)
    }
    # One service row, under the cursor or not.
    $addRow = {
        param([object]$Service, [bool]$Cursor)
        if ($Cursor) { & $add (Format-PickerRow $Service $true) (Format-PickerRow $Service $true -Screen) -Row }
        else { & $add (Format-PickerRow $Service $false) }
    }
    & $add '--------------'
    & $add '|UsagiTools Banner Setup'
    switch ($State.Mode) {
        'Main' {
            & $add '|> Please select services for the banner to monitor.'
            foreach ($line in Get-PickerColumnHeader) { & $add $line }
            for ($i = 0; $i -lt $State.Items.Count; $i++) { & $addRow $State.Items[$i] ($State.Cursor -eq $i) }
            $n = $State.Items.Count
            if ($State.Cursor -eq $n) { & $add "<= => Add your own: $($State.Input)_" "< >   Add your own: $($State.Input)_" -Row }
            else { & $add "< >   Add your own: $($State.Input)_" }
            if ($State.Cursor -eq $n + 1) { & $add '<=Search for Services=>' '<Search for Services>' -Button '<Search for Services>' }
            else { & $add '<Search for Services>' }
            if ($State.Cursor -eq $n + 2) { & $add '<=Done=>' '<Done>' -Button '<Done>' }
            else { & $add '<Done>' }
            & $add (Get-PickerHint $State)
        }
        'Search' {
            & $add '|> Please select services for the banner to monitor.'
            & $add '|> SERVICE SELECTION MENU'
            if ($State.Filter) { & $add "|> Filter: $($State.Filter)_" }
            foreach ($line in Get-PickerColumnHeader) { & $add $line }
            $view = $State.View
            $top = $State.SearchOffset
            $end = [Math]::Min($view.Count, $top + $script:WindowRows)
            if ($top -gt 0) { & $add '^Scroll^' }
            for ($i = $top; $i -lt $end; $i++) { & $addRow $view[$i] ($State.SearchCursor -eq $i) }
            if ($end -lt $view.Count) { & $add 'vScrollv' }
            if (-not $view.Count) {
                & $add $(if ($State.Filter) { '      (no service matches the filter)' } else { '      (no services found)' })
            }
            & $add '[Spacebar=Select Item, Esc=Back and add, Up/Down arrows to scroll]'
        }
        'Confirm' {
            & $add '|> Please select services for the banner to monitor.'
            foreach ($line in Get-PickerColumnHeader) { & $add $line }
            foreach ($service in $State.Items) { if ($service.Checked) { & $addRow $service $false } }
            & $add '|>DO YOU WISH TO SAVE THE FOLLOWING SERVICES TO BANNER MONITOR'
            if ($State.OnDone) {
                & $add '<Back> <=Done=>' '<Back> <Done>' -Button '<Done>'
                & $add '[Enter=Commit Changes and Save, Left/Right arrows to scroll]'
            } else {
                & $add '<=Back=> <Done>' '<Back> <Done>' -Button '<Back>'
                & $add '[Enter=Back, Left/Right arrows to scroll]'
            }
        }
        'Saved' {
            & $add '|> THE BELOW WILL BE CHECKED ON LOGON'
            foreach ($line in Get-PickerColumnHeader) { & $add $line }
            foreach ($service in $State.Items) { if ($service.Checked) { & $addRow $service $false } }
            & $add '|>THE ABOVE WILL BE CHECKED ON LOGON'
        }
        'Cancelled' { & $add '|> Cancelled. Nothing was saved.' }
    }
    [pscustomobject]@{
        Lines      = [string[]]$lines
        Screen     = [string[]]$screenLines
        Highlight  = [pscustomobject]@{ Line = $highlight.Line; Start = $highlight.Start; Length = $highlight.Length }
        CursorLine = $highlight.Line
    }
}

# Add-PickerService STATE RENDER
# In:  the state, with a name typed on the "Add your own" row.
# Out: that service listed, checked and under the cursor. It shows
#      "checking..." for one frame while it is looked up, then its display
#      name and status. One that is not found stays listed but unchecked
#      (D10). A name listed already is checked, not listed twice; a listed
#      one that was not found is looked up again.
# Why: a typo should be seen, not monitored.
function Add-PickerService {
    param([object]$State, [scriptblock]$Render)
    $name = $State.Input.Trim()
    $State.Input = ''
    if (-not $name) { return }
    $index = Get-PickerItemIndex $State $name
    if ($index -ge 0 -and $State.Items[$index].Status -ne 'NOTFOUND') {
        $State.Items[$index].Checked = $true
        $State.Cursor = $index
        return
    }
    if ($index -lt 0) {
        $State.Items.Add([pscustomobject]@{ Name = $name; Display = ''; Status = ''; Checked = $true })
        $index = $State.Items.Count - 1
    }
    $item = $State.Items[$index]
    $item.Display = 'checking...'
    $item.Status = 'checking...'
    $item.Checked = $true
    $State.Cursor = $index
    if ($Render) { & $Render (Format-PickerFrame $State) }
    $found = & $State.Source.Find $name
    if (-not $found) {
        $item.Display = 'NOTFOUND'
        $item.Status = 'NOTFOUND'
        $item.Checked = $false
        return
    }
    $listed = Get-PickerItemIndex $State $found.Name
    if ($listed -ge 0 -and $listed -ne $index) {
        # Found by its display name, and listed already under its service name.
        $State.Items.RemoveAt($index)
        $State.Cursor = Get-PickerItemIndex $State $found.Name
        $State.Items[$State.Cursor].Checked = $true
        return
    }
    $item.Name = $found.Name
    $item.Display = $found.Display
    $item.Status = $found.Status
}

# Update-PickerView STATE
# Out: State.View is the service list narrowed to the services whose name or
#      display name contains the filter (any case), with the cursor on its
#      first row.
function Update-PickerView {
    param([object]$State)
    $view = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $State.Search) {
        if (-not $State.Filter -or
            $row.Name.Contains($State.Filter, [System.StringComparison]::OrdinalIgnoreCase) -or
            $row.Display.Contains($State.Filter, [System.StringComparison]::OrdinalIgnoreCase)) { $view.Add($row) }
    }
    $State.View = $view
    $State.SearchCursor = 0
    $State.SearchOffset = 0
}

# Open-PickerSearch STATE
# Out: the service list open, sorted by name, with the first screen's checks
#      carried over.
function Open-PickerSearch {
    param([object]$State)
    $list = [System.Collections.Generic.List[object]]::new()
    foreach ($service in @(& $State.Source.List)) {
        $index = Get-PickerItemIndex $State $service.Name
        $list.Add([pscustomobject]@{
                Name    = $service.Name
                Display = [string]$service.Display
                Status  = $service.Status
                Checked = $index -ge 0 -and $State.Items[$index].Checked
            })
    }
    # Ordinal, ignoring case: the same order on every OS and in every culture.
    $list.Sort([System.Comparison[object]] {
            param($a, $b)
            [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$a.Name, [string]$b.Name)
        })
    $State.Search = $list
    $State.Filter = ''
    $State.Mode = 'Search'
    Update-PickerView $State
}

# Close-PickerSearch STATE
# In:  the state, in the service list.
# Out: back on the first screen, the cursor on the search button. A service
#      checked in the list is added, or checked if listed already; one
#      unchecked there is unchecked on the first screen too.
function Close-PickerSearch {
    param([object]$State)
    foreach ($row in $State.Search) {
        $index = Get-PickerItemIndex $State $row.Name
        if ($index -ge 0) { $State.Items[$index].Checked = $row.Checked }
        elseif ($row.Checked) {
            $State.Items.Add([pscustomobject]@{ Name = $row.Name; Display = $row.Display; Status = $row.Status; Checked = $true })
        }
    }
    $State.Search = $null
    $State.View = $null
    $State.Filter = ''
    $State.Mode = 'Main'
    $State.Cursor = $State.Items.Count + 1
}

function Step-PickerMain {
    param([object]$State, [System.ConsoleKeyInfo]$Key, [scriptblock]$Render)
    $n = $State.Items.Count
    $onAdd = $State.Cursor -eq $n
    switch ($Key.Key) {
        'UpArrow' { if ($State.Cursor -gt 0) { $State.Cursor-- }; return }
        'DownArrow' { if ($State.Cursor -lt $n + 2) { $State.Cursor++ }; return }
        'Escape' { $State.Mode = 'Cancelled'; return }
        'Enter' {
            if ($onAdd) { Add-PickerService $State $Render }
            elseif ($State.Cursor -eq $n + 1) { Open-PickerSearch $State }
            elseif ($State.Cursor -eq $n + 2) { $State.Mode = 'Confirm'; $State.OnDone = $false }
            return
        }
        'Backspace' {
            if ($onAdd -and $State.Input) { $State.Input = $State.Input.Substring(0, $State.Input.Length - 1) }
            return
        }
        'Spacebar' {
            if ($State.Cursor -lt $n) {
                $item = $State.Items[$State.Cursor]
                $item.Checked = -not $item.Checked
                return
            }
        }
    }
    # Typing on the "Add your own" row, Space included: a Windows service
    # name can hold one.
    if ($onAdd -and -not [char]::IsControl($Key.KeyChar)) { $State.Input += $Key.KeyChar }
}

function Step-PickerSearch {
    param([object]$State, [System.ConsoleKeyInfo]$Key)
    switch ($Key.Key) {
        'Escape' { Close-PickerSearch $State; return }
        'UpArrow' { $State.SearchCursor-- }
        'DownArrow' { $State.SearchCursor++ }
        'PageUp' { $State.SearchCursor -= $script:WindowRows }
        'PageDown' { $State.SearchCursor += $script:WindowRows }
        'Home' { $State.SearchCursor = 0 }
        'End' { $State.SearchCursor = $State.View.Count - 1 }
        'Spacebar' {
            if ($State.View.Count) {
                $row = $State.View[$State.SearchCursor]
                $row.Checked = -not $row.Checked
            }
        }
        'Backspace' {
            if ($State.Filter) {
                $State.Filter = $State.Filter.Substring(0, $State.Filter.Length - 1)
                Update-PickerView $State
            }
        }
        default {
            # Any other character narrows the list to the services that contain the text typed.
            if (-not [char]::IsControl($Key.KeyChar)) {
                $State.Filter += $Key.KeyChar
                Update-PickerView $State
            }
        }
    }
    # Clamp the cursor to the list, and scroll to keep it on screen.
    $State.SearchCursor = [Math]::Max(0, [Math]::Min($State.SearchCursor, $State.View.Count - 1))
    if ($State.SearchCursor -lt $State.SearchOffset) { $State.SearchOffset = $State.SearchCursor }
    elseif ($State.SearchCursor -ge $State.SearchOffset + $script:WindowRows) {
        $State.SearchOffset = $State.SearchCursor - $script:WindowRows + 1
    }
}

function Step-PickerConfirm {
    param([object]$State, [System.ConsoleKeyInfo]$Key)
    switch ($Key.Key) {
        'LeftArrow' { $State.OnDone = $false }
        'RightArrow' { $State.OnDone = $true }
        'Escape' { $State.Mode = 'Main'; $State.Cursor = $State.Items.Count + 2 }
        'Enter' {
            # Back is the default, so a second Enter cannot commit by accident.
            if ($State.OnDone) { $State.Mode = 'Saved' }
            else { $State.Mode = 'Main'; $State.Cursor = $State.Items.Count + 2 }
        }
    }
}

function Step-Picker {
    <#
    .SYNOPSIS
    Applies one key to the picker state. RENDER, when given, receives the
    extra "checking..." frame drawn while an added service is looked up.
    #>
    param([Parameter(Mandatory)][object]$State, [Parameter(Mandatory)][System.ConsoleKeyInfo]$Key, [scriptblock]$Render)
    # Ctrl+C cancels from any screen. The terminal wrapper reads it as a key,
    # because PowerShell cannot stop a script that is waiting in ReadKey.
    if ($Key.KeyChar -eq [char]3 -or ($Key.Key -eq [ConsoleKey]::C -and $Key.Modifiers.HasFlag([ConsoleModifiers]::Control))) {
        $State.Mode = 'Cancelled'
        return
    }
    switch ($State.Mode) {
        'Main' { Step-PickerMain -State $State -Key $Key -Render $Render }
        'Search' { Step-PickerSearch $State $Key }
        'Confirm' { Step-PickerConfirm $State $Key }
    }
}

function Invoke-ServicePicker {
    <#
    .SYNOPSIS
    Runs the picker until the user saves or cancels.
    .OUTPUTS
    Saved ($true when saved, $false when cancelled) and Services (the names
    of the services checked, when saved).
    #>
    [CmdletBinding()]
    param(
        # The services monitored already when the picker opens.
        [string[]]$Monitored = @(),
        # Where services come from: List and Find scriptblocks, as from Get-PickerServiceSource.
        [Parameter(Mandatory)][object]$Source,
        # Returns the next key, a [ConsoleKeyInfo].
        [Parameter(Mandatory)][scriptblock]$ReadKey,
        # Draws a frame (Format-PickerFrame's output).
        [Parameter(Mandatory)][scriptblock]$Render
    )
    $services = @(foreach ($name in $Monitored) {
            $found = & $Source.Find $name
            if ($found) { [pscustomobject]@{ Name = $found.Name; Display = $found.Display; Status = $found.Status; Checked = $true } }
            else {
                # Monitored already but not found: it stays checked, so opening
                # the picker and saving changes nothing the user did not touch.
                [pscustomobject]@{ Name = $name; Display = 'NOTFOUND'; Status = 'NOTFOUND'; Checked = $true }
            }
        })
    $state = New-PickerState -Services $services -Source $Source
    & $Render (Format-PickerFrame $state)
    while ($state.Mode -notin 'Saved', 'Cancelled') {
        Step-Picker -State $state -Key (& $ReadKey) -Render $Render
        & $Render (Format-PickerFrame $state)
    }
    $saved = $state.Mode -eq 'Saved'
    [pscustomobject]@{
        Saved    = $saved
        Services = [string[]]@(if ($saved) { foreach ($item in $state.Items) { if ($item.Checked) { $item.Name } } })
    }
}

# ConvertTo-PickerStatus ACTIVE SUB
# In:  a systemd unit's active state and sub-state.
# Out: the status shown: Running, Exited, Stopped, Failed, or systemd's word.
function ConvertTo-PickerStatus {
    param([string]$Active, [string]$Sub)
    switch ($Active) {
        'active' { if ($Sub -eq 'exited') { 'Exited' } else { 'Running' } }
        'inactive' { 'Stopped' }
        'failed' { 'Failed' }
        default { $Active }
    }
}

# ConvertFrom-SystemctlUnitList LINE...
# In:  the lines of "systemctl list-units --type=service --all --no-legend --plain".
# Out: one service per unit: Name (without ".service"), Display (the unit's
#      description) and Status.
function ConvertFrom-SystemctlUnitList {
    param([string[]]$Line)
    foreach ($text in $Line) {
        # Columns: UNIT LOAD ACTIVE SUB DESCRIPTION. Without --plain, systemd
        # 255 puts a bullet before a failed unit; one is accepted anyway.
        if ($text -match '^\s*(?:\S\s+)?(\S+)\.service\s+\S+\s+(\S+)\s+(\S+)\s*(.*)$') {
            [pscustomobject]@{ Name = $Matches[1]; Display = $Matches[4]; Status = (ConvertTo-PickerStatus $Matches[2] $Matches[3]) }
        }
    }
}

# Find-PickerSystemdService NAME
# In:  a service name, with or without ".service".
# Out: the service, as ConvertFrom-SystemctlUnitList returns one, or nothing
#      when systemd has no such unit. It asks systemd for the unit itself, so
#      one that is installed but not loaded is found too.
function Find-PickerSystemdService {
    param([string]$Name)
    $unit = $Name -replace '\.service$', ''
    # Only a unit name reaches systemctl, and after "--": no glob, no option.
    if ($unit -notmatch '^[A-Za-z0-9:_.@\\-]+$') { return }
    $property = @{}
    foreach ($line in & systemctl show --no-pager --property=Id,Description,LoadState,ActiveState,SubState -- "$unit.service" 2>$null) {
        $key, $value = $line -split '=', 2
        $property[$key] = $value
    }
    if (-not $property['LoadState'] -or $property['LoadState'] -eq 'not-found') { return }
    [pscustomobject]@{
        Name    = $property['Id'] -replace '\.service$', ''
        Display = [string]$property['Description']
        Status  = ConvertTo-PickerStatus $property['ActiveState'] $property['SubState']
    }
}

function New-PickerDemoSource {
    # The made-up services of the walk-through, and enough others to scroll.
    $rows = @(
        'Netlogon|Netlogon|Running'
        'w32time|Windows Time|Running'
        'RmmAgent|RMM Agent|Running'
        '11AmazonThings|Amazon Tool Things|Running'
        'AarSvc_7fe7ef|Agent Activation Runtime_7fe7ef|Stopped'
        'ADPSvc|Aggregated Data Platform Service|Stopped'
        'ALG|Application Layer Gateway Service|Stopped'
        'AMD Crash Defender Service|AMD Crash Defender Service|Running'
        'AMD External Events Utility|AMD External Events Utility|Running'
        'amd3dvcacheSvc|AMD 3D V-Cache Performance Service|Stopped'
        'AmdAppCompatSvc|AMD Application Compatibility Database Service|Stopped'
        'AmdPpkgSvc|AMD Provisioning Packages Service|Running'
        'AppIDSvc|Application Identity|Stopped'
        'Appinfo|Application Information|Running'
        'AppMgmt|Application Management|Stopped'
        'AppXSvc|AppX Deployment Service (AppXSVC)|Running'
        'AudioEndpointBuilder|Windows Audio Endpoint Builder|Running'
        'BFE|Base Filtering Engine|Running'
        'BITS|Background Intelligent Transfer Service|Running'
        'Dnscache|DNS Client|Running'
        'EventLog|Windows Event Log|Running'
        'sshd|OpenSSH SSH Server|Running'
        'WinRM|Windows Remote Management (WS-Management)|Running'
    )
    $list = @(foreach ($row in $rows) {
            $name, $display, $status = $row -split '\|'
            [pscustomobject]@{ Name = $name; Display = $display; Status = $status }
        })
    [pscustomobject]@{
        List = { $list }.GetNewClosure()
        # Like Get-Service: by service name, else by display name.
        Find = {
            param($Name)
            $match = $list | Where-Object { [string]::Equals($_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
            if (-not $match) {
                $match = $list | Where-Object { [string]::Equals($_.Display, $Name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
            }
            $match
        }.GetNewClosure()
    }
}

function Get-PickerServiceSource {
    <#
    .SYNOPSIS
    Where the picker's services come from: Get-Service on Windows, systemd's
    service units elsewhere, or with -Demo the made-up services of the
    walk-through. It only reads; it changes nothing.
    .OUTPUTS
    Two scriptblocks: List (every service) and Find (one, by name, or nothing).
    #>
    [CmdletBinding()]
    param([switch]$Demo)
    if ($Demo) { return New-PickerDemoSource }
    if ($IsWindows) {
        return [pscustomobject]@{
            List = {
                foreach ($service in Get-Service -ErrorAction SilentlyContinue) {
                    [pscustomobject]@{ Name = $service.Name; Display = $service.DisplayName; Status = [string]$service.Status }
                }
            }
            # Get-Service finds a service by its display name too.
            Find = {
                param($Name)
                # A literal name only: Get-Service -Name would expand a wildcard.
                if ([WildcardPattern]::ContainsWildcardCharacters($Name)) { return }
                $service = Get-Service -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($service) { [pscustomobject]@{ Name = $service.Name; Display = $service.DisplayName; Status = [string]$service.Status } }
            }
        }
    }
    [pscustomobject]@{
        List = { ConvertFrom-SystemctlUnitList (& systemctl list-units --type=service --all --no-legend --plain --no-pager 2>$null) }
        Find = { param($Name) Find-PickerSystemdService $Name }
    }
}

Export-ModuleMember -Function Invoke-ServicePicker, Get-PickerServiceSource
