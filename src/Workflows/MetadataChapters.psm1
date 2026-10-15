# MetadataChapters.psm1 - Metadata & Chapters: edit tags, strip metadata/chapters, add chapters, attach cover art.
# Every tool copies the streams (no re-encoding); only the labels inside the file change.
Set-StrictMode -Version 2.0

function Get-SameContainerExt {
    param($Info)
    $e = [System.IO.Path]::GetExtension($Info.Path)
    if ($e) { return $e }
    return '.mkv'
}

function ConvertTo-FFMetadataValue {
    # ffmetadata files escape = ; # \ and newlines with a backslash.
    param([string]$Text)
    $s = $Text.Replace('\', '\\').Replace('=', '\=').Replace(';', '\;').Replace('#', '\#')
    return ($s -replace "`r?`n", ('\' + "`n"))
}

function ConvertFrom-ChapterList {
    # 'HH:MM:SS Title; HH:MM:SS Title' -> @{ Ok; Chapters = @(@{ Start; Title }); Error }
    param([string]$Text, $Duration = $null)
    $chapters = @()
    $parts = @($Text -split ';' | Where-Object { $_.Trim() })
    if ($parts.Count -eq 0) { return @{ Ok = $false; Chapters = @(); Error = 'Enter at least one chapter.' } }
    $last = -1.0
    foreach ($p in $parts) {
        $m = [regex]::Match($p.Trim(), '^(\S+)\s+(.+)$')
        if (-not $m.Success) { return @{ Ok = $false; Chapters = @(); Error = "Each chapter needs a time and a title, for example 00:01:30 Introduction. Problem with: $($p.Trim())" } }
        $t = ConvertFrom-TimestampText $m.Groups[1].Value
        if (-not $t.Ok) { return @{ Ok = $false; Chapters = @(); Error = "'$($m.Groups[1].Value)' is not a valid time. Use HH:MM:SS, MM:SS or seconds." } }
        if ($t.Value -le $last) { return @{ Ok = $false; Chapters = @(); Error = 'Chapter times must be in increasing order.' } }
        if ($null -ne $Duration -and $t.Value -ge $Duration) { return @{ Ok = $false; Chapters = @(); Error = ('Chapter time {0} is beyond the end of the media ({1}).' -f $m.Groups[1].Value, (Format-Duration $Duration)) } }
        $last = $t.Value
        $chapters += , @{ Start = [double]$t.Value; Title = $m.Groups[2].Value.Trim() }
    }
    return @{ Ok = $true; Chapters = $chapters; Error = '' }
}

function New-FFMetadataChapterText {
    param($Chapters, [double]$Duration)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(";FFMETADATA1`n")
    for ($i = 0; $i -lt $Chapters.Count; $i++) {
        $start = [long][math]::Round($Chapters[$i].Start * 1000)
        $end = [long][math]::Round($Duration * 1000)
        if ($i -lt $Chapters.Count - 1) { $end = [long][math]::Round($Chapters[$i + 1].Start * 1000) }
        [void]$sb.Append("[CHAPTER]`nTIMEBASE=1/1000`nSTART=$start`nEND=$end`ntitle=" + (ConvertTo-FFMetadataValue $Chapters[$i].Title) + "`n")
    }
    return $sb.ToString()
}

# ---- 1. Edit metadata --------------------------------------------------------------------------

$script:MetaFields = @(
    @{ Id = 'title'; Label = 'Title'; Example = 'Summer trip 2025'; Help = 'The name shown by players.' },
    @{ Id = 'artist'; Label = 'Artist / Author'; Example = 'Jane Doe'; Help = 'Who made it.' },
    @{ Id = 'album'; Label = 'Album'; Example = 'Holiday songs'; Help = 'Album or collection name (mostly for music).' },
    @{ Id = 'genre'; Label = 'Genre'; Example = 'Documentary'; Help = 'Category of the content.' },
    @{ Id = 'date'; Label = 'Year / Date'; Example = '2025'; Help = 'Release year or date.' },
    @{ Id = 'comment'; Label = 'Comment'; Example = 'Recorded with my phone'; Help = 'Any note you want stored in the file.' }
)

function Get-EditMetadataSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media file' -Require Media -Help 'The file whose tags (title, artist and so on) you want to change. Audio and video are not re-encoded.'
    foreach ($f in $script:MetaFields) {
        $steps += @{ Id = 'm_' + $f.Id; Type = 'Text'; Prompt = $f.Label; Label = $f.Label; Optional = $true; Example = $f.Example
            Help = $f.Help + ' Leave empty to keep the current value unchanged.'
            Default = { param($W) '' } }
    }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'tagged' -Extension { param($W) Get-SameContainerExt (Get-Media $W 'input') }
    return $steps
}

function Build-EditMetadataJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $pairs = @()
    foreach ($f in $script:MetaFields) { $v = [string](Get-Answer $W ('m_' + $f.Id) ''); if ($v.Trim()) { $pairs += , @($f.Id, $v.Trim(), $f.Label) } }
    if ($pairs.Count -eq 0) { throw 'Nothing to change: fill in at least one field.' }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    Add-FFOutOpt $cmd (Get-CopyMapTokens (Get-SameContainerExt $info))
    Add-FFOutOpt $cmd @('-c', 'copy', '-map_metadata', '0')
    foreach ($p in $pairs) { Add-FFOutOpt $cmd @('-metadata', ($p[0] + '=' + $p[1])) }
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(, @('Input', $info.FileName))
    foreach ($p in $pairs) { $rows += , @($p[2], $p[1]) }
    $rows += , @('Output', $out.Path)
    return New-JobObject -Title 'Editing metadata' -Summary $rows -Stages @(@{ Name = 'Writing metadata'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $false -Notes $notes
}

# ---- 2. Strip metadata / chapters --------------------------------------------------------------

function Get-StripMetadataSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media file' -Require Media -Help 'Useful before sharing a file publicly: it can remove titles, dates, encoder names and chapters.'
    $steps += @{ Id = 'scope'; Type = 'Choice'; Prompt = 'What should be removed?'; Help = 'Audio and video are never touched.'
        Choices = { param($W) @(
            (New-Choice 'all' 'Everything: tags and chapters' 'Cleanest file; players show only the file name.'),
            (New-Choice 'tags' 'Tags only (keep chapters)' 'Remove title, artist, dates and so on; chapters stay.'),
            (New-Choice 'chapters' 'Chapters only (keep tags)' 'Remove the chapter list; tags stay.')) }
        Default = 'all' }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'clean' -Extension { param($W) Get-SameContainerExt (Get-Media $W 'input') }
    return $steps
}

function Build-StripMetadataJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $scope = [string](Get-Answer $W 'scope' 'all')
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    Add-FFOutOpt $cmd (Get-CopyMapTokens (Get-SameContainerExt $info))
    Add-FFOutOpt $cmd @('-c', 'copy')
    switch ($scope) {
        'tags' { Add-FFOutOpt $cmd @('-map_metadata', '-1', '-map_chapters', '0') }
        'chapters' { Add-FFOutOpt $cmd @('-map_metadata', '0', '-map_chapters', '-1') }
        default { Add-FFOutOpt $cmd @('-map_metadata', '-1', '-map_chapters', '-1') }
    }
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('Removing', @{ all = 'Tags and chapters'; tags = 'Tags'; chapters = 'Chapters' }[$scope]), @('Output', $out.Path))
    return New-JobObject -Title 'Removing metadata' -Summary $rows -Stages @(@{ Name = 'Copying without metadata'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $false -Notes $notes
}

# ---- 3. Chapters ------------------------------------------------------------------------------------

function Get-ChapterSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input media file' -Require Media -Help 'Chapters let viewers jump to sections. Supported in MKV, MP4, M4A/M4B and MOV files.' -Extra {
        param($info, $W) $e = [System.IO.Path]::GetExtension($info.Path).ToLowerInvariant()
        if ($e -notin @('.mkv', '.mka', '.mp4', '.m4a', '.m4b', '.mov', '.webm')) { return "Chapters cannot be stored in $e files. Convert the file to MKV or MP4 first (Remux & Streams)." }; $null }
    $steps += @{ Id = 'chapters'; Type = 'Text'; Prompt = 'Chapter list'; Label = 'Chapters'
        Help = 'Write each chapter as start time + title, separated by semicolons. The first chapter normally starts at 00:00:00. Existing chapters are replaced.'
        Example = '00:00:00 Intro; 00:02:30 Main part; 00:08:10 Ending'
        Validate = { param($v, $W) $m = Get-Media $W 'input'; $r = ConvertFrom-ChapterList $v $m.Duration; if (-not $r.Ok) { return $r.Error }; $null } }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'chapters' -Extension { param($W) Get-SameContainerExt (Get-Media $W 'input') }
    return $steps
}

function Build-ChapterJob {
    param($W)
    $info = Get-Media $W 'input'
    $out = Get-OutputFile $W
    $r = ConvertFrom-ChapterList ([string](Get-Answer $W 'chapters')) $info.Duration
    if (-not $r.Ok) { throw $r.Error }
    $dur = $info.Duration; if (-not $dur) { $dur = $r.Chapters[$r.Chapters.Count - 1].Start + 1 }
    $meta = New-TempTextFile -Content (New-FFMetadataChapterText $r.Chapters $dur) -Suffix '.ffmeta'
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    [void](Add-FFInput $cmd $meta @('-f', 'ffmetadata'))
    Add-FFOutOpt $cmd (Get-CopyMapTokens (Get-SameContainerExt $info))
    Add-FFOutOpt $cmd @('-c', 'copy', '-map_metadata', '0', '-map_chapters', '1')
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('Chapters', [string]$r.Chapters.Count))
    foreach ($c in $r.Chapters) { $rows += , @(('  ' + (ConvertTo-TimestampText $c.Start)), $c.Title) }
    $rows += , @('Output', $out.Path)
    return New-JobObject -Title 'Adding chapters' -Summary $rows -Stages @(@{ Name = 'Writing chapters'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -TempFiles @($meta) -SourceSize $info.Size -CompareSize $false -Notes $notes
}

# ---- 4. Cover art ---------------------------------------------------------------------------------

function Get-CoverArtSteps {
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Audio file' -Require Audio -Help 'An MP3, M4A or FLAC file that should get a cover picture.' -Extra {
        param($info, $W) $e = [System.IO.Path]::GetExtension($info.Path).ToLowerInvariant()
        if ($e -notin @('.mp3', '.m4a', '.flac')) { return 'Cover art can be attached to MP3, M4A and FLAC files. Convert the file first with Convert Audio Format.' }; $null }
    $steps += Get-InputFileStep -Id 'cover' -Prompt 'Cover picture' -Require Video -NoPanel -Example 'C:\Pictures\cover.jpg' -Help 'A JPG or PNG image. Square pictures of at least 500x500 pixels look best.' -Extra {
        param($info, $W) if ($info.Video[0].Codec -notin @('mjpeg', 'png')) { return 'Use a JPG or PNG picture.' }; $null }
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'cover' -Extension { param($W) Get-SameContainerExt (Get-Media $W 'input') }
    return $steps
}

function Build-CoverArtJob {
    param($W)
    $info = Get-Media $W 'input'
    $pic = Get-Media $W 'cover'
    $out = Get-OutputFile $W
    $ext = (Get-SameContainerExt $info).ToLowerInvariant()
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    [void](Add-FFInput $cmd $pic.Path)
    Add-FFOutOpt $cmd @('-map', '0:a', '-map', '1:v', '-c', 'copy', '-map_metadata', '0', '-disposition:v:0', 'attached_pic')
    if ($ext -eq '.mp3') { Add-FFOutOpt $cmd @('-id3v2_version', '3', '-metadata:s:v', 'title=Album cover', '-metadata:s:v', 'comment=Cover (front)') }
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Audio', $info.FileName), @('Cover', $pic.FileName), @('Output', $out.Path))
    return New-JobObject -Title 'Attaching cover art' -Summary $rows -Stages @(@{ Name = 'Attaching cover'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $false -Notes $notes
}

function Start-MetadataChaptersWorkflow {
    $items = @(
        @{ Label = 'Edit Metadata (Tags)'; Icon = 'Tag'; Desc = 'Change the title, artist, album, genre, year or comment of a file. No re-encoding.'; Value = { Start-StandardWorkflow -Title 'Edit Metadata' -Description 'Change the tags stored in a media file.' -Icon 'Tag' -StepsFactory { Get-EditMetadataSteps } -Build { param($W) Build-EditMetadataJob $W } } },
        @{ Label = 'Remove Metadata / Chapters'; Icon = 'Remove'; Desc = 'Clean tags and chapters before sharing a file. Picture and sound stay identical.'; Value = { Start-StandardWorkflow -Title 'Remove Metadata' -Description 'Strip tags and chapters from a file.' -Icon 'Remove' -StepsFactory { Get-StripMetadataSteps } -Build { param($W) Build-StripMetadataJob $W } } },
        @{ Label = 'Add Chapters'; Icon = 'Chapters'; Desc = 'Give a long video or audiobook a chapter list so viewers can jump to sections.'; Value = { Start-StandardWorkflow -Title 'Add Chapters' -Description 'Write a chapter list into a file.' -Icon 'Chapters' -StepsFactory { Get-ChapterSteps } -Build { param($W) Build-ChapterJob $W } } },
        @{ Label = 'Attach Cover Art to Audio'; Icon = 'Image'; Desc = 'Embed a cover picture in an MP3, M4A or FLAC file so players display it.'; Value = { Start-StandardWorkflow -Title 'Attach Cover Art' -Description 'Embed a picture in an audio file.' -Icon 'Image' -StepsFactory { Get-CoverArtSteps } -Build { param($W) Build-CoverArtJob $W } } }
    )
    Show-WorkflowSubmenu -Title ((Get-Icon 'Tag') + '  Metadata & Chapters') -Subtitle 'Edit the labels stored inside media files. Audio and video are never re-encoded.' -Items $items
}

Export-ModuleMember -Function ConvertTo-FFMetadataValue, ConvertFrom-ChapterList, New-FFMetadataChapterText, Get-EditMetadataSteps, Build-EditMetadataJob, Get-StripMetadataSteps, Build-StripMetadataJob, Get-ChapterSteps, Build-ChapterJob, Get-CoverArtSteps, Build-CoverArtJob, Start-MetadataChaptersWorkflow
