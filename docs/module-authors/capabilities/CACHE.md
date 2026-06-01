# Cache

Cache is a Lib-owned namespace for module runtime scratch state with a
game-lifetime owner. It is not for settings, hashes, profiles, UI staging, or
cross-module read models.

One cache domain exists today:

- `currentRun`: mutable table buckets that follow the lifetime of active `CurrentRun`

For runtime-owned scalar or table values that need normal module storage
semantics, use managed storage with `mode = "runtime"` instead of cache.

## Declaration

Declare current-run cache refs before activation:

```lua
local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example",
})
if not module then return end

module.cache.define({
    RunScratch = {
        domain = "currentRun",
        key = "run",
        factory = function()
            return {}
        end,
    },
})
module.ui.tab(ui.drawTab)
module.activate()
```

Runtime callbacks use `runtime.data.cache`:

```lua
local runScratch = runtime.data.cache.currentRun.get("RunScratch")
runScratch.seen = true
```

Current-run cache is not exposed through draw `state`. If UI needs to display a
runtime-derived value, write that value to managed `mode = "runtime"` storage
through `runtime.data.runtimeOwned` or publish shared data from runtime code.

Rules:

- cache declaration names must be stable identifiers
- declared cache is part of the structural definition fingerprint
- `runtime.data.cache` is valid outside draw callbacks
- current-run cache is only available from runtime data

## Current Run

Current-run cache is for per-run mutable table buckets attached to the active
`CurrentRun`.

```lua
local runState = runtime.data.cache.currentRun.get("RunScratch")
runState.ForcedNPCPending = runState.ForcedNPCPending or {}
```

Surface:

- `runtime.data.cache.currentRun.get(name)`
- `runtime.data.cache.currentRun.clear(name)`

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
