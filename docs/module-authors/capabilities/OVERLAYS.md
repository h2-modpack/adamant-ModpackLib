# Overlays

Overlays are retained HUD projections owned by a module host. They are useful for gameplay-facing status text, counters, timers, or compact tables that should appear in Lib-managed HUD regions.

Use overlays when the module needs a retained display. Use widgets when the module needs configuration UI.

## Normal Shape

Create the host, declare overlays on `host.overlays`, then activate:

```lua
local host, store = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})

host.overlays.createLine("summary.igt", {
    region = "middleRightStack",
    order = host.overlays.order.module,
    columnGap = 20,
    columns = {
        { key = "label", minWidth = 40 },
        { key = "time", minWidth = 80 },
    },
})

host.overlays.onCommit(function(ctx)
    ctx.setLine("summary.igt", {
        label = "IGT:",
        time = "00:00.00",
    })
    ctx.refresh("summary.igt")
end)

host.activate()
```

`host.overlays` is bound to the module host, so overlay declarations do not need
an owner token or a construction-time callback.

## Retained Elements

Use:

- `host.overlays.createLine(name, spec)`
- `host.overlays.createTable(name, spec)`

Retained element names are local to the module owner id derived from
`pluginGuid`. Different modules can reuse the same local element names without
colliding.

The shared managed region currently exposed to modules is:

- `middleRightStack`

Order bands:

- `host.overlays.order.framework`
- `host.overlays.order.module`
- `host.overlays.order.debug`

## Projection Events

Overlay projections can update retained elements from:

- `host.overlays.onCommit(function(ctx, commit) ... end)`
- `host.overlays.onInterval(name, seconds, function(ctx, event) ... end, opts)`
- `host.overlays.afterHook(path, function(ctx, event) ... end)`

The projection context exposes:

- `ctx.read(alias)`
- `ctx.isEnabled()`
- `ctx.log(fmt, ...)`
- `ctx.logIf(fmt, ...)`
- `ctx.setLine(name, values)`
- `ctx.setTable(name, rows)`
- `ctx.setCell(tableName, rowKey, columnKey, value)`
- `ctx.refresh(name)`
- `ctx.refreshRegion(region)`
- `ctx.refreshAll()`

Use `ctx.read(alias)` for committed store values. Do not capture UI state in overlay callbacks.

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

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [WIDGETS.md](WIDGETS.md)
- [../../../API.md](../../../API.md)
