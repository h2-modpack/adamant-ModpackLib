# Quick Setup

This document covers the Lib modpack Quick Setup surface.

Use [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md) as the entrypoint for
coordinator wiring.

## What Quick Setup Is

Quick Setup is the top-level modpack panel for compact, high-frequency controls.

Typical content:

- a small coordinator-owned control surface
- a small per-module quick surface

## Render Order

Quick Setup renders in this order:

1. built-in profile quick selector
2. coordinator-owned content from `opts.drawPackQuickContent(ctx)`
3. each discovered enabled module with quick content support

This happens inside `src/core/modpack/ui/quick_setup.lua`.

## Coordinator Quick Content

Coordinators may inject their own quick content through:

```lua
local function drawPackQuickContent(ctx)
    ...
end

Modpack.createPack(PACK_ID, config, #config.Profiles, defaultProfiles, {
    drawPackQuickContent = drawPackQuickContent,
})
```

`ctx` fields:

- `ui`
- `colors`
- `theme`
- `getModulesStatus(moduleIds)`
- `setModulesEnabled(moduleIds, enabled)`

Keep coordinator quick content coordinator-scoped. Module controls belong in
that module's draw surface.

The built-in profile selector always renders before coordinator content. It
lets users load saved profiles from the main Quick Setup tab without opening
the Profiles tab.

## Module Quick Content

Modules participate in Quick Setup through:

```lua
local data = import("mods/data.lua")
local logic = import("mods/logic.lua", nil, {
    data = data,
})
local ui = import("mods/ui.lua", nil, {
    data = data,
})

local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
})
if not module then
    return
end

module.data.define(data.buildStorage())
module.ui.tab(ui.drawTab)
module.ui.quickContent(ui.drawQuickContent)
logic.register(module)

local ok = module.activate()
if not ok then
    return
end
```

Modpack behavior:

- only enabled modules render quick content
- the modpack UI snapshots live modules at the start of the UI operation
- module quick content is called through that snapshot live module's
  `drawQuickContent()`
- the module-authored quick callback receives `(host, ui)`
- `ui.draw` contains `imgui`, `widgets`, `nav`, and `control`
- `ui.data` owns staged UI state
- `ui.status` reads runtime-published status
- `ui.actions` owns post-draw intent
- `ui.controls` and `ui.shared` expose control and shared-data surfaces
- if the module dirty-stages persisted state during quick content, the modpack
  UI commits it after draw

## What Belongs In Quick Setup

Good fits:

- one or two high-frequency controls
- fast run-setup toggles
- controls users need without opening the full module tab

Better suited for full module tabs:

- the full module UI copied into Quick Setup
- large audit/configuration surfaces
- controls that only make sense in deep configuration

## Related Docs

- [COORDINATOR_GUIDE.md](COORDINATOR_GUIDE.md)
- [HASH_PROFILE_ABI.md](HASH_PROFILE_ABI.md)
