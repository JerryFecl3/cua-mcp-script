# cua-mcp-script

一个 PowerShell 脚本，通过 SSH 反向隧道，让远端 Linux 上的 Codex、Hermes
等 MCP 客户端控制 Windows 桌面。桌面能力和 HTTP MCP 来自官方 Cua Driver。

## 使用

运行基准是 Windows 10/11 自带的 **Windows PowerShell 5.1**，无需安装 PowerShell 7。
整合包区分 x64（Intel/AMD）与 ARM64，内含相同版本的对应架构 CUA。
如果下载脚本受到执行策略限制，参见 [5.1 使用说明](docs/powershell-5.1.md)。

需要 Windows 交互式桌面、Windows PowerShell 5.1、Windows OpenSSH，以及官方 Cua Driver。
Linux 端需要 SSH 转发权限和 `ss`、`grep`、`curl`。

将对应架构的官方 Windows x64 / ARM64 binary ZIP 完整解压到脚本旁的 `cua/`，或者使用 PATH
中已安装的 cua-driver。脚本优先选择 `cua/cua-driver.exe`。

```powershell
powershell.exe -NoProfile -File ./CuaLink.ps1
```

选择 Start / Stop / Status；也可以直接运行 `./CuaLink.ps1 start`。
首次连接主机前，请先用普通 SSH 登录并核实主机指纹。

默认 `$UseScriptConfig = $false`，全部交互输入，Bearer token 自动随机生成。
密码输入时直接回车使用 SSH key。端口默认 SSH 22、Windows 19222、Linux 映射 19222。

使用固定配置时，编辑顶部的 `$UseScriptConfig = $true`，完整填写 token、地址、
用户名、认证模式和三个端口。`$SshAuthMode = 'key'` 不询问密码；`'password'`
每次新启动都要求隐藏输入密码，不能预置密码。不要提交填有 token 的本地脚本。

生成固定 Bearer token（不是 SSH 登录密钥）：

```powershell
$b = New-Object byte[] 32; $r = [Security.Cryptography.RandomNumberGenerator]::Create()
$r.GetBytes($b); $r.Dispose(); [BitConverter]::ToString($b).Replace('-', '')
```

启动和运行中的 Status 都显示：

```text
CUA link: running
SSH target: user@host connected
MCP Transport: Streamable HTTP
MCP address: http://127.0.0.1:19222/mcp
Authorization: Bearer ...
```

这里的 `127.0.0.1` 指 **SSH 目标 Linux 主机**。按回车退出启动窗口后，后台
继续运行；再次运行脚本并选择 Stop 才停止。任一子进程退出会清理另一进程，
目前不自动重连。状态信息不是连续的端到端健康监测。

## 客户端配置

Codex CLI 使用 HTTP 地址和 `bearer_token_env_var`，从设置好变量的终端启动。
Hermes 除 Authorization 外，还应设置：

```yaml
MCP-Protocol-Version: "2025-06-18"
```

已测 CUA 0.28.1 的 HTTP 端点会拒绝新版 Hermes SDK 默认的 `2025-11-25`
协议头。完整配置示例见 [英文 README](README.md#mcp-clients)。更换随机 token
后需要更新客户端配置并重连。

## 自动打包与测试

源码仓库不提交 CUA 二进制、凭据或运行日志。每周或手动触发候选构建，自动寻找
最新的稳定 CUA Driver 标签，验证 SHA256、检查包结构、收集许可证并执行 HTTP
测试。未知许可证或包结构变化会阻止打包。

候选包不是经过真实桌面验证的稳定版。正式发布必须引用成功候选构建和兼容性
测试报告，并确认许可审核；发布使用原始候选包，不重新构建。实机测试需要保持
登录的专用 Windows 桌面，普通 GitHub runner 不能代替真实桌面验证。

目前历史验证包括 CUA 0.28.1、SSH key、窗口枚举与截图，以及用户确认的
Codex/Hermes 控制效果。SSH 密码实机登录仍需补测。详见
[发布检查表](docs/release-checklist.md)。

脚本 MIT；CUA 及其依赖遵守各自许可证，Node runtime 为 MPL-2.0。
运行时生成的辅助程序和加密配置均在 `.runtime/`，用户只需维护一个入口脚本。

