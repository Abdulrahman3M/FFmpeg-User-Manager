# Lessons From the Reference Implementation

The principles in this skill were extracted from a large Windows-first PowerShell TUI (about 27 guided workflows, 1,300+ automated checks). The defects below were found by running the suite on real Windows runners; each is a general trap, not a project detail. Read this before designing tests or release gates.

| # | What happened | General rule |
|---|---|---|
| 1 | A tool's list command printed a different column layout in a newer version; the parser silently found 0 items and many features switched themselves off | Parse tool output defensively (optional columns), add a regression test with the NEW format, and make "0 items found" a visible diagnostic, never a silent state |
| 2 | A test chose a menu entry by position; on Windows an extra (usable hardware) option appeared and every later answer was wrong; the wizard stalled | Choose options by LABEL in tests; make a stalled scripted flow print the last screen |
| 3 | An endless generated video was bounded only by `-shortest`; newer FFmpeg made the result nondeterministic | Bound endless sources explicitly with a known duration |
| 4 | Output redirected on Windows lost its glyphs (OEM code page) | Set console output to UTF-8 on Windows even when redirected |
| 5 | A launcher stub written as `.cmd` never returned to the calling `.bat` on real `cmd` | Stubs for launcher tests must be real executables; test on the real interpreter |
| 6 | The launcher echoed the command line to detect a double-click; `&` in a folder name executed text as a command | Never expand untrusted text unquoted in batch files; use delayed expansion in a tiny block and strip quotes first |
| 7 | Tests read `$IsWindows`; under StrictMode on 5.1 it does not exist and two tests silently became UNVERIFIED | One helper (`Test-IsWindows`) for tests and code |
| 8 | Test files with non-ASCII text were read as ANSI by 5.1 | UTF-8 BOM for such test files, ASCII-only for source |
| 9 | `Get-ChildItem -LiteralPath ... -Include` returned directories on 5.1; static tests crashed | Enumerate with `-File` and filter by extension |
| 10 | A real package-manager binary was present on the CI runner and changed test behavior | Tests hide external tools behind hooks instead of trusting the host |
| 11 | A package-manager shim copied elsewhere stopped working | Copy the real executable when a test needs an isolated PATH |
| 12 | Fixtures used characters that are illegal in Windows file names (`:` `"`) | Generate fixture names valid on the strictest platform, vary only by platform guard |
| 13 | A script-scope helper variable shared the name of the script's `-Demo` parameter | Names are case-insensitive and share scope; prefix module state |
| 14 | `pwsh -Command` joined extra arguments into the command text, so "argument count" tests lied | Pass data to child PowerShell with `-File` |
| 15 | Scripts ran under StrictMode and `$script:Tier` was unset at first use | Initialize module state at the top of the module |
| 16 | Many UNVERIFIED items hid real defects (a test that could not run was assumed fine) | Attempt the condition for real; keep UNVERIFIED for what truly cannot run; list each with local steps |
| 17 | Re-running the whole suite per guess wasted hours | Isolated repro workflows + diagnostics first, one deliberate full run after the proof |

Process lessons: keep screenshots from the real app and say how they were captured; keep a Windows verification script for humans (`Test-WindowsLocal`-style) listing the checks machines cannot do; keep the release reproducible through a manual workflow; write every claim in the release notes only after a run proved it.
