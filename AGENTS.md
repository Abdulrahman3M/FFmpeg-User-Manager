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
* **Numbered options only.** Every selectable option on every screen (menus, submenus, wizard questions, dialogs) is shown as `Number  Icon  Name` with a two-digit, zero-padded number (`01`, `02` ... `09`, `10`, `11` ..., continuing to `100` and beyond, never truncated). There are no letter keys, no `[X]` shortcuts and no exceptions (Exit and Back are numbered like everything else). `Show-Menu`, `Show-Notice` and `Show-Confirm` assign the numbers; never hand-write a key.
* **Every option explains itself.** Every option has a short description under it (what it does, when to use it, what to expect); every question has help text, and typed questions have an example. Static tests enforce this (`tests/Unit/UiRules.Tests.ps1`).
* **Icons are characters, not assets.** They come only from the three-tier table in `Theme.psm1` (Emoji / console-safe Symbol / ASCII) chosen by `Get-IconTier`; a new icon needs all three forms, and its Symbol form must be a WGL4 glyph so a legacy console font can always draw it.

## 4. PowerShell coding rules (learned the hard way; enforced by tests)
* Keep source files **ASCII-only** (Windows PowerShell 5.1 reads BOM-less files as ANSI). Use `[char]0x...` for symbols.
* No PowerShell-7-only syntax or parameters (`?:`, `??`, `&&`, `ForEach-Object -Parallel`, `$IsWindows` outside `Test-IsWindows`, `ProcessStartInfo.ArgumentList`, ...).
* Variable names are case-insensitive: never name a local `$w` inside code that has the wizard state `$W`; never use `$args`/`$input` as locals.
* A scriptblock stored in a wizard step that reads a local variable of its creating function must end in `.GetNewClosure()`.
* Wrap `Command -and ...` conditions in parentheses: `if ((Test-X) -and $y)`.
* A function that returns an array must not be assumed non-empty by callers (`@(...)`, `,@()` where needed) - scripts run under `Set-StrictMode -Version 2.0`. Write `@(Get-X).Count`, never `(Get-X).Count` (a single result is unrolled and has no `Count`).
* A parameter and a local differing only by case are the same variable (`param($Plan)` + `$plan = $null` destroys the parameter); `UiRules.Tests.ps1` flags it.

## 5. Testing and verification
* Run the relevant tests after every change and the full suite before finishing: `.\tests\Run-Tests.ps1` (report `PASS / FAIL / UNVERIFIED` honestly - never mark PASS unless it was actually run).
* Run a regression check on everything the change could touch and review the acceptance criteria item by item.
* Code that cannot be exercised in the current environment (for example Windows-only behavior) is reported `UNVERIFIED`, not assumed working.

## 6. Documentation, versions and history
* After each task, synchronize only the documentation that is actually affected (`README.md`, `docs/`, `CHANGELOG.md`).
* The canonical version is the `VERSION` file (Semantic Versioning 2.0.0). Never hand-edit version numbers elsewhere; see `docs/Versioning-and-Releases.md`.
* Screenshots must come from the real application. Never fabricate or mock up screenshots.
* Do not invent a license, badges, releases or features.

## 7. Dependency-aware change sync (permanent rule - applies to every change, by every agent and developer)
A task is **not finished when the code works**. Every change must be followed by a review of everything that depends on it, and everything that became outdated must be updated.

```text
Code Change
  -> Identify Affected Dependencies & Artifacts
  -> Update Them
  -> Tests
  -> Documentation / Visual / Version / Changelog Sync
  -> Final Verification
```

**Identify** what the change touches, then check each artifact class below and record "affected / not affected" with the reason in the Completion Report:

| Artifact class | Typical triggers |
|---|---|
| Documentation (`docs/`), `README.md` | new/changed/removed feature, key or menu change, option text, requirement, structure, test count |
| Help and usage text (in-app help, examples, descriptions) | changed behavior, new option, renamed label |
| Screenshots and project images (`docs/images/`, `docs/images/README.md`) | any visible UI change (layout, numbering, icons, wording, colors). Recapture from the **real** application; never mock up |
| Version information (`VERSION`, README badge, header) | only as `docs/Versioning-and-Releases.md` requires: a change after a published release follows SemVer; work that is still inside an unreleased version does not bump it |
| Changelog (`CHANGELOG.md`) | every user-visible change, under `[Unreleased]` |
| Release information (packaging script, release notes, checklist) | new shipped files (for example `LICENSE`, `NOTICE`), new requirements, packaging changes |
| Tests and test documentation | behavior, keys, counts, new static rules |
| Other artifacts and references | launcher, config defaults, links between documents, file-structure trees, `AGENTS.md` itself |

**Not** what this rule means: bumping the version for every small change, or regenerating every image for every commit. Inspect first, then update exactly what the change requires, following the project's Versioning/Documentation system. If nothing is affected, say so explicitly.

## 8. Licensing, dependencies and third-party notices
* The project is licensed under the **Apache License 2.0** (`LICENSE`, unmodified standard text; `NOTICE` carries the copyright and attribution notice). See `docs/Licensing.md` for the decision record. Never edit `LICENSE`, never add conflicting terms, and never use "All Rights Reserved" wording that contradicts it.
* **Never delete or weaken a required legal notice**: copyright lines, the `LICENSE` and `NOTICE` files, or a third party's license or attribution text. A copied or derived file keeps its original notices; changed files that derive from third-party code say so.
* Before adding a **library, font, icon set, image, script or any other third-party material**, and before **distributing a release**, review: (1) License compatibility with Apache-2.0 (permissive licenses such as MIT, BSD, Apache-2.0 are fine; GPL/AGPL/LGPL code or assets need an owner decision first); (2) Third-party notices - add the required attribution to `NOTICE` (or a `THIRD-PARTY-NOTICES` file) and ship the third party's license text; (3) Copyright/attribution requirements of that license are met. Record the result in the Completion Report.
* FFmpeg, ffprobe and winget are **external tools** that the user installs; they are never bundled or redistributed by this project. Keep it that way unless the owner decides otherwise (bundling FFmpeg would bring its LGPL/GPL obligations).
* No per-file copyright headers are required; `LICENSE` and `NOTICE` at the repository root (and in every release package) are the notice.

## 9. Repository and Git
* Develop on the branch named in the task; do not push elsewhere without permission. Commit with clear messages. Do not open pull requests unless asked.
* **The repository stays Private.** Never change visibility, and never publish a GitHub Release without the owner's explicit approval.

## 10. Finishing
Finish with a **Completion Report**: what was done, affected files, the artifact review required by section 7 (affected / updated / not affected, with reasons), tests and results, justified deviations from the handoff, remaining issues, and a clear final status:
`COMPLETE`, `PARTIALLY COMPLETE` or `BLOCKED`. Never report `COMPLETE` while a requirement or required verification is outstanding.
