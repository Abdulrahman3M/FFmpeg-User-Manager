# Packaging and Release

Use in SKILL.md phases 9-11.

## 1. Versioning

* Semantic Versioning 2.0.0: `MAJOR.MINOR.PATCH` (+ optional `-alpha.N`, `-beta.N`, `-rc.N`). PATCH = fixes, MINOR = backward-compatible features, MAJOR = breaking changes. While MAJOR is 0 anything may change between MINOR versions.
* `1.0.0` is a statement ("complete, tested on every supported runtime, documented, judged stable"), never a cosmetic choice. Keep `0.x` until the manual verification items are done.
* The file `VERSION` (first line, no `v`) is the ONLY source of truth. The app reads it (header, About, `-Version`); the package name and the Git tag derive from it; the README badge must equal it (a test checks).
* `VERSION` changes only when a release is prepared. Work in between is listed under `[Unreleased]` in `CHANGELOG.md`.

## 2. Changelog

Keep a Changelog format: `## [Unreleased]`, then `## [X.Y.Z] - YYYY-MM-DD` sections with `Added / Changed / Fixed / Removed`. Entries are user-relevant sentences, not commit messages. On release: rename `[Unreleased]`, open a fresh one.

## 3. Package

* `Scripts/New-TuiPackage.ps1` builds `<Name>-v<VERSION>.zip` containing only what end users need: launchers, entry script, `VERSION`, `README.md`, `CHANGELOG.md`, `LICENSE`, `NOTICE`, `config/`, `src/`, `docs/`. Excluded: `tests/`, `.git`, `.github`, `dist/`, logs, secrets.
* The archive has ONE top-level folder so extraction never scatters files.
* Build it from the final merged commit, on the platform you target (PowerShell 5.1 `Compress-Archive` writes backslash entry names; build with PowerShell 7 or verify extraction on Windows).
* Verify before attaching: list the contents; extract into a folder whose name contains spaces and parentheses; run `-Version`; start the app with `-ScriptedInput` exit; compute SHA-256 and publish it.

## 4. Launchers

* `.bat`: locate its own folder (`%~dp0`), prefer `pwsh.exe`, fall back to `powershell.exe`, bypass the execution policy for THIS process only, pass `%*`, return the exit code, no parenthesized blocks (paths containing `)` break them), CRLF line endings, never echo untrusted command lines unquoted.
* `.sh`: `#!/bin/sh`, resolve its own folder, require `pwsh`, `exec`, LF endings, executable bit.
* Tests for launchers run the real interpreter; see Testing-Strategy.md.

## 5. Release checklist (in order)

1. Scope complete; all gates of the previous phases passed.
2. Full test matrix green on every supported environment (record counts, run id, commit).
3. Licensing reviewed: `LICENSE` unchanged, `NOTICE` current, third-party material listed, nothing bundled that has not been reviewed.
4. `CHANGELOG.md` moved to `[X.Y.Z] - date`; `VERSION` updated; README badge and mentions match; docs and screenshots reflect the final UI (screenshots come from the real app, never mock-ups).
5. Release notes written (summary, highlights, requirements, quick start, known limitations, upgrade notes) - only claims that were actually verified.
6. Merge to the default branch through a pull request with passing checks.
7. Annotated tag `vX.Y.Z` on the merge commit; release page with the notes and the zip + SHA-256.
8. Verify the published tag and release exist, the asset downloads, and the checksum matches.
9. Start `[Unreleased]` again.

## 6. When the environment cannot create tags/releases

Some automation environments block tag/release API calls. Do not work around the block silently: ask the owner, then use a **repository-owned manual workflow** (`workflow_dispatch`, `permissions: contents: write`, uses the repo's own token) that checks `VERSION` against its input, builds and verifies the package, creates the annotated tag and the release with the notes file and attaches the zip and `SHA256SUMS.txt`. Never publish for every commit.
