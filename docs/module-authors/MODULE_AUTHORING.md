# Module Authoring

This guide describes the supported module contract in Lib:
- namespaced public API
- managed storage and explicit draw/runtime data surfaces
- immediate-mode widgets
- direct draw-function authoring through `drawTab(draw, state, actions, services)`

## Lib Surface

Common module author surfaces:
- `lib.createModule(...)`
- `host.integrations.*`
- `host.cache.*`

Fallback UI modules also use:
- `host.fallbackUi.attachGuiOnce(...)`

Use runtime behavior APIs only when the module owns that kind of behavior:
- `host.hooks.*`
- `host.overlays.*`
- `host.mutation.*`

Pack, Framework, migration, and advanced storage plumbing may also use:
- `lib.createFrameworkRuntime(...)`

Use the namespaced API directly. Normal module code should keep the author host
returned by `lib.createModule(...)`.

## Capability Guides

Use focused capability guides for feature-level authoring details:

- [capabilities/MANAGED_STATE.md](capabilities/MANAGED_STATE.md)
- [capabilities/WIDGETS.md](capabilities/WIDGETS.md)
- [capabilities/HOOKS.md](capabilities/HOOKS.md)
- [capabilities/MUTATIONS.md](capabilities/MUTATIONS.md)
- [capabilities/OVERLAYS.md](capabilities/OVERLAYS.md)
- [capabilities/INTEGRATIONS.md](capabilities/INTEGRATIONS.md)
- [capabilities/CACHE.md](capabilities/CACHE.md)

## Basic Module Shape

Typical coordinated module:

```lua
local function drawTab(draw, state, actions, services)
    draw.widgets.checkbox(state.get("EnabledFlag"), {
        label = "Enabled",
    })

    draw.widgets.dropdown(state.get("Mode"), {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 180,
    })
end

local function drawQuickContent(draw, state, actions, services)
    draw.widgets.dropdown(state.get("Mode"), {
        label = "Mode",
        values = { "Vanilla", "Chaos" },
        controlWidth = 140,
    })
end

local function registerHooks(host, store)
    host.hooks.wrap("SomeGameFunction", function(base, ...)
        return base(...)
    end)
end

local host, store = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
    tooltip = "What this module does.",
    storage = {
        { type = "bool", alias = "EnabledFlag", default = false },
        { type = "string", alias = "Mode", default = "Vanilla", maxLen = 32 },
        { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
    },
    drawTab = drawTab,
    drawQuickContent = drawQuickContent,
})
if not host then return end

registerHooks(host, store)
host.activate()
```

This example assumes coordinated/framework hosting.
For fallback-only modules, `drawQuickContent` is optional and only matters if some external host uses it.
If the module does not register runtime hooks, skip the hook declaration call.

`lib.createModule(...)` is the supported module construction path.
For `createModule(...)`, `pluginGuid` is the single stable lifecycle identity.
Lib owns the internal per-plugin runtime state for structural hot-reload
tracking, hook refresh ownership, overlays, integrations, mutation runtime, and
live-host lookup.
Call `host.activate()` after construction. That activation step publishes the
live host, installs declared integrations, registers hooks and overlays, and
syncs initial runtime behavior.
`lib.createModule(...)` returns `nil, nil, err` when construction fails, so an
invalid module can be logged and skipped rather than stopping sibling modules.
Construction stays separate from activation: `createModule(...)` wraps only
construction, and `host.activate()` wraps only activation.
Declare hooks and retained overlays on the host after construction and before
`host.activate()`. These declarations are scoped to the module's
`pluginGuid`, so helper files do not need to know or manage an owner token.
Modules that use shared runtime helper files should pass the needed store or
narrower access/read closures into those helpers:

```lua
local function registerHooks(host, store)
    local featureEnabled = store.get("FeatureEnabled")

    host.hooks.wrap("SomeGameFunction", function(base, ...)
        if not host.isEnabled() then
            return base(...)
        end
        if featureEnabled:read() then
            -- Runtime behavior reads persisted state through store.
        end
        return base(...)
    end)
end
```

Callback argument order follows a stable convention:
- work surface first when a callback has one, such as `draw` for draw callbacks or `plan` for patch mutation callbacks
- state/context handles next, using `state`, `actions`, and `services` for draw and `host` for runtime/module context
- `store` last when persisted runtime values are needed

Examples: `drawTab(draw, state, actions, services)`, local
`registerHooks(host, store)` helpers, local overlay declaration helpers that
call `host.overlays.*`, and
`host.mutation.patch(function(plan, host, store) ... end)`.

## Definition Rules

Meaningful prepared definition fields:
- `id` (required stable module identity)
- `name` (required display name)
- `modpack`
- `shortName`
- `tooltip`
- `storage`
- `hashGroupPlan`

Lib rejects any definition key outside the list above so typos and stale author code fail at module load.

All modules must declare:
- `id`
- `name`

Coordinated modules also declare:
- `modpack`

Modules with no custom settings may omit `storage`; Lib injects built-in
`Enabled` and `DebugMode` aliases during preparation.

Framework behavior:
- every coordinated module gets its own tab
- `shortName` is used as the shorter tab label when present

## Store and State Rules

For the focused state guide, read [capabilities/MANAGED_STATE.md](capabilities/MANAGED_STATE.md).

Module construction creates two author-facing state handles:

- draw code receives `state` for staged UI reads and writes
- runtime callbacks receive `store` for committed gameplay reads

Raw Chalk config should stay local to `main.lua`. Host/framework plumbing owns
commit, reload, hash/profile import, and config flush behavior.

Storage roots live on `definition.storage`. Normal roots persist and hash by
default. Use `persist = false, hash = false` for transient staged-only UI
state. Runtime markers should prefer `host.cache.persistent.*`.

Lib injects `Enabled` and `DebugMode` into every prepared definition. Do not
declare them in module storage or `config.lua`.

Use [capabilities/MANAGED_STATE.md](capabilities/MANAGED_STATE.md) for storage
axes, table roots, packed roots, draw actions, and commit observers.

## Immediate-Mode UI

For the focused widget and navigation guide, read [capabilities/WIDGETS.md](capabilities/WIDGETS.md).

Module UI is authored directly in Lua draw functions.

Typical patterns:
- `draw.widgets.checkbox(...)`
- `draw.widgets.dropdown(...)`
- `draw.widgets.radio(...)`
- `draw.widgets.stepper(...)`
- `draw.widgets.packedCheckboxList(...)`
- `draw.nav.verticalTabs(...)`

Use raw ImGui layout as needed:
- `ui.Text(...)`
- `ui.SameLine()`
- `ui.BeginTabBar(...)`
- `ui.BeginChild(...)`

Lib widgets cover common controls. Use raw ImGui for custom structure and layout.

## Quick Content

Framework Quick Setup reads:
- coordinator `drawPackQuickContent(ctx)`
- module `drawQuickContent(draw, state, actions, services)`

`drawQuickContent` is a Framework Quick Setup hook.

## Runtime Hooks

For the focused hooks guide, read [capabilities/HOOKS.md](capabilities/HOOKS.md).

Modules that register ModUtil path hooks should declare them inside
local hook helpers by calling `host.hooks.*` before `host.activate()`.
Declarations are scoped to the activating module's `pluginGuid`, so hook files
do not need to manage owner tokens.

Use keyed overloads when one module needs several hooks on the same path.

## Mutation Lifecycle

For the focused mutation guide, read [capabilities/MUTATIONS.md](capabilities/MUTATIONS.md).

Call `host.mutation.patch(function(plan, host, store) ... end)` before activation
only when the module mutates live run data. The callback describes the mutation
plan for an enabled module. Lib owns apply/revert, enable/disable, settings
commit, profile load, hot reload, and rollback behavior through the live host.

Patch plans are the only supported run-data mutation API. If a real mutation
cannot be expressed by the current plan surface, add a first-class patch-plan
operation instead of bypassing the tracked lifecycle.

## Coordinated Modules

Framework discovery requires:
- a live host registered by `host.activate()`
- `host.getHostId()`
- `host.getModuleId()`
- `host.getPackId()`
- `host.getMeta()`
- a prepared definition and Lib-created storage surface

Framework resolves live `ModuleHost` values through its Framework runtime. Module
code normally uses the author host returned by `lib.createModule(...)`.

Framework behavior:
- each coordinated module gets its own top-level tab
- `ModuleHost.drawTab()` is the normal rendering contract
- `ModuleHost.drawQuickContent()` participates only in Quick Setup
- authored draw callbacks receive `drawTab(draw, state, actions, services)` and
  `drawQuickContent(draw, state, actions, services)`

## Fallback UI Modules

For non-framework hosting, use:

```lua
local PLUGIN_GUID = _PLUGIN.guid
local data = import("mods/data.lua")
local logic = import("mods/logic.lua").bind(data)
local ui = import("mods/ui.lua").bind(data)

local host, store = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = "ExampleModule",
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
    drawQuickContent = ui.drawQuickContent,
})
host.fallbackUi.attachGuiOnce(function(fallbackUi)
    rom.gui.add_imgui(fallbackUi.renderWindow)
    rom.gui.add_to_menu_bar(fallbackUi.addMenuBar)
end)
logic.registerHooks(host, store)
host.activate()
```

Notes:
- fallback UI suppresses its window/menu when the module is coordinated
- `host.activate()` syncs runtime mutation state for both coordinated and fallback UI modules
- `host.fallbackUi.attachGuiOnce(...)` keeps module-owned ROM GUI callsites stable while Lib owns the current runtime pointer
- the fallback UI window includes built-in:
  - `Enabled`
  - `Debug Mode`
  - `Resync State`
- the fallback UI window renders `drawTab`; Framework Quick Setup renders `drawQuickContent`

## Complete Example

This is a minimal end-to-end module shape showing:
- `main.lua`
- storage
- `drawTab`
- optional `drawQuickContent`
- fallback UI wiring

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

local config = chalk.auto("config.lua")

local PACK_ID = "example-pack"
local PLUGIN_GUID = _PLUGIN.guid

local drawTab
local drawQuickContent
local registerHooks

local function init()
    import_as_fallback(rom.game)

    local host, store = lib.createModule({
        pluginGuid = PLUGIN_GUID,
        config = config,
        modpack = PACK_ID,
        id = "ExampleModule",
        name = "Example Module",
        shortName = "Example",
        tooltip = "Demonstrates the Lib module contract.",
        storage = {
            { type = "bool", alias = "FeatureEnabled", default = false },
            { type = "string", alias = "Mode", default = "Vanilla", maxLen = 32 },
            { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
            {
                type = "packedInt",
                alias = "PackedFlags",
                default = 0,
                bits = {
                    { alias = "PackedFlags_Attack", label = "Attack", type = "bool", offset = 0, width = 1, default = false },
                    { alias = "PackedFlags_Special", label = "Special", type = "bool", offset = 1, width = 1, default = false },
                },
            },
        },
        drawTab = drawTab,
        drawQuickContent = drawQuickContent,
    })
    host.fallbackUi.attachGuiOnce(function(fallbackUi)
        rom.gui.add_imgui(fallbackUi.renderWindow)
        rom.gui.add_to_menu_bar(fallbackUi.addMenuBar)
    end)
    registerHooks(host, store)
    host.activate()
end

function drawTab(draw, state, actions, services)
    draw.widgets.checkbox(state.get("FeatureEnabled"), {
        label = "Enable Feature",
        tooltip = "Turns the feature logic on for this module.",
    })

    draw.widgets.dropdown(state.get("Mode"), {
        label = "Mode",
        values = { "Vanilla", "Chaos", "Custom" },
        controlWidth = 180,
    })

    draw.widgets.inputText(state.get("FilterText"), {
        label = "Filter",
        controlWidth = 180,
    })

    draw.imgui.Separator()
    draw.widgets.text("Packed Flags")
    draw.widgets.packedCheckboxList(state.get("PackedFlags"), {
        optionsPerLine = 2,
    })
end

function drawQuickContent(draw, state, actions, services)
    draw.widgets.dropdown(state.get("Mode"), {
        label = "Mode",
        values = { "Vanilla", "Chaos", "Custom" },
        controlWidth = 140,
    })
end

function registerHooks(host, store)
    local featureEnabled = store.get("FeatureEnabled")

    host.hooks.wrap("SomeGameFunction", function(base, ...)
        if host.isEnabled() and featureEnabled:read() then
            -- Optional runtime behavior goes here.
        end
        return base(...)
    end)
end

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(function() end, init)
end)
```

Notes on the example:
- `config` and `reload` stay local to `main.lua`
- `store` is passed to runtime hooks and mutation callbacks
- draw callbacks receive staged UI state through the `state` argument
- `host.activate()` owns live coordinated host registration
- `host.hooks.*` declarations happen before `host.activate()`
- `host.overlays.*` declarations happen before `host.activate()`
- `host.fallbackUi.attachGuiOnce(...)` keeps ROM GUI registration in module context without stacking across reloads
- `drawTab` uses raw ImGui for structure and `draw.widgets.*` / `draw.nav.*` for Lib draw helpers
- `drawQuickContent` is optional
- packed widgets use `StorageField` values produced by the draw `state`
  argument
