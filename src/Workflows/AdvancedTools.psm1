# AdvancedTools.psm1 - Advanced FFmpeg: capability browser (everything the installed build offers), hardware
# acceleration check, build details and a guided custom command builder. The guided workflows cover the common
# tasks; this area is the organized way to reach everything else without a button for every codec or filter.
Set-StrictMode -Version 2.0

# ---- argument text -> tokens ----------------------------------------------------------------------------------

function ConvertFrom-ArgumentText {
    # Splits text into argument tokens. Whitespace separates tokens; double quotes group words (quotes are removed).
    # Returns @{ Ok; Tokens; Error }. Nothing is ever passed through a shell.
    param([string]$Text)
    $tokens = New-Object System.Collections.Generic.List[string]
    $sb = New-Object System.Text.StringBuilder
    $inQ = $false; $has = $false
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq '"') { $inQ = -not $inQ; $has = $true; continue }
        if ((-not $inQ) -and [char]::IsWhiteSpace($ch)) {
            if ($has -or $sb.Length -gt 0) { $tokens.Add($sb.ToString()); [void]$sb.Clear(); $has = $false }
            continue
        }
        [void]$sb.Append($ch)
    }
    if ($inQ) { return @{ Ok = $false; Tokens = @(); Error = 'A quotation mark is not closed.' } }
    if ($has -or $sb.Length -gt 0) { $tokens.Add($sb.ToString()) }
    return @{ Ok = $true; Tokens = $tokens.ToArray(); Error = '' }
}

function Test-CustomOptionTokens {
    # Returns $null when the tokens may be used, otherwise a message. Direction: Input | Output.
    param([string[]]$Tokens, [ValidateSet('Input', 'Output')][string]$Direction)
    $blocked = @{ '-i' = 'Inputs are chosen in the file list, so -i is not needed.'; '-y' = 'Overwriting is decided by this application, so -y is not allowed.'; '-n' = 'Overwrite handling is done by this application, so -n is not allowed.'; '-nostdin' = 'This option is added automatically.'; '-progress' = 'Progress reporting is handled by this application.'; '-stdin' = 'This option is not allowed.' }
    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $t = $Tokens[$i]
        if ($blocked.ContainsKey($t)) { return $blocked[$t] }
        $next = $null; if ($i + 1 -lt $Tokens.Count) { $next = $Tokens[$i + 1] }
        if ($t -match '^-(c|codec|vcodec|acodec|scodec)(:[a-z0-9:]+)?$' -and $next -and $next -ne 'copy') {
            if ($Direction -eq 'Output' -and -not (Test-FFEncoder $next)) { return "The encoder '$next' is not available in your FFmpeg build. Use the Capability Browser to see what is available." }
            if ($Direction -eq 'Input' -and -not (Test-FFDecoder $next)) { return "The decoder '$next' is not available in your FFmpeg build." }
        }
        if ($t -eq '-f' -and $next) {
            if ($Direction -eq 'Output' -and -not (Test-FFMuxer $next)) { return "The output format '$next' is not available in your FFmpeg build." }
            if ($Direction -eq 'Input' -and -not (Test-FFDemuxer $next)) { return "The input format '$next' is not available in your FFmpeg build." }
        }
    }
    return $null
}

# ---- capability browser -----------------------------------------------------------------------------------------

function Get-CapabilityRows {
    # -> @(@{ Name; Kind; Description }) for a category key.
    param([string]$Category)
    $c = Get-FFCapabilities
    switch ($Category) {
        'encoders' { return @($c.Encoders.Keys | Sort-Object | ForEach-Object { @{ Name = $_; Kind = $c.Encoders[$_].Type; Description = $c.Encoders[$_].Description } }) }
        'decoders' { return @($c.Decoders.Keys | Sort-Object | ForEach-Object { @{ Name = $_; Kind = $c.Decoders[$_].Type; Description = $c.Decoders[$_].Description } }) }
        'muxers' { return @($c.Muxers.Keys | Sort-Object | ForEach-Object { @{ Name = $_; Kind = 'out'; Description = $c.Muxers[$_].Description } }) }
        'demuxers' { return @($c.Demuxers.Keys | Sort-Object | ForEach-Object { @{ Name = $_; Kind = 'in'; Description = $c.Demuxers[$_].Description } }) }
        'filters' { return @($c.Filters.Keys | Sort-Object | ForEach-Object { @{ Name = $_; Kind = $c.Filters[$_].Io; Description = $c.Filters[$_].Description } }) }
        'protocols' {
            $rows = @(); foreach ($k in ($c.ProtocolsIn.Keys | Sort-Object)) { $rows += , @{ Name = $k; Kind = $(if ($c.ProtocolsOut.ContainsKey($k)) { 'in/out' } else { 'in' }); Description = '' } }
            foreach ($k in ($c.ProtocolsOut.Keys | Sort-Object)) { if (-not $c.ProtocolsIn.ContainsKey($k)) { $rows += , @{ Name = $k; Kind = 'out'; Description = '' } } }
            return $rows }
        'hwaccels' { return @($c.HwAccels | ForEach-Object { @{ Name = $_; Kind = 'hw'; Description = 'Hardware-accelerated decoding method' } }) }
        'pixfmts' {
            $r = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-hide_banner', '-pix_fmts') -TimeoutSec 30
            $rows = @(); foreach ($l in (($r.StdOut -split "`r?`n") | Where-Object { $_ -match '^[I\.][O\.][H\.][P\.][B\.]\s+\S+\s+\d+' })) { $m = [regex]::Match($l, '^(\S+)\s+(\S+)\s+(\d+)\s+(\d+)'); $rows += , @{ Name = $m.Groups[2].Value; Kind = $m.Groups[3].Value + ' ch'; Description = ($m.Groups[4].Value + ' bits per pixel') } }
            return $rows }
    }
    return @()
}

function Get-CapabilityHelpArgs {
    param([string]$Category, [string]$Name)
    switch ($Category) {
        'encoders' { return @('-hide_banner', '-h', "encoder=$Name") }
        'decoders' { return @('-hide_banner', '-h', "decoder=$Name") }
        'muxers' { return @('-hide_banner', '-h', "muxer=$Name") }
        'demuxers' { return @('-hide_banner', '-h', "demuxer=$Name") }
        'filters' { return @('-hide_banner', '-h', "filter=$Name") }
        default { return $null }
    }
}

function Show-CapabilityBrowser {
    $cats = @(
        @{ Id = 'encoders'; Label = 'Encoders (codecs that can be written)'; Desc = 'Video, audio and subtitle codecs you can convert TO, such as libx264, aac, libopus.'; Icon = 'Video' },
        @{ Id = 'decoders'; Label = 'Decoders (codecs that can be read)'; Desc = 'Codecs FFmpeg can understand when opening a file.'; Icon = 'Search' },
        @{ Id = 'muxers'; Label = 'Output formats (muxers / containers)'; Desc = 'File types FFmpeg can create, such as mp4, matroska, mp3.'; Icon = 'Merge' },
        @{ Id = 'demuxers'; Label = 'Input formats (demuxers)'; Desc = 'File types and devices FFmpeg can read.'; Icon = 'Folder' },
        @{ Id = 'filters'; Label = 'Filters (video and audio effects)'; Desc = 'Every effect available, for example scale, eq, volume, atempo, drawtext.'; Icon = 'Filters' },
        @{ Id = 'protocols'; Label = 'Protocols (network and file access)'; Desc = 'Ways FFmpeg can read or write data: file, http, rtmp, srt, udp ...'; Icon = 'Network' },
        @{ Id = 'hwaccels'; Label = 'Hardware acceleration methods'; Desc = 'GPU decoding methods compiled into this FFmpeg (cuda, d3d11va, qsv ...).'; Icon = 'Hardware' },
        @{ Id = 'pixfmts'; Label = 'Pixel formats'; Desc = 'Color and bit-depth layouts such as yuv420p and yuv420p10le.'; Icon = 'Image' }
    )
    $items = @($cats | ForEach-Object { @{ Label = $_.Label; Desc = $_.Desc; Icon = $_.Icon; Value = $_ } })
    $idx = 0
    while ($true) {
        $r = Show-Menu -Title 'Capability Browser' -Subtitle 'Everything below comes from your installed FFmpeg. Pick a category, then search it.' -Items $items -AllowBack -InitialIndex $idx -ShowHeader
        if ($r.Action -ne 'Select') { return }
        $idx = $r.Index
        $cat = $r.Item.Value
        $rows = @(Get-CapabilityRows $cat.Id)
        while ($true) {
            Clear-Ui
            Write-Rule -Title $cat.Label
            Write-Ui -Text ("  {0} entries in this build. Type part of a name or description to search, or leave empty to list all." -f $rows.Count) -Role DimText
            Write-UiBlank
            Write-KeyHints @(@('Enter', 'Search'), @('Esc', 'Back'))
            $l = Read-TuiLine -Prompt 'Search> '
            if ($l.Status -ne 'Ok') { break }
            $term = $l.Text.Trim()
            $hits = @($rows | Where-Object { -not $term -or $_.Name -like "*$term*" -or $_.Description -like "*$term*" })
            $lines = @("$($hits.Count) match(es)" + $(if ($term) { " for '$term'" } else { '' }) + " (of $($rows.Count)).", '')
            foreach ($h in ($hits | Select-Object -First 500)) { $lines += ('{0,-26} {1,-7} {2}' -f $h.Name, $h.Kind, $h.Description) }
            if ($hits.Count -gt 500) { $lines += ''; $lines += 'Only the first 500 matches are shown. Refine your search.' }
            Show-TextViewer -Title $cat.Label -Lines $lines
            $exact = @($hits | Where-Object { $_.Name -eq $term })
            if ($exact.Count -eq 1) { $hits = $exact }
            if ($hits.Count -eq 1) {
                $ha = Get-CapabilityHelpArgs $cat.Id $hits[0].Name
                if ($ha) {
                    $hr = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments $ha -TimeoutSec 20
                    if ($hr.ExitCode -eq 0) { Show-TextViewer -Title ($cat.Id + ': ' + $hits[0].Name) -Lines @(($hr.StdOut + $hr.StdErr) -split "`r?`n") }
                }
            }
        }
    }
}

# ---- hardware acceleration check ---------------------------------------------------------------------------------

function Get-HardwareReport {
    param([scriptblock]$OnProgress)
    $c = Get-FFCapabilities
    $lines = @('Hardware acceleration report', '')
    $hw = @($c.HwAccels)
    $lines += 'Decoding methods compiled into this FFmpeg:'
    if ($hw.Count -eq 0) { $lines += '  (none)' } else { $lines += ('  ' + ($hw -join ', ')) }
    $lines += ''
    $enc = @($c.Encoders.Keys | Where-Object { $_ -match '_(nvenc|qsv|amf|videotoolbox|vaapi|mf|v4l2m2m|vulkan)$' } | Sort-Object)
    $lines += 'GPU video encoders (each one is test-encoded for real):'
    if ($enc.Count -eq 0) { $lines += '  (none compiled into this FFmpeg)' }
    $n = 0
    foreach ($e in $enc) {
        $n++
        if ($OnProgress) { & $OnProgress $e $n $enc.Count }
        if (Test-FFEncoderUsable $e) { $lines += ('  [usable]     {0}' -f $e) } else { $lines += ('  [not usable] {0}   (no matching GPU or driver found)' -f $e) }
    }
    $lines += ''
    $lines += 'Only encoders marked [usable] are offered in the conversion wizards. GPU encoders are faster; software encoders (libx264, libx265) usually give smaller files at the same quality.'
    return $lines
}

function Show-HardwareCheck {
    $prog = { param($name, $n, $total) Show-BusyScreen -Title 'Testing GPU encoders' -Message ("Testing $name ($n of $total)") -Tick $n }
    Show-BusyScreen -Title 'Testing GPU encoders' -Message 'Checking what this computer can use...' -Tick 0
    $lines = Get-HardwareReport -OnProgress $prog
    Show-TextViewer -Title 'Hardware acceleration' -Lines $lines
}

function Show-BuildDetails {
    $r = Invoke-ExternalCapture -FilePath (Get-FFmpegPath) -Arguments @('-hide_banner', '-version') -TimeoutSec 20
    $lines = @('FFmpeg build details', '', "Program: $(Get-FFmpegPath)", "ffprobe: $(Get-FFprobePath)", '')
    $lines += @(($r.StdOut + $r.StdErr) -split "`r?`n" | ForEach-Object { $_ -replace '\s--', "`n   --" } | ForEach-Object { $_ -split "`n" })
    $st = Get-FFCapabilityStatus
    $lines += ''; $lines += ("Capabilities: {0} encoders, {1} decoders, {2} muxers, {3} demuxers, {4} filters, {5} protocols." -f $st.Encoders, $st.Decoders, $st.Muxers, $st.Demuxers, $st.Filters, $st.Protocols)
    Show-TextViewer -Title 'FFmpeg build' -Lines $lines
}

# ---- custom command --------------------------------------------------------------------------------------------------

function Get-CustomCommandSteps {
    $steps = @()
    $steps += @{ Id = 'inputs'; Type = 'Files'; Prompt = 'Input files'; Min = 1
        Help = 'One or more files FFmpeg should read (-i). The first file is input 0, the second is input 1, and so on; refer to them that way in your options (for example -map 1:a).' }
    $steps += @{ Id = 'inopts'; Type = 'Text'; Prompt = 'Options for the first input (optional)'; Label = 'Input options'; Optional = $true; Example = '-ss 00:00:10 -t 5'
        Help = 'FFmpeg options placed before the first input: seeking, duration, frame rate of an image sequence, hardware decoding and similar. Leave empty for none.'
        Validate = { param($v, $W) $t = ConvertFrom-ArgumentText $v; if (-not $t.Ok) { return $t.Error }; Test-CustomOptionTokens $t.Tokens 'Input' } }
    $steps += @{ Id = 'outopts'; Type = 'Text'; Prompt = 'Options for the output (optional)'; Label = 'Output options'; Optional = $true; Example = '-c:v libx264 -crf 20 -vf "scale=1280:-2" -c:a aac -b:a 128k'
        Help = 'Codecs, filters, mapping and everything else. Use double quotes around values with spaces. Look up encoders and filters in the Capability Browser. Leave empty to let FFmpeg choose defaults from the output file name.'
        Validate = { param($v, $W) $t = ConvertFrom-ArgumentText $v; if (-not $t.Ok) { return $t.Error }; Test-CustomOptionTokens $t.Tokens 'Output' } }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'inputs' -Suffix 'custom' -ProtectIds @('inputs') -NamePrompt 'Output file name (with extension)' -Extension { param($W) '' }
    for ($i = 0; $i -lt $steps.Count; $i++) {
        if ($steps[$i].Id -eq 'outname') { $steps[$i].Help = 'FFmpeg chooses the file format from the extension, so include it (for example result.mp4, result.mkv, result.mp3, result.gif).'; $steps[$i].Default = { param($W) $p = [string]((@(Get-Answer $W 'inputs'))[0]); if ($p) { [System.IO.Path]::GetFileNameWithoutExtension($p) + '_custom' + [System.IO.Path]::GetExtension($p) } else { 'output.mkv' } } }
    }
    return $steps
}

function Build-CustomCommandJob {
    param($W)
    $inputs = @(Get-Answer $W 'inputs' @())
    if ($inputs.Count -eq 0) { throw 'Add at least one input file.' }
    $out = Get-OutputFile $W
    if (-not [System.IO.Path]::GetExtension($out.Name)) { throw 'The output file name needs an extension such as .mp4 or .mkv, so FFmpeg knows which format to write.' }
    $inT = ConvertFrom-ArgumentText ([string](Get-Answer $W 'inopts' '')); if (-not $inT.Ok) { throw $inT.Error }
    $outT = ConvertFrom-ArgumentText ([string](Get-Answer $W 'outopts' '')); if (-not $outT.Ok) { throw $outT.Error }
    $m = Test-CustomOptionTokens $inT.Tokens 'Input'; if ($m) { throw $m }
    $m = Test-CustomOptionTokens $outT.Tokens 'Output'; if ($m) { throw $m }
    $cmd = New-FFCommand
    for ($i = 0; $i -lt $inputs.Count; $i++) { [void](Add-FFInput $cmd ([string]$inputs[$i]) $(if ($i -eq 0) { $inT.Tokens } else { @() })) }
    Add-FFOutOpt $cmd $outT.Tokens
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $dur = $null
    $p = Get-MediaInfo -Path ([string]$inputs[0]); if ($p.Ok) { $dur = $p.Info.Duration }
    $notes = @('Your options are passed to FFmpeg exactly as typed (as separate arguments, never through a shell). If FFmpeg rejects them, the technical details show its message.'); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Inputs', (@($inputs | ForEach-Object { [System.IO.Path]::GetFileName([string]$_) }) -join ', ')), @('Input options', $(if ($inT.Tokens.Count) { $inT.Tokens -join ' ' } else { '(none)' })), @('Output options', $(if ($outT.Tokens.Count) { $outT.Tokens -join ' ' } else { '(none)' })), @('Output', $out.Path))
    return New-JobObject -Title 'Running custom FFmpeg command' -Summary $rows -Stages @(@{ Name = 'Running FFmpeg'; Arguments = (Get-FFTokens $cmd); DurationSec = $dur }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

function Start-AdvancedWorkflow {
    $items = @(
        @{ Label = 'Capability Browser'; Icon = 'Search'; Desc = 'Search every encoder, decoder, format, filter and protocol in your FFmpeg build.'; Value = { Show-CapabilityBrowser } },
        @{ Label = 'Custom FFmpeg Command (Guided)'; Icon = 'Code'; Desc = 'Pick files and type your own FFmpeg options; safety and progress are handled.'; Value = { Start-StandardWorkflow -Title 'Custom FFmpeg Command' -Description 'Run FFmpeg with options you type yourself.' -Icon 'Code' -StepsFactory { Get-CustomCommandSteps } -Build { param($W) Build-CustomCommandJob $W } } },
        @{ Label = 'Hardware Acceleration Check'; Icon = 'Hardware'; Desc = 'See which GPU encoders and decoders your computer can really use.'; Value = { Show-HardwareCheck } },
        @{ Label = 'FFmpeg Build Details'; Icon = 'Info'; Desc = 'Show the version and the configuration flags of the installed FFmpeg.'; Value = { Show-BuildDetails } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Code') + '  Advanced FFmpeg') -Subtitle 'For everything the guided tools do not cover. Capabilities always come from your installed FFmpeg.' -Items $items
}

Export-ModuleMember -Function ConvertFrom-ArgumentText, Test-CustomOptionTokens, Get-CapabilityRows, Get-CapabilityHelpArgs, Show-CapabilityBrowser, Get-HardwareReport, Show-HardwareCheck, Show-BuildDetails, Get-CustomCommandSteps, Build-CustomCommandJob, Start-AdvancedWorkflow
