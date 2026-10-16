# Testing

## Compatibility matrix

| Environment | Result (actual, from the logs) | Run / commit |
|---|---|---|
| Windows PowerShell 5.1.26100.9444 on the local Windows host | **1581 PASS, 0 FAIL, 0 UNVERIFIED** | full `tests/Run-Tests.ps1`, 2026-10-16; loopback checks run with the required local-network permission |
| PowerShell 7.6.5 on the local Windows host | **1581 PASS, 0 FAIL, 0 UNVERIFIED** | full `tests/Run-Tests.ps1`, 2026-10-16; loopback checks run with the required local-network permission |
| Windows PowerShell 5.1 on a Windows runner | **1323 PASS, 0 FAIL, 1 UNVERIFIED** | GitHub Actions run [38545320395](https://github.com/Abdulrahman3M/FFmpeg-User-Manager/actions/runs/38545320395), renderer commit `704fec00` |
| PowerShell 7 on a Windows runner | **1323 PASS, 0 FAIL, 1 UNVERIFIED** | GitHub Actions run [38545320395](https://github.com/Abdulrahman3M/FFmpeg-User-Manager/actions/runs/38545320395), renderer commit `704fec00` |
| PowerShell 7.4 on Linux (FFmpeg 6.1, Wine for the `.bat` tests) | **1261 PASS, 0 FAIL, 5 UNVERIFIED** | local run, commit `3f96e26` |

Full local verification after the library bundle and integration (2026-10-16): Windows PowerShell 5.1.26100.9444 and PowerShell 7.6.5 each completed `tests/Run-Tests.ps1` with **1581 PASS, 0 FAIL, 0 UNVERIFIED**. This includes the three checks previously reported as UNVERIFIED: the missing-ffprobe PATH sandbox uses isolated file copies; loopback HTTP inspect/save tests pass through the bounded raw TCP server when local-network access is permitted; and a live FFmpeg child exits when its parent PowerShell process is terminated. Both runtimes also completed actual OBJ-to-GLB conversion through the workflow, validated the GLB 2.0 geometry/material/texture references, and confirmed that source OBJ/MTL/texture files were unchanged. The app reports when a texture remains external instead of claiming that it is embedded.

History of the Windows work (same suite): run #12 established 1263 PASS / 0 FAIL / 1 UNVERIFIED under both Windows runtimes at commit `3f96e26`; run #3 (first diagnosable run) PowerShell 7 1034 PASS / 35 FAIL / 3 UNVERIFIED, PowerShell 5.1 893 PASS / 40 FAIL / 5 UNVERIFIED -> run #12 above. The causes are listed in the investigation table below.

The three-check result above supersedes the earlier 2026-10-15 full run (1386 PASS / 0 FAIL / 3 UNVERIFIED), which preceded the PATH-copy, loopback, process-job and Assimp end-to-end verification fixes. The 0.2.0 version consistency, release-package contents and post-bump static checks were also rerun successfully after preparing the release. Physical rapid-arrow/no-flicker behavior still requires Windows Terminal and classic conhost observation.

Remaining UNVERIFIED items (never reported as PASS):

| Environment | Test | Why it cannot run in the cloud | How to verify locally |
|---|---|---|---|
| Linux | parent process exits while a job runs | Windows Job Objects are not available; the Windows integration test covers the supported Windows behavior | no Linux process-lifetime guarantee is claimed |
| Linux | screen / webcam / microphone recording | needs Windows capture devices (gdigrab, dshow); parsing and command building are unit tested | `tools/Test-WindowsLocal.ps1` list item 5 on a Windows PC with devices |
| Linux | read permission denied | the account is root; on Windows this check **ran and passed** on the runner | run the suite as a standard user on Linux |
| Linux | two double-click launcher checks | Wine's `cmd` does not populate `%CMDCMDLINE%`; on Windows both **ran and passed** | none needed on Windows |

Not covered by any automated run (no result is claimed): rendering in a real **Windows Terminal** / classic console (emoji vs symbol icons, font), real `winget install/upgrade` of FFmpeg (mocked in the suite; installs need the user's consent), real recording devices. Use
`.\tools\Test-WindowsLocal.ps1` on a Windows PC: it runs the suite under every installed PowerShell edition, prints what the application detects (Segoe UI Emoji, terminal, icon set) and lists the manual checks.

Windows-only behavior that could not be exercised on Linux: native file/folder picker, `explorer.exe /select`, real `winget list/upgrade/install` text output
(the parser is exercised with sample text and mocks), legacy-console ANSI enabling (P/Invoke), Windows path/lock/permission errors.

## Windows investigation (root causes found by running the suite on a real Windows runner)

The first runs of the suite on GitHub's Windows runner (FFmpeg 9.0.2 from Chocolatey, Windows PowerShell 5.1 and PowerShell 7) failed in 35-40 places. Each failure was traced to evidence in the run logs; nothing was
"fixed" by weakening a check. The confirmed causes:

| # | Symptom on Windows | Confirmed root cause (evidence) | Where | Fix |
|---|---|---|---|---|
| 1 | About 20 workflow tests failed (loudness normalization, noise reduction, silence removal, subtitles, GIF dithering, rotate, waveform ...) and the menus said "requires the afftdn filter (not in this FFmpeg build)" | **Product bug.** FFmpeg 9 prints two flag columns in `ffmpeg -filters` (` TS afftdn  A->A`) where FFmpeg 6-8 print three. The parser found 0 filters (`caps: enc=221 mux=184 filt=0` in the log, while `ffmpeg -filters` listed 535) | `ConvertFrom-FFFilterList` in `src/FFmpeg/FFmpegCapabilities.psm1` | The third flag column is optional; regression test with the FFmpeg 9 format in `Core.Tests.ps1` |
| 2 | "H.265 with a chosen quality level" ended with `Scripted provider exceeded the call limit`; `Workflows1.Tests.ps1` then crashed with "property 'streams' cannot be found" | **Test bug, proven by an isolated reproduction** (`tests/Repro/Repro-H265.ps1`, workflow `repro`). The app lists `h264_mf` (Media Foundation, usable on the runner) as option 04, which shifted `libx265` to 05. The old test computed the position from a list WITHOUT hardware encoders, so it chose 04: the wizard then showed "Quality level - This encoder does not support quality-based mode" (disabled) and the scripted key `02` did nothing, 60 times. The `Workflows1` crash was only the consequence (the output file did not exist) | `tests/Smoke/Workflows1.Tests.ps1` | The codec is chosen by its label `{#[libx265]}`, like a user would; the old and new answers are kept side by side in the repro |
| 3 | `Audio to Video` (black screen) sometimes produced a 5.8 s video for a 4 s sound | **Product bug.** The black/picture source is endless and only `-shortest` bounded it; since FFmpeg 7 the encoder threads can run ahead of the audio end, so the result is nondeterministic | `Build-AudioVisualJob` in `src/Workflows/ImagesAndVisuals.psm1` | The source is bounded explicitly with the audio duration (`color=...:d=` / `-t`); test checks the command and the duration |
| 4 | Launcher: "a failing run is reported and pauses" never printed the message | **Test bug on real `cmd`.** The stub was a `.cmd`; a batch file started from a batch file without `call` never returns to the caller (real `pwsh.exe` does). Separately the double-click detection echoed the raw command line, so `&` in a folder name was executed as a command | `FFmpeg-User-Manager.bat`, `tests/Smoke/Launcher.Tests.ps1` | The detection uses delayed expansion in a small block and strips quotes first; on Windows the stub is a compiled executable (`csc.exe` that ships with Windows) |
| 5 | Unicode icon test: emoji missing in captured output | **Product bug.** The console was switched to UTF-8 only when output was not redirected, so a forced emoji set reached a parent process through the OEM code page | `Get-IconTier` in `src/Core/Environment.psm1` | UTF-8 output is set whenever the host is Windows |
| 6 | Windows PowerShell 5.1: test files with Cyrillic/Arabic/box-drawing text were misread; `Static`/`UiRules` crashed with "Access denied" on folders | 5.1 reads BOM-less files as ANSI; `Get-ChildItem -LiteralPath ... -Include` returns directories in 5.1 | `tests/**/*.ps1` | UTF-8 BOM on test files that contain non-ASCII text; file-only enumeration |
| 7 | "winget missing" / status tests behaved differently | The runner has a real winget; `Get-WingetPath` ignored the test hook | `Get-WingetPath` in `src/FFmpeg/FFmpegManager.psm1` | The hook is honoured; tests hide winget explicitly |
| 8 | `ffmpeg without ffprobe` test; Windows file names | Chocolatey's `ffmpeg.exe` is a shim that only works next to its install folder; `"` and `:` are illegal in Windows file names | `tests/Smoke/App.Tests.ps1`, `Workflows2/3` | The real executable is copied; those characters are skipped on Windows |
| 9 | `ffmpeg without ffprobe` PATH test was UNVERIFIED | Creating a hardlink was denied by NTFS/workspace access policy even though copying files was permitted | `tests/Smoke/App.Tests.ps1` | The isolated test directory now receives copies of the executable and runtime DLLs; the test passes on Windows |
| 10 | Local HTTP stream tests were UNVERIFIED | `HttpListener` needed an HTTP URL reservation, and the workspace sandbox separately denied loopback client connections | `tests/TestHelpers.ps1`, `tests/Smoke/Workflows4.Tests.ps1` | A bounded raw `TcpListener` server avoids URL ACLs; host-level integration execution proved inspect and save-stream workflows |
| 11 | Abrupt terminal close could orphan FFmpeg | `finally` cleanup is not guaranteed when the parent process is force-terminated | `src/Core/ProcessRunner.psm1`, `src/FFmpeg/FFmpegProgress.psm1` | FFmpeg is assigned to a Windows kill-on-job-close process job; the integration test confirmed the child exits when its PowerShell parent is killed |
| 12 | Scripted smoke flows failed before reaching their scenarios | The TUI provider runs in the input module's scope and could not resolve a helper defined only in the test script scope | `tests/TestHelpers.ps1` | The test-only macro resolver is available to the provider scope; regression suites now reach their intended assertions |

Method that was used (and should be used again): one isolated reproduction per failure (`tests/Repro`, run by the `repro` workflow, which prints every wizard screen, its options and the keys sent), proof from the logs,
then one deliberate full run. The full-suite workflow is started by hand (Actions tab -> *tests* -> *Run workflow*), by pull requests and by pushes to `main`; it no longer starts on every branch push.
The full `suite.log` of each run is kept as an artifact (`suite-log-powershell`, `suite-log-pwsh`).

## Running

```powershell
# everything (both suites)
.\tests\Run-Tests.ps1
# only fast unit tests / only workflow smoke tests / filter by file name
.\tests\Run-Tests.ps1 -Suite Unit
.\tests\Run-Tests.ps1 -Suite Smoke
.\tests\Run-Tests.ps1 -Suite Smoke -Filter Workflows2
# run once per runtime
powershell.exe -NoProfile -File .\tests\Run-Tests.ps1
pwsh -NoProfile -File .\tests\Run-Tests.ps1
```

The runner needs no Pester. It prints `[PASS] / [FAIL] / [UNVERIFIED]` per check and exits `1` when anything failed. `UNVERIFIED` is used only when a check cannot
be provoked in the current environment (with the reason printed). FFmpeg + ffprobe must be installed.

## Files

| Suite | File | Covers |
|---|---|---|
| Unit | `Core.Tests.ps1` | validation, paths, argument quoting round-trips with awkward file names, injection safety, filter escaping proven against the real filter parser, encoders, atempo chains, progress parsing, capability parsing/discovery, ffprobe model |
| Unit | `Manager.Tests.ps1` | detection (installed / missing / no ffprobe / stale PATH), bundled/custom/system pair selection, manifest-driven runtime self-check for executables, encoders, filters, version and architecture, update states with mocked winget text, install/update UI, failure and unmanaged cases |
| Unit | `ExternalLibraries.Tests.ps1` | canonical dependency manifest schema, stable version/package metadata, architecture/license/hash/source validation, and fail-closed invalid metadata checks |
| Unit | `Tui.Tests.ps1` | menu (two-digit numbers `01`-`99`, `100`+, prefix waiting, Enter, arrows, Esc, Ctrl+C, scrolling, disabled items, no letter keys), main-menu definition (31 numbered options, Exit last), narrow/normal/wide layout, the three icon tiers (emoji, console-safe symbol, ASCII; symbol glyphs are checked against WGL4), theme centralization, line editor, wizard (steps, Back, conditions, Goto, multi-choice, file list, summary menu), dialogs |
| Unit | `Compression.Tests.ps1` | target-size/reduction math, quality-risk assessment, codec-aware presets, bounded image-quality candidate planning and target tolerance, duration-aware choices, actual result metrics, Simple strategy labels and workflow wiring |
| Unit | `Upscale.Tests.ps1` | 1.5x/2x/4x/custom-resolution bounds, aspect-preserving scaling, invalid/downscale/overflow rejection |
| Unit | `Static.Tests.ps1` | version (`VERSION` is SemVer, README badge/CHANGELOG/tags consistent), README/docs link and image check, README commands vs real launcher switches, release-package contents, secret and machine-path scan, `.gitignore`, parse check, no `Invoke-Expression`, no network/telemetry code, no shell launching, no recursive deletion, PS-5.1 syntax/API scan, ASCII-only sources, closure rule, module/wiring/documentation presence |
| Unit | `NewTools.Tests.ps1` | icon-tier decision table (Windows Terminal, conhost, redirected, Linux, overrides), custom-command parsing/refusals, DirectShow and analysis parsers, chapters/metadata, stream destinations, slideshow/sequence helpers, Assimp license/hash inventory, and quoted Unicode UTF-8 MTL/texture dependency resolution |
| Smoke | `WebMedia.Tests.ps1` | real FFmpeg WebM/WebP conversion, sample and bitrate estimates, bundled Assimp UI and actual OBJ-to-GLB conversion from a Unicode/spaced path, GLB geometry/material/texture-record validation, honest external-texture warning and source-hash checks |
| Unit | `UiRules.Tests.ps1` | static UI rules by syntax tree: no letter keys or hand-written keys, every `New-Choice` has a description, every Yes/No question describes both answers, every question has help and typed questions an example, no local variable that collides with a parameter |
| Smoke | `Workflows1-5.Tests.ps1` | every workflow end-to-end through the real wizard with real FFmpeg; outputs are verified with ffprobe (codec, size, fps, duration, streams) and, where meaningful, by measurement (volume, LUFS, brightness/saturation, PSNR); `Workflows5` covers remux/streams, metadata/chapters, slideshows, audio effects, video enhancement, analysis, batch inventory/queue/collision handling, advanced tools and stream output |
| Smoke | `Failures.Tests.ps1` | bad input, output-name rules, unsupported combinations, non-zero FFmpeg exit + details + retry, cancellation, source protection, simulated unwritable folder |
| Smoke | `Launcher.Tests.ps1` | `FFmpeg-User-Manager.bat` with a real `cmd` interpreter (native on Windows, Wine's `cmd.exe` on Linux): runtime preference (pwsh.exe over powershell.exe), fallback, no-PowerShell error, missing entry script, paths with spaces/parentheses/ampersand, argument pass-through, exit-code propagation. Double-click detection (`%CMDCMDLINE%`) is `UNVERIFIED` under Wine |
| Smoke | `App.Tests.ps1` | launcher in child processes: startup/exit codes, non-interactive refusal, ANSI vs non-ANSI, terminal restoration after normal exit and after an error, missing/stale FFmpeg with a real PATH sandbox, main-menu integration, error containment |
| Smoke | `CompressionUpscaling.Tests.ps1` | real FFmpeg video/audio/image compression, target preview/risk and measured results, bounded JPEG search including an unreachable target, alpha-preserving PNG/WebP compression/upscaling at 1.5x/2x/4x/custom resolution, source hashes and output validation |

## Launcher tests and Wine

`tests/Smoke/Launcher.Tests.ps1` runs the batch file in a sandbox with dummy `pwsh.exe` / `powershell.exe` files on `PATH` (detection) and a `.cmd` stub selected through `FFUM_POWERSHELL` (execution and exit codes). On Windows the stub is a small executable compiled with the .NET Framework compiler that ships with Windows, because a batch file started from a batch file without `call` never returns to the caller.
On Windows it uses `cmd.exe`; on Linux it uses Wine if installed (`apt install wine64`), otherwise the cases are reported `UNVERIFIED`. Running the real PowerShell application through the launcher on Windows remains a manual check.

## Fixture strategy

No binary fixtures are committed. Tiny clips are synthesized with FFmpeg `lavfi` sources at run time in a temp folder that is removed afterwards
(see `tests/Fixtures/README.md`). Names contain spaces, `( ) & '`, Arabic and Cyrillic.
Package-manager operations are **mocked** (`Set-FFManagerHooks`); nothing on the machine is installed, updated or removed. Network-stream tests use a bounded raw TCP server on 127.0.0.1.

## How the UI is driven

`Invoke-Ui` feeds a fixed key string; `Invoke-Flow` answers on demand from rules that match the text of the current screen (`New-Rule 'Prompt' 'keys'`), pressing Enter (the default)
otherwise. Output is captured in the renderer's buffer, so assertions read what the user would see. Options are typed as numbers (`08`); the test helpers also understand
**key macros** that are resolved against the current screen - `{#label}` types the number of the option whose text contains *label*, `{#LAST}` the last number of the list - so tests do not depend on
the position of an option. `New-FileListRules` fills a "Files" question (type paths, *Add another file*, *Done*).

## Manual TUI checklist (real terminal)

1. Windows Terminal + PowerShell 7 and Windows PowerShell 5.1: start, arrow keys, typing numbers (`01`, `07`, `30`, `31`), Esc/Back, Ctrl+C.
2. Legacy console host (conhost, double-click the `.bat`): every option must show a **symbol icon** (never a blank, a box or an ASCII tag); colors fall back; still readable. Also check Windows Terminal (emoji icons), the Consolas, Lucida Console and raster fonts, and `FFTUI_ICONS=ascii`. **Not yet verified on Windows.**
3. Resize the window narrow (< 60 columns) and short (< 20 rows) while on the menu and in a wizard.
4. Paste a quoted path with spaces / Unicode; press `Tab` for the native picker.
5. Run a long job, press `Esc`, answer `02` (No, continues) then `Esc`, `01` (Yes, stops); confirm ffmpeg.exe is gone in Task Manager.
6. After quitting (and after a forced error) the cursor is visible and the scrollback of the terminal is intact.
7. Main menu `29` (Maintenance) -> `02` (check for updates) with and without internet; on a machine with FFmpeg from winget and one with a manual copy. Check Web Media Optimization at `30` and Exit at `31`.
8. `winget uninstall Gyan.FFmpeg`, start the app: install flow (needs internet).
9. Record / Capture (`24`): screen, webcam and microphone recordings need Windows capture devices; parsing and command building are unit tested but the recordings themselves are **unverified** until run on Windows.
