# Migrating Draw Callbacks To `host, ui`

This note covers the draw-callback API migration from older live draw/session
surfaces to the current `drawTab(host, ui)` shape.

## What Changed

Old draw callbacks commonly received raw ImGui/session surfaces:

```lua
function ui.drawTab(imgui, session, host)
end

function ui.drawQuickContent(imgui, session, host)
end
```

Intermediate versions split the draw pass into separate `draw`, `state`, and
`actions` arguments:

```lua
function ui.drawTab(draw, state, actions)
end
```

The current target callback receives a safe host projection plus one UI object:

```lua
function ui.drawTab(host, ui)
end

function ui.drawQuickContent(host, ui)
end
```

`ui` contains the draw-time surfaces:

- `ui.draw`: raw ImGui plus widgets, navigation, and control rendering
- `ui.data`: staged UI storage and read-only runtime-owned data
- `ui.actions`: draw-time action and shared-event intent staging
- `ui.controls`: UI control refs
- `ui.shared`: shared-data reads and owner writes

## Module Declaration

Module creation now returns a declaration object. Capabilities are attached
before activation:

```lua
local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
})
if not module then return end

module.data.define(data.buildStorage())
module.actions.define(actions.build())
module.ui.tab(ui.drawTab)
module.ui.quickContent(ui.drawQuickContent)
module.activate()
```

Do not pass `storage`, `drawTab`, or `drawQuickContent` through
`createModule(...)` options.

## Draw Code

Before:

```lua
function ui.drawTab(imgui, session, host)
    lib.widgets.checkbox(imgui, session, "FeatureEnabled", {
        label = "Enable Feature",
    })
end
```

After:

```lua
function ui.drawTab(host, ui)
    local draw = ui.draw
    local state = ui.data

    draw.widgets.checkbox(state.get("FeatureEnabled"), {
        label = "Enable Feature",
    })

    draw.widgets.dropdown(state.get("Mode"), {
        label = "Mode",
        values = { "Default", "Custom" },
    })
end
```

Pass `ui` or targeted pieces of it to inner draw files:

```lua
components.draw(host, ui)
```

or:

```lua
components.draw(ui.draw, ui.data, ui.actions)
```

Choose the narrower form when it makes ownership clearer.

## Widget Storage Fields

Widgets render resolved storage fields. Root widgets use refs from `ui.data`:

```lua
draw.widgets.checkbox(ui.data.get("FeatureEnabled"), opts)
draw.widgets.dropdown(ui.data.get("Mode"), opts)
draw.widgets.packedCheckboxList(ui.data.get("GodPool"), opts)
```

Table-backed widgets use a `StorageField` produced by the table API:

```lua
local bans = ui.data.get("ConfigurableBanPools"):get(index, "BanPool")

draw.widgets.packedCheckboxList(bans, opts)
draw.widgets.packedDropdown(bans, opts)
local selected = draw.widgets.getPackedChoiceAlias(bans, opts)
```

`StorageField` is the resolved leaf target for widgets. Storage and table APIs
own traversal; widgets own rendering.

## Actions

Draw actions are now under `ui.actions`:

```lua
ui.actions.trigger("Reset")

draw.widgets.button("Reset", {
    action = ui.actions.get("Reset"),
})
```

`ui.actions.emit(...)` queues shared events for commit-time delivery.

## Rules

- Use `module.ui.tab(...)` and `module.ui.quickContent(...)` before activation.
- Use `ui.draw.widgets.*` for Lib widgets.
- Use `ui.draw.nav.*` for Lib navigation helpers.
- Use `ui.draw.imgui` for raw ImGui layout calls.
- Use `ui.data` for staged UI storage.
- Use `ui.data.runtimeOwned` for UI reads of runtime-owned storage.
- Use `ui.actions` for transient draw intent.
- Keep static module data, catalogs, and services in normal module binding.
- Do not store draw mutation objects for runtime use.
