---
name: powershell-tui-application-designer
description: Designs and builds professional terminal (TUI) applications in PowerShell that run on Windows PowerShell 5.1 and PowerShell 7 on Windows and Linux - numbered menus, validated forms, icon/emoji fallbacks, safe external commands, launchers, tests, packaging and release. Use when asked to create, extend, review or release an interactive PowerShell console app, wizard or menu-driven tool.
---

# PowerShell TUI Application Designer (v1.0.0)

You are following an EXECUTABLE METHODOLOGY. Work through the phases IN ORDER. Each phase has: **Do** (steps), **Gate** (checks that must all pass), **If it fails**. You may not start phase N+1 until every Gate item of phase N is satisfied with evidence (a command you ran and its result). Do not skip, merge or reorder phases. Do not invent facts: inspect first.

Files you will use (relative to this skill folder):
`Templates/App` (working scaffold) - `Scripts/*.ps1` (generators and validators) - `Examples/*.ps1` (small patterns) - `References/*.md` (rules; open the one named in each phase) - `Images/` (illustrations only).

## Hard rules (apply in every phase)

1. **Numbered options only.** Every selectable option is `NN  Icon  Name` with a two-digit zero-padded number and a one-line description under it. No letter keys, no `[Y/N]`. Exit and Back are numbered options too.
2. **Single owners.** Only Renderer writes to the screen, only Input reads keys, only Theme knows colors/glyphs, only Platform knows the operating system.
3. **ASCII-only source files.** Build glyphs from code points. (Windows PowerShell 5.1 reads BOM-less files as ANSI.)
4. **No `Invoke-Expression`, no shell strings from user input.** External programs run from argument arrays.
5. **Both editions, both systems.** No PowerShell-7-only syntax, no `$IsWindows` outside Platform, no hard-coded paths or separators.
6. **Never overwrite, delete, install or download without asking.** Source/input files are never modified.
7. **Honest reporting.** Results are PASS, FAIL or UNVERIFIED (could not run here, with the reason). A check that did not execute is never PASS.
8. **Do not guess.** If two valid options exist and the choice changes the product, write the options and ask the owner; otherwise pick the documented default and say so.

---

## Phase 0 - Inspect the environment and the request

**Do**
1. Run `Scripts/Test-TuiEnvironment.ps1` (add `-Json` if you need to parse). Record platform, PowerShell version/edition, interactive or redirected, terminal facts, suggested icon tier.
2. List which of `pwsh` (7.x) and `powershell` (5.1) exist. Decide which you can execute tests with; everything else will be UNVERIFIED locally and needs CI or a human.
3. If a project folder already exists: read its README/AGENTS/rules files, folder layout, `VERSION`, tests, launchers. Reuse what exists; do not create duplicates of modules that already do the job.
4. Write down the request in your own words: users, tasks, platforms, external tools, constraints.

**Gate**
- [ ] Environment facts recorded. - [ ] Executable editions listed. - [ ] Existing rules/structure read (or "greenfield" stated). - [ ] Request restated in <= 10 lines.

**If it fails**: stop and report what is unknown; do not proceed on assumptions about the platform.

## Phase 1 - Plan before code

Open `References/Checklists.md` (A) and `References/Architecture.md`.

**Do**
1. Define the TASKS (each = one workflow: goal, inputs, outputs, external tools).
2. Draft the main menu: numbered, each option with icon name, label (2-4 words) and a one-line description; Exit last.
3. For each task list its questions (prompt, help, example, validation, default, choices) as data (see Architecture section 5).
4. List dependencies (external programs, files, network) and what happens when each is missing.
5. List what is OUT of scope.
6. Choose names: app display name, `AppId` (letters, digits, hyphens), environment prefix (UPPER_SNAKE).

**Gate**
- [ ] Menu draft with descriptions. - [ ] Questions listed as data for every task. - [ ] Dependency table with a "missing" behavior per row. - [ ] Out-of-scope list. - [ ] Names chosen.

**If it fails**: finish the plan first. Code written before this gate is discarded if it conflicts.

## Phase 2 - Decide the architecture

Open `References/Architecture.md` and `References/Cross-Platform-Compatibility.md`.

**Do**
1. Adopt the layering and module catalogue unchanged unless a rule forces a deviation; write each deviation and its reason in a `docs/Architecture.md` of the new project.
2. Decide which logic is pure (goes in Core, unit-testable) and which is screen code (TUI).
3. Decide platform support matrix (Windows PS 5.1, Windows PS 7, Linux PS 7) and write it in the README plan.
4. Decide the per-user data folder name and the persistent settings (keep them few).

**Gate**
- [ ] Module list with one responsibility each. - [ ] Support matrix written. - [ ] Pure/screen split stated for each task.

## Phase 3 - Scaffold

**Do**
1. `pwsh -File Scripts/New-TuiProject.ps1 -Name "<Display Name>" -Path <folder> -RunTests` (or `powershell -File` on Windows PowerShell).
2. Run `Scripts/Test-TuiProject.ps1 -Path <folder>`.
3. Start the generated app: `<folder>/Start-<AppId>.ps1 -Version` and `-ScriptedInput '05'` (exit).
4. Initialize version control; commit the scaffold as a separate first commit.

**Gate**
- [ ] Generator printed "Created". - [ ] Generated tests: 0 FAIL. - [ ] Test-TuiProject: "0 failed". - [ ] `-Version` prints the version. - [ ] Non-interactive start without `-ScriptedInput` exits 2.

**If it fails**: do NOT edit around the failure. Read the failing rule/test, fix the cause in the generated project or report a skill defect.

## Phase 4 - Platform layer

Open `References/Cross-Platform-Compatibility.md`.

**Do**
1. Keep `Core/Platform.psm1`; add only OS facts you need (e.g., `Find-Executable` for your tools).
2. Implement dependency detection for each external tool: find, run `--version`, parse capabilities from the tool itself, show a numbered "missing" screen (`01 Install it for me` only if you may install and the user says yes, `02 I will install it myself`, `03 Exit`).
3. Per-user settings/log folder via `Get-AppDataDirectory`; tests override it with `<PREFIX>_DATA_DIR`.
4. Launchers: keep the generated `.bat` (CRLF) and `.sh` (LF, executable); change only names/arguments.

**Gate**
- [ ] No OS check outside Platform (`Test-TuiProject` C5 passes). - [ ] Each dependency has a tested "present", "missing", "broken" path. - [ ] Launchers start the app from a folder with spaces.

## Phase 5 - Design the UI system

Open `References/TUI-Design-Rules.md` and `References/Unicode-and-Emoji-Handling.md`.

**Do**
1. Add icons your screens need to `Get-IconTable` with ALL THREE forms (Emoji, Symbol from WGL4, Ascii).
2. Define success/warning/error/info wording patterns (what + why + next).
3. Design each screen on paper: header, context, question, options, footer; typed questions with help + example + validation.
4. Decide the first-run icon question (offer emoji once in unrecognized Windows consoles, remember the answer) and the Settings entry.

**Gate**
- [ ] Every new icon has 3 forms. - [ ] Every screen listed with its options and descriptions. - [ ] Every typed question has help, example, validator.

## Phase 6 - Build

Open `References/Coding-Conventions.md`. Build ONE task at a time, smallest first.

**Do** (repeat per task)
1. Write the pure functions (Core) and their unit tests FIRST.
2. Write the screen code using only `Show-Menu`, `Show-Confirm`, `Show-Notice`, `Read-ValidatedInput` and Renderer roles.
3. Run external programs only through `Invoke-External` with an argument array; apply a timeout; handle `Started=$false`.
4. Add the task to the main menu with its description.
5. Run the unit tests and `Test-TuiProject` after EVERY task.

**Gate (per task)**
- [ ] New functions have tests (PASS). - [ ] `Test-TuiProject`: 0 failed. - [ ] Screen driven through `-ScriptedInput` end to end without error. - [ ] Option numbers/descriptions present (static test).

**If it fails**: fix before starting the next task. Never accumulate failing tasks.

## Phase 7 - Errors, logging, cancellation

Open `References/Error-Handling.md`.

**Do**
1. Classify each failure mode (expected / environmental / unexpected / cancellation) and give each a mechanism.
2. Add messages in the what + why + next form; add "Show technical details" where raw output helps.
3. Make long tasks cancellable (`Esc` then confirm); kill child processes on cancel and in `finally`.
4. Log unexpected errors and environmental failures; mask secrets everywhere.
5. Verify terminal restoration after a forced failure.

**Gate**
- [ ] A forced failure exits 1, restores the terminal, prints the message after leaving the alternate screen. - [ ] Missing-dependency path exits/returns with the documented code. - [ ] No raw exception text is shown to users.

## Phase 8 - Test on every claimed environment

Open `References/Testing-Strategy.md`.

**Do**
1. Run `Scripts/Invoke-TuiTests.ps1 -Path <folder>` (runs every installed edition; reports "NOT RUN" for missing ones).
2. Add static, flow, process-smoke and launcher tests for everything you built.
3. Set up CI for the claimed matrix (copy the workflow in Testing-Strategy section 3) and read its results; a platform without a run is UNVERIFIED.
4. When something fails in one environment only, follow Testing-Strategy section 4 (isolate, prove, fix the root cause, regression test).

**Gate**
- [ ] 0 FAIL on every environment you claim. - [ ] Every UNVERIFIED item listed with reason and the human steps to verify. - [ ] No test was skipped or loosened to pass.

## Phase 9 - Documentation

**Do**
1. README: purpose, requirements per platform, install, run (`.bat`/`.sh`), keys, exit codes, troubleshooting, license, support matrix with what was verified.
2. `docs/Workflows.md` (every task, every question), `docs/Architecture.md`, `docs/Testing.md`.
3. Screenshots only from the REAL app (say how captured, e.g. "Linux pseudo-terminal"); never mock-ups.
4. In-app help is the screen's help line + example; the docs do not replace it.

**Gate**
- [ ] A new user can install and run from the README alone. - [ ] Every claim in the docs is backed by a test or a stated manual check. - [ ] Links resolve.

## Phase 10 - Versioning and changelog

Open `References/Packaging-and-Release.md` sections 1-2.

**Do**
1. `VERSION` = Semantic Version. Start at `0.1.0` unless the owner states otherwise; `1.0.0` only when the criteria in section 1 are met.
2. Keep `CHANGELOG.md` with `[Unreleased]`; add user-relevant entries as you go.
3. Show the version in the header/About and `-Version`.

**Gate**
- [ ] VERSION, README badge, About screen and CHANGELOG agree (a test checks).

## Phase 11 - Package and release

Open `References/Packaging-and-Release.md` sections 3-6 and `References/Checklists.md` (E).

**Do**
1. Build the package with `Scripts/New-TuiPackage.ps1` from the final merged commit.
2. Inspect contents; extract into a folder with spaces; run `-Version` and a scripted start; record SHA-256.
3. Write release notes with verified facts only (features, requirements, quick start, known limitations).
4. Tag `vX.Y.Z` and publish the release (through the project's allowed mechanism); then verify the tag, the release page and the asset checksum exist.

**Gate**
- [ ] Package verified. - [ ] Tag and release verified to exist. - [ ] Notes contain only verified claims.

## Phase 12 - Final cleanup and report

Open `References/Checklists.md` (F).

**Do**
1. Remove temp files, logs, caches; search for secrets, tokens, personal data and absolute local paths.
2. Run `Test-TuiProject` and the full tests one last time on the final commit.
3. Write the final report: what was built, per-environment PASS/FAIL/UNVERIFIED counts, run ids/commits, UNVERIFIED items with human steps, known limitations, release links.

**Gate**
- [ ] No secrets/paths. - [ ] Final test numbers recorded per environment. - [ ] Report lists every UNVERIFIED item. Status is COMPLETE only if every requirement is verified; otherwise PARTIALLY COMPLETE with the exact remainder.

---

## Conflict rules

- A project's own rules files (AGENTS.md, CONTRIBUTING, owner instructions) override this skill; say which rule you followed.
- If two skill rules conflict, the one in "Hard rules" wins.
- If a rule cannot be satisfied on the platform (for example a glyph that the terminal cannot draw), use the next fallback tier; never drop the option or its description.

## Things you must NOT do

- Do not write colors, glyphs or `$IsWindows` outside Theme/Renderer/Platform.
- Do not use letter-key menus, `Read-Host` in modules, `Invoke-Expression`, or non-ASCII source.
- Do not report PASS for unexecuted tests, hide failing tests, or loosen assertions to get green.
- Do not publish, install, download or delete without the explicit approval the project rules require.
- Do not copy the reference application's domain code; copy only the principles.
