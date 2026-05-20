# Migrating Draw Callbacks To Draw Context

This note covers the planned draw-callback API change from three live draw
arguments to one render-scoped context object.

## What Changed

Old draw callbacks receive separate live surfaces:

```lua
function ui.drawTab(imgui, session, host)
end

function ui.drawQuickContent(imgui, session, host)
end
```

New draw callbacks receive one render-scoped context:

```lua
function ui.drawTab(draw)
end

function ui.drawQuickContent(draw)
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
---@field session AdamantModpackLib.AuthorSession
---@field services AdamantModpackLib.DrawServices
---@field widgets AdamantModpackLib.BoundWidgets
---@field nav AdamantModpackLib.BoundNav
```

`draw.widgets` is the bound widget surface. Widget calls no longer repeat
`imgui` and `session`:

```lua
function ui.drawTab(draw)
    draw.widgets.dropdown("Mode", {
        label = "Mode",
        values = { "Default", "Custom" },
    })

    draw.widgets.checkbox("FeatureEnabled", {
        label = "Enable Feature",
    })

    draw.imgui.SameLine()
end
```

`draw.nav` is the bound navigation surface. Navigation calls no longer repeat
`imgui` or `session`:

```lua
activeKey = draw.nav.verticalTabs({
    id = "ModuleTabs",
    activeKey = activeKey,
    tabs = tabs,
})

if draw.nav.isVisible("ShowAdvanced") then
    draw.widgets.checkbox("AdvancedFlag", opts)
end
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
draw.widgets.checkbox("FeatureEnabled", opts)
```

This intentionally differs from a `createDraw(...)` factory. `imgui`,
`session`, and `host` are live render/session surfaces, not static module
dependencies. They should enter the module at draw time, not be captured during
module construction.

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
    hashGroupPlan = hashGroupPlan,

    drawTab = ui.drawTab,
    drawQuickContent = ui.drawQuickContent,
})
```

`hasQuickContent` should stay internal. Module authors should not provide it as
public config. `createModule(...)` should derive it from the callback surface
and pass it to `prepareDefinition(...)` as structural metadata:

```lua
local preparedDefinition = moduleHost.prepareDefinition(
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

Normal root widgets should stay concise:

```lua
draw.widgets.checkbox("FeatureEnabled", opts)
draw.widgets.dropdown("Mode", opts)
draw.widgets.packedCheckboxList("GodPool", opts)
```

The string target is shorthand for a root storage field on the draw context's
author session. The full root form is available when a helper wants to pass a
resolved target around:

```lua
local mode = draw.field("Mode")
draw.widgets.dropdown(mode, opts)
```

Table-backed widgets use a `StorageField` produced by the table API:

```lua
local row = draw.session.table("ConfigurableBanPools"):rowHandle(index)
local bans = row:field("BanPool")

draw.widgets.packedCheckboxList(bans, opts)
draw.widgets.packedDropdown(bans, opts)
local selected = draw.widgets.getPackedChoiceAlias(bans, opts)
```

`StorageField` is the resolved leaf value target for widgets. It is not a path,
not a scoped alias string, and not a row handle pretending to be a session.
Storage and table APIs are responsible for traversal and validation; widgets
are leaf renderers that read schema/value data from the final field target.

Bound widgets accept only these target forms:

- `string`: root field alias, resolved through `draw.field(alias)`.
- `StorageField`: explicit resolved storage field.

They do not accept arbitrary table-shaped targets, parse scoped path strings,
or expose a public `draw.widgets.forSession(...)` rebinding API. Future path
support can live in storage APIs and resolve to `StorageField` before widgets
see it.

Implementation audit checklist:

- Add `draw.field(alias)` for explicit root storage fields.
- Add `rowHandle:field(alias)` for table row storage fields.
- Route bound widget targets through one `StorageField` normalization path.
- Remove `draw.widgets.forSession(...)` from the public bound widget surface.
- Replace loose `(handle, alias)` widget call sites with named domain helpers
  that return `StorageField` values.
- Keep normal root widget calls using string aliases as the ergonomic shorthand.

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
function ui.drawTab(draw)
    draw.widgets.checkbox("FeatureEnabled", {
        label = "Enable Feature",
    })
end
```

2. Pass one context object to inner UI files.

Before:

```lua
components.draw(imgui, session, host)
```

After:

```lua
components.draw(draw)
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
- Use `draw.widgets.*` for Lib widgets that bind to `imgui` and `session`.
- Use `draw.nav.*` for Lib navigation helpers that bind to `imgui` and
  `session`.
- Use `draw.imgui` for raw ImGui layout calls.
- Use `draw.session` only when direct staged-state access is clearer than a
  widget helper.
- Use `draw.services` for draw-safe module services such as logging, enabled
  checks, or integration queries. `draw.host` is no longer available.
- Keep static module data, catalogs, and action services in `ui.bind(...)`.
- Framework `drawPackQuickContent(ctx)` still uses its own coordinator/framework
  context object and is intentionally not part of this draw-object rename. Audit
  it separately before changing that callback shape.
