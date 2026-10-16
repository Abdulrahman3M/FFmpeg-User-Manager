# Architecture

## Layers

```
Start-FFmpegTUI.ps1 --> src/Import-Modules.ps1 --> Core/App.psm1 (Start-FFmpegTuiApp)
                                                     |
        +--------------------+-----------------------+-------------------+
        | TUI (screens)      | FFmpeg (engine)       | Workflows          |
        | Theme  Renderer    | FFmpegManager         | WorkflowCommon     |
        | Input  Menu Dialog | FFmpegCapabilities    | ConvertVideo ...   |
        | Wizard ProgressView| MediaProbe            | (32 workflow files)|
        |                    | FFmpegCommandBuilder  |                    |
        |                    | FFmpegProgress        |                    |
        +--------------------+ Core: Environment Paths Validation ProcessRunner ExternalLibraries
```

`FFmpeg-User-Manager.bat` (repository root) is a thin Windows launcher: it finds `Start-FFmpegTUI.ps1`, prefers `pwsh.exe`, falls back to `powershell.exe`, and forwards arguments and the exit code. The application version comes from the root `VERSION` file (`Get-AppVersion`).

All modules are imported into the global session state by `Import-FFTuiModules` (ordered, fail-fast), so exported
functions can call each other. Module-private state uses `$script:` variables.

`Core/ExternalLibraries.psm1` validates `External-Libraries/manifest.json`, compares Semantic Versions and package rebuild revisions, and performs bounded HTTPS GETs only to allowlisted official upstream and package-manager metadata endpoints. Startup reports stable updates but never downloads or replaces package files. Bundled executable and DLL paths are resolved from the project tree.

The manifest is the canonical version, architecture, edition-policy, source, integrity and platform-evidence inventory for bundled runtimes. `FFmpegManager.psm1` resolves FFmpeg and ffprobe as one validated pair in this order: application-bundled runtime, the explicit `FFTUI_FFMPEG_PATH` directory, then the existing system discovery path. It never combines executables from different tiers. The resolved source and directory are exposed through `Find-FFmpegInstallation` and `Get-FFmpegInfo`; the existing capability scanner continues to inspect the selected executable.

## Core

| Module | Responsibility |
|---|---|
| `App.psm1` | Startup sequence, FFmpeg missing/install/update screens, bounded read-only external-library update checks, capability scan, main menu, status screen, top-level error containment, terminal cleanup. |
| `Maintenance.psm1` | The guided *Check & Maintain FFmpeg Setup* tool; reuses the install/update/icon flows and asks before every step. |
| `Environment.psm1` | Runtime info (5.1 vs 7), interactive/ANSI/Unicode detection, terminal size, `config/defaults.json` loading. `Test-IsWindows` guards `$IsWindows` (absent in 5.1). |
| `Paths.psm1` | Path cleaning (`"..."`, `'...'`, `& '...'`), resolution, input-file checks (missing, folder, empty, locked, denied), file-name validation (reserved names, illegal chars), size/duration formatting, open-folder, optional native picker. |
| `Validation.psm1` | Parsers returning `{Ok, Value, Error}`: timestamps, integers, decimals, bitrates, frame rates, colors. Never throw for user mistakes. |
| `ProcessRunner.psm1` | Argument quoting per `CommandLineToArgvW` (works on 5.1, which has no `ArgumentList`), capture and streaming child-process helpers. Windows FFmpeg children are attached to a kill-on-job-close process job so terminal shutdown cannot orphan an encode. No shell is ever involved. |

## TUI

### Flicker-Free Centralized Frame Rendering

The Renderer composes a logical ANSI frame in memory via `Start-Frame`, semantic `Write-Ui` / `Write-UiSegments` calls and `Stop-Frame`. It compares the complete rendered ANSI text (including colors and styles) row-by-row to the last committed frame. Only changed rows are positioned with CSI `row;1H` and emitted with CSI `K`, while removed rows are erased with CSI `2K`. Stable frames require zero writes; the old and new selection rows are usually the only changed ones. The frame cache is invalidated at explicit clears, alternate-screen transitions, renderer initialization and terminal resize. Non-VT terminals use safe console cursor positioning with legacy clear fallback, and scripted `Buffer` output remains unchanged. Emoji/symbol/ASCII icons and muted descriptions are not removed. Physical flicker and right-edge/Unicode behavior remain subject to Windows Terminal/conhost manual validation.


* **Theme** - the only place with color values. Semantic roles: `PrimaryAccent SecondaryAccent Title NormalText DimText
  Success Warning Error Border Selected Muted`, each with an ANSI code and a legacy `ConsoleColor`. It also owns the **icons** (see
  [Icons](#icons-why-they-always-appear)).
* **Renderer** - all output. Three modes: ANSI (cursor-home redraw, alternate screen), legacy (`Clear-Host` + `Write-Host` colors)
  and a memory buffer used by tests. Provides header, rules, key/value panels, key hints, progress bar, width-aware truncation and
  compact layout (< 72 columns).
* **Input** - one key reader for the real console or a scripted queue/provider (automation hook), plus the single-line editor
  (`Read-TuiLine`: Left/Right/Home/End/Backspace/Delete, `Esc` = Back, `Tab` = Browse, `Ctrl+U` = clear).
* **Menu** - the one reusable list (main menu, submenus and every multiple-choice question). Rows read **Number, Icon, Name**; numbers are
  assigned automatically, two digits minimum and zero-padded (`01` ... `09`, `10` ... `99`, `100` ...), never hand-written. Keys: digits (quick select,
  `Resolve-NumberInput`), arrows, `Enter`, `Esc` (back), `Ctrl+C` (quit) - there are no letter keys. A description sits under every option; only when the
  window is very short is it shown for the selected option alone. Disabled items show their reason.
* **Dialog** - notices and yes/no confirmations (also numbered lists: `01`, `02` ...; an action id such as `R` is only an internal return value), scrollable text viewer.
* **ProgressView** - job progress (percentage only when the duration is known, otherwise spinner + elapsed time).
* **Wizard** - see below.

### Wizard system

Steps are data (hashtables). `Invoke-Wizard -Steps ... -Build {...}` renders them, keeps answers in `$W.Answers`, supports Back
(answers are kept), conditional steps (`When`), jumps (`$W.Goto`), info panels (`Set-WizardPanel`), a final summary (a numbered menu: Start, View command, Back).
Every choice carries a description and every question help text (and an example for typed answers); static tests enforce it.

| Field | Meaning |
|---|---|
| `Id`, `Type`, `Prompt`, `Help`, `Example`, `Default` | Identification and text. `Default`/`Choices` may be scriptblocks `param($W)`. |
| `Type` | `File`, `Files` (ordered list), `Directory`, `Text`, `Integer`, `Decimal`, `Timestamp`, `Bitrate`, `FrameRate`, `Color`, `Resolution`, `YesNo`, `Choice`, `MultiChoice`, `Info`, `Custom`. `Optional = $true` allows empty. |
| `Choices` | `@{Value; Label; Desc; Enabled; Reason}` (`New-Choice value label DESCRIPTION`); `AllowCustom = @{Type; Prompt; Min; Max; ...}` adds a "Custom..." entry that opens a validated text question. |
| `Validate` | `param($value,$W)` -> `$null` or an error message. |
| `When` | Step is skipped (and its stale answer dropped) when false. |
| `OnAnswer` | Side effects after acceptance, e.g. probing or `$W.Goto = 'stepId'`. |

The `Build` scriptblock turns answers into a **job**: `Summary` rows, `Stages` (each with `Arguments` or a `Factory`, `DurationSec`),
`OutputPath`, `OutputKind`, `TempFiles`, notes. `Start-StandardWorkflow` runs wizard -> `Invoke-FFJob` -> repeat on "Run again".

**Scoping rule:** step scriptblocks run later inside the Wizard module. A block that reads a local variable of the function that
created it must end with `.GetNewClosure()` (enforced by a static test). Never name a local `$w`: variable names are
case-insensitive and it would overwrite the wizard state `$W`.

### Icons: why they always appear

Icons are plain characters, not image files, so the only way one can fail to show is when the terminal cannot draw the glyph. `Theme.psm1` therefore keeps three forms of
every icon and `Get-IconTier` (decision logic in `Resolve-IconTier`, unit tested) picks the one the terminal can draw:

| Tier | Used when | Glyphs |
|---|---|---|
| **Emoji** | Windows Terminal, VS Code, ConEmu (`WT_SESSION`, `TERM_PROGRAM`, `ConEmuANSI`), UTF-8 terminals on Linux/macOS | Wide, emoji-presentation characters (two columns) |
| **Symbol** | The classic Windows console (conhost / the Windows PowerShell 5.1 window) and any other Windows console | Single-column glyphs from the Windows Glyph List 4 (for example a play triangle, note, arrows), which Consolas, Lucida Console and Courier New all contain - so there is always an icon, never a blank or a box |
| **Ascii** | Redirected output, or `FFTUI_ASCII=1` | Bracketed tags such as `[VIDEO]` |

On Windows the console output encoding is switched to UTF-8 at startup (`Set-ConsoleUtf8Output`) and the `.bat` launcher selects code page 65001 while the app runs and restores it afterwards.
`FFTUI_ICONS=emoji|symbol|ascii` overrides the detection. Otherwise a choice saved by the one-time startup question (`Invoke-IconStyleFlow`, stored by `Set-UserSetting` in the per-user settings file) is used. The Status screen shows which set is in use. The box-drawing characters follow the same tier.

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
* **Workflow modules** (`src/Workflows/`) - one module per tool group. `CompressionPlanning` and `CompressionWorkflow` power Compress Media; `UpscaleImage` reuses shared image helpers; `WebMediaOptimization` handles WebM, WebP, size estimates and OBJ-to-GLB. Other groups include `RemuxStreams`, `MetadataChapters`, `ImagesAndVisuals`, `AudioEffects`,
  `VideoEnhance`, `CaptureMedia`, `AnalyzeMedia`, `BatchConvert` and `AdvancedTools` (see [Workflows.md](Workflows.md) for the category map). Read-only analysis runs FFmpeg to a null
  output and parses its log (pure parsers, unit tested); batch conversion reuses the single-file job builders; the custom command splits typed options into tokens (`ConvertFrom-ArgumentText`) and validates
  encoders/formats against the installed build.
* **WorkflowCommon** - shared steps (input+probe, output folder/name/collision, container, video/audio encode, time range, resolution, frame rate),
  shared job builders (`New-VideoProcessJob`, `New-AudioProcessJob`), opt-in actual byte/reduction/target metrics and the job runner/result screens.

`ExternalLibraries.psm1` validates the external-library manifest and performs bounded, read-only stable-version checks against official upstream and package-manager metadata; it never downloads or replaces binaries. `WebMediaOptimization.psm1` reuses the shared job lifecycle for capability-driven WebM and WebP conversion, approximate bitrate/representative-sample size estimates, and OBJ-to-GLB conversion. Assimp is bundled under `External-Libraries/` with its runtime DLLs and license texts. A stage describes the bundled executable plus tokenized arguments without invoking a shell. Its GLB output is validated before finalization.

## Data flow of one job

`workflow steps` -> answers -> `Build` (validates combinations, builds tokens) -> summary -> `Invoke-FFJob` (creates folders after confirmation, runs stages,
progress, cancel) -> success screen / failure screen (short reason + technical details) -> temp-file cleanup.

## Automation hooks (tests)

`Start-FFmpegTUI.ps1 -ScriptedInput '01{Enter}' -BufferOutput` feeds keys and renders into a buffer;
`Set-TuiScriptedProvider` supplies keys on demand from the current screen text. Tokens: `{Enter} {Esc} {Up} {Down} {Left} {Right} {Home} {End} {Del} {BS} {Tab} {PgUp} {PgDn} {CtrlC} {Clear}`.
Environment switches: `FFTUI_FORCE_ANSI`, `FFTUI_NO_ANSI`, `NO_COLOR`, `FFTUI_ICONS` (`emoji`, `symbol`, `ascii`), `FFTUI_ASCII`, `FFTUI_UNICODE`, `FFTUI_NO_PICKER`, `FFTUI_SKIP_UPDATE`.
Numbers are typed as two-digit keys (`08` = Video to GIF). Test-only key macros in `tests/TestHelpers.ps1` resolve against the screen: `{#label}` types the number of the option whose text contains *label*, `{#LAST}` the last number.
