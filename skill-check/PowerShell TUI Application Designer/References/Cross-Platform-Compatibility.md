# Cross-Platform Compatibility (Windows + Linux, PowerShell 5.1 + 7)

Use in SKILL.md phases 3, 4 and 8. Principle: **shared core logic, isolated platform code.** Platform differences live in `Core/Platform` (OS facts), `TUI/Theme` + `Renderer` (terminal facts), and the launchers. Nowhere else may contain `if (Windows)`.

## 1. Support matrix to declare in README (and test)

| Runtime | Windows | Linux / macOS |
|---|---|---|
| Windows PowerShell 5.1 | supported | not possible |
| PowerShell 7.x | supported | supported |

Say which combinations were executed by tests and which were not. "Compiles" is not "works".

## 2. Differences and the required handling

| Area | Difference | Required handling |
|---|---|---|
| OS variables | `$IsWindows`, `$IsLinux`, `$IsMacOS` do not exist in 5.1 (and fail under StrictMode) | `Test-IsWindows` in Platform: `Major -lt 6` -> Windows, else `Get-Variable -Name IsWindows -ValueOnly -ErrorAction SilentlyContinue`. Tests must use the helper too (a test that read `$IsWindows` under 5.1 silently became UNVERIFIED) |
| Syntax | 5.1 lacks `?:`, `??`, `?.`, `&&`, `||` chains, `ForEach-Object -Parallel`, `-AdditionalChildPath` of `Join-Path`, `Get-Content -AsByteStream` | Forbidden by the validation gate; use `if/else`, two-argument `Join-Path` |
| File encoding | 5.1 reads BOM-less files as the ANSI code page | Source files ASCII-only (build glyphs from code points). Test files that must contain Unicode are saved with a UTF-8 BOM |
| Console encoding | Windows consoles default to an OEM code page; redirected output too | Set `[Console]::OutputEncoding` to UTF-8 (no BOM) on Windows, **also when redirected**; the `.bat` launcher switches to code page 65001 and restores it |
| Paths | `\` vs `/`, drive letters, case sensitivity, reserved names (`CON`, `NUL`), characters illegal on Windows (`< > : " / \ | ? *`) | `Join-Path` (2 args), `[IO.Path]::GetFullPath`, `-LiteralPath` for user paths (brackets), validate names for the strictest OS, never hard-code separators or drives |
| Per-user data | `%APPDATA%` vs `$XDG_CONFIG_HOME`/`~/.config` | `Get-AppDataDirectory`; an override variable for tests |
| Executables | `.exe` suffix, package-manager shims (Chocolatey/winget links) that only work from their install folder, `PATHEXT` | `Get-Command -CommandType Application`; verify it runs; never copy a shim somewhere else |
| Process arguments | Windows passes ONE command-line string; Linux passes an argv array | Always pass an argument array to your `Invoke-External`, which quotes with the CommandLineToArgvW rules; never build shell strings |
| `-Command` | `pwsh -Command` joins remaining arguments into the command text | Pass data to child PowerShell with `-File script args`, not `-Command` |
| Line endings | `.bat` needs CRLF; `.sh` needs LF + shebang | Generator/`.gitattributes`: `*.bat eol=crlf`, `*.sh eol=lf`; validation gate checks both |
| Permissions | Linux needs `chmod +x` for `.sh`; admin vs user rights on Windows; root ignores permission checks | `chmod +x` in the package/scaffold; permission tests must report UNVERIFIED when the account ignores the denial |
| Terminals | Windows Terminal/VS Code/ConEmu support ANSI + emoji; classic conhost may not; Linux terminals vary by locale | Theme tiers (Unicode-and-Emoji-Handling.md); `NO_COLOR`; ANSI only when not redirected |
| Redirection | Output/input may be pipes in CI | Detect with `[Console]::IsOutputRedirected/IsInputRedirected`; refuse interactive mode with exit code 2 unless `-ScriptedInput` |
| `Get-ChildItem` | `-LiteralPath` + `-Include` returns directories in 5.1 | Enumerate with `-File` and filter by `.Extension` |
| JSON/Compress | 5.1 `Compress-Archive` writes backslash entry names; `ConvertFrom-Json` returns different shapes for single items | Build packages with PowerShell 7 or verify the zip on the target; always wrap results `@(...)` |
| Time/locale | Culture changes number formats | Format numbers for external tools with `[CultureInfo]::InvariantCulture` |
| Package/launch | Double-click = `cmd /c`; a `.cmd` started from a `.bat` without `call` never returns | Launcher tests run the real `cmd`; stubs for launcher tests must be real executables |

## 3. Isolation patterns

* **Facade:** callers use `Find-Executable`, `Get-AppDataDirectory`, `Get-CurrentPowerShellPath`; they never ask "am I on Windows?".
* **Tier tables:** differences in what the terminal can draw are data (`Get-IconTable`), not code branches.
* **Test seams:** `Platform` and `Process` functions accept overrides (data-dir variable, mock hooks) so tests simulate the other platform's facts; the *real* other platform is covered by CI (below).

## 4. Verification matrix (minimum for a release)

1. Windows PowerShell 5.1 on Windows - full suite.
2. PowerShell 7 on Windows - full suite.
3. PowerShell 7 on Linux - full suite.
4. Manual (cannot be automated): a real Windows Terminal and a classic console for icon rendering; real devices/installers if the app uses them.

Use a CI matrix (GitHub Actions `windows-latest` with `shell: powershell` and `shell: pwsh`, plus `ubuntu-latest`). Do not claim a platform that no run executed. See Testing-Strategy.md.
