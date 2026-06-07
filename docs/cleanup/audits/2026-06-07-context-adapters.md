# Context and Adapter Audit

## Commands

```powershell
rg -n "\bctx\b|\bcontext\b|Context|\badapter\b|\badapters\b|Adapter|Adapters|create.*Surface|Surface|bundle|Bundle|opts\.\w+Bundle|deps\.|local deps = \.\.\." src tests docs API.md
rg --files src | rg "(adapters|adapter|context|bundle)"
rg -n "mutationBundle|hookDeclarations|overlayDeclarations|sharedDataDeclarations|status\.adapters|cache\.adapters|shared\.adapters|adapters" src\core tests docs API.md
```

## Classification

- `keep`: `module_bootstrap/ui/context.lua` is the UI callback object composer.
  It builds the narrow `(host, ui)` callback surface and is not a broad context
  bus.
- `keep`: `module_state/storage_ref_adapter.lua` is the author-facing storage
  ref wrapper. It owns method-call validation, private-alias rejection, and
  read/write variant projection.
- `keep`: status, shared, and cache data adapters are lane-specific projections
  from callback APIs into their subsystem backends.
- `keep`: hook, overlay, shared, and mutation module adapters translate
  `ManagedModule` records into subsystem owner receipts. System adapters do the
  same for managed system scopes.
- `keep`: `module_state/persistent/storage_config_adapter.lua` isolates config
  backend reads/writes from persistent state.
- `keep`: internal `service` and `bundle` names remain subsystem composition
  vocabulary, per the service audit.

## Edits

- Collapsed a one-line mutation adapter helper that only forwarded to
  `requireModuleRecord`.
- Renamed a stale hook test from host installation wording to module
  installation wording.
- Updated contributor wording so module adapters derive identity from the
  `ManagedModule`, not from callback host terminology.

## Result

No broad context object survived the native API migration. The remaining
adapters are intentional boundary layers: callback object composition,
author-facing ref projection, config backend isolation, and module/system
receipt translation.
