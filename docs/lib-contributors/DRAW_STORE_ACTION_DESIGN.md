# Draw, Store, Actions, And Services Redesign

## Purpose

This note records the target shape for the next storage and draw API cleanup.
It is an audit document for the migration, not a description of the current
public API.

The design separates runtime and draw phases without hiding every concept
behind one broad facade. Runtime code receives runtime objects. Draw code
receives draw-only objects. Each object has a narrow job and can eventually be
phase-gated at its own boundary.

## Target Callback Shape

Runtime callbacks receive module capability and committed data surfaces:

```lua
function module.onSettingsCommitted(host, store, commit)
end

function module.registerHooks(host, store)
end
```

Draw callbacks receive immediate UI render helpers, editable UI data, staged UI
actions, and a narrow draw-safe service surface:

```lua
function ui.drawTab(draw, data, actions, services)
end

function ui.drawQuickContent(draw, data, actions, services)
end
```

The phase boundary is the author-facing rule:

- `host` is the declaration, activation, and runtime capability authority; it
  is not a draw-phase object.
- `store` is the committed runtime data object; it is not a draw-phase object.
- `draw`, `data`, `actions`, and `services` are draw-phase objects.
- `store` is not available inside draw callbacks.
- `draw`, `data`, `actions`, and `services` are not available outside the
  active draw callback.

Phase enforcement can come after migration, but the API should be shaped so
that enforcement is natural. Cached draw-phase objects may exist as Lua
values, but calling any of their methods after the draw callback closes should
throw a clear phase error.

## Runtime Objects

### `host`

`host` is the module capability expression object. It owns module authority
before activation, during activation, and in runtime callbacks. Its capability
namespaces include:

- hooks
- integrations
- overlays
- mutations
- cache
- logging
- activation and host identity

`host` should not be passed to draw callbacks. If draw code needs diagnostic
logging or read/query module services, expose those through the draw-phase
`services` object instead of exposing the full host.

### `store`

`store` is the committed runtime data adapter. It should expose a storage-ref
factory rather than broad read/write/table functions:

```lua
local enabled = store.get("Enabled")

if enabled:read() then
    host.log("Enabled")
end
```

Runtime `store` should stay read-oriented. Runtime cache writes belong to
`host.cache.persistent`, while UI-staged edits belong to draw `data`.

## Draw Objects

### `draw`

`draw` is the immediate UI rendering service. It owns things that perform draw
work or are direct draw helpers:

- `draw.imgui`
- `draw.widgets`
- `draw.nav`

`draw.imgui` should eventually be a gated proxy. If raw ImGui is exposed
without gating, it becomes the loophole in the draw-phase contract.

### `data`

`data` is the editable draw-time data adapter. It is closer to the model side
of the UI than to the view side, so the public name is `data`, not `view`.

```lua
local enabled = data.get("Enabled")

if enabled:read() then
    enabled:write(false)
end
```

`data` uses the same conceptual storage grammar as `store`, but it reads and
writes the staged UI state for the active draw callback.

### `actions`

`actions` is the draw-time staged intent service. Actions are deferred UI
commands that runtime commit code can process after staged data is committed.
They are not logging and they are not a replacement for ordinary data writes.

```lua
local reset = actions.get("Reset")

draw.widgets.button("Reset", {
    action = reset,
})
```

Runtime code consumes action snapshots through the commit object:

```lua
function module.onSettingsCommitted(host, store, commit)
    local reset = commit.actions.get("Reset")

    if reset:read() == true then
        -- apply the deferred command
    end
end
```

### `services`

`services` is the draw-safe module service surface. It exists because draw code
can need narrow read/query services without needing the full host authority.

Keep this surface flat while it stays small:

```lua
services.log(fmt, ...)
services.logIf(fmt, ...)
services.isHostEnabled()
services.invokeIntegration(id, methodName, fallback, ...)
```

`services` is not a trimmed host. It should not expose registration,
activation, lifecycle mutation, storage mutation, hook declaration, overlay
declaration, or mutation declaration APIs.

Do not add a method to `services` merely because draw code wants access to a
host capability. Add it only when the operation is draw-safe, narrow,
read/query/logging oriented, and cannot mutate module lifecycle, declarations,
storage, or activation state.

Do not add `setEnabled` until there is a concrete module-draw use case. Enabled
transitions are currently Framework/fallback shell concerns, not inner module UI
concerns.

## Storage Refs

`store` and `data` should share a storage-ref vocabulary. The phase decides
which backend is read or written; the addressing grammar stays consistent.

Root scalar or packed storage returns a leaf ref:

```lua
local enabled = data.get("Enabled")

enabled:read()
enabled:write(true)
enabled:reset()
enabled:schema()
enabled:controlId()
```

Row-list storage returns a row-list object:

```lua
local pools = data.get("ApolloBanPools")

local count = pools:count()
local bans = pools:get(rowIndex, "Bans")

bans:read()
bans:write(false)
```

The row-list object owns table-wide operations:

- `count()`
- `read(index, cellAlias)`
- `write(index, cellAlias, value)`
- `reset(index, cellAlias)`
- `get(index, cellAlias)`
- `append(rowValues)`
- `insert(index, rowValues)`
- `remove(index)`
- `clear()`
- `snapshot(index)`
- `snapshots()`

Runtime `store` may expose only the subset that is valid for committed data and
runtime-read policy. Draw `data` exposes the editable staged subset.

Table cells are path refs, not root aliases. Cell aliases stay scoped to the
row schema; they do not become globally unique root aliases. If stable row
identity becomes necessary later, add an explicit row-id concept instead of
overloading positional row indexes.

Table owners cache row-cell control ids and refresh those caches after
structural row edits such as append, insert, remove, and clear. Root refs use
the root alias; row-cell refs include the table alias, positional row index,
and cell alias. Widgets read `field:controlId()` when building ImGui ids.

## Widgets

Widgets stay under `draw` because they are first-party render helpers:

```lua
draw.widgets.checkbox(data.get("Enabled"), {
    label = "Enabled",
})

draw.widgets.dropdown(data.get("Mode"), {
    label = "Mode",
    values = { "Default", "Custom" },
    action = actions.get("ModeChanged"),
})

draw.widgets.button("Reset", {
    action = actions.get("Reset"),
})
```

Widget rules:

- Value widgets take data refs, not raw sessions, raw stores, or table handles.
- Value widgets directly edit the passed data ref by default.
- Any interactive widget may optionally stage an action.
- Buttons are command widgets, not the only action-aware widgets.
- Raw `draw.imgui` remains available for custom UI.

This makes widgets the sanctioned first-party bridge across draw, data, and
actions. Custom UI can still use the draw-phase objects explicitly.

## What Not To Do

Do not collapse runtime and draw data into a polymorphic `read(...)` API:

```lua
-- Avoid
host.read("Enabled")
```

That hides the phase boundary and makes the same call mean different backends
depending on timing.

Do not pass `host` into draw callbacks:

```lua
-- Avoid
function ui.drawTab(draw, data, actions, host)
end
```

Draw code should not get the full module capability object. Add narrow
draw-phase services when draw code needs them:

```lua
function ui.drawTab(draw, data, actions, services)
    if services.invokeIntegration("run-director.god-availability", "isActive", false) then
        services.logIf("God Pool filtering is active")
    end
end
```

Do not make action staging the backend for ordinary widget value edits. A
checkbox click should change the checkbox data ref. Optional actions are for
extra deferred intent.

## Migration Plan

1. Add draw-phase `services` with `log`, `logIf`, `isHostEnabled`, and
   `invokeIntegration`, then remove `draw.host` from the draw context.
2. Extract actions from session into a first-class draw `actions` object.
3. Add `store.get(...)` and `data.get(...)` storage-ref factories beside the
   old APIs.
4. Make widgets accept storage refs and optional action refs. Action support
   should be broad, not button-only.
5. Change draw callbacks to `drawTab(draw, data, actions, services)` and
   `drawQuickContent(draw, data, actions, services)`.
6. Reassess module ergonomics after the draw/data/actions/services split.
7. Port modules to storage refs and row-list objects module by module.
8. Retire old author-facing session/store APIs.
9. Add phase gating for `store`, `draw`, `data`, `actions`, and `services`.

## Audit Checklist

Use this checklist while migrating:

- No `draw.host` in module UI.
- The draw context does not expose the author host.
- No `draw.session` in module UI.
- Draw-time logging uses `services.log` or `services.logIf`.
- Draw-time integration queries use `services.invokeIntegration`.
- `services` does not expose host registration, lifecycle, or mutation APIs.
- New `services` methods satisfy the draw-safe narrow read/query/logging rule.
- No widget receives a raw session or raw store.
- No widget receives a table handle instead of a data ref.
- Action support is not button-only.
- Table cells are addressed as path refs, not root aliases.
- `store` is not used inside draw callbacks.
- `draw`, `data`, `actions`, and `services` are not used outside draw
  callbacks.
- `draw.imgui` is included in phase enforcement or explicitly documented as a
  borrowed raw escape hatch.
- Runtime callbacks use `host` for capabilities and `store` for committed data.
- Draw callbacks use `draw` for rendering, `data` for staged UI data, and
  `actions` for deferred UI intents, and `services` for draw-safe module
  services.
