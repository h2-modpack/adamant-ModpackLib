# Migration Residue Vocabulary Audit

## Scope

Audit command:

```powershell
rg -n "\bcompat\b|\bcompatibility\b|\blegacy\b|\bdeprecated\b|\bdeprecation\b|\bshim\b|\bshims\b|\bmigration\b|\bmigrations\b|\bold\b|Compatibility|Legacy|Deprecated|Deprecation|Shim|Shims|Migration|Migrations" src tests docs API.md
```

## Result

Current Lib source, tests, API docs, and contributor docs no longer carry
backward-looking migration terminology outside the cleanup tracker and
historical audit files.

## Changes Made

- Removed the special `definition = {...}` createModule migration diagnostic;
  it now follows the normal unknown-option path.
- Replaced prepare-definition storage-default migration diagnostics with current
  structural-surface validation diagnostics.
- Removed redundant mutation lifecycle coverage for a retired `affectsRunData`
  flag shape.
- Reworded docs from old/legacy/compatibility/migration language to
  previous/current/temporary-bridge language.
- Renamed test fixture values from `old` to `before` where they only represented
  before/after state.
