# FFmpeg User Manager v0.1.0

**First official release - pre-release series 0.x.** A guided, keyboard-driven PowerShell terminal application that turns FFmpeg into a set of plain-English wizards: pick a task, answer a few multiple-choice questions, review the summary, and the app builds and runs the correct FFmpeg command for you.

## Highlights

- **27 guided workflows** covering the common 95% of FFmpeg: convert video/audio, extract audio, trim, merge, compress (including an approximate target size), resize, **Video to GIF**, extract frames, audio tools, subtitles, frame rate, filters and color, crop/rotate/flip, text and logo overlays, playback speed, HLS and network streams, media information, remux and streams, metadata and chapters, images and slideshows, video enhancement, record/capture, analyze and detect, batch convert, and an **Advanced FFmpeg** area (capability browser, guided custom command, GPU check). Every option is described in [docs/Workflows.md](Workflows.md).
- **Numbers, not shortcuts.** Every option is shown as `Number  Icon  Name` (`01`, `02` ... `100`) with a short description underneath; no letter keys to memorize.
- **Capability-aware.** Encoders, formats, filters and hardware accelerators are discovered from *your* FFmpeg build; unsupported options are not offered. Verified against FFmpeg 6.1 and FFmpeg 9.0.2.
- **Safe by design.** Existing files are never overwritten without asking, source files are never modified, and FFmpeg is started with argument arrays (no shell, no `Invoke-Expression`). No telemetry, no accounts.
- **Setup help.** Detects FFmpeg/ffprobe, offers to install or update them through `winget` (`Gyan.FFmpeg`) only after you say yes, and includes a *Check & Maintain FFmpeg Setup* tool that explains each step before it asks.
- **Icons that always show.** Emoji in modern terminals, single-column symbols in the classic Windows console, ASCII when output is redirected; the app offers emoji once on first start and remembers your choice.

## New in this release: bigger GIFs

The Video to GIF *Width* question now offers **1080**, **2K**, **4K** and **8K** before *Custom*. As with the existing sizes, the values are widths in pixels and the height follows the aspect ratio:

| Option | Width |
|---|---|
| 1080 | 1080 px |
| 2K | 2560 px |
| 4K | 3840 px |
| 8K | 7680 px |

Widths of 2560 px and more show a short warning (memory, processing time, file size) but are never blocked. *Custom* accepts 16 to 7680 px.

## Reliability work included

Found by running the complete test suite on a real Windows runner and fixed at the root cause (details in [docs/Testing.md](Testing.md)): FFmpeg 9 `-filters` format (the capability scan found no filters), audio-to-video length with FFmpeg 7+, UTF-8 output when redirected, launcher detection of double-click starts in folders with `&`, Windows PowerShell 5.1 encoding and file-enumeration differences.

## Compatibility and verification (what was actually tested)

| Environment | Result |
|---|---|
| Windows PowerShell 5.1 on a Windows runner (FFmpeg 9.0.2) | 1318 PASS, 0 FAIL, 1 UNVERIFIED |
| PowerShell 7 on a Windows runner (FFmpeg 9.0.2) | 1318 PASS, 0 FAIL, 1 UNVERIFIED |
| PowerShell 7.4 on Linux (FFmpeg 6.1) | 1316 PASS, 0 FAIL, 5 UNVERIFIED |

The application targets **Windows 10/11**. Linux is used only to run the test suite.

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in) or PowerShell 7.x (preferred automatically when installed)
- `ffmpeg` and `ffprobe` on `PATH` (the app can install them with winget after asking)
- Windows Terminal recommended; the classic console works with symbol icons

## Quick start

1. Download `FFmpeg-User-Manager-v0.1.0.zip` and extract it completely (right-click the ZIP -> *Properties* -> *Unblock* first).
2. Double-click `FFmpeg-User-Manager.bat` (or run `.\Start-FFmpegTUI.ps1`). No installer, no policy change.

## Known limitations

- **Not verified by any automated run (and therefore not claimed):** rendering in a real Windows Terminal or classic console, real `winget` installs/updates, the native file picker and Explorer integration, and screen / webcam / microphone recording on real devices. `tools/Test-WindowsLocal.ps1` lists these checks. `1.0.0` is reserved until they are done.
- Closing the terminal window during a job cannot be tested automatically.
- A very large GIF (4K/8K) can need gigabytes of memory; use short clips and a low frame rate.
- The UI is English only.

## Upgrade notes

None: this is the first release. Settings are stored per user in `%APPDATA%\FFmpeg-User-Manager\settings.json` (icon style only).

## License

Apache License 2.0 (`LICENSE`, `NOTICE`). FFmpeg is not bundled; it is installed separately under its own license.

Full history: [CHANGELOG.md](../CHANGELOG.md).
