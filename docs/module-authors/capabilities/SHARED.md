# Shared

Shared is the Lib-owned cross-module cooperation surface.

It has two related parts:

- shared data: owner-published read models available through
  `runtime.shared` / `runtime.data.shared` and draw `ui.shared` /
  `ui.data.shared`
- shared events: optional runtime signals emitted through `runtime.shared.emit`
  or draw `ui.shared.emit`

Both are declared on `module.shared` before activation.

## Shared Data

Owner declaration:

```lua
module.shared.data.owner("GodAvailability", {
    id = "run-director.god-availability",
    default = {
        active = false,
        available = {},
    },
})
```

Owner write:

```lua
runtime.data.shared.set("GodAvailability", {
    active = true,
    available = {
        Apollo = false,
    },
})
```

Reader declaration:

```lua
module.shared.data.reader("GodAvailability", {
    id = "run-director.god-availability",
    fallback = {
        active = false,
        available = {},
    },
})
```

Draw read:

```lua
local availability = ui.data.shared.read("GodAvailability")
local available = availability.available or {}
```

Surface:

- `module.shared.data.owner(name, { id = string, default? = value })`
- `module.shared.data.reader(name, { id = string, fallback? = value })`
- `runtime.data.shared.read(name)`
- `runtime.data.shared.set(name, value)` for owner declarations
- `runtime.data.shared.clear(name)` for owner declarations
- `runtime.shared.*` is the same runtime shared-data surface
- `ui.data.shared.read(name)`
- `ui.data.shared.set(name, value)` for owner declarations
- `ui.data.shared.clear(name)` for owner declarations
- `ui.shared.*` is the same draw shared-data surface

Values may be scalars or tables with string/number keys. Table writes are
copied once and reads return recursive read-only views. Cache repeated inner
tables in locals when doing repeated reads in one function.

Shared data writes publish immediately. `ui.shared.set(...)` and
`ui.data.shared.set(...)` are not staged config writes, do not make the module
dirty, and are not rolled back if a later config commit fails. Use them when
the shared read model is meant to reflect the current owner state immediately.
If the shared value should reflect only committed UI settings, publish it from
`module.onCommit(...)` or runtime code after reading `runtime.data`.

## Shared Events

Listener declaration:

```lua
module.shared.listen("run-director.route-state", "routeChanged", function(host, runtime, payload)
    host.log("route changed: %s", tostring(payload.route))
end)
```

Runtime emit:

```lua
runtime.shared.emit("run-director.route-state", "routeChanged", {
    route = "Apollo",
})
```

Draw emit:

```lua
local function drawTab(host, ui)
    if ui.draw.widgets.button("Refresh route") then
        ui.shared.emit("run-director.route-state", "routeChanged", {
            route = ui.data.read("Route"),
        })
    end
end
```

Draw emits are staged during the draw callback and delivered during commit
after staged state flush, mutation sync, action handlers, and queued
status resets.
`runtime.shared.emit(...)` returns `true, deliveredCount` because it delivers
immediately. `ui.shared.emit(...)` returns `true` only; its delivery count is
not available until the deferred commit flush runs.
Use [../DRAW_LIFECYCLE.md](../DRAW_LIFECYCLE.md) for the full draw/commit
order.

Delivery rules:

- disabled listener modules do not receive events
- disabled emitter modules do not emit events
- listener order is unspecified
- one failing listener logs and does not stop remaining listeners
- emits inside listeners are queued until the current event fanout completes
- events are not replayed to late listeners
- listener callbacks receive `(host, runtime, payload)`

Use shared data for synchronous read models. Use shared events for small
signals. Do not use shared events for synchronous draw-time reads.
