# Runtime/UI Backend Restructuring

Future contributor design spec. This is an internal cleanup direction for Lib's
module creation, activation, and author-facing phase surfaces.

This document is intentionally not about controls or composite UI primitives.
Controls may benefit from this cleanup later, but they are out of scope here.

## Status

Lib-side implementation complete.

The implementation now uses the clean breaking API shape:

- `createModule(...)` accepts identity fields only.
- `createModule(...)` returns `module, err`.
- Runtime author callbacks receive explicit runtime data through callback
  arguments instead of using the old returned store.
- Draw author callbacks receive `ui, host`.
- Storage, cache, actions, commit observers, shared declarations,
  mutations, overlays, hooks, and draw callbacks are declared on `module`
  before activation.
- Definition preparation and structural fingerprinting happen during
  `module.activate()`, after declarations are complete.

The remaining work is first-party module migration and public author-doc
updates after those module ports provide final examples.

## Current Tension

The old `createModule(...)` API did two different jobs:

1. It creates the module identity and lifecycle object.
2. It accepts the module's declarative capability surfaces:
   storage, cache, actions, draw callbacks, and commit callback.

That makes the module entrypoint browsable, but it also means definition
preparation happens before the module object exists as the declaration
authority. This has several second-order effects:

- Structural fingerprinting is tied to creation-time options.
- `storage`, `cache`, and `actions` are shaped differently from hooks, shared,
  overlays, and mutations even though all are module-owned capabilities.
- Runtime callbacks usually close over `host` and `store` from outer scope.
- Draw callbacks use phase objects directly, while runtime callbacks rely more
  on ambient objects.
- The author-facing words `store` and `state` expose implementation history
  more than the runtime/UI phase distinction.

None of this was a correctness bug. It was an API coherence issue that became
more visible as Lib grew.

## Goals

- Make the object returned by `createModule(...)` the `module` declaration and
  activation facade.
- Reserve `host` for a small unphased callback utility projection.
- Make callback execution use explicit phase objects rather than ambient
  captured author objects.
- Rename author-facing data surfaces around phases:
  - runtime callbacks use `runtime.data`
  - draw callbacks use `ui.data`
- Keep storage mechanics internally split between persistent runtime state and
  staged UI state.
- Move data-like declarations from `createModule(...)` onto module capability
  namespaces.
- Finalize the structural definition at activation, after declarations are
  complete.
- Keep the migration incremental and testable.

## Non-Goals

- Do not design controls here.
- Do not redesign table storage semantics here.
- Do not remove phase gating.
- Do not remove activation receipts.
- Do not make the returned `module` a general runtime object after activation.
- Do not make callback `host` a lifecycle mutation surface.
- Do not expose lifecycle host internals to module authors.
- Do not break the next release solely to achieve naming symmetry.

## Target Author Model

The desired long-term shape is:

```lua
local module = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = "run-director",
    id = "Example",
    name = "Example",
})

module.data.define({
    { type = "bool", alias = "EnabledFeature", default = false },
    { type = "int", alias = "RuntimeCount", mode = "runtime", default = 0 },
})

module.actions.define({
    Reset = function(host, uiData, runtimeData, value)
        uiData.write("EnabledFeature", false)
        host.logIf("reset from UI")
    end,
})

module.cache.define({
    Scratch = {
        domain = "currentRun",
        key = "scratch",
        factory = function()
            return {}
        end,
    },
})

module.shared.data.owner("Availability", {
    id = "example.availability",
    default = {},
})

module.shared.listen("example.events", "changed", function(host, runtime, payload)
    host.log("changed: %s", tostring(payload))
end)

module.mutation.patch(function(host, runtime, plan)
    if runtime.data.read("Enabled") then
        -- build plan
    end
end)

module.ui.tab(function(host, ui)
    ui.draw.widgets.checkbox(ui.data.get("EnabledFeature"))
    ui.actions.trigger("Reset")
end)

module.activate()
```

The exact names are provisional. The important shape is:

- declarations live on `module`
- callbacks receive the small unphased `host` utility projection first
- runtime execution gets a `runtime` phase object after `host`
- draw execution gets a `ui` phase object after `host`
- long-lived returned `store` is no longer the main author concept

## Module And Host Roles

`module` should mean "module declaration and activation authority."

Before activation, module may declare capabilities:

- `module.data.define(...)`
- `module.actions.define(...)`
- `module.cache.define(...)`
- `module.shared.data.owner(...)`
- `module.shared.data.reader(...)`
- `module.shared.listen(...)`
- `module.hooks.wrap(...)`
- `module.overlays.createLine(...)`
- `module.mutation.patch(...)`
- `module.ui.tab(...)`
- `module.ui.quickContent(...)`
- `module.activate()`

After activation begins, declaration capabilities close.

Runtime and draw logic should not treat `module` as the object they use for
normal work. They should receive phase objects from their callback boundary.

`host` should become the small unphased callback utility projection. It is not
the lifecycle module object. Candidate surface:

```lua
host = {
    getHostId = function() end,
    getModuleId = function() end,
    getPackId = function() end,
    getMeta = function() end,
    log = function(...) end,
    logIf = function(...) end,
    isEnabled = function() end,
}
```

Keep lifecycle mutation off this projection. In particular, `setEnabled` should
remain a Framework/fallback/lifecycle operation unless a concrete module-author
use case proves otherwise.

`host.isEnabled()` should mean the committed/effective module enabled state.
It should not mean the staged UI checkbox value currently being edited.

Equivalent intent:

```lua
host.isEnabled() == (runtime.data.read("Enabled") == true)
```

In UI callbacks, authors should use `ui.data.read("Enabled")` when they need
the staged UI value. Keep `host.isEnabled()` because it communicates committed
runtime intent clearly in hooks, shared listeners, mutation builders, and other
runtime-shaped callbacks.

## Phase Objects

`runtime` and `ui` should become the author-facing phase objects.

The long-term rule should not be:

```text
store is runtime-gated
state/actions/draw are draw-gated
```

The long-term rule should be:

```text
runtime works in runtime callbacks
ui works in UI callbacks
```

This means phasing moves conceptually up to the callback object. Authors should
not need to learn which lower-level child surface owns which phase rule.

Implementation still needs lightweight gates on the child facades because
authors can cache escaped references:

```lua
local escapedUi

module.ui.tab(function(host, ui)
    escapedUi = ui
end)

escapedUi.data.read("Enabled") -- rejects outside a UI callback
```

The intended layering is:

- `phaseGate` remains the central internal phase service.
- `runtime` and `ui` own the author-facing phase contract.
- Thin phase facades like `runtime.data`, `ui.data`, `ui.actions`, and
  `ui.draw` perform one cheap phase check before delegating.
- Stateless subsystem logic remains phase-agnostic.
- Subsystems should not each invent independent phase semantics.

In other words, phase enforcement remains real, but phase meaning should be
expressed through `runtime` and `ui`, not scattered across storage, actions,
shared data, widgets, and nav as separate author concepts.

### Runtime

`runtime` is the non-draw execution object. It should be valid in hooks,
mutation builders, shared listeners, overlay projections when appropriate, and
other sanctioned runtime callbacks.

Candidate surface:

```lua
runtime = {
    data = runtimeData,
    cache = runtimeCache,
    shared = runtimeShared,
}
```

`runtime.data` replaces author-facing `store` in runtime callbacks.

`runtime.data` may still be backed internally by persistent state and store
adapters. The external name should describe the phase, not the storage
implementation.

### UI

`ui` is the draw execution object. It should be valid only while a draw callback
is running.

Candidate surface:

```lua
ui = {
    draw = draw,
    data = uiData,
    actions = uiActions,
    shared = uiShared,
}
```

`ui.data` replaces author-facing `state` in UI callbacks.

`ui.draw` owns ImGui, widgets, and nav. It remains the render surface.

`ui.actions` remains the UI intent/action staging surface.

## Data Declarations

Storage should move from `createModule({ storage = ... })` to:

```lua
module.data.define({
    -- storage schema
})
```

This makes storage a module-declared capability like hooks, overlays, shared, and
mutations. It also gives the future system a single declaration window:

```text
create module
declare capabilities
activate module
```

Built-in Lib storage remains injected at finalization:

- `Enabled`
- `DebugMode`
- `AdamantFramework_PackRestoreSnapshot`

Even if user storage becomes declaration-time, every module still has a data
system because built-in lifecycle fields exist.

## Action Declarations

Actions should move from `createModule({ actions = ... })` to:

```lua
module.actions.define({
    Reset = function(host, uiData, runtimeData, value)
        -- command body
    end,
})
```

The exact handler parameters need final confirmation. The current action model
already treats actions as the UI-to-runtime command bridge. The cleanup should
preserve that idea:

```text
draw callback stages action
action handlers run after draw callback
staged UI data flushes
commit callbacks run
```

Potential handler shape:

```lua
function(host, uiData, runtimeData, value)
end
```

Actions should not receive full `ui`, full `runtime`, draw, widgets, nav, or
future controls. They should be simple edge mappers from UI intent into staged
UI data and runtime-owned data:

- `uiData` is the staged UI data surface.
- `runtimeData` is the runtime-owned/committed data surface.
- `host` is only the small unphased utility projection for identity, logging,
  and enable checks.
- `value` is the explicit action payload staged by draw code.

This keeps controls and rendering in the UI layer while still supporting
recording-style commands that need to write runtime-owned storage.

## Commit Callback

`onSettingsCommitted` should become `onCommit`.

The current name leaks the staging implementation and is too narrow for the
broader transaction model. The callback observes a committed module
transaction, not merely "settings":

```text
draw callback stages UI data and actions
action handlers run
staged UI data flushes
shared events queued by actions flush
onCommit runs
```

Target shape:

```lua
module.onCommit(function(host, runtime, commit)
end)
```

The previous `onSettingsCommitted` spelling is retired. Do not add new
compatibility paths for it; route commit observers through `module.onCommit`.

## Cache Declarations

Current-run cache should move from `createModule({ cache = ... })` to:

```lua
module.cache.define({
    RunScratch = {
        domain = "currentRun",
        key = "scratch",
        factory = function()
            return {}
        end,
    },
})
```

Only lifecycle-linked cache belongs here. Runtime/UI storage now owns ordinary
persistent or runtime-write data.

Current cache scope:

- `currentRun` stays a runtime-only cache tied to game lifecycle data.
- Persistent cache has been absorbed by runtime-owned storage.
- Shared data lives under `host.shared.data` and phase data adapters.

## Draw Declarations

Draw callbacks should move out of `createModule(...)` into:

```lua
module.ui.tab(function(host, ui)
end)

module.ui.quickContent(function(host, ui)
end)
```

This removes the special status of draw callbacks as creation-time options.
They become declarations that are finalized at activation with the rest of the
module surface.

Internally, the draw facade can remain singleton-like. The per-host phase object
is the UI object that binds draw, data, actions, shared access, and logging for
that host and phase.

## Mutation Callbacks

Current mutation callback:

```lua
module.mutation.patch(function(plan, host, store)
end)
```

Target:

```lua
module.mutation.patch(function(host, runtime, plan)
end)
```

The mutation lifecycle already calls through host adapters and receives the
host-owned store. This is mostly a callback-boundary cleanup:

- no ambient `store`
- no declaration/lifecycle `module` in the callback
- mutation builders receive the runtime data surface plus the small utility
  host projection

## Shared Events

Current listener callback:

```lua
module.shared.listen(id, eventName, function(payload)
end)
```

Target:

```lua
module.shared.listen(id, eventName, function(host, runtime, payload)
end)
```

Shared events are runtime events. Delivery should remain outside draw phase.
The runtime phase object makes listener dependencies explicit without requiring
closures over `module` and `store`.

Emits remain:

```lua
module.shared.emit(id, eventName, payload)
ui.actions.emit(id, eventName, payload)
```

Long term, `ui.actions.emit(...)` can remain shorthand for staging an event
from draw without declaring a named action first.

## Hooks And Overlays

Hooks and overlays are the hardest migration points.

Hooks currently use callback shapes dictated by game/ModUtil call signatures.
A future shape might be:

```lua
module.hooks.wrap(path, key, function(host, runtime, base, ...)
end)
```

But this changes the most sensitive author callback shape in Lib. It should not
be bundled into the first cleanup slice.

Overlays already own their own retained projection model and callback kinds:

- `onCommit`
- `onInterval`
- `afterHook`

These can receive runtime/UI projections later if a real use case needs it.
The first cleanup should preserve overlay semantics and avoid forcing them into
the normal draw callback model.

## Structural Fingerprint

Moving declarations out of `createModule(...)` means structural fingerprinting
must move from creation to activation finalization.

This is not a Framework discovery blocker. Framework already resolves modules
through the live-module registry, and the live-module registry only publishes
activated hosts. The invariant to preserve is:

```text
only finalized, activated modules are published as live modules
```

So the fingerprint comparison can move fully into the activation path. Activation
should finalize declarations, compute the candidate structural fingerprint,
compare it against the previous live module's finalized fingerprint, then either
continue with receipt installation or request/reject the structural reload.

Current flow:

```text
createModule(opts)
  build definition input
  prepare definition
  create persistent/staged state
  create ManagedModule
module.activate()
  install receipts
```

Target flow:

```text
createModule(identity opts)
  create module/lifecycle record
  create empty declaration buckets
module.data.define(...)
module.actions.define(...)
module.cache.define(...)
module.ui.tab(...)
module.activate()
  finalize definition
  prepare storage/cache/action metadata
  create persistent/staged state
  create runtime/UI phase objects
  compute structural fingerprint
  compare previous fingerprint
  install receipts transactionally
```

Structural fields should include:

- identity fields relevant to Framework discovery
- storage schema
- cache declarations that alter managed runtime cache contracts
- quick-content presence

Actions should remain validated and ordered but not structural unless a reload
bug proves otherwise.

Shared data declarations are currently non-structural. Keep that unless
Framework or profile behavior begins depending on them.

## Activation Finalization

Activation should become the only place that turns declarations into live
runtime objects.

Activation should own:

- final definition preparation
- structural fingerprint comparison
- structural reload request/rejection
- store/runtime data creation
- UI data/action creation
- shared data/event installation
- hook installation
- overlay installation
- mutation sync
- fallback UI installation
- rollback receipts
- old-module retirement

The current `managed_module_activation.lua` already acts as an installation transaction.
The future shape should expand it into the central finalization boundary rather
than adding declaration finalization to scattered subsystems.

`managed_module.lua` should remain the facade and lifecycle object. It should not become
the place where every subsystem finalizes itself inline.

## Internal Naming Direction

Internal names should make the phase split clear:

- persistent implementation can remain `persistentState`
- staged implementation can remain `stagedState`
- author-facing runtime facade should become `runtimeData` or `runtime.data`
- author-facing draw facade should become `uiData` or `ui.data`
- action queue/buffer naming should stay implementation-facing
- module registry should stay a hot-reload registry, not a dependency bus
- author-facing declaration facade should move toward `module`
- callback utility projection should use `host`

Avoid using `author` to mean both runtime author surfaces and draw-time author
surfaces. Prefer:

- `runtime_*` for runtime callback surfaces
- `ui_*` for draw callback surfaces
- `module_*` or `author_module_*` for the pre-activation module author facade
- `host_*` only when the file models the internal lifecycle host or the small
  callback host projection; do not blur those two in new code

## Compatibility Status

The lib-side implementation now uses the breaking target shape rather than the
temporary compatibility shape:

- `createModule(opts)` accepts identity fields only.
- `createModule(opts)` returns `module, err`.
- `storage`, `cache`, `actions`, `drawTab`,
  `drawQuickContent`, and commit observers are declared on `module`.
- Definition preparation and structural fingerprinting happen during
  `module.activate()`, after declarations are complete.
- `onSettingsCommitted` has been retired at the host lifecycle boundary;
  `module.onCommit(...)` is the supported spelling.

Current callback shapes:

```lua
module.ui.tab(function(host, ui) end)
module.mutation.patch(function(host, runtime, plan) end)
module.shared.listen(id, eventName, function(host, runtime, payload) end)
module.actions.define({
    Reset = function(host, uiData, runtimeData, value) end,
})
```

Do not use suffix shims for callbacks whose trailing varargs are part of
the domain contract. Hooks are the main example: game callbacks often forward
arbitrary `...`, so adding runtime as a suffix would change the game callback
shape. Overlays also have callback shapes that are tied to retained projection
semantics.

The likely endgame for hooks and overlays is prefixing Lib phase/context objects
before the domain callback args:

```lua
module.hooks.wrap(path, key, function(host, runtime, base, ...)
end)

module.overlays.onInterval(name, seconds, function(host, runtime, overlay)
end)
```

That keeps the game/framework callback tail intact while still making the Lib
execution context explicit. Migrate hooks and overlays after the simpler
runtime/UI callback model proves itself.

## Suggested Migration Slices

Completed lib-side:

1. Introduce internal `runtime` and `ui` phase object factories.
2. Add module declaration buckets for data, actions, cache, commit
   observers, shared declarations, mutations, overlays, hooks, and draw
   callbacks.
3. Move definition finalization and structural fingerprinting to activation.
4. Add new public declaration methods:
   - `module.data.define`
   - `module.actions.define`
   - `module.cache.define`
   - `module.onCommit`
   - `module.ui.tab`
   - `module.ui.quickContent`

Remaining:

1. Port first-party modules.
2. Update author docs after the module ports provide final examples.
3. Revisit hooks and overlays only after the phase object model settles.

Do not start with hooks or overlays. They have special callback contracts and
should migrate after the phase object model proves itself on storage, actions,
cache, mutation, shared events, and draw callbacks.

## Risks

- Moving state creation to activation means more code must tolerate a host
  record before data objects exist.
- Fingerprinting must be relocated cleanly so structural reload decisions happen
  before any candidate module is published as the live module.
- Structural reload behavior must remain deterministic across hot reload.
- Compatibility shims can hide design mistakes if left around too long.
- Runtime/UI objects can become broad context blobs if new methods are added
  casually.

## Guardrails

- Validate broad shapes only at declaration/finalization contact points.
- After activation finalizes declarations, downstream subsystems should trust
  the prepared records.
- Keep phase objects narrow. Add methods only when the operation belongs to the
  phase.
- Do not add a method to `ui` merely because draw code wants access to a host
  capability.
- Do not add a method to `runtime` merely to avoid passing a real domain object
  to a helper.
- Do not add rendering, controls, widgets, nav, or lifecycle mutation to action
  handlers. Actions should only see `host`, `uiData`, `runtimeData`, and
  `value`.
- Keep activation receipt rollback as the source of truth for external side
  effects.
- Keep hot-reload-stable data under scoped registry buckets only.

## Open Questions

- Should callback dispatch eventually make `host.isEnabled()` unnecessary in
  more places, or is the explicit committed-state query useful enough to keep?
- How much compatibility should be kept in a 2.x release before the next major
  cleanup removes old surfaces?
