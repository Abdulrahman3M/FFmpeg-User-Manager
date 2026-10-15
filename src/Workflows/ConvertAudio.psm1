# ConvertAudio.psm1 - workflow 2: Convert Audio Format.
Set-StrictMode -Version 2.0

function Get-ConvertAudioSteps {
    $fam = { param($W) $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); if ($f) { @($f.Codecs) } else { @() } }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input audio file' -Require Audio -Example 'C:\Music\song.flac'
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Output format'; Help = 'Only formats supported by your FFmpeg build are listed.'
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }
        Default = { param($W) $m = Get-Media $W 'input'; $e = [System.IO.Path]::GetExtension($m.Path).ToLowerInvariant().TrimStart('.'); foreach ($f in Get-AvailableAudioFormats) { if ($f.Id -ne $e) { return $f.Id } }; 'mp3' } }
    $steps += Get-AudioEncodeSteps -Prefix 'a' -FormatAudioFamilies $fam -Full -OfferVbr
    $steps += Get-MetadataStep -Id 'metadata'
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'converted' -Extension { param($W) (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))).Ext }
    return $steps
}

function Build-ConvertAudioJob {
    param($W)
    $info = Get-Media $W 'input'
    $fmt = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))
    $out = Get-OutputFile $W
    $ae = Resolve-AudioEncode $W -Prefix 'a' -Container '' -AllowedFamilies @($fmt.Codecs) -HasAudio $true
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path)
    Add-FFOutOpt $cmd @('-vn', '-map', ('0:' + $info.Audio[0].Index))
    Add-FFOutOpt $cmd $ae.Tokens
    Add-FFOutOpt $cmd (Get-MetadataTokens ([string](Get-Answer $W 'metadata' 'keep')))
    Add-FFOutOpt $cmd @('-f', $fmt.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($info.Audio.Count -gt 1) { $notes += 'The file has several audio tracks; the first one is converted.' }
    if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(, @('Input', $info.FileName)) + @(@('Format', $fmt.Label), @('Encoder', $ae.Encoder), @('Output', $out.Path))
    return New-JobObject -Title 'Converting audio' -Summary $rows -Stages @(@{ Name = 'Encoding audio'; Arguments = (Get-FFTokens $cmd); DurationSec = $info.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -SourceSize $info.Size -CompareSize $true -Notes $notes
}

function Start-ConvertAudioWorkflow {
    Start-StandardWorkflow -Title 'Convert Audio Format' -Description 'Convert an audio file to MP3, AAC, FLAC, WAV, Opus and other supported formats.' -Icon 'Audio' -StepsFactory { Get-ConvertAudioSteps } -Build { param($W) Build-ConvertAudioJob $W }
}

Export-ModuleMember -Function Get-ConvertAudioSteps, Build-ConvertAudioJob, Start-ConvertAudioWorkflow
