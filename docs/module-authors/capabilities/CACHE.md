# Cache

Cache is a Lib-owned namespace for module runtime cache values. Use it for
runtime state that is not staged UI config, hash/profile config, or mutation
state.

Three domains exist today:

- `currentRun`: table buckets that follow the lifetime of active `CurrentRun`
- `persistent`: flat scalar values that survive reloads and restarts
- `shared`: owner-published live read models that other modules can read

No cache domain participates in staging, hashes, profiles, or whole-state
resets. `currentRun` and `persistent` live on the author `host`.
`shared` also has a draw-services read/write surface so owner UI code can
publish live projections from draw-visible staged state.

## Current Run

```lua
local runState = host.cache.currentRun.get("run", function()
    return {
        ForcedNPCPending = {},
        NPCEncounterSeen = {},
    }
end)
```

`currentRun.get(...)` returns `nil` when there is no active `CurrentRun`.

The author-host namespace binds the module's host id, which is backed by the
module's `pluginGuid`. Module code supplies only the cache domain and local key.
Internally, cache storage has three parts:

- `CurrentRun`: the live game run table
- owner id: the module's runtime owner identity, derived from `pluginGuid`
- `key`: cache bucket inside the owner namespace

Lib stores the bucket under one private root on `CurrentRun` so modules do not
attach ad hoc top-level keys. Pack and module ids remain Lib/Framework domain
metadata; `pluginGuid` is the module lifecycle identity that Lib maps to cache
ownership.

Current-run surface:

- `host.cache.currentRun.get(key, factory?)`
- `host.cache.currentRun.peek(key)`
- `host.cache.currentRun.clear(key)`

`get(...)` creates the cache bucket when missing. The optional factory runs
only on first creation and must return a table.

`peek(...)` returns an existing cache bucket without creating it.

`clear(...)` removes one cache bucket and prunes empty namespace tables.

## Persistent

Persistent cache is flat and scalar. It is intended for small runtime markers
such as "recording is ready", not nested state.

```lua
local ready = host.cache.persistent.read("RecordingReady", false)

host.cache.persistent.write("RecordingReady", true)

if host.cache.persistent.has("RecordingReady") then
    host.cache.persistent.clear("RecordingReady")
end

local recordingReady = host.cache.persistent.create("RecordingReady", {
    default = false,
})
recordingReady:set(true)
local drawSafeReady = recordingReady:get()
```

Persistent surface:

- `host.cache.persistent.read(key, default?)`
- `host.cache.persistent.write(key, value)`
- `host.cache.persistent.clear(key)`
- `host.cache.persistent.has(key)`
- `host.cache.persistent.create(key, opts?)`

Allowed persistent value types:

- boolean
- number
- string

`read(...)` returns the stored value when present, otherwise the optional
default. It does not create a stored value. `write(nil)` is invalid; use
`clear(...)` to remove a stored value.

`create(...)` returns a small write-through projection of one persistent
cache key. `get()` reads the in-memory snapshot, while `set(...)` and
`clear()` update persistent cache immediately and then update the snapshot.

## Shared

Shared cache is for cross-module read models. The owner module publishes a
stable id before activation, writes the current projection when it changes, and
other modules read that projection cheaply from runtime or draw code.

```lua
host.cache.shared.publish("run-director.god-availability", {
    default = { active = false, available = {} },
})

host.cache.shared.write("run-director.god-availability", {
    active = true,
    available = {
        Apollo = false,
    },
})
```

Draw consumers can read:

```lua
local snapshot = services.cache.shared.read("run-director.god-availability", {
    active = false,
    available = {},
})
```

Shared surface:

- `host.cache.shared.publish(id, opts?)`
- `host.cache.shared.read(id, fallback?)`
- `host.cache.shared.write(id, value)`
- `host.cache.shared.clear(id)`
- `services.cache.shared.read(id, fallback?)`
- `services.cache.shared.write(id, value)`
- `services.cache.shared.clear(id)`

`publish(...)` is declaration-time only and must run before activation. Only
the publishing host can write or clear that id. Other modules can only read.

`write(...)` updates live memory immediately. `clear(...)` resets the projection
to the publisher default. Shared cache does not persist and does not flush.

Reads return the caller fallback when no active publisher exists or when the
publisher is disabled. If an active publisher exists but has not written a
value, reads return the publisher default when one was declared.

Values may be scalars or tables. Lib deep-copies on write and read so consumers
cannot mutate the publisher's cached projection.

## When To Use It

Use current-run cache for:

- per-run transient state attached to `CurrentRun`
- data that should disappear when `CurrentRun` is replaced

Use persistent cache for:

- small runtime markers that should survive reloads or restarts
- values that should not appear in UI, hashes, profiles, or reset defaults

Use shared cache for:

- public live read models owned by one module and consumed by other modules
- immediate-mode UI filters that should read a cheap current projection instead
  of polling another module repeatedly

Use managed storage instead when the value is module configuration.

## Common Mistakes

- Do not store config settings in cache.
- Do not attach module keys directly to `CurrentRun`.
- Do not use cache for values that must participate in hashes or profiles.
- Do not let the factory return non-table values.
- Do not put tables in persistent cache. Serialize to a string yourself if a
  complex value is truly needed.
- Do not publish shared cache ids from draw code. Declare them before
  activation, then write from host or draw services later.
- Do not use shared cache for behavior calls. Use integrations for cross-module
  behavior APIs.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
