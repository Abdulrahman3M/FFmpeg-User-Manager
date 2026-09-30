# Versioning and Releases

## Standard

The project follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html): `MAJOR.MINOR.PATCH`.

| Increment | When | Example |
|---|---|---|
| **PATCH** | Bug fixes, small compatibility or reliability fixes, non-breaking internal fixes, documentation fixes tied to a release | `0.1.2` -> `0.1.3` |
| **MINOR** | New backward-compatible features: new workflows, menu functions, options, notable UI improvements. PATCH resets to `0` | `0.1.3` -> `0.2.0` |
| **MAJOR** | Breaking changes: removed or incompatible behavior, incompatible configuration changes, anything users must adapt to. MINOR and PATCH reset to `0` | `1.3.4` -> `2.0.0` |

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

* The application reads it (`Get-AppVersion`) and shows it in the header, on the FFmpeg Status screen and with `Start-FFmpegTUI.ps1 -Version`.
* The release archive name and the Git tag are derived from it (`FFmpeg-User-Manager-v<VERSION>.zip`, `v<VERSION>`).
* The README version badge is a static image and must equal `VERSION`; `tests/Unit/Static.Tests.ps1` fails when they differ, or when `VERSION` is not valid SemVer.
* Do not write the version number by hand anywhere else.

## Changelog process

[`CHANGELOG.md`](../CHANGELOG.md) follows Keep a Changelog. During development add user-relevant entries (not raw commit messages) under `## [Unreleased]`
in `Added / Changed / Fixed / Removed` (omit empty sections). On release, rename `[Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, open a fresh `[Unreleased]`, and keep older releases in reverse chronological order.

## Release checklist

1. Complete the intended release scope.
2. Run the tests on **both** runtimes on Windows: `powershell.exe -NoProfile -File .\tests\Run-Tests.ps1` and `pwsh -NoProfile -File .\tests\Run-Tests.ps1`.
3. Verify the launcher: double-click `FFmpeg-User-Manager.bat`, run it from another folder and from a path with spaces (the automated launcher tests cover the logic).
4. Update `CHANGELOG.md` (move `[Unreleased]` entries into the new version section with today's date).
5. Decide the SemVer increment from the rules above.
6. Update `VERSION`.
7. Verify the application shows the new version (`.\Start-FFmpegTUI.ps1 -Version`, header, Status screen).
8. Verify the README badge and any version mentions match `VERSION` (the static test checks this).
9. Commit the release changes (`Release vX.Y.Z`).
10. Create the tag: `git tag -a vX.Y.Z -m "FFmpeg User Manager vX.Y.Z"` and push it (`git push origin vX.Y.Z`).
11. Build the package: `.\tools\New-ReleasePackage.ps1` -> `dist\FFmpeg-User-Manager-vX.Y.Z.zip`; inspect its contents (launcher included; no `.git`, tests output, logs or secrets).
12. Prepare the GitHub Release titled `FFmpeg User Manager vX.Y.Z` from the tag, with the changelog section as notes (summary, features, fixes, breaking changes, update notes, known limitations) and attach the zip. **Publish only after the owner approves.**
13. Verify the downloadable archive starts correctly after extraction (including into a folder with spaces).
14. Confirm the repository visibility is unchanged (it stays Private unless the owner explicitly decides otherwise).

Official releases are never published automatically for every commit.

## Release package

`tools/New-ReleasePackage.ps1` creates `dist/FFmpeg-User-Manager-v<VERSION>.zip` containing only what end users need:
`FFmpeg-User-Manager.bat`, `Start-FFmpegTUI.ps1`, `VERSION`, `README.md`, `CHANGELOG.md`, `config/`, `src/`, `docs/`. Tests, `.git`, local output and `dist/` are excluded. No installer is provided.
