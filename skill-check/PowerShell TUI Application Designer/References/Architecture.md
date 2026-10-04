# Architecture Reference

Use this file in SKILL.md phases 2-4. It defines WHAT the modules are and WHICH direction dependencies may point. The template in `Templates/App` implements it exactly.

## 1. Layers (dependencies point DOWN only)

```text
Entry script (Start-<App>.ps1)          parse parameters, load modules, set up terminal, call Start-<App>App, map errors to exit codes
  Core/App.psm1                         main loop, screens, actions (orchestration)
    Core/<Domain>.psm1                  business logic: pure functions, no screen, no keyboard
    TUI/Menu, Dialog, Prompt            screens built from Renderer + Input
      TUI/Renderer, Input, Theme        the ONLY writers/readers of the terminal and the ONLY owners of colors/icons
        Core/Platform, Settings, Log, Process   OS facts, per-user files, external programs
```

Rules (a violation fails the validation gate):

1. **Single owners.** Only `Renderer` writes to the screen. Only `Input` reads the keyboard. Only `Theme` knows colors and glyphs. Only `Platform` reads `$IsWindows`/`$IsLinux`/`$IsMacOS`, the OS name or an OS-specific path.
2. **Business logic never touches the terminal.** A function that decides, parses, validates or builds a command returns a value; the screen code shows it. This is what makes unit tests possible.
3. **No global mutable state** except the private `$script:` state of Renderer (sink, ANSI flag, buffer), Input (queue) and Theme (icon tier). Application state is a single hashtable passed explicitly (see section 4).
4. **One import list.** `src/Import-Modules.ps1` names every module in dependency order. A new module is added there and nowhere else.
5. **Everything the user can choose is data**, not code branches: menu items, wizard steps, presets (see section 5).

## 2. Entry point responsibilities (and only these)

1. `param(...)` with `-Version` and `-ScriptedInput` always present (CI and demos need them).
2. `$ErrorActionPreference = 'Stop'`, `Set-StrictMode -Version 2.0`.
3. Load modules via `Import-AppModules`.
4. `-Version` prints `<Name> v<VERSION>` and exits 0 BEFORE any terminal work.
5. Refuse non-interactive use (redirected input or output) unless `-ScriptedInput` was given: print one clear sentence, exit code **2**.
6. Initialize Renderer (ANSI decision), Input (scripted queue), enter the alternate screen, set `TreatControlCAsInput`.
7. Run the app in `try`; `catch [OperationCanceledException]` = quiet quit (exit 0); any other exception = exit 1 with the message printed AFTER the screen was restored.
8. `finally`: restore screen, cursor, Ctrl+C mode.

## 3. Module catalogue (what the template ships; copy these names)

| Module | Exports (examples) | Notes |
|---|---|---|
| `Core/Platform` | `Test-IsWindows`, `Get-PlatformName`, `Get-RuntimeInfo`, `Get-AppDataDirectory`, `Find-Executable`, `Get-CurrentPowerShellPath` | the only OS-aware module |
| `Core/Settings` | `Get-UserSetting`, `Set-UserSetting` | JSON, UTF-8 without BOM, never throws on a read-only profile |
| `Core/Log` | `Write-AppLog` | append-only, size-capped, never throws, never logs secrets |
| `Core/Process` | `ConvertTo-ProcessArgument`, `Invoke-External` | argument arrays only |
| `TUI/Theme` | `Get-Icon`, `Resolve-IconTier`, `Get-IconTier`, `Get-RoleStyle` | roles and tiers |
| `TUI/Renderer` | `Write-Ui`, `Write-UiLine`, `Clear-Ui`, `Enter-Screen`, `Exit-Screen`, `Initialize-Renderer` | Console and Buffer sinks |
| `TUI/Input` | `Read-AppKey`, `Set-ScriptedInput` | real keys or a scripted queue |
| `TUI/Menu` | `Show-Menu`, `New-MenuItem`, `Resolve-NumberInput` | numbered options |
| `TUI/Dialog` | `Show-Confirm`, `Show-Notice` | also numbered |
| `TUI/Prompt` | `Read-ValidatedInput` | help + example + validation |
| `Core/App` | `Start-TuiApp` | screens and actions |

## 4. State management

* Keep one `$state` hashtable (or `[pscustomobject]`) per user flow; pass it to functions; never read it from `$global:`.
* Persistent user choices (icon style, last folder) go to `Settings` (per user, small, optional). The app must run correctly with an empty or unreadable settings file.
* Defaults shipped with the app live in a `config/defaults.json` (read-only data) with a hard-coded fallback in code, so a missing file never crashes the app.

## 5. Data-driven wizards (for multi-step tasks)

When a task asks several questions, model each question as data:

```powershell
@{ Id = 'width'; Type = 'Choice'; Prompt = 'Width'; Help = '...'; Example = '...'
   When = { param($S) $S.Mode -eq 'custom' }          # shown only if true
   Choices = { param($S) @(New-MenuItem ...) }        # computed from state
   Validate = { param($v, $S) $null }                 # $null = OK, else message
   Default = 480 }
```

A generic runner walks the steps, skips those whose `When` is false, supports Back (Esc) to the previous *shown* step, and ends with a summary screen (`01 Start`, `02 View details`, `03 Back`). Closures that capture local variables MUST end with `.GetNewClosure()`. Adding a question never touches the runner.

## 6. External tools (dependency detection)

1. Discover with `Find-Executable` (PATH); never hard-code locations.
2. Verify it RUNS (`--version`), not just that a file exists (stale PATH entries and package-manager shims are common).
3. Discover capabilities from the tool itself (encoders, flags) instead of a hard-coded universe; options the tool cannot do are shown disabled with a reason.
4. If missing: show what is missing, why it is needed, and the exact choices (`01 Install it for me`, `02 I will install it myself`, `03 Exit`). Any download or install needs an explicit "Yes" first.
5. Build commands as token arrays; show the generated command on request ("View command") - it doubles as documentation and as a debugging aid.

## 7. Folder layout (template)

```text
<App>/
  Start-<App>.ps1   <App>.bat   <App>.sh   VERSION   README.md   CHANGELOG.md   LICENSE
  src/Import-Modules.ps1   src/Core/*.psm1   src/TUI/*.psm1
  config/defaults.json (optional)
  docs/   tests/Run-Tests.ps1   tests/TestHelpers.ps1   tests/Unit/*.Tests.ps1   tests/Smoke/*.Tests.ps1
  tools/New-ReleasePackage.ps1
```
