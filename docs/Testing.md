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
| Unit | `Tui.Tests.ps1` | menu (numbers, letters, arrows, Enter, Esc, Q, scrolling, disabled items), main-menu definition, narrow/normal/wide layout, icons and ASCII fallback, theme centralization, line editor, wizard (validation, Back, Goto, multi-select, file list, summary, build errors), dialogs |
| Unit | `Static.Tests.ps1` | parse check, no `Invoke-Expression`, no network/telemetry code, no shell launching, no recursive deletion, PS-5.1 syntax/API scan, ASCII-only sources, closure rule, module/wiring/documentation presence |
| Smoke | `Workflows1-4.Tests.ps1` | every workflow end-to-end through the real wizard with real FFmpeg; outputs are verified with ffprobe (codec, size, fps, duration, streams) and, where meaningful, by measurement (volume, LUFS, brightness/saturation, PSNR) |
| Smoke | `Failures.Tests.ps1` | bad input, output-name rules, unsupported combinations, non-zero FFmpeg exit + details + retry, cancellation, source protection, simulated unwritable folder |
| Smoke | `App.Tests.ps1` | launcher in child processes: startup/exit codes, non-interactive refusal, ANSI vs non-ANSI, terminal restoration after normal exit and after an error, missing/stale FFmpeg with a real PATH sandbox, main-menu integration, error containment |

## Fixture strategy

No binary fixtures are committed. Tiny clips are synthesized with FFmpeg `lavfi` sources at run time in a temp folder that is removed afterwards
(see `tests/Fixtures/README.md`). Names contain spaces, `( ) & '`, Arabic and Cyrillic.
Package-manager operations are **mocked** (`Set-FFManagerHooks`); nothing on the machine is installed, updated or removed. Network-stream tests use a local `HttpListener` on 127.0.0.1.

## How the UI is driven

`Invoke-Ui` feeds a fixed key string; `Invoke-Flow` answers on demand from rules that match the text of the current screen (`New-Rule 'Prompt' 'keys'`), pressing Enter (the default)
otherwise. Output is captured in the renderer's buffer, so assertions read what the user would see.

## Manual TUI checklist (real terminal)

1. Windows Terminal + PowerShell 7 and Windows PowerShell 5.1: start, arrow keys, digits, letters, Esc/Back, Q.
2. Legacy console host (conhost) : colors fall back, ASCII icons, still readable.
3. Resize the window narrow (< 60 columns) and short (< 20 rows) while on the menu and in a wizard.
4. Paste a quoted path with spaces / Unicode; press `Tab` for the native picker.
5. Run a long job, press `Q`, answer No (continues) then `Q`, Yes (stops); confirm ffmpeg.exe is gone in Task Manager.
6. After quitting (and after a forced error) the cursor is visible and the scrollback of the terminal is intact.
7. `S` -> `U` with and without internet; on a machine with FFmpeg from winget and one with a manual copy.
8. `winget uninstall Gyan.FFmpeg`, start the app: install flow (needs internet).
