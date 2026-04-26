# ReLoad, ModUtil, and Chalk Reference

This document explains how `SGG_Modding-ReLoad`, `SGG_Modding-ModUtil`, and `SGG_Modding-Chalk` actually behave in the Hades II modding stack, with source-backed guidance for hot reload, game-load timing, and config persistence.

It is written for two audiences:
- humans maintaining the modpack
- future agentic tools that should not have to rediscover these library semantics from plugin source

For the hot-reload contract of `adamant-ModpackLib`, `adamant-ModpackFramework`, coordinator shells, and modules built on top of these libraries, see [HOT_RELOAD_ARCHITECTURE.md](HOT_RELOAD_ARCHITECTURE.md).

## Scope

This document focuses on:
- `reload.load`, `reload.auto`, `reload.auto_single`, `reload.auto_multiple`
- `reload.queue.*` triggers
- `modutil.once_loaded.*`
- `ModUtil.LoadOnce`
- `chalk.auto`

It does not define the stack-specific hot-reload architecture for Lib, Framework, Core, or module hosts.

It also calls out a few important things these libraries do **not** do:
- ModUtil wrap registration does **not** deduplicate by callback or mod
- `once_loaded.*` does **not** deduplicate callbacks after a milestone has already happened
- `reload.auto()` does **not** give first-load suppression

## Authoritative Source Files

These are the main source files this document is based on:

- `SGG_Modding-ReLoad/main.lua`
- `SGG_Modding-ReLoad/def.lua`
- `SGG_Modding-ReLoad/triggers.lua`
- `SGG_Modding-ModUtil/main.lua`
- `SGG_Modding-ModUtil/ModUtil.Main.lua`
- `SGG_Modding-ModUtil/ModUtil.lua`
- `SGG_Modding-Chalk/main.lua`
- `SGG_Modding-Chalk/def.lua`
- `ReturnOfModdingBase/src/lua/lua_manager.cpp`
- `Hell2Modding/src/hades2/hades_lua.hpp`
- `Hell2Modding/src/lua_extensions/bindings/hades/data.cpp`

## Related Stack Doc

This file documents third-party library behavior.

The repo-specific hot-reload model built on top of those behaviors is documented in [HOT_RELOAD_ARCHITECTURE.md](HOT_RELOAD_ARCHITECTURE.md).

---

## Executive Summary

Use this as the short version.

- `on_ready` means: run only on the first load for a given ReLoad signature.
- `on_reload` means: run on the first load after `on_ready`, and also on every reload for that signature.
- `reload.auto_single()` is the normal choice for a plugin `main.lua`.
- `reload.auto_multiple()` is for one file that needs several separately tracked reloadable registrations.
- `reload.auto()` does **not** track first load at all. It always behaves like a fresh load and should usually be avoided for normal plugin bootstrap.
- `modutil.once_loaded.game(...)` is a game-readiness gate, not a reload gate.
- `modutil.once_loaded.game(...)` runs immediately if the game milestone already happened.
- `chalk.auto('config.lua')` is the normal way to get persistent config. Recreating the wrapper on reload is normal.
- ModUtil wraps are compositional, not deduplicating. If repeated wraps are safe in practice, that safety comes from the target function being recreated/reset by the reload/import model, not from ModUtil detecting duplicates.

## Mental Model

There are three separate concerns:

1. ReLoad answers:
- when should this file's bootstrap logic run on first load vs reload?

2. ModUtil `once_loaded` answers:
- has the mod system, game scripts, or save/load milestone happened yet?

3. Chalk answers:
- how do I load and persist config across reloads without owning raw file I/O?

Do not mix these up.

Examples:
- `once_loaded.game(...)` does not replace `reload.auto_single()`
- `reload.auto_single()` does not tell you whether HUD globals or game scripts exist yet
- `chalk.auto(...)` does not solve timing; it only solves persisted config loading and update/merge behavior

## ReLoad Semantics

### `reload.load(signature, on_ready, on_reload)`

Source behavior:
- if `signature` is new:
  - run `on_ready()` first if present
  - then run `on_reload()` if present
- if `signature` has already loaded before:
  - skip `on_ready()`
  - run `on_reload()` if present

This comes directly from `handle_load(sig, on_ready, on_reload)` in `SGG_Modding-ReLoad/main.lua`.

Important consequence:
- `on_reload` is not "reload-only"
- it is really "every active load after first-load gating is resolved"

So the names mean:
- `on_ready`: first-load-only
- `on_reload`: always-run lifecycle body

### `reload.auto()`

`reload.auto()` binds ReLoad calls **without a signature**.

That means:
- `handle_load(nil, ...)` always treats the call as a fresh load
- `on_ready()` runs every time
- `on_reload()` also runs every time

This is usually **not** what a normal plugin wants.

Practical interpretation:
- `reload.auto()` gives convenience, not reload identity
- it is useful only when you intentionally do not care about first-load suppression

### `reload.auto_single()`

`reload.auto_single()` is the normal choice for plugin `main.lua`.

It derives a stable signature from:
- the calling file source
- the plugin guid when `_PLUGIN` exists

Then:
- `loader.load(on_ready, on_reload)` tracks first-load-vs-reload correctly for that file
- `loader.queue.*(...)` also uses that same file-level signature

This is the right default for:
- one loader site per file
- a file that reruns on hot reload and wants one first-load gate

### `reload.auto_multiple()`

`reload.auto_multiple()` is for a single file that needs more than one independently tracked reload identity.

It builds a signature prefix from the file, then you supply a local suffix:

```lua
local loader = reload.auto_multiple()
loader.load("hud", onReadyHud, onReloadHud)
loader.load("hooks", onReadyHooks, onReloadHooks)
```

Use this when:
- one file owns multiple logically separate reloadable lifecycles
- you do not want them all sharing one first-load gate

If you only need one lifecycle per file, `auto_single()` is simpler and better.

## ReLoad Queue Triggers

ReLoad also exposes queued triggers.

Defined triggers in `SGG_Modding-ReLoad/triggers.lua`:
- `on_update`
- `pre_import`
- `post_import`
- `any_load`
- `pre_import_file`
- `post_import_file`

These use the same first-load-vs-reload signature rules as `reload.load`.

### `queue.on_update`

Runs from `rom.gui.add_always_draw_imgui`.

Use when:
- you need polling for a condition that becomes true later
- you do not have a cleaner import/load event

Be careful:
- this is effectively per-frame
- avoid heavy work

### `queue.pre_import` / `queue.post_import`

Runs on any game script import through `rom.on_import.pre/post`.

Use when:
- you need to react to script loading in general
- you need to modify `_ENV` or observe the import stream

### `queue.pre_import_file(script)` / `queue.post_import_file(script)`

Runs only for a specific imported game script.

Use when:
- your bootstrap depends on one known game script being imported
- you want a precise hook point like `"HUDLogic.lua"`

This is more precise than `once_loaded.game(...)` if you really care about one script.

### `queue.any_load`

Runs from `rom.game.OnAnyLoad{...}`.

Use when:
- you want a callback on general in-game load transitions
- you need load-context args

This is a gameplay/session load trigger, not the same as plugin file reload.

## ModUtil `once_loaded`

Defined in `SGG_Modding-ModUtil/main.lua`:
- `once_loaded.mod`
- `once_loaded.game`
- `once_loaded.save`

These are milestone gates.

They are **not** reload trackers.

### Important behavior

If a milestone has already happened, then:
- `once_loaded.*(callback)` runs `callback()` immediately

This means:
- no queued dedupe
- no first-load suppression after the milestone
- it is a readiness gate, not a lifecycle tracker

### `once_loaded.mod`

Triggered by `SGG_Modding-ModUtil/ready.lua`.

Meaning:
- ModUtil itself is ready

This is mostly useful if you need to wait for ModUtil bootstrap specifically.

### `once_loaded.game`

Triggered from `rom.on_import.post(...)` in ModUtil when either:
- `RoomLogic.lua`
- `RoomManager.lua`

has been imported.

Meaning:
- the game has reached a script-import milestone ModUtil considers "game ready"

This is the normal gate for:
- HUD/UI work
- framework init that relies on game globals
- mod bootstrap that should happen after core game script availability

### `once_loaded.save`

Triggered indirectly via:
- `ModUtil.LoadOnce(trigger_loaded.save)`

after `once_loaded.game` fires.

Meaning:
- next in-game load after the game-ready milestone

This is the latest and most gameplay-session-oriented milestone in this group.

## `ModUtil.LoadOnce`

`ModUtil.LoadOnce(fn)` queues `fn` to run on the next `OnAnyLoad`.

Implementation:
- `funcsToLoad` is a queue
- `OnAnyLoad{ loadFuncs }` drains it once

Use this when:
- you want something to happen on the next actual in-game load
- not merely after script import

This is what `once_loaded.save` builds on.

## Chalk Semantics

### `chalk.auto(config_lua, config_cfg, descript, section, is_newer)`

`chalk.auto(...)`:
- finds the caller plugin environment
- imports the default config Lua table from that environment
- chooses a `.cfg` path under the plugin guid
- loads both the cfg and default table
- decides which is newer
- merges the resulting values back into the cfg
- returns:
  - a table-like wrapper
  - the underlying config object

In practice, most code uses the wrapper only:

```lua
config = chalk.auto('config.lua')
```

### What persists

The persisted truth is the `.cfg` file managed by ROM config.

The Chalk wrapper:
- is a Lua table-like proxy around the underlying config object
- can be recreated on reload with no problem
- is not the long-lived identity you should build architecture around

This is why current module patterns are correct:
- create config once at top level
- recreate store/session from config on reload

### Merge behavior

`chalk.load(...)` and `chalk.auto(...)` are version-aware by default:
- they compare `version`
- if loaded cfg is newer than the Lua default, it preserves the loaded values
- otherwise it merges defaults in and saves

This is useful for mod config evolution, but it is not a substitute for your own higher-level hash/profile ABI policy.

## Wraps and Hot Reload

This matters because it is easy to assume ModUtil is doing more than it actually does.

### What ModUtil wrap does do

- `ModUtil.Wrap(base, wrap, mod)` creates a new wrapper closure
- stores wrapper history metadata
- supports helper operations like:
  - `Original`
  - `Restore`
  - `Decorate.Refresh`

### What ModUtil wrap does not do

- it does not deduplicate wraps by callback identity
- it does not deduplicate wraps by mod
- it does not say "this path is already wrapped by this plugin, skip"

So:
- repeated wraps stack
- each wrapper gets the previous function as `base`
- one top-level call still calls the chain once, but every wrapper layer runs its side logic

Practical consequence:
- do not rely on ModUtil for hook dedupe
- if wraps are safe across hot reload in practice, that safety is coming from target recreation/reset in the game/reload pipeline or from a higher-level wrapper layer owning dedupe itself

## Best Practices

## 1. Normal plugin `main.lua`

Use:

```lua
local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(nil, init)
end)
```

Why:
- `once_loaded.game(...)` waits for game readiness
- `auto_single()` gives one stable reload identity for the file
- `init` becomes the steady-state bootstrap body that runs on each active load

If you also need stable first-load-only work such as GUI callback registration, split that into a separate `on_ready` function.

This is the normal steady-state plugin pattern when the active bootstrap body is reload-safe.

## 2. Stable GUI registration

Register stable GUI callbacks from `on_ready`, not directly in the game-readiness hook:

```lua
local function registerGui()
    rom.gui.add_imgui(renderWindow)
    rom.gui.add_to_menu_bar(addMenuBar)
end

modutil.once_loaded.game(function()
    loader.load(registerGui, init)
end)
```

Why:
- GUI registration itself should not stack on reload
- the returned callbacks should late-bind to current module/framework state
- `init` can rebuild current state on every reload

## 3. Use `auto_multiple()` only when one file has several distinct reload lifecycles

Do not use `auto_multiple()` just because it sounds more powerful.

Use it only when a single file genuinely owns multiple independently tracked reload registrations.

## 4. Avoid `reload.auto()` for normal module bootstrap

Because `reload.auto()` uses no signature:
- `on_ready` will run every time
- it does not protect first-load logic from rerunning

That makes it a poor default for hot-reload-aware plugin files.

## 5. Use `once_loaded.*` as readiness gates, not dedupe gates

Good:
- "run this after the game milestone exists"

Bad:
- "run this only once ever"

Because after the milestone is already reached, `once_loaded.*` executes immediately every time you call it.

## 6. Recreate runtime wrappers from persisted config on reload

Good pattern:
- `local dataDefaults = import("config.lua")`
- `config = chalk.auto(...)`
- recreate `store, session = lib.createStore(config, definition)`
- recreate module/framework derived state

Recreate wrapper objects during reload so they point at the rebuilt module state.

## 7. Do not rely on ModUtil hook dedupe

If a hook site must be one-time by construction:
- make it one-time in your architecture

Do not assume `ModUtil.Wrap` will silently collapse duplicate registrations.

## When To Use What

Use this decision table.

### "My plugin file should rerun cleanly on hot reload"
Use:
- `reload.auto_single()`

### "I need several independent first-load gates in one file"
Use:
- `reload.auto_multiple()`

### "I need to wait until the game scripts are ready"
Use:
- `modutil.once_loaded.game(...)`

### "I need to run something on the next actual in-game load"
Use:
- `ModUtil.LoadOnce(...)`
- or `modutil.once_loaded.save(...)` if the save milestone is what you want

### "I need a config object that persists across reloads"
Use:
- `chalk.auto('config.lua')`

### "I need to react to one specific imported script"
Use:
- `reload.queue.pre_import_file(...)`
- or `reload.queue.post_import_file(...)`

## Common Misconceptions

### "on_reload only runs on reload"

False.

`on_reload` runs:
- on first load, after `on_ready`
- and on subsequent reloads

### "`once_loaded.game` means once"

False.

It means:
- wait until the milestone is reached
- then run immediately if already reached

### "`reload.auto()` is the simple normal option"

False for hot-reload-aware plugins.

It does not preserve first-load suppression.

### "ModUtil wraps are deduped by mod"

False.

There is metadata for mod ownership in decorator history, but not dedupe behavior.

## Recommended Template

For most Hades II plugin `main.lua` files in this modpack family, use this shape:

```lua
local mods = rom.mods
mods['SGG_Modding-ENVY'].auto()

modutil = mods['SGG_Modding-ModUtil']
local reload = mods['SGG_Modding-ReLoad']
local chalk = mods['SGG_Modding-Chalk']

local config = chalk.auto('config.lua')

local loader = reload.auto_single()

local function registerGui()
    -- first-load-only callback registration
end

local function init()
    -- reimport locals, rebuild definition/store/session, then apply current config
end

modutil.once_loaded.game(function()
    loader.load(registerGui, init)
end)
```

If the plugin has no first-load-only setup, use `loader.load(nil, init)` instead.

For the repo-specific module and coordinator patterns built on top of these libraries, see [HOT_RELOAD_ARCHITECTURE.md](HOT_RELOAD_ARCHITECTURE.md).

## Guidance For Future Agents

If you are an agent reading this later, assume the following unless local repo code clearly contradicts it:

- `auto_single()` is the default reload tool for `main.lua`
- `once_loaded.game(...)` is a readiness gate, not a lifecycle system
- `chalk.auto(...)` returns a fresh wrapper around persisted config each reload; that is normal
- do not claim ModUtil deduplicates wraps unless you have new source evidence
- if you need the repo's stack contract rather than raw library behavior, read [HOT_RELOAD_ARCHITECTURE.md](HOT_RELOAD_ARCHITECTURE.md)
- when reviewing hot reload behavior, separate:
  - plugin file reload
  - game script import milestones
  - in-game load milestones
  - persisted config reloading

If you need to revisit library behavior, start with the source files listed near the top of this document.
