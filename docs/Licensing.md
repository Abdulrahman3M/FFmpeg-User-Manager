# Licensing and intellectual property

FFmpeg User Manager is licensed under the **Apache License, Version 2.0** (SPDX identifier `Apache-2.0`).

| File | Purpose |
|---|---|
| [`LICENSE`](../LICENSE) | The unmodified standard Apache-2.0 text (byte-identical to <https://www.apache.org/licenses/LICENSE-2.0.txt>; a test checks its SHA-256 fingerprint) |
| [`NOTICE`](../NOTICE) | Copyright notice and attribution statement, plus the third-party statement. Apache-2.0 requires this file to be kept by anyone who redistributes the project |
| [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md) | Per-runtime ownership, license, source and package summary; copied into both release editions |

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
| FFmpeg (`ffmpeg.exe`, `ffprobe.exe`, DLLs) | Started as a separate process with argument arrays; Full defaults to its verified bundled runtime | **Full: Yes. Lite: No.** Full package uses the exact Gyan `Gyan.FFmpeg.Shared` 9.0.2 x64 build. Lite relies on configured/system FFmpeg. The app may also install/update FFmpeg through the previously consented WinGet flow. | This exact build reports **GPL-3.0** (`--enable-gpl --enable-version3`) and preserves its original GPLv3 text and Gyan README in Full. The runtime has separate terms; these do not relicense the application source. Source commit and actual `-buildconf` output are recorded in generated `External-Libraries/FFmpeg/SOURCE.txt`. See <https://ffmpeg.org/legal.html> and [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md). |
| Windows Package Manager (`winget`) | Optional installer helper, started as a separate program | No (part of Windows) | Microsoft's terms |
| PowerShell 5.1 / 7.x | Runtime | No | Microsoft's terms (Windows PowerShell) / MIT (PowerShell 7) |
| Icons | Unicode characters drawn by the terminal's own font; no image files | No assets exist | Nothing to attribute |
| Screenshots in `docs/images/` | Captured from the running application | Part of the documentation (Apache-2.0) | The terminal fonts used for the capture (DejaVu Sans Mono, Noto Color Emoji) are not included in the repository |
| Assimp 6.0.5 and runtime dependencies (LLVM libc++/libunwind, minizip, bzip2, zlib-ng-compat) | Bundled CLI and required runtime DLLs for OBJ-to-GLB | **Full: Yes. Lite: No.** Versions, package checksums and runtime inventory are in [`External-Libraries/manifest.json`](../External-Libraries/manifest.json); full original license texts ship in Full under `External-Libraries/Assimp/licenses/`. | Assimp BSD-3-Clause; LLVM Apache-2.0 WITH LLVM-exception; minizip/zlib-ng zlib license; bzip2 permissive license. |

The Assimp runtime tree was reviewed package by package for license compatibility, dependency edges and original license texts. Its listed licenses are permissive and the full texts/attribution are shipped in Full. FFmpeg is copyleft GPL-3.0 in this exact build; the owner-approved Full packaging workflow includes the upstream license, Gyan attribution/readme, source revision and actual build configuration. Bundling FFmpeg does not make this Apache-2.0 project source Apache-only or change FFmpeg's own license. The FFmpeg project publishes licensing guidance at <https://ffmpeg.org/legal.html>; this documentation is an inventory, not legal advice. Future updates/distribution must follow sections 8, 8.1 and 8.2 of [AGENTS.md](../AGENTS.md), and maintainers must verify that corresponding-source obligations are met before official distribution.

## Rules for contributors and AI agents

Summarized from [AGENTS.md](../AGENTS.md), sections 8-8.2:

* Never delete or weaken `LICENSE`, `NOTICE`, copyright lines or a third party's required notices.
* Before adding a dependency (library, font, icon set, image, script) or shipping a release, check **license compatibility**, add the **third-party notice** and satisfy the
  **copyright/attribution** terms of that license. Permissive licenses (MIT, BSD, Apache-2.0) fit; copyleft licenses (GPL/AGPL/LGPL) need an owner decision first.
* Full Edition is an explicit owner-approved exception to the no-unapproved-copyleft rule; it must retain the exact FFmpeg license/source/configuration information. Lite excludes runtime binaries.
* Both Full and Lite archives carry the root `LICENSE`, `NOTICE`, and `THIRD-PARTY-NOTICES.md`; Full additionally carries original runtime license texts.
* Per-file copyright headers are not required for project-authored code. Third-party files keep their own notices and license terms.

## GitHub metadata

GitHub detects the license automatically from the root `LICENSE` file and shows **Apache-2.0** in the repository's *About* panel. The repository stays **Private**;
choosing a license does not change visibility and nothing is published.
