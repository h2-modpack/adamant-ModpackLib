# Hot Reload Registry Migration

This document tracks the migration from scattered `AdamantModpackLib_Runtime`
subsystem tables to one central Lib hot-reload registry root.

## Goal

Lib should have one place where root hot-reload buckets are created. Subsystems
should own the shape of their assigned bucket.

The desired root shape is:

```lua
registry.hosts
registry.hooks
registry.integrations
registry.mutations
registry.overlays
registry.fallback
registry.coordinators
```

Only `core/lib_bootstrap/registry.lua` should create these root buckets on
`AdamantModpackLib_Runtime`. Subsystems may mutate only the bucket passed to
them.

## Rules

- Do not write `runtime.<subsystem>` outside `core/lib_bootstrap/registry.lua`.
- Do not make the root registry a full schema dump. It creates subsystem
  buckets; each subsystem initializes its own leaf tables.
- Do not use subsystem registry buckets as generic dependency buses. Store only
  data that must survive Lib re-import because external callbacks, installed
  hooks, active mutations, retained overlays, fallback GUI dispatchers, live
  hosts, or coordinator registrations still reference it.
- Keep rebuildable services, per-frame objects, local weak side tables, and
  implementation caches local to their subsystem files.
- Pass subsystem buckets to subsystem initializers, not the full registry, unless
  a file is explicitly a bootstrap composition point.

## Target Ownership

`core/lib_bootstrap/registry.lua` owns root bucket creation:

```lua
local runtimeRoot = deps.runtimeRoot
runtimeRoot.registry = runtimeRoot.registry or {}

local registry = runtimeRoot.registry
registry.hosts = registry.hosts or {}
registry.hooks = registry.hooks or {}
registry.integrations = registry.integrations or {}
registry.mutations = registry.mutations or {}
registry.overlays = registry.overlays or {}
registry.fallback = registry.fallback or {}
registry.coordinators = registry.coordinators or {}

return registry
```

Subsystem entry files receive scoped buckets:

```lua
hooks/00_init.lua              hookRegistry = registry.hooks
integrations/00_init.lua       integrationRegistry = registry.integrations
mutations/00_init.lua          mutationRegistry = registry.mutations
overlays/00_init.lua           overlayRegistry = registry.overlays
fallback/fallback_ui.lua       fallbackRegistry = registry.fallback
coordinator/coordinator.lua    coordinatorRegistry = registry.coordinators
```

Host registry remains a dedicated adapter over the host bucket:

```lua
hostRegistry = import("core/lib_bootstrap/host_registry.lua", nil, {
    hostBucket = registry.hosts,
})
```

## Migration Steps

### 1. Create Root Registry

- [x] Rename `core/lib_bootstrap/runtime_registry.lua` to
  `core/lib_bootstrap/registry.lua`.
- [x] Change it from module-host-specific helper storage into root bucket
  creation. Host helper methods remain as transitional methods until step 2.
- [x] Update `core/init.lua` to import `registry.lua`.
- [x] Keep `AdamantModpackLib_Runtime` as the one environment global, but make
  `registry.lua` the only file that shapes Lib-owned root buckets under it.

### 2. Move Host Bucket Shape

- [x] Move live host, plugin info, pending coordinator rebuild, and weak host
  record setup into `core/lib_bootstrap/host_registry.lua`.
- [x] Use `registry.hosts` as the host bucket.
- [x] Keep `hostRegistry.getRecord(host)` and `hostRegistry.setRecord(host,
  record)` as the host-object record adapter.
- [x] Keep live-host/plugin metadata helper methods on the host registry service
  or on a narrowly named host registry adapter.

Expected host bucket leaf tables:

```lua
hosts.live
hosts.pluginInfo
hosts.pendingCoordinatorRebuilds
hosts.records
```

### 3. Migrate Hooks

- [x] Pass `hookRegistry = registry.hooks` into `core/hooks/00_init.lua`.
- [x] Move `runtime.hooks.ownerSlots` and `runtime.hooks.hookDispatchers` to the
  hook bucket.
- [x] Keep per-host `record.hookDeclarations` on the host record.
- [x] Keep ModUtil backend slot records on the persistent ModUtil owner table,
  but source the owner-key string from the hook bucket.

Expected hook bucket leaf tables:

```lua
hookRegistry.ownerSlots
hookRegistry.dispatchers
hookRegistry.modutilOwnerKey
```

### 4. Migrate Integrations

- [x] Pass `integrationRegistry = registry.integrations` into
  `core/integrations/00_init.lua`.
- [x] Remove `runtime.integrations.registry`.
- [x] Let `core/integrations/registry.lua` initialize provider storage inside
  the integration bucket.
- [x] Keep per-host staged `record.integrationRegistrations` on the host record.

Expected integration bucket leaf table:

```lua
integrationRegistry.providers
```

### 5. Migrate Mutations

- [x] Pass `mutationRegistry = registry.mutations` into
  `core/mutations/00_init.lua`.
- [x] Rename `mutationState` to `mutationRegistry`.
- [x] Rename per-owner `runtimeState` locals to `slot`.
- [x] Move `runtime.mutation.ownerRuntime` to `mutationRegistry.ownerSlots`.
- [x] Keep `planExecutors` weak-keyed and owned by the mutation bucket.

Expected mutation bucket leaf tables:

```lua
mutationRegistry.ownerSlots
mutationRegistry.planExecutors
```

### 6. Migrate Overlays

- [x] Pass `overlayRegistry = registry.overlays` into
  `core/overlays/00_init.lua`.
- [x] Rename `core/overlays/state.lua` to `core/overlays/registry.lua` or fold
  the leaf initialization into `00_init.lua`.
- [x] Rename `overlayState` locals to `overlayRegistry`.
- [x] Keep renderer, retained, and suppression leaf tables owned by the overlay
  subsystem, not by root registry.

Expected overlay bucket leaf tables:

```lua
overlayRegistry.renderer
overlayRegistry.retained
overlayRegistry.uiSuppressors
overlayRegistry.nextUiSuppressorId
```

### 7. Migrate Fallback UI

- [x] Pass `fallbackRegistry = registry.fallback` into fallback UI assembly.
- [x] Rename `fallbackUiState` locals to `fallbackRegistry`.
- [x] Move `runtime.fallbackUi.*` leaf setup into fallback code using the bucket.

Expected fallback bucket leaf tables:

```lua
fallbackRegistry.bridges
fallbackRegistry.guiAttached
fallbackRegistry.runtimes
fallbackRegistry.fallbackHud
```

### 8. Migrate Coordinator

- [x] Pass `coordinatorRegistry = registry.coordinators` into coordinator code.
- [x] Move `runtime.coordinator.coordinators` and `runtime.coordinator.rebuilds`
  to the coordinator bucket.
- [x] Keep Framework-facing coordinator APIs on the framework runtime service;
  the registry is only retained storage.

Expected coordinator bucket leaf tables:

```lua
coordinatorRegistry.configs
coordinatorRegistry.rebuilds
```

### 9. Update Tests And Docs

- [x] Update tests that inspect `harness.runtime.<subsystem>` to inspect the new
  registry buckets.
- [x] Update architecture docs that mention `runtime.moduleHost`,
  `runtime.hooks`, `runtime.overlays`, `runtime.fallbackUi`,
  `runtime.integrations`, `runtime.mutation`, or `runtime.coordinator`.
- [x] Keep public Framework/runtime service docs distinct from Lib's internal
  hot-reload registry docs.

### 10. Final Audit

Run these scans after the migration:

```powershell
rg -n "runtime\.[A-Za-z_]" adamant-ModpackLib/src
rg -n "AdamantModpackLib_Runtime|runtime\.[A-Za-z_]" adamant-ModpackLib/docs adamant-ModpackLib/API.md
rg -n "State|state" adamant-ModpackLib/src/core/hooks adamant-ModpackLib/src/core/integrations adamant-ModpackLib/src/core/mutations adamant-ModpackLib/src/core/overlays adamant-ModpackLib/src/core/fallback
```

Expected result:

- `runtime.<subsystem>` writes appear only in `core/lib_bootstrap/registry.lua`.
- Subsystems use scoped names like `hookRegistry`, `integrationRegistry`,
  `mutationRegistry`, `overlayRegistry`, `fallbackRegistry`, and
  `coordinatorRegistry`.
- Local implementation side tables remain local when they are not hot-reload
  global data.

Run full validation:

```powershell
python Setup/test_all.py
```
