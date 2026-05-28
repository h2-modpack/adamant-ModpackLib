# adamant-ModpackLib API

This is the public Lib surface.

Preferred usage uses top-level module authoring helpers plus namespaces for specialized APIs:
- `lib.createModule(...)`
- `lib.createFrameworkRuntime(...)`
- `module.fallbackUi.*`
- `module.hooks.*`
- `module.overlays.*`
- `module.shared.*`
- `module.mutation.*`

Framework-owned live-host discovery, hash/profile, overlay, UI suppression, and
diagnostic controls are available from
`lib.createFrameworkRuntime("adamant-ModpackFramework")`.

## Core Model

Modules create a declaration object through `lib.createModule(...)`, declare
data/UI/runtime capabilities on that object, then call `module.activate()`.

`createModule(...)` accepts only module identity, display metadata, `config`,
and optional `modpack`. Everything else is declared through namespaces before
activation:
- `module.data.define(...)`
- `module.actions.define(...)`
- `module.cache.define(...)`
- `module.hashGroups.define(...)`
- `module.ui.tab(...)`
- `module.ui.quickContent(...)`
- `module.onCommit(...)`
- `module.hooks.*`
- `module.shared.*`
- `module.mutation.*`
- `module.overlays.*`
- `module.fallbackUi.*`

That host owns:
- `drawTab`
- optional `drawQuickContent`
- built-in module registry helpers for Framework and fallback UI

Module behavior is hosted through Lib's live module registry.

## `module.shared`

Small registry for optional cross-module cooperation. Shared has two surfaces:
event signals and owner-published read models. Both are declared after
`lib.createModule(...)` returns and before `module.activate()`.

Typical listener declaration before activation:

```lua
local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
})
if not module then return end

module.data.define(data.buildStorage())
module.ui.tab(ui.drawTab)

module.shared.listen("run-director.route-state", "routeChanged", function(host, runtime, payload)
    host.log("route changed: %s", tostring(payload.route))
end)

module.shared.data.owner("GodAvailability", {
    id = "run-director.god-availability",
    default = {
        active = false,
        available = {},
    },
})

module.activate()
```

Typical emitter:

```lua
module.shared.emit("run-director.route-state", "routeChanged", {
    route = "Apollo",
})
```

Draw callbacks emit through the post-draw action bridge:

```lua
actions.emit("run-director.route-state", "routeChanged", {
    route = state.read("Route"),
})
```

Surface:
- `module.shared.data.owner(name, { id = string, default? = value })`
- `module.shared.data.reader(name, { id = string, fallback? = value })`
- `module.shared.listen(id, eventName, callback)`
- `module.shared.emit(id, eventName, payload)`
- `actions.emit(id, eventName, payload)` from draw callbacks

Rules:
- Shared ids should describe domain behavior, not consumer names
- shared data declarations do not participate in the module structural fingerprint
- shared data writes go through `store.shared.*` or `state.shared.*`
- shared data reads return fallback when no active publisher exists
- absence means the optional notification has no listeners
- events are runtime notifications; listener order is unspecified and nested emits are queued
- listener callbacks receive `payload`
- disabled listener hosts do not receive events
- disabled emitter hosts do not emit events
- one failing listener logs and does not stop remaining listeners
- events are not replayed to late listeners
- event payloads should be small signals, not durable shared state

Use shared data for synchronous read-sharing and shared events for
notifications and coordination signals.

Shared data owner:

```lua
module.shared.data.owner("GodAvailability", {
    id = "run-director.god-availability",
    default = {
        active = false,
        available = {},
    },
})

store.shared.set("GodAvailability", {
    active = true,
    available = {
        Apollo = false,
    },
})
```

Shared data reader:

```lua
module.shared.data.reader("GodAvailability", {
    id = "run-director.god-availability",
    fallback = {
        active = false,
        available = {},
    },
})

if state.shared.read("GodAvailability").available.Apollo ~= false then
    -- draw available UI
end
```

Shared data surface:
- `store.shared.read(name)`
- `store.shared.set(name, value)` for owner declarations
- `store.shared.clear(name)` for owner declarations
- `state.shared.read(name)`
- `state.shared.set(name, value)` for owner declarations
- `state.shared.clear(name)` for owner declarations

Shared data rules:
- owner and reader access is declared through `module.shared.data.*` before activation
- only the publishing module can write or clear a shared data id
- writes update live memory immediately; there is no flush or persistence
- reads return the fallback when no active publisher exists or the publisher is disabled
- values may be scalars or tables with string/number keys
- table writes are copied once and returned as cached recursive read-only views

For table-shaped shared data, prefer a small domain helper that hides the
nested table layout and exposes semantic reads. The helper can accept either
`store` or draw `state`, because both expose `source.shared.read(...)`.

## Cache

Declared runtime cache owned by the module. Use cache only for module scratch
state with a game-lifetime owner, not for UI settings, hashes, profiles, or
runtime-write/UI-read values.

Declarative cache:

```lua
local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = "Example",
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

Runtime callbacks read declared cache refs through `runtime.data.cache`:

```lua
local runScratch = runtime.data.cache.currentRun.get("RunScratch")
runScratch.seen = true
```

Rules:
- cache declaration names must be stable identifiers
- declared cache participates in structural definition fingerprinting
- `runtime.data.cache` is valid outside draw callbacks
- current-run cache is only available from runtime data

Current run cache:

```lua
local runScratch = runtime.data.cache.currentRun.get("RunScratch")
runScratch.seen = true
```

Surface:
- `runtime.data.cache.currentRun.get(name)`
- `runtime.data.cache.currentRun.clear(name)`

Rules:
- the declaration name must be a stable identifier
- the declaration factory runs only when the bucket is missing
- the factory must return a table when provided
- cache is namespaced under one Lib-owned root on `CurrentRun`
- current-run cache is unavailable from draw `state`

For runtime-owned values that UI needs to read, declare managed storage with
`mode = "runtime"` and access it through `store.runtime` plus draw `state`.

## Store And State

### `lib.createModule(opts)`

Canonical safe module-construction helper.
`pluginGuid` is the stable runtime identity. Lib owns the internal per-plugin
runtime state used for structural hot-reload tracking, hook refresh ownership,
overlay ownership, shared event refresh, cache, mutation runtime, and
live-host lookup.

```lua
local data = import("mods/data.lua")
local logic = import("mods/logic.lua").bind(data)
local ui = import("mods/ui.lua").bind(data)

local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
})
if not module then return end

module.data.define(data.buildStorage())
module.ui.tab(ui.drawTab)
module.ui.quickContent(ui.drawQuickContent)
module.mutation.patch(logic.buildPatchPlan)
logic.registerHooks(module)
module.activate()
```

Returns:
- `module, nil` when construction succeeds
- `nil, err` when construction fails

The returned module object is the author-facing declaration and lifecycle
surface. It has `activate()`, `isEnabled()`, metadata getters, logging helpers,
and all declaration namespaces.

`createModule(...)` intentionally does not return the prepared definition or
raw staged state. Draw callbacks receive three draw-phase arguments:
`draw`, staged `state`, and draw `actions`.
`draw` owns `imgui`, `widgets`, `nav`, and draw-safe logging helpers; the other
arguments own staged UI state and deferred UI intent.

Declare hooks on `module.hooks.*` before `module.activate()`. Runtime helper
files should receive the needed `store` or narrowed read/access closures from
the module's hook-declaration code; draw/UI paths should use the `draw`,
`state`, and `actions` arguments passed to draw callbacks.

The failure path logs `host.create_failed` and does not activate or publish a
host. Use this at pack orchestration boundaries when one invalid module should
be skipped without stopping sibling modules.

```lua
local module, err = lib.createModule(opts)
if module then
    local ok, activateErr = module.activate()
end
```

`createModule(...)` only wraps construction. Activation remains explicit through
`module.activate()`.

The runtime store surface provides:
- `store.get(alias)`
- `store.read(alias, ...)`
- `store.runtime.read(alias)`
- `store.runtime.set(alias, value)`
- `store.runtime.clear(alias)`

Persisted writes happen through host-owned semantic helpers or staged-state flushes:

```lua
host.setEnabled(enabled)
host.setDebugMode(enabled)
```

Normal modules should let `createModule(...)` and the host own enabled/debug
transitions. Ordinary draw-code edits stay staged and commit through the
host/framework flow.

`Enabled` and `DebugMode` are ordinary prepared storage aliases injected by Lib.
Do not declare them in module storage or module `config.lua`.
`Enabled` is the module behavior toggle. Framework serializes it through the
module-level hash key. `DebugMode` is diagnostic-only and has `hash = false`.

`store.read(alias, ...)` is syntax sugar for `store.get(alias):read(...)`.
Scalar fields accept no extra path arguments; table handles accept the same row
path arguments as `tableHandle:read(...)`.

Rules:
- widgets and draw code should usually read staged values through `state.get(...)`
- runtime/gameplay code should read committed setting/runtime values through `store.get(...):read()` or `store.read(...)`
- runtime-owned storage declares `mode = "runtime"` and writes through `store.runtime`
- runtime-owned storage cannot participate in hashes
- enabled toggles should write through the host/framework flow
- debug toggles should write through the host/framework flow
- profile/hash plumbing should stage values through `stagedState.write(...)` and flush them through `stagedState._flushToConfig()`
- transient aliases are read from `state` in draw code or internal `stagedState` plumbing
- transient aliases declare `persist = false, hash = false` and stay out of persisted config

Composite table storage is declared as one table root with a uniform row schema:

```lua
{
    type = "table",
    alias = "Tiers",
    minRows = 0,
    maxRows = 10,
    defaultRows = 1,
    row = {
        { type = "bool", alias = "Enabled", default = true },
        { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
        {
            type = "packedInt",
            alias = "PackedChoices",
            bits = {
                { alias = "ChoiceA", offset = 0, width = 1, type = "bool", default = false },
                { alias = "ChoiceMode", offset = 1, width = 2, type = "int", default = 0 },
            },
        },
    },
}
```

The table root owns `persist` and `hash`. Row fields are row-scoped
storage aliases and do not declare storage axes. Table rows are compact ordered
arrays with no row ids or holes.

Read table state through `get(...)` when using the object-factory path:

```lua
local tiers = state.get("Tiers")
local enabled = tiers:read(1, "Enabled")
local enabledField = tiers:get(1, "Enabled")

local runtimeTiers = store.get("Tiers")
local committedEnabled = runtimeTiers:read(1, "Enabled")
local committedEnabledSugar = store.read("Tiers", 1, "Enabled")
```

Lib internals still expose direct table helpers on the full staged-state object:

```lua
local tiers = stagedState.table("Tiers")
tiers:append({ Enabled = true, ChoiceA = true })
tiers:write(1, "ChoiceMode", 2)
local enabled = tiers:read(1, "Enabled")
local field = tiers:get(1, "ChoiceMode")
```

Table handles:
- `store.get(alias)` returns a read-only field or table handle for committed setting or runtime-owned aliases
- `state.get(alias)` returns a writable staged field or table handle
- `tableHandle:get(rowIndex, alias)` returns a row-cell `StorageField`
- full internal stores expose `store.table(alias)` for framework plumbing
- full internal staged-state objects expose `stagedState.table(alias)` for framework plumbing
- table handles are object methods; call them with colon syntax such as `tiers:read(rowIndex, alias)`
- row aliases can address scalar row roots, packed row roots, or packed child aliases
- `snapshot(rowIndex)` returns a copied row table
- `snapshots()` returns copied rows
- table storage participates in hash/profile serialization when `hash` is true

Aliases are direct flat storage identifiers. Managed storage reads and writes the
declared alias key directly; future composite storage should own any generated
backing keys internally.

Storage axis defaults:

| Declaration | Persisted config | Staged UI state | Hash/profile |
| --- | --- | --- | --- |
| omitted flags | yes | yes | yes |
| `persist = false, hash = false` | no | yes | no |
| `hash = false` | yes | yes | no |

Invalid storage combinations fail during storage validation:
- `hash = true` requires `persist = true`

Reserved aliases:
- `Enabled`
- `DebugMode`

### `stagedState`

Managed staged UI state for the module. This is a Lib/Framework plumbing
object; module draw callbacks receive the narrower `state` adapter below.

Internal surface:
- `stagedState.view`
- `stagedState.get(alias)`
- `stagedState.read(alias)`
- `stagedState.table(alias)`
- `stagedState.field(alias)`
- `stagedState.getAliasSchema(alias)`
- `stagedState.write(alias, value)`
- `stagedState.reset(alias)`
- `stagedState.resetAll(opts?)`
- `stagedState.isDirty()`
- `stagedState.auditMismatches()`

Host/framework plumbing methods:
- `stagedState._flushToConfig()`
- `stagedState._reloadFromConfig()`
- `stagedState._captureDirtyConfigSnapshot()`
- `stagedState._restoreConfigSnapshot(snapshot)`

When a module is rendered through a Lib host, draw callbacks receive a
restricted author-facing `state` view with:
- `get(alias)`
- `read(alias, ...)`
- `write(alias, ...)`
- `resetAll(opts?)`

Draw action staging is not exposed on `stagedState`; use
`actions.trigger(actionKey, value?)` or `actions.get(actionKey)` instead.

`stagedState.get(alias)` returns a storage object: scalar and packed aliases return
`StorageField`; table roots return staged table handles. `state.get(alias)` is
the author-facing entrypoint for the same staged storage objects.
`state.read(alias, ...)` and `state.write(alias, ...)` are convenience forwards
for custom raw ImGui draw code; they call `state.get(alias):read(...)` and
`state.get(alias):write(...)`.
`tableHandle:get(rowIndex, alias)` returns `StorageField` targets for widgets
and UI helpers. A storage field is a resolved leaf value target; storage and
table APIs own traversal, while widgets render the final field. Storage fields
expose `field:alias()` for schema identity and
`field:controlId()` for draw/control identity. Root control ids equal their
alias; table cell control ids are cached by the table owner and include table
alias, row index, and cell alias.

Behavior:
- persisted aliases stage in `stagedState` and only hit config on flush/commit
- transient aliases live only in `stagedState`
- staged actions are transient "last intent wins" command slots that make the
  staged state dirty and are delivered to `module.onCommit(...)`
- packed child aliases re-encode their owning packed root automatically

`stagedState.read(alias)` returns:
- staged value

## Whole-State Reset

### `host.resetAll(opts?)`

Resets changed persistent storage roots back to their defaults in the host's staged state.

Returns:
- `changed`
- `count`

Options:
- `exclude = { Alias = true }` skips specific root aliases.

Draw callbacks receive the same reset behavior through `state.resetAll(opts?)`.

## `module.hooks`

Reload-stable wrappers around ModUtil path hooks.

Hosted modules declare hooks on the module object returned by
`lib.createModule(...)`. Lib scopes those declarations to the host's
module owner id, derived from `pluginGuid`.

### `module.hooks.wrap(path, handler)`

Registers or updates a stable ModUtil runtime `Path.Wrap(...)` dispatcher.

Also supports:
- `module.hooks.wrap(path, key, handler)`

Use the keyed form when one module registers more than one wrap against the same path.

### `module.hooks.override(path, replacement)`

Registers or updates a stable ModUtil runtime `Path.Override(...)`.

Also supports:
- `module.hooks.override(path, key, replacement)`

`replacement` must be a function. Function replacements are dispatched through
a stable wrapper so reloading updates behavior without stacking another
override.

### `module.hooks.contextWrap(path, context)`

Registers or updates a stable ModUtil runtime `Path.Context.Wrap(...)` dispatcher.

Also supports:
- `module.hooks.contextWrap(path, key, context)`

These APIs are only valid before `module.activate()`. Lib-owned ModUtil
dispatchers are private infrastructure, not a public owner-token surface.

### Typical module pattern

```lua
local function registerHooks(module)
    module.hooks.wrap("GetEligibleLootNames", function(host, runtime, base, ...)
        local result = base(...)
        if host.isEnabled() and runtime.data.read("FeatureEnabled") then
            -- inspect or transform the wrapped call here
        end
        return result
    end)
end

local PLUGIN_GUID = _PLUGIN.guid
local data = import("mods/data.lua")
local ui = import("mods/ui.lua").bind(data)

local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
})
if not module then return end

module.data.define(data.buildStorage())
module.ui.tab(ui.drawTab)
registerHooks(module)
module.activate()
```

When `module.activate()` runs, activation installs the declarations currently
recorded on `module.hooks` and deactivates hooks omitted by a later host for the
same module owner id.

## `module.overlays` And `frameworkRuntime.overlays`

Host-scoped module overlays and Framework-scoped retained HUD projections for shared overlay placement.

Overlay visibility has two layers:
- Lib applies a global game-HUD gate, currently based on `ShowingCombatUI`.
- Each overlay can also provide its own `visible` boolean or callback.
- Lib-hosted ImGui configuration windows acquire a UI suppression token while
  open. Any active token hides the entire overlay layer until released.

When the global gate is closed, lib hides all retained overlay components even if their own `visible` callback returns true. Text callbacks may still be refreshed so the display is fresh when the game HUD returns.

Framework and fallback module UIs use this gate so configuration UI and
gameplay overlays are mutually exclusive on screen.

Managed region:
- `middleRightStack`: a right-anchored vertical stack used for framework markers and module status text.

Order bands:
- `module.overlays.order.framework`
- `module.overlays.order.module`
- `module.overlays.order.debug`
- `frameworkRuntime.overlays.order.*` exposes the same shared bands for Framework overlays.

### Module `module.overlays`

Modules declare overlay structure on the returned module before activation:

```lua
local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
})
if not module then return end

module.data.define(data.buildStorage())
module.ui.tab(ui.drawTab)

module.overlays.createLine("summary.igt", {
    region = "middleRightStack",
    order = module.overlays.order.module,
    columnGap = 20,
    columns = {
        { key = "label", minWidth = 40 },
        { key = "time", minWidth = 80 },
    },
})

module.overlays.onCommit(function(ctx)
    ctx.setLine("summary.igt", { label = "IGT:", time = "00:00.00" })
    ctx.refresh("summary.igt")
end)

module.activate()
```

Retained element names are local to the module owner id derived from
`pluginGuid` and do not collide across modules.

### `module.overlays.createLine(name, spec)`

Declares one retained display line. Lines can use a one-column convenience shape:

```lua
module.overlays.createLine("message", {
    region = "middleRightStack",
    minWidth = 120,
})
```

or explicit columns:

```lua
module.overlays.createLine("summary.rta", {
    region = "middleRightStack",
    columnGap = 20,
    columns = {
        { key = "label", minWidth = 40 },
        { key = "time", minWidth = 80 },
    },
})
```

Projection callbacks update lines through `ctx.setLine(name, values)`.

### `module.overlays.createTable(name, spec)`

Declares one fixed-capacity retained table projection:

```lua
module.overlays.createTable("runs", {
    region = "middleRightStack",
    maxRows = 10,
    columnGap = 20,
    columns = {
        { key = "label", minWidth = 80 },
        { key = "igt", minWidth = 78 },
        { key = "rta", minWidth = 78 },
    },
})
```

Rows beyond `maxRows` are ignored. Unused retained rows are hidden. Projection callbacks update
tables through `ctx.setTable(name, rows)`.

### Projection Events

Supported retained overlay events:

- `module.overlays.onCommit(function(ctx, commit) ... end)`
- `module.overlays.onInterval(name, seconds, function(ctx, event) ... end, opts)`
- `module.overlays.afterHook(path, function(ctx, event) ... end)`

The projection context exposes read-only helpers plus named retained updates:

- `ctx.read(alias)`
- `ctx.isEnabled()`
- `ctx.log(fmt, ...)`
- `ctx.logIf(fmt, ...)`
- `ctx.setLine(name, values)`
- `ctx.setTable(name, rows)`
- `ctx.setCell(tableName, rowKey, columnKey, value)`
- `ctx.refresh(name)`
- `ctx.refreshRegion(region)`
- `ctx.refreshAll()`

### `frameworkRuntime.overlays.define(packId, name, register)`

Declares narrow retained HUD lines for one Framework-owned pack overlay scope.
The `packId` and `name` are combined into a retained owner id, so one Framework
runtime can own separate pack surfaces such as `hud` without sharing one
retained overlay owner.
The registrar supports `createLine(...)` and
`onCommit(...)`; module-only projection events such as `onInterval(...)` and
`afterHook(...)` are intentionally not exposed.

```lua
local frameworkRuntime = lib.createFrameworkRuntime("adamant-ModpackFramework")

frameworkRuntime.overlays.define("pack", "hud", function(overlays)
    overlays.createLine("hash", {
        region = "middleRightStack",
        order = frameworkRuntime.overlays.order.framework,
        minWidth = 120,
    })
end)
```

Overlay UI suppression is not a public module-author API. Framework uses
`lib.createFrameworkRuntime(...).ui`, and Lib fallback UI windows use the
internal overlay service.

## `frameworkRuntime.diagnostics`

Framework-only diagnostics controls returned by
`lib.createFrameworkRuntime("adamant-ModpackFramework")`.

### `frameworkRuntime.diagnostics.isLibDebugEnabled()`

Returns whether Lib internal diagnostic warnings are enabled.

### `frameworkRuntime.diagnostics.setLibDebugEnabled(enabled)`

Sets Lib internal diagnostic warnings. `enabled` must be a boolean.

## `frameworkRuntime.coordinator`

Framework-only coordinator registration helpers returned by
`lib.createFrameworkRuntime("adamant-ModpackFramework")`.

### `frameworkRuntime.coordinator.register(packId, config)`

Registers coordinator config for a pack. `config` may be `nil` to clear the
registration.

### `frameworkRuntime.coordinator.registerRebuild(packId, callback)`

Registers the Framework rebuild callback used when coordinated module structure
changes. `callback` may be `nil` to clear the callback.

### `frameworkRuntime.coordinator.isRegistered(packId)`

Returns whether a pack id is registered.

## `frameworkRuntime.hashing`

Framework-only hash/profile serialization and packed-bit helpers returned by
`lib.createFrameworkRuntime("adamant-ModpackFramework")`.

### `frameworkRuntime.hashing.getRoots(storage)`

Returns prepared root nodes that participate in hash/profile serialization.
The returned nodes are read-only metadata owned by Lib storage preparation; callers must not mutate them.

### `frameworkRuntime.hashing.getAliases(storage)`

Returns the prepared alias map.
The returned map and nodes are read-only metadata owned by Lib storage preparation; callers must not mutate them.

Includes:
- hash/profile root aliases
- non-hash staged aliases
- transient staged-state aliases
- packed child aliases

### `frameworkRuntime.hashing.valuesEqual(node, a, b)`

Storage-aware equality helper for comparing persisted/hash values.

### `frameworkRuntime.hashing.getPackWidth(node)`

Returns the derived pack width for a node type that supports packing.

### `frameworkRuntime.hashing.toHash(node, value)`

Encodes one storage value for hash/profile serialization.

### `frameworkRuntime.hashing.fromHash(node, str)`

Decodes one storage value from hash/profile serialization.

### `frameworkRuntime.hashing.isHashTokenValid(node, str)`

Returns whether one serialized hash/profile token is syntactically valid for a prepared storage node.
Use this at external hash/profile import boundaries before calling `fromHash(...)`.

### `frameworkRuntime.hashing.readPackedBits(packed, offset, width)`

Raw numeric bit extraction helper.

### `frameworkRuntime.hashing.writePackedBits(packed, offset, width, value)`

Raw numeric bit write helper.

Enabled/debug transitions, activation-time mutation sync, and staged-state commit/resync are module-host responsibilities. Framework uses the live host surface (`host.setEnabled`, `host.setDebugMode`, `host.flush`, `host.resync`) instead of calling internals directly.
Framework-owned pack suspension is also a host lifecycle responsibility; Framework uses `host.suspendForPackDisable`, `host.restoreForPackEnable`, and `host.rollbackPackTransition` so Lib can keep its internal restore marker private.

## `module.fallbackUi`

Fallback UI provides the module-owned ROM GUI callsites used when a module is
not being coordinated by Framework.

### `module.fallbackUi.attachGuiOnce(register)`

Registers stable no-op-safe fallback UI callbacks once for the module's plugin
guid. Call this before `module.activate()`.

The callback still owns the actual ROM registration, so it runs from the module
context:

```lua
module.fallbackUi.attachGuiOnce(function(fallbackUi)
    rom.gui.add_imgui(fallbackUi.renderWindow)
    rom.gui.add_to_menu_bar(fallbackUi.addMenuBar)
end)
```

Behavior:
- `attachGuiOnce(...)` prevents callback stacking across hot reloads
- `module.activate()` installs or swaps the active fallback UI runtime
- callbacks no-op until a runtime is active
- fallback UI suppresses its window/menu when the module's pack is coordinated
- the fallback window includes built-in:
  - `Enabled`
  - `Debug Mode`
  - `Resync State`
- then calls `moduleHost.drawTab(...)` when the module is enabled
- commits dirty staged state through `moduleHost.commitIfDirty()`

## `frameworkRuntime.modules`

Framework-only live module host discovery returned by
`lib.createFrameworkRuntime("adamant-ModpackFramework")`.

### `frameworkRuntime.modules.getLiveHost(pluginGuid)`

Returns the full runtime host registered by module activation, or `nil` when
the plugin guid is invalid or no live host is registered.

This is infrastructure API for Framework discovery. Normal module code should
keep the module object returned by `lib.createModule(...)` and use runtime/UI
callback arguments for data access.

## Draw Logging

Draw-safe module logging is available on the draw callback `draw` argument.

Built-ins:
- `draw.log(fmt, ...)`
- `draw.logIf(fmt, ...)`

These helpers are the sanctioned draw-time logging path. `draw.host` is not
available in module UI, and draw callbacks do not receive the declaration
facade.

## Draw Actions

Draw callbacks expose the `actions` argument for transient UI intent:

- `actions.get(actionKey)`
- `actions.trigger(actionKey, value?)`
- `actions.emit(id, eventName, payload?)`

`actions.get(actionKey)` returns a ref:

- `action:stage(value)`
- `action:read()`
- `action:clear()`
- `action:has()`

Action refs are object handles; call their methods with colon syntax.
`actions.trigger(actionKey, value?)` is shorthand for staging a declared action;
when `value` is omitted it stages `true`. `actions.emit(id, eventName, payload?)`
queues a shared event to emit after the draw callback.

Runtime commit callbacks receive the same action snapshot through
`commit.actions`:

- `commit.actions.get(actionKey)`
- `commit.actions.hasAny()`

`commit.actions.get(actionKey)` returns a read-only ref with:

- `action:read()`
- `action:has()`

The old `session.stageAction(...)` form has been removed. Use
`actions.trigger(actionKey, value)` in draw code, or `actions.get(actionKey)`
when a widget needs an action ref.

Declare action handlers with `module.actions.define(...)`. Handlers run after
the draw callback and before staged state flush:

```lua
module.actions.define({
    StartRecording = function(host, uiData, actionRuntime, value)
        host.logIf("Starting recording")
        actionRuntime.set("RecordingEnabled", value == true)
    end,
})
```

Handlers receive the callback host, draw `uiData`, a narrow
`actionRuntime` bridge (`read`, `set`, `clear`), and the staged action `value`.

## Draw Widgets

Immediate-mode widget helpers are available on the module draw object as
`draw.widgets`.

Built-ins:
- `draw.widgets.separator()`
- `draw.widgets.text(text, opts?)`
- `draw.widgets.button(label, opts?)`
- `draw.widgets.confirmButton(id, label, opts?)`
- `draw.widgets.inputText(target, opts?)`
- `draw.widgets.dropdown(target, opts?)`
- `draw.widgets.packedDropdown(target, opts?)`
- `draw.widgets.getPackedChoiceAlias(target, opts?)`
- `draw.widgets.radio(target, opts?)`
- `draw.widgets.packedRadio(target, opts?)`
- `draw.widgets.stepper(target, opts?)`
- `draw.widgets.steppedRange(minTarget, maxTarget, opts?)`
- `draw.widgets.checkbox(target, opts?)`
- `draw.widgets.packedCheckboxList(target, opts?)`

These are direct immediate-mode helpers. `draw.widgets` is bound to the current
`imgui` for the render call. Value widgets accept `StorageField` refs:

```lua
function ui.drawTab(draw, state, actions)
    draw.widgets.checkbox(state.get("FeatureEnabled"), {
        label = "Enable Feature",
    })

    draw.imgui.SameLine()
    draw.widgets.dropdown(state.get("Mode"), {
        label = "Mode",
        values = { "Default", "Custom" },
    })
end
```

Use `state.get(alias)` for root storage fields, and
`tableHandle:get(rowIndex, alias)` for table-backed fields:

```lua
local mode = state.get("Mode")
draw.widgets.dropdown(mode, opts)

local rows = state.get("Rows")
draw.widgets.packedDropdown(rows:get(1, "PackedChoices"), opts)
```

`getPackedChoiceAlias(...)` returns the selected child alias for packed
dropdown/radio use cases, or `nil` when the selected choice is none or
multiple. It uses the same `selectionMode` option as `packedDropdown(...)` and
`packedRadio(...)`.

Interactive widgets may optionally stage a draw action with
`action = actions.get("ActionName")`. Buttons stage `value` or `true` when
`value` is omitted. Value widgets keep their normal data edit and stage the
edited value by default unless `value` is provided.

## Draw Navigation

Navigation helpers are available on the module draw object as `draw.nav`.

### `draw.nav.verticalTabs(opts)`

Simple immediate-mode vertical tab rail.

Inputs:
- `id`
- `tabs`
- `activeKey`
- optional `navWidth`
- optional `height`

Each tab entry may include:
- `key`
- `label`
- optional `group`
- optional `color`

Returns:
- next `activeKey`
