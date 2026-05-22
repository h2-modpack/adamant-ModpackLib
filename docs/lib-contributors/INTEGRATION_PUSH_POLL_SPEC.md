# Integration Push/Poll Spec

This is a design note for extending integrations with push notifications while
preserving polling as the source of truth for current provider state.

## Goals

- Keep integrations optional and domain-scoped.
- Add event-driven invalidation for consumers that cache provider-derived data.
- Avoid turning integrations into a general cross-module state bus.
- Keep provider reads constrained through declared `reads`.
- Keep listener writes explicit and local to the consumer.

## Public Surface

Target module-facing API:

```lua
host.integrations.provide(id, spec)
host.integrations.poll(id, methodName, fallback, ...)
host.integrations.listen(id, eventName, callback)
host.integrations.emit(id, eventName, payload)
```

Planned renames:

```lua
register(...) -> provide(...)
invoke(...)   -> poll(...)
```

Draw services should expose only the draw-safe pull side:

```lua
services.pollIntegration(id, methodName, fallback, ...)
```

Do not expose `provide`, `listen`, or `emit` from draw services.

## Provider Declaration

Providers declare pull methods and push events together:

```lua
host.integrations.provide("run-director.god-availability", {
    providerId = "GodPool",

    methods = {
        snapshot = {
            reads = GOD_AVAILABILITY_READS,
            handler = function(scope)
                return buildSnapshot(scope.read)
            end,
        },

        isAvailable = {
            reads = GOD_AVAILABILITY_READS,
            handler = function(scope, godKey)
                return readGodAvailability(scope.read, godKey) ~= false
            end,
        },
    },

    events = {
        availabilityChanged = true,
    },
})
```

Rules:

- `providerId` is the public provider identity returned by `poll`.
- `methods` are provider pull functions.
- `events` is a flat map of provider-owned event names.
- Provider declarations close when `host.activate()` begins.
- Provider hosts are lifecycle-owned by plugin guid and cleaned up on reload.
- Disabled provider hosts are skipped by `poll`.
- Disabled provider hosts cannot `emit`.

## Polling

```lua
local snapshot, providerId = host.integrations.poll(id, "snapshot", EMPTY)
local available = host.integrations.poll(id, "isAvailable", true, godKey)
```

Semantics:

- Poll asks the current preferred enabled provider for a method result.
- The preferred provider is the newest activated enabled provider.
- Missing providers or methods return `fallback, providerIdOrNil`.
- Provider method failures are logged and return the fallback.
- Provider methods receive a scoped read object plus method arguments.
- Provider scope exposes only `scope.read(alias, ...)` and `scope.get(alias)`.
- Provider scope is valid only during the method call.
- Provider reads must be declared through `reads`.

Polling answers: what is true now?

## Listening

```lua
host.integrations.listen("run-director.god-availability", "availabilityChanged", function(payload, providerId)
    refreshAvailabilityCache()
end)
```

Rules:

- Listener declarations close when `host.activate()` begins.
- Listeners are lifecycle-owned by the listener host and removed on reload.
- Listener order is unspecified.
- Disabled listener hosts do not receive events.
- Listener callbacks receive `payload, providerId`.
- Listener callbacks are runtime callbacks, not draw callbacks.
- Listener callbacks should not write managed settings.
- Listener callbacks should treat events as invalidation or change signals.
- One failing listener logs and does not stop remaining listeners.

Events announce: something changed.

## Emitting

```lua
host.integrations.emit("run-director.god-availability", "availabilityChanged", {
    reason = "settingsCommitted",
})
```

Rules:

- The emitter must be an enabled provider for that integration id.
- The event name must be declared by that provider's `events`.
- Undeclared emits are author errors.
- Payloads are plain Lua data.
- Payloads should be small and should not be treated as authoritative long-term state.
- Prefer returning `true, deliveredCount` for accepted emits.

## Nested Emits

Nested event fanout should be queued, not delivered recursively.

Semantics:

- If `emit(...)` happens outside event delivery, delivery starts immediately.
- If `emit(...)` happens while an event is being delivered, Lib queues it.
- The current event finishes delivery to all listeners first.
- Queued events drain FIFO afterward.
- Events emitted while draining append to the same queue.
- A drain guard should stop cycles, log the violation, and drop remaining queued events.

Events are notifications, not call-chain interception. Queueing avoids
hook-like recursive stack complexity.

## Poll And Push Relationship

Events are not state. Current state comes from `poll`; invalidation comes from
`emit` / `listen`.

Recommended consumer pattern:

```lua
local availabilityCache = nil

local function refresh(host)
    availabilityCache = host.integrations.poll(ID, "snapshot", EMPTY_SNAPSHOT)
end

host.integrations.listen(ID, "availabilityChanged", function()
    refresh(host)
end)

local function isAvailable(host, godKey)
    if availabilityCache == nil then
        refresh(host)
    end
    return availabilityCache[godKey] ~= false
end
```

This handles module load order:

- If the provider loads first, lazy polling recovers current state.
- If the consumer loads first, later provider events refresh the cache.
- If an initial event is missed, lazy polling still recovers.
- If the provider reloads, changes, or disables, provider events can invalidate or refresh consumers.

Lib should not replay or cache events for late listeners. Replay would require
retention policy, payload lifetime rules, and provider-disable semantics that
are heavier than the integration model needs.

## God Pool Target Shape

God Pool can provide both current-state methods and change events:

```lua
host.integrations.provide(ID, {
    providerId = "GodPool",

    methods = {
        snapshot = {
            reads = GOD_AVAILABILITY_READS,
            handler = function(scope)
                return buildAvailabilitySnapshot(scope.read)
            end,
        },
        isAvailable = {
            reads = GOD_AVAILABILITY_READS,
            handler = function(scope, godKey)
                return readGodAvailability(scope.read, godKey) ~= false
            end,
        },
    },

    events = {
        availabilityChanged = true,
    },
})
```

Consumers should use `poll(..., "snapshot", EMPTY)` for cache fill and listen
to `availabilityChanged` for refresh. Consumers that do not cache can keep
polling directly.

## Relationship To Hooks

Hooks and integration events are analogous only at declaration time.

Hooks intercept a live call path:

- base function
- return values
- ordering concerns
- recursive stack behavior

Integration events broadcast information:

- no base function
- no return value collection
- unspecified listener order
- queued nested emits

The module-facing language should match existing author verbs:

```lua
host.hooks.wrap(...)
host.integrations.provide(...)
host.integrations.listen(...)
host.integrations.emit(...)
```
