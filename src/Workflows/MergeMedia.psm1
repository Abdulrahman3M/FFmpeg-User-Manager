# MergeMedia.psm1 - workflow 5: Merge Media (video or audio concatenation).
Set-StrictMode -Version 2.0

function Get-MergeCompatibility {
    # Inspects all inputs. Returns @{ Kind = video|audio|mixed; CanCopy; Reason }.
    param($Infos)
    $res = @{ Kind = 'video'; CanCopy = $true; Reason = '' }
    $anyVideo = @($Infos | Where-Object { $_.HasVideo }).Count
    if ($anyVideo -eq 0) { $res.Kind = 'audio' }
    elseif ($anyVideo -ne $Infos.Count) { $res.Kind = 'mixed'; $res.CanCopy = $false; $res.Reason = 'Some files have video and some are audio-only. Merge video files together or audio files together.'; return $res }
    $first = $Infos[0]
    for ($i = 1; $i -lt $Infos.Count; $i++) {
        $o = $Infos[$i]; $n = $i + 1
        if ($res.Kind -eq 'video') {
            $a = $first.Video[0]; $b = $o.Video[0]
            if ($a.Codec -ne $b.Codec) { $res.CanCopy = $false; $res.Reason = "File $n uses a different video codec ($(Get-FriendlyCodecName $b.Codec) vs $(Get-FriendlyCodecName $a.Codec))."; break }
            if ($a.Width -ne $b.Width -or $a.Height -ne $b.Height) { $res.CanCopy = $false; $res.Reason = "File $n has a different resolution ($($b.Width)x$($b.Height) vs $($a.Width)x$($a.Height))."; break }
            if ($a.PixFmt -ne $b.PixFmt) { $res.CanCopy = $false; $res.Reason = "File $n uses a different pixel format ($($b.PixFmt) vs $($a.PixFmt))."; break }
            if ($a.Fps -and $b.Fps -and [math]::Abs($a.Fps - $b.Fps) -gt 0.01) { $res.CanCopy = $false; $res.Reason = "File $n has a different frame rate ($('{0:0.##}' -f $b.Fps) vs $('{0:0.##}' -f $a.Fps) FPS)."; break }
        }
        if ($first.HasAudio -ne $o.HasAudio) { $res.CanCopy = $false; $res.Reason = "File $n and file 1 differ in whether they contain audio."; break }
        if ($first.HasAudio) {
            $a = $first.Audio[0]; $b = $o.Audio[0]
            if ($a.Codec -ne $b.Codec) { $res.CanCopy = $false; $res.Reason = "File $n uses a different audio codec ($(Get-FriendlyCodecName $b.Codec) vs $(Get-FriendlyCodecName $a.Codec))."; break }
            if ($a.SampleRate -ne $b.SampleRate -or $a.Channels -ne $b.Channels) { $res.CanCopy = $false; $res.Reason = "File $n has different audio settings (sample rate or channels)."; break }
        }
    }
    return $res
}

function Get-MergeSteps {
    $isVideo = { param($W) $p = $W.Data['mergePlan']; [bool]($p -and $p.Kind -eq 'video') }
    $isAudio = { param($W) $p = $W.Data['mergePlan']; [bool]($p -and $p.Kind -eq 'audio') }
    $reenc = { param($W) (Get-Answer $W 'method') -eq 'reencode' }
    $steps = @()
    $steps += @{
        Id = 'input'; Type = 'Files'; Prompt = 'Files to merge'; Help = 'Add the files in the order they should play. At least two are required.'; Min = 2; Example = 'C:\Videos\part1.mp4'
        Validate = { param($v, $W) $m = Get-MediaInfo -Path $v; if (-not $m.Ok) { return $m.Error }; $W.Data['probe.' + $v] = $m.Info; $null }
        OnAnswer = {
            param($v, $W)
            $infos = @(@($v) | ForEach-Object { $k = 'probe.' + $_; if ($W.Data.ContainsKey($k)) { $W.Data[$k] } else { $r = Get-MediaInfo -Path $_; if ($r.Ok) { $r.Info } } })
            $plan = Get-MergeCompatibility $infos
            $W.Data['mergePlan'] = $plan; $W.Data['mergeInfos'] = $infos
            $W.Data['probe.input'] = $infos[0]
            $rows = @(@('Files', [string]$infos.Count))
            $tot = 0.0; foreach ($i in $infos) { if ($i.Duration) { $tot += $i.Duration } }
            $rows += , @('Total length', (Format-Duration $tot))
            $rows += , @('Type', $(if ($plan.Kind -eq 'video') { 'Video' } elseif ($plan.Kind -eq 'audio') { 'Audio' } else { 'Mixed' }))
            Set-WizardPanel $W 'merge' 'Merge' $rows 13
            if ($plan.Kind -eq 'mixed') { $null = Show-Notice -Title 'These files cannot be merged together' -Lines @($plan.Reason) -Kind Warning -Actions @(, @('Enter', 'Edit the list')); $W.Goto = 'input' }
        }
    }
    $steps += @{
        Id = 'method'; Type = 'Choice'; Prompt = 'Merge method'; Help = 'Lossless merge copies the streams without re-encoding. It is only possible when all files share the same codecs and settings.'
        Choices = { param($W) $p = $W.Data['mergePlan']; @( (New-Choice 'copy' 'Lossless (stream copy)' 'Fastest, no quality loss.' $p.CanCopy $p.Reason), (New-Choice 'reencode' 'Re-encode to common settings' 'Required when the files differ; slower.') ) }
        Default = { param($W) if ($W.Data['mergePlan'].CanCopy) { 'copy' } else { 'reencode' } }
        Validate = { param($v, $W) if ($v -eq 'copy' -and -not $W.Data['mergePlan'].CanCopy) { return $W.Data['mergePlan'].Reason }; $null }
    }
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Output format'; Help = 'The file type of the merged result.'; When = { param($W) (& $isVideo $W) -and (& $reenc $W) }.GetNewClosure()
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mp4' }
    $steps += Get-VideoEncodeSteps -Prefix 'v' -ContainerScript { param($W) [string](Get-Answer $W 'format' 'mp4') } -Level Simple -GateWhen ({ param($W) (& $isVideo $W) -and (& $reenc $W) }.GetNewClosure())
    $steps += @{ Id = 'resolution'; Type = 'Choice'; Prompt = 'Resolution of the merged video'; Help = 'All clips are scaled (with black bars if needed) to the same size.'; When = { param($W) (& $isVideo $W) -and (& $reenc $W) }.GetNewClosure()
        Choices = { param($W) $v = $W.Data['mergeInfos'][0].Video[0]; @(New-Choice 'first' ("Same as the first file ({0}x{1})" -f $v.Width, $v.Height)) + @(Get-ResolutionChoices | Where-Object { $_.Value -ne 'keep' }) }; Default = 'first' }
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Output format'; Help = 'The audio file type of the merged result.'; When = { param($W) (& $isAudio $W) -and (& $reenc $W) }.GetNewClosure()
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mp3' }
    $steps += Get-AudioEncodeSteps -Prefix 'a' -FormatAudioFamilies ({ param($W) if (& $isAudio $W) { $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); @($f.Codecs) } else { $c = Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4')); @($c.Audio) } }.GetNewClosure()) -When ({ param($W) & $reenc $W }.GetNewClosure())
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'merged' -ProtectIds @('input') -Extension {
        param($W)
        $first = $W.Data['mergeInfos'][0]
        if ((Get-Answer $W 'method') -eq 'copy') { return [System.IO.Path]::GetExtension($first.Path) }
        if ($W.Data['mergePlan'].Kind -eq 'audio') { return (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))).Ext }
        return (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext
    }
    return $steps
}

function Build-MergeJob {
    param($W)
    $infos = @($W.Data['mergeInfos'])
    $plan = $W.Data['mergePlan']
    $out = Get-OutputFile $W
    $copy = ((Get-Answer $W 'method') -eq 'copy')
    $notes = @()
    $tempFiles = @()
    $total = 0.0; foreach ($i in $infos) { if ($i.Duration) { $total += $i.Duration } }
    $cmd = New-FFCommand
    if ($copy) {
        $sb = New-Object System.Text.StringBuilder
        foreach ($i in $infos) { [void]$sb.Append("file '" + $i.Path.Replace("'", "'\''") + "'`n") }
        $list = New-TempTextFile $sb.ToString() '.txt'
        $tempFiles += $list
        [void](Add-FFInput $cmd $list @('-f', 'concat', '-safe', '0'))
        Add-FFOutOpt $cmd @('-map', '0:v?', '-map', '0:a?', '-c', 'copy')
    } else {
        foreach ($i in $infos) { [void](Add-FFInput $cmd $i.Path) }
        $n = $infos.Count
        $allAudio = -not (@($infos | Where-Object { -not $_.HasAudio }).Count)
        $parts = @()
        if ($plan.Kind -eq 'video') {
            $v0 = $infos[0].Video[0]
            $res = [string](Get-Answer $W 'resolution' 'first')
            if ($res -eq 'first') { $tw = [int]$v0.Width; $th = [int]$v0.Height } else { $h = [int]$res.Substring(1); $th = $h; $tw = [int](2 * [math]::Round(($h * $v0.Width / $v0.Height) / 2)) }
            if ($tw % 2) { $tw-- }; if ($th % 2) { $th-- }
            $fps = if ($v0.Fps) { [math]::Round($v0.Fps, 3) } else { 30 }
            for ($k = 0; $k -lt $n; $k++) {
                $parts += "[${k}:v:0]scale=${tw}:${th}:force_original_aspect_ratio=decrease,pad=${tw}:${th}:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=$(Format-FFNumber $fps 3),format=yuv420p[v$k]"
            }
        }
        if ($allAudio) {
            for ($k = 0; $k -lt $n; $k++) { $parts += "[${k}:a:0]aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo[a$k]" }
        } elseif ($plan.Kind -eq 'video') { $notes += 'Not every file has audio, so the merged video will have no audio track.' }
        $concatIn = ''
        for ($k = 0; $k -lt $n; $k++) { if ($plan.Kind -eq 'video') { $concatIn += "[v$k]" }; if ($allAudio) { $concatIn += "[a$k]" } }
        $vN = $(if ($plan.Kind -eq 'video') { 1 } else { 0 }); $aN = $(if ($allAudio) { 1 } else { 0 })
        $labels = ''; if ($vN) { $labels += '[vout]' }; if ($aN) { $labels += '[aout]' }
        $parts += "${concatIn}concat=n=${n}:v=${vN}:a=${aN}${labels}"
        Add-FFOutOpt $cmd @('-filter_complex', ($parts -join ';'))
        if ($vN) {
            $container = [string](Get-Answer $W 'format' 'mp4')
            $ve = Resolve-VideoEncode $W -Prefix 'v' -Container $container -Faststart $true
            Add-FFOutOpt $cmd @('-map', '[vout]'); Add-FFOutOpt $cmd $ve.Tokens
            if ($aN) { $ae = Resolve-AudioEncode $W -Prefix 'a' -Container $container -HasAudio $true; Add-FFOutOpt $cmd @('-map', '[aout]'); Add-FFOutOpt $cmd $ae.Tokens }
            Add-FFOutOpt $cmd @('-f', (Get-VideoContainer $container).Muxer)
        } else {
            $fmt = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))
            $ae = Resolve-AudioEncode $W -Prefix 'a' -Container '' -AllowedFamilies @($fmt.Codecs) -HasAudio $true
            Add-FFOutOpt $cmd @('-map', '[aout]'); Add-FFOutOpt $cmd $ae.Tokens
            Add-FFOutOpt $cmd @('-f', $fmt.Muxer)
        }
        $notes += 'The files are re-encoded to common settings' + $(if (-not $plan.CanCopy) { ': ' + $plan.Reason } else { '.' })
    }
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Files', ((@($infos | ForEach-Object { $_.FileName })) -join '  ->  ')), @('Method', $(if ($copy) { 'Lossless (stream copy)' } else { 'Re-encode' })), @('Output', $out.Path))
    return New-JobObject -Title 'Merging media' -Summary $rows -Stages @(@{ Name = 'Merging'; Arguments = (Get-FFTokens $cmd); DurationSec = $total }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -TempFiles $tempFiles -Notes $notes
}

function Start-MergeWorkflow {
    Start-StandardWorkflow -Title 'Merge Media' -Description 'Join multiple compatible video or audio files into one output.' -Icon 'Merge' -StepsFactory { Get-MergeSteps } -Build { param($W) Build-MergeJob $W }
}

Export-ModuleMember -Function Get-MergeCompatibility, Get-MergeSteps, Build-MergeJob, Start-MergeWorkflow
