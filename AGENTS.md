# AGENTS.md - Working rules for AI agents

These rules apply to every AI agent (and human contributor) changing this repository.
Read this file **before** starting any task.

## 1. Before you change anything
1. Read this file and the task's handoff/instructions completely.
2. **Investigate first:** inspect the current structure, code, tests and docs that relate to the task - only those.
3. Prefer the project's real structure over assumptions in a handoff; keep the goal and requirements intact.
4. Reuse the canonical implementation (central theme, renderer, wizard, command builder, runner). Do not create duplicates.
5. If task files are split into phases, execute them strictly in order, one at a time.

## 2. Doing the work
* Implement the task **fully** - analysis or a plan alone is not a deliverable.
* Preserve existing, unrelated behavior. No unnecessary refactors or rewrites. Do not modify unrelated code you happen to notice; report it instead.
* Ordinary decisions that can be settled safely by inspecting the project are yours. Stop and ask the owner **only** for a real conflict that cannot be resolved safely - state the conflict, the options, the impact of each, and the exact decision needed.
* Never commit secrets, tokens, personal data or machine-specific absolute paths.

## 3. Product rules (from the approved design)
* UI text is English. Windows PowerShell 5.1 **and** PowerShell 7.x must keep working; PowerShell 7 must never become mandatory.
* No `Invoke-Expression`, no shell strings built from user input: FFmpeg arguments are token arrays (see `FFmpegCommandBuilder.psm1`, `ProcessRunner.psm1`).
* Never overwrite or delete user files silently; output collisions always ask. Source media is never modified.
* Capabilities (encoders, filters, ...) come from the installed FFmpeg, never from a hardcoded universe.
* No telemetry, accounts, downloads of executables from URLs, GUI, web server or database.
* Colors live only in `Theme.psm1`/`Renderer.psm1`; do not scatter `-ForegroundColor` or ANSI codes.

## 4. PowerShell coding rules (learned the hard way; enforced by tests)
* Keep source files **ASCII-only** (Windows PowerShell 5.1 reads BOM-less files as ANSI). Use `[char]0x...` for symbols.
* No PowerShell-7-only syntax or parameters (`?:`, `??`, `&&`, `ForEach-Object -Parallel`, `$IsWindows` outside `Test-IsWindows`, `ProcessStartInfo.ArgumentList`, ...).
* Variable names are case-insensitive: never name a local `$w` inside code that has the wizard state `$W`; never use `$args`/`$input` as locals.
* A scriptblock stored in a wizard step that reads a local variable of its creating function must end in `.GetNewClosure()`.
* Wrap `Command -and ...` conditions in parentheses: `if ((Test-X) -and $y)`.
* A function that returns an array must not be assumed non-empty by callers (`@(...)`, `,@()` where needed) - scripts run under `Set-StrictMode -Version 2.0`.

## 5. Testing and verification
* Run the relevant tests after every change and the full suite before finishing: `.\tests\Run-Tests.ps1` (report `PASS / FAIL / UNVERIFIED` honestly - never mark PASS unless it was actually run).
* Run a regression check on everything the change could touch and review the acceptance criteria item by item.
* Code that cannot be exercised in the current environment (for example Windows-only behavior) is reported `UNVERIFIED`, not assumed working.

## 6. Documentation, versions and history
* After each task, synchronize only the documentation that is actually affected (`README.md`, `docs/`, `CHANGELOG.md`).
* The canonical version is the `VERSION` file (Semantic Versioning 2.0.0). Never hand-edit version numbers elsewhere; see `docs/Versioning-and-Releases.md`.
* Screenshots must come from the real application. Never fabricate or mock up screenshots.
* Do not invent a license, badges, releases or features.

## 7. Repository and Git
* Develop on the branch named in the task; do not push elsewhere without permission. Commit with clear messages. Do not open pull requests unless asked.
* **The repository stays Private.** Never change visibility, and never publish a GitHub Release without the owner's explicit approval.

## 8. Finishing
Finish with a **Completion Report**: what was done, affected files, tests and results, justified deviations from the handoff, remaining issues, and a clear final status:
`COMPLETE`, `PARTIALLY COMPLETE` or `BLOCKED`. Never report `COMPLETE` while a requirement or required verification is outstanding.
