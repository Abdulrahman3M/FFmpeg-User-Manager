# Changelog

All notable user-facing changes are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) (see [docs/Versioning-and-Releases.md](docs/Versioning-and-Releases.md)).

The current working version is the content of the [`VERSION`](VERSION) file. No release has been tagged yet;
everything below is unreleased work that will ship as **0.1.0** once the owner approves the first release.

## [Unreleased]

### Added
- **Video to GIF:** new width presets **1080**, **2K**, **4K** and **8K** before *Custom*. As with the existing sizes the values are widths in pixels (the height follows the aspect ratio): 1080 = 1080 px, 2K = 2560 px, 4K = 3840 px, 8K = 7680 px, shown on screen. Widths of 2560 px and more show a short warning (memory, time and file size). *Custom* now accepts 16 to 7680 px wide (custom height up to 4320 px).
- GitHub Actions workflow (`.github/workflows/tests.yml`) that runs the full test suite on a Windows runner with Windows PowerShell 5.1 and PowerShell 7 (started by hand, by pull requests and by pushes to `main`; the full log is kept as an artifact), and an isolated-reproduction workflow (`repro.yml`, `tests/Repro/`).
- `tools/Test-WindowsLocal.ps1`: runs the suite under every installed PowerShell edition, reports what the application detects about the terminal and lists the checks that need a real Windows Terminal or real devices.
- Tests: real "read permission denied" and "file locked by another program" checks, a regression test for the FFmpeg 9 filter list, flow tracing for diagnosing scripted wizards.
- The maintenance tool's font step reports which terminal was detected (for example Windows Terminal); it never downloads a font and never starts a system repair.
- **Numbered options everywhere.** Every option on every screen is shown as `Number  Icon  Name` with a two-digit, zero-padded number (`01` ... `09`, `10`, `11` ..., continuing to `100`+), with a short description under each option.
  There are no letter keys any more (Exit and Back are numbered like everything else; `Esc` goes back, `Ctrl+C` quits).
- Explanations for every question and option: a description under every choice, both answers of every Yes/No question described, help text for every question and an example for every typed input.
- New tool groups for fuller FFmpeg coverage, all capability-checked against the installed build:
  **Remux & Streams** (container change without re-encoding, keep selected streams, track language/default), **Metadata & Chapters** (edit tags, remove metadata/chapters, add chapters, cover art),
  **Images & Slideshows** (slideshow with music, image sequence to video, audio to video, contact sheet), **Video Enhancement** (deinterlace, denoise, stabilize, add bars for an aspect ratio, reverse, loop),
  **Record / Capture** (screen, webcam, microphone on Windows), **Analyze & Detect** (volume, loudness, silence, black frames, scene changes, black bars, PSNR/SSIM comparison),
  **Batch Convert Folder**, and **Advanced FFmpeg** (capability browser for every encoder/decoder/format/filter/protocol/pixel format, guided custom command, GPU check, build details).
- Audio Tools: fade in/out, bass/treble/voice clarity, noise reduction, silence removal, frequency filters, audio/video sync offset, reverse.
- Streaming: send a file to an RTMP/SRT/UDP/RTSP address in real time (stream key hidden on screen).
- Licensing: the project is now licensed under the Apache License 2.0 (`LICENSE`, `NOTICE`, `docs/Licensing.md`, README License section); both files ship in the release package.
- `AGENTS.md`: permanent dependency-aware change-sync rule (code change -> affected artifacts -> update -> tests -> docs/visuals/version/changelog sync -> final verification) and licensing/third-party rules.
- Tests: new suites for the added tools, the icon-tier decision, argument parsing and log parsers, and static UI rules (numbers only, descriptions everywhere, parameter/variable collisions).
- Interactive PowerShell TUI for FFmpeg with a guided question-and-answer wizard for every workflow (Windows PowerShell 5.1 and PowerShell 7.x code base).
- Workflows: video and audio conversion, audio extraction, trim/cut, merge, compression (including approximate target size), resize/scale,
  video to GIF (palette-based), frame extraction, audio tools (volume, loudness normalization, sample rate, channels, tempo, remove/replace audio),
  subtitle tools (extract, mux, burn, remove, keep selected), frame-rate conversion, filters and color controls with a filter browser,
  crop/rotate/flip, text and logo overlays, playback speed, HLS creation and network-stream saving/inspection, media information.
- FFmpeg lifecycle management: detection (real `-version` check), automatic installation and update checks through winget (`Gyan.FFmpeg`),
  non-fatal handling of offline/unmanaged installations, capability discovery from the installed build, FFmpeg status screen.
- Windows launcher `FFmpeg-User-Manager.bat` (prefers PowerShell 7, falls back to Windows PowerShell 5.1, process-scoped execution policy only).
- Safety behavior: no silent overwrite, source files never modified, argument-array command construction, cancellation with confirmation.
- Single version source (`VERSION`), version shown in the header, Status screen and `Start-FFmpegTUI.ps1 -Version`.
- Documentation (`README.md`, `docs/`), `AGENTS.md` working rules, and an automated test suite (`tests/Run-Tests.ps1`).

- **Check & Maintain FFmpeg Setup** (main menu 28): guided, step-by-step health check (FFmpeg install/repair, updates, emoji font, icon style, capability re-scan) that explains each step and asks before any download.

### Changed
- On first start in a Windows console that is not recognized as emoji-capable, the app offers colorful emoji icons (with a preview). The answer is remembered per Windows account (`%APPDATA%\FFmpeg-User-Manager\settings.json`), so it is asked only once; FFmpeg Status / Settings has an *Icon style* option to change it. `FFTUI_ICONS` still overrides.
- Wizard summary, dialogs, FFmpeg status and media-information screens use numbered options instead of letter keys; the job-cancel key is `Esc`.
- Main menu grew from 19 to 29 numbered options (Exit is the last number).
- The `.bat` launcher switches the console to UTF-8 (code page 65001) while the app runs and restores it afterwards.
- Screenshots in `docs/images/` were recaptured for the new layout.

### Fixed
- **FFmpeg 9 compatibility:** `ffmpeg -filters` now has two flag columns; the capability scan found no filters, so loudness normalization, noise reduction, silence removal, subtitles and others were switched off. The parser accepts both layouts.
- **Audio to Video** (black screen / still picture): the endless picture source is bounded by the length of the audio; relying on `-shortest` alone gave videos up to about 2 s too long with FFmpeg 7+.
- Forced emoji/symbol icons were lost when the output was redirected on Windows (the console is now switched to UTF-8 in that case too).
- `FFmpeg-User-Manager.bat`: the double-click detection no longer executes parts of the command line when the folder name contains `&`, quotes or parentheses.
- The winget lookup honors the test hook, so tests no longer depend on a real winget.
- **Icons missing in a normal run.** Icons are characters, not files, and on the classic Windows console (double-clicking the `.bat`) the old detection fell back to text tags or the console could not draw the emoji. Icons now use three tiers
  (emoji / console-safe WGL4 symbols / ASCII) chosen by `Get-IconTier`, the console is switched to UTF-8 output, and every option always shows an icon. Emoji widths were made consistent (wide emoji only).
- "Run again" after a cancelled job returned to the menu instead of restarting the wizard.
