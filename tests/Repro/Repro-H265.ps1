<#
 Isolated reproduction of the "H.265 with a chosen quality level" wizard problem (not part of the normal suite).
 Prints: environment, the encoder lists, the exact question/option/answer sequence of the wizard for
 (A) the answers the OLD test sent (codec chosen by position computed WITHOUT hardware encoders) and
 (B) the answers of the fixed test (codec chosen by its label), plus the final FFmpeg command and ffprobe codec.
 Usage: powershell -NoProfile -File tests\Repro\Repro-H265.ps1   (or pwsh)
#>
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'TestHelpers.ps1')
Initialize-TestEnvironment
try {
    $W = Get-TestWork
    Write-Host ("PowerShell {0}" -f $PSVersionTable.PSVersion)
    Write-Host ("OS: {0}" -f [System.Environment]::OSVersion.VersionString)
    Write-Host ("ffmpeg: {0}" -f (Get-FFmpegPath))
    Write-Host ((Get-FFmpegInfo).Version)
    $fam = @('h264', 'hevc', 'av1', 'mpeg4', 'vp9')
    $noHw = @(Get-VideoEncoderChoices -AllowedFamilies $fam | ForEach-Object { $_.Encoder })
    $mp4 = @((Get-VideoContainer 'mp4').Video)
    $withHw = @(Get-VideoEncoderChoices -AllowedFamilies $mp4 -IncludeHardware | ForEach-Object { $_.Encoder })
    Write-Host ('LIST used by the OLD test (no hardware, 5 families)     : ' + ($noHw -join ', '))
    Write-Host ('LIST shown by the app for MP4 (hardware included)       : ' + ($withHw -join ', '))
    $oldKey = '{0:00}' -f (1 + 1 + 1 + [array]::IndexOf($noHw, 'libx265'))
    Write-Host ('OLD test key for libx265 = ' + $oldKey + '  -> in the app that number is option #' + $oldKey + ' = ' + $(if ($withHw.Count -ge ([int]$oldKey - 2)) { '(Auto, Copy, then) ' + (@('auto','copy') + $withHw)[[int]$oldKey - 1] } else { '?' }))
    $vid = New-Fixture 'w video.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=3:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
    $DONE = New-ScreenRule 'Completed successfully' '{#Main menu}'
    $FAIL = New-ScreenRule 'Processing failed\.' '{#Back}'
    foreach ($case in @(@{ N = 'A: OLD answers (codec by computed position ' + $oldKey + ')'; Codec = $oldKey }, @{ N = 'B: FIXED answers (codec by label [libx265])'; Codec = '{#[libx265]}' })) {
        Write-Host ("`n================ Case " + $case.N + ' ================')
        $trace = New-Object 'System.Collections.Generic.List[string]'
        $out = Join-Path $W ('repro_' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.mp4')
        $ui = Invoke-Flow { Start-ConvertVideoWorkflow } @((New-Rule 'Input video' "$vid{Enter}"), (New-Rule 'Video codec' $case.Codec), (New-Rule 'Quality mode' '02'), (New-Rule 'Quality level' '01'), (New-Rule 'Encoding speed / preset' '01'), (New-Rule 'Output file name' ('{Clear}' + [System.IO.Path]::GetFileName($out) + '{Enter}')), (New-ScreenRule '── Summary' '{#View FFmpeg command}{Esc}{Enter}' 1), $DONE, $FAIL) -Trace $trace -MaxCalls 60
        $i = 0; foreach ($t in $trace) { $i++; Write-Host ('  step {0,2}: {1}' -f $i, $t) }
        Write-Host ('  completed successfully : ' + $ui.Output.Contains('Completed successfully'))
        Write-Host ('  error                  : ' + $(if ($ui.Error) { ($ui.Error -split "`n")[0] } else { '(none)' }))
        $mc = [regex]::Match((Get-FlatText $ui.Output), 'ffmpeg(\.exe)?"? .{0,600}?-c:v \S+ .{0,200}')
        $cmdLine = $mc.Value
        Write-Host ('  FFmpeg command lines   : ' + $(if ($cmdLine) { $cmdLine } else { '(never reached)' }))
        if (Test-Path -LiteralPath $out) { Write-Host ('  output codec (ffprobe) : ' + (Get-StreamOf (Get-ProbeJson $out) 'video')[0].codec_name) } else { Write-Host '  output file            : (not created)' }
    }
} finally { Remove-TestEnvironment }
