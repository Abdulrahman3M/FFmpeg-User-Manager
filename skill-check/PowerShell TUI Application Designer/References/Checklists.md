# Checklists

Copy the relevant list into your working notes and tick it with evidence (command + result).

## A. Planning gate (phase 1)
- [ ] Target users and platforms written down (Windows/Linux, PS 5.1/7).
- [ ] Task list with the data each task needs and the external tools it calls.
- [ ] Main menu drafted as numbered options with one-line descriptions (Exit last).
- [ ] Out-of-scope list written (no GUI/web/database/telemetry unless required).
- [ ] Decisions needing the owner listed; none are guessed.

## B. Scaffold gate (phase 3)
- [ ] `Scripts/New-TuiProject.ps1` ran; generated tests pass (`-RunTests`).
- [ ] `Scripts/Test-TuiProject.ps1` reports 0 failed rules.
- [ ] Entry script `-Version` prints the version; non-interactive start exits 2.

## C. Screen gate (phase 6)
- [ ] Every option numbered NN with icon, label and description; no letter keys.
- [ ] Every question has help; every typed question has an example and validation.
- [ ] Success/Warning/Error/Info use the shared icons and roles.
- [ ] Works with `NO_COLOR=1` and with `<APP>_ICONS=ascii`; no output wider than the window.

## D. Compatibility gate (phase 8)
- [ ] No OS check outside Platform; no 7-only syntax; ASCII-only source.
- [ ] Paths built with Join-Path and used with -LiteralPath.
- [ ] Launchers: `.bat` CRLF, `.sh` LF + exec bit; run from a path with spaces.
- [ ] Tests executed on each claimed environment; UNVERIFIED items listed.

## E. Release gate (phase 11)
- [ ] `VERSION`, README badge, CHANGELOG, About screen agree.
- [ ] Package built from the final commit, contents inspected, extracted into a folder with spaces, `-Version` OK, SHA-256 recorded.
- [ ] Release notes only state verified facts; known limitations listed.
- [ ] Tag and release verified to exist after publishing.

## F. Final cleanup (phase 12)
- [ ] No secrets, tokens, personal data or absolute local paths in any file.
- [ ] No temp files, logs, `dist/` content or caches in the package.
- [ ] README explains install, run, keys, exit codes, troubleshooting.
