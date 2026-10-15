param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Marker)

$ErrorActionPreference = 'Stop'
. (Join-Path (Join-Path $Root 'src') 'Import-Modules.ps1')
Import-FFTuiModules -Root $Root
Set-AppRoot $Root
$installation = Find-FFmpegInstallation
if ($installation.Status -ne 'Ready') { exit 6 }

$baselineIds = @([System.Diagnostics.Process]::GetProcessesByName('ffmpeg') | ForEach-Object { $_.Id })
$markerPath = $Marker
$onTick = {
    param($State)
    if (-not (Test-Path -LiteralPath $markerPath)) {
        $children = @([System.Diagnostics.Process]::GetProcessesByName('ffmpeg') | Where-Object { $baselineIds -notcontains $_.Id })
        if ($children.Count -gt 0) { [System.IO.File]::WriteAllText($markerPath, ('{0}|{1}' -f $PID, $children[0].Id)) }
    }
    return $false
}.GetNewClosure()

$stage = Invoke-FFmpegStage -FfmpegPath (Get-FFmpegPath) -Arguments @('-nostdin', '-re', '-f', 'lavfi', '-i', 'testsrc=size=64x64:rate=10', '-t', '120', '-f', 'null', '-') -OnTick $onTick
if (-not $stage.Started -or $stage.ExitCode -ne 0) { exit 7 }
