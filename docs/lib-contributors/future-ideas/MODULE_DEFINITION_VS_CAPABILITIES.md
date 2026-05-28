# Module Definition Vs Capabilities

Future contributor note. This captures a design discussion so the boundary can
be revisited intentionally later.

Related larger cleanup proposal:
[RUNTIME_UI_BACKEND_RESTRUCTURING.md](RUNTIME_UI_BACKEND_RESTRUCTURING.md).
That proposal intentionally revisits this document's current recommendation to
keep storage, cache, actions, and draw callbacks inside `createModule(...)`.

## Current Framing

`createModule(...)` should be understood as the module's static definition
surface. It is the place for declarative data and command surfaces that shape
the author-facing `store`, draw `state`, draw `actions`, and related typed
refs.

Host calls between creation and activation should be understood as runtime
capability declarations. They install behavior into external/runtime systems
and are owned by activation receipts.

In short:

```text
createModule({...}) = static definition, data plane, command plane
host.<capability>.* = runtime capability declaration before activation
```

## Static Definition Plane

These belong in `createModule(...)` for now:

- identity/config fields
- `storage`
- `cache`
- `actions`
- `hashGroupPlan`
- draw callbacks
- `onSettingsCommitted`

This shape is intentionally browsable:

```lua
local host, store = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example",

    storage = {
        -- persistent/staged module data
    },

    cache = {
        -- Lib-managed runtime cache refs
    },

    actions = {
        ResetAll = function(host, state)
            state.resetAll()
        end,
    },

    drawTab = ui.drawTab,
})
```

The goal is not to make `createModule(...)` tiny. The goal is to make it the
complete static module definition.

## Capability Plane

These remain host declarations between creation and activation:

- hooks
- shared events
- overlays
- mutation patches
- fallback UI attachment

Those capabilities install runtime behavior or external side effects and should
continue to be managed by activation/rollback receipts:

```lua
host.hooks.wrap(...)
host.shared.listen(...)
host.overlays.add(...)
host.mutation.patch(...)
host.activate()
```

## Structural Fingerprint

Not every static definition field is structural in the same way.

Structural data-plane declarations:

- `storage`
- `cache`
- `hashGroupPlan`

These change store/state/cache shape, persistent or managed runtime data
contracts, cross-module shared data publication contracts, hash/profile
surface, or activation-visible data contracts.

Validated but behavior-hot-reloadable command declarations:

- `actions`

Actions are static and definition-like, but they do not create persisted config
state, hash/profile state, or external activation receipts. Adding or changing
an action is closer to changing draw behavior than changing storage shape.
Do not add actions to the structural fingerprint unless a concrete reload bug
shows they need that treatment.

## Revisit Criteria

Revisit this boundary if:

- `createModule(...)` becomes hard to scan because too many non-declarative
  capability calls move into it
- cache declarations start behaving like side-effectful capability installs
  rather than managed data refs
- actions gain external side effects or activation-visible declarations
- storage/state construction is redesigned around a separate builder/finalize
  lifecycle

Do not move storage out of `createModule(...)` without a larger lifecycle
redesign. Storage is the substrate for built-in enabled/debug state, store,
draw state, mutation sync, hashes, profiles, and resets.
