# Cleanup Tracking

This folder is a working area for post-migration cleanup. It is not module-author
documentation and should not be treated as an API contract.

## Process

1. Save audit commands and raw outputs under `audits/`.
2. Classify findings before editing.
3. Work in narrow passes with one cleanup theme per patch.
4. Check production callers before deleting or collapsing helpers.
5. Keep tests as behavior coverage, not as the only reason an obsolete surface exists.
6. Update or delete stale docs in the same pass that changes the public shape.

## Finding Labels

- `keep`: current name or shape is intentional.
- `rename`: concept is still valid, but the vocabulary is stale.
- `delete`: concept is obsolete and has no production caller.
- `collapse`: helper/file exists only as a redirection layer.
- `move`: useful code lives in the wrong subsystem.
- `document`: behavior is intentional but needs a doc anchor.
- `test-only`: code only exists for tests and should be replaced with behavioral coverage or removed.

## Initial Cleanup Checklist

- [x] `runtimeOwned` naming residue now that public API is `status`.
- [x] `host` versus `module` vocabulary residue in diagnostics, docs, and internal APIs.
  Audit: [2026-06-06-host-module.md](audits/2026-06-06-host-module.md).
- [x] old `service` terminology that is either real Lib internals or leftover author-facing wording.
  Audit: [2026-06-07-service.md](audits/2026-06-07-service.md).
- [x] stale `integration`, `poll`, and `provider` references.
  Audit: [2026-06-07-integration-poll-provider.md](audits/2026-06-07-integration-poll-provider.md).
- [x] `compat`, `legacy`, `deprecated`, `shim`, and `migration` references.
  Audit: [2026-06-07-migration-residue.md](audits/2026-06-07-migration-residue.md).
- [x] broad context objects or adapter layers that survived the native API migration.
  Audit: [2026-06-07-context-adapters.md](audits/2026-06-07-context-adapters.md).
- [x] one-line helpers that only hide direct calls without adding policy.
  Audit: [2026-06-07-one-line-helpers.md](audits/2026-06-07-one-line-helpers.md).
- [x] docs that describe historical migration plans instead of current behavior.
  Audit: [2026-06-07-historical-docs.md](audits/2026-06-07-historical-docs.md).
- [x] implementation-side LuaCAT annotations that duplicated the canonical public definition file.
  Audit: [2026-06-07-luacat-surface.md](audits/2026-06-07-luacat-surface.md).

## Subsystem Audit Progress

Work from low-dependency primitives toward higher-level composition. When a
subsystem was audited before this table existed, keep the row marked complete
and add a dedicated audit note only if a future pass finds new issues.

| Order | Subsystem | Status | Notes |
| --- | --- | --- | --- |
| 1 | Bootstrap primitives: logging, registry, module registry, system scope, game deps, values | Done | Policy naming and duplicated diagnostics were cleaned during the bootstrap pass. |
| 2 | Storage core and hash serialization | Done | Removed obsolete hash-packing direction, tightened profile decode behavior, and kept hash compression as a future optional direction. |
| 3 | Module-state backend and storage frontends | Done | Backend adapters, persistent/staged state, and standard `ui.data`/`runtime.data` surfaces were reviewed together. |
| 4 | Status lane | Done | Public API is `module.status`, `runtime.status`, and `ui.status`; old runtime-owned vocabulary is internal only where it names backend implementation. |
| 5 | Actions, reset, and draw commit lifecycle | Done | Commit ordering is centralized and documented; reset is exposed as one UI/module operation rather than lane-specific public reset helpers. |
| 6 | Cache and shared data/events | Done | Shared emit is variant-typed through `runtime.shared` and `ui.shared`; shared publication writes are documented as immediate publication writes. |
| 7 | Controls | Done | Controls compile config storage only; status/actions remain module-level coordination lanes. |
| 8 | Widgets | Done | Hot draw-path helpers, option validation, and docs/API alignment were audited. Audit: [2026-06-07-widgets.md](audits/2026-06-07-widgets.md). |
| 9 | Hooks | Done | Declaration/install boundaries, context wrapping, and ModUtil registry interactions were audited. Audit: [2026-06-07-hooks.md](audits/2026-06-07-hooks.md). |
| 10 | Overlays | Pending | Audit retained overlay lifecycle, suppression, renderer boundaries, and docs. |
| 11 | Mutations | Done | Plan generation, lifecycle sync, and framework/module integration points were audited. Audit: [2026-06-07-mutations.md](audits/2026-06-07-mutations.md). |
| 12 | Fallback UI and framework runtime | Done | Framework/runtime docs were aligned with `ui.status`; fallback UI now balances ImGui `Begin`/`End` on module draw errors. Audit: [2026-06-07-fallback-framework-runtime.md](audits/2026-06-07-fallback-framework-runtime.md). |
| 13 | Module bootstrap and activation | Pending | Audit last because it composes every lower subsystem. |

## Production Caller Rule

Before removing a helper or file:

1. Search production code first: `src`, then module consumers if relevant.
2. Search tests second.
3. If only tests call it, decide whether the test should move to a public behavior.
4. If production calls it, classify whether it is a real boundary or an accidental redirection.

## Suggested Audit Commands

Run from `adamant-ModpackLib`.

```powershell
rg -n "runtimeOwned|store\.runtimeOwned|stagedState\.runtimeOwned|RuntimeOwned" src tests docs API.md
rg -n "\bservices?\b|\bintegration\b|\bintegrations\b|\bpoll\b|\bprovider\b|\bproviders\b" src tests docs API.md
rg -n "\bcompat\b|\blegacy\b|\bdeprecated\b|\bshim\b|\bmigration\b|\bold\b" src tests docs API.md
rg -n "\bhost\b|Host|host\." src
rg -n "\bhost\b|Host|host\." docs API.md
rg -n "\bhost\b|Host|host\." tests
rg -n "moduleHost|hostLifecycle|applyForHost|syncForHost|revertForHost|emitForHost|installForHost|getOwnerId|HostGui" src tests docs API.md
```

Save large outputs as separate audit files instead of trying to clean them from
terminal scrollback.
