# BatchConvert.psm1 - Batch Convert Folder: apply one conversion (same settings) to every media file in a folder.
# Reuses the single-file job builders, so a batch behaves exactly like converting each file by hand.
Set-StrictMode -Version 2.0

$script:BatchVideoExt = @('.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.ts', '.m4v', '.mpg', '.mpeg', '.3gp', '.mts', '.m2ts', '.vob', '.ogv')
$script:BatchAudioExt = @('.mp3', '.wav', '.flac', '.aac', '.m4a', '.ogg', '.opus', '.wma', '.aiff', '.aif', '.ac3', '.mka')
$script:BatchMaxFiles = 500

function Get-BatchCandidates {
    # Files in the folder (optionally recursive) whose extension belongs to the chosen kind.
    param([string]$Folder, [ValidateSet('video', 'audio')][string]$Kind, [bool]$Recurse = $false)
    $exts = $(if ($Kind -eq 'video') { $script:BatchVideoExt } else { $script:BatchAudioExt })
    $gci = @{ LiteralPath = $Folder; File = $true; ErrorAction = 'SilentlyContinue' }
    if ($Recurse) { $gci['Recurse'] = $true }
    return @(Get-ChildItem @gci | Where-Object { $exts -contains $_.Extension.ToLowerInvariant() } | Sort-Object FullName)
}

function Get-BatchSteps {
    $isVideo = { param($W) (Get-Answer $W 'kind') -eq 'video' }
    $isAudio = { param($W) (Get-Answer $W 'kind') -eq 'audio' }
    $cont = { param($W) [string](Get-Answer $W 'format' 'mp4') }
    $steps = @()
    $steps += @{ Id = 'folder'; Type = 'Directory'; Prompt = 'Folder with the files to convert'; Label = 'Folder'; MustExist = $true; Example = 'C:\Videos\Holiday'
        Help = 'Every matching file in this folder will be converted with the same settings. Your originals are never changed.'
        Validate = { param($v, $W) $n = @(Get-BatchCandidates $v 'video').Count + @(Get-BatchCandidates $v 'audio').Count; if ($n -eq 0) { return 'No video or audio files were found in that folder.' }; $null } }
    $steps += @{ Id = 'sub'; Type = 'YesNo'; Prompt = 'Include files in sub-folders too?'; Help = 'When you choose Yes, folders inside the folder are searched as well.'; Default = $false
        YesLabel = 'Yes, include sub-folders'; NoLabel = 'No, only this folder'; YesDesc = 'Converted files from sub-folders are placed directly in the output folder.'; NoDesc = 'Only files directly inside the folder are used.' }
    $steps += @{ Id = 'kind'; Type = 'Choice'; Prompt = 'What do you want to convert?'; Help = 'A batch converts one kind of file at a time.'
        Choices = { param($W)
            $f = [string](Get-Answer $W 'folder'); $r = [bool](Get-Answer $W 'sub' $false)
            $nv = @(Get-BatchCandidates $f 'video' $r).Count; $na = @(Get-BatchCandidates $f 'audio' $r).Count
            @( (New-Choice 'video' "Video files ($nv found)" 'Convert videos to another format.' ($nv -gt 0) 'There are no video files in the folder.'),
               (New-Choice 'audio' "Audio files ($na found)" 'Convert music or recordings to another audio format.' ($na -gt 0) 'There are no audio files in the folder.') ) }
        Default = { param($W) $f = [string](Get-Answer $W 'folder'); $r = [bool](Get-Answer $W 'sub' $false); if (@(Get-BatchCandidates $f 'video' $r).Count -gt 0) { 'video' } else { 'audio' } } }
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Convert videos to'; Help = 'The file type of every result.'; When = $isVideo
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mp4' }
    $steps += Get-VideoEncodeSteps -Prefix 'v' -ContainerScript $cont -Level Simple -GateWhen $isVideo
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Convert audio files to'; Help = 'The audio file type of every result.'; When = $isAudio
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mp3' }
    $steps += Get-AudioEncodeSteps -Prefix 'a' -FormatAudioFamilies { param($W) $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); if ($f) { @($f.Codecs) } else { @() } } -When $isAudio
    $steps += @{ Id = 'outdir'; Type = 'Choice'; Prompt = 'Output folder'; Help = 'Where the converted files are saved.'
        Choices = { param($W) $d = Join-Path ([string](Get-Answer $W 'folder')) 'Converted'; @( (New-Choice $d 'A "Converted" folder inside the source folder' $d) ) }
        AllowCustom = @{ Label = 'Choose another folder...'; Type = 'Directory'; Prompt = 'Output folder path'; Help = 'Type or paste a folder path. It is created when the batch starts.'; Example = 'C:\Videos\Converted'; Desc = 'Type or paste a folder path.' }
        Default = { param($W) Join-Path ([string](Get-Answer $W 'folder')) 'Converted' } }
    $steps += @{ Id = 'exists'; Type = 'Choice'; Prompt = 'If a converted file already exists'; Help = 'Existing files are never replaced unless you choose to.'
        Choices = { param($W) @( (New-Choice 'skip' 'Skip that file  (Recommended)' 'Keep the existing result and move on.'), (New-Choice 'overwrite' 'Overwrite it' 'Replace the existing converted file.') ) }; Default = 'skip' }
    return $steps
}

function Build-BatchJob {
    param($W)
    $folder = [string](Get-Answer $W 'folder'); $recurse = [bool](Get-Answer $W 'sub' $false)
    $kind = [string](Get-Answer $W 'kind' 'video')
    $outDir = [string](Get-Answer $W 'outdir')
    $overwrite = ((Get-Answer $W 'exists' 'skip') -eq 'overwrite')
    $files = @(Get-BatchCandidates $folder $kind $recurse)
    # Never convert files that already live in the output folder.
    $outFull = [System.IO.Path]::GetFullPath($outDir).TrimEnd('\', '/')
    $files = @($files | Where-Object { -not ([System.IO.Path]::GetFullPath($_.DirectoryName).TrimEnd('\', '/')).StartsWith($outFull, [StringComparison]::OrdinalIgnoreCase) })
    if ($files.Count -eq 0) { throw 'No files to convert were found.' }
    if ($files.Count -gt $script:BatchMaxFiles) { throw "That is $($files.Count) files; a batch is limited to $script:BatchMaxFiles. Use a smaller folder." }
    if ($kind -eq 'video') { $ext = (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext } else { $ext = (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))).Ext }
    $stages = @(); $skipped = @(); $expected = @(); $used = @{}
    $i = 0
    foreach ($f in $files) {
        $i++
        $m = Get-MediaInfo -Path $f.FullName
        if (-not $m.Ok) { $skipped += "$($f.Name): not readable as media"; continue }
        $info = $m.Info
        if ($kind -eq 'video' -and (-not $info.HasVideo -or $info.IsImageOnly)) { $skipped += "$($f.Name): has no video"; continue }
        if ($kind -eq 'audio' -and (-not $info.HasAudio)) { $skipped += "$($f.Name): has no audio"; continue }
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $name = $stem + $ext
        $n = 1; while ($used.ContainsKey($name.ToLowerInvariant())) { $n++; $name = "${stem}_$n$ext" }
        $target = Join-Path $outDir $name
        if ([string]::Equals([System.IO.Path]::GetFullPath($target), $f.FullName, [StringComparison]::OrdinalIgnoreCase)) { $name = $stem + '_converted' + $ext; $target = Join-Path $outDir $name }
        if ((Test-Path -LiteralPath $target) -and -not $overwrite) { $skipped += "$($f.Name): output already exists"; continue }
        $used[$name.ToLowerInvariant()] = $true
        $w2 = @{ Answers = @{}; Data = @{}; Panels = [ordered]@{}; Title = $W.Title; Description = ''; Icon = ''; Goto = $null; Step = $null; Error = '' }
        foreach ($k in $W.Answers.Keys) { $w2.Answers[$k] = $W.Answers[$k] }
        foreach ($k in $W.Data.Keys) { $w2.Data[$k] = $W.Data[$k] }
        $w2.Data['probe.input'] = $info
        $w2.Answers['outdir'] = $outDir; $w2.Answers['outname'] = $name; $w2.Answers['outoverwrite'] = $(if ($overwrite) { 'overwrite' } else { 'rename' })
        $extCopy = $ext
        $w2.Data['outext'] = { param($x) $extCopy }.GetNewClosure()
        try {
            if ($kind -eq 'video') {
                $j = New-VideoProcessJob -W $w2 -Title 'Batch' -Rows @() -AudioMode copy -StageName 'Converting'
            } else {
                $j = New-AudioProcessJob -W $w2 -Title 'Batch' -Rows @() -StageName 'Converting'
            }
        } catch { $skipped += "$($f.Name): $($_.Exception.Message)"; continue }
        $st = $j.Stages[0]
        $st.Name = ('File {0} of {1}: {2}' -f ($stages.Count + 1), '{TOTAL}', $f.Name)
        $stages += , $st
        $expected += $target
    }
    if ($stages.Count -eq 0) { throw ('Nothing to convert. ' + (($skipped | Select-Object -First 3) -join '; ')) }
    for ($k = 0; $k -lt $stages.Count; $k++) { $stages[$k].Name = $stages[$k].Name.Replace('{TOTAL}', [string]$stages.Count) }
    $notes = @()
    if ($skipped.Count -gt 0) { $notes += ("$($skipped.Count) file(s) will be skipped: " + (($skipped | Select-Object -First 5) -join '; ') + $(if ($skipped.Count -gt 5) { '; ...' } else { '' })) }
    if ($overwrite) { $notes += 'Existing converted files will be overwritten.' }
    $notes += 'The batch stops at the first file that fails; files already converted are kept.'
    $rows = @(@('Folder', $folder), @('Files', [string]$stages.Count), @('Convert to', $ext.TrimStart('.').ToUpperInvariant()), @('Output folder', $outDir))
    $exp = $expected
    $count = { @($exp | Where-Object { Test-Path -LiteralPath $_ }).Count }.GetNewClosure()
    return New-JobObject -Title 'Batch conversion' -Summary $rows -Stages $stages -OutputPath $outDir -OutputKind 'Folder' -EnsureDirs @($outDir) -Notes $notes -CountOutputs $count
}

function Start-BatchWorkflow {
    Start-StandardWorkflow -Title 'Batch Convert Folder' -Description 'Convert every video or audio file in a folder with the same settings.' -Icon 'Batch' -StepsFactory { Get-BatchSteps } -Build { param($W) Build-BatchJob $W }
}

Export-ModuleMember -Function Get-BatchCandidates, Get-BatchSteps, Build-BatchJob, Start-BatchWorkflow
