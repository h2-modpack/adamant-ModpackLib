# Migrating Draw Callbacks To Draw/State/Actions/Services

This note covers the draw-callback API migration from earlier live draw
surfaces to four render-scoped draw-phase objects.

## What Changed

Old draw callbacks receive separate live surfaces:

```lua
function ui.drawTab(imgui, session, host)
end

function ui.drawQuickContent(imgui, session, host)
end
```

Intermediate draw callbacks received one render-scoped context:

```lua
function ui.drawTab(draw)
end

function ui.drawQuickContent(draw)
end
```

The current target callback shape separates rendering, staged state, and
transient actions:

```lua
function ui.drawTab(draw, state, actions)
end

function ui.drawQuickContent(draw, state, actions)
end
```

Module creation stays grep-visible and does not use a construction-time draw
factory:

```lua
local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
    storage = storage,
    drawTab = ui.drawTab,
    drawQuickContent = ui.drawQuickContent,
})
```

## Draw Context Shape

Lib creates the context at the host draw boundary for each render call.

```lua
---@class AdamantModpackLib.DrawContext
---@field imgui table
---@field widgets AdamantModpackLib.DrawWidgets
---@field nav AdamantModpackLib.DrawNav
```

`draw.widgets` is the draw widget surface. Widget calls no longer repeat
`imgui`, while value widgets receive explicit storage refs from `state`:

```lua
function ui.drawTab(draw, state, actions)
    draw.widgets.dropdown(state.get("Mode"), {
        label = "Mode",
        values = { "Default", "Custom" },
    })

    draw.widgets.checkbox(state.get("FeatureEnabled"), {
        label = "Enable Feature",
    })

    draw.imgui.SameLine()
end
```

`draw.nav` is the draw navigation surface. Navigation calls no longer repeat
`imgui`:

```lua
activeKey = draw.nav.verticalTabs({
    id = "ModuleTabs",
    activeKey = activeKey,
    tabs = tabs,
})
```

## Why

The old callback shape kept module entrypoints simple, but it pushed the same
three live draw dependencies through every helper and subfile:

```lua
lib.widgets.checkbox(imgui, session, "FeatureEnabled", opts)
subPanel.draw(imgui, session, host)
```

The context shape keeps the entrypoint explicit while reducing module-side
plumbing:

```lua
subPanel.draw(draw)
draw.widgets.checkbox(state.get("FeatureEnabled"), opts)
```

This intentionally differs from a `createDraw(...)` factory. `imgui`, staged
state, and actions are live draw-phase surfaces, not static module dependencies.
They should enter the module at draw time, not be captured during module
construction.

## Related CreateModule Boundary Cleanup

This migration is expected to pair with flattening the author-facing
`lib.createModule(...)` options. The old nested `definition = { ... }` shape is
a remnant of the former explicit `prepareDefinition(...) -> createStore(...) ->
createHost(...)` construction path. If `createModule(...)` is the canonical
module-author API, it should accept definition fields directly and build the
pure prepared-definition input internally.

Target author shape:

```lua
local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,

    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
    shortName = "Example",
    tooltip = "...",
    storage = storage,
    drawTab = ui.drawTab,
    drawQuickContent = ui.drawQuickContent,
})
```

`hasQuickContent` should stay internal. Module authors should not provide it as
public config. `createModule(...)` should derive it from the callback surface
and pass it to `prepareDefinition(...)` as structural metadata:

```lua
local preparedDefinition = managedModule.prepareDefinition(
    GetStructuralBaseline(opts.pluginGuid),
    definitionInput,
    {
        hasQuickContent = type(opts.drawQuickContent) == "function",
    }
)
```

That keeps the fingerprint behavior unchanged while making the structure
cleaner:

- `createModule(...)` owns public option shape and derives construction inputs.
- `prepareDefinition(...)` owns validation, fingerprinting, and prepared
  definition metadata.
- `drawQuickContent` remains an optional draw callback.
- `hasQuickContent` remains internal structural surface data, not author-owned
  module data.

## Widget Storage Fields

The draw-context widget surface uses storage fields, not session-like table
handles.

Root widgets use refs from the draw `state` object:

```lua
draw.widgets.checkbox(state.get("FeatureEnabled"), opts)
draw.widgets.dropdown(state.get("Mode"), opts)
draw.widgets.packedCheckboxList(state.get("GodPool"), opts)
```

Table-backed widgets use a `StorageField` produced by the table API:

```lua
local bans = state.get("ConfigurableBanPools"):get(index, "BanPool")

draw.widgets.packedCheckboxList(bans, opts)
draw.widgets.packedDropdown(bans, opts)
local selected = draw.widgets.getPackedChoiceAlias(bans, opts)
```

`StorageField` is the resolved leaf value target for widgets. It is not a path,
not a scoped alias string, and not a row handle pretending to be a session.
Storage and table APIs are responsible for traversal and validation; widgets
are leaf renderers that read schema/value data from the final field target.
Fields expose `field:alias()` for storage-schema identity and
`field:controlId()` for ImGui/control identity. Root control ids equal their
alias; table-cell control ids are cached by the table owner and include the
table alias, positional row index, and cell alias.

Bound widgets accept only these target forms:

- `StorageField`: explicit resolved storage field from
  `state.get(alias)` or `state.get(tableAlias):get(rowIndex, cellAlias)`.

They do not accept arbitrary table-shaped targets, parse scoped path strings,
root alias strings, or expose a public rebinding API. Future path support can
live in storage APIs and resolve to `StorageField` before widgets see it.

Implementation audit checklist:

- Add `state.get(alias)` for explicit root storage fields.
- Add `tableHandle:get(rowIndex, alias)` for table row storage fields.
- Route bound widget targets through one `StorageField` normalization path.
- Keep widget binding scoped to the current `imgui` only.
- Replace loose `(handle, alias)` widget call sites with named domain helpers
  that return `StorageField` values.
- Root widget calls should pass `state.get(alias)` refs.

## Migration Steps

1. Change draw callback signatures.

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
function ui.drawTab(draw, state, actions)
    draw.widgets.checkbox(state.get("FeatureEnabled"), {
        label = "Enable Feature",
    })
end
```

2. Pass the draw-phase objects to inner UI files.

Before:

```lua
components.draw(imgui, session, host)
```

After:

```lua
components.draw(draw, state, actions)
```

3. Keep static module dependencies in normal module binding.

```lua
local ui = {}
local catalog
local components

function ui.bind(deps)
    catalog = deps.catalog
    components = import("mods/ui/components.lua").bind({
        catalog = catalog,
    })
    return ui
end
```

`draw` is for render-scoped live surfaces only. Do not store it across frames,
hot reloads, or module activation boundaries.

## Rules

- Keep `drawTab = ui.drawTab` and `drawQuickContent = ui.drawQuickContent` in
  module creation.
- Do not introduce `createDraw(...)` for normal module authoring.
- Use `draw.widgets.*` for Lib widgets that bind to `imgui` and staged `state`.
- Use `draw.nav.*` for Lib navigation helpers that bind to `imgui`.
- Use `draw.imgui` for raw ImGui layout calls.
- Use `draw.log(...)` and `draw.logIf(...)` for draw-safe module logging.
- Use `state` for direct staged-state access.
- Use `actions` for transient draw intent.
- Keep static module data, catalogs, and action services in `ui.bind(...)`.
- Framework `drawPackQuickContent(ctx)` still uses its own coordinator/framework
  context object and is intentionally not part of this draw-object rename. Audit
  it separately before changing that callback shape.
