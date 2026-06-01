# Contributing to LidLess

Thanks for your interest in improving LidLess! This is a small,
dependency-free PowerShell project, so contributing is straightforward.

## Prerequisites

- Windows 10 or 11 (the tool targets Windows power management).
- Windows PowerShell 5.1 or PowerShell 7+.
- A laptop is helpful for end-to-end testing (lid/AC/DC behavior), but the unit
  tests run anywhere PowerShell does.

## Project layout

- `LidLess.ps1` — command entrypoint and monitor state machine.
- `src/*.psm1` — implementation modules, one concern each.
- `tests/run-tests.ps1` — no-dependency test runner.
- `README.md` / `README.zh-CN.md` — user-facing documentation.

## Running the tests

```powershell
.\tests\run-tests.ps1
```

All tests must pass. Add a test for any new parsing, state, or formatting logic.
The runner is intentionally plain (no Pester dependency); follow the existing
`Invoke-LLTest` / `Assert-LL*` pattern.

## Linting

CI runs [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer) using
`PSScriptAnalyzerSettings.psd1`. To check locally:

```powershell
Install-Module PSScriptAnalyzer -Scope CurrentUser   # one time
Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
```

CI fails on `Error`-severity findings. Warnings are advisory.

## Coding conventions

- Functions are named `Verb-LLNoun` and exported explicitly via
  `Export-ModuleMember`.
- `Set-StrictMode -Version 2.0` is on everywhere; avoid relying on undefined
  variables or properties.
- Avoid shadowing PowerShell automatic variables (`$matches`, `$args`, `$input`).
- Keep modules single-purpose; shared helpers live in `RuntimeSupport.psm1`.
- Power-policy changes must be reversible: snapshot the original value before
  taking ownership, and restore only values the guard still owns.

## Pull requests

1. Branch from the default branch.
2. Keep changes focused; update the README files and `CHANGELOG.md` when
   behavior changes.
3. Ensure tests pass and the analyzer is clean of new errors.
4. Describe what you changed and how you verified it (see the PR template).

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
