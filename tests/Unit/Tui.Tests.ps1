Set-TestGroup 'Centralized differential frame renderer'
Assert-Equal 'Unchanged frame has no changed rows' 0 @(Get-ChangedFrameRows -Previous @('A','B') -Current @('A','B')).Count
Assert-Equal 'Changing only an ANSI selection role changes one row' '1' (@(Get-ChangedFrameRows -Previous @('Header','Normal Choice') -Current @('Header','Selected Choice')) -join ',')
Assert-Equal 'Moving selected row repaints old and new rows' '0,1' (@(Get-ChangedFrameRows -Previous @('Selected','Normal') -Current @('Normal','Selected')) -join ',')
Assert-Equal 'Shrinking the frame erases the trailing row' '1' (@(Get-ChangedFrameRows -Previous @('A','B') -Current @('A')) -join ',')
Assert-Equal 'Adding a row repaints only that row' '1' (@(Get-ChangedFrameRows -Previous @('A') -Current @('A','B')) -join ',')

﻿# Unit tests: TUI components (menu, line editor, wizard, layout, theme, icons).
Set-TestGroup 'Menu: numbering, navigation and shortcuts'
$items = @(@{ Label = 'One'; Value = 'a' }, @{ Label = 'Two'; Value = 'b' }, @{ Label = 'Three'; Value = 'c' }, @{ Label = 'Four'; Value = 'd' })
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '02'
Assert-Equal 'two-digit number selects the item' 'b' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '3'
Assert-Equal 'a single digit that cannot start a longer number selects the item' 'c' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } 'a'
Assert-True 'letters are not shortcuts (numbers only)' ($ui.Error -like '*exhausted*')
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } 'b'
Assert-True 'B does not go back and Q does not quit (Esc and Ctrl+C are the only non-numeric keys)' ($ui.Error -like '*exhausted*')
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '{Down}{Down}{Enter}'
Assert-Equal 'arrow down x2 + Enter selects third item' 'c' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '{Down}{Up}{Up}{Enter}'
Assert-Equal 'arrow navigation wraps around' 'd' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '{Enter}'
Assert-Equal 'Enter selects the highlighted (first) item' 'a' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '0{BS}2'
Assert-Equal 'Backspace removes a typed digit' 'b' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '09{Enter}'
Assert-True 'a number beyond the list is ignored' ($ui.Error -like '*exhausted*' -or $ui.Value.Item.Value -eq 'a')
$ui = Invoke-Ui { Show-Menu -Items @(@{ Label = 'X' }) -AllowBack -AllowQuit } '{Esc}'
Assert-Equal 'Escape goes back' 'Back' $ui.Value.Action
$ui = Invoke-Ui { Show-Menu -Items @(@{ Label = 'X' }) -AllowBack -AllowQuit } '{CtrlC}'
Assert-Equal 'Ctrl+C quits' 'Quit' $ui.Value.Action
$ui = Invoke-Ui { Show-Menu -Items @(@{ Label = 'X' }) } '{Esc}'
Assert-True 'Escape does nothing when Back is not allowed (waits for a real choice)' ($ui.Error -like '*exhausted*')
$dis = @(@{ Label = 'Off'; Enabled = $false; Reason = 'not available' }, @{ Label = 'On'; Value = 'on' })
$ui = Invoke-Ui { Show-Menu -Items $dis -AllowBack } '01{Enter}'
Assert-Equal 'disabled item cannot be chosen; selection starts on first enabled item' 'on' $ui.Value.Item.Value
Assert-Contains 'disabled item shows its reason' $ui.Output 'not available'
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '{Enter}'
Assert-Contains 'footer lists only keys that work (Esc Back, Ctrl+C Quit)' (Get-LastFrame $ui.Output) 'Ctrl+C Quit'
$ui = Invoke-Ui { Show-Menu -Items $items } '{Enter}'
Assert-NotContains 'footer hides Back/Quit when not allowed' (Get-LastFrame $ui.Output) 'Ctrl+C Quit'
$frame = Get-LastFrame $ui.Output
Assert-True 'rows read: Number, Icon, Option name' ($frame -match '(?m)^\s*(?:\S\s)?\s*01\s+\S+\s+One\s*$')
Assert-True 'numbers are zero-padded two digits (01..04) with no letters' (($frame -match '04\s+\S+\s+Four') -and ($frame -notmatch '(?m)^\s*(?:\S\s)?\s*[A-Za-z]\.'))
Assert-Contains 'footer explains number entry' $frame '01-04 Type a number'
# bigger lists: 01..09, 10, 11, 12 ... 100
$many = @(1..12 | ForEach-Object { @{ Label = "Item $_"; Value = $_ } })
$ui = Invoke-Ui { Show-Menu -Items $many -AllowBack } '05'
Assert-Equal '12 items: 05 selects item 5' 5 $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $many -AllowBack } '10'
Assert-Equal '12 items: 10 selects item 10' 10 $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $many -AllowBack } '12'
Assert-Equal '12 items: 12 selects item 12' 12 $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $many -AllowBack } '1{Enter}'
Assert-Equal '12 items: a prefix waits, Enter accepts it as item 1' 1 $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $many -AllowBack } '5'
Assert-Equal '12 items: 5 cannot start a longer number and selects item 5' 5 $ui.Value.Item.Value
$lots = @(1..120 | ForEach-Object { @{ Label = "Item $_"; Value = $_ } })
$ui = Invoke-Ui { Show-Menu -Items $lots -AllowBack } '100' -Height 60
Assert-Equal '120 items: numbering continues past 99 (100 selects item 100)' 100 $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $lots -AllowBack } '{End}{Enter}' -Height 60
Assert-Equal '120 items: End selects item 120' 120 $ui.Value.Item.Value
Assert-Contains '120 items: the last number is shown in full (no truncation)' (Get-LastFrame $ui.Output) '120'
$ui = Invoke-Ui { Show-Menu -Items $lots -AllowBack } '10{Enter}' -Height 60
Assert-Equal '120 items: 10 then Enter selects item 10' 10 $ui.Value.Item.Value
$many40 = @(1..40 | ForEach-Object { @{ Label = "Item $_"; Value = $_ } })
$ui = Invoke-Ui { Show-Menu -Items $many40 -AllowBack } '{End}{Enter}' -Height 14
Assert-Equal 'long list: End selects the last item' 40 $ui.Value.Item.Value
Assert-Contains 'long list: scrolled view still shows the selected item' (Get-LastFrame $ui.Output) 'Item 40'
Assert-Equal 'number format helper: 1, 9, 10, 99, 100' '01,09,10,99,100' ((1, 9, 10, 99, 100 | ForEach-Object { Format-MenuNumber $_ }) -join ',')
Assert-True 'no code path still defines letter hotkeys' (-not (Get-Command Get-MenuHotkeys -ErrorAction SilentlyContinue))

Set-TestGroup 'Main menu definition'
$mm = Get-MainMenuItems
$labels = @('Convert Video Format', 'Convert Audio Format', 'Extract Audio from Video', 'Trim / Cut Media', 'Merge Media', 'Compress Media', 'Resize / Scale Video', 'Video to GIF', 'Extract Frames / Images', 'Audio Tools', 'Subtitle Tools', 'Change Frame Rate', 'Filters & Color', 'Crop / Rotate / Flip', 'Text & Watermark', 'Change Playback Speed', 'Streaming / HLS', 'Media Information', 'Remux & Streams', 'Metadata & Chapters', 'Images & Slideshows', 'Video Enhancement', 'Record / Capture', 'Analyze & Detect', 'Batch Convert Folder', 'Advanced FFmpeg', 'FFmpeg Status / Settings', 'Check & Maintain FFmpeg Setup', 'Exit')
Assert-Equal 'main menu labels match the required text' ($labels -join '|') (($mm | ForEach-Object { $_.Label }) -join '|')
Assert-True 'Exit is the last numbered option (no exceptions, no letter key)' ($mm[$mm.Count - 1].Value -eq 'Quit')
Assert-True 'every menu item (including Exit) has a description' (@($mm | Where-Object { -not $_.Desc }).Count -eq 0)
Assert-True 'every menu item has an icon' (@($mm | Where-Object { -not $_.Icon }).Count -eq 0)
foreach ($tier in 'Emoji', 'Symbol') {
    Initialize-Renderer -Ansi $false -Unicode $tier -Sink Buffer -Width 100 -Height 30
    $glyphs = @($mm | ForEach-Object { Get-Icon $_.Icon })
    Assert-True "main menu: every option has its own icon in the $tier tier ($($glyphs.Count) distinct of $($mm.Count))" (@($glyphs | Select-Object -Unique).Count -eq $mm.Count)
}
Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 100 -Height 40
Assert-True 'main menu items carry no letter keys' (@($mm | Where-Object { $_.ContainsKey('Key') }).Count -eq 0)
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '11' -Height 60
Assert-Equal 'main menu: 11 opens Subtitle Tools' 'SubtitleTools' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '27' -Height 60
Assert-Equal 'main menu: 27 opens Status' 'Status' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '28' -Height 60
Assert-Equal 'main menu: 28 opens Check & Maintain' 'Maintenance' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '29' -Height 60
Assert-Equal 'main menu: 29 (the last number) is Exit' 'Quit' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '29' -Height 80
$f = Get-LastFrame $ui.Output
$missing = ''
foreach ($n in 1..29) { $num = ('{0:00}' -f $n); if ($f -notmatch "(?m)^\s*(?:\S\s)?\s*$num\s+\S+\s+\S") { $missing = $num; break } }
Assert-True 'all 29 options are numbered 01..29 in order, each as Number, Icon, Name' ($missing -eq '') "missing $missing"
Assert-True 'no option is labeled with a letter (A., B., [S], [Q] ...)' ($f -notmatch '(?m)^\s*(?:\S\s)?\s*\[?[A-Za-z]\]?[\.\)]\s')
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '29' -Height 80
Assert-Contains 'tall terminal shows a description under every option' $ui.Output 'Convert a video to another container or video format.'
Assert-Contains 'the last option shows its description too' $ui.Output 'Close FFmpeg User Manager.'
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '29' -Height 25
Assert-True 'short terminal keeps every item reachable (scrolling, selected item description shown)' ($ui.Value.Item.Value -eq 'Quit')

Set-TestGroup 'Layout: narrow / normal / wide terminals'
foreach ($w in 40, 60, 100, 160) {
    $ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '{End}{Enter}' -Width $w -Height 50
    $frame = Get-LastFrame $ui.Output
    $max = 0; foreach ($l in ($frame -split "`n")) { $tw = Get-TextWidth $l; if ($tw -gt $max) { $max = $tw } }
    $limit = [math]::Min($w, 101)
    Assert-True "width $w : no line exceeds the terminal width (max $max)" ($max -le $limit) "max=$max limit=$limit"
    $top = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '{Enter}' -Width $w -Height 50
    Assert-True "width $w : first and last option labels are intact" ($frame.Contains('Exit') -and (Get-LastFrame $top.Output).Contains('Convert Video Format'))
}
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '{End}{Enter}' -Width 40 -Height 50
Assert-True 'narrow layout is compact (descriptions of unselected items hidden)' (-not (Get-LastFrame $ui.Output).Contains('Keep only a selected time range'))
Assert-Equal 'compact flag on narrow terminal' $true (& { Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 50 -Height 30; Test-CompactLayout })
Assert-Equal 'not compact on a normal terminal' $false (& { Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 100 -Height 30; Test-CompactLayout })
Assert-Equal 'long text is truncated with an ellipsis' ('abc' + [string][char]0x2026) (& { Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 100 -Height 30; Limit-Text 'abcdefghij' 4 })

Set-TestGroup 'Theme and icons'
Initialize-Renderer -Ansi $false -Unicode 'Emoji' -Sink Buffer -Width 100 -Height 30
$emoji = Get-Icon 'Video'
Initialize-Renderer -Ansi $false -Unicode 'Symbol' -Sink Buffer -Width 100 -Height 30
$sym = Get-Icon 'Video'
Initialize-Renderer -Ansi $false -Unicode 'Ascii' -Sink Buffer -Width 100 -Height 30
$asc = Get-Icon 'Video'
Assert-True 'three icon tiers exist and differ (emoji, console symbol, ASCII tag)' (($emoji -ne $sym) -and ($sym -ne $asc) -and $asc -eq '[VIDEO]')
Assert-Equal 'bool true maps to the emoji tier and false to ASCII (compatibility)' "$emoji|$asc" ((& { Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 100 -Height 30; Get-Icon 'Video' }) + '|' + (& { Initialize-Renderer -Ansi $false -Unicode $false -Sink Buffer -Width 100 -Height 30; Get-Icon 'Video' }))
foreach ($n in (Get-IconNames)) {
    Initialize-Renderer -Ansi $false -Unicode 'Ascii' -Sink Buffer -Width 100 -Height 30
    Assert-True "icon '$n' has an ASCII-only fallback" ((Get-Icon $n) -match '^[\x20-\x7E]+$')
    Initialize-Renderer -Ansi $false -Unicode 'Symbol' -Sink Buffer -Width 100 -Height 30
    $g = Get-Icon $n
    Assert-True "icon '$n' has a console-safe symbol (one column, never empty)" (($g.Length -eq 1) -and ((Get-TextWidth $g) -eq 1))
    Initialize-Renderer -Ansi $false -Unicode 'Emoji' -Sink Buffer -Width 100 -Height 30
    Assert-True "icon '$n' has an emoji glyph" ((Get-Icon $n).Length -ge 1)
}
# Symbol-tier glyphs must belong to the Windows Glyph List 4 (WGL4): Consolas, Lucida Console, Courier New and
# Cascadia Mono all contain it, so the legacy console always has a glyph to draw.
$wgl4 = @(0x2022, 0x203C, 0x2229, 0x2642, 0x25CF, 0x25D8, 0x2660, 0x2663, 0x2665, 0x2190, 0x2191, 0x2192, 0x2193, 0x2194, 0x2195, 0x221A, 0x221E, 0x2248, 0x2261, 0x2302, 0x2500, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518, 0x2550, 0x256C, 0x25A0, 0x25B2, 0x25BA, 0x25BC, 0x25C4, 0x25CB, 0x263A, 0x263B, 0x263C, 0x2666, 0x266A, 0x266B)
function Test-Wgl4 { param([string]$Text) foreach ($ch in $Text.ToCharArray()) { $c = [int]$ch; if (-not (($c -ge 0x20 -and $c -le 0x7E) -or ($c -ge 0xA0 -and $c -le 0xFF) -or ($wgl4 -contains $c))) { return $false } }; return $true }
Initialize-Renderer -Ansi $false -Unicode 'Symbol' -Sink Buffer -Width 100 -Height 30
$notWgl = @(); foreach ($n in (Get-IconNames)) { $g = Get-Icon $n; if (-not (Test-Wgl4 $g)) { $notWgl += "$n=U+{0:X4}" -f [int][char]$g } }
Assert-True 'every symbol-tier icon is a WGL4 glyph (drawn by every Windows console font)' ($notWgl.Count -eq 0) ($notWgl -join ', ')
$boxBad = @(); foreach ($c in (Get-BoxChars).PSObject.Properties) { if (-not (Test-Wgl4 ([string]$c.Value))) { $boxBad += $c.Name } }
Assert-True 'symbol-tier frame characters are WGL4 glyphs' ($boxBad.Count -eq 0) ($boxBad -join ', ')
Initialize-Renderer -Ansi $false -Unicode 'Ascii' -Sink Buffer -Width 100 -Height 60
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '{Enter}' -Height 60 -Unicode $false
Assert-Contains 'ASCII tags are used only in the ASCII tier' $ui.Output '[VIDEO]'
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '{Enter}' -Height 60 -Unicode 'Symbol'
Assert-NotContains 'symbol tier never prints the ASCII tag (an icon is always a glyph)' $ui.Output '[VIDEO]'
Assert-Contains 'symbol tier shows the glyph between number and name' $ui.Output ('01 ' + [string][char]0x25BA + ' Convert Video Format')
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } '{Enter}' -Height 60 -Unicode 'Emoji'
Assert-Contains 'emoji tier shows the emoji between number and name' $ui.Output ('01 ' + [string][char]::ConvertFromUtf32(0x1F3AC) + ' Convert Video Format')
Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 100 -Height 60
$roles = @('PrimaryAccent', 'SecondaryAccent', 'Title', 'NormalText', 'DimText', 'Success', 'Warning', 'Error', 'Border', 'Selected', 'Muted')
Assert-True 'theme defines all required semantic roles' (@($roles | Where-Object { (Get-ThemeRoleNames) -notcontains $_ }).Count -eq 0)
Assert-Equal 'DimText is muted gray' 'DarkGray' (Get-ThemeConsoleColor 'DimText')
Assert-Equal 'unknown role falls back to normal text' (Get-ThemeConsoleColor 'NormalText') (Get-ThemeConsoleColor 'NoSuchRole')
# No hard-coded colors outside the theme
$hard = @(); foreach ($srcFile in Get-ChildItem -LiteralPath (Join-Path (Get-TestRoot) 'src') -Recurse -Filter '*.psm1') { if ($srcFile.Name -in @('Theme.psm1', 'Renderer.psm1')) { continue }; $t = Get-Content -LiteralPath $srcFile.FullName -Raw; if ($t -match '-ForegroundColor|\[ConsoleColor\]|\\e\[|\[char\]27') { $hard += $srcFile.Name } }
Assert-True 'colors are centralized (no ForegroundColor/ANSI codes outside Theme/Renderer)' ($hard.Count -eq 0) ($hard -join ',')

Set-TestGroup 'Line editor'
$ui = Invoke-Ui { Read-TuiLine -Prompt '> ' } 'hello{Enter}'
Assert-Equal 'typed text is returned' 'hello' $ui.Value.Text
$ui = Invoke-Ui { Read-TuiLine -Prompt '> ' } 'helo{Left}l{Enter}'
Assert-Equal 'Left + insert edits in the middle' 'hello' $ui.Value.Text
$ui = Invoke-Ui { Read-TuiLine -Prompt '> ' } 'abcd{BS}{BS}{Enter}'
Assert-Equal 'Backspace removes characters' 'ab' $ui.Value.Text
$ui = Invoke-Ui { Read-TuiLine -Prompt '> ' } 'abc{Home}{Del}{Enter}'
Assert-Equal 'Home + Delete' 'bc' $ui.Value.Text
$ui = Invoke-Ui { Read-TuiLine -Prompt '> ' } 'abc{Home}x{End}y{Enter}'
Assert-Equal 'Home/End movement' 'xabcy' $ui.Value.Text
$ui = Invoke-Ui { Read-TuiLine -Prompt '> ' } 'abc{Esc}'
Assert-Equal 'Escape returns Back' 'Back' $ui.Value.Status
$ui = Invoke-Ui { Read-TuiLine -Prompt '> ' -Initial 'seed' } '{Enter}'
Assert-Equal 'initial text is preserved' 'seed' $ui.Value.Text
$ui = Invoke-Ui { Read-TuiLine -Prompt '> ' } 'Тест-اختبار-日本{Enter}'
Assert-Equal 'Unicode input round-trips' 'Тест-اختبار-日本' $ui.Value.Text

Set-TestGroup 'Wizard framework'
function New-WizTestSteps {
    @(
        @{ Id = 'n'; Type = 'Integer'; Prompt = 'Number'; Help = 'a whole number'; Example = '5'; Min = 1; Max = 10; Label = 'Number' },
        @{ Id = 'c'; Type = 'Choice'; Prompt = 'Pick'; Choices = { param($W) @((New-Choice 'x' 'Ex'), (New-Choice 'y' 'Why')) }; Default = 'x' },
        @{ Id = 'yn'; Type = 'YesNo'; Prompt = 'Sure?'; Default = $true },
        @{ Id = 'only_x'; Type = 'Text'; Prompt = 'Only when c is x'; When = { param($W) $W.Answers['c'] -eq 'x' } }
    )
}
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps (New-WizTestSteps) } '99{Enter}{BS}{BS}0{Enter}{BS}abc{Enter}{BS}{BS}{BS}5{Enter}{Enter}{Enter}hi{Enter}'
Assert-Equal 'wizard completes after invalid entries' 'Completed' $ui.Value.Status
Assert-Equal 'invalid numbers (too big, too small, text) are rejected then corrected' 5 $ui.Value.Answers['n']
Assert-Contains 'out-of-range message is shown' $ui.Output 'at most 10'
Assert-Contains 'below-minimum message is shown' $ui.Output 'at least 1'
Assert-Contains 'non-number message is shown' $ui.Output 'must be a whole number'
Assert-Equal 'default choice accepted with Enter' 'x' $ui.Value.Answers['c']
Assert-Equal 'conditional step answered' 'hi' $ui.Value.Answers['only_x']
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps (New-WizTestSteps) } '5{Enter}2{Enter}{Enter}'
Assert-True 'conditional step is skipped when its condition is false' ((-not $ui.Value.Answers.ContainsKey('only_x')) -and $ui.Value.Status -eq 'Completed')
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps (New-WizTestSteps) } '5{Enter}{Esc}{BS}7{Enter}{Enter}{Enter}z{Enter}'
Assert-Equal 'Back returns to the previous question and allows a new answer' 7 $ui.Value.Answers['n']
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps (New-WizTestSteps) } '5{Enter}{Esc}{Enter}{Enter}{Enter}z{Enter}'
Assert-Equal 'Back preserves the previously entered value as default' 5 $ui.Value.Answers['n']
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps (New-WizTestSteps) } '{Esc}'
Assert-Equal 'Back on the first question cancels the wizard' 'Cancelled' $ui.Value.Status
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps (New-WizTestSteps) } '{CtrlC}'
Assert-Equal 'Ctrl+C cancels the wizard' 'Cancelled' $ui.Value.Status
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps (New-WizTestSteps) } '5{Enter}'
Assert-True 'multiple-choice options are rendered as Number, Icon, Name' ((Get-LastFrame $ui.Output) -match '(?m)^\s*(?:\S\s)?\s*01\s+\S+\s+Ex\s*$')
# Summary + build
$buildSteps = @(@{ Id = 'n'; Type = 'Integer'; Prompt = 'Number'; Min = 1; Max = 10 })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $buildSteps -Build { param($W) @{ Summary = @(, @('Number', [string]$W.Answers['n'])); Stages = @(@{ Name = 's'; Arguments = @('-i', 'a b.mp4', 'out.mp4') }); Notes = @() } } } '4{Enter}{Enter}'
Assert-Equal 'summary Start -> wizard completes with a job' 'Completed' $ui.Value.Status
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $buildSteps -Build { param($W) @{ Summary = @(, @('Number', [string]$W.Answers['n'])); Stages = @(@{ Name = 's'; Arguments = @('-i', 'a b.mp4', 'out.mp4') }); Notes = @() } } } '4{Enter}02{Esc}{Enter}'
Assert-Contains 'summary option 02 shows the generated command (Advanced)' $ui.Output 'Generated FFmpeg command'
Assert-Contains 'generated command quotes paths with spaces' $ui.Output '"a b.mp4"'
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $buildSteps -Build { param($W) throw 'This cannot be processed.' } } '4{Enter}{Enter}{Esc}'
Assert-Contains 'build error is shown to the user instead of crashing' $ui.Output 'This cannot be processed.'
Assert-True 'wizard survives a build error and returns to the last step' ($ui.Error -eq '' -and $ui.Value.Status -eq 'Cancelled')
# Goto
$goSteps = @(@{ Id = 'a'; Type = 'Text'; Prompt = 'A' }, @{ Id = 'b'; Type = 'YesNo'; Prompt = 'Again?'; OnAnswer = { param($v, $W) if ($v) { $W.Goto = 'a' } } }, @{ Id = 'c'; Type = 'Text'; Prompt = 'C' })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $goSteps } 'one{Enter}01{Clear}two{Enter}02end{Enter}'
Assert-True 'step can jump back to an earlier step (Goto)' ($ui.Value.Answers['a'] -eq 'two' -and $ui.Value.Answers['c'] -eq 'end')
# MultiChoice
$mcSteps = @(@{ Id = 'm'; Type = 'MultiChoice'; Prompt = 'Pick many'; Min = 1; Choices = { param($W) @((New-Choice 'a' 'A'), (New-Choice 'b' 'B'), (New-Choice 'c' 'C')) } })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $mcSteps } '010304'
Assert-Equal 'multi-choice toggles items and continues' 'a,c' (@($ui.Value.Answers['m']) -join ',')
# Files ordered list
$fa = New-Fixture 'w_a.mp4' @('-f', 'lavfi', '-i', 'testsrc=d=1:s=64x64:r=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p')
$fb = New-Fixture 'w_b.mp4' @('-f', 'lavfi', '-i', 'testsrc2=d=1:s=64x64:r=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p')
$fileSteps = @(@{ Id = 'f'; Type = 'Files'; Prompt = 'Files'; Min = 2 })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $fileSteps } ("$fa{Enter}" + '02' + "$fb{Enter}" + '{Enter}' + '01' + '04')
Assert-Equal 'file list: add, reorder (move up) and finish' ("$fb|$fa") (@($ui.Value.Answers['f']) -join '|')
$fileSteps1 = @(@{ Id = 'f'; Type = 'Files'; Prompt = 'Files'; Min = 1 })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $fileSteps1 } ("$fa{Enter}" + '02' + "$fb{Enter}" + '{Up}{Enter}' + '03' + '03')
Assert-Equal 'file list: remove an item' "$fb" (@($ui.Value.Answers['f']) -join '|')
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $fileSteps } ("$fa{Enter}" + '{Down}{Enter}')
Assert-True 'file list: cannot finish with fewer than the minimum files' ($ui.Error -like '*exhausted*')
# File step validations
$fs = @(@{ Id = 'f'; Type = 'File'; Prompt = 'File' })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $fs } ((Join-Path (Get-TestWork) 'missing.mp4') + '{Enter}{Clear}' + "`"$fa`"{Enter}")
Assert-Contains 'missing file is rejected with a message' $ui.Output 'File not found'
Assert-Equal 'quoted path is accepted' $fa $ui.Value.Answers['f']
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $fs } ("& '$fa'{Enter}")
Assert-Equal 'drag-and-drop style path (& ''...'') is accepted' $fa $ui.Value.Answers['f']

Set-TestGroup 'Dialogs'
$ui = Invoke-Ui { Show-Confirm -Title 'Sure?' -Default $false } '01'
Assert-Equal 'option 01 (Yes) confirms' $true $ui.Value
$ui = Invoke-Ui { Show-Confirm -Title 'Sure?' -Default $true } '{Enter}'
Assert-Equal 'Enter accepts the default' $true $ui.Value
$ui = Invoke-Ui { Show-Confirm -Title 'Sure?' -Default $true } '{Esc}'
Assert-Equal 'Escape means No' $false $ui.Value
$ui = Invoke-Ui { Show-Notice -Title 'T' -Lines @('l') -Actions @(, @('B', 'Back')) } '01'
Assert-Equal 'single-action notice works (array flattening safe)' 'B' $ui.Value
Assert-Contains 'single-action notice renders its label' $ui.Output '01 '

Set-TestGroup 'Wizard screen layout'
$lay = Invoke-Ui { Invoke-Wizard -Title 'Layout Test' -Steps @(@{ Id = 'c'; Type = 'Choice'; Prompt = 'Pick one'; Help = 'some help'; Choices = { param($W) @((New-Choice 'x' 'Ex')) } }) } '01'
$frame = Get-LastFrame $lay.Output
Assert-True 'choice screen: the workflow header/panels come first, then the question, then the options' (($frame.IndexOf('Layout Test') -ge 0) -and ($frame.IndexOf('Layout Test') -lt $frame.IndexOf('Pick one')) -and ($frame.IndexOf('Pick one') -lt $frame.IndexOf('Ex')))
