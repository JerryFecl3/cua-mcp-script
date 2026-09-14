# 0.1.0 validation record

Date: 2026-09-15. Windows x64, PowerShell 7, OpenSSH for Windows 9.5p2,
official installed CUA Driver 0.28.1. This is a source-release validation record,
not a certification of an automatically built binary candidate.

Passed locally:

- PowerShell syntax and configuration/output-contract checks.
- Isolated CUA HTTP initialization, unauthenticated 401, expected tool names.
- Real interactive Explorer enumeration and inline MCP screenshot response.
- Published script run from a directory containing spaces.
- Preset SSH key login to a Linux host using independent local/remote test ports.
- Repeated Start reused the same supervisor; Status returned successfully.
- Stop cleaned up; the remote test port was no longer listening.
- Existing user link was not interrupted by these tests.

The original prototype was also used successfully by the user with Codex and
Hermes. Those historical client tests are not automated regression coverage.

Still required before binary release certification:

- Exact candidate SHA256 and all rows in release-checklist.md.
- Actual SSH password login and wrong-password behavior.
- Fault injection for connection loss, local/remote port conflicts.
- GUI text input/readback through both clients against the exact candidate.
- Maintainer review of bundled native dependencies and license/source notices.

No passwords, tokens, host addresses or screenshots are included in this record.
