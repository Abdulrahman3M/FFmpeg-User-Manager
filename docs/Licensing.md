# Licensing and intellectual property

FFmpeg User Manager is licensed under the **Apache License, Version 2.0** (SPDX identifier `Apache-2.0`).

| File | Purpose |
|---|---|
| [`LICENSE`](../LICENSE) | The unmodified standard Apache-2.0 text (byte-identical to <https://www.apache.org/licenses/LICENSE-2.0.txt>; a test checks its SHA-256 fingerprint) |
| [`NOTICE`](../NOTICE) | Copyright notice and attribution statement, plus the third-party statement. Apache-2.0 requires this file to be kept by anyone who redistributes the project |

Copyright holder: **Abdulrahman3M** (the GitHub account that owns the project), year **2026**. The owner may replace that name with a legal name or
organization in `NOTICE` at any time; nothing else needs to change.

## What the license means in plain words

* **Free to use** for any purpose, including commercially, at no cost.
* **Open source**: anyone may read, change and share the code.
* **Redistribution is allowed**, in original or modified form, as long as the recipient also gets the `LICENSE` and keeps the `NOTICE`.
* **Copyright and attribution stay.** Copies and derived works must keep the copyright notices, the license text and the `NOTICE` content, and must say clearly
  which files were changed. Nobody may remove the author's attribution or claim to be the original author.
* **No warranty.** The software is provided "as is"; the authors are not liable for damage caused by using it (sections 7 and 8 of the license).
* **Patent grant.** Contributors grant a patent license for their contributions (section 3); it ends for anyone who sues over patents in the software.
* **No endorsement.** The license does not grant permission to use the project's name or logos as if endorsed by the author (section 6).

This is a summary, not legal advice; the `LICENSE` text is what counts.

## Why Apache-2.0 (comparison of the standard OSI licenses considered)

The goal: free to use, truly open source, redistribution allowed, **original copyright and required attribution must survive**, nobody may claim original authorship,
a clear warranty and liability disclaimer - using a **standard** license, never a custom one.

| License | Permits free use and redistribution | Forces keeping copyright and notices | Explicit attribution file (`NOTICE`) and "state your changes" rule | Explicit patent grant | Verdict |
|---|---|---|---|---|---|
| **Apache-2.0** | yes | yes (sections 4a-4d) | **yes** | **yes** | **Chosen**: strongest standard way to preserve authorship and notices while staying permissive |
| MIT | yes | yes (notice in copies) | no | no (implied only) | Good and very short, but weaker on attribution of changes and no patent language |
| BSD-3-Clause | yes | yes | no | no | Similar to MIT, plus a no-endorsement clause; no `NOTICE` mechanism |
| MPL-2.0 | yes | yes | partly | yes | File-level copyleft: modified files must stay open; more restrictive than the stated goal |
| GPL-3.0 / AGPL-3.0 | yes | yes | no | yes | Strong copyleft: every derived work must also be GPL. Not wanted here ("allow code use per license terms") |
| CC0 / Unlicense | yes | **no** | no | no | Gives up attribution entirely, which contradicts the goal |

Apache-2.0 also keeps the repository's obligations clear: "All Rights Reserved" wording must **not** be used next to it, and no custom conditions are added.

## Third-party components review

| Component | How it is used | Bundled in this repository / release package? | Its license and obligations |
|---|---|---|---|
| FFmpeg (`ffmpeg`, `ffprobe`) | Started as a separate program from the user's computer; command-line arguments only | **No.** Installed by the user, or by `winget` from the `Gyan.FFmpeg` package on the user's own machine | FFmpeg's own license (LGPL 2.1+, or GPL depending on the build; <https://ffmpeg.org/legal.html>). Because it is neither bundled nor linked, its license does not apply to this project's code; users receive it under its own terms |
| Windows Package Manager (`winget`) | Optional installer helper, started as a separate program | No (part of Windows) | Microsoft's terms |
| PowerShell 5.1 / 7.x | Runtime | No | Microsoft's terms (Windows PowerShell) / MIT (PowerShell 7) |
| Icons | Unicode characters drawn by the terminal's own font; no image files | No assets exist | Nothing to attribute |
| Screenshots in `docs/images/` | Captured from the running application | Part of the documentation (Apache-2.0) | The terminal fonts used for the capture (DejaVu Sans Mono, Noto Color Emoji) are not included in the repository |
| Libraries, fonts, scripts from others | none | none | - |

There is therefore **nothing third-party to attribute today**, and `NOTICE` says so. Adding third-party material changes that; follow section 8 of [AGENTS.md](../AGENTS.md).

## Rules for contributors and AI agents

Summarized from [AGENTS.md](../AGENTS.md), section 8:

* Never delete or weaken `LICENSE`, `NOTICE`, copyright lines or a third party's required notices.
* Before adding a dependency (library, font, icon set, image, script) or shipping a release, check **license compatibility**, add the **third-party notice** and satisfy the
  **copyright/attribution** terms of that license. Permissive licenses (MIT, BSD, Apache-2.0) fit; copyleft licenses (GPL/AGPL/LGPL) need an owner decision first.
* Do not bundle FFmpeg without an owner decision (it would bring LGPL/GPL obligations).
* Per-file copyright headers are not required; the root `LICENSE` and `NOTICE` (also included in every release package) are the notice.

## GitHub metadata

GitHub detects the license automatically from the root `LICENSE` file and shows **Apache-2.0** in the repository's *About* panel. The repository stays **Private**;
choosing a license does not change visibility and nothing is published.
