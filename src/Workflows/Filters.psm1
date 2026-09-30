# Filters.psm1 - workflow 13: Filters & Color (guided common filters, Filter Browser, validated expert filter).
Set-StrictMode -Version 2.0

$script:EffectChoices = @(
    @{ Id = 'brightness'; Label = 'Brightness'; Desc = 'Make the picture lighter or darker.' },
    @{ Id = 'contrast'; Label = 'Contrast'; Desc = 'Difference between light and dark areas.' },
    @{ Id = 'saturation'; Label = 'Saturation'; Desc = 'Color intensity.' },
    @{ Id = 'gamma'; Label = 'Gamma'; Desc = 'Mid-tone brightness.' },
    @{ Id = 'grayscale'; Label = 'Grayscale'; Desc = 'Remove all color.' },
    @{ Id = 'sharpen'; Label = 'Sharpen'; Desc = 'Increase edge detail.' },
    @{ Id = 'blur'; Label = 'Blur'; Desc = 'Soften the picture.' },
    @{ Id = 'fadein'; Label = 'Fade in'; Desc = 'Start from black.' },
    @{ Id = 'fadeout'; Label = 'Fade out'; Desc = 'End by fading to black.' }
)

function Test-EffectSelected { param($W, [string]$Id) return (@(Get-Answer $W 'effects' @()) -contains $Id) }

function Test-ExpertFilterExpression {
    # Validates an expert filter string by letting FFmpeg parse it against a tiny synthetic input.
    param([string]$Expression)
    if ([string]::IsNullOrWhiteSpace($Expression)) { return 'Enter a filter expression.' }
    if ($Expression.Length -gt 1000) { return 'The expression is too long.' }
    $r = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-hide_banner', '-loglevel', 'error', '-nostdin', '-f', 'lavfi', '-i', 'color=c=black:s=64x64:d=0.2:r=10', '-vf', $Expression, '-frames:v', '1', '-f', 'null', '-') -TimeoutSec 20
    if ($r.TimedOut) { return 'FFmpeg took too long to test this filter.' }
    if ($r.ExitCode -ne 0) { $m = ($r.StdErr -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 1); return "FFmpeg rejected this filter: $m" }
    return $null
}

function Get-FilterSteps {
    $effect = { param($W, $id) (Test-EffectSelected $W $id) }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Video
    $steps += @{ Id = 'effects'; Type = 'MultiChoice'; Prompt = 'Which effects do you want to apply?'; Help = 'Select one or more. You will set the strength of each next.'; Min = 1
        Choices = { param($W) @($script:EffectChoices | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = @('brightness') }
    $steps += @{ Id = 'brightness'; Type = 'Choice'; Prompt = 'Brightness'; Help = '0 = unchanged. Positive is brighter, negative is darker.'; When = { param($W) Test-EffectSelected $W 'brightness' }
        Choices = { param($W) @( (New-Choice -0.2 'Darker (-0.2)'), (New-Choice -0.1 'Slightly darker (-0.1)'), (New-Choice 0.1 'Slightly brighter (+0.1)'), (New-Choice 0.2 'Brighter (+0.2)'), (New-Choice 0.3 'Much brighter (+0.3)') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = -1; Max = 1; Prompt = 'Custom brightness'; Help = 'Between -1 and 1.'; Example = '0.15'; ValueLabel = 'Brightness'; Desc = 'Between -1 and 1.' }; Default = 0.1 }
    $steps += @{ Id = 'contrast'; Type = 'Choice'; Prompt = 'Contrast'; Help = '1 = unchanged. Above 1 increases contrast.'; When = { param($W) Test-EffectSelected $W 'contrast' }
        Choices = { param($W) @( (New-Choice 0.8 'Lower (0.8)'), (New-Choice 1.2 'Higher (1.2)'), (New-Choice 1.5 'Much higher (1.5)'), (New-Choice 2.0 'Extreme (2.0)') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = -1000; Max = 1000; Prompt = 'Custom contrast'; Help = 'A number such as 1.3 (1 = unchanged).'; Example = '1.3'; ValueLabel = 'Contrast'; Desc = 'For example 1.3.' }; Default = 1.2 }
    $steps += @{ Id = 'saturation'; Type = 'Choice'; Prompt = 'Saturation'; Help = '1 = unchanged, 0 = grayscale, above 1 = more vivid.'; When = { param($W) Test-EffectSelected $W 'saturation' }
        Choices = { param($W) @( (New-Choice 0.5 'Muted (0.5)'), (New-Choice 1.3 'Vivid (1.3)'), (New-Choice 1.6 'Very vivid (1.6)'), (New-Choice 2.0 'Intense (2.0)') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = 0; Max = 3; Prompt = 'Custom saturation'; Help = 'Between 0 and 3.'; Example = '1.4'; ValueLabel = 'Saturation'; Desc = 'Between 0 and 3.' }; Default = 1.3 }
    $steps += @{ Id = 'gamma'; Type = 'Choice'; Prompt = 'Gamma'; Help = '1 = unchanged. Above 1 brightens mid-tones.'; When = { param($W) Test-EffectSelected $W 'gamma' }
        Choices = { param($W) @( (New-Choice 0.8 'Darker mid-tones (0.8)'), (New-Choice 1.2 'Brighter mid-tones (1.2)'), (New-Choice 1.5 'Much brighter (1.5)') ) }
        AllowCustom = @{ Label = 'Custom...'; Type = 'Decimal'; Min = 0.1; Max = 10; Prompt = 'Custom gamma'; Help = 'Between 0.1 and 10.'; Example = '1.1'; ValueLabel = 'Gamma'; Desc = 'Between 0.1 and 10.' }; Default = 1.2 }
    $steps += @{ Id = 'sharpen'; Type = 'Choice'; Prompt = 'Sharpen strength'; Help = 'Stronger settings can add visible halos.'; When = { param($W) Test-EffectSelected $W 'sharpen' }
        Choices = { param($W) @( (New-Choice 0.5 'Light'), (New-Choice 1.0 'Medium'), (New-Choice 1.8 'Strong') ) }; Default = 1.0 }
    $steps += @{ Id = 'blur'; Type = 'Choice'; Prompt = 'Blur strength'; Help = 'Larger values blur more.'; When = { param($W) Test-EffectSelected $W 'blur' }
        Choices = { param($W) @( (New-Choice 1 'Light'), (New-Choice 3 'Medium'), (New-Choice 6 'Strong'), (New-Choice 12 'Very strong') ) }; Default = 3 }
    $steps += @{ Id = 'fadein'; Type = 'Decimal'; Prompt = 'Fade-in length (seconds)'; Help = 'How long the fade from black lasts.'; Example = '1.5'; Min = 0.1; Max = 60; Default = 1; Label = 'Fade-in length'; Unit = 'seconds'; When = { param($W) Test-EffectSelected $W 'fadein' }
        Validate = { param($v, $W) $d = (Get-Media $W 'input').Duration; if ($d -and $v -ge $d) { return 'The fade is longer than the video.' }; $null } }
    $steps += @{ Id = 'fadeout'; Type = 'Decimal'; Prompt = 'Fade-out length (seconds)'; Help = 'How long the fade to black lasts at the end.'; Example = '1.5'; Min = 0.1; Max = 60; Default = 1; Label = 'Fade-out length'; Unit = 'seconds'; When = { param($W) Test-EffectSelected $W 'fadeout' }
        Validate = { param($v, $W) $d = (Get-Media $W 'input').Duration; if (-not $d) { return 'The video length is unknown, so a fade-out cannot be placed.' }; if ($v -ge $d) { return 'The fade is longer than the video.' }; $null } }
    $steps += Get-AdvancedGateStep -Prompt 'Add an expert filter expression?'
    $steps += @{ Id = 'expert'; Type = 'Text'; Prompt = 'Expert filter expression'; Help = 'An FFmpeg video filter string. It is test-run against a sample frame before it is accepted. Leave empty to skip.'; Example = 'hue=h=30,vignette'; Optional = $true
        When = { param($W) [bool](Get-Answer $W 'advanced' $false) }
        Validate = { param($v, $W) if ([string]::IsNullOrWhiteSpace($v)) { return $null }; Test-ExpertFilterExpression $v } }
    $steps += Get-VideoTailSteps -Suffix 'filtered'
    return $steps
}

function Build-FilterJob {
    param($W)
    $info = Get-Media $W 'input'
    $sel = @(Get-Answer $W 'effects' @())
    $f = @(); $labels = @()
    $eq = @()
    if ($sel -contains 'brightness') { $eq += ('brightness=' + (Format-FFNumber ([double](Get-Answer $W 'brightness')) 4)); $labels += ('Brightness ' + ('{0:+0.##;-0.##;0}' -f [double](Get-Answer $W 'brightness'))) }
    if ($sel -contains 'contrast') { $eq += ('contrast=' + (Format-FFNumber ([double](Get-Answer $W 'contrast')) 4)); $labels += ('Contrast ' + ('{0:0.##}' -f [double](Get-Answer $W 'contrast'))) }
    if ($sel -contains 'saturation') { $eq += ('saturation=' + (Format-FFNumber ([double](Get-Answer $W 'saturation')) 4)); $labels += ('Saturation ' + ('{0:0.##}' -f [double](Get-Answer $W 'saturation'))) }
    if ($sel -contains 'gamma') { $eq += ('gamma=' + (Format-FFNumber ([double](Get-Answer $W 'gamma')) 4)); $labels += ('Gamma ' + ('{0:0.##}' -f [double](Get-Answer $W 'gamma'))) }
    if ($eq.Count -gt 0) { $f += ('eq=' + ($eq -join ':')) }
    if ($sel -contains 'grayscale') { $f += 'hue=s=0'; $labels += 'Grayscale' }
    if ($sel -contains 'sharpen') { $f += ('unsharp=5:5:' + (Format-FFNumber ([double](Get-Answer $W 'sharpen')) 3) + ':5:5:0'); $labels += 'Sharpen' }
    if ($sel -contains 'blur') { $f += ('gblur=sigma=' + (Format-FFNumber ([double](Get-Answer $W 'blur')) 3)); $labels += 'Blur' }
    if ($sel -contains 'fadein') { $f += ('fade=t=in:st=0:d=' + (Format-FFNumber ([double](Get-Answer $W 'fadein')) 3)); $labels += 'Fade in' }
    if ($sel -contains 'fadeout') { $d = [double](Get-Answer $W 'fadeout'); $f += ('fade=t=out:st=' + (Format-FFNumber ($info.Duration - $d) 3) + ':d=' + (Format-FFNumber $d 3)); $labels += 'Fade out' }
    $ex = [string](Get-Answer $W 'expert' '')
    if ($ex) { $f += $ex; $labels += 'Custom filter' }
    if ($f.Count -eq 0) { throw 'Select at least one effect.' }
    return New-VideoProcessJob -W $W -Title 'Applying filters' -VideoFilters $f -Rows @(@('Input', $info.FileName), @('Filters', ($labels -join ', '))) -AudioMode copy -StageName 'Applying filters'
}

function Show-FilterBrowser {
    while ($true) {
        Clear-Ui
        Write-Rule -Title 'Filter Browser'
        Write-Ui -Text '  Filters available in your installed FFmpeg build.' -Role DimText
        Write-Ui -Text '  Type part of a name or description to search. Leave empty to list everything.' -Role DimText
        Write-UiBlank
        Write-KeyHints @(@('Enter', 'Search'), @('Esc', 'Back'))
        $l = Read-TuiLine -Prompt 'Search> '
        if ($l.Status -ne 'Ok') { return }
        $term = $l.Text.Trim()
        $all = @(Get-FFFilterList)
        $hits = @($all | Where-Object { -not $term -or $_.Name -like "*$term*" -or $_.Description -like "*$term*" })
        $lines = @("$($hits.Count) filter(s) match" + $(if ($term) { " '$term'" } else { '' }) + " (of $($all.Count)).", '')
        foreach ($h in ($hits | Select-Object -First 400)) { $lines += (('{0,-22} {1,-8} {2}' -f $h.Name, $h.Io, $h.Description)) }
        if ($hits.Count -gt 400) { $lines += ''; $lines += 'Only the first 400 matches are shown. Refine your search.' }
        Show-TextViewer -Title 'Filters' -Lines $lines
        if ($hits.Count -ge 1 -and $hits.Count -le 30 -and $term) {
            $detail = $hits[0].Name
            if ($hits.Count -gt 1) { continue }
            $r = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-hide_banner', '-h', "filter=$detail") -TimeoutSec 20
            if ($r.ExitCode -eq 0) { Show-TextViewer -Title "Filter: $detail" -Lines @($r.StdOut -split "`r?`n") }
        }
    }
}

function Start-FiltersWorkflow {
    $items = @(
        @{ Label = 'Apply Filters & Color'; Desc = 'Brightness, contrast, saturation, gamma, grayscale, sharpen, blur and fades.'; Key = '1'; Value = { Start-StandardWorkflow -Title 'Filters & Color' -Description 'Apply common visual filters and color adjustments.' -Icon 'Filters' -StepsFactory { Get-FilterSteps } -Build { param($W) Build-FilterJob $W } } },
        @{ Label = 'Filter Browser'; Desc = 'Search the filters and descriptions in your FFmpeg build.'; Key = '2'; Value = { Show-FilterBrowser } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Filters') + '  Filters & Color') -Subtitle 'Apply common filters, or explore every filter your FFmpeg build provides.' -Items $items
}

Export-ModuleMember -Function Test-ExpertFilterExpression, Get-FilterSteps, Build-FilterJob, Show-FilterBrowser, Start-FiltersWorkflow
