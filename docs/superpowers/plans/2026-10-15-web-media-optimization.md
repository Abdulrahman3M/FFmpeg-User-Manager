# Web Media Optimization Implementation Plan

> **Execution:** Inline in the current session; use TDD and commit task-sized changes. The user-provided handoff is the authoritative specification.

**Goal:** Add guided WebM optimization and size estimates, WebP image conversion with batching, and safe OBJ-to-GLB conversion through an existing Assimp CLI installation.

**Architecture:** Keep WebM, estimation, and WebP workflows together in a focused workflow module. Keep Assimp executable discovery and selection separate from FFmpeg capability discovery, and pass all tool arguments through the existing structured process runner. Extend the shared job runner only where estimate-only work or an external process needs reusable progress and cleanup.

**Tech Stack:** Windows PowerShell 5.1 / PowerShell 7, existing TUI and FFmpeg modules, structured process arguments, current test harness. No new runtime dependency is installed or bundled.

**Spec:** User-provided task handoff (not stored in the repository).

## Global Constraints

- UI text is English; every option is numbered and described.
- Offer codecs and formats only when discovered in the installed FFmpeg build.
- Preserve source files; never overwrite existing outputs without confirmation.
- Keep source ASCII-only and compatible with both supported PowerShell versions.
- Do not download or install Assimp; detect/select an existing executable until an owner-approved source and package route exist.
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

### Task 3: Existing Assimp discovery and OBJ-to-GLB

**Files:** src/Workflows/WebMediaOptimization.psm1, src/Import-Modules.ps1, tests/Unit/NewTools.Tests.ps1, tests/Smoke/WebMedia.Tests.ps1.

**Interfaces:** Get-ThreeDToolStatus reports availability and selected Assimp executable. The settings-backed tool manager validates an explicitly selected existing CLI. Get-ObjDependencyReport returns present and missing MTL/texture sidecars. Build-ObjToGlbJob(State) creates a cancellable external-process job using separate input/output arguments and the Assimp glb2 exporter. Discovery and workflow live together in the feature module; no separate tool manager was needed.

- [x] Add tests for missing engine, safe argument construction, MTL/texture discovery, missing-texture warnings, and GLB validation.
- [x] Implement discovery/selection/requirements UI without installation or network access.
- [x] Implement Assimp CLI conversion with GLB2 output where supported and truthful result notes.
- [x] Run focused tests; end-to-end conversion is reported UNVERIFIED because Assimp is not installed here.

### Task 4: Integration, documentation, and full verification

**Files:** README.md, CHANGELOG.md, docs/Workflows.md, docs/Testing.md, docs/Architecture.md, docs/images/README.md only if screenshots are actually recaptured.

- [x] Verify main-menu numbering/action wiring, descriptions, module imports, and both PowerShell syntax levels.
- [x] Document formats, estimate limitations, WebP behavior, optional Assimp requirements, and dependency restrictions.
- [x] Run .\tests\Run-Tests.ps1 on PowerShell 7 and Windows PowerShell 5.1; report every UNVERIFIED result honestly (1386 PASS / 0 FAIL / 3 UNVERIFIED on each).
- [x] Review the full diff and run git diff --check. Commit after final docs validation; do not merge or push.

**Visual artifact status:** the main-menu UI changed, but the real application screenshots were not recaptured in this execution environment. Existing images remain untouched and their outdated menu inventory is now explicitly disclosed in the image documentation and README. Per repository rules, this keeps screenshot validation outstanding.
