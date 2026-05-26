# Storage Type Persistence Boundary

Future contributor note. This is not an accepted implementation plan.

## Context

Managed storage tables are well isolated at the module author surface:

```lua
local rows = state.get("Tiers")
rows:read(rowIndex, "Limit")
rows:write(rowIndex, "Limit", 5)
rows:append(...)
rows:remove(...)
```

That surface could survive a persistence backend change. The weaker boundary is
inside Lib: persistent and staged state currently assume every persisted storage
root maps to one config key.

Current shape:

```text
author table handle
  -> staged/persistent state
    -> storage table normalization/helpers
      -> storageConfig.readValue(root._storageKey)
      -> storageConfig.writeValue(root._storageKey, value)
```

For `type = "table"`, this means Chalk/config persistence stores one table
value under the table root alias. It does not flatten rows or cells.

## Issue

The one-root-one-key assumption is simple, but it leaks persistence layout into
`module_state/persistent` and `module_state/staged`.

If table storage ever needs a different backing layout, such as:

```text
Tiers.__count
Tiers.1.Enabled
Tiers.1.Limit
Tiers.2.Enabled
Tiers.2.Limit
```

then the change is not isolated to `storage/table.lua`. It would also affect:

- persisted hydration
- staged flush
- dirty snapshot capture
- rollback restore
- stale key cleanup when row counts shrink
- migration from old root-table entries

The author API protects modules from this, but the Lib internal boundary is not
as narrow as it could be.

## Possible Future Boundary

Move persisted layout behind storage-type behavior:

```lua
storageType.readPersisted(root, backend)
storageType.writePersisted(root, backend, value)
storageType.capturePersisted(root, backend)
storageType.restorePersisted(root, backend, snapshot)
```

Then:

- scalar storage types read and write one key
- packed storage types read and write one key
- table storage can still read and write one key today
- table storage could later switch to flattened keys without changing staged
  state or persistent state orchestration

Staged state can continue storing full normalized root values in memory. The
storage type would only own how that root value maps to persistent config.

## Tradeoffs

Benefits:

- makes storage backend layout a storage-type concern
- makes flattened table persistence possible behind the existing table handle API
- keeps rollback and snapshot logic explicit per storage type
- reduces future blast radius if table persistence changes

Costs:

- more ceremony for scalar storage types
- more interface surface between storage and module state
- rollback/snapshot behavior becomes storage-type code instead of one generic
  root-value path

## Current Recommendation

Do not change this now. Whole-root table persistence is acceptable for current
table sizes and commit frequency.

Keep this note as a reminder: if a storage type may require special backend
layout, put persistence encode/decode behind the storage type before optimizing
the backend.
