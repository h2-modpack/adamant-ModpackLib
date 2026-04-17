# Module Authoring

This guide describes the current supported module contract in Lib.

It is written for the live surface:
- namespaced public API
- managed storage and `uiState`
- immediate-mode widgets
- direct `DrawTab(ui, uiState)` authoring

It does not document the old declarative `definition.ui` model.

## Preferred Lib Surface

New module code should use:
- `lib.store.create(...)`
- `lib.storage.*`
- `lib.mutation.*`
- `lib.host.*`
- `lib.coordinator.*`
- `lib.widgets.*`
- `lib.nav.*`

Flat `lib.*` aliases should not be used for new code.

## Basic Module Shape

Typical coordinated module:

```lua
local dataDefaults = import("config.lua")

public.definition = {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    tooltip = "What this module does.",
    default = false,
    affectsRunData = false,
    storage = {
        { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 32 },
        { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
    },
}

public.store = lib.store.create(config, public.definition, dataDefaults)
store = public.store

function internal.DrawTab(ui, uiState)
    lib.widgets.checkbox(ui, uiState, "EnabledFlag", {
        label = "Enabled",
    })

    lib.widgets.dropdown(ui, uiState, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 180,
    })
end

function internal.DrawQuickContent(ui, uiState)
    lib.widgets.dropdown(ui, uiState, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 140,
    })
end

public.DrawTab = internal.DrawTab
public.DrawQuickContent = internal.DrawQuickContent
```

## Definition Rules

Meaningful module definition fields:
- `modpack`
- `id`
- `name`
- `shortName`
- `tooltip`
- `default`
- `storage`
- `hashGroups`
- `affectsRunData`
- `patchPlan`
- `apply`
- `revert`

Ignored under the current lean contract:
- `category`
- `subgroup`
- `placement`
- `ui`
- `customTypes`
- `selectQuickUi`

If you keep those fields around, Lib will warn in debug mode.

## Store and State Rules

After store creation:
- use `store.read(alias)` and `store.write(alias, value)` for persisted runtime state
- use `store.uiState` for staged UI state
- keep raw Chalk config local to `main.lua`

Draw code should usually read from:
- `uiState.view`

Runtime/gameplay code should usually read from:
- `store.read(...)`

Do not write schema-backed persisted values directly from draw code through raw config.

## Storage Authoring

### Persisted roots

```lua
{ type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
{ type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 }
{ type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 32 }
```

### Transient roots

```lua
{ type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 }
```

Rules:
- persisted roots use `configKey`
- transient roots use `lifetime = "transient"`
- `configKey` and `lifetime` are mutually exclusive
- transient roots do not hash

### Packed storage

Use `packedInt` when you need alias-addressable packed children:

```lua
{
    type = "packedInt",
    alias = "PackedAphrodite",
    configKey = "PackedAphrodite",
    bits = {
        { alias = "AttackBanned", offset = 0, width = 1, type = "bool", default = false },
        { alias = "RarityOverride", offset = 1, width = 2, type = "int", default = 0 },
    },
}
```

If the module only treats the packed value as a raw mask, keep it as a plain root `int` instead.

## Immediate-Mode UI

Current module UI should be authored directly in Lua draw functions.

Typical patterns:
- `lib.widgets.checkbox(...)`
- `lib.widgets.dropdown(...)`
- `lib.widgets.radio(...)`
- `lib.widgets.stepper(...)`
- `lib.widgets.packedCheckboxList(...)`
- `lib.nav.verticalTabs(...)`

Use raw ImGui layout as needed:
- `ui.Text(...)`
- `ui.SameLine()`
- `ui.BeginTabBar(...)`
- `ui.BeginChild(...)`

Lib widgets are helpers, not a full layout runtime.

## Quick Content

Framework Quick Setup now reads only:
- coordinator `renderQuickSetup(ctx)`
- module `DrawQuickContent(ui, uiState)`

There is no quick-node discovery from `definition.ui`.

## Mutation Lifecycle

Use `affectsRunData = true` only when the module actually mutates live run data.

Supported lifecycle shapes:
- patch only: `patchPlan(plan, store)`
- manual only: `apply(store)` + `revert(store)`
- hybrid: both

Patch-plan example:

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(SomeTable, "Enabled", true)
    plan:appendUnique(SomeTable, "Pool", "NewEntry")
end
```

Lib helpers:
- `lib.mutation.apply(def, store)`
- `lib.mutation.revert(def, store)`
- `lib.mutation.reapply(def, store)`
- `lib.mutation.setEnabled(def, store, enabled)`

## Coordinated Modules

Framework-hosted modules should export:
- `public.definition`
- `public.store`
- `public.DrawTab`
- optional `public.DrawQuickContent`

Framework discovery requires:
- `definition.modpack`
- `definition.id`
- `definition.name`
- `definition.storage`
- public `store`
- public `DrawTab`

## Standalone Modules

For non-framework hosting, use:

```lua
local runtime = lib.host.standaloneUI(
    public.definition,
    public.store,
    public.store.uiState,
    {
        getDrawTab = function() return public.DrawTab end,
        getDrawQuickContent = function() return public.DrawQuickContent end,
    }
)

rom.gui.add_imgui(runtime.renderWindow)
rom.gui.add_to_menu_bar(runtime.addMenuBar)
```

Standalone host still supports before/after draw hooks in `opts`, but framework-hosted modules should not rely on them.
