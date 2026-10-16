# Web Media Optimization Implementation Record

> **Execution record:** The original implementation plan was later extended by the owner to bundle Assimp, perform a full real-model conversion check and prepare the SemVer release. This record reflects the final authorized scope.

**Goal:** Add guided WebM optimization and size estimates, WebP image conversion with batching, and safe OBJ-to-GLB conversion using the bundled Assimp CLI.

**Architecture:** Keep WebM, estimation, and WebP workflows together in a focused workflow module. Keep Assimp executable discovery and selection separate from FFmpeg capability discovery, and pass all tool arguments through the existing structured process runner. Extend the shared job runner only where estimate-only work or an external process needs reusable progress and cleanup.

**Tech Stack:** Windows PowerShell 5.1 / PowerShell 7, existing TUI and FFmpeg modules, structured process arguments, current test harness, bundled Assimp 6.0.5 and reviewed Clang64 runtime packages.

**Spec:** User-provided task handoff (not stored in the repository).

## Global Constraints

- UI text is English; every option is numbered and described.
- Offer codecs and formats only when discovered in the installed FFmpeg build.
- Preserve source files; never overwrite existing outputs without confirmation.
- Keep source ASCII-only and compatible with both supported PowerShell versions.
- The owner later explicitly requested Assimp be obtained through the official MSYS2 package-manager route, audited, bundled and used by default. No runtime updater downloads or replaces libraries.
- Do not merge or push this task branch.

## Review Focus

- Synthetic or limited FFmpeg capabilities: unsupported choices must be absent or disabled with a reason.
- Very short media: sample windows must stay within duration and must not yield fabricated estimates.
- Failed or cancelled sample encodes: owned temporary files are cleaned and no final output is created.
- Transparent PNG input: alpha remains present in WebP output when the encoder supports it.
- OBJ files with absent MTL/textures: warn accurately and never claim materials or textures were preserved.
- Unicode and spaced paths: preserve paths as separate process arguments.

### Task 1: Size-estimate primitives and estimate-only job handling

**Files:** src/Workflows/WorkflowCommon.psm1, new src/Workflows/WebMediaOptimization.psm1, tests/Unit/NewTools.Tests.ps1.

**Interfaces:** Get-WebBitrateEstimate(DurationSec, VideoBitrateKbps, AudioBitrateKbps) returns method and bounded byte estimates. Get-WebSampleEstimate(SampleBytes, SampleDurations, DurationSec) returns low, midpoint, and high byte estimates from observed sample rates. An estimate-only job uses the shared progress/cancellation/cleanup runner without creating a user output.

- [x] Add tests for bitrate arithmetic, invalid durations/rates, three-sample bounds, and estimate-only result wording/cleanup.
- [x] Run focused unit tests and observe the expected missing-function / missing-job-behavior failures.
- [x] Implement the smallest helpers and shared estimate-job behavior.
- [x] Re-run focused unit tests; all assertions pass.

### Task 2: WebM conversion and WebP conversion/batching

**Files:** src/Workflows/WebMediaOptimization.psm1, src/Core/BatchProcessing.psm1 only if required, src/Core/App.psm1, src/Import-Modules.ps1, src/TUI/Theme.psm1, new tests/Smoke/WebMedia.Tests.ps1.

**Interfaces:** Consume Test-FFEncoder, Test-FFMuxer, Get-MediaInfo, Get-OutputSteps, Get-OutputFile, Invoke-FFJob, and Resolve-BatchOutputPath. Produce WebM single-file conversion, standalone video size estimation, WebP single/multi/folder conversion, and Start-WebMediaOptimizationWorkflow.

- [x] Add tests for dynamic VP9/AV1/WebP availability, profile args, resolution/audio mappings, estimate method labels, paths with spaces and Unicode, lossless WebP, and batch behavior.
- [x] Implement bitrate estimates and three representative short sample encodes; provide a numbered continue/change/cancel decision after an estimate.
- [x] Implement WebM profiles and measured input/output size summaries.
- [x] Implement WebP quality/lossless choices and image batching without changing originals.
- [x] Run focused unit and smoke suites; installed-codec cases execute and unavailable-codec states are covered.

### Task 3: Bundled Assimp and OBJ-to-GLB

**Files:** src/Workflows/WebMediaOptimization.psm1, src/Import-Modules.ps1, tests/Unit/NewTools.Tests.ps1, tests/Smoke/WebMedia.Tests.ps1.

**Interfaces:** Get-ThreeDToolStatus reports availability and selected Assimp executable. The settings-backed tool manager validates an explicitly selected existing CLI. Get-ObjDependencyReport returns present and missing MTL/texture sidecars. Build-ObjToGlbJob(State) creates a cancellable external-process job using separate input/output arguments and the Assimp glb2 exporter. Discovery and workflow live together in the feature module; no separate tool manager was needed.

- [x] Add tests for missing engine, safe argument construction, MTL/texture discovery, missing-texture warnings, and GLB validation.
- [x] Implement discovery/selection/requirements UI without installation or network access.
- [x] Implement Assimp CLI conversion with GLB2 output where supported and truthful result notes.
- [x] Bundle the verified Assimp CLI and runtime DLLs, retain all six package license texts, record package/archive and binary hashes, and include only runtime assets in release packaging.
- [x] Add bounded read-only stable-upstream and official MSYS2 package-manager update checks, including detection of package-only rebuilds; do not download or replace files at runtime.
- [x] Run a real OBJ + MTL + texture through the application wizard and job runner with the Assimp install directory absent from PATH; validate GLB 2.0 geometry, UVs, normals, materials and texture reference, report external textures honestly, and verify source hashes.

### Task 4: Integration, documentation, and full verification

**Files:** README.md, CHANGELOG.md, docs/Workflows.md, docs/Testing.md, docs/Architecture.md, docs/images/README.md only if screenshots are actually recaptured.

- [x] Verify main-menu numbering/action wiring, descriptions, module imports, and both PowerShell syntax levels.
- [x] Document formats, estimate limitations, WebP behavior, bundled Assimp requirements, package update policy, licenses and dependency restrictions.
- [x] Run .\tests\Run-Tests.ps1 on PowerShell 7 and Windows PowerShell 5.1; both report 1581 PASS / 0 FAIL / 0 UNVERIFIED, including the three formerly unverified Windows checks.
- [x] Review the full diff and run git diff --check. Commit after final docs validation; do not merge or push.

**Visual artifact status:** screenshots remain genuine historical captures. The menu screenshots predate the current menu entries and were not regenerated in this run; the image guide and README disclose that limitation. No fabricated screenshots were added.

**Dependency review:** Assimp 6.0.5 is the latest stable upstream release and `mingw-w64-clang-x86_64-assimp` 6.0.5-2 is the current official MSYS2 package observed on 2026-10-16. Package archives were signature/integrity checked before extraction. The runtime dependency tree and licenses are recorded in `External-Libraries/manifest.json`; no update is silently applied.

**Version:** After both full Windows suites passed, the compatible feature release was prepared as v0.2.0 (MINOR increment from v0.1.1). It is local only and has not been pushed or published.
