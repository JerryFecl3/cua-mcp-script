# Changelog

## 0.2.0

- Windows PowerShell 5.1 is the baseline; PowerShell 7 is no longer required.
- Replace modern .NET-only hashing/RNG APIs and launch the in-box worker host.
- Build Windows x64 and ARM64 bundles using one pinned latest stable CUA tag.
- Run native Windows PowerShell 5.1 HTTP smoke tests for both architectures.
- Document execution policies without automatically changing system settings.

## 0.1.1

- Fix Windows UTF-8 decoding and ZIP timestamps in candidate builds.
- Recover omitted third-party notices from exact dependency source commits.
- Preserve bundle documentation and add packaging regression tests.
- Full CUA 0.28.1 candidate build passed on GitHub Actions; artifact SHA256,
  clean defaults and 645 license/notice files were verified after download.
- Binary publication still requires the dedicated compatibility checklist.

## 0.1.0

- Single Windows PowerShell entry point for start, stop and status.
- Complete preset configuration or fully interactive connection setup.
- Fixed/random Bearer tokens, SSH keys and prompted password authentication.
- Background supervisor with per-directory pipe identity and child cleanup.
- Prefer a colocated official CUA binary, with PATH fallback.
- Codex and Hermes connection examples, including the legacy HTTP version header.
- Windows HTTP smoke tests and conservative, checksum-verified candidate packaging.
- Manual compatibility report and repository-owner approval before binary release.

Initial source release does not bundle CUA. Candidate builds must pass the license
and compatibility gates before a binary release can be approved.
