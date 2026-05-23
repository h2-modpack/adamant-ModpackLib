# Shared Cache Design

Shared cache is a cache domain for owner-published cross-module read
models. It standardizes the existing pattern where one module owns live domain
truth, publishes a cheap projection, and other modules read that projection
during runtime or draw code.

This does not replace integrations. Integrations remain the right tool for
cross-module behavior calls and event delivery. Shared cache is for live data
snapshots.

## Concept

Cache domains:

- `host.cache.currentRun`: owner-private cache with active `CurrentRun` lifetime
- `host.cache.persistent`: owner-private flat scalar cache persisted through
  Chalk-backed module config
- `host.cache.shared`: owner-published, cross-module live read model

Shared cache is live memory only. It is not store-backed, staged, flushed,
persisted, hashed, profiled, or reset as managed state.

## Provider Declaration

Declarations happen before activation:

```lua
host.cache.shared.publish("run-director.god-availability", {
    default = { active = false, available = {} },
})
```

Rules:

- `publish(id, opts)` is declaration-time only.
- `id` must be a non-empty string.
- `opts.default` is optional but recommended.
- ownership is recorded from the declaring host plugin guid.
- duplicate active publishers for the same id are invalid, except same-owner
  hot reload replacement.
- publication installs through activation receipts so failed activation rolls
  back cleanly.

## Provider Writes

The owner may write after activation through runtime host or draw services:

```lua
host.cache.shared.write(id, snapshot)
host.cache.shared.clear(id)

services.cache.shared.write(id, snapshot)
services.cache.shared.clear(id)
```

Rules:

- only the publishing owner can write or clear an id.
- `write(...)` updates the live projection immediately.
- `clear(...)` resets the live projection to the publisher default.
- writes do not flush and do not persist.
- values are deep-copied on write.

Draw services expose write and clear because ownership, not phase, determines
write authority. Owner UI code may need to update its public projection from
draw-visible staged state.

## Consumer Reads

Runtime host:

```lua
local snapshot = host.cache.shared.read(id, fallback)
```

Draw services:

```lua
local snapshot = services.cache.shared.read(id, fallback)
```

Rules:

- any host or draw services object may read.
- reads return a deep copy.
- if no active publisher exists, read returns caller fallback.
- if publisher exists but has not written, read returns publisher default when
  present, otherwise caller fallback.
- if publisher host is disabled, read returns caller fallback.
- caller fallback is used only when no active published value/default is
  available.

Draw code may read shared cache because this is live projection data, not
persistent config. Draw code may not publish new shared cache ids.

## Lifecycle

Activation:

- `publish(...)` declarations are staged before activation.
- activation installs a shared cache publication receipt.
- activation failure restores the previous publication state.
- old host retirement removes the old publication only when the old host still
  owns it.

Disable:

- disabled owners are invisible to reads.
- reads return fallback while the owner is disabled.
- re-enable makes the owner visible again with its current live value/default.

Hot reload:

- same plugin guid replacement may replace publication ownership.
- activation failure restores the previous publication.
- old host retirement must not clear a newer owner token.

## Implementation Shape

Add the implementation to the cache subsystem:

```text
core/cache/shared_cache.lua
core/cache/adapters/author_cache.lua
core/cache/00_init.lua
```

Use a hot-reload-stable registry bucket:

```lua
registry.cache.shared
```

Suggested record:

```lua
{
    id = id,
    ownerId = pluginGuid,
    ownerToken = token,
    default = copiedDefault,
    value = copiedValue,
    hasValue = boolean,
}
```

Author host cache API:

```lua
host.cache.shared.publish(id, opts)
host.cache.shared.write(id, value)
host.cache.shared.clear(id)
host.cache.shared.read(id, fallback)
```

Draw services cache API:

```lua
services.cache.shared.read(id, fallback)
services.cache.shared.write(id, value)
services.cache.shared.clear(id)
```

`services.cache.shared.publish(...)` must not exist.

## God Availability Migration

GodPool should use shared cache for its UI-facing availability read model:

```lua
host.cache.shared.publish(GOD_AVAILABILITY_ID, {
    default = { active = false, available = {} },
})
```

GodPool writes the snapshot:

- after activation
- after committed config changes
- optionally from owner draw code when staged UI changes should immediately
  update the public projection

BoonBans and BiomeControl read the projection during draw:

```lua
local snapshot = services.cache.shared.read(GOD_AVAILABILITY_ID, DEFAULT)
```

They then interpret the snapshot locally.

God availability does not need to keep using integrations once shared cache is
implemented. That is a module-level migration choice; the integration subsystem
itself remains unchanged for behavior-style cross-module APIs.
