# Cache

Cache is a Lib-owned namespace for module runtime cache values. Use it for
runtime state that is not staged UI config, hash/profile config, or mutation
state.

Two domains exist today:

- `currentRun`: table buckets that follow the lifetime of active `CurrentRun`
- `persistent`: flat scalar values that survive reloads and restarts

Neither domain participates in staging, hashes, profiles, or whole-state resets.

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
```

Persistent surface:

- `host.cache.persistent.read(key, default?)`
- `host.cache.persistent.write(key, value)`
- `host.cache.persistent.clear(key)`
- `host.cache.persistent.has(key)`

Allowed persistent value types:

- boolean
- number
- string

`read(...)` returns the stored value when present, otherwise the optional
default. It does not create a stored value. `write(nil)` is invalid; use
`clear(...)` to remove a stored value.

## When To Use It

Use current-run cache for:

- per-run transient state attached to `CurrentRun`
- data that should disappear when `CurrentRun` is replaced

Use persistent cache for:

- small runtime markers that should survive reloads or restarts
- values that should not appear in UI, hashes, profiles, or reset defaults

Use managed storage instead when the value is module configuration.

## Common Mistakes

- Do not store config settings in cache.
- Do not attach module keys directly to `CurrentRun`.
- Do not use cache for values that must participate in hashes or profiles.
- Do not let the factory return non-table values.
- Do not put tables in persistent cache. Serialize to a string yourself if a
  complex value is truly needed.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
