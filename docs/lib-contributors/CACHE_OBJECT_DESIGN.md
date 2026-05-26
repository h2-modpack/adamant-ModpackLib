# Cache Design

Contributor note for the managed cache implementation.

Cache is declared on module definition and exposed through the runtime store
surface:

- runtime code uses `store.cache`
- draw code does not receive cache domains

The author host does not expose a separate cache namespace. Cache stays under
the data-access model instead of becoming a host capability.

## Domains

Current-run cache:

- mutable table buckets
- follows the active `CurrentRun`
- runtime-only through `store.cache.currentRun`
- inaccessible from draw state
- backed by one Lib-owned root on `CurrentRun`

Runtime-owned storage replaces the old persistent-cache use case. If a module
needs a value that runtime writes and UI reads, declare managed storage with
`mode = "runtime"` and access it through `store.runtime` plus draw `state`.

Cross-module read models are not cache domains. They are declared through
`host.shared.data.*` and implemented by the shared subsystem.

## Access Shape

Declarations:

```lua
cache = {
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
local runScratch = store.cache.currentRun.get("RunScratch")
runScratch.seen = true
```

## Implementation Rule

Keep domain logic in the cache-domain files:

- `current_run_cache.lua`

Keep author-facing runtime adapters in:

- `adapters/data_cache.lua`

Do not reintroduce root string dispatchers or host-level cache helpers. If a
new cache operation is needed, add it to the specific domain facade where the
phase and ownership rules are obvious.

## Shared Data Boundary

Shared data uses the same `store`/draw `state` access model, but its
declaration and activation lifecycle belong to `core/shared`. Keep that
boundary intact so cache remains module-local runtime scratch state and shared
remains cross-module cooperation.
