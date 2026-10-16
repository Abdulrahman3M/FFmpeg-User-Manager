# Full Edition Runtime and Releases Implementation Plan

> **For agentic workers:** Implement task-by-task in this order; every task ends with its focused tests. Do not merge to `main` or publish a GitHub Release.

**Goal:** Deliver reproducible Full and Lite Windows packages with deterministic runtime selection, verified bundled dependencies, safe update/rollback behavior, and truthful compatibility/licensing documentation.

**Architecture:** Extend the existing `External-Libraries` inventory and `FFmpegManager` rather than creating competing runtime registries. Resolve Full-bundled FFmpeg/ffprobe first, then an explicit per-user/custom location, then the existing system discovery path; keep Lite packages free of runtime binaries. Build both editions from one source revision, validate package contents and runtime behavior, and record checksums.

**Tech Stack:** Windows PowerShell 5.1 and PowerShell 7, existing PowerShell modules/test harness, winget package metadata/download, JSON manifests, ZIP release packages.

**Spec:** `D:/Test/02 │ Assistance Projects/FFmpeg User Manager │ Archive/FUM │ Stages Completed/FUM │ Stages Completed │ 2026.10/FUM 2026.10.16-01/IMPLEMENTATION-HANDOFF_FFmpeg-User-Manager_Full-Edition_Runtime-and-Releases.md`

## Global Constraints

- Preserve PowerShell 5.1 and 7.x compatibility; keep source code ASCII-only.
- Keep FFmpeg capabilities dynamic; verify actual encoders, filters, ffprobe, Assimp, architecture, and Unicode/spaced paths.
- Never download executables directly from URLs; use the vetted package-manager route and verify package integrity.
- Stage candidates, test before activation, preserve/restore the known-good runtime on failure, and require explicit user consent for updates.
- Ship required third-party notices/licenses and source information; do not alter the root Apache-2.0 `LICENSE`.
- Full and Lite packages share one canonical app version/source revision; never publish or merge automatically.
- Follow root `AGENTS.md` dependency-aware artifact review and run the full suite on Windows PowerShell 5.1 and PowerShell 7.

## Review Focus

- Bundled runtime vs custom/system discovery and stale PATH entries — unit tests assert source precedence and that invalid bundled files fall through safely.
- Unicode and spaced install roots — package smoke tests extract under a path containing spaces and non-ASCII characters and invoke both runtimes.
- Failed runtime replacement, including a failed second rename or post-activation check — transaction tests prove the known-good files remain/restored and staging is cleaned.
- Missing or corrupt license/runtime manifest entries — package validation rejects incomplete Full packages and confirms Lite contains no external runtime binaries.
- A newer upstream version without an available verified package — update status remains informational/unknown and no package is installed or activated.

---

### Task 1: Canonical dependency inventory and runtime resolution

**Files:** `External-Libraries/manifest.json`, `src/Core/ExternalLibraries.psm1`, `src/FFmpeg/FFmpegManager.psm1`, `tests/Unit/Manager.Tests.ps1`, new `tests/Unit/ExternalLibraries.Tests.ps1`.

**Interfaces:** `Get-BundledFFmpegPath()` and `Get-BundledFFprobePath()` return an absolute path or `''`; `Find-FFmpegInstallation()` and `Get-FFmpegInfo()` expose `Source` (`Bundled|Custom|System`) and `Directory` with the validated pair. `FFTUI_FFMPEG_PATH` explicitly selects a custom directory. Reuse `Get-AppRoot`, `Get-ExternalLibraryManifest`, and existing FFmpeg detection. Record exact version, x64 architecture, source/package identity, license, checksums, acquisition date, and platform evidence in the one manifest.

- [x] Add failing tests named `bundled FFmpeg and ffprobe take precedence over configured custom and system paths`, `custom FFmpeg directory is used when the bundled pair is absent`, `system pair is used when Full runtime and custom path are absent`, and `an incomplete or uncallable higher-priority pair is rejected without mixing ffprobe from another runtime` in `tests/Unit/Manager.Tests.ps1`.
- [x] Add failing manifest tests named `manifest identifies pinned FFmpeg and Assimp packages`, `manifest records required architecture, sources, licenses, hashes and platform evidence`, and `unsupported schema or invalid dependency metadata is rejected` in `tests/Unit/ExternalLibraries.Tests.ps1`.
- [x] Run focused tests and confirm the expected failures.
- [x] Implement bundled path resolution, explicit custom path resolution and source-aware runtime detection in the existing runtime modules; do not mix tools from different source tiers. Keep missing-runtime install/update behavior for Lite unchanged.
- [x] Run focused Manager and ExternalLibraries tests under Windows PowerShell 5.1 and PowerShell 7.6.5 (Manager: 48 PASS each; ExternalLibraries: 11 PASS each).

### Task 2: Full-runtime self-check and capability/Assimp verification

**Files:** `src/FFmpeg/FFmpegManager.psm1`, `src/FFmpeg/FFmpegCapabilities.psm1` only if needed, `src/Workflows/WebMediaOptimization.psm1` only if needed, `tests/Unit/Manager.Tests.ps1`, `tests/Smoke/WebMedia.Tests.ps1`, `docs/Testing.md`.

**Interfaces:** Add `Test-FFmpegRuntimeRequirements()` returning `{ Ready; MissingExecutables; MissingEncoders; MissingFilters; Version; Architecture; Source }`; consume existing `Test-FFToolCallable`, `Initialize-FFCapabilities`, `Get-ThreeDToolStatus`, and OBJ-to-GLB validation. Required feature names come only from the approved handoff's acceptance list and are checked against the actual build; do not create a hardcoded universe or duplicate Assimp resolution.

- [x] Add failing tests named `Full runtime self-check reports missing ffmpeg and ffprobe`, `Full runtime self-check discovers required encoders and filters from the executable build`, `Full runtime self-check reports architecture/version/source`, and `Full runtime self-check identifies unavailable capabilities without claiming readiness`.
- [x] Add/extend a smoke case proving `bundled Assimp OBJ-to-GLB conversion preserves supported UVs, normals, materials and reports external texture links honestly from a Unicode/spaced path`; the current CLI build writes a URI-linked texture rather than embedding it, and the app already warns that those images must stay beside the output.
- [x] Run the focused tests to prove they fail for missing requirements.
- [x] Implement only the necessary runtime self-check/reporting changes and fix the PowerShell 5.1 quoted UTF-8 MTL-path regression exposed by the end-to-end test.
- [x] Run Manager (52 PASS), ExternalLibraries (12 PASS), NewTools (148 PASS), and Web Media (17 PASS) under Windows PowerShell 5.1 and PowerShell 7.6.5; all focused runs had 0 FAIL and 0 UNVERIFIED.

### Task 3: Consent-based transactional dependency updates

**Files:** `src/Core/ExternalLibraries.psm1`, `src/Core/App.psm1`, `src/FFmpeg/FFmpegManager.psm1`, `tests/Unit/Manager.Tests.ps1`, new `tests/Unit/ExternalLibraries.Tests.ps1`, `tests/Unit/Static.Tests.ps1`.

**Interfaces:** Reuse bounded official upstream checks and the existing token-array process runner. Use its streaming callback for download progress and cancellation because the x64 archive is large; activate via same-volume rename with rollback. Keep startup checks read-only and updates user-initiated.

- [x] Add mock-driven failing tests for candidate verification, declined update, success, each activation failure/rollback, and cleanup without deleting the active runtime.
- [x] Run focused tests and confirm the expected failures.
- [x] Implement staged download, hash/source/version checks, candidate smoke/capability checks, activation/rollback, and safe old-version cleanup.
- [x] Add a numbered, described consent flow for bundled runtime updates; preserve existing non-fatal behavior on offline/unknown status.
- [x] Run focused tests and static safety/PowerShell-5.1 checks.

Task 3 verification (2026-10-16): ExternalLibraries passed with 27 PASS / 0 FAIL / 0 UNVERIFIED on PowerShell 5.1.26100.9444 and PowerShell 7.6.5. Static safety/compatibility passed with 198 PASS / 0 FAIL / 0 UNVERIFIED on both. Live upstream DNS and real WinGet acquisition were not available/performed; the official installer manifest format was checked, parsing and hash verification are covered with fixtures, and no system package was installed or updated. Assimp checks remain read-only because a compatible package replacement transaction and dependency-license review are not approved/configured.

### Task 4: Full/Lite reproducible packaging and release validation

**Files:** `tools/New-ReleasePackage.ps1` or a focused packaging helper, `.github/workflows/release.yml`, `tests/Unit/Static.Tests.ps1`, new `tests/Unit/ReleasePackage.Tests.ps1`, `.gitignore`.

**Interfaces:** Preserve a compatibility entry point for the existing package command. Add `Full`, `Lite`, and `Both` modes; support an explicit verified runtime source/cache and package-manager acquisition when requested. Generate exact Full/Lite asset names and SHA-256 sums; reject missing runtime/license files, stale versions, architecture mismatch, unapproved extra files, and forbidden development content.

- [ ] Add failing package tests for exact filenames, edition contents, common source/version, hash output, clean paths, stable ordering/timestamps, and runtime validation.
- [ ] Run the package tests and confirm the expected failures.
- [ ] Implement the edition builder and validation using the existing packager where practical.
- [ ] Update the manual release workflow to validate/attach both assets and their checksums; do not run it or publish from this task.
- [ ] Build and inspect both local packages, then extract and smoke-test them from a Unicode/spaced directory.

### Task 5: Governance, licensing, compatibility, docs, and SemVer release prep

**Files:** `AGENTS.md`, `External-Libraries/README.md`, `NOTICE`, new `THIRD-PARTY-NOTICES.md` and FFmpeg `SOURCE.txt`/license texts as required, `docs/Licensing.md`, `docs/Testing.md`, `docs/Versioning-and-Releases.md`, `docs/Release-Notes-v*.md`, `README.md`, `CHANGELOG.md`, `VERSION`, `.github/workflows/tests.yml`.

- [ ] Add static failing checks for required governance, Full/Lite policy, release-note structure, compatibility evidence, and synchronized version references.
- [ ] Record observed OS/runtime support as `PASS`, `FAIL`, `UNVERIFIED`, or `N/A`; make no unsupported Windows/Linux claims.
- [ ] Document exact runtime licenses, obligations, ownership, sources, hashes, and delivered package contents; leave Apache `LICENSE` unchanged.
- [ ] Update README, help, docs, release notes, changelog, CI, checksums, and file trees only where affected.
- [ ] Prepare the backward-compatible feature release under the repository's SemVer rules; synchronize canonical `VERSION`, badge, notes, and references in the same change.
- [ ] Run both full Windows PowerShell suites, focused package/runtime checks, review the acceptance criteria, and commit the verified task changes without publishing or merging.
