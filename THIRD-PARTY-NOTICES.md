# Third-party notices

FFmpeg User Manager is licensed under Apache-2.0. This file records separately licensed runtime components included only in generated **Full Edition** packages. Lite packages include the inventory/notice documents but contain no external runtime executable or DLL. The project does not claim authorship of these components or relicense them.

| Component | Version / package | License | Full package contents and source |
|---|---|---|---|
| FFmpeg (`ffmpeg.exe`, `ffprobe.exe`, FFmpeg DLLs) | 9.0.2; Gyan `Gyan.FFmpeg.Shared` x64 shared full build | GPL-3.0 | Exact package hash and files are in [`External-Libraries/manifest.json`](External-Libraries/manifest.json). The upstream source revision is [FFmpeg commit 946fcce07b](https://github.com/FFmpeg/FFmpeg/commit/946fcce07b); `External-Libraries/FFmpeg/SOURCE.txt` in Full records the runtime-reported `-buildconf` flags and source archive reference. Gyan's package README is also included. See the [FFmpeg licensing guidance](https://ffmpeg.org/legal.html). |
| Assimp | 6.0.5-2; MSYS2 Clang64 x64 package | BSD-3-Clause | `assimp.exe`, `libassimp-6.dll`, package checksum, source and original license are identified in the manifest and `External-Libraries/Assimp/licenses/`. |
| LLVM libc++ and libunwind | 22.1.7-1; MSYS2 Clang64 | Apache-2.0 WITH LLVM-exception | Required runtime DLLs and original notices are listed in the manifest and shipped under `External-Libraries/Assimp/licenses/`. |
| minizip | 1.3.2-2; MSYS2 Clang64 | zlib | Required runtime DLL and original license are listed in the manifest and shipped under `External-Libraries/Assimp/licenses/`. |
| bzip2 | 1.0.8-3; MSYS2 Clang64 | bzip2 permissive license | Original license is shipped under `External-Libraries/Assimp/licenses/`. |
| zlib-ng-compat | 2.3.3-2; MSYS2 Clang64 | zlib | Required runtime DLL and original license are listed in the manifest and shipped under `External-Libraries/Assimp/licenses/`. |

The exact package archive hashes, runtime-file SHA-256 values, dependency edges, acquisition sources, architectures and platform evidence are maintained in the canonical manifest. The release builder rejects files whose hashes, sizes, architecture, versions, licenses or required build flags do not match its verified metadata. It does not download arbitrary files from URLs.

## FFmpeg configuration and source

The selected Gyan build reports GPL-3.0 and `--enable-gpl --enable-version3`; it is therefore not described as LGPL-only. Full packages preserve its upstream GPLv3 text and Gyan README, identify the exact FFmpeg source revision, and record the real build configuration obtained from `ffmpeg -buildconf`. The build includes GPL-licensed components including x264/x265, as reflected in its configuration.

The Gyan WinGet archive hash and the per-file hashes are pinned in the manifest. The source revision link above and the generated `SOURCE.txt` identify the corresponding upstream FFmpeg source and build configuration. The FFmpeg project's legal page describes its source-distribution guidance; maintainers must re-check the applicable obligations and make the corresponding source available with any official binary release.

The five currently reviewed FFmpeg 9.0.2 advisories are recorded in the manifest and in the v0.3.0 release notes. They are disclosed as known limitations; no claim is made that this runtime is security-current beyond the checked stable package metadata date.
