# Module Authoring

This guide describes the supported module contract in Lib:
- namespaced public API
- managed storage and explicit `session`
- immediate-mode widgets
- direct draw-function authoring through `internal.DrawTab(ui, session)`

## Lib Surface

Module code should use:
- `lib.config`
- `lib.createStore(...)`
- `lib.createModuleHost(...)`
- `lib.standaloneHost(...)`
- `lib.isModuleEnabled(...)`
- `lib.isModuleCoordinated(...)`
- `lib.resetStorageToDefaults(...)`
- `lib.hooks.*`
- `lib.hashing.*`
- `lib.mutation.*`
- `lib.lifecycle.*`
- `lib.widgets.*`
- `lib.nav.*`

Use the namespaced API directly.

## Basic Module Shape

Typical coordinated module:

```lua
local dataDefaults = import("config.lua")

local definition = lib.prepareDefinition(internal, dataDefaults, {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    tooltip = "What this module does.",
    affectsRunData = false,
    storage = {
        { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 32 },
        { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
    },
})

local store, session = lib.createStore(config, definition)
internal.store = store

function internal.DrawTab(ui, session)
    lib.widgets.checkbox(ui, session, "EnabledFlag", {
        label = "Enabled",
    })

    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 180,
    })
end

function internal.DrawQuickContent(ui, session)
    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 140,
    })
end

public.host = lib.createModuleHost({
    definition = definition,
    store = store,
    session = session,
    hookOwner = internal,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
```

This example assumes coordinated/framework hosting.
For standalone-only modules, `DrawQuickContent` is optional and only matters if some external host uses it.
If the module does not register runtime hooks, omit `hookOwner` and `registerHooks`.

## Definition Rules

Meaningful prepared definition fields:
- `modpack`
- `id`
- `name`
- `shortName`
- `tooltip`
- `storage`
- `hashGroupPlan`
- `affectsRunData`
- `patchPlan`
- `apply`
- `revert`

In debug mode, Lib warns on any definition key outside the list above so typos surface early.

Coordinated modules should declare:
- `modpack`
- `id`
- `name`
- `storage`

Framework behavior:
- every coordinated module gets its own tab
- `shortName` is used as the shorter tab label when present

## Store and State Rules

After store creation:
- use `store.read(alias)` for persisted runtime state
- use the explicit `session` return for staged UI state
- keep raw Chalk config local to `main.lua`

Draw code should usually read from:
- `session.view`

Runtime/gameplay code should usually read from:
- `store.read(...)`

Lifecycle/framework plumbing can persist built-in host state through:
- `lib.lifecycle.setEnabled(def, store, enabled)`
- `lib.lifecycle.setDebugMode(store, enabled)`

Hash/profile plumbing should stage arbitrary decoded aliases through:
- `session.write(alias, value)`
- `session._flushToConfig()`

Draw code stages schema-backed values through `session`. Under the host contract, draw callbacks receive an author session with:
- `session.view`
- `session.read(alias)`
- `session.write(alias, value)`
- `session.reset(alias)`

Use `store.read(...)` from runtime/gameplay code for persisted values. Use `session` for transient aliases and UI edits.

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
- transient roots are excluded from hash/profile serialization

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

If the module treats the packed value as a raw mask, a plain root `int` is enough.

## Immediate-Mode UI

Module UI is authored directly in Lua draw functions.

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

Lib widgets cover common controls. Use raw ImGui for custom structure and layout.

## Quick Content

Framework Quick Setup reads:
- coordinator `renderQuickSetup(ctx)`
- module `DrawQuickContent(ui, session)`

`DrawQuickContent` is a Framework Quick Setup hook.

## Runtime Hooks

Modules that register ModUtil path hooks should do that through `lib.hooks.*`.

Typical shape:

```lua
function internal.RegisterHooks()
    lib.hooks.Wrap(internal, "GetEligibleLootNames", function(base, ...)
        local result = base(...)
        -- inspect or transform the wrapped call here
        return result
    end)
end

public.host = lib.createModuleHost({
    definition = definition,
    store = store,
    session = session,
    hookOwner = internal,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
```

Rules:
- use a persistent owner table such as the module `internal`
- declare hook sites inside `RegisterHooks()`
- let `createModuleHost(...)` own the registration pass
- use the keyed overload when one owner needs several hooks on the same path

## Mutation Lifecycle

Use `affectsRunData = true` only when the module actually mutates live run data.

Supported lifecycle shapes:
- patch only: `patchPlan(plan, store)`
- manual only: `apply(store)` + `revert(store)`
- hybrid: both

Patch-plan example:

```lua
local definition = lib.prepareDefinition(internal, {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    affectsRunData = true,
    storage = internal.BuildStorage(),
    patchPlan = function(plan, store)
    plan:set(SomeTable, "Enabled", true)
    plan:appendUnique(SomeTable, "Pool", "NewEntry")
    end,
})
```

Lib helpers:
- `lib.lifecycle.setEnabled(def, store, enabled)`
- `lib.lifecycle.applyMutation(def, store)`
- `lib.lifecycle.revertMutation(def, store)`
- `lib.lifecycle.reapplyMutation(def, store)`

## Coordinated Modules

Framework-hosted modules should export:
- `public.host`

Framework discovery requires:
- a live host registered by `lib.createModuleHost(...)`
- `host.getIdentity()`
- `host.getMeta()`
- a prepared definition with `storage`

Framework behavior:
- each coordinated module gets its own top-level tab
- `host.drawTab(...)` is the normal rendering contract
- `host.drawQuickContent(...)` participates only in Quick Setup

## Standalone Modules

For non-framework hosting, use:

```lua
local definition = lib.prepareDefinition(internal, {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    storage = internal.BuildStorage(),
})

local store, session = lib.createStore(config, definition)

public.host = lib.createModuleHost({
    definition = definition,
    store = store,
    session = session,
    hookOwner = internal,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})

local runtime = lib.standaloneHost(public.host)

local function registerGui()
    rom.gui.add_imgui(runtime.renderWindow)
    rom.gui.add_to_menu_bar(runtime.addMenuBar)
end
```

Notes:
- `lib.standaloneHost(...)` suppresses its window/menu when the module is coordinated
- `lib.standaloneHost(...)` applies startup lifecycle state for non-coordinated modules
- the standalone window includes built-in:
  - `Enabled`
  - `Debug Mode`
  - `Resync Session`
- the standalone window renders `DrawTab`; Framework Quick Setup renders `DrawQuickContent`

## Complete Example

This is a minimal end-to-end module shape showing:
- `main.lua`
- storage
- `DrawTab`
- optional `DrawQuickContent`
- standalone wiring

```lua
local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN
game = rom.game
modutil = mods["SGG_Modding-ModUtil"]
local chalk = mods["SGG_Modding-Chalk"]
local reload = mods["SGG_Modding-ReLoad"]
---@type AdamantModpackLib
lib = mods["adamant-ModpackLib"]

local dataDefaults = import("config.lua")
local config = chalk.auto("config.lua")

local PACK_ID = "example-pack"
---@class ExampleModuleInternal
---@field store ManagedStore|nil
---@field standaloneUi StandaloneRuntime|nil
---@field RegisterHooks fun()|nil
---@field DrawTab fun(imgui: table, session: AuthorSession)|nil
---@field DrawQuickContent fun(imgui: table, session: AuthorSession)|nil
ExampleModule_Internal = ExampleModule_Internal or {}
---@type ExampleModuleInternal
local internal = ExampleModule_Internal

public.host = nil
local store = nil
local session = nil
internal.standaloneUi = nil

local function init()
    import_as_fallback(rom.game)

    local definition = lib.prepareDefinition(internal, dataDefaults, {
        modpack = PACK_ID,
        id = "ExampleModule",
        name = "Example Module",
        shortName = "Example",
        tooltip = "Demonstrates the Lib module contract.",
        affectsRunData = false,
        storage = {
            { type = "bool", alias = "FeatureEnabled", configKey = "FeatureEnabled", default = false },
            { type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 32 },
            { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
            {
                type = "packedInt",
                alias = "PackedFlags",
                configKey = "PackedFlags",
                default = 0,
                bits = {
                    { alias = "PackedFlags_Attack", label = "Attack", type = "bool", offset = 0, width = 1, default = false },
                    { alias = "PackedFlags_Special", label = "Special", type = "bool", offset = 1, width = 1, default = false },
                },
            },
        },
    })

    store, session = lib.createStore(config, definition)
    internal.store = store

    public.host = lib.createModuleHost({
        definition = definition,
        store = store,
        session = session,
        hookOwner = internal,
        registerHooks = internal.RegisterHooks,
        drawTab = internal.DrawTab,
        drawQuickContent = internal.DrawQuickContent,
    })

    internal.standaloneUi = lib.standaloneHost(public.host)
end

function internal.DrawTab(ui, session)
    lib.widgets.checkbox(ui, session, "FeatureEnabled", {
        label = "Enable Feature",
        tooltip = "Turns the feature logic on for this module.",
    })

    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos", "Custom" },
        controlWidth = 180,
    })

    lib.widgets.inputText(ui, session, "FilterText", {
        label = "Filter",
        controlWidth = 180,
    })

    ui.Separator()
    lib.widgets.text(ui, "Packed Flags")
    lib.widgets.packedCheckboxList(ui, session, "PackedFlags", store, {
        optionsPerLine = 2,
    })
end

function internal.DrawQuickContent(ui, session)
    lib.widgets.dropdown(ui, session, "Mode", {
        label = "Mode",
        values = { "Vanilla", "Chaos", "Custom" },
        controlWidth = 140,
    })
end

function internal.RegisterHooks()
    -- Optional: register runtime hooks here through lib.hooks.*
end

local loader = reload.auto_single()

local function registerGui()
    rom.gui.add_imgui(function()
        if internal.standaloneUi and internal.standaloneUi.renderWindow then
            internal.standaloneUi.renderWindow()
        end
    end)

    rom.gui.add_to_menu_bar(function()
        if internal.standaloneUi and internal.standaloneUi.addMenuBar then
            internal.standaloneUi.addMenuBar()
        end
    end)
end

modutil.once_loaded.game(function()
    loader.load(registerGui, init)
end)
```

Notes on the example:
- `config` and `reload` stay local to `main.lua`
- `store` is recreated on every reload
- `session` stays local to `main.lua`; draw callbacks receive the restricted author session through `public.host`
- `lib.createModuleHost(...)` owns the live coordinated host registration
- `public.host` remains the normal exported reference used by standalone hosting and local module code
- `internal.RegisterHooks()` is the normal place for `lib.hooks.*` declarations
- `DrawTab` uses raw ImGui for structure and `lib.widgets.*` for controls
- `DrawQuickContent` is optional
- packed widgets need the module `store`
