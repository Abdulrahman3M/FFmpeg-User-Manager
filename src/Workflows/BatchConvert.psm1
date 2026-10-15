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
    return @(Get-BatchFilesFromFolder -Folder $Folder -Extensions $exts -Recurse $Recurse)
}

function Get-BatchSelectedInventory {
    param($W, [ValidateSet('video', 'audio')][string]$Kind)
    $exts = $(if ($Kind -eq 'video') { $script:BatchVideoExt } else { $script:BatchAudioExt })
    if ((Get-Answer $W 'inputmode' 'folder') -eq 'folder') {
        return Get-BatchFolderInventory -Folder ([string](Get-Answer $W 'folder')) -Extensions $exts -Recurse ([bool](Get-Answer $W 'sub' $false))
    }
    $all = @(Get-Answer $W 'files' @())
    $files = @($all | Where-Object { $_ -and $exts -contains [System.IO.Path]::GetExtension($_).ToLowerInvariant() } | ForEach-Object { Get-Item -LiteralPath $_ -ErrorAction SilentlyContinue } | Where-Object { $_ })
    return [pscustomobject]@{ Total = $all.Count; Compatible = $files.Count; Unsupported = ($all.Count - $files.Count); Files = $files }
}

function Get-BatchSelectedCandidates {
    param($W, [ValidateSet('video', 'audio')][string]$Kind)
    return @((Get-BatchSelectedInventory $W $Kind).Files)
}

function Test-BatchPathWithinDirectory {
    param([string]$Path, [string]$Directory)
    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    $fullDir = [System.IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    $prefix = $fullDir + [System.IO.Path]::DirectorySeparatorChar
    return $fullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($fullPath, $fullDir, [StringComparison]::OrdinalIgnoreCase)
}

function Get-BatchSteps {
    $isVideo = { param($W) (Get-Answer $W 'kind') -eq 'video' }
    $isAudio = { param($W) (Get-Answer $W 'kind') -eq 'audio' }
    $cont = { param($W) [string](Get-Answer $W 'format' 'mp4') }
    $steps = @()
    $steps += @{ Id = 'inputmode'; Type = 'Choice'; Prompt = 'Select input'; Help = 'Choose files individually or scan one folder. Settings are collected once and then applied to the queue.'
        Choices = { param($W) @((New-Choice 'folder' 'Folder' 'Scan one folder for compatible video or audio files.'), (New-Choice 'multiple' 'Multiple files' 'Build an ordered list of files to process with the same settings.')) }; Default = 'folder' }
    $steps += @{ Id = 'files'; Type = 'Files'; Prompt = 'Files to convert'; Min = 1; When = { param($W) (Get-Answer $W 'inputmode') -eq 'multiple' }
        Help = 'Add one or more readable media files. The queue processes them in the order shown.' }
    $steps += @{ Id = 'folder'; Type = 'Directory'; Prompt = 'Folder with the files to convert'; Label = 'Folder'; MustExist = $true; Example = 'C:\Videos\Holiday'; When = { param($W) (Get-Answer $W 'inputmode') -eq 'folder' }
        Help = 'Every matching file in this folder will be converted with the same settings. Your originals are never changed.'
        Validate = {
            param($v, $W)
            $inventory = Get-BatchFolderInventory -Folder $v -Extensions @($script:BatchVideoExt + $script:BatchAudioExt)
            if ($inventory.Compatible -eq 0) { return 'No compatible video or audio files were found in that folder.' }
            Set-WizardPanel $W 'batch.input' 'Folder scan' @(@('Files scanned', [string]$inventory.Total), @('Compatible media', [string]$inventory.Compatible), @('Unsupported', [string]$inventory.Unsupported)) 18
            $null
        } }
    $steps += @{ Id = 'sub'; Type = 'YesNo'; Prompt = 'Include files in sub-folders too?'; Help = 'When you choose Yes, folders inside the folder are searched as well.'; Default = $false; When = { param($W) (Get-Answer $W 'inputmode') -eq 'folder' }
        YesLabel = 'Yes, include sub-folders'; NoLabel = 'No, only this folder'; YesDesc = 'Converted files from sub-folders are placed directly in the output folder.'; NoDesc = 'Only files directly inside the folder are used.' }
    $steps += @{ Id = 'kind'; Type = 'Choice'; Prompt = 'What do you want to convert?'; Help = 'A batch converts one kind of file at a time.'
        Choices = { param($W)
            $vi = Get-BatchSelectedInventory $W 'video'; $ai = Get-BatchSelectedInventory $W 'audio'
            @( (New-Choice 'video' "Video files ($($vi.Compatible) compatible)" ("Convert $($vi.Compatible) video file(s); $($vi.Unsupported) other or unsupported file(s) will be ignored.") ($vi.Compatible -gt 0) 'There are no compatible video files in this input.'),
               (New-Choice 'audio' "Audio files ($($ai.Compatible) compatible)" ("Convert $($ai.Compatible) audio file(s); $($ai.Unsupported) other or unsupported file(s) will be ignored.") ($ai.Compatible -gt 0) 'There are no compatible audio files in this input.') ) }
        Default = { param($W) if ((Get-BatchSelectedInventory $W 'video').Compatible -gt 0) { 'video' } else { 'audio' } } }
    $steps += @{ Id = 'format'; Type = 'Choice'; Prompt = 'Convert videos to'; Help = 'The file type of every result.'; When = $isVideo
        Choices = { param($W) @(Get-AvailableVideoContainers | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mp4' }
    $steps += Get-VideoEncodeSteps -Prefix 'v' -ContainerScript $cont -Level Simple -GateWhen $isVideo
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Convert audio files to'; Help = 'The audio file type of every result.'; When = $isAudio
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mp3' }
    $steps += Get-AudioEncodeSteps -Prefix 'a' -FormatAudioFamilies { param($W) $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); if ($f) { @($f.Codecs) } else { @() } } -When $isAudio
    $steps += @{ Id = 'outdir'; Type = 'Choice'; Prompt = 'Output folder'; Help = 'Where the converted files are saved.'
        Choices = { param($W) $base = [string](Get-Answer $W 'folder'); if (-not $base) { $base = [System.IO.Path]::GetDirectoryName([string](@(Get-Answer $W 'files')[0])) }; $d = Join-Path $base 'Converted'; @( (New-Choice $d 'A "Converted" folder inside the source folder' $d) ) }
        AllowCustom = @{ Label = 'Choose another folder...'; Type = 'Directory'; Prompt = 'Output folder path'; Help = 'Type or paste a folder path. It is created when the batch starts.'; Example = 'C:\Videos\Converted'; Desc = 'Type or paste a folder path.' }
        Default = { param($W) $base = [string](Get-Answer $W 'folder'); if (-not $base) { $base = [System.IO.Path]::GetDirectoryName([string](@(Get-Answer $W 'files')[0])) }; Join-Path $base 'Converted' } }
    $steps += @{ Id = 'exists'; Type = 'Choice'; Prompt = 'If a converted file already exists'; Help = 'Existing files are never replaced unless you choose to.'
        Choices = { param($W) @( (New-Choice 'skip' 'Skip that file  (Recommended)' 'Keep the existing result and move on.'), (New-Choice 'rename' 'Auto rename the new file' 'Keep the existing result and create a numbered new file.'), (New-Choice 'overwrite' 'Overwrite it' 'Replace the existing converted file after this one-time choice.') ) }; Default = 'skip' }
    return $steps
}

function Build-BatchJob {
    param($W)
    $kind = [string](Get-Answer $W 'kind' 'video')
    $outDir = [string](Get-Answer $W 'outdir')
    $policy = [string](Get-Answer $W 'exists' 'skip')
    $files = @(Get-BatchSelectedCandidates $W $kind)
    # For folder scans, ignore prior results only when the output is a nested directory.
    # An output folder equal to the source folder is valid and must not exclude every input.
    if ((Get-Answer $W 'inputmode' 'folder') -eq 'folder') {
        $sourceFull = [System.IO.Path]::GetFullPath([string](Get-Answer $W 'folder')).TrimEnd('\', '/')
        $outFull = [System.IO.Path]::GetFullPath($outDir).TrimEnd('\', '/')
        if (-not [string]::Equals($sourceFull, $outFull, [StringComparison]::OrdinalIgnoreCase) -and (Test-BatchPathWithinDirectory -Path $outFull -Directory $sourceFull)) {
            $files = @($files | Where-Object { -not (Test-BatchPathWithinDirectory -Path $_.DirectoryName -Directory $outFull) })
        }
    }
    if ($files.Count -eq 0) { throw 'No files to convert were found.' }
    if ($files.Count -gt $script:BatchMaxFiles) { throw "That is $($files.Count) files; a batch is limited to $script:BatchMaxFiles. Use a smaller folder." }
    if ($kind -eq 'video') { $ext = (Get-VideoContainer ([string](Get-Answer $W 'format' 'mp4'))).Ext } else { $ext = (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))).Ext }
    $stages = @(); $skipped = @(); $expected = @(); $used = @{}
    $queue = @(New-BatchQueue -Paths @($files | ForEach-Object { $_.FullName }))
    $i = 0
    foreach ($f in $files) {
        $i++
        $m = Get-MediaInfo -Path $f.FullName
        if (-not $m.Ok) { $skipped += "$($f.Name): not readable as media"; $queue[$i - 1].Status = 'Skipped'; $queue[$i - 1].Error = 'Not readable as media'; continue }
        $info = $m.Info
        if ($kind -eq 'video' -and (-not $info.HasVideo -or $info.IsImageOnly)) { $skipped += "$($f.Name): has no video"; $queue[$i - 1].Status = 'Skipped'; $queue[$i - 1].Error = 'Has no video'; continue }
        if ($kind -eq 'audio' -and (-not $info.HasAudio)) { $skipped += "$($f.Name): has no audio"; $queue[$i - 1].Status = 'Skipped'; $queue[$i - 1].Error = 'Has no audio'; continue }
        $plan = Resolve-BatchOutputPath -InputPath $f.FullName -OutputFolder $outDir -Extension $ext -Policy $policy -ReservedNames $used
        if ($plan.Action -eq 'Skip') { $skipped += "$($f.Name): output already exists"; $queue[$i - 1].Status = 'Skipped'; $queue[$i - 1].Error = 'Output already exists'; continue }
        $target = $plan.ActionPath; $name = [System.IO.Path]::GetFileName($target)
        $used[$name.ToLowerInvariant()] = $true
        $w2 = @{ Answers = @{}; Data = @{}; Panels = [ordered]@{}; Title = $W.Title; Description = ''; Icon = ''; Goto = $null; Step = $null; Error = '' }
        foreach ($k in $W.Answers.Keys) { $w2.Answers[$k] = $W.Answers[$k] }
        foreach ($k in $W.Data.Keys) { $w2.Data[$k] = $W.Data[$k] }
        $w2.Data['probe.input'] = $info
        $w2.Answers['outdir'] = $outDir; $w2.Answers['outname'] = $name; $w2.Answers['outoverwrite'] = $(if ($plan.Overwrite) { 'overwrite' } else { 'rename' })
        $extCopy = $ext
        $w2.Data['outext'] = { param($x) $extCopy }.GetNewClosure()
        try {
            if ($kind -eq 'video') {
                $j = New-VideoProcessJob -W $w2 -Title 'Batch' -Rows @() -AudioMode copy -StageName 'Converting'
            } else {
                $j = New-AudioProcessJob -W $w2 -Title 'Batch' -Rows @() -StageName 'Converting'
            }
        } catch { $skipped += "$($f.Name): $($_.Exception.Message)"; $queue[$i - 1].Status = 'Skipped'; $queue[$i - 1].Error = $_.Exception.Message; continue }
        $st = $j.Stages[0]
        $st.Name = ('File {0} of {1}: {2}' -f ($stages.Count + 1), '{TOTAL}', $f.Name)
        $st.BatchItem = $queue[$i - 1]
        $stages += , $st
        $expected += $target
    }
    if ($stages.Count -eq 0) { throw ('Nothing to convert. ' + (($skipped | Select-Object -First 3) -join '; ')) }
    for ($k = 0; $k -lt $stages.Count; $k++) { $stages[$k].Name = $stages[$k].Name.Replace('{TOTAL}', [string]$stages.Count) }
    $notes = @()
    if ($skipped.Count -gt 0) { $notes += ("$($skipped.Count) file(s) will be skipped: " + (($skipped | Select-Object -First 5) -join '; ') + $(if ($skipped.Count -gt 5) { '; ...' } else { '' })) }
    if ($policy -eq 'overwrite') { $notes += 'Existing converted files will be overwritten.' }
    $notes += 'A failed file is recorded and the queue continues with the next file.'
    $sourceLabel = if ((Get-Answer $W 'inputmode' 'folder') -eq 'folder') { [string](Get-Answer $W 'folder') } else { 'Selected file list' }
    $rows = @(@('Input', $sourceLabel), @('Files', [string]$stages.Count), @('Convert to', $ext.TrimStart('.').ToUpperInvariant()), @('Output folder', $outDir), @('Collision policy', $policy))
    $exp = $expected
    $count = { @($exp | Where-Object { Test-Path -LiteralPath $_ }).Count }.GetNewClosure()
    $job = New-JobObject -Title 'Batch conversion' -Summary $rows -Stages $stages -OutputPath $outDir -OutputKind 'Folder' -EnsureDirs @($outDir) -Notes $notes -CountOutputs $count
    $job.BatchQueue = $queue; $job.ContinueOnFailure = $true
    return $job
}

function Start-BatchWorkflow {
    Start-StandardWorkflow -Title 'Batch Convert' -Description 'Convert selected files or a folder with one shared set of settings.' -Icon 'Batch' -StepsFactory { Get-BatchSteps } -Build { param($W) Build-BatchJob $W }
}

Export-ModuleMember -Function Get-BatchCandidates, Get-BatchSelectedCandidates, Get-BatchSteps, Build-BatchJob, Start-BatchWorkflow
