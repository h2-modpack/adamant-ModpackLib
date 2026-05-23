# adamant-ModpackLib API

This is the public Lib surface.

Preferred usage uses top-level module authoring helpers plus namespaces for specialized APIs:
- `lib.createModule(...)`
- `lib.createFrameworkRuntime(...)`
- `host.fallbackUi.*`
- `host.hooks.*`
- `host.overlays.*`
- `host.integrations.*`
- `host.cache.*`
- `host.mutation.*`

Framework-owned live-host discovery, hash/profile, overlay, UI suppression, and
diagnostic controls are available from
`lib.createFrameworkRuntime("adamant-ModpackFramework")`.

## Core Model

Modules declare:
- required `definition.id`
- required `definition.name`
- optional `definition.modpack`
- optional `definition.storage`

Modules normally create and publish their behavior host through:
- `lib.createModule(...)`
- `host.activate()`

Module/host creation requires:
- `drawTab`

Optional module callbacks passed to module/host creation:
- `onSettingsCommitted`
- `drawQuickContent`

Host-owned capabilities can also be declared on the returned author host before
activation:
- `host.hooks.*`
- `host.integrations.*`
- `host.cache.*`
- `host.mutation.*`
- `host.overlays.*`
- `host.fallbackUi.*`

That host owns:
- `drawTab`
- optional `drawQuickContent`
- built-in host registry helpers for Framework and fallback UI

Module behavior is hosted through Lib's live host registry.

## `host.integrations`

Small registry for optional cross-module cooperation. Modules can publish
domain-named integration methods and events, and consumers can use them when
present while remaining fully functional when absent.

Typical provider declaration before activation:

```lua
local host, store, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})
if not host then return end

host.integrations.provide("run-director.god-availability", {
    providerId = MODULE_ID,
    methods = {
        isActive = {
            handler = function()
                return true
            end,
        },
        isAvailable = {
            reads = { "ZeusEnabled" },
            handler = function(scope, godKey)
                if godKey == "Zeus" then
                    return scope.read("ZeusEnabled") ~= false
                end
                return true
            end,
        },
    },
    events = {
        availabilityChanged = true,
    },
})

host.activate()
```

`providerId` is the public provider identity returned to integration consumers.
Module lifecycle refresh is scoped separately by the module owner id, which Lib
derives from `pluginGuid`; provider ids do not need to match the module's
`pluginGuid`.

Typical consumer:

```lua
local active = host.integrations.poll("run-director.god-availability", "isActive", false)
if active then
    return host.integrations.poll("run-director.god-availability", "isAvailable", true, godKey) ~= false
end
return true
```

Surface:
- `host.integrations.provide(id, { providerId = providerId, methods = methods })`
- `host.integrations.poll(id, methodName, fallback, ...)`
- `host.integrations.listen(id, eventName, callback)`
- `host.integrations.emit(id, eventName, payload)`

Rules:
- integration ids should describe domain behavior, not consumer names
- absence means the optional enhancement is inactive
- provider methods receive a scoped read object, not the provider host or store
- provider methods can only read aliases listed in that method's `reads`
- provider read scopes use the provider module's staged state and close after the method returns
- `reads` must be an array of aliases; declaring a table root allows read-only table access, while packed child reads must declare the child alias
- consumers should prefer `host.integrations.poll(...)` so Lib resolves active provider behavior at call time
- when multiple providers exist, `poll(...)` uses the most recently activated enabled provider
- provider events must be declared in the provider spec before they can be emitted
- `providerChanged` is a Lib-reserved event emitted once after a provider host's module enabled state changes
- events are runtime notifications; listener order is unspecified and nested emits are queued
- listener callbacks receive `payload, providerId`
- event payloads are not durable state; consumers should poll for current values when needed

## `host.cache`

Namespaced runtime cache owned by the module host.

Use this for module-owned runtime cache that is not staged UI config,
hashed/profiled config, or mutation state.

The normal author path is the author host returned by `lib.createModule(...)`.
It binds the module's host id, backed by `pluginGuid`, so module code only
supplies the cache domain and key.

Current run cache:

```lua
local state = host.cache.currentRun.get("run", function()
    return {
        ForcedNPCPending = {},
        NPCEncounterSeen = {},
    }
end)
```

`currentRun.get(...)` returns `nil` when there is no active `CurrentRun`.

Surface:
- `host.cache.currentRun.get(key, factory?)`
- `host.cache.currentRun.peek(key)`
- `host.cache.currentRun.clear(key)`

Rules:
- `key` must be a non-empty string
- `factory` runs only when the bucket is missing
- `factory` must return a table when provided
- cache is namespaced under one Lib-owned root on `CurrentRun`

Persistent scalar cache:

```lua
local ready = host.cache.persistent.read("RecordingReady", false)

host.cache.persistent.write("RecordingReady", true)

if host.cache.persistent.has("RecordingReady") then
    host.cache.persistent.clear("RecordingReady")
end
```

Surface:
- `host.cache.persistent.read(key, default?)`
- `host.cache.persistent.write(key, value)`
- `host.cache.persistent.clear(key)`
- `host.cache.persistent.has(key)`

Rules:
- `key` must be a non-empty string
- `value` and `default` must be boolean, number, string, or `nil` for the default only
- `read(...)` does not create a stored value
- `write(nil)` is invalid; use `clear(...)`
- persistent cache is not staged, hashed, profiled, or reset by Lib

Shared live cache:

```lua
host.cache.shared.publish("run-director.god-availability", {
    default = { active = false, available = {} },
})

host.cache.shared.write("run-director.god-availability", {
    active = true,
    available = {
        Apollo = false,
    },
})
```

Draw consumers can read the same live projection:

```lua
local snapshot = services.cache.shared.read("run-director.god-availability", {
    active = false,
    available = {},
})
```

Surface:
- `host.cache.shared.publish(id, opts?)`
- `host.cache.shared.read(id, fallback?)`
- `host.cache.shared.write(id, value)`
- `host.cache.shared.clear(id)`
- `services.cache.shared.read(id, fallback?)`
- `services.cache.shared.write(id, value)`
- `services.cache.shared.clear(id)`

Rules:
- `publish(...)` is declaration-time only and must run before activation
- only the publishing host can write or clear a shared cache id
- writes update live memory immediately; there is no flush or persistence
- reads return the fallback when no active publisher exists or the publisher is disabled
- values may be scalars or tables and are deep-copied on write/read
- use integrations for cross-module behavior calls; use shared cache for public live read models

## Store And State

### `lib.createModule(opts)`

Canonical safe module-construction helper.
`pluginGuid` is the stable runtime identity. Lib owns the internal per-plugin
runtime state used for structural hot-reload tracking, hook refresh ownership,
overlay ownership, integration refresh, cache, mutation runtime, and
live-host lookup.

```lua
local data = import("mods/data.lua")
local logic = import("mods/logic.lua").bind(data)
local ui = import("mods/ui.lua").bind(data)

local host, store, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
    drawQuickContent = ui.drawQuickContent,
})
if not host then return end

host.mutation.patch(logic.buildPatchPlan)
logic.registerHooks(host, store)
host.activate()
```

Returns:
- `host, store, nil` when construction succeeds
  - `host`
  Author-facing host with `activate()`, `isEnabled()`, metadata getters, and module-scoped logging helpers.
  - `store`
  Runtime read surface for gameplay/hooks.
- `nil, nil, err` when construction fails

`createModule(...)` intentionally does not return the prepared definition or
raw staged state. Draw callbacks receive four draw-phase arguments:
`draw`, staged `state`, draw `actions`, and draw-safe `services`.
`draw` owns `imgui`, `widgets`, and `nav`; the other arguments own staged UI state,
deferred UI intent, and narrow draw-safe services.

Declare hooks on `host.hooks.*` before `host.activate()`. Runtime helper
files should receive the needed `store` or narrowed read/access closures from
the module's hook-declaration code; draw/UI paths should use the `state`,
`actions`, and `services` arguments passed to draw callbacks.

The failure path logs `host.create_failed` and does not activate or publish a
host. Use this at pack orchestration boundaries when one invalid module should
be skipped without stopping sibling modules.

```lua
local host, store, err = lib.createModule(opts)
if host then
    local ok, activateErr = host.activate()
end
```

`createModule(...)` only wraps construction. Activation remains explicit through
`host.activate()`.

The runtime store surface provides:
- `store.get(alias)`
- `store.read(alias, ...)`

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
- runtime/gameplay code should read persisted values through `store.get(...):read()` or `store.read(...)`
- new flat runtime markers should prefer `host.cache.persistent.*`
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
- `store.get(alias)` returns a read-only field or table handle for persisted aliases
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
`actions.get(actionKey)` instead.

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
  staged state dirty and are delivered to `onSettingsCommitted(host, store, commit)`
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

## `host.hooks`

Reload-stable wrappers around ModUtil path hooks.

Hosted modules declare hooks on the author host returned by
`lib.createModule(...)`. Lib scopes those declarations to the host's
module owner id, derived from `pluginGuid`.

### `host.hooks.wrap(path, handler)`

Registers or updates a stable ModUtil runtime `Path.Wrap(...)` dispatcher.

Also supports:
- `host.hooks.wrap(path, key, handler)`

Use the keyed form when one module registers more than one wrap against the same path.

### `host.hooks.override(path, replacement)`

Registers or updates a stable ModUtil runtime `Path.Override(...)`.

Also supports:
- `host.hooks.override(path, key, replacement)`

`replacement` must be a function. Function replacements are dispatched through
a stable wrapper so reloading updates behavior without stacking another
override.

### `host.hooks.contextWrap(path, context)`

Registers or updates a stable ModUtil runtime `Path.Context.Wrap(...)` dispatcher.

Also supports:
- `host.hooks.contextWrap(path, key, context)`

These APIs are only valid before `host.activate()`. Lib-owned ModUtil
dispatchers are private infrastructure, not a public owner-token surface.

### Typical module pattern

```lua
local function registerHooks(host, store)
    host.hooks.wrap("GetEligibleLootNames", function(base, ...)
        local result = base(...)
        if host.isEnabled() and store.get("FeatureEnabled"):read() then
            -- inspect or transform the wrapped call here
        end
        return result
    end)
end

local PLUGIN_GUID = _PLUGIN.guid
local data = import("mods/data.lua")
local ui = import("mods/ui.lua").bind(data)

local host, store, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    modpack = PACK_ID,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})
if not host then return end

registerHooks(host, store)
host.activate()
```

When `host.activate()` runs, activation installs the declarations currently
recorded on `host.hooks` and deactivates hooks omitted by a later host for the
same module owner id.

## `host.overlays` And `frameworkRuntime.overlays`

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
- `host.overlays.order.framework`
- `host.overlays.order.module`
- `host.overlays.order.debug`
- `frameworkRuntime.overlays.order.*` exposes the same shared bands for Framework overlays.

### Module `host.overlays`

Modules declare overlay structure on the returned author host before activation:

```lua
local host, store, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})
if not host then return end

host.overlays.createLine("summary.igt", {
    region = "middleRightStack",
    order = host.overlays.order.module,
    columnGap = 20,
    columns = {
        { key = "label", minWidth = 40 },
        { key = "time", minWidth = 80 },
    },
})

host.overlays.onCommit(function(ctx)
    ctx.setLine("summary.igt", { label = "IGT:", time = "00:00.00" })
    ctx.refresh("summary.igt")
end)

host.activate()
```

Retained element names are local to the module owner id derived from
`pluginGuid` and do not collide across modules.

### `host.overlays.createLine(name, spec)`

Declares one retained display line. Lines can use a one-column convenience shape:

```lua
host.overlays.createLine("message", {
    region = "middleRightStack",
    minWidth = 120,
})
```

or explicit columns:

```lua
host.overlays.createLine("summary.rta", {
    region = "middleRightStack",
    columnGap = 20,
    columns = {
        { key = "label", minWidth = 40 },
        { key = "time", minWidth = 80 },
    },
})
```

Projection callbacks update lines through `ctx.setLine(name, values)`.

### `host.overlays.createTable(name, spec)`

Declares one fixed-capacity retained table projection:

```lua
host.overlays.createTable("runs", {
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

- `host.overlays.onCommit(function(ctx, commit) ... end)`
- `host.overlays.onInterval(name, seconds, function(ctx, event) ... end, opts)`
- `host.overlays.afterHook(path, function(ctx, event) ... end)`

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

Enabled/debug transitions, activation-time mutation sync, and staged-state commit/resync are host responsibilities. Use the returned module host surface (`host.setEnabled`, `host.setDebugMode`, `host.flush`, `host.resync`) instead of calling internals directly.
Framework-owned pack suspension is also a host lifecycle responsibility; Framework uses `host.suspendForPackDisable`, `host.restoreForPackEnable`, and `host.rollbackPackTransition` so Lib can keep its internal restore marker private.

## `host.fallbackUi`

Fallback UI provides the module-owned ROM GUI callsites used when a module is
not being coordinated by Framework.

### `host.fallbackUi.attachGuiOnce(register)`

Registers stable no-op-safe fallback UI callbacks once for the module's plugin
guid. Call this before `host.activate()`.

The callback still owns the actual ROM registration, so it runs from the module
context:

```lua
host.fallbackUi.attachGuiOnce(function(fallbackUi)
    rom.gui.add_imgui(fallbackUi.renderWindow)
    rom.gui.add_to_menu_bar(fallbackUi.addMenuBar)
end)
```

Behavior:
- `attachGuiOnce(...)` prevents callback stacking across hot reloads
- `host.activate()` installs or swaps the active fallback UI runtime
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
keep the author host returned by `lib.createModule(...)` and use
`store` and draw callback arguments for state access.

## Draw Services

Draw-safe module services are available through the draw callback `services`
argument.

Built-ins:
- `services.log(fmt, ...)`
- `services.logIf(fmt, ...)`
- `services.pollIntegration(id, methodName, fallback, ...)`
- `services.cache.shared.read(id, fallback?)`
- `services.cache.shared.write(id, value)`
- `services.cache.shared.clear(id)`

These helpers are the sanctioned draw-time access path for narrow module
services. `draw.host` is not available in module UI. `services` is
intentionally not a full host facade: it does not expose registration,
activation, lifecycle mutation, storage mutation, hook declaration, overlay
declaration, or mutation declaration APIs.

## Draw Actions

Draw callbacks expose the `actions` argument for transient UI intent:

- `actions.get(actionKey)`
- `actions.hasAny()`

`actions.get(actionKey)` returns a ref:

- `action:stage(value)`
- `action:read()`
- `action:clear()`
- `action:has()`

Action refs are object handles; call their methods with colon syntax.

Runtime commit callbacks receive the same action snapshot through
`commit.actions`:

- `commit.actions.get(actionKey)`
- `commit.actions.hasAny()`

`commit.actions.get(actionKey)` returns a read-only ref with:

- `action:read()`
- `action:has()`

The old `session.stageAction(...)` form has been removed. Use
`actions.get(actionKey):stage(value)` in draw code.

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
function ui.drawTab(draw, state, actions, services)
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
