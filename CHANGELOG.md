# Changelog

All notable user-facing changes are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) (see [docs/Versioning-and-Releases.md](docs/Versioning-and-Releases.md)).

The current working version is the content of the [`VERSION`](VERSION) file. No release has been tagged yet;
everything below is unreleased work that will ship as **0.1.0** once the owner approves the first release.

## [Unreleased]

### Added
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
