# Getting Started

This guide is for first-time module authors using adamant ModpackLib and
ModpackFramework.

For exact API types, use [API.md](../../API.md). For the fuller contract, use
[MODULE_AUTHORING.md](MODULE_AUTHORING.md).

## Start From The Tools

For the full new-pack walkthrough, start with the
[`ModpackBootstrap` Getting Started guide](https://github.com/h2-modpack/ModpackBootstrap/blob/main/docs/GETTING_STARTED.md).
This guide focuses on the Lib module-authoring contract after a pack workspace
exists.

For a new pack, use
[`ModpackBootstrap`](https://github.com/h2-modpack/ModpackBootstrap). It creates
the shell repo, coordinator package, shared Lib/Framework submodules, and
`ModpackTools/`.

For a new module in an existing pack, run this from the shell repo root:

```bash
python ModpackTools/new_module/create.py --package-id My_Module --title "My Module"
```

That command scaffolds from
[`ModpackModuleTemplate`](https://github.com/h2-modpack/ModpackModuleTemplate),
registers the module under `Submodules/`, and syncs coordinator dependencies.

## Core Model

A module is built from four pieces:

- `main.lua`: imports dependencies, creates the Lib module, declares
  capabilities, and activates.
- `data.lua`: owns storage schemas, actions, cache/control declarations, and
  static option data.
- `ui.lua`: owns immediate-mode draw functions.
- `logic.lua`: owns hooks, mutations, and runtime behavior.

The important phase rule:

- draw code uses `ui.data`, `ui.draw`, `ui.actions`, and optional `ui.controls`
- runtime code uses the `runtime` callback argument

## Minimal Module

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
local MODULE_ID = "ExampleModule"
local PLUGIN_GUID = _PLUGIN.guid

local function drawTab(host, ui)
    ui.draw.widgets.checkbox(ui.data.get("FeatureEnabled"), {
        label = "Enable Feature",
    })
end

local function init()
    import_as_fallback(rom.game)

    local module, err = lib.createModule({
        pluginGuid = PLUGIN_GUID,
        config = config,
        modpack = PACK_ID,
        id = MODULE_ID,
        name = "Example Module",
    })
    if not module then return end

    module.data.define({
        { type = "bool", alias = "FeatureEnabled", default = false },
    })
    module.ui.tab(drawTab)
    module.activate()
end

local loader = reload.auto_single()

modutil.once_loaded.game(function()
    loader.load(nil, init)
end)
```

## Declaring Storage

Storage is declared after creation and before activation:

```lua
module.data.define({
    { type = "bool", alias = "FeatureEnabled", default = false },
    { type = "string", alias = "Mode", default = "Vanilla", maxLen = 32 },
    { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
})
```

Rules:

- aliases are direct flat storage identifiers
- normal values persist and hash by default
- transient UI values use `persist = false, hash = false`
- runtime-owned markers use `mode = "runtime"`
- `Enabled` and `DebugMode` are reserved Lib aliases

## Drawing UI

Draw functions receive `(host, ui)`.

```lua
local MODE_VALUES = { "Vanilla", "Chaos" }

local function drawTab(host, ui)
    local draw = ui.draw
    local state = ui.data

    draw.widgets.dropdown(state.get("Mode"), {
        label = "Mode",
        values = MODE_VALUES,
        controlWidth = 180,
    })
end
```

`ui.draw`, `ui.data`, `ui.actions`, and `ui.controls` are draw-callback
objects. Reads are phase-neutral, but staged writes, action staging, and other
mutations remain draw-scoped.

## Runtime Logic

Runtime declarations happen before activation:

```lua
module.hooks.wrap("SomeGameFunction", function(host, runtime, base, ...)
    local result = base(...)
    if host.isEnabled() and runtime.data.read("FeatureEnabled") then
        -- Gameplay behavior here.
    end
    return result
end)
```

Mutations use the same callback language:

```lua
module.mutation.patch(function(host, runtime, plan)
    if runtime.data.read("FeatureEnabled") then
        plan:set(SomeGameTable, "SomeKey", true)
    end
end)
```

## Fallback UI

Fallback UI modules attach stable ROM GUI callbacks before activation:

```lua
module.fallbackUi.attachGuiOnce(function(fallbackUi)
    rom.gui.add_imgui(fallbackUi.renderWindow)
    rom.gui.add_to_menu_bar(fallbackUi.addMenuBar)
end)
```

## Next Reads

1. [MODULE_AUTHORING.md](MODULE_AUTHORING.md)
2. [capabilities/README.md](capabilities/README.md)
3. [API.md](../../API.md)
