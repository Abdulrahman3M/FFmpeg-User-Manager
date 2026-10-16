# FFmpeg User Manager v0.2.0

**A backward-compatible MINOR release** in the 0.x pre-release series, prepared locally from v0.1.1. This source version and package have not been pushed or published; the last published release remains v0.1.0.

## What changed

- **Web Media Optimization:** guided WebM encoding and size estimates, batch lossy/lossless WebP conversion, and OBJ-to-GLB conversion through bundled Assimp.
- **Media compression and image upscaling:** unified Simple/Advanced compression controls, measured results, bounded target-quality searches, and Lanczos image enlargement with alpha preservation where supported.
- **Batch conversion:** ordered multi-file selection and collision-safe auto-renaming.
- **Bundled library maintenance:** Assimp 6.0.5, its reviewed runtime dependency DLLs and complete license texts are included under `External-Libraries/`. Startup checks upstream stable-release and official MSYS2 package metadata but never downloads or replaces files.
- **Reliability checks:** the PATH isolation, local HTTP stream, and parent-terminal/FFmpeg child-lifetime tests now pass on both supported Windows PowerShell runtimes.

## Verification

Windows PowerShell 5.1.26100.9444 and PowerShell 7.6.5 each completed `tests/Run-Tests.ps1` with **1581 PASS, 0 FAIL, 0 UNVERIFIED**. The suites include a real OBJ/MTL/texture conversion through the application to GLB 2.0, output structure validation, and source-file hash checks.

## Notes and limitations

OBJ material and texture retention depends on the source and exporter. The application identifies external texture references rather than claiming they were embedded; keep referenced sidecar files with the output. Review the converted asset in a 3D viewer before relying on it.

The historical menu screenshots have not been recaptured for this version; `docs/images/README.md` records which screens they do and do not represent. Real Windows Terminal and classic-console visual behavior remains a manual check.

## Licensing and upgrade

Assimp and each bundled runtime dependency retain their own permissive licenses. Their complete license texts and package inventory are shipped in `External-Libraries/`; see [docs/Licensing.md](Licensing.md). No data migration is required. Extract the complete package and replace the prior application folder; user settings remain separate in `%APPDATA%\\FFmpeg-User-Manager\\settings.json`.
