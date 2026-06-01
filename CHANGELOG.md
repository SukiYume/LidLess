# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-06-01

First public release.

### Added

- Dynamic lid/sleep/hibernate protection that activates only while a configured
  agent process (e.g. `claude`, `codex`, `Codex Desktop`) is running and the
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

[Unreleased]: https://github.com/SukiYume/AgentLidGuard/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/SukiYume/AgentLidGuard/releases/tag/v1.0.0
