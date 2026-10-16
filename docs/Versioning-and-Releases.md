# Versioning and Releases

## Standard

The project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html): `MAJOR.MINOR.PATCH`.

| Increment | When | Example |
|---|---|---|
| **PATCH** | Bug fixes, small compatibility or reliability fixes, non-breaking internal fixes, documentation fixes tied to a release | `0.1.2` -> `0.1.3` |
| **MINOR** | New backward-compatible features: new workflows, menu functions, options, notable UI improvements. PATCH resets to `0` | `0.1.3` -> `0.2.0` |
| **MAJOR** | Breaking changes: removed or incompatible behavior, incompatible configuration changes, anything users must adapt to. MINOR and PATCH reset to `0` | `1.3.4` -> `2.0.0` |

`VERSION` changes only when a release is prepared (checklist below). Work done after the last release, or before the first one, is collected under `[Unreleased]` in the changelog and does **not** bump the
version on its own; the increment is decided once, for the whole set of changes, when the release is cut. The first release, `0.1.0` (2026-10-04), collected all the work done before it.

While the major version is `0` the project is pre-release: anything may change between MINOR versions.
`1.0.0` is reserved for the point where the full application is implemented, tested on Windows under both PowerShell runtimes,
documented and judged stable for general users - it is never assigned for appearance.

### Pre-release labels

| Label | Meaning | Example |
|---|---|---|
| `alpha` | Early, unstable development | `1.0.0-alpha.1` |
| `beta` | Feature complete or nearly so; in testing | `1.0.0-beta.1` |
| `rc` | Release candidate | `1.0.0-rc.1` |

No other labels are used.

## Git tags

Every official release has exactly one annotated tag named `vMAJOR.MINOR.PATCH` (or with a pre-release label), for example `v0.1.0`, `v1.0.0`, `v1.0.0-rc.1`.
Tags such as `release-1`, `final`, `build7` are not used.

## Canonical version source

The file [`VERSION`](../VERSION) in the repository root is the single source of truth (first line, a SemVer string, no `v` prefix).

Version `0.3.0` is the published MINOR release for the backward-compatible Full/Lite runtime resolution, transactional FFmpeg maintenance and reproducible release-package features. The preceding `0.2.0` feature set is retained in the changelog and historical release notes.

* The application reads it (`Get-AppVersion`) and shows it in the header, on the FFmpeg Status screen and with `Start-FFmpegTUI.ps1 -Version`.
* Release archive names and the Git tag are derived from it (`FFmpeg-User-Manager-v<VERSION>-Full-Windows-x64.zip`, `FFmpeg-User-Manager-v<VERSION>-Lite-Windows-x64.zip`, `v<VERSION>`); the checksum file is `SHA256SUMS-v<VERSION>.txt`.
* The README version badge is a static image and must equal `VERSION`; `tests/Unit/Static.Tests.ps1` fails when they differ, or when `VERSION` is not valid SemVer.
* Do not write the version number by hand anywhere else.

## Changelog process

[`CHANGELOG.md`](../CHANGELOG.md) follows Keep a Changelog. During development add user-relevant entries (not raw commit messages) under `## [Unreleased]`
in `Added / Changed / Fixed / Removed` (omit empty sections). On release, rename `[Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, open a fresh `[Unreleased]`, and keep older releases in reverse chronological order.

## Release checklist

1. Complete the intended release scope.
2. Run the tests on **both** runtimes on Windows: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1` and `pwsh -NoProfile -File .\tests\Run-Tests.ps1`.
3. Review licensing: `LICENSE` is unchanged, `NOTICE` and the third-party statement still match reality (see [Licensing.md](Licensing.md) and section 8 of `AGENTS.md`), and any new dependency was reviewed (compatibility, third-party notices, attribution).
4. Verify the launcher: double-click `FFmpeg-User-Manager.bat`, run it from another folder and from a path with spaces (the automated launcher tests cover the logic).
5. Update `CHANGELOG.md` (move `[Unreleased]` entries into the new version section with today's date).
6. Decide the SemVer increment from the rules above.
7. Update `VERSION`.
8. Verify the application shows the new version (`.\Start-FFmpegTUI.ps1 -Version`, header, Status screen).
9. Verify the README badge and any version mentions match `VERSION` (the static test checks this).
10. Commit the release changes (`Release vX.Y.Z`).
11. Create the tag: `git tag -a vX.Y.Z -m "FFmpeg User Manager vX.Y.Z"` and push it (`git push origin vX.Y.Z`).
12. Build both editions: `.\tools\New-ReleasePackage.ps1 -Edition Both -AcquireFFmpeg` (after explicitly approving the pinned FFmpeg download) or pass a previously verified local runtime with `-FFmpegRuntimeSource`; inspect both ZIPs and `SHA256SUMS-vX.Y.Z.txt` (Full contains approved runtimes and their licenses; Lite has no runtime binaries; neither contains `.git`, tests, logs or secrets).
13. Prepare the GitHub Release titled `FFmpeg User Manager vX.Y.Z` from the tag, with the changelog section as notes and both edition ZIPs plus the checksum file. **Publish only after the owner approves.**
14. Verify the downloadable archive starts correctly after extraction (including into a folder with spaces).
15. Confirm the repository visibility is unchanged (it stays Private unless the owner explicitly decides otherwise).

Official releases are never published automatically for every commit. Publication is performed by an authorized maintainer after reviewing the release contents and assets.

## Release package

`tools/New-ReleasePackage.ps1` creates deterministic Full and/or Lite packages named `FFmpeg-User-Manager-v<VERSION>-<Edition>-Windows-x64.zip`, plus `SHA256SUMS-v<VERSION>.txt`. Both contain `FFmpeg-User-Manager.bat`, `Start-FFmpegTUI.ps1`, `VERSION`, `README.md`, `CHANGELOG.md`, `LICENSE`, `NOTICE`, `THIRD-PARTY-NOTICES.md`, `config/`, `src/`, `docs/`, and the dependency manifest. Full additionally contains the manifest-verified FFmpeg/ffprobe and Assimp runtime files, original license texts, Gyan README, exact FFmpeg source revision and runtime-verified `-buildconf` metadata; Lite excludes all external runtime binaries and their runtime payloads. `BUILD-INFO.txt` records the common version, source commit and source-tree fingerprint. ZIP paths are ordinally sorted with fixed timestamps, and existing artifacts are never overwritten. Tests, `.git`, package caches, local output and `dist/` are excluded. No installer is provided.

The release workflow is manual-only on a Windows Server 2025 runner. It requires the maintainer to confirm acquisition of the exact manifest-pinned GPL-3.0 FFmpeg package through WinGet. Before creating a tag/release it verifies package checksums and metadata, checks bundled runtime/license contents, extracts both editions under a Unicode/spaced path, launches each with its supported PowerShell entry point, and performs an OBJ-to-GLB integration conversion from the Full Edition. Building locally never publishes or pushes anything.
