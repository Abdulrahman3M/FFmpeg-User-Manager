# Testing Strategy

Use in SKILL.md phases 8-10. A claim is only as good as the run that proves it. Report PASS / FAIL / UNVERIFIED honestly; never mark PASS for something that did not execute.

## 1. Test pyramid for a TUI

| Level | What | How |
|---|---|---|
| **Unit** | pure functions: validators, parsers, tier decision, number resolution, argument quoting, command builders | direct calls, many small assertions |
| **UI flow** | menus, prompts, dialogs, whole screens | **scripted input** (`Set-ScriptedInput '02{Enter}'`) + **Buffer sink** (`Initialize-Renderer -Sink Buffer`): the test reads exactly what the user would see |
| **Process smoke** | the real entry script as a child process | `-Version`, `-ScriptedInput '05'`, non-interactive refusal (exit 2), forced icon tiers, failure path restores the terminal |
| **Launcher** | `.bat` with the real `cmd`, `.sh` with a real shell | sandbox with stub executables ON PATH; stubs must be real executables on Windows |
| **Static** | the rules by syntax tree | ASCII-only, parse, no `Invoke-Expression`, no 7-only syntax, platform variables only in Platform, every `New-MenuItem` has a description, param/local name collisions, CRLF/LF |
| **Manual checklist** | what no machine here can see | real Windows Terminal rendering, real devices, real installers |

## 2. Rules for the test harness

1. Tests never touch the real user profile: override the data folder (`<APP>_DATA_DIR`) and use a temp work folder removed afterwards.
2. A test that runs out of scripted keys must FAIL loudly (`Scripted input exhausted.`), and an error from the scripted flow must carry the last screen text - this turns "the wizard stalled" into a readable diagnosis.
3. Select options by their LABEL in tests (`{#libx265}` style macro) rather than by position: the list of choices legitimately differs between machines (hardware encoders, capabilities).
4. A condition that depends on the machine (admin rights, locked files, Wine) is attempted for real; if it cannot be provoked the test is `UNVERIFIED` with the reason - never silently skipped, never PASS.
5. No test depends on another's side effects; each creates its own fixtures (generate small files at run time, do not commit binaries).
6. Source and tests are run under EVERY supported PowerShell edition. A tests file containing non-ASCII text carries a UTF-8 BOM so 5.1 reads it correctly.

## 3. CI matrix (copy and adapt)

```yaml
name: tests
on: { push: { branches: [main] }, pull_request: {}, workflow_dispatch: {} }
jobs:
  windows:
    runs-on: windows-latest
    strategy: { fail-fast: false, matrix: { shell: [powershell, pwsh] } }
    steps:
      - uses: actions/checkout@v4
      - name: Run the suite (${{ matrix.shell }})
        shell: cmd
        run: ${{ matrix.shell }} -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 > suite.log 2>&1
      - name: Failure summary
        if: always()
        shell: pwsh
        run: Select-String -Path suite.log -Pattern '^FAIL:|SUMMARY' | ForEach-Object { $_.Line }
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: suite-log-${{ matrix.shell }}, path: suite.log }
  linux:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pwsh -NoProfile -File tests/Run-Tests.ps1
```

Run the full matrix deliberately (manual dispatch / pull request), not on every push of a working branch; keep the full log as an artifact.

## 4. Diagnosing a failure without guessing

1. Get the exact failing test names per environment. Compare environments: what differs (edition, OS, tool version, hardware, locale, account rights)?
2. Reproduce with the **smallest isolated run** (one test file, or a repro script) in the failing environment - a dedicated workflow that prints every screen, its options and the keys sent.
3. Prove the cause with evidence (a printed list, an exit code, a log line) BEFORE changing code. Decide: product bug, test bug, or environment difference.
4. Fix the root cause once; add a regression test that fails without the fix; re-run the isolated test, then the related suite, then the full matrix once.
5. Never loosen an assertion or skip a test to get green.

Typical root causes seen in practice (details in Lessons-From-The-Reference-Implementation.md): tool output format changed between versions, machine-dependent option lists shifting positional answers, `$IsWindows` unset under StrictMode in 5.1, BOM-less test files read as ANSI, illegal Windows file-name characters in fixtures, batch-to-batch calls that never return, redirected output losing UTF-8.

## 5. Acceptance numbers

Record for each environment: PASS / FAIL / UNVERIFIED counts, the exact commit and run id, and the list of UNVERIFIED items with their local steps. A release needs 0 FAIL on every supported environment.
