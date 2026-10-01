# ExtractAudio.psm1 - workflow 3: Extract Audio from Video.
Set-StrictMode -Version 2.0

function Get-CopyFormatForCodec {
    # Container that can hold a copied audio stream of the given codec without re-encoding.
    param([string]$Codec)
    $fam = Get-AudioFamily $Codec
    switch ($fam) { 'aac' { 'm4a' } 'alac' { 'm4a' } 'mp3' { 'mp3' } 'opus' { 'opus' } 'vorbis' { 'ogg' } 'flac' { 'flac' } 'ac3' { 'ac3' } 'pcm' { 'wav' } default { 'mka' } }
}

function Get-AudioStreamLabel {
    param($A, [int]$Ordinal)
    $t = "Track $($Ordinal + 1): " + (Get-AudioLine $A)
    if ($A.Language) { $t += "  [$($A.Language)]" }
    if ($A.Title) { $t += "  $($A.Title)" }
    return $t
}

function Get-ExtractAudioSteps {
    $fam = { param($W) $f = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3')); if ($f) { @($f.Codecs) } else { @() } }
    $convert = { param($W) (Get-Answer $W 'mode') -eq 'convert' }
    $steps = @()
    $steps += Get-InputFileStep -Id 'input' -Prompt 'Input video' -Require Audio
    $steps += @{ Id = 'stream'; Type = 'Choice'; Prompt = 'Audio track'; Help = 'This file contains several audio tracks. Choose the one to extract.'
        When = { param($W) (Get-Media $W 'input').Audio.Count -gt 1 }
        Choices = { param($W) $m = Get-Media $W 'input'; $l = @(); for ($i = 0; $i -lt $m.Audio.Count; $i++) { $l += , (New-Choice $m.Audio[$i].Index (Get-AudioStreamLabel $m.Audio[$i] $i) 'An audio track in the video (for example a language version).') }; $l }
        Default = { param($W) (Get-Media $W 'input').Audio[0].Index } }
    $steps += @{ Id = 'mode'; Type = 'Choice'; Prompt = 'Output mode'; Help = 'Copying keeps the original quality and is instant; converting lets you choose another format.'
        Choices = { param($W) $m = Get-Media $W 'input'; @( (New-Choice 'copy' 'Copy original audio stream' 'No re-encoding: fastest, no quality loss.'), (New-Choice 'convert' 'Convert to another format' 'Choose format, codec, bitrate, sample rate and channels.') ) }
        Default = 'copy' }
    $steps += @{ Id = 'afmt'; Type = 'Choice'; Prompt = 'Output format'; Help = 'Only formats supported by your FFmpeg build are listed.'; When = $convert
        Choices = { param($W) @(Get-AvailableAudioFormats | ForEach-Object { New-Choice $_.Id $_.Label $_.Desc }) }; Default = 'mp3' }
    $steps += Get-AudioEncodeSteps -Prefix 'a' -FormatAudioFamilies $fam -When $convert -Full -OfferVbr
    $steps += Get-TimeRangeSteps -Prefix 't' -InputId 'input' -Prompt 'Extract which part?'
    $steps += Get-OutputSteps -Prefix 'out' -InputId 'input' -Suffix 'audio' -Extension {
        param($W)
        $m = Get-Media $W 'input'
        if ((Get-Answer $W 'mode') -eq 'convert') { return (Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))).Ext }
        $idx = Get-Answer $W 'stream'; $a = $m.Audio[0]; if ($null -ne $idx) { foreach ($x in $m.Audio) { if ($x.Index -eq $idx) { $a = $x } } }
        return (Get-AudioFormat (Get-CopyFormatForCodec $a.Codec)).Ext
    }
    return $steps
}

function Build-ExtractAudioJob {
    param($W)
    $info = Get-Media $W 'input'
    $idx = Get-Answer $W 'stream'; $a = $info.Audio[0]
    if ($null -ne $idx) { foreach ($x in $info.Audio) { if ($x.Index -eq $idx) { $a = $x } } }
    $out = Get-OutputFile $W
    $range = Resolve-TimeRange $W 't' 'input'
    if ((Get-Answer $W 'mode') -eq 'convert') {
        $fmt = Get-AudioFormat ([string](Get-Answer $W 'afmt' 'mp3'))
        $ae = Resolve-AudioEncode $W -Prefix 'a' -Container '' -AllowedFamilies @($fmt.Codecs) -HasAudio $true
    } else {
        $fmt = Get-AudioFormat (Get-CopyFormatForCodec $a.Codec)
        if (-not (Test-FFMuxer $fmt.Muxer)) { throw "Your FFmpeg build cannot write $($fmt.Label) files. Choose 'Convert' instead." }
        $ae = @{ None = $false; Copy = $true; Tokens = @('-c:a', 'copy'); Encoder = 'copy' }
    }
    $cmd = New-FFCommand
    [void](Add-FFInput $cmd $info.Path (Get-RangeInputOptions $range))
    Add-FFOutOpt $cmd @('-vn', '-map', "0:$($a.Index)")
    Add-FFOutOpt $cmd $ae.Tokens
    Add-FFOutOpt $cmd @('-f', $fmt.Muxer)
    Set-FFOutput $cmd $out.Path -Overwrite:$out.Overwrite
    $notes = @(); if ($out.Overwrite) { $notes += 'The existing output file will be overwritten.' }
    $rows = @(@('Input', $info.FileName), @('Track', (Get-AudioLine $a)), @('Mode', $(if ($ae.Copy) { 'Copy original stream' } else { "Convert ($($ae.Encoder))" })), @('Format', $fmt.Label), @('Range', $(if ($range.Full) { 'Entire file' } else { ('{0} + {1} s' -f (Format-Duration $range.Start), (Format-FFNumber $range.Duration 2)) })), @('Output', $out.Path))
    return New-JobObject -Title 'Extracting audio' -Summary $rows -Stages @(@{ Name = 'Extracting audio'; Arguments = (Get-FFTokens $cmd); DurationSec = $range.Duration }) -OutputPath $out.Path -EnsureDirs @($out.Dir) -Notes $notes
}

function Start-ExtractAudioWorkflow {
    Start-StandardWorkflow -Title 'Extract Audio from Video' -Description 'Save one audio stream from a video as a separate audio file.' -Icon 'Extract' -StepsFactory { Get-ExtractAudioSteps } -Build { param($W) Build-ExtractAudioJob $W }
}

Export-ModuleMember -Function Get-CopyFormatForCodec, Get-ExtractAudioSteps, Build-ExtractAudioJob, Start-ExtractAudioWorkflow
