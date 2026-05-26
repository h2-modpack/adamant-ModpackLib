# Cache

Cache is a Lib-owned namespace for module runtime scratch state with a
game-lifetime owner. It is not for settings, hashes, profiles, UI staging, or
cross-module read models.

One cache domain exists today:

- `currentRun`: mutable table buckets that follow the lifetime of active `CurrentRun`

For runtime-owned scalar or table values that need normal module storage
semantics, use managed storage with `mode = "runtime"` instead of cache.

## Declaration

Declare current-run cache refs next to storage/actions:

```lua
local host, store = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example",
    cache = {
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
local runScratch = store.cache.currentRun.get("RunScratch")
runScratch.seen = true
```

Current-run cache is not exposed through draw `state`. If UI needs to display a
runtime-derived value, write that value to managed runtime storage or shared
data from runtime code.

Rules:

- cache declaration names must be stable identifiers
- declared cache is part of the structural definition fingerprint
- `store.cache` is valid outside draw callbacks
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

## When To Use It

Use current-run cache for:

- per-run transient state attached to `CurrentRun`
- data that should disappear when `CurrentRun` is replaced

Use `mode = "runtime"` storage for:

- runtime-owned values that UI can read
- values that may persist through reloads or restarts
- values that should stay outside hashes/profiles and staged UI writes

Do not use cache for:

- user-editable settings: use normal managed storage
- hash/profile state: use managed storage
- cross-module read models or behavior callbacks: use shared
