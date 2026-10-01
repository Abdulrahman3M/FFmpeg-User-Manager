# Testing

## Compatibility matrix

| Runtime | Required | Status in this repository |
|---|---|---|
| Windows PowerShell 5.1 | PASS required | **Not executed by the author's environment** (Linux container without Windows PowerShell). Syntax-level compatibility is verified by static tests (see below). **Run the suite on a Windows machine to complete this row.** |
| PowerShell 7.x | PASS required | Full suite executed on PowerShell 7.4 (Linux, FFmpeg 6.1). |

Windows-only behavior that could not be exercised on Linux: native file/folder picker, `explorer.exe /select`, real `winget list/upgrade/install` text output
(the parser is exercised with sample text and mocks), legacy-console ANSI enabling (P/Invoke), Windows path/lock/permission errors.

## Running

```powershell
# everything (both suites)
.\tests\Run-Tests.ps1
# only fast unit tests / only workflow smoke tests / filter by file name
.\tests\Run-Tests.ps1 -Suite Unit
.\tests\Run-Tests.ps1 -Suite Smoke
.\tests\Run-Tests.ps1 -Suite Smoke -Filter Workflows2
# run once per runtime
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
pwsh -NoProfile -File .\tests\Run-Tests.ps1
```

The runner needs no Pester. It prints `[PASS] / [FAIL] / [UNVERIFIED]` per check and exits `1` when anything failed. `UNVERIFIED` is used only when a check cannot
be provoked in the current environment (with the reason printed). FFmpeg + ffprobe must be installed.

## Files

| Suite | File | Covers |
|---|---|---|
| Unit | `Core.Tests.ps1` | validation, paths, argument quoting round-trips with awkward file names, injection safety, filter escaping proven against the real filter parser, encoders, atempo chains, progress parsing, capability parsing/discovery, ffprobe model |
| Unit | `Manager.Tests.ps1` | detection (installed / missing / no ffprobe / stale PATH), update states with mocked winget text, install and update flows through the UI, failure and unmanaged cases |
| Unit | `Tui.Tests.ps1` | menu (two-digit numbers `01`-`99`, `100`+, prefix waiting, Enter, arrows, Esc, Ctrl+C, scrolling, disabled items, no letter keys), main-menu definition (28 numbered options, Exit last), narrow/normal/wide layout, the three icon tiers (emoji, console-safe symbol, ASCII; symbol glyphs are checked against WGL4), theme centralization, line editor, wizard (steps, Back, conditions, Goto, multi-choice, file list, summary menu), dialogs |
| Unit | `Static.Tests.ps1` | version (`VERSION` is SemVer, README badge/CHANGELOG/tags consistent), README/docs link and image check, README commands vs real launcher switches, release-package contents, secret and machine-path scan, `.gitignore`, parse check, no `Invoke-Expression`, no network/telemetry code, no shell launching, no recursive deletion, PS-5.1 syntax/API scan, ASCII-only sources, closure rule, module/wiring/documentation presence |
| Unit | `NewTools.Tests.ps1` | icon-tier decision table (Windows Terminal, conhost, redirected, Linux, overrides), custom-command argument parsing and refusals, DirectShow device parsing, analysis log parsers, chapter parsing and ffmetadata escaping, stream-output destinations, slideshow/sequence helpers |
| Unit | `UiRules.Tests.ps1` | static UI rules by syntax tree: no letter keys or hand-written keys, every `New-Choice` has a description, every Yes/No question describes both answers, every question has help and typed questions an example, no local variable that collides with a parameter |
| Smoke | `Workflows1-5.Tests.ps1` | every workflow end-to-end through the real wizard with real FFmpeg; outputs are verified with ffprobe (codec, size, fps, duration, streams) and, where meaningful, by measurement (volume, LUFS, brightness/saturation, PSNR) ; `Workflows5` covers the tools added for full FFmpeg category coverage (remux/streams, metadata/chapters, slideshows, audio effects, video enhancement, analysis, batch, advanced, stream output) |
| Smoke | `Failures.Tests.ps1` | bad input, output-name rules, unsupported combinations, non-zero FFmpeg exit + details + retry, cancellation, source protection, simulated unwritable folder |
| Smoke | `Launcher.Tests.ps1` | `FFmpeg-User-Manager.bat` with a real `cmd` interpreter (native on Windows, Wine's `cmd.exe` on Linux): runtime preference (pwsh.exe over powershell.exe), fallback, no-PowerShell error, missing entry script, paths with spaces/parentheses/ampersand, argument pass-through, exit-code propagation. Double-click detection (`%CMDCMDLINE%`) is `UNVERIFIED` under Wine |
| Smoke | `App.Tests.ps1` | launcher in child processes: startup/exit codes, non-interactive refusal, ANSI vs non-ANSI, terminal restoration after normal exit and after an error, missing/stale FFmpeg with a real PATH sandbox, main-menu integration, error containment |

## Launcher tests and Wine

`tests/Smoke/Launcher.Tests.ps1` runs the batch file in a sandbox with dummy `pwsh.exe` / `powershell.exe` files on `PATH` (detection) and a `.cmd` stub selected through `FFUM_POWERSHELL` (execution and exit codes).
On Windows it uses `cmd.exe`; on Linux it uses Wine if installed (`apt install wine64`), otherwise the cases are reported `UNVERIFIED`. Running the real PowerShell application through the launcher on Windows remains a manual check.

## Fixture strategy

No binary fixtures are committed. Tiny clips are synthesized with FFmpeg `lavfi` sources at run time in a temp folder that is removed afterwards
(see `tests/Fixtures/README.md`). Names contain spaces, `( ) & '`, Arabic and Cyrillic.
Package-manager operations are **mocked** (`Set-FFManagerHooks`); nothing on the machine is installed, updated or removed. Network-stream tests use a local `HttpListener` on 127.0.0.1.

## How the UI is driven

`Invoke-Ui` feeds a fixed key string; `Invoke-Flow` answers on demand from rules that match the text of the current screen (`New-Rule 'Prompt' 'keys'`), pressing Enter (the default)
otherwise. Output is captured in the renderer's buffer, so assertions read what the user would see. Options are typed as numbers (`08`); the test helpers also understand
**key macros** that are resolved against the current screen - `{#label}` types the number of the option whose text contains *label*, `{#LAST}` the last number of the list - so tests do not depend on
the position of an option. `New-FileListRules` fills a "Files" question (type paths, *Add another file*, *Done*).

## Manual TUI checklist (real terminal)

1. Windows Terminal + PowerShell 7 and Windows PowerShell 5.1: start, arrow keys, typing numbers (`01`, `08`, `28`), Esc/Back, Ctrl+C.
2. Legacy console host (conhost, double-click the `.bat`): every option must show a **symbol icon** (never a blank, a box or an ASCII tag); colors fall back; still readable. Also check Windows Terminal (emoji icons), the Consolas, Lucida Console and raster fonts, and `FFTUI_ICONS=ascii`. **Not yet verified on Windows.**
3. Resize the window narrow (< 60 columns) and short (< 20 rows) while on the menu and in a wizard.
4. Paste a quoted path with spaces / Unicode; press `Tab` for the native picker.
5. Run a long job, press `Esc`, answer `02` (No, continues) then `Esc`, `01` (Yes, stops); confirm ffmpeg.exe is gone in Task Manager.
6. After quitting (and after a forced error) the cursor is visible and the scrollback of the terminal is intact.
7. Main menu `27` -> `02` (check for updates) with and without internet; on a machine with FFmpeg from winget and one with a manual copy.
8. `winget uninstall Gyan.FFmpeg`, start the app: install flow (needs internet).
9. Record / Capture (`23`): screen, webcam and microphone recordings need Windows capture devices; parsing and command building are unit tested but the recordings themselves are **unverified** until run on Windows.
