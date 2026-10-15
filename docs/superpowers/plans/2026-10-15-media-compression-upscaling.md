# Media Compression and Image Upscaling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans task-by-task. This execution is single-agent; do not delegate.

**Goal:** Extend the existing compression workflow with Simple and Advanced strategies for video, audio, and supported images, and add FFmpeg-only still-image upscaling.

**Architecture:** Keep codec argument generation in `FFmpegCommandBuilder.psm1`, capability filtering in `FFmpegCapabilities.psm1`, probing in `MediaProbe.psm1`, and input/output/job lifecycle in `WorkflowCommon.psm1`. Add one compression-planning module for preset mapping, target math, image quality search decisions, risk and measured metrics; extend the existing compressor and add a separate image-upscaling workflow that reuses `New-ScaleFilter` and the standard collision-safe job runner.

**Tech Stack:** Windows PowerShell 5.1 and PowerShell 7.x, FFmpeg/ffprobe already installed, project TUI and token-array process runner.

**Spec:** Owner-provided media-compression and image-upscaling handoff (source document is outside the repository).

## Global Constraints

- Keep UI text English and source files ASCII-only.
- Use installed FFmpeg capabilities; add no image engine or processing dependency.
- Never use a shell for user-controlled FFmpeg arguments; pass token arrays.
- Keep inputs untouched and require the existing explicit collision confirmation for outputs.
- Keep PowerShell 5.1 compatibility, existing navigation, and dynamic numbering/descriptions.
- Keep new release/version values untouched during unreleased development; use `[Unreleased]`.
- Do not merge this task branch to `main`.

## Review Focus

1. Source/output path equality and existing-output collision: reject source replacement and preserve explicit overwrite confirmation.
2. Tiny/invalid target sizes and 0/100% reduction: reject invalid math before an FFmpeg process starts.
3. Images with alpha and lossless input: preserve alpha/losslessness; never silently fall back to a lossy format.
4. Unknown duration, missing codecs, malformed probes, or unsupported encoder controls: hide/reject unsupported choices and show estimates as unavailable when they cannot be derived.
5. Very large custom dimensions and aspect mismatch: reject unsafe/downscale requests; preserve aspect by default and report measured dimensions/settings.

---

### Task 1: Central compression planning

**Files:** Create `src/Workflows/CompressionPlanning.psm1`; modify `src/Import-Modules.ps1`; test in new `tests/Unit/Compression.Tests.ps1`.

**Interfaces:**
- `Get-CompressionPreset(Encoder, Preset)` returns the encoder's quality mode/value or a bitrate-based fallback using the existing encoder profile.
- `Get-CompressionTargetBytes(SourceBytes, Mode, Value)` validates and returns an approximate target for Target Size or Target Reduction.
- `Get-CompressionBitratePlan(TargetBytes, DurationSec, AudioBps)` returns a container-overhead-adjusted total/video bitrate and a clear validation error when the audio budget or minimum video rate makes the target impossible.
- `Get-CompressionResultMetrics(SourceBytes, OutputBytes, TargetBytes)` returns actual saved bytes, reduction percentage, and target difference.
- Image-quality profile and bounded candidate selection remain in this module; lossless formats never switch to lossy implicitly.

- [x] Add failing arithmetic/preset/range tests, including 10 MB -> 8/5/1 MB for 20/50/90%, audio-budget rejection, zero/negative/100% reduction, and actual output metrics.
- [x] Run the focused unit file on Windows PowerShell 5.1 and PowerShell 7 and confirm expected RED failures.
- [x] Implement the shared helpers by reusing the existing encoder profile and `Get-TargetBitrateForSize`; expose them from the new module.
- [x] Run the same unit file on both runtimes and confirm GREEN.

### Task 2: Simple and Advanced compression

**Files:** Modify `src/Workflows/CompressMedia.psm1`, `src/Workflows/WorkflowCommon.psm1`, and `src/FFmpeg/FFmpegCommandBuilder.psm1`; test in `tests/Unit/Compression.Tests.ps1` and new `tests/Smoke/CompressionUpscaling.Tests.ps1`.

**Interfaces:** Consume the planning module from Task 1, existing media model, codec profiles, audio/video encode helpers, output steps, and `Invoke-FFJob`. Produce six Simple strategies (Light, Balanced, Strong, Maximum, Target Size, Target Reduction) plus capability-aware Advanced controls; support video, existing audio compression, and image formats whose installed encoders support the requested operation. Return a standard job with preflight summary/notes and measured size metrics.

- [x] Add failing tests for each Simple preset, target-size/reduction arithmetic, quality-risk notes, image lossless behavior/alpha, bounded JPEG/WebP quality attempts where available, and unsupported combinations.
- [x] Run the focused tests on both runtimes and confirm the expected failures.
- [x] Add the Simple/Advanced branch while retaining existing advanced video/audio options and preserving audio-only compatibility.
- [x] Build image compression from probed still-image inputs, preserving their source format; use bounded quality attempts only for lossy encoders and never switch a lossless source to lossy automatically.
- [x] Extend only opt-in compression jobs with actual bytes-saved, percent-reduced, and target-difference result metrics; leave other workflows' result screens unchanged.
- [x] Run focused unit and real-FFmpeg smoke tests on both runtimes; inspect produced streams, format, alpha where supported, and source hashes.

### Task 3: FFmpeg-only image upscaling

**Files:** Create `src/Workflows/UpscaleImage.psm1`; modify `src/Core/App.psm1`, `src/Import-Modules.ps1`, and `src/TUI/Theme.psm1` only if a new three-tier icon is necessary; test in `tests/Unit/Compression.Tests.ps1` and `tests/Smoke/CompressionUpscaling.Tests.ps1`.

**Interfaces:** `Get-UpscaleImageSteps`, `Get-UpscaleDimensions`, `Build-UpscaleImageJob`, and `Start-UpscaleImageWorkflow`. Use `Get-InputFileStep`, `Get-OutputSteps`, `New-ScaleFilter`, and `New-JobObject`; preserve source format, alpha when supported, and use Lanczos by default.

- [x] Add failing tests for 1.5x/2x/4x, custom dimensions, preserved aspect, invalid/same/downscale dimensions, alpha and path edge cases.
- [x] Run focused tests on both runtimes and confirm expected failures.
- [x] Implement the workflow and add a fully described numbered main-menu option; reuse an existing icon where suitable.
- [x] Run focused unit and real-FFmpeg smoke tests on both runtimes; inspect actual output dimensions, format, alpha and source hashes.

### Task 4: Documentation, regression, and commit

**Files:** Update `README.md`, `CHANGELOG.md`, `docs/Workflows.md`, `docs/Architecture.md`, `docs/Testing.md`, `docs/images/README.md` only where affected; update menu/UI tests and add the focused suites above.

- [x] Update documentation with Simple/Advanced distinctions, size-vs-quality semantics, estimate limits, lossless/lossy behavior, image upscaling limitations, and the new menu number.
- [x] Review every section of the handoff acceptance criteria; record unsupported runtime-dependent checks as UNVERIFIED.
- [x] Run focused suites and the complete `tests/Run-Tests.ps1` suite on Windows PowerShell 5.1 and PowerShell 7; update exact totals.
- [x] Run `git diff --check`, review all changed files, check ASCII/PowerShell compatibility/UI rules, and verify no unrelated changes.
- [x] Record the task's changes in `[Unreleased]`; leave `VERSION` unchanged and report that no history generator/NID/CID/RID source exists rather than inventing IDs.
- [x] Commit only task 3 on `codex/media-compression-upscaling`; do not merge or push.

**Visual artifact status:** the main menu will change. Recapture screenshots only from the real application; if this environment cannot capture it, leave the existing images untouched, disclose the stale menu inventory, and report screenshot recapture as UNVERIFIED.
