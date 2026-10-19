# FFmpeg User Manager v0.3.1

This backward-compatible PATCH release improves Windows Terminal launching and interactive TUI reliability since v0.3.0. It does not add a new workflow or change media-processing defaults.

## Fixes and improvements

- The Windows launcher opens Windows Terminal for ordinary and elevated launches when it is not already running inside Windows Terminal. It preserves the current terminal session when launched from one, prefers PowerShell 7 and falls back to Windows PowerShell 5.1. Direct invocation avoids the `cmd.exe` quoting failure involving a quoted working directory ending in a backslash. The owner confirmed elevated Windows Terminal launch.
- Interactive screens now detect terminal size changes while waiting for input and redraw without requiring an arrow key. The owner confirmed the repaired visual behavior.
- Wizard text prompts keep the active input line on the expected row within the managed screen frame. Confirming, navigating back, browsing, resizing and choosing Run Again no longer leave stale input paths or duplicate old prompt rows behind.
- Successful result screens show `Input:` and `Output:` paths together near the result summary, rather than leaving an old input path stranded at the bottom of the terminal.
- Regression coverage and documentation were updated for the launcher, idle resize handling, prompt/input lifecycle and result path layout.
- Full-edition release acquisition now resolves WinGet's renamed FFmpeg archive by the exact pinned SHA-256 (including its package/version subfolder), while rejecting missing or duplicate hash matches before license and runtime validation. The same handling protects the explicit bundled-runtime update flow.

## Editions and dependencies

The release uses the same Windows x64 editions and external runtime versions as v0.3.0. Full includes the verified, manifest-pinned FFmpeg/ffprobe and Assimp runtimes with their required license and attribution material. Lite excludes bundled external runtime binaries and resolves user-installed runtimes. No third-party library or runtime was added or updated for this release.

Both editions use the same source revision and version. The release package builder produces Full and Lite ZIPs plus a SHA-256 checksum file for publication as release assets. Verify each downloaded archive against the checksum before extraction.

## Verification and limitations

The owner confirmed the repaired TUI layout visually on 2026-10-19. Automated regression tests cover the input lifecycle, resize redraw logic, result summary, launcher command construction and WinGet's nested release archive path. Full Windows PowerShell 5.1.26100.9444 and PowerShell 7.6.5 suites each completed on 2026-10-20 with **1675 PASS, 0 FAIL, 0 UNVERIFIED**; details are recorded in [Testing.md](Testing.md).

The existing compatibility matrix and known FFmpeg 9.0.2 advisories from v0.3.0 remain applicable. This release does not change supported operating systems or claim additional platform compatibility. See [v0.3.0 release notes](Release-Notes-v0.3.0.md), [Testing](Testing.md) and [Licensing](Licensing.md).
