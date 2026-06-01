# LidLess

[English](README.md) | [简体中文](README.zh-CN.md)

> 合上笔记本盖子后，让你的 AI agent 任务继续跑完——又不会让机器在其余时间一直醒着。

![CI](https://github.com/SukiYume/LidLess/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)

LidLess 让你选定的 Windows agent 进程在合盖后依然保持运行、可联网。它为 Codex、
Claude Code、ChatGPT Desktop、VS Code 的 agent 工作流等工具而设计。当配置的 agent
正在运行时，你可以合上盖子让长任务跑完；一旦 agent 退出，系统立刻恢复正常的睡眠
行为。

在 Modern Standby（S0）笔记本上，待机期间网络通常会断开，所以「在待机中维持连接」
并不可靠。LidLess 反其道而行：只要配置的 agent 在运行，就干脆不让 Windows 进入待机，
从而让机器保持唤醒与在线。

## 工作原理

LidLess 以 `SYSTEM` 计划任务的形式运行一个轻量监控循环，每隔几秒检查两件事：

1. 是否至少有一个配置的进程正在运行？
2. 当前电源（`AC` 交流 / `DC` 电池）在 `config.json` 中是否启用？

只有**两者同时成立**时才启用保护；任意一个变为否，就释放所有占用并还原你原本的
设置。因此，只有在你确实有 agent 任务在跑时，保护才会生效。

## 环境要求

- Windows 10 或 11（笔记本，针对合盖场景）。
- Windows PowerShell 5.1 或 PowerShell 7+。
- 管理员权限（`start`/`stop`/`run`/`once` 会在需要时通过 UAC 自动提权）。

## 安装

1. 把本仓库下载或克隆到任意文件夹。
2. 如果是从网上下载的，先解封文件，PowerShell 才会运行它们（Windows 会把下载的
   脚本标记为「已阻止」）：

   ```powershell
   Get-ChildItem -Path . -Recurse | Unblock-File
   ```

3. 在项目文件夹里启动：

   ```powershell
   .\LidLess.ps1 start
   ```

这会注册并启动后台任务。之后只要配置的 agent 在运行，你就可以合盖。想停止并完整
还原电源设置时，运行 `.\LidLess.ps1 stop`。

## 命令

在项目文件夹的 PowerShell 中运行：

```powershell
cd path\to\LidLess

.\LidLess.ps1 status
.\LidLess.ps1 doctor
.\LidLess.ps1 start
.\LidLess.ps1 stop
```

如果本地执行策略阻止直接运行脚本，改用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\LidLess.ps1 status
```

| 命令 | 作用 |
|------|------|
| `status` | 打印当前任务、电源、各项策略值、匹配到的进程和运行时状态。只读。 |
| `doctor` | 在 `status` 基础上额外打印可用睡眠状态、`powercfg /requests`，以及近期电源/WLAN 事件，用于诊断。 |
| `start`  | 注册并启动一个名为 `LidLess` 的隐藏 `SYSTEM` 计划任务。 |
| `stop`   | 停止并注销任务，释放电源请求，还原它改过的所有设置。 |
| `run`    | 在前台运行监控循环（用于调试）。 |
| `once`   | 执行一次保护检查，然后打印状态。 |

`start`、`stop`、`run`、`once` 会在需要时请求管理员提权。若要用 `run` 或 `once`
做前台调试，先打开一个已提权的 PowerShell，输出才会留在同一个终端里。

### `status` 输出示例

```text
LidLess status
  Task:                 LidLess (Running)
  Power source:         AC
  Source enabled:       True
  Active scheme:        381b4222-f694-41f0-9685-ff5bb260df2e
  AC lid:               0 (Do nothing)
  DC lid:               1 (Sleep)
  AC sleep after:       0 (Never)
  DC sleep after:       900 sec (15 min)
  AC hibernate after:   0 (Never)
  DC hibernate after:   0 (Never)
  Poll seconds:         5
  Process names:        claude, codex, Codex Desktop
  Matches:              codex[12840]
  Runtime protected:    True
  Runtime reason:       matched process and source enabled
  Runtime heartbeat:    2026-06-01T20:31:07.4521820+08:00 (pid=9123)
  Runtime power request: handle=True, system=True, execution=True
```

## 配置

设置保存在 `config.json` 中（首次运行时会用默认值自动创建）。编辑后，重新运行
`.\LidLess.ps1 start` 即可生效。

```json
{
  "processNames": ["claude", "codex", "Codex Desktop"],
  "pollSeconds": 5,
  "ac": {
    "enabled": true,
    "lidCloseDoNothing": true,
    "preventIdleSleep": true,
    "preventHibernate": true,
    "holdSystemRequiredRequest": true,
    "holdExecutionRequiredRequest": true
  },
  "dc": {
    "enabled": false,
    "lidCloseDoNothing": true,
    "preventIdleSleep": true,
    "preventHibernate": false,
    "holdSystemRequiredRequest": true,
    "holdExecutionRequiredRequest": true
  },
  "diagnostics": {
    "includeRecentPowerEvents": true,
    "eventLookbackHours": 12
  }
}
```

### 字段说明

| 字段 | 含义 |
|------|------|
| `processNames` | 要监控的进程名，不带 `.exe`。匹配不区分大小写，自动去重，并支持 `Get-Process -Name` 接受的通配符。 |
| `pollSeconds` | 监控循环的检查间隔，最小值 `2`。 |
| `ac` / `dc` | 分别对应「接通电源（AC）」和「使用电池（DC）」两种状态的策略。 |
| `*.enabled` | 在该电源状态下是否启用保护。 |
| `*.lidCloseDoNothing` | 把合盖动作设为「不采取任何操作」（这正是阻止合盖睡眠的关键）。 |
| `*.preventIdleSleep` | 把「在此时间后睡眠」设为「从不」。 |
| `*.preventHibernate` | 把「在此时间后休眠」设为「从不」。 |
| `*.holdSystemRequiredRequest` | 持有 Windows `PowerRequestSystemRequired` 请求（对空闲睡眠起补充作用）。 |
| `*.holdExecutionRequiredRequest` | 持有 Windows `PowerRequestExecutionRequired` 请求。 |
| `diagnostics.includeRecentPowerEvents` | `doctor` 是否包含近期 Kernel-Power 事件。 |
| `diagnostics.eventLookbackHours` | `doctor` 回溯电源/WLAN 事件的时间窗口（小时）。 |

合盖动作才是真正阻止合盖睡眠的机制；电源请求只是对空闲睡眠的补充，单靠它们无法
覆盖合盖触发的睡眠动作。

VS Code、ChatGPT Desktop 这类常驻 GUI 默认**不**在列表里，因为它们经常整天开着，
会让机器在任务早已结束后仍长时间保持唤醒。只有当你希望「它在运行」本身就算数时，
才把它们加进去。

默认配置偏保守：AC 完全保护，DC 关闭以避免耗电。

## 卸载

```powershell
.\LidLess.ps1 stop
```

`stop` 会移除计划任务、释放电源请求，并还原 LidLess 改过的所有设置。之后直接删除
文件夹即可。唯一会留下的是本地的 `state/` 和 `logs/` 文件夹，也可一并删除。

## 常见问题

- **提示「在此系统上禁止运行脚本」。** 解封文件
  （`Get-ChildItem -Recurse | Unblock-File`），或使用上文的
  `-ExecutionPolicy Bypass` 方式运行。
- **合盖后还是睡了。** 运行 `.\LidLess.ps1 doctor`，确认匹配的进程出现在
  `Matches` 下、当前电源在 `config.json` 中 `enabled`、并且 `AC lid`（或 `DC lid`）
  显示为 `0 (Do nothing)`。注意：部分 OEM 固件可能无视 Windows 策略强制睡眠，
  `doctor` 里的电源事件有助于判断是什么触发的。
- **任务没在运行。** `status` 会显示任务状态。在已提权的终端重新运行
  `.\LidLess.ps1 start`，并查看 `logs\LidLess.log`。
- **崩溃后保护好像卡住了。** 如果监控进程被强杀，`powercfg` 的改动会一直保留直到
  被重新协调。当存在保护状态但任务未运行时，`status` 会给出警告；运行 `start`
  （重新协调并重启）或 `stop`（还原）即可修复。
- **我的进程没被识别。** 使用 `Get-Process` 显示的、不带 `.exe` 的进程名，并在
  `status` 的 `Matches` 中确认。

## 后台运行方式

监控循环是一个在开机时以 `SYSTEM` 身份运行的 Windows 计划任务。这样无需服务包装器
或编译型 Windows 服务即可获得类服务的行为，并且能在重启后存活：系统重启后任务会
再次启动并重新协调状态。任务还配置为在进程失败后重启监控；监控在连续多次检查失败
后会主动退出，让任务干净地把它重启。

每次检查都会向 `state/state.json` 写入一个心跳，`status` 会展示它。

## 还原安全

LidLess 在修改每一项设置前都会先快照其原始值，并把该设置标记为「归自己所有」。
还原时，只会回滚仍归自己所有、且当前值仍是它设定值的设置——因此你在保护生效期间
手动做的更改不会被覆盖。状态文件采用原子写入，读取时会修复为当前结构，所以更旧或
不完整的状态文件也能正常加载。

停止服务的目标是让 Windows 恢复到仿佛 LidLess 从未运行过的状态（保留的日志除外）。

## 测试

运行无依赖的测试脚本：

```powershell
.\tests\run-tests.ps1
```

## 文档

- [docs/design.md](docs/design.md) —— 架构与设计理由（英文）。
- [CHANGELOG.md](CHANGELOG.md) —— 版本历史。
- [SECURITY.md](SECURITY.md) —— 它会改动什么，以及如何上报问题。
- [CONTRIBUTING.md](CONTRIBUTING.md) —— 开发环境、测试与约定。

## 参与贡献

欢迎贡献。提交 PR 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md) 并运行
`.\tests\run-tests.ps1`。

## 许可证

基于 [MIT License](LICENSE) 发布。
