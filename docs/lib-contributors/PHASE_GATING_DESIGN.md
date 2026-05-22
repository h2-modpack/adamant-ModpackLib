# Phase Gating Design

This note captures the intended phase-gating shape for the host/store and
draw/state/actions/services split. It is an audit target for implementation,
not a description of the current live behavior.

## Goal

Enforce the author contract without adding meaningful draw-path overhead.

- Outside draw callbacks, runtime `store` access is open and draw-phase objects
  are closed.
- During a module draw callback, `draw`, `state`, `actions`, and `services` are
  open for that module, and that module's own `store` is closed.
- Other modules' stores remain open. This preserves draw-safe integration
  queries where one module invokes another provider and the provider reads its
  own committed store.

## Phase State

Use one lightweight Lib phase module with one active owner token:

```lua
local activeDrawOwner = nil
```

Do not add a depth counter. Draw is expected to be single-threaded and
non-reentrant. Nested draw entry is an invariant violation.

Target API:

```lua
phase.enterDraw(owner, context)
phase.leaveDraw(owner, context)

phase.requireAnyDraw(context)
phase.requireOwnerDraw(owner, context)
phase.requireRuntime(owner, context)
```

Rules:

- `requireAnyDraw`: `activeDrawOwner ~= nil`
- `requireOwnerDraw`: `activeDrawOwner == owner`
- `requireRuntime`: `activeDrawOwner ~= owner`

Policy ids should stay broad:

- `phase.invalid_ui_access`
- `phase.invalid_runtime_access`
- `phase.nested_draw`
- `phase.invalid_leave`

Use static context strings such as `"state.get"` or
`"draw.widgets.checkbox"`. Avoid dynamic message construction unless the check
fails.

## Owner Token

Each module host gets one private token during host construction:

```lua
local phaseOwner = {}
```

The token is captured by:

- the author-facing runtime `store`
- draw `state`
- draw `actions`
- draw `services`
- the host draw runner

The token is not public API.

## Draw Entry

`host.drawTab()` and `host.drawQuickContent()` are the only sanctioned UI phase
entrypoints.

Target shape:

```lua
local function runDraw(context, callback)
    phase.enterDraw(phaseOwner, context)
    local ok, result = pcall(callback, uiPhase.draw, uiPhase.state, uiPhase.actions, uiPhase.services)
    phase.leaveDraw(phaseOwner, context)
    if not ok then error(result, 0) end
    return result
end
```

The real implementation must be cleanup-safe: `leaveDraw` must run even when
the author callback errors.

## Draw Object

`draw` remains a singleton. Gate only methods that execute sanctioned draw
work:

- `draw.widgets.*`: `phase.requireAnyDraw("draw.widgets.X")`
- `draw.nav.*`: `phase.requireAnyDraw("draw.nav.X")`

Do not wrap or gate raw `draw.imgui` table access. Raw ImGui cannot be
comprehensively enforced without wrapping the entire ImGui API, and that is not
worth the complexity or draw-path cost.

## Draw State

`state` is owner draw-scoped.

Gate top-level methods:

- `state.get`
- `state.read`
- `state.write`
- `state.resetAll`

Do not return refs owned by raw `stagedState`. Create cached refs and table
handles against a gated owner/backend.

Scalar field owner:

```lua
owner.read = function(alias)
    phase.requireOwnerDraw(phaseOwner, "state.field:read")
    return stagedState.read(alias)
end

owner.write = function(alias, value)
    phase.requireOwnerDraw(phaseOwner, "state.field:write")
    return stagedState.write(alias, value)
end

owner.reset = function(alias)
    phase.requireOwnerDraw(phaseOwner, "state.field:reset")
    return stagedState.reset(alias)
end

owner.getAliasSchema = stagedState.getAliasSchema
```

Table handle backend:

```lua
readRoot = function(root)
    phase.requireOwnerDraw(phaseOwner, "state.table:read")
    return rawStagedReadRoot(root)
end

writeRoot = function(root, value)
    phase.requireOwnerDraw(phaseOwner, "state.table:write")
    return rawStagedWriteRoot(root, value)
end
```

This covers:

- cached `state.get("Alias")` scalar fields
- cached table handles
- cached table-cell fields from `rows:get(index, alias)`
- `rows:count/read/write/reset/append/insert/remove/clear/snapshot/snapshots`

There is no public row-handle API, so no row-handle surface needs gating.

## Actions

`actions` is owner draw-scoped.

Gate:

- `actions.get`
- `actions.hasAny`
- cached action ref `:stage`
- cached action ref `:read`
- cached action ref `:clear`
- cached action ref `:has`

Prefer making `ui_actions.lua` own gated draw refs over changing the raw
`action_buffer` contract. Commit actions stay phase-independent.

## Services

`services` is owner draw-scoped.

Gate:

- `services.log`
- `services.logIf`
- `services.isHostEnabled`
- `services.invokeIntegration`

`services.invokeIntegration(...)` may call another module's provider. That
provider can read its own `store` because runtime gating is owner-specific,
not global.

## Store

`store` is owner runtime-scoped.

Gate top-level methods:

- `store.get`
- `store.read`

Do not return refs owned by raw `persistentState`. Create cached refs and table
handles against a gated read-only owner/backend.

Scalar field owner:

```lua
owner.read = function(alias)
    phase.requireRuntime(phaseOwner, "store.field:read")
    return persistentState.read(alias)
end

owner.getAliasSchema = persistentState.getAliasSchema
```

Table backend:

```lua
readRoot = function(root)
    phase.requireRuntime(phaseOwner, "store.table:read")
    return rawPersistentReadRoot(root)
end
```

Store refs remain read-only.

## Internal State

Do not gate raw internals in the first pass:

- raw `persistentState`
- raw `stagedState`
- raw `actionBuffer`
- host lifecycle internals

Lifecycle, commit, reload, mutation sync, logging, and framework paths
legitimately use these surfaces outside author draw rules. The phase contract
belongs to author-facing surfaces.

## Host Methods

Do not phase-gate full lifecycle host methods in the first pass. Full `host` is
framework/internal and is not passed to module draw callbacks.

Possible later hardening:

- `host.read`
- `host.writeAndFlush`
- `host.stage`
- `host.flush`
- `host.reloadFromConfig`
- `host.resync`
- `host.resetAll`
- `host.commitIfDirty`
- `host.setEnabled`
- `host.setDebugMode`

Leave this out until the author-facing gates are implemented and tested.

## Performance Rules

- No allocations during normal draw calls.
- Phase objects are created once at host construction.
- Store, state, and action refs are cached by alias/key.
- Table handles are cached by alias.
- Table-cell fields are cached by row/alias as today.
- Each gate is one branch:

```lua
if activeDrawOwner ~= owner then
    logging.violate(...)
end
```

or:

```lua
if activeDrawOwner == owner then
    logging.violate(...)
end
```

## Test Plan

Minimum focused tests:

- `store.read/get` work outside draw.
- Same-owner `store.read/get` fail inside that host draw.
- Other-owner `store.read/get` work during a different host draw.
- `state.read/write/get/resetAll` fail outside draw.
- Cached `state.get("Alias")` field fails outside draw.
- Cached table handle fails outside draw.
- Cached table-cell field from `rows:get(...)` fails outside draw.
- `actions.get/hasAny` fail outside draw.
- Cached action ref fails outside draw.
- `services.*` fail outside draw.
- `draw.widgets.*` and `draw.nav.*` fail outside draw.
- Draw callback errors clear phase.
- Nested draw entry fails explicitly.

## Implementation Verdict

This is worth implementing only if it stays narrow. The target is one cheap
branch per sanctioned author-facing operation, with no phase awareness pushed
into raw storage or lifecycle internals.
