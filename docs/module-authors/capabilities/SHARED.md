# Shared

Shared is the Lib-owned cross-module cooperation surface. It has two related
parts:

- shared data: owner-published read models available through `store.shared` and
  draw `state.shared`
- shared events: optional runtime signals emitted through `host.shared.emit` or
  draw `actions.emit`

Both are declared on `host.shared` after `lib.createModule(...)` returns and
before `host.activate()`.

Use shared data when draw/runtime code needs to read another module's public
projection. Use shared events when modules should react to a small signal and
still work when no listener or emitter is present.

## Shared Data

Owner declaration:

```lua
host.shared.data.owner("GodAvailability", {
    id = "run-director.god-availability",
    default = {
        active = false,
        available = {},
    },
})
```

Owner write:

```lua
store.shared.set("GodAvailability", {
    active = true,
    available = {
        Apollo = false,
    },
})
```

Reader declaration:

```lua
host.shared.data.reader("GodAvailability", {
    id = "run-director.god-availability",
    fallback = {
        active = false,
        available = {},
    },
})
```

Runtime readers use `store.shared`; draw readers use `state.shared`:

```lua
local availability = state.shared.read("GodAvailability")
local available = availability.available or {}
```

Surface:

- `host.shared.data.owner(name, { id = string, default? = value })`
- `host.shared.data.reader(name, { id = string, fallback? = value })`
- `store.shared.read(name)`
- `store.shared.set(name, value)` for owner declarations
- `store.shared.clear(name)` for owner declarations
- `state.shared.read(name)`
- `state.shared.set(name, value)` for owner declarations
- `state.shared.clear(name)` for owner declarations

Shared data does not persist and does not flush. Reads return the declaration
fallback when no active publisher exists or when the publisher is disabled. If
an active publisher exists but has not written a value, reads return the
publisher default when one was declared.

Values may be scalars or tables with string/number keys. Table writes are
copied once and reads return recursive read-only views. For repeated inner
reads in one function, cache the returned snapshot or inner table in a local.

Shared data declarations do not participate in the module structural
fingerprint. They are activation-time shared capabilities, not core module
identity.

## Shared Events

Shared events let one module emit a small domain signal and let other modules
listen without hard dependency coupling.

### Listener Shape

Hosted modules declare listeners on the author host before activation:

```lua
local host, store, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})
if not host then return end

host.shared.listen("run-director.route-state", "routeChanged", function(payload)
    host.log("route changed: %s", tostring(payload.route))
end)

host.activate()
```

Listener declarations close when activation begins. Register the complete
current listener set before calling `host.activate()`.

### Emit Shape

Activated hosts can emit events at runtime:

```lua
host.shared.emit("run-director.route-state", "routeChanged", {
    route = "Apollo",
})
```

Draw callbacks do not receive the author host. To emit from UI intent, queue the
event through draw actions:

```lua
function ui.drawTab(draw, state, actions)
    if draw.widgets.button("Refresh route") then
        actions.emit("run-director.route-state", "routeChanged", {
            route = state.read("Route"),
        })
    end
end
```

`emit(...)` returns `true, deliveredCount` when the event was accepted. Missing
listeners are not an error and return `true, 0`.

Event payloads are plain Lua values. Keep them small and treat them as signals,
not durable replicated state. For live read models, use shared data.

## Delivery Rules

- disabled listener hosts do not receive events
- disabled emitter hosts do not emit events
- listener order is unspecified
- one failing listener logs and does not stop remaining listeners
- emits inside listeners are queued until the current event fanout completes
- events are not replayed to late listeners
- listener callbacks receive `payload`

Listeners are runtime callbacks. Do not write managed settings from listeners.
Use current-run cache or `mode = "runtime"` storage for explicit runtime state
writes.

## Public Surface

Use:

- `host.shared.data.owner(name, opts)`
- `host.shared.data.reader(name, opts)`
- `host.shared.listen(id, eventName, callback)`
- `host.shared.emit(id, eventName, payload)`
- `actions.emit(id, eventName, payload)` from draw callbacks

There is no synchronous shared-event polling surface. If draw code needs to read
another module's published state, model that data through shared data instead
of a shared event callback.

## Naming

Shared ids should describe domain behavior, not a specific consumer:

```text
run-director.route-state
run-director.timer-events
```

Event names should describe the signal:

```text
routeChanged
recordingStarted
recordingStopped
```

## Common Mistakes

- Do not make listeners require an emitter to exist unless it is truly mandatory.
- Do not treat event payloads as durable state.
- Do not write managed settings from event listeners.
- Do not emit before `host.activate()` completes.
- Do not use shared events for synchronous draw-time reads; use shared data.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
