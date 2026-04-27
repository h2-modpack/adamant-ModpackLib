# Getting Started

This guide is for first-time module authors using adamant ModpackLib and ModpackFramework.

It explains:
- what the main concepts are
- what each source file is for
- how data moves through a module
- how to build a minimal working module from the template

For the exact API surface, use [API.md](../API.md). For the fuller authoring contract, use [MODULE_AUTHORING.md](MODULE_AUTHORING.md).

## Starting A New Repo

If you are starting from scratch, use the scaffold scripts before writing code.

- new pack shell repo:
  [`Setup/scaffold/new_pack.py`](https://github.com/h2-modpack/Setup/blob/main/scaffold/new_pack.py)
- new module inside an existing shell repo:
  [`Setup/scaffold/new_module.py`](https://github.com/h2-modpack/Setup/blob/main/scaffold/new_module.py)

Those scripts handle the repo and submodule chores so you can get to actual module authoring quickly.

Use them when you need:

- a new modpack shell with Lib, Framework, Setup, and a coordinator already wired
- a new module repo created from the template and registered as a shell submodule

After scaffolding, come back to this guide for the actual code model.

If you want the script workflow and setup details, read the
[Setup README.md](https://github.com/h2-modpack/Setup/blob/main/README.md).

## The Core Model

A module is built from four main pieces:

- `definition`
  Declares module identity, storage, and optional mutation lifecycle hooks.
- `store`
  Persisted runtime state. Read this from gameplay and hook code.
- `session`
  Staged UI state. Draw code edits this and host/framework plumbing commits it later.
- `host`
  The behavior object created by `lib.createModuleHost(...)`. Framework and standalone hosting both use this.

Typical module flow:

1. `main.lua` prepares `local definition = lib.prepareDefinition(...)`.
2. `main.lua` creates `store, session = lib.createStore(...)`.
3. `main.lua` creates the live module host through `lib.createModuleHost(...)`.
4. UI code edits staged values through `session`.
5. Host/framework plumbing commits staged persistent values when appropriate.
6. Gameplay logic reads persisted state through `store.read(...)`.

## The Most Important Rule

Use the right state object for the right job:

- draw/UI code uses `session`
- gameplay/runtime logic uses `store`

If you ignore that boundary, the module will still often "work", but you will create drift between the UI and the persisted state model.

## File Roles

The template is split into four files on purpose.

### `src/main.lua`

Owns module wiring:

- imports Lib and stack dependencies
- prepares `definition`
- imports `data.lua`, `logic.lua`, and `ui.lua`
- creates `store` and `session`
- copies `store` to `internal.store` if logic needs it
- creates the live host through `lib.createModuleHost(...)`
- wires optional standalone UI

Keep store/session/host creation here even if the module grows.

### `src/data.lua`

Owns static module data:

- `definition.storage`
- `definition.hashGroupPlan`
- option lists
- lookup tables derived after game import

Use this file to declare module data. UI belongs in `ui.lua`; gameplay behavior belongs in `logic.lua`.

### `src/ui.lua`

Owns immediate-mode UI:

- `internal.DrawTab(ui, session)`
- optional `internal.DrawQuickContent(ui, session)`

This code should read and write staged values through the author-facing `session` it receives from the host.

### `src/logic.lua`

Owns gameplay and mutation behavior:

- `internal.RegisterHooks()`
- `definition.patchPlan`
- optional `definition.apply(...)` / `definition.revert(...)`

This code should read persisted state through `internal.store`.

## First Module Checklist

Start with the template, then fill in these pieces in order.

### 1. Set module identity in `main.lua`

At minimum:

```lua
local definition = lib.prepareDefinition(internal, {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    affectsRunData = false,
})
```

For coordinated modules, `modpack`, `id`, `name`, and `storage` are the important discovery fields.

### 2. Declare storage in `data.lua`

Example:

```lua
local definition = lib.prepareDefinition(internal, dataDefaults, {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    affectsRunData = false,
    storage = {
    { type = "bool", alias = "FeatureEnabled", configKey = "FeatureEnabled" },
    { type = "string", alias = "Mode", configKey = "Mode", maxLen = 32 },
    { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
    },
})
```

Rules:

- persisted values use `configKey`
- transient values use `lifetime = "transient"`
- transient values live only in session state
- draw code should still access both through `session`

### 3. Create the managed state in `main.lua`

```lua
local store, session = lib.createStore(config, definition)
internal.store = store
```

Keep `session` local to `main.lua`. The draw path will receive the restricted author-facing session through the live host.

### 4. Build the UI in `ui.lua`

Example:

```lua
function internal.DrawTab(ui, session)
    lib.widgets.checkbox(ui, session, "FeatureEnabled", {
        label = "Enable Feature",
    })

    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = internal.MODE_VALUES,
        controlWidth = 180,
    })
end
```

Draw callbacks receive the author-facing session API:

- `session.view`
- `session.read(alias)`
- `session.write(alias, value)`
- `session.reset(alias)`

Commit and reload operations are handled by host/framework plumbing.

### 5. Register gameplay logic in `logic.lua`

If the module only changes configuration/UI, `logic.lua` can stay minimal.

If the module changes live run data:

```lua
local definition = lib.prepareDefinition(internal, dataDefaults, {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    affectsRunData = true,
    storage = internal.BuildStorage(dataDefaults),
    patchPlan = function(plan, activeStore)
    if activeStore.read("FeatureEnabled") then
        plan:set(SomeGameTable, "SomeKey", true)
    end
    end,
})
```

Use `patchPlan` when possible. Reach for manual `apply/revert` only when the mutation is not naturally expressed as reversible table edits.

If the module installs runtime hooks, declare them through `lib.hooks.*` from `internal.RegisterHooks()`:

```lua
function internal.RegisterHooks()
    lib.hooks.Wrap(internal, "SomeGameFunction", function(base, ...)
        local result = base(...)

        if internal.store.read("FeatureEnabled") then
            -- apply module-specific logic to the wrapped call here
        end

        return result
    end)
end
```

### 6. Expose the module host in `main.lua`

```lua
lib.createModuleHost({
    definition = definition,
    store = store,
    session = session,
    hookOwner = internal,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
```

This is the main module export.

Framework uses it for coordinated modules. Standalone hosting uses it for module windows and menu items.

If the module has no runtime hooks, `hookOwner` and `registerHooks` may be omitted.

## Coordinated vs Standalone

### Coordinated

If the module belongs to a Framework-managed pack:

- `lib.createModuleHost(...)` registers the module in Lib's live-host registry
- Framework calls `host.drawTab(...)`
- optional quick setup uses `host.drawQuickContent(...)`

### Standalone

If the module is not coordinated:

```lua
internal.standaloneUi = lib.standaloneHost()
```

Then wire:

- `internal.standaloneUi.renderWindow()` into `rom.gui.add_imgui(...)`
- `internal.standaloneUi.addMenuBar()` into `rom.gui.add_to_menu_bar(...)`

Standalone hosting automatically suppresses itself when the module is coordinated.

## How State Actually Flows

This is the part most new authors get wrong.

### Persisted values

Persisted storage roots live in Chalk config and are exposed through `store.read(...)`.

The UI stages edits in `session`, then host/framework plumbing commits those edits later.

### Transient values

Transient aliases never hit persisted config. They only live in `session`.

Examples:

- filter text
- temporary selection state
- ephemeral editor helpers

### Packed values

Packed widgets can edit packed child aliases, but storage still persists the packed root. Lib handles the repacking automatically.

## Common Mistakes

### Reading transient values from `store`

Transient aliases live in `session`. Read them with `session.read(...)` or `session.view`.

### Writing persisted config directly from draw code

Normal draw code should stage values through `session` and let the host/framework commit them.

### Putting gameplay logic in `ui.lua`

Keep UI and game mutation separate. UI edits state; logic applies state.

### Putting UI outside draw functions

Author UI through draw functions such as `internal.DrawTab(ui, session)`.

## LuaLS Setup

The template already shows the pattern that gives good editor inference:

```lua
---@type AdamantModpackLib
lib = mods["adamant-ModpackLib"]
```

And for the module internal table:

```lua
---@class TemplateModuleInternal
---@field DrawTab fun(imgui: table, session: AuthorSession)|nil
---@field DrawQuickContent fun(imgui: table, session: AuthorSession)|nil
```

That lets LuaLS infer the `AuthorSession` type through `internal.DrawTab = function(...)`.

## Recommended Next Reads

After this guide:

1. Read [MODULE_AUTHORING.md](MODULE_AUTHORING.md) for the fuller authoring contract.
2. Use [API.md](../API.md) when you need exact function names and behavior.
3. Use the template source files as the concrete code reference.
