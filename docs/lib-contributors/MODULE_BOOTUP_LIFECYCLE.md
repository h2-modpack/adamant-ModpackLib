# Module Bootup Lifecycle

This note tracks cold-start module boot order for Lib and Framework. Use
[HOT_RELOAD_ARCHITECTURE.md](HOT_RELOAD_ARCHITECTURE.md) for reload behavior and
[../module-authors/DRAW_LIFECYCLE.md](../module-authors/DRAW_LIFECYCLE.md) for
per-frame draw/commit behavior.

The key invariant: normal startup hydrates persisted config once, when Lib
constructs module state. Activation, fallback UI startup, and Framework initial
UI staging trust that prepared state.

## Shared Module Creation

Every module, coordinated or standalone, enters through the same Lib path:

1. Module code calls `lib.createModule(...)`.
2. The returned declaration facade collects storage, status, cache, controls,
   actions, hooks, overlays, shared declarations, mutation, UI callbacks, and
   optional fallback UI attachment requests.
3. Module code calls `module.activate()`.
4. The activation finalizer compiles controls and status storage.
5. Lib prepares the definition and structural fingerprint.
6. `moduleState.create(config, definition)` constructs persistent and staged
   state.
7. Persistent state hydrates persisted roots from config exactly once.
8. Staged state copies from committed roots.
9. `managedModule.create(...)` builds the live module, runtime context, UI
   context, action buffer, callback host, and control catalog.
10. Activation installs and commits capability receipts: shared, hooks,
    overlays, mutation, and optional fallback UI.
11. Lib publishes the live module by `pluginGuid`.
12. `module.onActivate(host, runtime)` runs, if declared, against the prepared
    runtime state.

Activation does not call `_reloadFromConfig()`. If `onActivate(...)` cannot see
hydrated runtime data, the bug is in state construction or declaration
preparation, not in activation ordering.

## Uncoordinated Fallback Boot

An uncoordinated module is a normal live module whose pack id has no registered
coordinator.

1. The shared module creation sequence runs.
2. If the module called `module.fallbackUi.attachGuiOnce(...)`, Lib records a
   fallback UI request before activation.
3. Activation commits the fallback UI receipt.
4. The fallback receipt installs a hot-reload-stable runtime for the module's
   owner id and refreshes the fallback HUD marker.
5. ROM GUI callbacks call through the stable fallback bridge and late-read the
   current runtime.
6. The fallback menu renders `Show Mod Menu` for uncoordinated modules.
7. Opening the fallback window snapshots runtime controls from the live module:
   `module.isEnabled()` and `module.read("DebugMode")`.
8. Opening or first drawing the fallback window does not reload config.
9. The fallback tab calls `module.drawTabAndCommit()` only while the module is
   enabled.

Fallback enable/debug toggles stage through the live module lifecycle. If staged
state drift is detected, lifecycle code resyncs staged state from already
committed roots and then stages the requested boolean. That repair must not
re-read external config.

## Coordinated Framework Boot

A coordinated module is the same live module plus a Framework pack that discovers
it by pack id.

1. The coordinator calls `Framework.registerCoordinator(packId, displayName,
   config, rebuildCallback)`.
2. Each module runs the shared Lib module creation sequence and publishes a live
   module under its `pluginGuid`.
3. The coordinator calls `Framework.createPack(...)`.
4. Framework validates pack config and runtime prerequisites.
5. Framework creates a module registry for the pack.
6. `moduleRegistry.refresh(...)` scans live modules and builds entries from live
   module metadata, storage, module id, pack id, and quick-content capability.
7. Framework creates hash, HUD, theme, and UI runtime objects.
8. Framework UI reconciles pack-disabled state.
9. Framework initial UI staging captures a live-module snapshot and reads
   enabled/debug state from that snapshot.
10. Framework initial UI staging does not call `liveModule.reloadFromConfig()`.
11. Framework audits saved profiles and installs HUD behavior.
12. The pack is published in `FrameworkPackRegistry`.

Framework is allowed to rebuild its own pack/UI objects on coordinator re-entry,
but normal module activation remains the source of hydrated module state.

## Reload Boundaries

These paths intentionally re-read config after startup:

- `module.reloadFromConfig()`: explicit live-module API for external config
  resync.
- Framework hash/profile apply: writes staged values, flushes them, then reloads
  module state from config so UI mirrors the applied profile.
- Framework runtime `resyncAllState()`: explicit user/runtime resync.
- Lib lifecycle mismatch resync: used after an internal staged/committed audit
  detects drift.

These paths should not re-read config during normal startup:

- `managed_module_activation.activateOrThrow(...)`
- fallback UI install
- fallback first window open
- fallback first draw
- Framework initial `createUI(...)` staging
- lifecycle enable/debug drift repair

## Startup Hydration Contract

The normal startup contract is:

1. Persistent state construction is the config hydration boundary.
2. Staged state construction mirrors committed roots.
3. Activation trusts the prepared persistent and staged state.
4. `onActivate(...)` reads committed runtime state through `runtime.data` and
   `runtime.status`.
5. UI startup snapshots live module state; it does not repair or rehydrate it.
6. Later external config changes must enter through explicit reload/resync paths.

If a future change needs a second startup reload, first prove which earlier
boundary failed to construct the correct committed state. A second reload should
be treated as a boundary bug until proven otherwise.
