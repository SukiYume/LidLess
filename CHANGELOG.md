# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.2] - 2026-06-02

### Fixed

- Fixed `doctor` event summaries so recent power and WLAN diagnostics render
  without failing under strict mode.
- Made `start` stop any existing task before reconciling residual state, avoiding
  a race with an already-running monitor during re-registration.

### Changed

- Runtime logs now record protection state transitions instead of repeating the
  same active/inactive message on every poll.
- Log rotation preserves the previous log as `LidLess.log.1` instead of clearing
  diagnostic history when the log grows.
- Policy restoration now writes an explicit log entry when settings are restored.

## [1.0.1] - 2026-06-02

### Fixed

- `status` now distinguishes "not installed" from "access denied" when a
  non-elevated shell cannot query the elevated scheduled task.
- Suppressed misleading stale-state warnings when the monitor heartbeat is
  present but task state cannot be queried without elevation.

## [1.0.0] - 2026-06-01

First public release.

### Added

- Dynamic lid/sleep/hibernate protection that activates only while a configured
  agent process (e.g. `claude`, `codex`) is running and the
  current power source is enabled.
- Per-source (`AC`/`DC`) configuration in `config.json`, with conservative
  defaults (AC protected, DC disabled).
- Windows power requests (`PowerRequestSystemRequired` /
  `PowerRequestExecutionRequired`) and `SetThreadExecutionState` as a supplement
  to idle-sleep prevention.
- `SYSTEM` scheduled-task runner that starts at boot and restarts on failure.
- Reversible policy changes with original-value snapshots in
  `state/state.json`; restore only touches values the guard still owns.
- Heartbeat in runtime state plus a `status` warning when a protected state is
  present while the task is not running.
- Self-recovery: the monitor exits after repeated tick failures so the scheduled
  task can restart it cleanly.
- `status`, `doctor`, `start`, `stop`, `run`, and `once` commands.
- Locale-robust `powercfg` parsing for non-English Windows.
- No-dependency test runner under `tests/`.

[Unreleased]: https://github.com/SukiYume/LidLess/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/SukiYume/LidLess/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/SukiYume/LidLess/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/SukiYume/LidLess/releases/tag/v1.0.0
