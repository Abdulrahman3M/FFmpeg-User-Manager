# PowerShell TUI Application Designer

| | |
|---|---|
| **Skill name** | `powershell-tui-application-designer` (display name: PowerShell TUI Application Designer) |
| **Version** | 1.0.0 |
| **Purpose** | Teach an AI agent to design, build, test, package and release professional terminal (TUI) applications in PowerShell |
| **Compatibility** | Generated apps: Windows PowerShell 5.1 and PowerShell 7.x on Windows; PowerShell 7.x on Linux/macOS. Skill scripts: same |
| **Last updated** | 2026-10-04 |

## What this is

An **executable methodology**, not an essay. `SKILL.md` gives an agent 13 ordered phases (0-12), each with steps, a gate of checkable criteria and a failure rule. The rest of the package gives it the material it needs:

```text
PowerShell TUI Application Designer/
  SKILL.md              the strict procedure (start here)
  README.md  VERSION    this file; version 1.0.0
  References/           the rules, one topic per file (open the one SKILL.md names)
  Scripts/              generator, validators, test runner, packager, self-check
  Templates/App/        a complete working scaffold (the generator copies it)
  Examples/             eight small, runnable patterns (+ Shared/TinyTui.ps1)
  Images/               illustrations of the style (not needed to apply the skill)
```

## What a generated application looks like

Numbered menus (`01  Icon  Name` + a description), validated forms with help and an example, confirmations as `01 Yes / 02 No`, success/warning/error notices, icons in three tiers (emoji, single-column symbols, ASCII) chosen from facts about the terminal, safe external-command execution from argument arrays, a scripted-input mode for tests and CI, launchers for Windows (`.bat`) and Linux (`.sh`), a per-user settings file and log, a unit/UI test suite, and a package script. See `Images/`.

## Quick start

```powershell
# 1. look at the machine
pwsh -File Scripts/Test-TuiEnvironment.ps1
# 2. create an app from the template and run its tests
pwsh -File Scripts/New-TuiProject.ps1 -Name "Disk Helper" -Path ./disk-helper -RunTests
# 3. validate the project against the rules
pwsh -File Scripts/Test-TuiProject.ps1 -Path ./disk-helper
# 4. run it
pwsh -File ./disk-helper/Start-DiskHelper.ps1
# 5. check this skill package itself
pwsh -File Scripts/Test-SkillPackage.ps1
```

On Windows PowerShell 5.1 use `powershell -NoProfile -File ...` instead of `pwsh`.

## Scripts

| Script | Use |
|---|---|
| `New-TuiProject.ps1` | Generate a working project from `Templates/App` (placeholders, CRLF/LF, exec bit) |
| `Test-TuiProject.ps1` | Validation gate: structure, ASCII-only, syntax, forbidden constructs, launchers, version (exit 1 on any failure) |
| `Test-TuiEnvironment.ps1` | Platform / edition / terminal / encoding / suggested icon tier (read-only) |
| `Invoke-TuiTests.ps1` | Run a project's tests under every installed PowerShell edition; "NOT RUN" is never a pass |
| `New-TuiPackage.ps1` | Build `<Name>-v<VERSION>.zip` (no tests/.git/dist) |
| `Test-SkillPackage.ps1` | Self-check of this package (links, privacy, syntax, generated project, examples) |

## Installing the skill

Copy the folder into your agent's skills location (for example `.claude/skills/`). Some loaders require the folder name to equal the `name` in the `SKILL.md` front matter: rename the folder to `powershell-tui-application-designer` in that case. The folder name `PowerShell TUI Application Designer` is the display name used for the distributed archive.

## Verification status of this release

Executed on PowerShell 7.4 on Linux: `Test-SkillPackage.ps1` (all checks), the generated project's tests and validator, all eight examples. Executed on Windows PowerShell 5.1 / PowerShell 7 on Windows: see `References/Testing-Strategy.md` for how to run `Scripts/Test-SkillPackage.ps1` there; the result of that run is recorded in the release notes of this skill version, not assumed here. Rendering of the icon tiers in a real Windows Terminal is a manual check.

## Principles extracted from a reference implementation

The rules come from a large production-style PowerShell TUI built and tested on Windows PowerShell 5.1, PowerShell 7 and Linux. What was a project decision there (its domain, menu content) is NOT part of the skill; what was a general lesson is in `References/` (see `Lessons-From-The-Reference-Implementation.md`).

## Change history

| Version | Date | Changes |
|---|---|---|
| 1.0.0 | 2026-10-04 | First stable release: 13-phase methodology, 8 references plus lessons and checklists, working template, 6 scripts, 8 examples, illustrations |
