# Hot Reload Architecture

This document describes the supported hot-reload model of the adamant stack.

It covers how `adamant-ModpackLib`, `adamant-ModpackFramework`, coordinator shells, and coordinated modules stay coherent when files reload inside one live Hades II process.

For the raw behavior of `SGG_Modding-ReLoad`, `SGG_Modding-ModUtil`, and `SGG_Modding-Chalk`, read [RELOAD_MODUTIL_CHALK_REFERENCE.md](RELOAD_MODUTIL_CHALK_REFERENCE.md) first.

## Goals

- keep normal player sessions safe without requiring code edits
- support module development with live module reloads
- support Lib and Framework development without leaving the stack on stale hosts or stale callbacks
- keep ownership of reload-sensitive responsibilities explicit

## Process Model

Hot reload reruns Lua files inside the live game process.

Important consequences:
- a full game process restart clears mod globals, wrapper chains, and reload state
- loading a save, starting a run, or returning to title is not a full process restart
- persistent module globals survive when code reuses them with `X = X or {}`

The stack relies on that persistence for stable internal registries.

## Persistent Internal Globals

The stack deliberately stores reload-sensitive state on `_G` tables:

- `AdamantModpackLib_Internal`
- `AdamantModpackFramework_Internal`
- each module's `RunDirector*_Internal` table

These tables are initialized with `X = X or {}` so they survive a file reload in the same game process.

Safe to rebuild on every module `init`:
- `definition`
- `store`
- `session`
- `public.host`
- UI draw closures
- lookup tables derived from current imports

Expected to persist across reloads:
- Lib coordinator registrations
- Lib mutation runtime state
- Lib hook registries keyed by persistent hook owner tables
- Framework pack registry and stable GUI callbacks
- Framework generation counter
- module-local hook owner tables

Do not replace an entire persistent `*_Internal` table during reload. Mutate fields on the existing table instead. Replacing the table breaks hook ownership, mutation tracking, and any live closures that intentionally point at the persistent owner.

## Layer Responsibilities

### Core

Core owns coordinator bootstrap and stable GUI callback registration.

Core responsibilities:
- register stable `rom.gui` callbacks once behind `modutil.once_loaded.game(...)`
- call `Framework.init(...)` from the reload body
- late-read Framework factories so a Framework reload does not leave Core holding stale closures

### Framework

Framework owns pack-level coordinator state:
- discovery
- hashing
- HUD
- coordinator UI

Framework also owns pack freshness checks:
- it stores the init params used to build each pack session
- it rebuilds a pack when Framework itself reloads
- it does not rebuild a pack for ordinary coordinated module behavior reloads

### Lib

Lib owns the shared reload-sensitive plumbing:
- coordinator registration
- coordinated module startup/runtime sync
- stable ModUtil hook dispatch
- mutation runtime persistence
- standalone host suppression for coordinated modules

### Modules

Modules own their local rebuild:
- recreate `definition`, `store`, `session`, and `public.host` in `init`
- keep `chalk`, `reload`, and raw config local to `main.lua`
- keep persisted runtime reads on `store`
- keep staged UI edits on the author-facing `session`
- declare runtime hooks from `internal.RegisterHooks()`

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

## Coordinated Module Host Refresh

`lib.createModuleHost(...)` is the behavior refresh boundary for a coordinated module.

When host creation succeeds:
- the module host closes over the current `definition`, `store`, and `session`
- if `hookOwner` and `registerHooks` are provided, Lib refreshes that owner's hook registrations
- if the coordinator for `definition.modpack` is already registered, Lib immediately runs `host.applyOnLoad()`

That means one coordinated module reload refreshes its live runtime behavior immediately without forcing a pack rebuild.

## Framework Pack Refresh

Framework stores two things per pack session:
- `initParams`
- `frameworkGeneration`

Its renderer, menu-bar callback, and always-draw callback all run a freshness check before using the pack.

Framework rebuilds the pack when:
- Framework reloaded and its generation changed

The rebuild path reruns `Framework.init(pack.initParams)` and refreshes discovery, HUD, hash, and UI state from the latest framework surfaces.

The re-entry is intentional. Core registers GUI callbacks once, and those callback closures remain valid across reloads. Before drawing, the callback asks Framework whether the pack object was created by the current Framework generation. If not, Framework calls the latest `rom.mods["adamant-ModpackFramework"].init(...)` using the remembered `initParams`.

The invariant is:
- stable callbacks survive reloads
- pack objects are generation-scoped
- the latest Framework code is always reached through `rom.mods`
- ordinary coordinated module reloads do not require a pack rebuild

This keeps Core from accumulating duplicate GUI callbacks while still letting Framework code changes rebuild pack-level state.

## Hook Model

Raw ModUtil path hooks do not deduplicate. The stack solves that through `lib.hooks`.

Supported public hook entrypoints:
- `lib.hooks.Wrap`
- `lib.hooks.Override`
- `lib.hooks.Context.Wrap`

The model is:
- use a persistent owner table, typically the module `internal`
- register hook sites from `internal.RegisterHooks()`
- pass `hookOwner` and `registerHooks` into `lib.createModuleHost(...)`
- Lib runs the full registration pass during host creation

Behavior:
- the same owner/path/key updates the live handler instead of stacking another wrapper
- function overrides dispatch through a stable wrapper
- omitted wrap and context-wrap registrations become inert
- omitted override registrations are restored

This keeps hot-reloaded logic live without accumulating normal duplicate wrappers.

### Hook Caveat

There is one accepted development-only caveat.

If the same wrap or context-wrap site is:
- removed
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

Mutation runtime is persisted on `AdamantModpackLib_Internal`, not on recreated store objects.

Important properties:
- active tracked mutation state survives store recreation
- active state is keyed by stable module identity when available
- `applyOnLoad` synchronizes live mutation state to the module's effective enabled state
- if a module is disabled on reload, tracked active mutation state is reverted

This keeps run-data patch lifecycles coherent across reloads.

## Coordinator And Standalone Behavior

Coordinator metadata is persisted on `AdamantModpackLib_Internal.coordinators`.

Important consequences:
- a Lib reload does not forget which packs are coordinated
- standalone module windows remain suppressed for coordinated modules
- standalone startup lifecycle applies only when the module is not coordinated

Framework calls `applyOnLoad()` for discovered coordinated modules during pack init.
`lib.standaloneHost(...)` calls `applyOnLoad()` for standalone modules during standalone startup.
`lib.createModuleHost(...)` also calls `applyOnLoad()` immediately when the module is already coordinated, so behavior-only module reloads resync live runtime state without a pack rebuild.

## Safety By Scenario

### Normal player use

Safe.

Players who are not editing files do not exercise the hot-reload path. The stack boots from scratch and uses the same runtime contracts without reload churn.

### Developer doing module work

Supported.

Module reload replaces the module's live host surface. Framework snapshots that host on the next UI/hash operation, and Lib immediately resyncs live mutation state if the module is already coordinated.

### Developer doing Lib or Framework work

Supported.

Persistent Lib registries survive Lib reload. Core late-reads Framework callbacks. Framework rebuilds pack state when its generation changes.

### Developer reloading Lib and modules in one session

Supported.

The coordinator registry, mutation runtime, and Framework freshness checks are designed to converge back to the latest live surfaces.

### Structural edits

Not hot-reload resilient by design.

Changes to:
- `definition.id`
- `definition.modpack`
- `definition.name` or `shortName`
- `definition.storage`
- `definition.hashGroupPlan` / host hash hints
- module presence or discovery shape

should be handled by a full reload.

## Practical Rules

- keep `chalk`, `reload`, and raw config local to `main.lua`
- recreate `definition`, `store`, `session`, and `public.host` in `init`
- keep `session` local to `main.lua`; draw callbacks receive the restricted author session through the host
- register runtime hooks through `internal.RegisterHooks()` and `lib.hooks.*`
- pass `hookOwner` and `registerHooks` to `lib.createModuleHost(...)` when the module owns runtime hooks
- keep stable GUI callbacks outside `init`
- late-read current framework or module state from those stable callbacks when a stale closure would matter
- do not use raw ModUtil path wraps for repo-owned hot-reload-sensitive hook sites
- do not replace persistent internal registries on reload; update their contents instead
