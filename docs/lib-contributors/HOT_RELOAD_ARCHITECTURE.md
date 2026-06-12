# Hot Reload Architecture

This document describes the supported hot-reload model of the adamant stack.

It covers how `adamant-ModpackLib`, coordinator shells, and coordinated modules
stay coherent when files reload inside one live Hades II process.

For the raw behavior of `SGG_Modding-ReLoad`, `SGG_Modding-ModUtil`, and `SGG_Modding-Chalk`, read [RELOAD_MODUTIL_CHALK_REFERENCE.md](../references/RELOAD_MODUTIL_CHALK_REFERENCE.md) first.

Accepted hot-reload boundaries are documented in
[KNOWN_LIMITATIONS.md](../references/KNOWN_LIMITATIONS.md).

## Goals

- keep normal player sessions safe without requiring code edits
- support module development with live module reloads
- document Lib reloads as infrastructure development paths with a full restart as the correctness boundary
- keep ownership of reload-sensitive responsibilities explicit

## Process Model

Hot reload reruns Lua files inside the live game process.

Important consequences:
- a full game process restart clears mod globals, wrapper chains, and reload state
- loading a save, starting a run, or returning to title is not a full process restart
- persistent module globals survive when code reuses them with `X = X or {}`

The stack relies on that persistence for stable runtime registries.

## Persistent Runtime Globals

The stack deliberately stores reload-sensitive state on `_G` tables:

- `AdamantModpackLib_Runtime`
-- `AdamantModpackLib_Runtime.registry.modpacks`

These tables are initialized with `X = X or {}` so they survive a file reload in the same game process.

Safe to rebuild on every module `init`:
- module declarations
- committed runtime data and staged UI data adapters
- live module created by `lib.createModule(...)` and activated by `module.activate()`
- UI draw closures
- lookup tables derived from current imports

Expected to persist across reloads:
- Lib coordinator registrations under `AdamantModpackLib_Runtime.registry.coordinators`
- Lib live-module registry keyed by `pluginGuid` under `AdamantModpackLib_Runtime.registry.modules`
- Lib hook dispatchers that map each capability owner slot to its current owner
  object under `AdamantModpackLib_Runtime.registry.hooks`
- Lib shared event listeners, mutation owner slots, retained overlays, and
  fallback GUI bridges under their scoped `AdamantModpackLib_Runtime.registry`
  buckets
- Lib modpack registry and stable GUI callbacks
- module-owned ROM GUI callbacks attached through `module.fallbackUi.attachGuiOnce(...)`
  and backed by Lib fallback UI bridges keyed by owner id

Modules pass `pluginGuid` as their stable lifecycle identity. The live module
for that plugin is the structural hot-reload baseline and the owner for managed
hooks, overlays, shared events, and activation metadata. Capability backends
receive this identity as an `ownerId`; system scopes provide their own scoped
owner ids. Mutation runtime remains owner-scoped because raw game-table edits
are process-global.

## Layer Responsibilities

### Coordinator

The coordinator owns pack bootstrap and stable GUI callback registration.

Coordinator responsibilities:
- register stable `rom.gui` callbacks once behind `modutil.once_loaded.game(...)`
- register coordinator metadata from `mods.on_all_mods_loaded(...)`
- call `lib.modpack.createPack(...)` from the reload body or lazy pack creation path
- late-read Lib modpack callbacks so a Lib reload does not leave the coordinator holding stale closures

`mods.on_all_mods_loaded(...)` is intentional coordinator timing, not a generic
readiness gate. ROM calls these callbacks after the full mod graph loads, and it
also replays a module's callbacks when that module hot reloads after the
all-mods-loaded milestone. That gives the coordinator both properties the beacon
needs: initial registration happens after coordinated modules have loaded, and
later coordinator reloads refresh Lib's stored rebuild callback closure.

### Lib Modpack

Lib modpack owns pack-level coordinator state:
- discovery
- hashing
- HUD
- coordinator UI

Lib owns the current pack object for each `packId`.
Coordinator code owns the pack creation parameters and re-calls `lib.modpack.createPack(...)`
when the coordinator layer reloads or when Lib requests a coordinated
structural rebuild.

### Lib

Lib owns the shared reload-sensitive plumbing:
- coordinator registration
- coordinated module startup/runtime sync
- stable ModUtil hook dispatch
- shared event listener refresh
- retained overlay registration and refresh
- mutation runtime tracking for module reloads
- fallback UI suppression for coordinated modules

### Modules

Modules own their local rebuild:
- recreate module declarations and activate the Lib-created live module in `init`
- keep `chalk`, `reload`, and raw config local to `main.lua`
- keep committed runtime reads on `runtime.data`
- keep staged UI edits on draw `ui.data`
- declare runtime hooks on `module.hooks.*` before activation
- declare retained overlays on `module.overlays.*` before activation

## Bootstrap Pattern

The steady-state plugin pattern is:

```lua
local loader = reload.auto_single()

local function registerGui()
    rom.gui.add_imgui(renderWindow)
    rom.gui.add_always_draw_imgui(alwaysDraw)
    rom.gui.add_to_menu_bar(addMenuBar)
end

local function init()
    -- rebuild current state
end

modutil.once_loaded.game(function()
    loader.load(registerGui, init)
end)
```

The important part is the split:
- stable GUI registration happens once
- the active state rebuild happens from `init`

## Coordinated Module Refresh

`lib.createModule(...)` plus `module.activate()` is the normal behavior refresh boundary for a coordinated module.

During module creation and activation:
- the module declaration facade collects data, UI, actions, hooks, overlays, shared declarations, mutations, and cache
- `module.activate()` creates and publishes the live module
- Lib refreshes hook registrations under the module owner id derived from `pluginGuid`; absent hook registrations for that owner are deactivated
- Lib refreshes shared event listener registrations under the module owner id derived from `pluginGuid`; absent shared event listeners for that owner are removed
- if the coordinator for `definition.modpack` is already registered, Lib immediately syncs live mutation state

That means one coordinated module reload refreshes its live runtime behavior immediately without forcing a pack rebuild.

## Modpack Refresh

Lib modpack replaces the current pack object when the coordinator calls
`lib.modpack.createPack(...)` again for the same `packId`. The replacement keeps
the pack's stable HUD/index slot while rebuilding discovery, HUD, hash, and UI
state from the current live modules.

The coordinator registers GUI callbacks once and those callback closures remain
valid across reloads by reading the current pack runtime from Lib's hot-reload
stable modpack registry.

The invariant is:
- stable callbacks survive reloads
- the coordinator owns `lib.modpack.createPack(...)` re-entry
- ordinary coordinated module behavior reloads do not require a pack rebuild

Lib modpack reload is an infrastructure path, not the fast module-authoring path.
Rebuilding a pack is allowed to recreate modpack UI state from scratch. The
mod window may close, the selected tab may reset, and transient profile/import
feedback may be lost. Persist only correctness-critical state across Lib
reloads. Module behavior state refreshes through live modules.

A Lib file reload does not, by itself, rebuild an existing pack object. The
coordinator must call `lib.modpack.createPack(...)` again, either from its
reload body or through a coordinated structural rebuild request.

HUD marker text is safe to refresh in place. HUD marker layout is not: the game
creates retained HUD components from `ScreenData.HUD.ComponentData`, so changing
that table only affects future HUD construction. A Lib modpack change that
moves or restyles the marker structurally must recreate the HUD component or
wait for a game HUD refresh.

## Hook Model

Raw ModUtil path hooks do not deduplicate. The stack solves that through `module.hooks`.

Supported public hook entrypoints:
- `module.hooks.wrap`
- `module.hooks.override`
- `module.hooks.contextWrap`

The model is:
- register hook sites on the returned module declaration facade before activation
- pass `pluginGuid` into `lib.createModule(...)`
- call `module.activate()` after declarations
- Lib runs the full registration pass during module activation

Behavior:
- the same plugin-guid/path/key updates the live handler and keeps one active wrapper
- function overrides dispatch through a stable wrapper
- omitted wrap and context-wrap registrations become inert
- omitted override registrations are restored

This keeps hot-reloaded logic live without accumulating normal duplicate wrappers.

### Hook Caveat

There is one accepted development-only caveat.

If the same wrap or context-wrap site is:
- omitted from a registration pass
- hot reloaded
- re-added
- hot reloaded again

within one live game process, inert wrappers can accumulate for that path.

This is:
- dev-only
- functionally safe
- cleared by a full game process restart

The stack does not currently engineer around that case.

## Mutation Model

Mutation runtime is durable across module reloads, not across arbitrary Lib
implementation reloads.

Important properties:
- active tracked mutation state survives live-module recreation during module reload
- active module records are keyed by `pluginGuid`
- module activation synchronizes live mutation state to the module's persisted enabled state
- if a module is disabled on reload, tracked active mutation state is reverted

This keeps run-data patch lifecycles coherent across reloads.

Lib reload is an infrastructure development path. If Lib's mutation internals
reload while mutations are already active, use a full game process restart as the
correctness boundary before validating mutation rollback behavior.

## Coordinator And Fallback UI Behavior

Coordinator metadata is persisted on
`AdamantModpackLib_Runtime.registry.coordinators.configs`.

Important consequences:
- a Lib reload does not forget which packs are coordinated
- fallback UI windows remain suppressed for coordinated modules
- activation-time mutation sync uses coordinator state when present and module state otherwise

Activation syncs live mutation state for both coordinated and fallback UI modules.
Lib modpack init and fallback UI activation do not run a separate startup mutation pass.
This keeps non-structural module reloads on the same managed module activation path as cold startup.

## Safety By Scenario

### Normal player use

Safe.

Players who are not editing files do not exercise the hot-reload path. The stack boots from scratch and uses the same runtime contracts without reload churn.

### Developer doing module work

Supported.

Module reload replaces the module's live runtime surface. Lib modpack snapshots
that module on the next UI/hash operation, and Lib immediately resyncs live
mutation state if the module is already coordinated.

### Developer doing Lib work

Best-effort infrastructure development path.

Persistent Lib registries survive Lib reload, and the coordinator callbacks read
current pack state from Lib's modpack registry. Existing managed modules may
still close over prior Lib implementation closures until the owning module
reloads. The coordinator must re-call `lib.modpack.createPack(...)` to rebuild
pack state after Lib modpack changes. Use a full process restart as the
correctness boundary for infrastructure changes that affect mutation internals,
top-level registration, or retained HUD layout.

### Developer reloading Lib and modules in one session

Best-effort.

The coordinator registry, live-module registry, and coordinator rebuild callback
are designed to converge back to the latest live surfaces after the relevant
modules rebuild their live modules. Active mutation runtime is not a Lib reload
persistence guarantee.

### Structural edits

Handled by coordinated rebuild when a coordinator rebuild callback is registered;
otherwise full reload is required.

Changes to:
- `definition.id`
- `definition.modpack`
- `definition.name`
- `definition.shortName`
- `definition.storage`
- module presence or discovery shape

should be treated as structural coordination work. In coordinated packs, Lib
can request a modpack rebuild after the replacement live module is created.
Outside that coordinated path, use a full reload.

## Practical Rules

- keep `chalk`, `reload`, and raw config local to `main.lua`
- recreate module declarations and activate the Lib-created live module in `init`
- keep staged state behind the live module; draw callbacks receive restricted
  `ui.draw`, `ui.data`, and `ui.actions` through the UI callback object
- register runtime hooks through `module.hooks.*` before activation
- pass `pluginGuid` to `lib.createModule(...)`
- call `module.activate()` after declarations
- keep stable GUI callbacks outside `init`
- late-read current modpack or module state from those stable callbacks when a stale closure would matter
- do not use raw ModUtil path wraps for repo-owned hot-reload-sensitive hook sites
- keep persistent runtime registries stable across reloads; update their contents in place
