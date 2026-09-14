# Changelog

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
