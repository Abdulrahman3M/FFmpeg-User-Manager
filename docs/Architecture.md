# Architecture

## Layers

```
Start-FFmpegTUI.ps1 --> src/Import-Modules.ps1 --> Core/App.psm1 (Start-FFmpegTuiApp)
                                                     |
        +--------------------+-----------------------+-------------------+
        | TUI (screens)      | FFmpeg (engine)       | Workflows          |
        | Theme  Renderer    | FFmpegManager         | WorkflowCommon     |
        | Input  Menu Dialog | FFmpegCapabilities    | ConvertVideo ...   |
        | Wizard ProgressView| MediaProbe            | (18 workflow files)|
        |                    | FFmpegCommandBuilder  |                    |
        |                    | FFmpegProgress        |                    |
        +--------------------+ Core: Environment Paths Validation ProcessRunner
```

`FFmpeg-User-Manager.bat` (repository root) is a thin Windows launcher: it finds `Start-FFmpegTUI.ps1`, prefers `pwsh.exe`, falls back to `powershell.exe`, and forwards arguments and the exit code. The application version comes from the root `VERSION` file (`Get-AppVersion`).

All modules are imported into the global session state by `Import-FFTuiModules` (ordered, fail-fast), so exported
functions can call each other. Module-private state uses `$script:` variables.

## Core

| Module | Responsibility |
|---|---|
| `App.psm1` | Startup sequence, FFmpeg missing/install/update screens, capability scan, main menu, status screen, top-level error containment, terminal cleanup. |
| `Environment.psm1` | Runtime info (5.1 vs 7), interactive/ANSI/Unicode detection, terminal size, `config/defaults.json` loading. `Test-IsWindows` guards `$IsWindows` (absent in 5.1). |
| `Paths.psm1` | Path cleaning (`"..."`, `'...'`, `& '...'`), resolution, input-file checks (missing, folder, empty, locked, denied), file-name validation (reserved names, illegal chars), size/duration formatting, open-folder, optional native picker. |
| `Validation.psm1` | Parsers returning `{Ok, Value, Error}`: timestamps, integers, decimals, bitrates, frame rates, colors. Never throw for user mistakes. |
| `ProcessRunner.psm1` | Argument quoting per `CommandLineToArgvW` (works on 5.1, which has no `ArgumentList`), capture and streaming child-process helpers. No shell is ever involved. |

## TUI

* **Theme** - the only place with color values. Semantic roles: `PrimaryAccent SecondaryAccent Title NormalText DimText
  Success Warning Error Border Selected Muted`, each with an ANSI code and a legacy `ConsoleColor`. Icons have Unicode and
  ASCII variants (`[VIDEO]`, `[GIF]`, ...).
* **Renderer** - all output. Three modes: ANSI (cursor-home redraw, alternate screen), legacy (`Clear-Host` + `Write-Host` colors)
  and a memory buffer used by tests. Provides header, rules, key/value panels, key hints, progress bar, width-aware truncation and
  compact layout (< 72 columns).
* **Input** - one key reader for the real console or a scripted queue/provider (automation hook), plus the single-line editor
  (`Read-TuiLine`: Left/Right/Home/End/Backspace/Delete, `Esc` = Back, `Tab` = Browse, `Ctrl+U` = clear).
* **Menu** - reusable list: arrows, digits, letters, disabled items with a reason, scrolling viewport, description under each
  item (or only for the selected item when the window is short). Item hotkeys take precedence over Back/Quit (so main-menu `B` = Subtitle Tools).
* **Dialog** - notices, yes/no confirmations, scrollable text viewer.
* **ProgressView** - job progress (percentage only when the duration is known, otherwise spinner + elapsed time).
* **Wizard** - see below.

### Wizard system

Steps are data (hashtables). `Invoke-Wizard -Steps ... -Build {...}` renders them, keeps answers in `$W.Answers`, supports Back
(answers are kept), conditional steps (`When`), jumps (`$W.Goto`), info panels (`Set-WizardPanel`), a final summary and `[V]` command view.

| Field | Meaning |
|---|---|
| `Id`, `Type`, `Prompt`, `Help`, `Example`, `Default` | Identification and text. `Default`/`Choices` may be scriptblocks `param($W)`. |
| `Type` | `File`, `Files` (ordered list), `Directory`, `Text`, `Integer`, `Decimal`, `Timestamp`, `Bitrate`, `FrameRate`, `Color`, `Resolution`, `YesNo`, `Choice`, `MultiChoice`, `Info`, `Custom`. `Optional = $true` allows empty. |
| `Choices` | `@{Value; Label; Desc; Enabled; Reason}`; `AllowCustom = @{Type; Prompt; Min; Max; ...}` adds a "Custom..." entry that opens a validated text question. |
| `Validate` | `param($value,$W)` -> `$null` or an error message. |
| `When` | Step is skipped (and its stale answer dropped) when false. |
| `OnAnswer` | Side effects after acceptance, e.g. probing or `$W.Goto = 'stepId'`. |

The `Build` scriptblock turns answers into a **job**: `Summary` rows, `Stages` (each with `Arguments` or a `Factory`, `DurationSec`),
`OutputPath`, `OutputKind`, `TempFiles`, notes. `Start-StandardWorkflow` runs wizard -> `Invoke-FFJob` -> repeat on "Run again".

**Scoping rule:** step scriptblocks run later inside the Wizard module. A block that reads a local variable of the function that
created it must end with `.GetNewClosure()` (enforced by a static test). Never name a local `$w`: variable names are
case-insensitive and it would overwrite the wizard state `$W`.

## FFmpeg engine

* **FFmpegManager** - detect (`Get-Command` + real `-version` run), winget install/upgrade/list parsing (locale independent: rows are found by
  package id), PATH refresh, update status (`UpdateAvailable | UpToDate | Unmanaged | Unknown`). External calls are injectable
  (`Set-FFManagerHooks`) so tests never touch the system.
* **FFmpegCapabilities** - runs `-encoders -decoders -muxers -demuxers -filters -protocols -hwaccels -codecs` once per session, parses into sets
  and answers `Test-FFEncoder/Muxer/Filter/Protocol/HwAccel`. Friendly presets (H.264, HEVC, AV1, VP9, AAC, Opus, ...) map to candidate
  encoders and are offered only if present; hardware encoders additionally need a successful 1-frame test encode.
* **MediaProbe** - `ffprobe -print_format json` -> normalized model (container, duration, bitrate, size, video/audio/subtitle streams, fps, VFR flag,
  rotation, language/title, attached pictures separated). Friendly summaries; raw JSON is never shown.
* **FFmpegCommandBuilder** - the only place command lines are assembled: token lists, `-n`/`-y` policy, filter escaping
  (`ConvertTo-FFFilterValue`, two-level), `atempo` chains, scale filters, per-encoder quality/preset mapping (a table of *how to drive* encoders,
  not of what exists), container catalog, target-size bitrate calculation.
* **FFmpegProgress** - runs one stage as a child process with `-progress pipe:1`, parses time/speed/size, supports cooperative cancel
  (`q` on stdin, then kill), collects stderr for the details view.
* **WorkflowCommon** - shared steps (input+probe, output folder/name/collision, container, video/audio encode, time range, resolution, frame rate),
  shared job builders (`New-VideoProcessJob`, `New-AudioProcessJob`) and the job runner/result screens.

## Data flow of one job

`workflow steps` -> answers -> `Build` (validates combinations, builds tokens) -> summary -> `Invoke-FFJob` (creates folders after confirmation, runs stages,
progress, cancel) -> success screen / failure screen (short reason + technical details) -> temp-file cleanup.

## Automation hooks (tests)

`Start-FFmpegTUI.ps1 -ScriptedInput '1{Enter}' -BufferOutput` feeds keys and renders into a buffer;
`Set-TuiScriptedProvider` supplies keys on demand from the current screen text. Tokens: `{Enter} {Esc} {Up} {Down} {Left} {Right} {Home} {End} {Del} {BS} {Tab} {PgUp} {PgDn} {CtrlC} {Clear}`.
Environment switches: `FFTUI_FORCE_ANSI`, `FFTUI_NO_ANSI`, `NO_COLOR`, `FFTUI_ASCII`, `FFTUI_UNICODE`, `FFTUI_NO_PICKER`, `FFTUI_SKIP_UPDATE`.
