# Unit tests: FFmpeg manager (detection, install, update) using injected hooks - no real system state is touched.
$realFf = Get-FFmpegPath
$realFp = Get-FFprobePath
$global:WingetCalls = New-Object System.Collections.Generic.List[string]

function New-WingetMock {
    param([hashtable]$Responses)   # key: first argument (list/upgrade/show/install) -> @{ExitCode;StdOut}
    return {
        param($argsArray, $onTick)
        $global:WingetCalls.Add(($argsArray -join ' '))
        $k = [string]$argsArray[0]
        $r = $Responses[$k]
        if (-not $r) { $r = @{ ExitCode = 0; StdOut = '' } }
        if ($onTick) { $null = & $onTick 0.1 'working' }
        return [pscustomobject]@{ Started = $true; ExitCode = $r.ExitCode; StdOut = $r.StdOut; StdErr = ''; TimedOut = $false; Cancelled = $false; Error = '' }
    }.GetNewClosure()
}
$listInstalled = "Name   Id           Version Source`n-----------------------------------`nFFmpeg Gyan.FFmpeg  7.1     winget`n"
$upgradeAvail = "Name   Id           Version Available Source`n---------------------------------------------`nFFmpeg Gyan.FFmpeg  7.1     8.0       winget`n1 upgrades available.`n"

Set-TestGroup 'FFmpeg detection'
Set-FFManagerHooks -Reset
$d = Find-FFmpegInstallation
Assert-True 'installed ffmpeg + ffprobe are detected (Ready)' ($d.Status -eq 'Ready' -and $d.Version)
Assert-True 'version string captured' ($d.Version -match '^\d|^n|^N|git')
Assert-Equal 'ffmpeg path is registered' $d.Ffmpeg (Get-FFmpegPath)
$global:RealFf = $realFf; $global:RealFp = $realFp
Set-FFManagerHooks -FindCommand { param($n) $null }
Assert-Equal 'missing ffmpeg is reported' 'Missing' (Find-FFmpegInstallation).Status
Set-FFManagerHooks -FindCommand { param($n) if ($n -eq 'ffmpeg') { $global:RealFf } else { $null } }
$d = Find-FFmpegInstallation
Assert-Equal 'ffmpeg without ffprobe is reported' 'FfprobeMissing' $d.Status
Set-FFManagerHooks -FindCommand { param($n) '/nonexistent/stale/path/' + $n }
$d = Find-FFmpegInstallation
Assert-True 'stale PATH entry is not treated as an installation' ($d.Status -eq 'Broken' -and $d.Detail -like '*stale PATH*')
Set-FFManagerHooks -Reset
$d = Find-FFmpegInstallation
Assert-Equal 'detection recovers after mocks are removed' 'Ready' $d.Status

Set-TestGroup 'FFmpeg update check (mocked winget)'
Set-FFManagerHooks -FindCommand { param($n) if ($n -eq 'ffmpeg') { $global:RealFf } elseif ($n -eq 'ffprobe') { $global:RealFp } else { $null } }
$null = Find-FFmpegInstallation
$global:WingetCalls.Clear()
Set-FFManagerHooks -Winget (New-WingetMock @{ list = @{ ExitCode = 0; StdOut = $listInstalled }; upgrade = @{ ExitCode = 0; StdOut = $upgradeAvail } })
$u = Get-FFmpegUpdateStatus
Assert-True 'update available is detected without hardcoded versions' ($u.State -eq 'UpdateAvailable' -and $u.Installed -eq '7.1' -and $u.Available -eq '8.0')
Assert-True 'update check only reads (no install/upgrade side effects beyond query)' (-not @($global:WingetCalls | Where-Object { $_ -like 'install*' }))
Set-FFManagerHooks -Winget (New-WingetMock @{ list = @{ ExitCode = 0; StdOut = $listInstalled }; upgrade = @{ ExitCode = 0; StdOut = "No available upgrade found.`nNo newer package versions are available from the configured sources.`n" } })
Assert-Equal 'no update -> UpToDate' 'UpToDate' (Get-FFmpegUpdateStatus).State
Set-FFManagerHooks -Winget (New-WingetMock @{ list = @{ ExitCode = 0; StdOut = $listInstalled }; upgrade = @{ ExitCode = -1978335189; StdOut = "No applicable update found.`n" } })
Assert-Equal 'winget "not applicable" exit code -> UpToDate' 'UpToDate' (Get-FFmpegUpdateStatus).State
Set-FFManagerHooks -Winget (New-WingetMock @{ list = @{ ExitCode = 0; StdOut = $listInstalled }; upgrade = @{ ExitCode = -1978335138; StdOut = "Failed when opening source(s); try the source reset command`n" } })
$u = Get-FFmpegUpdateStatus
Assert-True 'update check failure is non-fatal (Unknown + message)' ($u.State -eq 'Unknown' -and $u.Message.Length -gt 10)
$global:WingetCalls.Clear()
Set-FFManagerHooks -Winget (New-WingetMock @{ list = @{ ExitCode = -1978335212; StdOut = "No installed package found matching input criteria.`n" } })
$u = Get-FFmpegUpdateStatus
Assert-Equal 'manually installed FFmpeg is reported as Unmanaged' 'Unmanaged' $u.State
Assert-True 'unmanaged FFmpeg is never replaced (no install/upgrade issued)' (-not @($global:WingetCalls | Where-Object { $_ -like 'install*' -or $_ -like 'upgrade*' }))
Set-FFManagerHooks -Winget { param($a, $t) throw 'boom' }
$u = Get-FFmpegUpdateStatus
Assert-Equal 'unexpected errors in the check are swallowed (Unknown)' 'Unknown' $u.State
Set-FFManagerHooks -Reset
# hide winget but keep the real ffmpeg/ffprobe (a Windows machine or runner usually has a real winget)
Set-FFManagerHooks -FindCommand { param($n) if ($n -eq 'winget') { return $null }; $c = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { return [string]$c.Source } }
$null = Find-FFmpegInstallation
$u = Get-FFmpegUpdateStatus
Assert-True 'winget missing -> Unknown with explanation' ($u.State -eq 'Unknown' -and $u.Message -like '*winget*')
$p = ConvertFrom-WingetPackageLine "FFmpeg (Full) Gyan.FFmpeg   7.1.1-full   8.0   winget" 'Gyan.FFmpeg'
Assert-True 'package line parsing (spaces in name, 3 columns)' ($p.Found -and $p.Installed -eq '7.1.1-full' -and $p.Available -eq '8.0')

Set-TestGroup 'FFmpeg install flow (mocked winget, scripted UI)'
$global:Installed = $false
Set-FFManagerHooks -FindCommand { param($n) if (-not $global:Installed) { $null } elseif ($n -eq 'ffmpeg') { $global:RealFf } elseif ($n -eq 'ffprobe') { $global:RealFp } else { $null } }
$installMock = {
    param($argsArray, $onTick)
    $global:WingetCalls.Add(($argsArray -join ' '))
    if ($argsArray[0] -eq 'install') { $global:Installed = $true }
    return [pscustomobject]@{ Started = $true; ExitCode = 0; StdOut = 'ok'; StdErr = ''; TimedOut = $false; Cancelled = $false; Error = '' }
}
Set-FFManagerHooks -Winget $installMock
$global:WingetCalls.Clear(); $global:Installed = $false
$det = Find-FFmpegInstallation
Assert-Equal 'precondition: ffmpeg missing' 'Missing' $det.Status
$ui = Invoke-Ui { Show-FFmpegMissingFlow (Find-FFmpegInstallation) } '0101{Enter}'
Assert-Contains 'missing screen: shows the not-found message' $ui.Output 'FFmpeg was not found.'
Assert-Contains 'missing screen: offers automatic install' $ui.Output 'Install FFmpeg automatically'
Assert-Contains 'missing screen: offers exit' $ui.Output 'Exit'
Assert-True 'install: returns success after verification' ($ui.Value -eq $true) $ui.Error
Assert-True 'install: package verified (show) before installing' (@($global:WingetCalls | Where-Object { $_ -like 'show --id Gyan.FFmpeg --exact*' }).Count -eq 1)
Assert-True 'install: exact package id used, agreements accepted' (@($global:WingetCalls | Where-Object { $_ -like 'install --id Gyan.FFmpeg --exact*--accept-package-agreements*' }).Count -eq 1)
Assert-Equal 'install: ffmpeg re-detected and registered' $realFf (Get-FFmpegPath)
Assert-Contains 'install: success is reported' $ui.Output 'FFmpeg installed'
# user declines
$global:Installed = $false; $global:WingetCalls.Clear()
$ui = Invoke-Ui { Show-FFmpegMissingFlow (Find-FFmpegInstallation) } '03'
Assert-True 'exit from the missing screen returns $false (no menu entered)' ($ui.Value -eq $false)
Assert-Equal 'nothing is installed unless the user chooses Install' 0 $global:WingetCalls.Count
# declining the confirmation
$ui = Invoke-Ui { Show-FFmpegMissingFlow (Find-FFmpegInstallation) } '0102'
Assert-True 'declining the install confirmation does not call winget install' (-not @($global:WingetCalls | Where-Object { $_ -like 'install*' }))
# installation failure
$failMock = { param($argsArray, $onTick) $global:WingetCalls.Add(($argsArray -join ' ')); $code = 0; if ($argsArray[0] -eq 'install') { $code = -1978335216 }; return [pscustomobject]@{ Started = $true; ExitCode = $code; StdOut = 'installer failed: access is denied'; StdErr = ''; TimedOut = $false; Cancelled = $false; Error = '' } }
Set-FFManagerHooks -Winget $failMock
$global:WingetCalls.Clear(); $global:Installed = $false
$ui = Invoke-Ui { Show-FFmpegMissingFlow (Find-FFmpegInstallation) } '010103'
Assert-True 'install failure: does not claim success' ($ui.Value -eq $false -and $ui.Output -like '*could not be completed*')
Assert-Contains 'install failure: explains elevation problem' $ui.Output 'administrator'
Assert-Contains 'install failure: offers Retry and Exit' $ui.Output 'Retry'
$ui = Invoke-Ui { Show-FFmpegMissingFlow (Find-FFmpegInstallation) } '010101{Esc}03'
Assert-Contains 'install failure: technical details view is available' $ui.Output 'winget output'
# winget unavailable
Set-FFManagerHooks -FindCommand { param($n) $null }
Set-FFManagerHooks -Reset
Set-FFManagerHooks -FindCommand { param($n) $null }
$ui = Invoke-Ui { Show-FFmpegMissingFlow (Find-FFmpegInstallation) } '02'
Assert-Contains 'winget missing: exact reason is shown' $ui.Output 'winget'
Assert-NotContains 'winget missing: no install action is offered' $ui.Output 'Install FFmpeg automatically'
# installation reported OK but PATH stale
Set-FFManagerHooks -Reset
Set-FFManagerHooks -FindCommand { param($n) $null }
Set-FFManagerHooks -Winget { param($a, $t) [pscustomobject]@{ Started = $true; ExitCode = 0; StdOut = 'ok'; StdErr = ''; TimedOut = $false; Cancelled = $false; Error = '' } }
$r = Install-FFmpegViaWinget
Assert-True 'winget success but tools not found -> not reported as success' ((-not $r.Ok) -and $r.Message -like '*new terminal*')

Set-TestGroup 'FFmpeg update flow (mocked winget, scripted UI)'
Set-FFManagerHooks -Reset
$global:Upgraded = $false
Set-FFManagerHooks -FindCommand { param($n) if ($n -eq 'ffmpeg') { $global:RealFf } elseif ($n -eq 'ffprobe') { $global:RealFp } else { $null } }
$null = Find-FFmpegInstallation
$updMock = { param($argsArray, $onTick)
    $global:WingetCalls.Add(($argsArray -join ' '))
    $out = ''
    if ($argsArray[0] -eq 'list') { $out = "FFmpeg Gyan.FFmpeg 7.1 winget" }
    elseif ($argsArray[0] -eq 'upgrade') { if ($global:Upgraded) { $out = 'No available upgrade found.' } else { $out = "FFmpeg Gyan.FFmpeg 7.1 8.0 winget"; if ($argsArray -contains '--accept-package-agreements') { $global:Upgraded = $true; $out = 'Successfully installed' } } }
    return [pscustomobject]@{ Started = $true; ExitCode = 0; StdOut = $out; StdErr = ''; TimedOut = $false; Cancelled = $false; Error = '' } }
Set-FFManagerHooks -Winget $updMock
$global:WingetCalls.Clear(); $global:Upgraded = $false
$ui = Invoke-Ui { Invoke-UpdateFlow } '01{Enter}'
Assert-Contains 'update prompt shows the update-available title' $ui.Output 'FFmpeg update available'
Assert-Contains 'update prompt shows installed/available versions' $ui.Output 'Installed: 7.1'
Assert-Contains 'update prompt offers Update and Continue' $ui.Output 'Continue without updating'
Assert-True 'choosing Update runs winget upgrade with the exact id' (@($global:WingetCalls | Where-Object { $_ -like 'upgrade --id Gyan.FFmpeg --exact*--accept-package-agreements*' }).Count -eq 1)
Assert-Contains 'update result shows the verified version' $ui.Output 'FFmpeg updated'
$global:WingetCalls.Clear(); $global:Upgraded = $false
$ui = Invoke-Ui { Invoke-UpdateFlow } '02'
Assert-True 'choosing Continue does not run any upgrade' (-not @($global:WingetCalls | Where-Object { $_ -like 'upgrade*--accept-package-agreements*' }))
Set-FFManagerHooks -Winget { param($a, $t) [pscustomobject]@{ Started = $true; ExitCode = -1978335138; StdOut = 'network error'; StdErr = ''; TimedOut = $false; Cancelled = $false; Error = '' } }
$ui = Invoke-Ui { Invoke-UpdateFlow } ''
Assert-True 'update-check failure at startup needs no key press (non-blocking)' ($ui.Error -eq '')
Set-FFManagerHooks -Reset
$null = Find-FFmpegInstallation
