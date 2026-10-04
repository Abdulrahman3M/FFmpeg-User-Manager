# Import-Modules.ps1 - the ONE place that lists the modules and their order (dependencies first).
Set-StrictMode -Version 2.0

function Import-AppModules {
    param([Parameter(Mandatory)][string]$Root)
    $order = @('Core\Platform', 'Core\Settings', 'Core\Log', 'Core\Process', 'TUI\Theme', 'TUI\Renderer', 'TUI\Input', 'TUI\Menu', 'TUI\Dialog', 'TUI\Prompt', 'Core\App')
    foreach ($m in $order) {
        $path = Join-Path (Join-Path $Root 'src') ($m + '.psm1')
        if (-not (Test-Path -LiteralPath $path)) { throw "Module file not found: $path" }
        Import-Module -Name $path -Force -DisableNameChecking -Global
    }
}
