# Cache Design

Contributor note for the managed cache implementation.

Cache is declared on module definition and exposed through the same phase
surfaces as managed storage:

- runtime code uses `store.cache`
- draw code uses `state.cache`

The author host does not expose a separate cache namespace. This keeps cache
under the data-access model instead of creating a second host capability for
the same state.

## Domains

Persistent cache:

- flat scalar values only
- survives reloads and restarts
- runtime writable through `store.cache.persistent`
- draw readable through `state.cache.persistent`
- backed by the module persistent cache store

Current-run cache:

- mutable table buckets
- follows the active `CurrentRun`
- runtime-only through `store.cache.currentRun`
- inaccessible from draw state
- backed by one Lib-owned root on `CurrentRun`

Cross-module read models are not cache domains. They are declared through
`host.shared.data.*` and implemented by the shared subsystem.

## Access Shape

Declarations:

```lua
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
}
```

Runtime access:

```lua
store.cache.persistent.set("RecordingReady", true)
local recordingReady = store.cache.persistent.read("RecordingReady")

local runScratch = store.cache.currentRun.get("RunScratch")
runScratch.seen = true
```

Draw access:

```lua
local recordingReady = state.cache.persistent.read("RecordingReady")
```

## Implementation Rule

Keep domain logic in the cache-domain files:

- `persistent_cache.lua`
- `current_run_cache.lua`

Keep author-facing phase adapters in:

- `adapters/data_cache.lua`

Do not reintroduce root string dispatchers or host-level cache helpers. If a
new cache operation is needed, add it to the specific domain facade where the
phase and ownership rules are obvious.

## Shared Data Boundary

Shared data uses the same `store`/draw `state` access model, but its
declaration and activation lifecycle belong to `core/shared`. Keep that
boundary intact so cache remains module-local runtime storage and shared remains
cross-module cooperation.
