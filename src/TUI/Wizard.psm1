# Wizard.psm1 - the reusable question/answer framework. Workflows describe steps as data; this module
# renders them, validates answers, supports Back with preserved answers, and ends with a summary screen.
Set-StrictMode -Version 2.0

function New-WizardState {
    param([string]$Title, [string]$Description = '', [string]$Icon = '')
    return @{
        Title = $Title; Description = $Description; Icon = $Icon
        Answers = @{}; Data = @{}; Panels = [ordered]@{}
        Goto = $null; Step = $null; Error = ''
    }
}

function Set-WizardPanel {
    # Persistent info panel shown above every following question (e.g. the Source summary).
    param($W, [string]$Key, [string]$Title, [object[]]$Rows, [int]$LabelWidth = 10)
    $W.Panels[$Key] = @{ Title = $Title; Rows = $Rows; LabelWidth = $LabelWidth }
}

function Remove-WizardPanel { param($W, [string]$Key) if ($W.Panels.Contains($Key)) { $W.Panels.Remove($Key) } }

function Get-WizardTopLineCount {
    param($W)
    $n = 3
    if ($W.Description) { $n++ }
    foreach ($k in $W.Panels.Keys) { $n += $W.Panels[$k].Rows.Count + 2 }
    return $n + 3
}

function Write-WizardTop {
    param($W)
    $t = $W.Title
    if ($W.Icon) { $t = (Get-Icon $W.Icon) + '  ' + $W.Title }
    Write-Rule -Title $t
    if ($W.Description) { Write-UiSegments @(, @(('  ' + $W.Description), 'DimText')) }
    foreach ($k in @($W.Panels.Keys)) {
        $p = $W.Panels[$k]
        Write-Panel -Title $p.Title -Rows $p.Rows -LabelWidth $p.LabelWidth
    }
    Write-UiBlank
}

function Resolve-StepValue {
    # Evaluates a value that may be a scriptblock taking the wizard state.
    param($Value, $W)
    if ($Value -is [scriptblock]) { return (& $Value $W) }
    return $Value
}

function Test-StepVisible {
    param($Step, $W)
    if ($Step.ContainsKey('When') -and $Step.When) { return [bool](& $Step.When $W) }
    return $true
}

function Format-ValueForDisplay {
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [double]) { return $Value.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture) }
    return [string]$Value
}

# ---- text-like steps ---------------------------------------------------------

function Convert-TextAnswer {
    # Parses free text for a step type. Returns @{ Ok; Value; Error } (never throws).
    param($Step, [string]$Text, $W)
    $type = [string]$Step.Type
    if ($Step.ContainsKey('CustomType') -and $Step.CustomType) { $type = [string]$Step.CustomType }
    $min = $null; if ($Step.ContainsKey('Min')) { $min = $Step.Min }
    $max = $null; if ($Step.ContainsKey('Max')) { $max = $Step.Max }
    $label = 'Value'; if ($Step.ContainsKey('Label') -and $Step.Label) { $label = [string]$Step.Label }
    $isOptional = ($Step.ContainsKey('Optional') -and $Step.Optional)
    if ([string]::IsNullOrWhiteSpace($Text) -and $type -ne 'Text') {
        if ($isOptional) { return New-ValidationResult $true $null }
        return New-ValidationResult $false $null 'This value is required.'
    }
    switch ($type) {
        'Integer' { $r = ConvertFrom-IntegerText $Text $min $max $label }
        'Decimal' { $r = ConvertFrom-DecimalText $Text $min $max $label }
        'Timestamp' { $r = ConvertFrom-TimestampText $Text }
        'Bitrate' { $r = ConvertFrom-BitrateText $Text $label }
        'FrameRate' { $r = ConvertFrom-FrameRateText $Text }
        'Color' { $r = ConvertFrom-ColorText $Text }
        'Resolution' {
            $t = $Text.Trim().ToLowerInvariant().Replace(' ', '')
            if ($t -match '^(\d+)x(\d+)$') {
                if ([int]$Matches[1] -lt 16 -or [int]$Matches[2] -lt 16 -or [int]$Matches[1] -gt 16384 -or [int]$Matches[2] -gt 16384) { return New-ValidationResult $false $null 'Width and height must be between 16 and 16384 pixels.' }
                $r = New-ValidationResult $true $t
            } elseif ($t -match '^\d+$') {
                if ([int]$t -lt 16 -or [int]$t -gt 16384) { return New-ValidationResult $false $null 'Width must be between 16 and 16384 pixels.' }
                $r = New-ValidationResult $true $t
            } else { return New-ValidationResult $false $null 'Enter width x height such as 1280x720, or just a width such as 1280.' }
        }
        'File' {
            $p = Resolve-UserPath $Text
            if (-not $p) { return New-ValidationResult $false $null 'That is not a valid path.' }
            if (-not ($Step.ContainsKey('MustExist') -and $Step.MustExist -eq $false)) {
                $e = Test-InputFile $p
                if ($e) { return New-ValidationResult $false $null $e }
            }
            $r = New-ValidationResult $true $p
        }
        'Directory' {
            $p = Resolve-UserPath $Text
            if (-not $p) { return New-ValidationResult $false $null 'That is not a valid folder path.' }
            if (Test-Path -LiteralPath $p -PathType Leaf) { return New-ValidationResult $false $null 'That path is a file, not a folder.' }
            if ($Step.ContainsKey('MustExist') -and $Step.MustExist -and -not (Test-Path -LiteralPath $p -PathType Container)) { return New-ValidationResult $false $null "Folder not found: $p" }
            $r = New-ValidationResult $true $p
        }
        default {
            $t = $Text.Trim()
            if (-not ($Step.ContainsKey('NoTrim') -and $Step.NoTrim)) { $Text = $t }
            if ([string]::IsNullOrEmpty($Text) -and -not $isOptional) { return New-ValidationResult $false $null 'This value is required.' }
            $r = New-ValidationResult $true $Text
        }
    }
    if ($r.Ok -and $Step.ContainsKey('Validate') -and $Step.Validate) {
        $msg = $null
        try { $msg = & $Step.Validate $r.Value $W } catch { $msg = "Validation failed: $($_.Exception.Message)" }
        if ($msg) { return New-ValidationResult $false $null ([string]$msg) }
    }
    return $r
}

function Read-TextStep {
    # Returns @{ Status = Ok|Back|Quit; Value }.
    param($Step, $W, $Initial = $null)
    $error1 = ''
    $initText = ''
    if ($null -ne $Initial) { $initText = Format-ValueForDisplay $Initial }
    $def = $null
    if ($Step.ContainsKey('Default')) { $def = Resolve-StepValue $Step.Default $W }
    $browse = $false
    if ($Step.Type -eq 'File' -or $Step.Type -eq 'Directory') { $browse = Test-NativePickerAvailable }
    while ($true) {
        Hide-Cursor
        Start-Frame
        Write-WizardTop $W
        Write-UiSegments @(, @([string]$Step.Prompt, 'Title'))
        if ($Step.ContainsKey('Help') -and $Step.Help) { foreach ($l in (Split-TextLines ([string]$Step.Help) ((Get-UiWidth) - 4))) { Write-Ui -Text ('   ' + $l) -Role DimText } }
        if ($Step.ContainsKey('Example') -and $Step.Example) { Write-Ui -Text ('   Example: ' + $Step.Example) -Role DimText }
        if ($null -ne $def -and "$def" -ne '') { Write-Ui -Text ('   Default: ' + (Format-ValueForDisplay $def) + $(if ($Step.ContainsKey('Unit') -and $Step.Unit) { ' ' + $Step.Unit } else { '' }) + '   (press Enter to accept)') -Role DimText }
        elseif ($Step.ContainsKey('Optional') -and $Step.Optional) { Write-Ui -Text '   Optional - press Enter to skip.' -Role DimText }
        if ($error1) { Write-Ui -Text ('   ' + (Get-Icon 'Fail') + ' ' + $error1) -Role Error }
        Write-UiBlank
        Stop-Frame
        $hint = @(@('Enter', 'Confirm'), @('Esc', 'Back'), @('Ctrl+U', 'Clear'))
        if ($browse) { $hint += , @('Tab', 'Browse...') }
        Write-KeyHints $hint
        $line = Read-TuiLine -Prompt '> ' -Initial $initText -AllowBrowse:$browse
        if ($line.Status -eq 'Back') { return @{ Status = 'Back'; Value = $null } }
        if ($line.Status -eq 'Quit') { return @{ Status = 'Quit'; Value = $null } }
        if ($line.Status -eq 'Browse') {
            $mode = if ($Step.Type -eq 'Directory') { 'Folder' } else { 'File' }
            $pick = Show-NativePicker -Mode $mode
            if ($pick) { $initText = $pick }
            continue
        }
        $text = $line.Text
        if ([string]::IsNullOrWhiteSpace($text) -and $null -ne $def -and "$def" -ne '') { $text = Format-ValueForDisplay $def }
        $r = Convert-TextAnswer $Step $text $W
        if ($r.Ok) { return @{ Status = 'Ok'; Value = $r.Value } }
        $error1 = $r.Error
        $initText = $line.Text
    }
}

# ---- menu-like steps ----------------------------------------------------------

function Read-ChoiceStep {
    param($Step, $W, $Initial = $null)
    $top = { Write-WizardTop $W }.GetNewClosure()
    $choices = @(Resolve-StepValue $Step.Choices $W)
    $items = @()
    $custom = $null
    if ($Step.ContainsKey('AllowCustom') -and $Step.AllowCustom) { $custom = $Step.AllowCustom }
    $hk = Get-MenuHotkeys $choices.Count $(if ($custom) { @('C') } else { @() })
    $idx = 0
    $selIndex = 0
    $def = $Initial
    if ($null -eq $def -and $Step.ContainsKey('Default')) { $def = Resolve-StepValue $Step.Default $W }
    for ($i = 0; $i -lt $choices.Count; $i++) {
        $c = $choices[$i]
        $en = $true; if ($c.ContainsKey('Enabled')) { $en = [bool]$c.Enabled }
        $desc = ''; if ($c.ContainsKey('Desc')) { $desc = [string]$c.Desc }
        $reason = ''; if ($c.ContainsKey('Reason')) { $reason = [string]$c.Reason }
        $items += , @{ Label = [string]$c.Label; Desc = $desc; Key = $hk[$i]; Value = $i; Enabled = $en; Reason = $reason }
        if ($null -ne $def -and (Format-ValueForDisplay $c.Value) -eq (Format-ValueForDisplay $def)) { $selIndex = $i }
    }
    $customIndex = -1
    if ($custom) {
        $customIndex = $items.Count
        $cl = 'Custom...'; if ($custom.ContainsKey('Label')) { $cl = [string]$custom.Label }
        $cd = ''; if ($custom.ContainsKey('Desc')) { $cd = [string]$custom.Desc }
        $items += , @{ Label = $cl; Desc = $cd; Key = 'C'; Value = -2; Enabled = $true }
        if ($null -ne $def -and $selIndex -eq 0 -and $choices.Count -gt 0 -and (Format-ValueForDisplay $choices[0].Value) -ne (Format-ValueForDisplay $def)) { $selIndex = $customIndex }
    }
    while ($true) {
        $help = ''; if ($Step.ContainsKey('Help')) { $help = [string]$Step.Help }
        $r = Show-Menu -Title ([string]$Step.Prompt) -Subtitle $help -Items $items -AllowBack -InitialIndex $selIndex -InfoRenderer $top -InfoLines (Get-WizardTopLineCount $W)
        if ($r.Action -eq 'Back') { return @{ Status = 'Back'; Value = $null } }
        if ($r.Action -eq 'Quit') { return @{ Status = 'Quit'; Value = $null } }
        if ($r.Item.Value -eq -2) {
            $cs = @{}
            foreach ($k in $custom.Keys) { $cs[$k] = $custom[$k] }
            $cs['Prompt'] = $(if ($custom.ContainsKey('Prompt')) { $custom.Prompt } else { [string]$Step.Prompt })
            if (-not $cs.ContainsKey('Type')) { $cs['Type'] = 'Text' }
            $cs['CustomType'] = $cs['Type']
            if ($cs.ContainsKey('ValueLabel')) { $cs['Label'] = $cs['ValueLabel'] } else { $cs.Remove('Label') }
            $res = Read-TextStep $cs $W $null
            if ($res.Status -eq 'Ok') {
                # The step-level validation also applies to values typed through the custom entry.
                $msg = $null
                if ($Step.ContainsKey('Validate') -and $Step.Validate) { $msg = & $Step.Validate $res.Value $W }
                if ($msg) { $null = Show-Notice -Title 'That value cannot be used' -Lines @([string]$msg) -Kind Warning; $selIndex = $customIndex; continue }
                return @{ Status = 'Ok'; Value = $res.Value }
            }
            if ($res.Status -eq 'Quit') { return @{ Status = 'Quit'; Value = $null } }
            $selIndex = $customIndex
            continue
        }
        $val = $choices[[int]$r.Item.Value].Value
        if ($Step.ContainsKey('Validate') -and $Step.Validate) {
            $msg = & $Step.Validate $val $W
            if ($msg) { $null = Show-Notice -Title 'That choice cannot be used' -Lines @([string]$msg) -Kind Warning; $selIndex = [int]$r.Item.Value; continue }
        }
        return @{ Status = 'Ok'; Value = $val }
    }
}

function Read-MultiChoiceStep {
    param($Step, $W, $Initial = $null)
    $top = { Write-WizardTop $W }.GetNewClosure()
    $choices = @(Resolve-StepValue $Step.Choices $W)
    $selected = New-Object System.Collections.Generic.HashSet[string]
    $start = $Initial
    if ($null -eq $start -and $Step.ContainsKey('Default')) { $start = Resolve-StepValue $Step.Default $W }
    foreach ($v in @($start)) { if ($null -ne $v) { [void]$selected.Add((Format-ValueForDisplay $v)) } }
    $min = 0; if ($Step.ContainsKey('Min')) { $min = [int]$Step.Min }
    $cursor = 0
    $hk = Get-MenuHotkeys $choices.Count @('C')
    while ($true) {
        $items = @()
        for ($i = 0; $i -lt $choices.Count; $i++) {
            $c = $choices[$i]
            $mark = if ($selected.Contains((Format-ValueForDisplay $c.Value))) { '[x] ' } else { '[ ] ' }
            $d = ''; if ($c.ContainsKey('Desc')) { $d = [string]$c.Desc }
            $items += , @{ Label = $mark + [string]$c.Label; Desc = $d; Key = $hk[$i]; Value = $i }
        }
        $items += , @{ Label = 'Continue'; Desc = "Select at least $min item(s), then continue."; Key = 'C'; Value = -1; Enabled = ($selected.Count -ge $min); Reason = "Select at least $min item(s) first." }
        $help = 'Select an item to toggle it, then choose Continue.'; if ($Step.ContainsKey('Help') -and $Step.Help) { $help = [string]$Step.Help }
        $r = Show-Menu -Title ([string]$Step.Prompt) -Subtitle $help -Items $items -AllowBack -InitialIndex $cursor -InfoRenderer $top -InfoLines (Get-WizardTopLineCount $W) -ExtraHints @(, @('C', 'Continue'))
        if ($r.Action -eq 'Back') { return @{ Status = 'Back'; Value = $null } }
        if ($r.Action -eq 'Quit') { return @{ Status = 'Quit'; Value = $null } }
        if ($r.Item.Value -eq -1) {
            $vals = @(); foreach ($c in $choices) { if ($selected.Contains((Format-ValueForDisplay $c.Value))) { $vals += , $c.Value } }
            return @{ Status = 'Ok'; Value = $vals }
        }
        $cursor = [int]$r.Item.Value
        $key = Format-ValueForDisplay $choices[$cursor].Value
        if (-not $selected.Add($key)) { [void]$selected.Remove($key) }
    }
}

function Read-YesNoStep {
    param($Step, $W, $Initial = $null)
    $top = { Write-WizardTop $W }.GetNewClosure()
    $def = $Initial
    if ($null -eq $def -and $Step.ContainsKey('Default')) { $def = Resolve-StepValue $Step.Default $W }
    $yes = 'Yes'; $no = 'No'
    if ($Step.ContainsKey('YesLabel')) { $yes = [string]$Step.YesLabel }
    if ($Step.ContainsKey('NoLabel')) { $no = [string]$Step.NoLabel }
    $yd = ''; if ($Step.ContainsKey('YesDesc')) { $yd = [string]$Step.YesDesc }
    $nd = ''; if ($Step.ContainsKey('NoDesc')) { $nd = [string]$Step.NoDesc }
    $items = @(@{ Label = $yes; Key = 'Y'; Desc = $yd; Value = $true }, @{ Label = $no; Key = 'N'; Desc = $nd; Value = $false })
    $sel = 1; if ($def -eq $true) { $sel = 0 }
    $help = ''; if ($Step.ContainsKey('Help')) { $help = [string]$Step.Help }
    $r = Show-Menu -Title ([string]$Step.Prompt) -Subtitle $help -Items $items -AllowBack -InitialIndex $sel -InfoRenderer $top -InfoLines (Get-WizardTopLineCount $W)
    if ($r.Action -eq 'Back') { return @{ Status = 'Back'; Value = $null } }
    if ($r.Action -eq 'Quit') { return @{ Status = 'Quit'; Value = $null } }
    return @{ Status = 'Ok'; Value = [bool]$r.Item.Value }
}

function Read-FilesStep {
    # Ordered multi-file list: add, move up/down, remove.
    param($Step, $W, $Initial = $null)
    $top = { Write-WizardTop $W }.GetNewClosure()
    $files = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Initial) { foreach ($f in @($Initial)) { $files.Add([string]$f) } }
    $min = 1; if ($Step.ContainsKey('Min')) { $min = [int]$Step.Min }
    $one = @{ Type = 'File'; Prompt = [string]$Step.Prompt; Help = $(if ($Step.ContainsKey('Help')) { $Step.Help } else { '' }); Validate = $(if ($Step.ContainsKey('Validate')) { $Step.Validate } else { $null }) }
    $cursor = 0
    while ($true) {
        if ($files.Count -eq 0) {
            $r = Read-TextStep $one $W $null
            if ($r.Status -ne 'Ok') { return $r }
            $files.Add([string]$r.Value)
            continue
        }
        $items = @()
        for ($i = 0; $i -lt $files.Count; $i++) {
            $items += , @{ Label = ('{0}. {1}' -f ($i + 1), [System.IO.Path]::GetFileName($files[$i])); Desc = $files[$i]; Value = $i }
        }
        $items += , @{ Label = 'Add another file'; Key = 'A'; Value = 'add'; Desc = 'Append a file to the end of the list.' }
        $items += , @{ Label = 'Done - continue'; Key = 'D'; Value = 'done'; Desc = "Continue with the files listed above (at least $min required)."; Enabled = ($files.Count -ge $min); Reason = "Add at least $min file(s) first." }
        $r = Show-Menu -Title ([string]$Step.Prompt) -Subtitle 'Files are processed in this order. Select a file to reorder or remove it.' -Items $items -AllowBack -InitialIndex $cursor -InfoRenderer $top -InfoLines (Get-WizardTopLineCount $W)
        if ($r.Action -eq 'Back') { return @{ Status = 'Back'; Value = $null } }
        if ($r.Action -eq 'Quit') { return @{ Status = 'Quit'; Value = $null } }
        $v = $r.Item.Value
        if ($v -eq 'done') { return @{ Status = 'Ok'; Value = $files.ToArray() } }
        if ($v -eq 'add') {
            $a = Read-TextStep $one $W $null
            if ($a.Status -eq 'Ok') { $files.Add([string]$a.Value); $cursor = $files.Count - 1 }
            elseif ($a.Status -eq 'Quit') { return $a }
            continue
        }
        $i = [int]$v
        $cursor = $i
        $sub = @(
            @{ Label = 'Move up'; Key = 'U'; Value = 'up'; Enabled = ($i -gt 0); Reason = 'Already first.' },
            @{ Label = 'Move down'; Key = 'D'; Value = 'down'; Enabled = ($i -lt $files.Count - 1); Reason = 'Already last.' },
            @{ Label = 'Remove from list'; Key = 'R'; Value = 'remove' }
        )
        $s = Show-Menu -Title ('File ' + ($i + 1) + ': ' + [System.IO.Path]::GetFileName($files[$i])) -Subtitle $files[$i] -Items $sub -AllowBack
        if ($s.Action -eq 'Select') {
            switch ($s.Item.Value) {
                'up' { $t = $files[$i]; $files[$i] = $files[$i - 1]; $files[$i - 1] = $t; $cursor = $i - 1 }
                'down' { $t = $files[$i]; $files[$i] = $files[$i + 1]; $files[$i + 1] = $t; $cursor = $i + 1 }
                'remove' { $files.RemoveAt($i); $cursor = 0 }
            }
        }
    }
}

function Read-InfoStep {
    param($Step, $W)
    $lines = @(Resolve-StepValue $Step.Lines $W)
    $r = Show-Notice -Title ([string]$Step.Prompt) -Lines $lines -Kind Info -Actions @(@('Enter', 'Continue'), @('Esc', 'Back'))
    if ($r -eq 'ESC') { return @{ Status = 'Back'; Value = $null } }
    if ($r -eq 'CTRLC') { return @{ Status = 'Quit'; Value = $null } }
    return @{ Status = 'Ok'; Value = $true }
}

function Invoke-WizardStep {
    param($Step, $W, $Initial)
    switch ([string]$Step.Type) {
        'Choice' { return (Read-ChoiceStep $Step $W $Initial) }
        'MultiChoice' { return (Read-MultiChoiceStep $Step $W $Initial) }
        'YesNo' { return (Read-YesNoStep $Step $W $Initial) }
        'Files' { return (Read-FilesStep $Step $W $Initial) }
        'Info' { return (Read-InfoStep $Step $W) }
        'Custom' { return (& $Step.Run $W $Step $Initial) }
        default { return (Read-TextStep $Step $W $Initial) }
    }
}

function Show-WizardSummary {
    # Returns 'Start' | 'Back' | 'Quit'.
    param($W, $Job)
    $uiw = Get-UiWidth
    while ($true) {
        Hide-Cursor
        Start-Frame
        Write-WizardTopForSummary $W
        Write-Rule -Title 'Summary'
        $rows = @($Job.Summary)
        Write-KeyValueTable -Rows $rows -LabelWidth ([math]::Min(16, [math]::Max(8, ($rows | ForEach-Object { ([string]$_[0]).Length } | Measure-Object -Maximum).Maximum + 1))) -Indent 1
        Write-Rule
        foreach ($n in @($Job.Notes)) { if ($n) { foreach ($l in (Split-TextLines ([string]$n) ($uiw - 4))) { Write-Ui -Text ('  ' + (Get-Icon 'Warn') + ' ' + $l) -Role Warning } } }
        Write-KeyHints @(@('Enter', 'Start'), @('V', 'View FFmpeg command (Advanced)'), @('Esc', 'Back'))
        Stop-Frame
        $k = Read-TuiKey
        if ($k.Name -eq 'Enter') { return 'Start' }
        if ($k.Name -eq 'Esc') { return 'Back' }
        if ($k.Name -eq 'CtrlC') { return 'Quit' }
        if ($k.Name -eq 'Char') {
            $c = $k.Char.ToUpperInvariant()
            if ($c -eq 'S') { return 'Start' }
            if ($c -eq 'B') { return 'Back' }
            if ($c -eq 'V') {
                $lines = @('Advanced view. This is the exact command the application will run (arguments are passed as separate tokens, never through a shell).', '')
                foreach ($st in @($Job.Stages)) { $lines += ('[' + $st.Name + ']'); $lines += (Format-FFmpegCommandLine $st.Arguments); $lines += '' }
                Show-TextViewer -Title 'Generated FFmpeg command' -Lines $lines
            }
        }
    }
}

function Write-WizardTopForSummary {
    param($W)
    $t = $W.Title; if ($W.Icon) { $t = (Get-Icon $W.Icon) + '  ' + $W.Title }
    Write-Rule -Title $t
    foreach ($k in @($W.Panels.Keys)) { $p = $W.Panels[$k]; Write-Panel -Title $p.Title -Rows $p.Rows -LabelWidth $p.LabelWidth }
    Write-UiBlank
}

function Invoke-Wizard {
    <#
      Runs steps in order. Returns @{ Status = 'Completed'|'Cancelled'; Answers; Job; State }.
      -Build receives the wizard state and returns the job (Summary rows, Stages, Output, ...). Build may throw a
      user-facing message, which is shown before returning to the last step.
    #>
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Description = '',
        [string]$Icon = '',
        [Parameter(Mandatory)][object[]]$Steps,
        [scriptblock]$Build,
        [hashtable]$InitialData = @{}
    )
    $W = New-WizardState -Title $Title -Description $Description -Icon $Icon
    foreach ($k in $InitialData.Keys) { $W.Data[$k] = $InitialData[$k] }
    $history = New-Object System.Collections.Generic.List[int]
    $i = 0
    $final = @{ Status = 'Cancelled'; Answers = $W.Answers; Job = $null; State = $W }
    while ($true) {
        if ($i -ge $Steps.Count) {
            $job = $null
            if ($Build) {
                try { $job = & $Build $W } catch {
                    $null = Show-Notice -Title 'This selection cannot be processed' -Lines @($_.Exception.Message) -Kind Warning -Actions @(@('Enter', 'Go back'))
                    if ($history.Count -eq 0) { return $final }
                    $i = $history[$history.Count - 1]; $history.RemoveAt($history.Count - 1)
                    continue
                }
                $act = Show-WizardSummary $W $job
                if ($act -eq 'Quit') { return $final }
                if ($act -eq 'Back') {
                    if ($history.Count -eq 0) { return $final }
                    $i = $history[$history.Count - 1]; $history.RemoveAt($history.Count - 1)
                    continue
                }
            }
            return @{ Status = 'Completed'; Answers = $W.Answers; Job = $job; State = $W }
        }
        $step = $Steps[$i]
        if (-not (Test-StepVisible $step $W)) {
            if ($W.Answers.ContainsKey($step.Id)) { $W.Answers.Remove($step.Id) }
            $i++
            continue
        }
        $W.Step = $step
        $initial = $null
        if ($W.Answers.ContainsKey($step.Id)) { $initial = $W.Answers[$step.Id] }
        $res = Invoke-WizardStep $step $W $initial
        if ($res.Status -eq 'Quit') { return $final }
        if ($res.Status -eq 'Back') {
            if ($history.Count -eq 0) { return $final }
            $i = $history[$history.Count - 1]; $history.RemoveAt($history.Count - 1)
            continue
        }
        $W.Answers[$step.Id] = $res.Value
        $history.Add($i)
        $W.Goto = $null
        if ($step.ContainsKey('OnAnswer') -and $step.OnAnswer) { & $step.OnAnswer $res.Value $W }
        if ($W.Goto) {
            $target = -1
            for ($j = 0; $j -lt $Steps.Count; $j++) { if ($Steps[$j].Id -eq $W.Goto) { $target = $j; break } }
            $W.Goto = $null
            if ($target -ge 0) {
                while ($history.Count -gt 0 -and $history[$history.Count - 1] -ge $target) { $history.RemoveAt($history.Count - 1) }
                $i = $target
                continue
            }
        }
        $i++
    }
}

Export-ModuleMember -Function New-WizardState, Set-WizardPanel, Remove-WizardPanel, Write-WizardTop, Convert-TextAnswer, Read-TextStep, Read-ChoiceStep, Read-MultiChoiceStep, Read-YesNoStep, Read-FilesStep, Invoke-WizardStep, Show-WizardSummary, Invoke-Wizard
