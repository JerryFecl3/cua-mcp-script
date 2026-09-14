# Configuration / 配置

Connection settings live in `config.ini` next to `CuaLink.ps1`. The first menu
launch creates it from `config.example.ini`, without overwriting an existing file.
You can also copy the template before the first run. INI is read as UTF-8 data,
never executed as PowerShell. Use one [CuaLink] section, Key=Value lines and
unquoted values. Blank lines and whole-line comments starting with ; or # are
supported. Inline comments are not supported: punctuation after = is part of
the value, preserving tokens containing =, ; or #. Duplicate keys are rejected.

连接设置保存在脚本旁的 `config.ini`。首次双击 `run.cmd` 会自动生成此文件，
也可以自行复制 `config.example.ini` 并改名。编辑配置后选择 Start 即可读取；
正在运行的连接不会自动变更，需要先 Stop 再 Start。

| Setting | Meaning / 含义 |
| --- | --- |
| BearerToken | Preset: 32–4096 non-whitespace characters / 预置模式必填，无空白字符 |
| SshHost | Linux SSH hostname or IP / SSH 目标主机 |
| SshUser | SSH username / SSH 用户名 |
| SshAuthMode | `key` or `password`; passwords always prompted / 密码模式每次启动输入密码 |
| SshPort | SSH port, 1–65535 / 默认 22 |
| LocalPort | Windows CUA port, 1–65535 / 默认 19222 |
| RemotePort | Linux mapped port, 1–65535 / 默认 19222 |

Leave every value empty for interactive input with a fresh random Bearer token.
Once any value is filled, all seven settings are required. Ports must be integers
without quotes. There is no configuration switch. Passwords cannot be stored.

所有值留空时使用交互输入，token 自动随机生成；填入任意值时，七个配置项必须填全。
不再设置总开关，配置文件不支持保存 SSH 密码。
所有值均不加引号，注释单独一行以 `;` 或 `#` 开头，不要把注释放在值的后面。
模板不含注释；各项说明、默认端口及 token / SSH key 生成命令均在本文中。

## Generate a Bearer token / 生成 token

Run in Windows PowerShell 5.1 and paste the result into `BearerToken`:

```powershell
$b = New-Object byte[] 32; $r = [Security.Cryptography.RandomNumberGenerator]::Create()
$r.GetBytes($b); $r.Dispose(); [BitConverter]::ToString($b).Replace('-', '')
```

This generates 64 hex characters. It is not an SSH login key. To generate an SSH
key, use `ssh-keygen -t ed25519` and install only the `.pub` public key in the
Linux user's `~/.ssh/authorized_keys`. Keep the private key on Windows. Key mode
uses OpenSSH identities/config/agent; unlock encrypted keys in ssh-agent first.

上述命令生成 64 位十六进制 token，不是 SSH 密钥。SSH 密钥使用
`ssh-keygen -t ed25519` 生成，仅将公钥放到 Linux 的 `~/.ssh/authorized_keys`。
有口令的私钥需要事先通过 ssh-agent 解锁。

## Upgrades / 升级

Stop the old link before upgrading. Release ZIPs contain only the clean
`config.example.ini`, so extracting an update into the same directory preserves
your `config.ini`. When moving to a new directory, copy your config.ini there.
Keep it private: a fixed token is stored there in plain text. Git ignores this file
and the packager never includes it.

升级前先 Stop。新版 ZIP 仅包含模板，不含个人 `config.ini`，覆盖解压到原目录
即可保留配置；换目录时复制 `config.ini`。固定 token 在配置中以明文保存，请勿分享。

From 0.2.x: transfer your old connection settings manually into config.ini, omitting
the old switch. Do not copy the old customized PS1 over the new
one. Passwords remain interactive. Stop and Status use saved runtime state and
continue working even if config.ini is invalid.

从 0.2.x 升级：将旧脚本里的连接参数手动填入 `config.ini`，不再复制总开关；
不要用旧 PS1 覆盖新版。配置损坏不会影响 Stop / Status。

From 0.3.0: remove the UseConfig line and comments. For fixed settings, keep all
seven values filled. For interactive input, clear all seven values, including
ports and authentication mode. Existing personal config files are never rewritten.

从 0.3.0 升级：删除 UseConfig 行和注释。固定配置保留七项完整值；交互输入则将
七项值全部清空，包括端口和认证模式。程序不会自动重写个人配置文件。

## Validation

Windows PowerShell 5.1 passed INI parsing and rejection checks (missing fields,
duplicate keys, unknown settings, invalid ports/tokens), UTF-8 comments, and token
punctuation preservation. A local SSH-key integration run verified template
creation, configuration preservation, start/repeated-start, and status/stop with
an invalid INI file. Password login and full ARM64 desktop certification remain
separate checks.
