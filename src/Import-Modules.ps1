# Import-Modules.ps1 - safe, ordered module loader shared by the launcher and the tests.
# Modules are imported into the global session state so their exported functions can call each other.
function Import-FFTuiModules {
    param([Parameter(Mandatory)][string]$Root)
    $order = @(
        'Core\Environment', 'Core\Paths', 'Core\Validation', 'Core\ProcessRunner',
        'TUI\Theme', 'TUI\Renderer', 'TUI\Input', 'TUI\Menu', 'TUI\Dialog', 'TUI\ProgressView', 'TUI\Wizard',
        'FFmpeg\FFmpegManager', 'FFmpeg\FFmpegCapabilities', 'FFmpeg\MediaProbe', 'FFmpeg\FFmpegCommandBuilder', 'FFmpeg\FFmpegProgress',
        'Workflows\WorkflowCommon',
        'Workflows\ConvertVideo', 'Workflows\ConvertAudio', 'Workflows\ExtractAudio', 'Workflows\TrimMedia', 'Workflows\MergeMedia',
        'Workflows\CompressMedia', 'Workflows\ResizeVideo', 'Workflows\VideoToGif', 'Workflows\ExtractFrames',
        'Workflows\AudioTools', 'Workflows\SubtitleTools', 'Workflows\FrameRate', 'Workflows\Filters', 'Workflows\TransformVideo',
        'Workflows\OverlayTools', 'Workflows\PlaybackSpeed', 'Workflows\StreamingHls', 'Workflows\MediaInfo',
        'Core\App'
    )
    foreach ($m in $order) {
        $p = Join-Path (Join-Path $Root 'src') (($m -replace '\\', [string][System.IO.Path]::DirectorySeparatorChar) + '.psm1')
        if (Test-Path -LiteralPath $p) {
            Import-Module -Name $p -Force -DisableNameChecking -Global -ErrorAction Stop
        }
    }
}
