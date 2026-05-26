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

Shared cache:

- live cross-module read models
- owner and reader access are declared on module definitions
- owner writes are immediate and non-persistent
- reader access is runtime/draw safe
- tables are copied once on write and exposed as cached recursive read-only
  views on object reads
- table-shaped shared cache should be wrapped by module-level semantic helpers
  when consumers need repeated inner reads, so nested layout does not leak
  across call sites

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
    GodAvailability = {
        domain = "shared",
        id = "run-director.god-availability",
        access = "reader",
        fallback = {
            active = false,
            available = {},
        },
    },
}
```

Runtime access:

```lua
store.cache.persistent.set("RecordingReady", true)
local recordingReady = store.cache.persistent.read("RecordingReady")

local runScratch = store.cache.currentRun.get("RunScratch")
runScratch.seen = true

local availability = store.cache.shared.read("GodAvailability")
```

Draw access:

```lua
local availability = state.cache.shared.read("GodAvailability")
```

## Implementation Rule

Keep domain logic in the cache-domain files:

- `persistent_cache.lua`
- `current_run_cache.lua`
- `shared_cache.lua`

Keep author-facing phase adapters in:

- `adapters/data_cache.lua`

Do not reintroduce root string dispatchers or host-level cache helpers. If a
new cache operation is needed, add it to the specific domain facade where the
phase and ownership rules are obvious.

## Shared Cache Notes

Shared owner declarations are staged during host construction and installed
during activation. Installation returns a receipt so activation rollback and hot
reload replacement stay transaction-shaped with the other host capabilities.

Same-frame shared-cache visibility follows host draw order. A write during one
module's draw may be visible to later modules in that same frame and not visible
to earlier modules until the next frame.
