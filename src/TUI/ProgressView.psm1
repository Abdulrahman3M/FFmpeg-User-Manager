# ProgressView.psm1 - progress / spinner screens for jobs, installs and scans.
Set-StrictMode -Version 2.0

$script:SpinnerAscii = @('|', '/', '-', '\')
$script:SpinnerUni = @([string][char]0x280B, [string][char]0x2819, [string][char]0x2839, [string][char]0x2838, [string][char]0x283C, [string][char]0x2834, [string][char]0x2826, [string][char]0x2827, [string][char]0x2807, [string][char]0x280F)

function Get-SpinnerFrame {
    param([int]$Tick)
    if ((Get-BoxChars).H -ne '-') { return $script:SpinnerUni[$Tick % $script:SpinnerUni.Count] }
    return $script:SpinnerAscii[$Tick % $script:SpinnerAscii.Count]
}

function Format-ClockTime {
    param($Seconds)
    if ($null -eq $Seconds) { return '--:--:--' }
    return (Format-Duration $Seconds)
}

function Show-JobProgress {
    # One frame of the job progress view. Percent = $null shows a spinner and elapsed time (never a fake percentage).
    param(
        [string]$Title = 'Processing',
        [string]$StageText = '',
        $Percent = $null,
        $OutTime = $null, $TotalSec = $null, $Speed = 0.0,
        [TimeSpan]$Elapsed = [TimeSpan]::Zero,
        [int]$Tick = 0,
        [string[]]$ExtraLines = @(),
        [string]$Status = 'Encoding'
    )
    $w = Get-UiWidth
    Hide-Cursor
    Start-Frame
    Write-UiSegments @(, @($Title, 'Title'))
    if ($StageText) { Write-UiSegments @(, @($StageText, 'DimText')) }
    Write-UiBlank
    if ($null -ne $Percent) {
        $barW = [math]::Min(40, $w - 10)
        $parts = Format-ProgressBar -Percent ([int]$Percent) -Width $barW
        Write-UiSegments @(@(' ', 'NormalText'), @($parts[0], 'PrimaryAccent'), @($parts[1], 'Muted'), @(('  {0,3}%' -f [int]$Percent), 'Title'))
    } else {
        Write-UiSegments @(@(' ', 'NormalText'), @((Get-SpinnerFrame $Tick), 'PrimaryAccent'), @('  Working... (total duration unknown)', 'DimText'))
    }
    Write-UiBlank
    $rows = @()
    if ($null -ne $TotalSec -and $null -ne $OutTime) { $rows += , @('Time', ((Format-ClockTime $OutTime) + ' / ' + (Format-ClockTime $TotalSec))) }
    $rows += , @('Elapsed', (Format-ClockTime $Elapsed.TotalSeconds))
    if ($Speed -gt 0) { $rows += , @('Speed', ('{0:0.0#}x' -f $Speed)) }
    $rows += , @('Status', $Status)
    Write-KeyValueTable -Rows $rows -LabelWidth 9 -Indent 1
    foreach ($l in $ExtraLines) { Write-Ui -Text (' ' + (Limit-Text $l ($w - 2))) -Role DimText }
    Write-KeyHints @(@('Q', 'Cancel job'))
    Stop-Frame
}

function Show-BusyScreen {
    # Static "please wait" frame used for short blocking work (scans, update checks).
    param([string]$Title, [string]$Message = '', [int]$Tick = 0)
    Hide-Cursor
    Start-Frame
    Write-Header
    Write-UiBlank
    Write-UiSegments @(@(((Get-SpinnerFrame $Tick) + ' '), 'PrimaryAccent'), @($Title, 'Title'))
    if ($Message) { Write-Ui -Text ('  ' + $Message) -Role DimText }
    Stop-Frame
}

Export-ModuleMember -Function Get-SpinnerFrame, Show-JobProgress, Show-BusyScreen
