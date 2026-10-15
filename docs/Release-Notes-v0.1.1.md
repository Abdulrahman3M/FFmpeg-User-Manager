# FFmpeg User Manager v0.1.1

**A backward-compatible PATCH release** compared with the first published release, [v0.1.0](https://github.com/Abdulrahman3M/FFmpeg-User-Manager/releases/tag/v0.1.0).

## What changed since v0.1.0

- **Smoother terminal navigation:** the TUI now renders complete logical frames centrally and repaints only rows that changed during menu navigation. Unchanged frames produce no screen updates, while selection styling, icons, descriptions and a legacy console fallback are preserved.
- **Regression coverage and technical documentation:** tests cover unchanged frames, selection changes, row additions/removals and repaint behavior. Architecture and testing docs describe the renderer and its validation limits.
- **Repository presentation:** the README shows the current source version beside the project name and features the new FFmpeg User Manager cover image.
- **SemVer and release metadata:** version references follow the canonical `VERSION` value, with changes recorded in the changelog.

## Verification

The renderer changes passed the repository's Windows CI suite on Windows PowerShell 5.1 and PowerShell 7: 1323 PASS, 0 FAIL, 1 UNVERIFIED on each runtime. Real visual behavior in Windows Terminal and classic conhost remains a manual check and is not claimed as verified.

## Upgrade notes

No migration is required. Replace the previous extracted application folder with the v0.1.1 release package. User settings remain in `%APPDATA%\\FFmpeg-User-Manager\\settings.json`.

## Previous release

The previous published release was v0.1.0. See the [comparison](https://github.com/Abdulrahman3M/FFmpeg-User-Manager/compare/v0.1.0...v0.1.1) and [changelog](../../CHANGELOG.md).
