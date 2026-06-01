## What does this change?

A short description of the change and the motivation.

## Related issues

Closes #...

## How was it verified?

- [ ] `.\tests\run-tests.ps1` passes
- [ ] `Invoke-ScriptAnalyzer` reports no new errors
- [ ] Manually exercised on a real machine (describe: AC/DC, lid close, etc.)

## Checklist

- [ ] Updated README files if behavior changed
- [ ] Updated `CHANGELOG.md` under `[Unreleased]`
- [ ] Power-policy changes remain reversible (snapshot + owned-only restore)
