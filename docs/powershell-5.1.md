# Windows PowerShell 5.1 baseline

The script targets Windows PowerShell 5.1, shipped with Windows 10/11.
PowerShell 7 is optional. The hidden worker explicitly launches the system
`powershell.exe`, even when the visible script was started in PowerShell 7.

The baseline uses .NET Framework-compatible random generation and hashing,
CurrentUser DPAPI, and HTTP APIs. It does not call PowerShell 7-only members or
require `pwsh.exe`. CI checks 5.1 and optional 7 compatibility; each binary
architecture receives a Windows PowerShell 5.1 native HTTP smoke test.

## Downloaded scripts and execution policy

This script is unsigned. Windows can mark downloaded ZIP contents as originating
from the internet. After verifying the download, unblock just the entry script:

```powershell
Unblock-File -LiteralPath .\CuaLink.ps1
.\CuaLink.ps1
```

If the effective policy is Restricted, a trusted local invocation can use a
process-only policy; it does not change the machine or user policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\CuaLink.ps1
```

Organizational policies may still require signing. Inspect
`Get-ExecutionPolicy -List` and follow your organization's policy. No automatic
policy changes, unblocking, or security prompt bypasses are performed by this tool.

Windows OpenSSH Client must be installed/enabled. CUA is bundled in integrated
Windows ZIPs, so a separate CUA installation or PATH change is not required.

## Validation on 2026-09-15

Windows PowerShell 5.1.26100.9444 with CUA 0.28.1 passed local configuration tests,
random-token tests, real desktop window/image capture over HTTP, and a full SSH
key start/status/repeated-start/stop sequence using a directory containing spaces.
The supervisor process was confirmed to be `powershell`, and the remote test
port was released after stop. Existing links were not interrupted.

Actual password login and full ARM64 desktop GUI actions are separate compatibility
checks; do not infer those from native HTTP smoke tests alone.
