# Application-level tests: launcher, startup screens, terminal state, ANSI / non-ANSI, main menu integration.
$root = Get-TestRoot
$W = Get-TestWork
$launcher = Join-Path $root 'Start-FFmpegTUI.ps1'
$hostExe = (Get-Process -Id $PID).Path
$ESC = [string][char]27

function Invoke-Launcher {
    # Runs the launcher in a child PowerShell process (same edition as the test host) and returns stdout/stderr/exit code.
    param([string[]]$LauncherArgs, [hashtable]$Env = @{}, [int]$Timeout = 120)
    $saved = @{}
    foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
    try { return (Invoke-ExternalCapture -FilePath $hostExe -Arguments (@('-NoProfile', '-NonInteractive', '-File', $launcher) + $LauncherArgs) -TimeoutSec $Timeout) }
    finally { foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) } }
}

Set-TestGroup 'Launcher: startup and exit'
$r = Invoke-Launcher @('-SkipUpdateCheck', '-ScriptedInput', '29')
Assert-Equal 'starts, shows the main menu and exits with code 0' 0 $r.ExitCode
Assert-Contains 'main menu was rendered' $r.StdOut 'Convert Video Format'
Assert-Contains 'header shows the product name and canonical version' $r.StdOut ('FFmpeg User Manager v' + (Get-Content -LiteralPath (Join-Path $root 'VERSION') -TotalCount 1).Trim())
$r = Invoke-Launcher @('-SkipUpdateCheck')
Assert-Equal 'non-interactive (redirected) input is refused with exit code 2' 2 $r.ExitCode
Assert-Contains 'non-interactive refusal explains why' $r.StdOut 'interactive console'
Assert-True 'non-interactive refusal is not a crash (no stack trace)' (-not $r.StdOut.Contains('at <ScriptBlock>') -and -not $r.StdErr.Contains('at <ScriptBlock>'))

Set-TestGroup 'Terminal: ANSI mode and restoration'
$r = Invoke-Launcher @('-SkipUpdateCheck', '-ScriptedInput', '29') @{ FFTUI_FORCE_ANSI = '1'; FFTUI_UNICODE = '1'; FFTUI_ICONS = 'emoji' }
Assert-Contains 'ANSI: color escape sequences are emitted' $r.StdOut ($ESC + '[')
Assert-Contains 'ANSI: alternate screen entered (scrollback preserved)' $r.StdOut ($ESC + '[?1049h')
Assert-Contains 'ANSI: alternate screen left on exit' $r.StdOut ($ESC + '[?1049l')
Assert-Contains 'ANSI: cursor shown again on exit' $r.StdOut ($ESC + '[?25h')
Assert-Contains 'ANSI: colors reset on exit' $r.StdOut ($ESC + '[0m')
Assert-True 'ANSI: cursor is restored AFTER the last screen was drawn' ($r.StdOut.LastIndexOf($ESC + '[?25h') -gt $r.StdOut.IndexOf('Convert Video Format'))
Assert-Contains 'ANSI: dim (bright black) is used for secondary descriptions' $r.StdOut ($ESC + '[90m')
Assert-Contains 'Unicode icons render in UTF-8 terminals' $r.StdOut ([string][char]::ConvertFromUtf32(0x1F3AC))
$r = Invoke-Launcher @('-SkipUpdateCheck', '-ScriptedInput', '29') @{ FFTUI_NO_ANSI = '1'; FFTUI_ASCII = '1'; NO_COLOR = '1' }
Assert-Equal 'non-ANSI: exits normally' 0 $r.ExitCode
Assert-True 'non-ANSI: no ANSI escape sequences at all' (-not $r.StdOut.Contains($ESC + '[?1049') -and -not $r.StdOut.Contains($ESC + '[90m') -and -not $r.StdOut.Contains($ESC + '[96m'))
Assert-Contains 'non-ANSI: ASCII icon markers keep the menu readable' $r.StdOut '[VIDEO]'
Assert-True 'non-ANSI: menu is still fully usable (items shown, scroll indicator when the window is short)' ($r.StdOut.Contains('Convert Video Format') -and $r.StdOut.Contains('more'))
$r = Invoke-Launcher @('-SkipUpdateCheck', '-ScriptedInput', 'zz') @{ FFTUI_FORCE_ANSI = '1' }
Assert-Equal 'unhandled failure (script ends inside the menu) exits with code 1' 1 $r.ExitCode
Assert-Contains 'failure message is shown to the user' $r.StdOut 'unexpected error'
Assert-True 'terminal is restored after a failure (cursor shown, alternate screen left)' ($r.StdOut.Contains($ESC + '[?25h') -and $r.StdOut.Contains($ESC + '[?1049l'))
$i1 = $r.StdOut.LastIndexOf($ESC + '[?1049l'); $i2 = $r.StdOut.IndexOf('unexpected error')
Assert-True 'the error message is printed after leaving the alternate screen (stays visible)' ($i1 -ge 0 -and $i2 -gt $i1)

Set-TestGroup 'Startup: FFmpeg missing / incomplete (real launcher, real PATH manipulation)'
$emptyBin = Join-Path $W 'emptybin'; [void](New-Item -ItemType Directory -Path $emptyBin -Force)
$origPath = $env:PATH
$r = Invoke-Launcher @('-SkipUpdateCheck', '-ScriptedInput', '02') @{ PATH = $emptyBin }
Assert-Contains 'missing FFmpeg: the not-found screen is shown' $r.StdOut 'FFmpeg was not found.'
Assert-Contains 'missing FFmpeg: exit is offered' $r.StdOut 'Exit'
Assert-NotContains 'missing FFmpeg: the main menu is NOT entered' $r.StdOut 'Convert Video Format'
Assert-Equal 'missing FFmpeg: choosing Exit ends cleanly' 0 $r.ExitCode
Assert-Contains 'missing FFmpeg without winget: manual help is shown instead of a silent install' $r.StdOut 'winget'
$onlyFfmpeg = Join-Path $W 'ffonlybin'; [void](New-Item -ItemType Directory -Path $onlyFfmpeg -Force)
try {
    if (Test-IsWindows) {
        # a package-manager shim (for example Chocolatey's) only works next to its install folder: copy the real executable instead
        $realFf = (Get-FFmpegPath)
        if ($realFf -like '*\chocolatey\bin\*' -and $env:ChocolateyInstall) {
            $found = Get-ChildItem -LiteralPath (Join-Path $env:ChocolateyInstall 'lib') -Recurse -Filter 'ffmpeg.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $realFf = $found.FullName }
        }
        Copy-Item -LiteralPath $realFf -Destination (Join-Path $onlyFfmpeg 'ffmpeg.exe')
        $runtimeDir = Split-Path -Parent $realFf
        foreach ($dll in (Get-ChildItem -LiteralPath $runtimeDir -Filter '*.dll' -File -ErrorAction SilentlyContinue)) {
            [void](New-Item -ItemType HardLink -Path (Join-Path $onlyFfmpeg $dll.Name) -Target $dll.FullName -ErrorAction Stop)
        }
    }
    else { New-Item -ItemType SymbolicLink -Path (Join-Path $onlyFfmpeg 'ffmpeg') -Target (Get-FFmpegPath) | Out-Null }
    $r = Invoke-Launcher @('-SkipUpdateCheck', '-ScriptedInput', '02') @{ PATH = $onlyFfmpeg }
    Assert-Contains 'ffmpeg without ffprobe: the ffprobe-missing screen is shown' $r.StdOut 'ffprobe is missing.'
    Assert-NotContains 'ffmpeg without ffprobe: the main menu is NOT entered' $r.StdOut 'Convert Video Format'
} catch { Skip-Test 'ffmpeg without ffprobe (real PATH)' "could not prepare the PATH sandbox: $($_.Exception.Message)" }
$staleBin = Join-Path $W 'stalebin'; [void](New-Item -ItemType Directory -Path $staleBin -Force)
try {
    $fake = Join-Path $staleBin 'ffmpeg'; [System.IO.File]::WriteAllText($fake, "#!/bin/sh`nexit 3`n")
    if (-not (Test-IsWindows)) { $null = Invoke-ExternalCapture -FilePath 'chmod' -Arguments @('+x', $fake) }
    Copy-Item -LiteralPath $fake -Destination (Join-Path $staleBin 'ffprobe')
    $r = Invoke-Launcher @('-SkipUpdateCheck', '-ScriptedInput', '02') @{ PATH = $staleBin }
    Assert-True 'a broken/stale ffmpeg on PATH is not accepted as an installation' ($r.StdOut.Contains('cannot be started') -or $r.StdOut.Contains('FFmpeg was not found.'))
    Assert-NotContains 'stale PATH entry: the main menu is NOT entered' $r.StdOut 'Convert Video Format'
} catch { Skip-Test 'stale PATH entry (real PATH)' "could not prepare the PATH sandbox: $($_.Exception.Message)" }

Set-TestGroup 'Main menu integration (scripted, in-process)'
$MM = '01-29 Type a number'
$vid = New-Fixture 'app video.mp4' @('-f', 'lavfi', '-i', 'testsrc=duration=2:size=320x240:rate=25', '-f', 'lavfi', '-i', 'sine=duration=2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-shortest')
$ui = Invoke-Flow { Start-MainMenu } @((New-ScreenRule $MM '08' 1), (New-Rule 'Input video' '{Esc}'), (New-ScreenRule $MM '29')) -Height 60
Assert-Contains 'shortcut 8 opens the Video to GIF wizard' $ui.Output 'Video to GIF'
Assert-True 'Escape returns from a wizard to the main menu, Q then exits' ($ui.Error -eq '')
$ui = Invoke-Flow { Start-MainMenu } @((New-ScreenRule $MM '27' 1), (New-ScreenRule 'FFmpeg Status / Settings' '{#Back}' 1), (New-ScreenRule $MM '29')) -Height 60
Assert-True '27 opens the status screen, Back returns to the menu' ($ui.Output.Contains('Re-scan capabilities') -and $ui.Error -eq '')
$ui = Invoke-Flow { Start-MainMenu } @((New-ScreenRule $MM '17' 1), (New-ScreenRule 'Work with supported streams' '{Esc}' 1), (New-ScreenRule $MM '29')) -Height 60
Assert-True '17 opens the Streaming / HLS submenu, Esc returns' ($ui.Output.Contains('Create HLS Output from Media File') -and $ui.Error -eq '')
$ui = Invoke-Flow { Start-MainMenu } @((New-ScreenRule $MM '11' 1), (New-ScreenRule 'Extract, add, remove, copy or burn' '{Esc}' 1), (New-ScreenRule $MM '29')) -Height 60
Assert-True '11 opens Subtitle Tools' ($ui.Output.Contains('Add / Mux Subtitle') -and $ui.Error -eq '')
$ui = Invoke-Flow { Start-MainMenu } @((New-ScreenRule $MM '18' 1), (New-Rule 'File to inspect' "$vid{Enter}" 1), (New-ScreenRule 'More actions' '{Esc}' 1), (New-ScreenRule $MM '29')) -Height 60
Assert-True '18 inspects a file and returns to the menu' ($ui.Output.Contains('H.264') -and $ui.Error -eq '')
$ui = Invoke-Flow { Start-MainMenu } @((New-ScreenRule $MM '{Down}{Down}{Enter}' 1), (New-Rule 'Input video' '{Esc}' 1), (New-ScreenRule $MM '29')) -Height 60
Assert-Contains 'arrow keys + Enter open the highlighted item (third: Extract Audio from Video)' $ui.Output 'Save one audio stream from a video as a separate audio file.'
$ui = Invoke-Flow { Start-MainMenu } @((New-ScreenRule $MM '01' 1), (New-Rule 'Input video' "$vid{Enter}" 1), (New-ScreenRule 'Completed successfully' '{#Run again}' 1), (New-Rule 'Input video' '{Esc}' 1), (New-ScreenRule $MM '29')) -Height 60
Assert-True 'a workflow can be repeated with "Run again" and the menu is reachable afterwards' ($ui.Error -eq '')
# unexpected exceptions inside a workflow never take the app down
function global:Start-GifWorkflow { throw 'simulated failure inside a workflow' }
$ui = Invoke-Flow { Start-MainMenu } @((New-ScreenRule $MM '08' 1), (New-ScreenRule 'Something went wrong' '{#Show technical}' 1), (New-ScreenRule 'Technical details' '{Esc}' 1), (New-ScreenRule 'Something went wrong' '{#Back to the main}' 1), (New-ScreenRule $MM '29')) -Height 60
Import-Module -Name (Join-Path (Join-Path (Join-Path (Get-TestRoot) 'src') 'Workflows') 'VideoToGif.psm1') -Force -DisableNameChecking -Global
Assert-Contains 'an unexpected error inside a workflow is contained and explained' $ui.Output 'Something went wrong'
Assert-Contains 'the error text is available under technical details' $ui.Output 'simulated failure inside a workflow'
Assert-True 'the app keeps running and exits normally afterwards' ($ui.Error -eq '')
Assert-True 'the workflow override was removed again' ((Get-Command Start-GifWorkflow).ModuleName -eq 'VideoToGif')
Set-FFManagerHooks -Reset
$null = Find-FFmpegInstallation
