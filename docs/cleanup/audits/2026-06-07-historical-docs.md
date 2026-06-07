# Historical Docs Audit

## Commands

```powershell
rg -n "future|planned|plan|proposal|should|would|could|migration|migrate|transitional|temporary|old|legacy|deprecated|retired|compat|shim|TODO|FIXME" docs API.md README.md CONTRIBUTING.md
rg -n "migration|migrate|transitional|temporary bridge|legacy|deprecated|retired|compat|shim|future composite|Future direction|future public|implemented" API.md docs\module-authors docs\lib-contributors docs\README.md --glob "!docs/cleanup/**" --glob "!docs/references/**" --glob "!docs/rejected-directions/**"
```

## Classification

- `keep`: `docs/lib-contributors/future-ideas/*` contains active future design
  notes, currently hash-string compression and optional status intents.
- `keep`: `docs/rejected-directions/*` and `docs/references/KNOWN_LIMITATIONS.md`
  intentionally preserve architectural decisions and accepted constraints.
- `keep`: cleanup audit files are historical work logs by design and are not
  module-author or contributor API documentation.
- `keep`: contributor rules about retired namespaces and temporary bridges are
  current cleanup policy, not migration instructions.
- `rename`: `API.md` referred to "future composite storage"; controls already
  implement Lib-managed composite backing keys, so the API now states that as
  current behavior.

## Result

No current public or contributor doc describes an obsolete migration plan. The
remaining historical material is either an explicit rejected direction, a known
limitation, a future-ideas record, or a cleanup audit log.
