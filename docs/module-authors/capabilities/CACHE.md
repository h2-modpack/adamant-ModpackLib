# Cache

Cache is a Lib-owned namespace for module runtime cache values. Use it for
runtime state that is not staged UI config, hash/profile config, or mutation
state.

Three domains exist today:

- `currentRun`: table buckets that follow the lifetime of active `CurrentRun`
- `persistent`: flat scalar values that survive reloads and restarts
- `shared`: owner-published live read models that other modules can read

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
        GodAvailability = {
            domain = "shared",
            id = "run-director.god-availability",
            access = "reader",
            fallback = {
                active = false,
                available = {},
            },
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
local availability = state.cache.shared.read("GodAvailability")
if availability.active and availability.available.Apollo ~= false then
    -- draw available UI
end
```

Rules:

- cache declaration names must be stable identifiers
- declared cache is part of the structural definition fingerprint
- `store.cache` is valid outside draw callbacks
- `state.cache` is valid only during draw callbacks
- persistent cache is writable from `store.cache`; draw access is read-only
- current-run cache is only available from `store.cache`
- shared owner declarations can write through `store.cache.shared.set(...)` or
  `state.cache.shared.set(...)`
- shared reader declarations are read-only

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

## Shared

Shared cache is for cross-module read models. The owner module declares a
stable id and writes the current projection when it changes. Other modules read
that projection cheaply from runtime or draw code.

Owner declaration:

```lua
GodAvailability = {
    domain = "shared",
    id = "run-director.god-availability",
    access = "owner",
    default = {
        active = false,
        available = {},
    },
}
```

Owner write:

```lua
store.cache.shared.set("GodAvailability", {
    active = true,
    available = {
        Apollo = false,
    },
})
```

Reader declaration:

```lua
GodAvailability = {
    domain = "shared",
    id = "run-director.god-availability",
    access = "reader",
    fallback = {
        active = false,
        available = {},
    },
}
```

Surface:

- `store.cache.shared.read(name)`
- `store.cache.shared.set(name, value)` for owner declarations
- `store.cache.shared.clear(name)` for owner declarations
- `state.cache.shared.read(name)`
- `state.cache.shared.set(name, value)` for owner declarations
- `state.cache.shared.clear(name)` for owner declarations

Shared cache does not persist and does not flush. Reads return the declaration
fallback when no active publisher exists or when the publisher is disabled. If
an active publisher exists but has not written a value, reads return the
publisher default when one was declared.

Values may be scalars or tables. Table writes are copied once and reads return
recursive read-only views.

For table-shaped shared cache, prefer a small domain helper around the raw
table path instead of spreading nested lookups through module code:

```lua
local function readAvailability(source)
    return source.cache.shared.read("GodAvailability")
end

local function isGodAvailable(source, godKey)
    local availability = readAvailability(source)
    if availability.active ~= true then
        return true
    end
    return not availability.available or availability.available[godKey] ~= false
end
```

The helper can accept either `store` or draw `state` because both expose
`source.cache.shared.read(...)`. For repeated inner reads in one function,
cache the returned snapshot or inner table in a local:

```lua
local availability = state.cache.shared.read("GodAvailability")
local available = availability.available or {}

if available.Apollo ~= false then
    -- draw Apollo UI
end
```

## When To Use It

Use current-run cache for:

- per-run transient state attached to `CurrentRun`
- data that should disappear when `CurrentRun` is replaced

Use persistent cache for:

- small runtime markers that should survive reloads or restarts
- values that should not appear in UI, hashes, profiles, or reset defaults

Use shared cache for:

- public read models shared between modules
- low-cost runtime/draw reads where integrations would be too heavy

Do not use cache for:

- user-editable settings: use managed storage
- hash/profile state: use managed storage
- behavior callbacks: use integrations
