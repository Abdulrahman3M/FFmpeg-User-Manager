# Coding Conventions (PowerShell)

Use in SKILL.md phase 6. These are enforced by `Scripts/Test-TuiProject.ps1` where a machine can check them.

## Files and syntax

1. ASCII-only source (`.ps1`, `.psm1`, `.bat`, `.sh`). Use `[char]0x25BA` / `[char]::ConvertFromUtf32(...)` for glyphs.
2. `Set-StrictMode -Version 2.0` in every module and entry script; `$ErrorActionPreference = 'Stop'` in entry scripts and tools.
3. Allowed on both editions only: no `?:`, `??`, `?.`, `&&`/`||`, `ForEach-Object -Parallel`, `ProcessStartInfo.ArgumentList`, `Join-Path` with 3+ arguments, `$IsWindows` outside Platform.
4. No `Invoke-Expression`, no shell strings built from user input, no aliases in committed code (`%`, `?`, `gci`), no backticks for line continuation (use splatting or parentheses).
5. One module = one responsibility; export explicitly with `Export-ModuleMember -Function ...`; internal helpers are not exported.

## Naming

* Functions: Approved verbs, `Verb-Noun` (`Show-Menu`, `Read-AppKey`, `Test-IsWindows`, `Resolve-IconTier`). Pure decision functions are `Resolve-*`/`Test-*`/`Format-*`/`ConvertTo-*`.
* Variables: `$camelCase` locals, `$script:PascalCase` for module state. Parameters: `PascalCase`.
* **Variable names are case-insensitive.** A local `$plan` overwrites a parameter `$Plan`; a script-scope `$script:Demo` overwrites a script parameter `$Demo` (this broke an example during skill development). Never reuse a parameter name as a local, and prefix module state distinctively (`$script:TinyDemo`).
* Never name a local `$args`, `$input`, `$matches`, `$error`, `$host`, `$pid`, `$home`.

## Data and collections

* Wrap any command result before `.Count`: `@(Get-X).Count` (a single object is unrolled and has no `Count` under StrictMode).
* A function that returns an array must not be assumed non-empty by callers; return `,@()` when an empty array must survive the pipeline.
* Test optional properties with `$obj.PSObject.Properties['Name']`; initialize every `$script:` variable at module top.
* Scriptblocks stored in data (wizard steps) that read locals of their creating function end with `.GetNewClosure()`.
* Wrap `Command -and ...` conditions: `if ((Test-X) -and $y)`.

## Functions

* Parameters typed and validated (`[ValidateSet]`, `[Parameter(Mandatory)]`); `[CmdletBinding()]` on tools and entry scripts.
* Small: a function that does not fit a screen is split. Pure logic first, side effects at the edges.
* Comments say WHY (a platform quirk, a past defect), not WHAT. A line that exists because of a bug links to the reason in one sentence.
* User-facing text lives next to the code that shows it; one language; sentences start with a capital letter and end with a period (one-line descriptions included).

## Tests accompany code

Every pure function has unit tests; every new menu item has a description (static test); every platform branch has a test that simulates both facts through the seam.
