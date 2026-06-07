# Module Authoring

This guide describes the supported module contract in Lib.

## Core Shape

Modules are created in three steps:

1. Create a module declaration object with `lib.createModule(...)`.
2. Declare data, UI, and runtime capabilities on that object.
3. Call `module.activate()`.

```lua
local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
    tooltip = "What this module does.",
})
if not module then return end

module.data.define(data.buildStorage())
module.status.define(data.buildStatus())
module.actions.define(data.buildActions())
module.cache.define(data.buildCache())
module.controls.defineTemplates(data.buildControlTemplates())
module.controls.define(data.buildControls())
module.ui.tab(ui.drawTab)
module.ui.quickContent(ui.drawQuickContent)
module.onCommit(logic.onCommit)

module.hooks.wrap("SomeGameFunction", function(host, runtime, base, ...)
    if host.isEnabled() and runtime.data.read("FeatureEnabled") then
        -- Runtime behavior reads committed state.
    end
    return base(...)
end)

module.mutation.patch(logic.buildPatchPlan)
module.activate()
```

`createModule(...)` accepts module identity/display metadata and the Chalk
config table. Storage, actions, cache, controls, UI, hooks, shared data,
mutations, overlays, and fallback UI are declarations made before
activation.

## Author Object

The returned object is the module-facing declaration and lifecycle surface.
Module code usually names it `module`.

Common surfaces:

- `module.data.define(...)`
- `module.status.define(...)`
- `module.actions.define(...)`
- `module.cache.define(...)`
- `module.controls.defineTemplates(...)`
- `module.controls.define(...)`
- `module.ui.tab(...)`
- `module.ui.quickContent(...)`
- `module.onCommit(...)`
- `module.hooks.*`
- `module.shared.*`
- `module.mutation.*`
- `module.overlays.*`
- `module.fallbackUi.attachGuiOnce(...)`
- `module.activate()`

Activation publishes the live module for Framework/fallback UI, installs declared
hooks/overlays/shared events, and syncs initial mutation state.

## Draw Callbacks

Draw callbacks receive one small host projection and one UI context:

```lua
local function drawTab(host, ui)
    local draw = ui.draw
    local state = ui.data
    local actions = ui.actions

    draw.widgets.checkbox(state.get("FeatureEnabled"), {
        label = "Enabled",
    })

    draw.control(ui.controls.get("CompositeSetting"))
end
```

`ui.draw`, `ui.data`, `ui.actions`, and `ui.controls` are draw-callback
objects. Use them in the callback that receives them. Do not retain them for
runtime hooks or later callbacks.

Use [DRAW_LIFECYCLE.md](DRAW_LIFECYCLE.md) for the full draw/commit order and
the runtime-vs-UI data boundary. Use [DATA_LANES.md](DATA_LANES.md) to decide
whether a value belongs in data, transient data, status, cache, shared state, or
actions.

## Runtime Callbacks

Runtime callbacks receive `host` plus a runtime context when they need module
data:

```lua
module.hooks.wrap("SomeGameFunction", function(host, runtime, base, ...)
    if host.isEnabled() and runtime.data.read("FeatureEnabled") then
        host.logIf("feature enabled")
    end
    return base(...)
end)

module.mutation.patch(function(host, runtime, plan)
    if runtime.data.read("FeatureEnabled") then
        plan:set(SomeGameTable, "Enabled", true)
    end
end)
```

Runtime data is committed state. Do not read draw `ui.data` from runtime
callbacks.

## Managed Data

Storage roots live in `module.data.define(...)`.

- Normal roots persist and hash by default.
- `persist = false, hash = false` creates transient draw-only UI state.
- `module.status.define(...)` declares runtime-authored state that runtime
  writes through `runtime.status` and UI reads through `ui.status`.
- Status is runtime state, not mutation configuration. Use normal UI-owned
  storage for values that should affect `module.mutation.patch`.
- `Enabled` and `DebugMode` are Lib-owned built-ins; do not declare them.

Use [capabilities/MANAGED_STATE.md](capabilities/MANAGED_STATE.md) for details.
Use [DATA_LANES.md](DATA_LANES.md) for the overall state ownership model.
Use [capabilities/CONTROLS.md](capabilities/CONTROLS.md) when a repeated
domain concept needs its own bundled storage, runtime reader, and draw path.

## Capability Guides

- [capabilities/MANAGED_STATE.md](capabilities/MANAGED_STATE.md)
- [capabilities/WIDGETS.md](capabilities/WIDGETS.md)
- [capabilities/CONTROLS.md](capabilities/CONTROLS.md)
- [capabilities/HOOKS.md](capabilities/HOOKS.md)
- [capabilities/MUTATIONS.md](capabilities/MUTATIONS.md)
- [capabilities/OVERLAYS.md](capabilities/OVERLAYS.md)
- [capabilities/SHARED.md](capabilities/SHARED.md)
- [capabilities/CACHE.md](capabilities/CACHE.md)
