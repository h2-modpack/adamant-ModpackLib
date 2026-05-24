# Cache Object Design

Contributor design note for the cache API migration.

The current public cache surface is function-oriented:

```lua
host.cache.persistent.read("RecordingReady", false)
host.cache.persistent.write("RecordingReady", true)
host.cache.shared.read("some.shared.id", fallback)
```

The target shape is object-oriented. Existing functions stay available during
the migration, but new module code should move toward cache objects.

## Goals

- Give each cache key/id one local owner object in module code.
- Make repeated reads cheap by returning a local snapshot.
- Keep writes explicit and immediate.
- Avoid adding draw-phase policy flags to module code.
- Keep cache namespaces discoverable and typed.

## Constructors

Keep the cache namespaces. Do not add a root string dispatcher.

```lua
host.cache.persistent.create(key, opts)
host.cache.currentRun.create(key, opts)
host.cache.shared.create(id, opts)
```

`access` only belongs on shared cache because shared cache crosses module
boundaries. Persistent and current-run cache are module-owned.

## Core Object Rule

Every cache object owns a local snapshot.

- `get()` returns the snapshot.
- `set(...)` writes the backend and updates the snapshot when supported.
- `clear()` clears the backend and updates the snapshot when supported.
- `refresh()` reloads the backend into the snapshot.

Unsupported operations should not exist on the returned object. Do not expose
no-op methods.

## Persistent Cache

Persistent cache is for small module-owned scalar values that survive reloads
and are outside managed settings, profile, and hash state.

```lua
local recordingReady = host.cache.persistent.create("RecordingReady", {
    default = false,
})
```

Object:

```lua
recordingReady:get()
recordingReady:set(value)
recordingReady:clear()
recordingReady:has()
recordingReady:refresh()
```

Rules:

- `default` may be `boolean`, `number`, `string`, or `nil`.
- `set(value)` accepts `boolean`, `number`, or `string`.
- `set(value)` writes persistent cache immediately and updates the snapshot
  only after a successful backend write.
- `clear()` removes the persisted value and resets the snapshot to `default`.
- `has()` checks persisted backend presence.
- `refresh()` reloads the persisted value, or `default` when no value exists.

## Current-Run Cache

Current-run cache is for module-owned mutable table buckets tied to the current
run.

```lua
local timerState = host.cache.currentRun.create("TimerState", {
    factory = function()
        return {
            rows = {},
        }
    end,
})
```

Object:

```lua
timerState:get()
timerState:peek()
timerState:clear()
timerState:refresh()
```

Normal write pattern:

```lua
timerState:get().rows[1] = row
timerState:get().started = true
```

Rules:

- `factory` is optional and must return a table when supplied.
- The initial snapshot is `peek(key)`.
- `get()` returns the snapshot when present; otherwise it uses the backend
  `get(key, factory)` path and snapshots the returned table.
- `peek()` reloads an existing backend table without creating it.
- `refresh()` is equivalent to re-peeking without creating.
- `clear()` clears the backend and sets the snapshot to `nil`.
- Do not add `set(table)` by default. The natural write model is mutating the
  table returned by `get()`.
- Add `replace(table)` later only if a real use case appears.

## Shared Cache

Shared cache is the only cache scope with access modes.

Owner:

```lua
local availability = host.cache.shared.create("run-director.god-availability", {
    access = "owner",
    default = { active = false, available = {} },
})
```

Owner object:

```lua
availability:get()
availability:set(value)
availability:clear()
availability:refresh()
```

Reader:

```lua
local availability = host.cache.shared.create("run-director.god-availability", {
    access = "reader",
    fallback = { active = false, available = {} },
})
```

Reader object:

```lua
availability:get()
availability:refresh()
```

Rules:

- `access = "owner"` publishes and owns the projection.
- `access = "reader"` reads another module's projection.
- Use `owner` and `reader`, not `read` and `write`.
- Owner objects may read their own snapshot. They are not write-only.
- Reader objects do not expose `set()` or `clear()`.
- `refresh()` reloads the shared registry into the snapshot.

## Internal Builder

Use a generic internal snapshot-object builder, but expose typed public object
classes.

```lua
createSnapshotObject({
    load = function() end,
    write = function(value) end, -- optional
    clear = function() end,      -- optional
    has = function() end,        -- optional
})
```

Builder responsibilities:

- Load the initial snapshot once.
- Add only supported methods.
- Update the snapshot only after successful backend writes.
- Keep backend validation in the cache-specific adapter.
- Keep public types specific to each cache scope.

## Compatibility

Keep existing APIs during the migration:

```lua
host.cache.persistent.read(...)
host.cache.persistent.write(...)
host.cache.persistent.clear(...)
host.cache.persistent.has(...)

host.cache.currentRun.get(...)
host.cache.currentRun.peek(...)
host.cache.currentRun.clear(...)

host.cache.shared.publish(...)
host.cache.shared.read(...)
host.cache.shared.write(...)
host.cache.shared.clear(...)
```

Docs should prefer object APIs after they land. Raw functions can become legacy
after modules are ported.

The short-lived `persistent.snapshotRef(...)` API should be replaced by
`persistent.create(...)` before it spreads, or kept only as a temporary alias.

## Migration Order

1. Add cache object APIs and focused Lib tests.
2. Replace `persistent.snapshotRef(...)` with `persistent.create(...)`.
3. Port Timer `RecordingReady`.
4. Port shared cache users.
5. Re-evaluate the draw-safe host facade after cache and integration polling
   have object-based alternatives.
6. Mark raw cache functions as legacy only after modules are clean.
