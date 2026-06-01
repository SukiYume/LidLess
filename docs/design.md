# LidLess Design

## Goal

Keep configured agent processes running and reachable after laptop lid close on
Windows laptops, especially Modern Standby systems where standby networking is
disconnected.

## Strategy

Protection is active only when both conditions are true:

1. At least one configured process name is running.
2. The current power source (`AC` or `DC`) is enabled in `config.json`.

While protected, the tool changes lid/sleep/hibernate policy for configured
sources and holds Windows power requests in the long-running monitor process.
When protection is inactive, it releases the requests and restores policy values
that it changed.

The lid close action (`Do nothing`) is the mechanism that actually stops a
closed laptop from entering standby. The power requests and
`SetThreadExecutionState` only supplement idle-sleep prevention; they do not
override a lid-close sleep action on their own.

The monitor records a heartbeat in `state/state.json` on every tick. The
scheduled task is configured to restart failed monitor processes, so the next
tick either keeps protection active for still-running matches or restores policy
when no matches remain. A manual `start` also reconciles residual state before
re-registering the task.

Consecutive tick failures are counted, and after five failures the monitor
restores protection and exits with status `1` to let the scheduled task restart
it instead of looping forever in a broken state.

## Components

- `LidLess.ps1`: command entrypoint and monitor state machine.
- `src/RuntimeSupport.psm1`: admin elevation, logging, and shared formatting.
- `src/Config.psm1`: config parsing, defaults, and backward compatibility with
  the first config format.
- `src/ProcessMatcher.psm1`: resolves configured names to running processes.
- `src/NativePower.psm1`: `GetSystemPowerStatus`,
  `PowerCreateRequest`/`PowerSetRequest`, and `SetThreadExecutionState`.
- `src/PowerPolicy.psm1`: `powercfg` and registry-based policy read/write.
- `src/StateStore.psm1`: runtime state and original policy snapshots.
- `src/ScheduledTask.psm1`: SYSTEM scheduled-task runner.
- `src/Diagnostics.psm1`: status and event-log inspection.

## Protected Values

- `LidAction`: `0` (`Do nothing`)
- `StandbyIdle`: `0` (`Never`)
- `HibernateIdle`: `0` (`Never`)
- `PowerRequestSystemRequired`: active when configured for current source
- `PowerRequestExecutionRequired`: active when configured for current source

`DisplayRequired` is intentionally not used because the desired state is a
running closed-lid machine, not an always-lit display.

## Restore Safety

Before changing a value, the guard snapshots the original and marks the setting
as owned. Restore only reverts settings still owned and still holding the value
the guard set, so a manual change made while the guard is active is not
clobbered. State is written atomically (temp file + move) and repaired into the
current shape on read, so older or partial state files load without error.
