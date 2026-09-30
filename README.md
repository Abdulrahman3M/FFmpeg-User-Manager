# FFmpeg TUI (FFmpeg PowerShell TUI)

A beginner-friendly, keyboard-driven **terminal user interface for FFmpeg on Windows**.
Pick what you want to do, answer a few plain-English questions, and the app runs FFmpeg for you -
no command-line syntax to remember.

* Runs on **Windows PowerShell 5.1** and **PowerShell 7.x** (same code base).
* English-only UI, bordered panels, icons (with ASCII fallbacks), dim help text, progress bars.
* Every workflow is a guided wizard: probe the source, ask relevant questions (multiple choice first),
  validate answers, show a summary, run FFmpeg, show the result.
* No accounts, telemetry, ads, GUI, web server or database. Everything stays on your machine.

## Requirements

| Item | Requirement |
|---|---|
| OS | Windows 10 / 11 (the app is tested logic-wise on Linux too, but installation/update features target Windows) |
| PowerShell | Windows PowerShell 5.1 **or** PowerShell 7.x |
| FFmpeg | `ffmpeg` and `ffprobe` on `PATH` - or let the app install them (see below) |
| Terminal | Windows Terminal recommended (ANSI colors + emoji). The legacy console works with plain colors and ASCII icons. The PowerShell ISE is **not** supported. |

## Start

```powershell
# from the project folder
.\Start-FFmpegTUI.ps1
```

If script execution is restricted on your machine:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-FFmpegTUI.ps1
# or, once, for a downloaded copy:
Get-ChildItem -Recurse . | Unblock-File
```

Optional switch: `-SkipUpdateCheck` (skip the FFmpeg update check at startup).

## What happens at startup

1. The terminal is initialized (ANSI/Unicode detection, safe restore on exit).
2. `ffmpeg` and `ffprobe` are located and **actually executed** (`-version`) - a stale PATH entry is not an installation.
3. **FFmpeg missing** -> a screen offers **[I] Install FFmpeg automatically** or **[Q] Exit**.
   The main menu is not entered until a working FFmpeg + ffprobe pair exists.
4. **FFmpeg found** -> a quick update check runs (only when the copy is managed by winget). If an update exists you can
   choose **[U] Update now** or **[C] Continue without updating**. If the check cannot run (offline, winget missing,
   manually installed FFmpeg) you get a short, non-fatal notice and continue.
5. The installed build is scanned once for its encoders, decoders, muxers, demuxers, filters, protocols and hardware
   accelerators. Only options your build really supports are offered.
6. The main menu opens.

### Automatic installation (winget)

* Uses Windows Package Manager (`winget`) with the package **`Gyan.FFmpeg`** (verified in the official winget-pkgs
  manifests; provides `ffmpeg`, `ffprobe`, `ffplay`). The package id lives in `config/defaults.json`.
* The package is verified first (`winget show`), the install only starts after you press Install, progress is shown,
  PATH is refreshed for the running process, and both tools are re-checked before the app continues.
* If installation cannot complete you get the exact reason (network, source, administrator rights) and can retry or exit.
  The app never downloads executables from URLs itself and never replaces an FFmpeg it did not install.

## Keyboard controls

| Key | Action |
|---|---|
| `Up` / `Down` | Move the highlight (wraps around) |
| `Enter` | Select / accept the default |
| `1`-`9`, letters shown in the menu | Quick select |
| `Esc` (or `B` where no menu item uses `B`) | Back one step - answers you already gave are kept |
| `Q` | Quit (main menu) - or cancel a running job (you are asked to confirm) |
| `V` on the summary screen | View the exact FFmpeg command (Advanced) |
| `Tab` in path questions | Open the native Windows file/folder picker (if available) |
| `Ctrl+U` in text questions | Clear the line |
| `C` in multi-select lists | Continue |

Typed or pasted paths always work: quotes, spaces, Unicode (Arabic, Cyrillic, ...) and drag-and-drop text such as
`& 'C:\my file.mp4'` are handled.

## Workflows

| Key | Workflow |
|---|---|
| 1 | Convert Video Format |
| 2 | Convert Audio Format |
| 3 | Extract Audio from Video |
| 4 | Trim / Cut Media |
| 5 | Merge Media |
| 6 | Compress Media |
| 7 | Resize / Scale Video |
| 8 | Video to GIF |
| 9 | Extract Frames / Images |
| A | Audio Tools (volume, loudness normalization, sample rate, channels, tempo/speed, remove audio, replace/add audio) |
| B | Subtitle Tools (extract, add/mux, burn, remove, copy selected) |
| C | Change Frame Rate |
| D | Filters & Color (+ Filter Browser) |
| E | Crop / Rotate / Flip |
| F | Text & Watermark |
| G | Change Playback Speed |
| H | Streaming / HLS |
| I | Media Information |
| S | FFmpeg Status / Settings |
| Q | Exit |

Details for every question of every workflow: [docs/Workflows.md](docs/Workflows.md).

## Safety guarantees

* Existing output files are **never overwritten without confirmation** (FFmpeg is always started with `-n`; `-y` is used
  only after you choose *Overwrite*). Source files are never modified or deleted.
* Commands are built as argument arrays and passed to FFmpeg without a shell; user text never goes through
  `Invoke-Expression`. Filter text (paths, overlay text) is escaped for FFmpeg's filter syntax.
* Cancelling a job asks for confirmation, then stops FFmpeg; partial output is flagged as potentially incomplete.

## Troubleshooting

| Symptom | What to do |
|---|---|
| "FFmpeg was not found." | Press `I` to install with winget, or install FFmpeg yourself, open a **new** terminal and choose *Retry*. |
| "ffmpeg cannot be started" | A stale `PATH` entry points to a missing/broken ffmpeg. Fix or remove it, then *Retry*. |
| Install/update fails with an administrator message | Start the terminal as Administrator, or install FFmpeg manually. |
| Garbled icons / no colors | Use Windows Terminal, or run with `$env:FFTUI_ASCII='1'` and `$env:FFTUI_NO_ANSI='1'`. |
| "needs an interactive console" | Start the script from a real terminal window (not from a redirect/pipe or the ISE). |
| A workflow option is missing | Your FFmpeg build does not include that encoder/filter; check *S. FFmpeg Status / Settings*. |
| Text overlay fails | The `drawtext` filter needs FreeType and a font; choose a font file in the *Font* question. |

More: [docs/Architecture.md](docs/Architecture.md) - [docs/Testing.md](docs/Testing.md).

## Project layout

```
Start-FFmpegTUI.ps1        launcher
src/Core                   app bootstrap, environment, paths, validation, process runner
src/TUI                    theme, renderer, input, menu, dialogs, wizard, progress view
src/FFmpeg                 manager (detect/install/update), capabilities, probe, command builder, progress
src/Workflows              one module per workflow group (+ WorkflowCommon)
config/defaults.json       application defaults (presets, winget package id)
tests/                     unit + smoke tests (Run-Tests.ps1)
docs/                      architecture, workflows, testing
```
