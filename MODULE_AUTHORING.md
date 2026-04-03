# Module Authoring

This guide covers the supported module contract for `adamant-ModpackLib`.

## Shared Rules

Every module exposes:

```lua
public.definition = {
    modpack = PACK_ID,
}

public.store = lib.createStore(config, public.definition)
```

## Module File Conventions

Use this split consistently:
- `config`, `chalk`, and `reload` stay local to `main.lua`
- `public.store = lib.createStore(config, public.definition)` is the boundary where raw Chalk config stops
- `store = public.store` may be shared across module files
- `modutil` and `lib` may be shared across module files
- imported files should read persisted state through `store.read(...)` and write through `store.write(...)`, not raw config
- `internal` is for module-local helpers, registration tables, and cached data, not dependency forwarding

Example:

```lua
local chalk = rom.mods["SGG_Modding-Chalk"]
local reload = rom.mods["SGG_Modding-ReLoad"]
local config = chalk.auto("config.lua")

public.store = lib.createStore(config, public.definition)
store = public.store
```

## Required State Access Rules

These are contract rules, not style preferences:
- keep raw Chalk config local to `main.lua`
- after `public.store = lib.createStore(config, public.definition)`, module code should use `store.read(...)` and `store.write(...)`
- do not share raw config across imported module files

Avoid:

```lua
if config.Strict then
    -- ...
end
```

Use:

```lua
if store.read("Strict") then
    -- ...
end
```

Recommended bootstrap:

```lua
local loader = reload.auto_single()

local function init()
    import_as_fallback(rom.game)

    if internal.RegisterHooks then
        internal.RegisterHooks()
    end

    if lib.isEnabled(public.store, public.definition.modpack) then
        lib.applyDefinition(public.definition, public.store)
    end

    if public.definition.affectsRunData and not lib.isCoordinated(public.definition.modpack) then
        SetupRunData()
    end
end

modutil.once_loaded.game(function()
    loader.load(init, init)
end)
```

## Regular Modules

Regular modules participate in category/group rendering and can expose inline options.

Typical definition:

```lua
public.definition = {
    modpack        = PACK_ID,
    id             = "ExampleMod",
    name           = "Example Mod",
    category       = "Run Mods",
    group          = "General",
    tooltip        = "What this module does.",
    default        = true,
    affectsRunData = false,
    options = {
        { type = "checkbox", configKey = "Strict", label = "Strict Mode", default = false },
        { type = "string", configKey = "Label", label = "Label", default = "", maxLen = 64 },
    },
}
```

Rules:
- `definition.id` is the regular-module hash namespace
- `definition.options` keys must be flat strings
- inline option values are edited through `public.store.uiState`

Standalone helper:

```lua
rom.gui.add_to_menu_bar(lib.standaloneUI(public.definition, public.store))
```

## Special Modules

Special modules get their own sidebar tab and declare state through `definition.stateSchema`.

Typical definition:

```lua
public.definition = {
    modpack        = PACK_ID,
    id             = "ExampleSpecial",
    name           = "Example Special",
    tabLabel       = "Example",
    special        = true,
    default        = false,
    affectsRunData = true,
    stateSchema = {
        { type = "dropdown", configKey = "Mode", values = { "A", "B" }, default = "A" },
        { type = "string", configKey = "TargetKey", default = "", maxLen = 128 },
        { type = "checkbox", configKey = { "Nested", "Flag" }, default = false },
    },
}
```

Rules:
- special-module hash namespace is the module `modName`
- `stateSchema` may use flat keys or nested path arrays
- draw functions receive `uiState`, not raw config

Supported public UI entrypoints:
- `public.DrawQuickContent(ui, uiState, theme)`
- `public.DrawTab(ui, uiState, theme)`

Standalone helper:

```lua
local specialUi = lib.standaloneSpecialUI(public.definition, public.store, public.store.uiState, {
    getDrawQuickContent = function() return public.DrawQuickContent end,
    getDrawTab = function() return public.DrawTab end,
})

rom.gui.add_imgui(specialUi.renderWindow)
rom.gui.add_to_menu_bar(specialUi.addMenuBar)
```

## Modules That Affect Run Data

If successful changes require run-data rebuild behavior, declare:

```lua
public.definition.affectsRunData = true
```

Lifecycle shape is inferred from exports.

### Patch-Only

Use this for deterministic reversible table edits.

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(RoomData.RoomA, "ForcedReward", "Devotion")
    plan:appendUnique(NamedRequirementsData, "SomeKey", { Name = "Req" })
end
```

### Manual-Only

Use this for procedural or engine-side mutation.

```lua
local backup, restore = lib.createBackupSystem()

local function apply()
    backup(SomeTable, "SomeKey")
    SomeTable.SomeKey = 123
end

public.definition.apply = apply
public.definition.revert = restore
```

### Hybrid

Use patch plans for obvious reversible edits and manual logic for the remainder.

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(SomeTable, "SomeKey", 123)
end

public.definition.apply = function()
    -- procedural remainder
end

public.definition.revert = function()
    -- procedural remainder revert
end
```

Stable ordering:
- apply: patch, then manual
- revert: manual, then patch

Guidance:
- prefer patch mode when possible
- keep patch-owned and manual-owned keys conceptually separate

## Managed UI State

When a module declares `options` or `stateSchema`, Lib creates `public.store.uiState`.

Use:
- `uiState.view` for rendering
- `uiState.set/update/toggle` for edits

Do not write schema-backed or option-backed config directly during draw.

Hosted Framework UI and standalone Lib helpers already:
- commit `uiState` transactionally
- roll staged config back on failed reapply
- call `SetupRunData()` after successful commits when required

## Hash/Profile Stability

After release, treat these as compatibility-sensitive:
- regular `definition.id`
- regular option `configKey`
- special `modName`
- special schema keys
- field defaults
- `toHash/fromHash`

If those change, the manual migration path is to save new profiles.
