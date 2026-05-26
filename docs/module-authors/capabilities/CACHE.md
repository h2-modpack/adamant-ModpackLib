# Cache

Cache is a Lib-owned namespace for module runtime cache values. Use it for
runtime state that is not staged UI config, hash/profile config, or mutation
state.

Two domains exist today:

- `currentRun`: table buckets that follow the lifetime of active `CurrentRun`
- `persistent`: flat scalar values that survive reloads and restarts

No cache domain participates in staging, hashes, profiles, or whole-state
resets.

Declare managed cache on `createModule({ cache = ... })` and access it through
`store.cache` or draw `state.cache`.

## Declaration

Declare Lib-managed cache refs next to storage/actions:

```lua
local host, store = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example",
    cache = {
        RecordingReady = {
            domain = "persistent",
            key = "RecordingReady",
            default = false,
        },
        RunScratch = {
            domain = "currentRun",
            key = "run",
            factory = function()
                return {}
            end,
        },
    },
    drawTab = ui.drawTab,
})
```

Runtime code uses `store.cache`:

```lua
store.cache.persistent.set("RecordingReady", true)
local ready = store.cache.persistent.read("RecordingReady")

local runScratch = store.cache.currentRun.get("RunScratch")
runScratch.seen = true
```

Draw code uses `state.cache` for draw-safe cache refs:

```lua
local ready = state.cache.persistent.read("RecordingReady")
```

Rules:

- cache declaration names must be stable identifiers
- declared cache is part of the structural definition fingerprint
- `store.cache` is valid outside draw callbacks
- `state.cache` is valid only during draw callbacks
- persistent cache is writable from `store.cache`; draw access is read-only
- current-run cache is only available from `store.cache`

## Current Run

Current-run cache is for per-run mutable table buckets attached to the active
`CurrentRun`.

```lua
local runState = store.cache.currentRun.get("RunScratch")
runState.ForcedNPCPending = runState.ForcedNPCPending or {}
```

Surface:

- `store.cache.currentRun.get(name)`
- `store.cache.currentRun.clear(name)`

`get(...)` creates the cache bucket when missing. The declaration factory runs
only on first creation and must return a table. `clear(...)` removes one cache
bucket and prunes empty namespace tables.

## Persistent

Persistent cache is flat and scalar. It is intended for small runtime markers
such as "recording is ready", not nested state.

```lua
store.cache.persistent.set("RecordingReady", true)
local ready = store.cache.persistent.read("RecordingReady")
store.cache.persistent.clear("RecordingReady")

local drawSafeReady = state.cache.persistent.read("RecordingReady")
```

Surface:

- `store.cache.persistent.read(name)`
- `store.cache.persistent.set(name, value)`
- `store.cache.persistent.clear(name)`
- `state.cache.persistent.read(name)`

Allowed persistent value types:

- boolean
- number
- string

`read(...)` returns the stored value when present, otherwise the declaration
default. It does not create a stored value. `set(nil)` is invalid; use
`clear(...)` to remove a stored value.

## When To Use It

Use current-run cache for:

- per-run transient state attached to `CurrentRun`
- data that should disappear when `CurrentRun` is replaced

Use persistent cache for:

- small runtime markers that should survive reloads or restarts
- values that should not appear in UI, hashes, profiles, or reset defaults

Do not use cache for:

- user-editable settings: use managed storage
- hash/profile state: use managed storage
- cross-module read models or behavior callbacks: use shared
