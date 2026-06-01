# AgentLidGuard

AgentLidGuard keeps selected Windows agent processes reachable after laptop lid
close. It is built for tools such as Codex, Claude Code, ChatGPT Desktop, and
VS Code agent workflows.

The important design point is that this tool does not try to keep networking
alive inside Modern Standby. On machines where S0 standby is network
disconnected, that is not reliable for desktop apps. Instead, while a configured
agent process is running, AgentLidGuard prevents Windows from entering standby
in the first place.

## What It Changes While Protected

When a matching process is running and the current power source is enabled in
`config.json`, AgentLidGuard can:

- Set lid close action to `Do nothing`.
- Set idle sleep timeout to `0` (`Never`).
- Set idle hibernate timeout to `0` (`Never`).
- Hold a Windows `PowerRequestSystemRequired` request.
- Hold a Windows `PowerRequestExecutionRequired` request.

The lid close setting is the mechanism that stops a closed laptop from entering
standby. Power requests only supplement idle-sleep protection; they do not
override a lid-close sleep action on their own.

When no matching process is running, or the service is stopped, it releases the
power requests and restores the power settings it changed.

## Files

- `AgentLidGuard.ps1` - command entrypoint.
- `config.json` - process and AC/DC protection policy.
- `src/` - implementation modules.
- `state/state.json` - runtime state, created while protection is active.
- `logs/AgentLidGuard.log` - runtime log, created on demand.

## Configuration

Edit `config.json`:

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

`processNames` are PowerShell process names without `.exe`. Matching is
case-insensitive, duplicates are ignored, and wildcards accepted by
`Get-Process -Name` also work.

Long-lived GUI shells such as VS Code or ChatGPT Desktop are intentionally not
part of the default list because they are often open all day. Add them only if
their presence should keep the machine awake.

The default is conservative: AC is fully protected, DC is disabled to avoid
battery drain.

## Commands

Run in PowerShell:

```powershell
cd C:\Users\torch\Desktop\VibeSpace\AgentLidGuard

.\AgentLidGuard.ps1 status
.\AgentLidGuard.ps1 doctor
.\AgentLidGuard.ps1 start
.\AgentLidGuard.ps1 stop
```

If local execution policy blocks direct script execution, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\AgentLidGuard.ps1 status
```

Commands:

- `status` prints current task, source, policy, matching processes, and runtime
  state.
- `doctor` prints status plus sleep-state, `powercfg /requests`, power event,
  and WLAN event diagnostics.
- `start` registers and starts a hidden SYSTEM scheduled task named
  `AgentLidGuard`.
- `stop` stops and unregisters the scheduled task, releases power requests, and
  restores touched settings.
- `run` runs the monitor loop in the foreground for debugging.
- `once` applies one protection tick, then prints status.

`start`, `stop`, `run`, and `once` request administrator elevation when needed.
For foreground debugging with `run` or `once`, open an elevated PowerShell first
so output stays in the same terminal.

## Tests

Run the no-dependency test script:

```powershell
.\tests\run-tests.ps1
```

## Why Scheduled Task Instead Of services.msc

The service runner is a Windows Scheduled Task running as `SYSTEM` at startup.
This gives service-like behavior without a service wrapper or a compiled Windows
Service. It also survives reboot: after an unexpected restart, the task starts
again and reconciles state.

## Restore Safety

AgentLidGuard snapshots the original values for every active power scheme it
touches. It restores only settings it actually changed. If a setting is changed
manually while the guard is active, restore skips values that no longer look
service-owned.

The scheduled task is configured to restart the monitor after process failure.
Each monitor tick writes a heartbeat to `state/state.json`; `status` reports the
last heartbeat and warns if a protected state remains while the task is not
running. Running `start` again first reconciles and removes any residual state
before registering the task.

If `powercfg` hangs, AgentLidGuard times it out rather than letting the monitor
tick block forever. After five consecutive tick failures, the monitor exits with
a non-zero status so the scheduled task can restart it.

Stopping the service is intended to leave Windows as if the guard had not been
running, except for retained logs.
