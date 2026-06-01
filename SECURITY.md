# Security Policy

## What AgentLidGuard does to your system

AgentLidGuard is a power-management tool, so by design it needs elevated access
and changes system-wide settings. Before running it, understand exactly what it
touches:

- **Runs as `SYSTEM`.** The `start` command registers a Windows Scheduled Task
  that runs the monitor loop as the `SYSTEM` account at startup with the highest
  run level. This is required to read/write power policy and hold power requests
  reliably regardless of which user is logged on.
- **Requires administrator elevation.** `start`, `stop`, `run`, and `once`
  self-elevate via UAC when not already elevated.
- **Changes power policy.** While a configured process is running and the
  current power source is enabled, it sets (for the active power scheme):
  - Lid close action -> `Do nothing`
  - Sleep after -> `Never`
  - Hibernate after -> `Never`
- **Holds Windows power requests.** It calls `PowerCreateRequest` /
  `PowerSetRequest` and `SetThreadExecutionState` (via P/Invoke into
  `kernel32.dll`) to supplement idle-sleep prevention.
- **Reads event logs.** `doctor` reads recent Kernel-Power and WLAN-AutoConfig
  events for diagnostics. It never transmits them anywhere; output stays local.

It does **not** make network connections, install drivers, or modify anything
outside the power subsystem and its own `state/` and `logs/` folders.

## Restoring your machine

`stop` releases all power requests and restores every setting it changed, using
the original values snapshotted in `state/state.json`. It only restores settings
that still hold the value AgentLidGuard set, so manual changes you made meanwhile
are not clobbered. After `stop`, the machine is left as if the guard had never
run (logs aside).

If the monitor process is killed abnormally, the power requests are released by
the OS automatically, but the `powercfg` policy values persist until the next
`start` (which reconciles residual state) or `stop`. `status` warns when a
protected state is present while the task is not running.

## Supported versions

This project follows the latest release on the default branch. Fixes are applied
to `main`; there are no separate maintenance branches.

## Reporting a vulnerability

Please **do not** open a public issue for security problems. Instead, report
privately through GitHub Security Advisories ("Report a vulnerability" on the
repository's *Security* tab), or email the maintainer listed in the repository
profile.

Include: affected version/commit, environment (Windows build, PowerShell
version), reproduction steps, and impact. You can expect an initial response
within a few days. Please give a reasonable window for a fix before any public
disclosure.
