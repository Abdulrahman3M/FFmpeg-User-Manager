# FFmpeg User Manager v0.3.0

**A backward-compatible MINOR release** in the 0.x pre-release series, succeeding v0.2.0. This release is published as `v0.3.0` on the official project repository.

## Highlights

- **Full Edition — Recommended:** deterministic Windows x64 package with bundled, manifest-verified FFmpeg, ffprobe and Assimp runtime files. Bundled FFmpeg is selected before custom/system paths; runtime health and required capabilities are checked centrally.
- **Lite Edition:** smaller Windows x64 package with no external runtime executable or DLL. It uses the supported custom/system runtime resolution path.
- **Safe maintenance:** FFmpeg updates require explicit consent, use the pinned WinGet package, stage and verify a candidate, activate transactionally and retain/restore the known-good runtime on failure.
- **Reproducible packaging:** Full and Lite share one source revision and app version. The builder checks runtime hashes, byte sizes, PE architecture, licenses and FFmpeg build flags; output includes edition metadata and SHA-256 checksums.
- **Release validation:** both locally built editions were extracted under a Unicode/spaced path, launched through their supported entry points and checked for runtime contents. Full OBJ-to-GLB integration conversion was exercised successfully. The manual-only GitHub Actions release workflow was not run.

## Runtime versions and licenses

- FFmpeg/ffprobe: Gyan `Gyan.FFmpeg.Shared` 9.0.2, x64, GPL-3.0. The verified runtime reports `--enable-gpl`, `--enable-version3`, `--enable-shared`, and `--enable-libssh`. Full preserves the upstream GPLv3 text, Gyan README, exact FFmpeg source revision and actual `-buildconf` output.
- Assimp: 6.0.5-2 MSYS2 Clang64 x64 package, BSD-3-Clause, with the reviewed runtime dependency tree and original license texts.
- No newer stable Gyan FFmpeg release or Assimp upstream/MSYS2 package was found in the official metadata checked on 2026-10-16. A newer unverified/nightly runtime was not adopted.

## Compatibility

| Component | Windows 7 | Windows 8 / 8.1 | Windows 10 | Windows 11 x64 | Linux |
|---|---|---|---|---|---|
| Application and extracted Full/Lite package integration | UNVERIFIED | UNVERIFIED | UNVERIFIED | PASS | NOT APPLICABLE (Windows package) |
| Bundled FFmpeg and Assimp runtimes | UNVERIFIED | UNVERIFIED | UNVERIFIED | PASS | NOT APPLICABLE (Windows binaries) |

Windows 11 x64 (build 26100) was exercised with Windows PowerShell 5.1 and PowerShell 7.6.5. No end-to-end compatibility claim is made for other Windows versions; the upstream Gyan provider's stated OS requirements are not a substitute for project verification. See [Testing](Testing.md) and the [runtime manifest](../External-Libraries/manifest.json).

## Known limitations and security

The selected stable FFmpeg 9.0.2 runtime is affected by public advisories [CVE-2026-107675](https://nvd.nist.gov/vuln/detail/CVE-2026-107675) (SFTP host verification), [CVE-2026-107676](https://nvd.nist.gov/vuln/detail/CVE-2026-107676) (crafted HDR metadata may disclose a few uninitialized bytes in output), [CVE-2026-107677](https://nvd.nist.gov/vuln/detail/CVE-2026-107677) (crafted DASH manifest can hang), [CVE-2026-107678](https://nvd.nist.gov/vuln/detail/CVE-2026-107678) (crafted MP4 can exhaust the stack), and [CVE-2026-107696](https://nvd.nist.gov/vuln/detail/CVE-2026-107696) (RTSP redirect loop). The pinned build has not been replaced because no newer stable package passed project verification at preparation time. Until a fixed stable package is verified, avoid SFTP URLs, untrusted DASH/RTSP endpoints and untrusted media containing crafted MP4, Matroska, HEVC or AV1 metadata. Full does not claim to be free of these known vulnerabilities.

OBJ material/texture retention still depends on source data and exporter behavior; review converted assets in a 3D viewer. Historical screenshots do not show the current menu inventory. Real Windows Terminal/classic-console rendering and physical device capture checks remain manual.

## Downloads

Download assets: `FFmpeg-User-Manager-v0.3.0-Full-Windows-x64.zip` (recommended), `FFmpeg-User-Manager-v0.3.0-Lite-Windows-x64.zip`, and `SHA256SUMS-v0.3.0.txt`. Verify the ZIP checksum against the published checksum file before extracting. Full bundles FFmpeg/ffprobe under GPL-3.0 and Assimp with its dependency licenses; Lite bundles no external runtime executables or DLLs. Review the known security advisories above before using Full with untrusted media.
