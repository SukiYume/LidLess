# LidLess

[English](README.md) | [简体中文](README.zh-CN.md)

> Keep your AI agent tasks running after you close the laptop lid — without
> leaving the machine awake the rest of the time.

![CI](https://github.com/SukiYume/LidLess/actions/workflows/ci.yml/badge.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)

LidLess keeps selected Windows agent processes reachable after laptop lid close.
It is built for tools such as Codex, Claude Code, ChatGPT Desktop, and VS Code
agent workflows. When a configured agent is running, you can close the lid and
let a long task finish; the moment the agent exits, normal sleep behavior
returns.

On Modern Standby (S0) laptops, networking is often disconnected during standby,
so trying to keep connections alive inside standby is unreliable. LidLess takes
the opposite approach: while a configured agent is running, it stops Windows from
entering standby at all, which keeps the machine awake and online.

## How it works

LidLess runs a small monitor as a `SYSTEM` scheduled task. Every few seconds it
checks two things:

1. Is at least one configured process running?
2. Is the current power source (`AC` or `DC`) enabled in `config.json`?

When **both** are true, it activates protection. When either becomes false, it
releases everything and restores your original settings. So protection is only
ever on while you actually have an agent task running.

## Requirements

- Windows 10 or 11 (laptop, for the lid-close scenario).
- Windows PowerShell 5.1 or PowerShell 7+.
- Administrator rights (`start`/`stop`/`run`/`once` self-elevate via UAC).

## Install

1. Download or clone this repository to any folder.
2. If you downloaded it from the internet, unblock the files so PowerShell will
   run them (Windows marks downloaded scripts as blocked):

   ```powershell
   Get-ChildItem -Path . -Recurse | Unblock-File
   ```

3. From the project folder, start it:

   ```powershell
   .\LidLess.ps1 start
   ```

That registers and starts the background task. You can close the lid while a
configured agent runs. To stop and fully restore your power settings later, run
`.\LidLess.ps1 stop`.

## Commands

Run from the project folder in PowerShell:

```powershell
cd path\to\LidLess

.\LidLess.ps1 status
.\LidLess.ps1 doctor
.\LidLess.ps1 start
.\LidLess.ps1 stop
```

If local execution policy blocks direct script execution, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\LidLess.ps1 status
```

| Command  | What it does |
|----------|--------------|
| `status` | Prints current task, power source, policy values, matching processes, and runtime state. Read-only. |
| `doctor` | Prints `status` plus available sleep states, `powercfg /requests`, and recent power/WLAN events for diagnostics. |
| `start`  | Registers and starts a hidden `SYSTEM` scheduled task named `LidLess`. |
| `stop`   | Stops and unregisters the task, releases power requests, and restores every setting it changed. |
| `run`    | Runs the monitor loop in the foreground (for debugging). |
| `once`   | Applies a single protection tick, then prints status. |

`start`, `stop`, `run`, and `once` request administrator elevation when needed.
For foreground debugging with `run` or `once`, open an elevated PowerShell first
so output stays in the same terminal.

`status` and `doctor` are read-only and can run without elevation. In a
non-elevated shell, Windows may hide the exact state of the `SYSTEM` scheduled
task and may block `powercfg /requests`; the commands still show policy values,
matched processes, runtime heartbeat, and recent events. Re-run them elevated
when you need the protected task state or full `powercfg /requests` output.

### Example `status` output

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
  Process names:        claude, codex
  Matches:              codex[12840]
  Runtime protected:    True
  Runtime reason:       matched process and source enabled
  Runtime heartbeat:    2026-06-01T20:31:07.4521820+08:00 (pid=9123)
  Runtime power request: handle=True, system=True, execution=True
```

## Configuration

Settings live in `config.json` (created with defaults on first run). Edit it,
then rerun `.\LidLess.ps1 start` to apply.

```json
{
  "processNames": ["claude", "codex"],
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

### Field reference

| Field | Meaning |
|-------|---------|
| `processNames` | Process names to watch, without `.exe`. Matching is case-insensitive, duplicates are ignored, and wildcards accepted by `Get-Process -Name` work. |
| `pollSeconds` | How often the monitor re-checks state. Minimum `2`. |
| `ac` / `dc` | Separate policy for when the laptop is on AC power vs. on battery (DC). |
| `*.enabled` | Whether protection runs at all on that power source. |
| `*.lidCloseDoNothing` | Set the lid-close action to `Do nothing` (this is what actually prevents closed-lid sleep). |
| `*.preventIdleSleep` | Set "sleep after" to `Never`. |
| `*.preventHibernate` | Set "hibernate after" to `Never`. |
| `*.holdSystemRequiredRequest` | Hold a Windows `PowerRequestSystemRequired` request (supplements idle-sleep prevention). |
| `*.holdExecutionRequiredRequest` | Hold a Windows `PowerRequestExecutionRequired` request. |
| `diagnostics.includeRecentPowerEvents` | Whether `doctor` includes recent Kernel-Power events. |
| `diagnostics.eventLookbackHours` | How far back `doctor` looks for power/WLAN events. |

To find the right process name, use PowerShell rather than the display name in
Task Manager:

```powershell
Get-Process | Sort-Object ProcessName -Unique | Select-Object ProcessName
```

For example, Claude Code is usually `claude`, Codex is usually `codex`, and
Visual Studio Code is `Code`.

The lid-close action is the mechanism that stops a closed laptop from entering
standby. The power requests only supplement idle-sleep prevention; they do not
override a lid-close sleep action on their own.

Long-lived GUI shells such as VS Code or ChatGPT Desktop are intentionally not
in the default list because they are often open all day, which would keep the
machine awake long after any task finished. Add them only if you want their mere
presence to count.

The default is conservative: AC is fully protected, DC is disabled to avoid
battery drain.

## Uninstall

```powershell
.\LidLess.ps1 stop
```

`stop` removes the scheduled task, releases the power requests, and restores
every setting LidLess changed. After that you can simply delete the folder. The
only things left behind are the local `state/` and `logs/` folders, which you
can delete too.

## Troubleshooting

- **"running scripts is disabled on this system".** Unblock the files
  (`Get-ChildItem -Recurse | Unblock-File`) or use the
  `-ExecutionPolicy Bypass` invocation shown above.
- **The lid still sleeps the machine.** Run `.\LidLess.ps1 doctor`. Confirm the
  matching process appears under `Matches`, that the current power source is
  `enabled` in `config.json`, and that `AC lid` (or `DC lid`) reads
  `0 (Do nothing)`. Note that some OEM firmware can force sleep regardless of
  Windows policy; `doctor`'s power events help confirm what triggered it.
- **The task is not running.** `status` shows the task state. Re-run
  `.\LidLess.ps1 start` from an elevated prompt and check
  `logs\LidLess.log`. If `status` shows `Access denied`, re-run `status` from
  an elevated prompt to see the exact task state; the runtime heartbeat is still
  useful in a non-elevated shell.
- **I moved the folder after starting LidLess.** Run `.\LidLess.ps1 stop` from
  the old location first if it still exists, then run `.\LidLess.ps1 start`
  from the new location. The scheduled task stores the script path used at
  registration time.
- **Protection seems stuck on after a crash.** If the monitor was killed,
  `powercfg` settings persist until reconciled. `status` warns when a protected
  state remains while the task is not running; run `start` to reconcile and
  start the task again, or `stop` to restore settings.
- **My process is not detected.** Use the process name without `.exe` as shown
  by `Get-Process`. Confirm it under `status` -> `Matches`.

## How it runs in the background

The monitor is a Windows Scheduled Task running as `SYSTEM` at startup. This
gives service-like behavior without a service wrapper or a compiled Windows
Service, and it survives reboot: after a restart the task starts again and
reconciles state. The task is also configured to restart the monitor after a
process failure, and the monitor exits on repeated tick failures so the task can
restart it cleanly.

Each tick writes a heartbeat to `state/state.json`, which `status` reports.

## Restore safety

LidLess snapshots the original value of every setting before it changes it, and
marks the setting as owned. On restore it reverts only settings it still owns and
that still hold the value it set — so a change you make manually while the guard
is active is not clobbered. State is written atomically and repaired into the
current shape on read, so older or partial state files load without error.

Stopping the service is intended to leave Windows as if the guard had never run,
except for retained logs.

## Tests

Run the no-dependency test script:

```powershell
.\tests\run-tests.ps1
```

## Documentation

- [CHANGELOG.md](CHANGELOG.md) — release history.
- [SECURITY.md](SECURITY.md) — what it touches and how to report issues.
- [CONTRIBUTING.md](CONTRIBUTING.md) — dev setup, tests, and conventions.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and run
`.\tests\run-tests.ps1` before opening a pull request.

## License

Released under the [MIT License](LICENSE).
