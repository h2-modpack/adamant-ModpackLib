# Overlays

Overlays are retained HUD projections owned by a managed module. They are useful for gameplay-facing status text, counters, timers, or compact tables that should appear in Lib-managed HUD regions.

Use overlays when the module needs a retained display. Use widgets when the module needs configuration UI.

## Normal Shape

Create the module, declare overlays on `module.overlays`, then activate:

```lua
local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
})
if not module then return end

module.data.define(data.buildStorage())
module.ui.tab(ui.drawTab)

module.overlays.createLine("summary.igt", {
    region = "middleRightStack",
    order = module.overlays.order.module,
    columnGap = 20,
    columns = {
        { key = "label", minWidth = 40 },
        { key = "time", minWidth = 80 },
    },
})

module.overlays.onCommit(function(host, runtime, overlay)
    overlay.setLine("summary.igt", {
        label = "IGT:",
        time = runtime.data.read("TimerText") or "00:00.00",
    })
    overlay.refresh("summary.igt")
end)

module.activate()
```

`module.overlays` is bound to the module, so overlay declarations do not need
a separate owner argument or a construction-time callback.

## Retained Elements

Use:

- `module.overlays.createLine(name, spec)`
- `module.overlays.createTable(name, spec)`

Retained element names are local to the module owner id derived from
`pluginGuid`. Different modules can reuse the same local element names without
colliding.

The shared managed region currently exposed to modules is:

- `middleRightStack`

Order bands:

- `module.overlays.order.framework`
- `module.overlays.order.module`
- `module.overlays.order.debug`

## Projection Events

Overlay projections can update retained elements from:

- `module.overlays.onCommit(function(host, runtime, overlay, commit) ... end)`
- `module.overlays.onInterval(name, seconds, function(host, runtime, overlay, event) ... end, opts)`
- `module.overlays.afterHook(path, function(host, runtime, overlay, event) ... end)`

`host` is the normal callback-safe module utility object. `runtime` is the runtime
callback object, so read committed module data through `runtime.data`.

The retained overlay projection exposes:

- `overlay.setLine(name, values)`
- `overlay.setTable(name, rows)`
- `overlay.setCell(tableName, rowKey, columnKey, value)`
- `overlay.refresh(name)`
- `overlay.refreshRegion(region)`
- `overlay.refreshAll()`

Do not capture UI state in overlay callbacks.
Projection callbacks are runtime projections, not draw callbacks. They do not
receive `draw`, `state`, or `actions`, and should not cache their
`runtime` or `overlay` objects outside the callback.

## Visibility And UI Suppression

Overlay visibility has multiple gates:

- Lib applies the global game-HUD gate.
- Each overlay can provide its own `visible` boolean or callback.
- Framework and fallback configuration UI suppress the entire overlay layer while open.

Module code does not call suppression APIs directly. Framework and Lib
fallback UI windows acquire and release suppression through their runtime
facades while foreground configuration UI is open.

## Common Mistakes

- Do not render overlay text directly from draw-tab UI code.
- Do not use overlays for editable configuration.
- Do not read staged UI state values from projection callbacks.
- Do not call draw widgets or raw ImGui from overlay projection callbacks.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [WIDGETS.md](WIDGETS.md)
- [../../../API.md](../../../API.md)
