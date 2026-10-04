# Error Handling

Use in SKILL.md phase 7. Goal: the user never sees a stack trace, never loses work silently, and the terminal is always restored.

## 1. Classify before you code

| Class | Example | Mechanism |
|---|---|---|
| **Expected / user** | bad input, missing file, locked file, unsupported combination | return a message (`$null` = OK) from a pure validator; show it inline; the flow continues |
| **Environmental** | dependency missing, no permission, disk full, network down | a result object (`Started`, `ExitCode`, `Error`) + a Notice with the next step; log details |
| **Programmer / unexpected** | null reference, parse failure | one top-level `catch`: log, restore terminal, print one line, exit code 1 |
| **Cancellation** | Esc, Ctrl+C | `OperationCanceledException` for Ctrl+C (quiet exit 0); Esc returns `$null` (Back) |

Exceptions are for the unexpected. Expected problems are values.

## 2. Message formula (what + why + next)

`Error` notices say: **what happened** ("Could not save the settings"), **why** if known ("the folder is read-only"), **what the user can do** ("Choose another folder (02) or continue without saving (01)"). Never expose paths of the app's internals or raw exception text; keep that in the log.

## 3. Exit codes (document them in README)

`0` success / normal quit, `1` unexpected error, `2` needs an interactive console, `3` missing required dependency (for example no PowerShell for the launcher), `4+` application-specific. Launchers pass the code through (`exit /b %RC%`, `exec`).

## 4. Terminal restoration

`Enter-Screen` (alternate screen, hidden cursor, Ctrl+C as input) is always paired with `Exit-Screen` in `finally`. Print the error message AFTER leaving the alternate screen, otherwise it disappears with the screen. Test it: run the app with a deliberately failing action and assert the restore sequences precede the message in the captured output.

## 5. External commands

* Check `Started` first (the program may not exist), then `TimedOut`, then `ExitCode`.
* Apply a timeout to everything; kill the child on timeout and in `finally` when the user cancels.
* Capture stderr; show a short friendly summary and offer "Show technical details" (the raw stderr) as a numbered option.
* Offer `Retry` for transient failures (permission, locked file, offline).

## 6. Files

* Never overwrite or delete silently: a collision is a question. Never modify the user's source/input files.
* Write results to a temporary name and rename on success when a half-written file would be harmful.
* Validate file names for the strictest platform (reserved names, illegal characters, trailing dots/spaces, length).
* Test-InputFile pattern: folder? missing? empty? unreadable (UnauthorizedAccess)? locked (IO)? - each returns its own sentence.

## 7. Logging

* One append-only log in the per-user data folder; size-capped (rotate at ~1 MB); logging must never throw.
* Log: timestamp, level, short message, exit codes, durations. Do NOT log secrets (passwords, tokens, stream keys, full command lines that contain them) - mask before logging and before showing.
* The user-facing "details" view and the log use the same masked text.

## 8. Strict-mode traps that cause "unexpected" errors

`Set-StrictMode -Version 2.0` makes unset variables and missing properties throw. Initialize every `$script:` variable at module top; wrap results in `@()` before `.Count`; test optional properties with `.PSObject.Properties[...]`; never reference `$IsWindows` directly.
