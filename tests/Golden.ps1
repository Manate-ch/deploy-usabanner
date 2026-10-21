# Golden.ps1 - golden frames: a banner checked whole against the frame kept in
# tests/frames, which a review reads as a terminal would show it. Dot-source
# it in a BeforeAll.
#
# A frame file holds the lines drawn, LF after each, in UTF-8 with no
# byte-order mark, each escape character written as U+238B, the ESC symbol,
# so the file stays readable text. With USABANNER_GOLDEN=write in the
# environment, each frame file is written instead of checked: run the suite
# that way after a deliberate change, then read the diff.

function Assert-UsaBannerGoldenFrame {
    # In:  the frame's name, the lines drawn, and the folder of frames (tests/frames by default)
    # Out: nothing; fails when the lines differ from <folder>/<name>.txt
    # Why: one check per frame shows the whole frame when it fails, and in a review
    param([Parameter(Mandatory)][string]$Name, [AllowEmptyString()][string[]]$Lines, [string]$Root = (Join-Path $PSScriptRoot 'frames'))
    $path = Join-Path $Root "$Name.txt"
    $text = (@($Lines | ForEach-Object { $_.Replace([string][char]27, [string][char]0x238B) }) -join "`n") + "`n"
    if ($env:USABANNER_GOLDEN -eq 'write') {
        $null = New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force
        [System.IO.File]::WriteAllText($path, $text, [System.Text.UTF8Encoding]::new($false))
        return
    }
    if (-not (Test-Path -LiteralPath $path)) { throw "There is no golden frame $Name.txt in tests/frames. Run the suite with USABANNER_GOLDEN=write, then review the file it writes." }
    [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false)) | Should -BeExactly $text -Because "the golden frame $Name.txt"
}
