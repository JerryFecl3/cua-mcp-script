# cua-mcp-script

A single PowerShell entry point that exposes a Windows [Cua Driver](https://github.com/trycua/cua)
HTTP MCP endpoint to a Linux machine through an authenticated SSH reverse tunnel.

[简体中文](README.zh-CN.md)

```text
Codex / Hermes on Linux → Linux 127.0.0.1:19222
                               │ SSH reverse tunnel
                         Windows 127.0.0.1:19222 → Cua Driver → Windows desktop
```

No MCP bridge or custom desktop driver. Start, stop and status are managed by the
same script. Closing the start window leaves a hidden supervisor running; when
either CUA or SSH exits, it stops the other child. Automatic reconnection is not implemented.

## Requirements

- Windows interactive desktop, Windows PowerShell **5.1** (included with Windows 10/11), Windows OpenSSH client.
- Official Cua Driver on PATH, or a matching Windows x64 or ARM64 bundle under `cua/`.
- An SSH-accessible Linux machine with remote TCP forwarding enabled, `ss`, `grep`, `curl`.
- Existing SSH host trust. First run `ssh user@host -p 22` and verify the host fingerprint.
- Key authentication uses OpenSSH's existing identities/config/agent. Unlock encrypted
  private keys in an agent first. Password mode uses an automatically compiled
  SSH_ASKPASS adapter; Windows .NET Framework's C# compiler must be installed.

Launch from your actual logged-in desktop, not a Windows SSH/service session or
an agent sandbox: those may see an isolated desktop.

## Quick start

Extract the integrated ZIP and double-click **run.cmd**. It unblocks only the
adjacent CuaLink.ps1 and starts Windows PowerShell 5.1 with process-only
RemoteSigned, without changing your user or machine execution policy.
Organization-enforced policies still apply. Command-line arguments also work:
`run.cmd status -NoPause`.

The baseline is **Windows PowerShell 5.1**. PowerShell 7 is not required. Integrated
Windows ZIPs include CUA: choose x64 for Intel/AMD PCs or ARM64 for ARM PCs.

Download the repository or a release. Source-only releases do **not** include CUA.
Obtain CUA from [official releases](https://github.com/trycua/cua/releases) and use
`windows-x86_64-binary.zip` for x64 or `windows-arm64-binary.zip` for ARM64. Preserve all files together:

```text
cua-mcp-script/
  run.cmd
  CuaLink.ps1
  config.example.ini      # clean template shipped in releases
  config.ini              # generated locally; preserved on upgrade
  cua/
    cua-driver.exe
    cua-driver-uia.exe
    cua-cursor-theme.exe
    cua_driver_sdk.dll
    cua_driver_node_runtime.node
    cua_driver_abi.h
  .runtime/                 # generated locally; never commit
```

The script prefers `cua/cua-driver.exe` and otherwise resolves `cua-driver` on PATH.

```powershell
powershell.exe -NoProfile -File ./CuaLink.ps1
# Or:
./CuaLink.ps1 start
./CuaLink.ps1 status
./CuaLink.ps1 stop
```

Select Start, enter host/user/ports, and enter a password or press Enter for key
authentication. Default SSH port is 22; both MCP ports default to 19222. A new
random token is generated for each fresh interactive start.

```text
CUA link: running
SSH target: user@host connected
MCP Transport: Streamable HTTP
MCP address: http://127.0.0.1:19222/mcp
Authorization: Bearer ...
```

Start and Status display the same connection block. The MCP address is on the
**Linux SSH destination**, not a public URL. Press Enter to leave the script;
an existing PowerShell terminal returns to its prompt. Run Stop to close the link.
For unsigned/downloaded script errors, see [PowerShell 5.1 and execution policy](docs/powershell-5.1.md).
`-NoPause` skips the final Enter prompt only, not required configuration/password prompts.

## Preset configuration

Edit **config.ini**, created from `config.example.ini` on first launch, or copy
the template yourself. No PowerShell script edits are needed. See
[configuration and upgrades](docs/configuration.md).

```ini
[CuaLink]
UseConfig=true
BearerToken=<32-4096 non-whitespace characters>
SshHost=your-linux-host
SshUser=your-user
SshAuthMode=key
SshPort=22
LocalPort=19222
RemotePort=19222
```

All these fields are required in preset mode. Missing fields fail instead of
silently prompting. Passwords cannot be preset: `password` mode always prompts
securely on each new start. `key` mode never asks for a password.

With `UseConfig=false`, the connection presets are ignored and collected
interactively; the token is random. To generate a fixed Bearer token in Windows PowerShell 5.1:

```powershell
$b = New-Object byte[] 32; $r = [Security.Cryptography.RandomNumberGenerator]::Create()
$r.GetBytes($b); $r.Dispose(); [BitConverter]::ToString($b).Replace('-', '')
```

This token is separate from an SSH key. Create an SSH key with `ssh-keygen -t ed25519`
and install its **public** key in the Linux user's `~/.ssh/authorized_keys`.

## MCP clients

### Codex CLI (on Linux)

```sh
read -rsp 'CUA token: ' CUA_MCP_TOKEN; echo
export CUA_MCP_TOKEN
codex mcp add windows_cua --url http://127.0.0.1:19222/mcp --bearer-token-env-var CUA_MCP_TOKEN
codex
```

Load the variable in the same terminal that starts Codex. Update it after a new
random token is generated. Already running clients may need to reconnect.

### Hermes

Merge into `~/.hermes/config.yaml` (preserve other servers):

```yaml
mcp_servers:
  remote-windows-pc:
    url: http://127.0.0.1:19222/mcp
    headers:
      MCP-Protocol-Version: "2025-06-18"
      Authorization: "Bearer YOUR_TOKEN"
```

Reload/restart the client. CUA 0.28.1 HTTP rejects the `2025-11-25` protocol header
used by the tested Hermes SDK; explicitly requesting `2025-06-18` fixed it.
This is an observed compatibility requirement, not a guarantee for future CUA releases.

## Tests and releases

Run these developer tests from a repository checkout (not the runtime-only ZIP):

```powershell
./tests/Test-Script.ps1
./tests/Test-CuaHttp.ps1 -Driver ./cua/cua-driver.exe
# Dedicated logged-in test desktop with an empty Explorer folder open:
./tests/Test-CuaHttp.ps1 -Driver ./cua/cua-driver.exe -Desktop
```

Original prototype: CUA 0.28.1 Windows x64, SSH key login, real window/screenshot
access, and user-confirmed Codex/Hermes control were exercised. Password adapter
encryption/decryption was tested locally; actual password SSH login remains a
release-checklist item. Hosted CI is **not** a desktop certification.

- **Script checks:** syntax, configuration constraints, output contract and clean defaults.
- **Build CUA candidate:** weekly/manual discovery of the latest stable driver tag,
  SHA256 verification, exact package-layout gate, license collection/review gate,
  and Windows HTTP smoke test; uploads a candidate artifact only after passing.
- **Publish tested candidate:** maintainer-only manual dispatch, successful original
  candidate run, test report URL and license-review attestation; publishes the
  original checksummed artifact without rebuilding. Configure the `release`
  environment with required reviewers for a second-person approval policy.

Stable CUA driver tags are matched by `cua-driver-rs-vX.Y.Z`. Upstream marks even
stable driver releases as GitHub prereleases, so GitHub's repository-wide `/latest`
is not used. Nightlies are intentionally excluded from automatic candidates.

See [release checklist](docs/release-checklist.md). A failed license check, changed
archive layout or incompatible protocol blocks the candidate; the last published
release remains available. The build script requires Python 3.12+ and Rust/Cargo.

## Licenses

This wrapper is MIT. CUA has its own MIT license; its `.node` compatibility runtime
is MPL-2.0. Binary bundles include upstream/third-party notices and source pointers.
The license gate is conservative and may require maintainer review on new dependencies;
it is not a substitute for reviewing the exact redistributed artifact.

Official references: [CUA license](https://github.com/trycua/cua/blob/cua-driver-rs-v0.28.1/LICENSE.md),
[Node runtime notice](https://github.com/trycua/cua/blob/cua-driver-rs-v0.28.1/libs/cua-driver/scripts/node-runtime-NOTICE.md).

This independent project is not affiliated with or endorsed by Cua, OpenAI or Hermes.

