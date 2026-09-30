# Unit tests: TUI components (menu, line editor, wizard, layout, theme, icons).
Set-TestGroup 'Menu: navigation and shortcuts'
$items = @(@{ Label = 'One'; Key = '1'; Value = 'a' }, @{ Label = 'Two'; Key = '2'; Value = 'b' }, @{ Label = 'Three'; Key = 'A'; Value = 'c' }, @{ Label = 'Four'; Key = 'B'; Value = 'd' })
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '2'
Assert-Equal 'numeric shortcut selects item' 'b' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } 'a'
Assert-Equal 'letter shortcut (lower case) selects item' 'c' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '{Down}{Down}{Enter}'
Assert-Equal 'arrow down x2 + Enter selects third item' 'c' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '{Down}{Up}{Up}{Enter}'
Assert-Equal 'arrow navigation wraps around' 'd' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '{Enter}'
Assert-Equal 'Enter selects the highlighted (first) item' 'a' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items @(@{ Label = 'X'; Key = '1' }) -AllowBack -AllowQuit } '{Esc}'
Assert-Equal 'Escape goes back' 'Back' $ui.Value.Action
$ui = Invoke-Ui { Show-Menu -Items @(@{ Label = 'X'; Key = '1' }) -AllowBack -AllowQuit } 'b'
Assert-Equal 'B goes back when no item owns it' 'Back' $ui.Value.Action
$ui = Invoke-Ui { Show-Menu -Items @(@{ Label = 'X'; Key = '1' }) -AllowBack -AllowQuit } 'q'
Assert-Equal 'Q quits' 'Quit' $ui.Value.Action
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } 'b'
Assert-Equal 'item shortcut B takes priority over Back (main-menu rule)' 'd' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items @(@{ Label = 'X'; Key = '1' }) } '{Esc}'
Assert-True 'Escape does nothing when Back is not allowed (waits for a real choice)' ($ui.Error -like '*exhausted*')
$dis = @(@{ Label = 'Off'; Key = '1'; Enabled = $false; Reason = 'not available' }, @{ Label = 'On'; Key = '2'; Value = 'on' })
$ui = Invoke-Ui { Show-Menu -Items $dis -AllowBack } '1{Enter}'
Assert-Equal 'disabled item cannot be chosen; selection starts on first enabled item' 'on' $ui.Value.Item.Value
Assert-Contains 'disabled item shows its reason' $ui.Output 'not available'
$ui = Invoke-Ui { Show-Menu -Items $items -AllowBack -AllowQuit } '{Enter}'
Assert-Contains 'footer only lists keys that work (Esc Back, Q Quit)' (Get-LastFrame $ui.Output) 'Q Quit'
$ui = Invoke-Ui { Show-Menu -Items $items } '{Enter}'
Assert-NotContains 'footer hides Back/Quit when not allowed' (Get-LastFrame $ui.Output) 'Q Quit'
$many = @(1..40 | ForEach-Object { @{ Label = "Item $_"; Value = $_ } })
$ui = Invoke-Ui { Show-Menu -Items $many -AutoKeys -AllowBack } '{End}{Enter}' -Height 14
Assert-Equal 'long list: End selects the last item' 40 $ui.Value.Item.Value
Assert-Contains 'long list: scrolled view still shows the selected item' (Get-LastFrame $ui.Output) 'Item 40'
$ui = Invoke-Ui { Show-Menu -Items $many -AutoKeys -AllowBack } '9' -Height 14
Assert-Equal 'auto keys: 9 selects item 9' 9 $ui.Value.Item.Value
$hk = Get-MenuHotkeys 12 @('C')
Assert-True 'auto hotkeys skip reserved B and Q and excluded keys' (($hk -notcontains 'B') -and ($hk -notcontains 'Q') -and ($hk -notcontains 'C'))

Set-TestGroup 'Main menu definition'
$mm = Get-MainMenuItems
$expected = @('1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'S', 'Q')
Assert-Equal 'main menu keys match the required layout' ($expected -join ',') (($mm | ForEach-Object { $_.Key }) -join ',')
$labels = @('Convert Video Format', 'Convert Audio Format', 'Extract Audio from Video', 'Trim / Cut Media', 'Merge Media', 'Compress Media', 'Resize / Scale Video', 'Video to GIF', 'Extract Frames / Images', 'Audio Tools', 'Subtitle Tools', 'Change Frame Rate', 'Filters & Color', 'Crop / Rotate / Flip', 'Text & Watermark', 'Change Playback Speed', 'Streaming / HLS', 'Media Information', 'FFmpeg Status / Settings', 'Exit')
Assert-Equal 'main menu labels match the required text' ($labels -join '|') (($mm | ForEach-Object { $_.Label }) -join '|')
Assert-True 'every menu item has a description (except Exit)' (@($mm | Where-Object { $_.Key -ne 'Q' -and -not $_.Desc }).Count -eq 0)
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } 'B' -Height 60
Assert-Equal 'main menu: B opens Subtitle Tools (not Back)' 'SubtitleTools' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } 'S' -Height 60
Assert-Equal 'main menu: S opens Status' 'Status' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } 'Q' -Height 60
Assert-Equal 'main menu: Q exits' 'Quit' $ui.Value.Item.Value
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } 'Q' -Height 60
Assert-Contains 'tall terminal shows descriptions inline' $ui.Output 'Convert a video to another container or video format.'
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } 'Q' -Height 25
Assert-True 'short terminal keeps every item reachable (scrolling, selected item description shown)' ($ui.Value.Item.Value -eq 'Quit')

Set-TestGroup 'Layout: narrow / normal / wide terminals'
foreach ($w in 40, 60, 100, 160) {
    $ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } 'Q' -Width $w -Height 50
    $frame = Get-LastFrame $ui.Output
    $max = 0; foreach ($l in ($frame -split "`n")) { $tw = Get-TextWidth $l; if ($tw -gt $max) { $max = $tw } }
    $limit = [math]::Min($w, 101)
    Assert-True "width $w : no line exceeds the terminal width (max $max)" ($max -le $limit) "max=$max limit=$limit"
    Assert-True "width $w : selected action label is intact" ($frame.Contains('Exit') -and $frame.Contains('Convert Video Format'))
}
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } 'Q' -Width 40 -Height 50
Assert-True 'narrow layout is compact (descriptions of unselected items hidden)' (-not (Get-LastFrame $ui.Output).Contains('Save frames from a video as JPG'))
Assert-Equal 'compact flag on narrow terminal' $true (& { Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 50 -Height 30; Test-CompactLayout })
Assert-Equal 'not compact on a normal terminal' $false (& { Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 100 -Height 30; Test-CompactLayout })
Assert-Equal 'long text is truncated with an ellipsis' ('abc' + [string][char]0x2026) (& { Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 100 -Height 30; Limit-Text 'abcdefghij' 4 })

Set-TestGroup 'Theme and icons'
Initialize-Renderer -Ansi $false -Unicode $true -Sink Buffer -Width 100 -Height 30
$uni = Get-Icon 'Video'
Initialize-Renderer -Ansi $false -Unicode $false -Sink Buffer -Width 100 -Height 30
$asc = Get-Icon 'Video'
Assert-True 'Unicode icon differs from the ASCII fallback' ($uni -ne $asc -and $asc -eq '[VIDEO]')
foreach ($n in (Get-IconNames)) { Assert-True "icon '$n' has an ASCII-only fallback" ((Get-Icon $n) -match '^[\x20-\x7E]+$') }
$ui = Invoke-Ui { Show-Menu -Items $mm -ShowHeader } 'Q' -Height 60 -Unicode $false
Assert-Contains 'ASCII fallback markers are used when icons are disabled' $ui.Output '[VIDEO]'
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
Assert-Contains 'multiple-choice options are rendered with numbers' (Get-LastFrame $ui.Output) '1. Ex'
# Summary + build
$buildSteps = @(@{ Id = 'n'; Type = 'Integer'; Prompt = 'Number'; Min = 1; Max = 10 })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $buildSteps -Build { param($W) @{ Summary = @(, @('Number', [string]$W.Answers['n'])); Stages = @(@{ Name = 's'; Arguments = @('-i', 'a b.mp4', 'out.mp4') }); Notes = @() } } } '4{Enter}{Enter}'
Assert-Equal 'summary Start -> wizard completes with a job' 'Completed' $ui.Value.Status
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $buildSteps -Build { param($W) @{ Summary = @(, @('Number', [string]$W.Answers['n'])); Stages = @(@{ Name = 's'; Arguments = @('-i', 'a b.mp4', 'out.mp4') }); Notes = @() } } } '4{Enter}V{Esc}{Enter}'
Assert-Contains 'summary [V] shows the generated command (Advanced)' $ui.Output 'Generated FFmpeg command'
Assert-Contains 'generated command quotes paths with spaces' $ui.Output '"a b.mp4"'
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $buildSteps -Build { param($W) throw 'This cannot be processed.' } } '4{Enter}{Enter}{Esc}'
Assert-Contains 'build error is shown to the user instead of crashing' $ui.Output 'This cannot be processed.'
Assert-True 'wizard survives a build error and returns to the last step' ($ui.Error -eq '' -and $ui.Value.Status -eq 'Cancelled')
# Goto
$goSteps = @(@{ Id = 'a'; Type = 'Text'; Prompt = 'A' }, @{ Id = 'b'; Type = 'YesNo'; Prompt = 'Again?'; OnAnswer = { param($v, $W) if ($v) { $W.Goto = 'a' } } }, @{ Id = 'c'; Type = 'Text'; Prompt = 'C' })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $goSteps } 'one{Enter}Y{Clear}two{Enter}Nend{Enter}'
Assert-True 'step can jump back to an earlier step (Goto)' ($ui.Value.Answers['a'] -eq 'two' -and $ui.Value.Answers['c'] -eq 'end')
# MultiChoice
$mcSteps = @(@{ Id = 'm'; Type = 'MultiChoice'; Prompt = 'Pick many'; Min = 1; Choices = { param($W) @((New-Choice 'a' 'A'), (New-Choice 'b' 'B'), (New-Choice 'c' 'C')) } })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $mcSteps } '13C'
Assert-Equal 'multi-choice toggles items and continues' 'a,c' (@($ui.Value.Answers['m']) -join ',')
# Files ordered list
$fa = New-Fixture 'w_a.mp4' @('-f', 'lavfi', '-i', 'testsrc=d=1:s=64x64:r=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p')
$fb = New-Fixture 'w_b.mp4' @('-f', 'lavfi', '-i', 'testsrc2=d=1:s=64x64:r=10', '-c:v', 'libx264', '-pix_fmt', 'yuv420p')
$fileSteps = @(@{ Id = 'f'; Type = 'Files'; Prompt = 'Files'; Min = 2 })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $fileSteps } ("$fa{Enter}" + 'A' + "$fb{Enter}" + '{Enter}U' + 'D')
Assert-Equal 'file list: add, reorder (move up) and finish' ("$fb|$fa") (@($ui.Value.Answers['f']) -join '|')
$fileSteps1 = @(@{ Id = 'f'; Type = 'Files'; Prompt = 'Files'; Min = 1 })
$ui = Invoke-Ui { Invoke-Wizard -Title 'T' -Steps $fileSteps1 } ("$fa{Enter}" + 'A' + "$fb{Enter}" + '{Up}{Enter}R' + 'D')
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
$ui = Invoke-Ui { Show-Confirm -Title 'Sure?' -Default $false } 'y'
Assert-Equal 'Y confirms' $true $ui.Value
$ui = Invoke-Ui { Show-Confirm -Title 'Sure?' -Default $true } '{Enter}'
Assert-Equal 'Enter accepts the default' $true $ui.Value
$ui = Invoke-Ui { Show-Confirm -Title 'Sure?' -Default $true } '{Esc}'
Assert-Equal 'Escape means No' $false $ui.Value
$ui = Invoke-Ui { Show-Notice -Title 'T' -Lines @('l') -Actions @(, @('B', 'Back')) } 'b'
Assert-Equal 'single-action notice works (array flattening safe)' 'B' $ui.Value
Assert-Contains 'single-action notice renders its label' $ui.Output '[B] Back'

Set-TestGroup 'Wizard screen layout'
$lay = Invoke-Ui { Invoke-Wizard -Title 'Layout Test' -Steps @(@{ Id = 'c'; Type = 'Choice'; Prompt = 'Pick one'; Help = 'some help'; Choices = { param($W) @((New-Choice 'x' 'Ex')) } }) } '1'
$frame = Get-LastFrame $lay.Output
Assert-True 'choice screen: the workflow header/panels come first, then the question, then the options' (($frame.IndexOf('Layout Test') -ge 0) -and ($frame.IndexOf('Layout Test') -lt $frame.IndexOf('Pick one')) -and ($frame.IndexOf('Pick one') -lt $frame.IndexOf('1. Ex')))
