# adamant-ModpackLib API

This is the public Lib surface.

Preferred usage uses top-level module authoring helpers plus namespaces for specialized APIs:
- `lib.createModule(...)`
- `lib.createFrameworkRuntime(...)`
- `host.fallbackUi.*`
- `host.hooks.*`
- `host.overlays.*`
- `host.integrations.*`
- `host.gameCache.*`
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
- `host.gameCache.*`
- `host.mutation.*`
- `host.overlays.*`
- `host.fallbackUi.*`

That host owns:
- `drawTab`
- optional `drawQuickContent`
- built-in host state helpers for Framework and fallback UI

Module behavior is hosted through Lib's live host registry.

## `host.integrations`

Small registry for optional cross-module cooperation. Modules can publish a
domain-named integration API, and consumers can use it when present while
remaining fully functional when absent.

Typical provider declaration before activation:

```lua
local host, store = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})
if not host then return end

host.integrations.register("run-director.god-availability", {
    providerId = MODULE_ID,
    api = {
        isActive = function()
            return host.isEnabled()
        end,
        isAvailable = function(godKey)
            return true
        end,
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
local active = host.integrations.invoke("run-director.god-availability", "isActive", false)
if active then
    return host.integrations.invoke("run-director.god-availability", "isAvailable", true, godKey) ~= false
end
return true
```

Surface:
- `host.integrations.register(id, { providerId = providerId, api = api })`
- `host.integrations.invoke(id, methodName, fallback, ...)`

Rules:
- integration ids should describe domain behavior, not consumer names
- absence means the optional enhancement is inactive
- provider APIs should be safe to call when their module is disabled
- consumers should prefer `host.integrations.invoke(...)` so Lib resolves active provider behavior at call time
- when multiple providers exist, `invoke(...)` uses the most recently activated provider

## `host.gameCache`

Namespaced runtime cache buckets attached to `CurrentRun`.

Use this for module-owned runtime cache whose lifetime should follow the active
run. It is not persisted, staged, hashed, profiled, or reset by Lib.

The normal author path is the author host returned by `lib.createModule(...)`.
It binds the module's host id, backed by `pluginGuid`, so module code only
supplies the cache domain and bucket key.

Current run cache:

```lua
local state = host.gameCache.currentRun.get("run", function()
    return {
        ForcedNPCPending = {},
        NPCEncounterSeen = {},
    }
end)
```

`currentRun.get(...)` returns `nil` when there is no active `CurrentRun`.

Surface:
- `host.gameCache.currentRun.get(key, factory?)`
- `host.gameCache.currentRun.peek(key)`
- `host.gameCache.currentRun.clear(key)`

Rules:
- `key` must be a non-empty string
- `factory` runs only when the bucket is missing
- `factory` must return a table when provided
- cache is namespaced under one Lib-owned root on `CurrentRun`

## Store And Session

### `lib.createModule(opts)`

Canonical safe module-construction helper.
`pluginGuid` is the stable runtime identity. Lib owns the internal per-plugin
runtime state used for structural hot-reload tracking, hook refresh ownership,
overlay ownership, integration refresh, game cache, mutation runtime, and
live-host lookup.

```lua
local data = import("mods/data.lua")
local logic = import("mods/logic.lua").bind(data)
local ui = import("mods/ui.lua").bind(data)

local host, store = lib.createModule({
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
raw session. Draw callbacks receive a render-scoped context with `imgui`,
author `session`, author `host`, and bound `widgets`.

Declare hooks on `host.hooks.*` before `host.activate()`. Runtime helper
files should receive the needed `store` or narrowed read/access closures from
the module's hook-declaration code; draw/UI paths should continue using the
session passed to draw callbacks.

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
- `store.read(alias)`
- `store.table(alias)`
- `store.writeUnstaged(alias, value)` returns whether the write was accepted

Persisted writes happen through host-owned semantic helpers or session flushes:

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

Rules:
- widgets and draw code should usually read staged values from `session.view`
- runtime/gameplay code should read persisted values through `store.read(...)`
- module-owned runtime markers declared with `stage = false, hash = false` should write through `store.writeUnstaged(...)`
- enabled toggles should write through the host/framework flow
- debug toggles should write through the host/framework flow
- profile/hash plumbing should stage values through `session.write(...)` and flush them through `session._flushToConfig()`
- transient aliases are read from `session`
- transient aliases declare `persist = false, hash = false` and stay out of persisted config
- runtime-cache aliases declare `stage = false, hash = false` and are excluded from session, hash, profile, and reset-to-defaults surfaces

Persistent runtime cache storage is declared on ordinary storage nodes:

```lua
{
    type = "bool",
    alias = "BatchRecordingArmed",
    default = false,
    stage = false,
    hash = false,
}
```

Use it for module-owned runtime intent or small reload/restart markers that should not affect UI staging, profiles, or config hashes:

```lua
store.writeUnstaged("BatchRecordingArmed", true)
local armed = store.read("BatchRecordingArmed") == true
```

`store.writeUnstaged(alias, value)` only accepts aliases declared with `stage = false`.
It returns `false` without mutating state if violation policy is downgraded from
error and the alias is rejected.

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

The table root owns `persist`, `stage`, and `hash`. Row fields are row-scoped
storage aliases and do not declare storage axes. Table rows are compact ordered
arrays with no row ids or holes.

Read table state through:

```lua
local tiers = session.table("Tiers")
tiers:append({ Enabled = true, ChoiceA = true })
tiers:write(1, "ChoiceMode", 2)
local enabled = tiers:read(1, "Enabled")

local row = tiers:rowHandle(1)
row.write("ChoiceMode", 2)
local selected = row.read("ChoiceMode")
local field = row:field("ChoiceMode")
```

Table handles:
- `store.table(alias)` returns a read-only table handle
- `session.table(alias)` returns a staged writable table handle
- table handles are object methods; call them with colon syntax such as `tiers:read(rowIndex, alias)`
- row aliases can address scalar row roots, packed row roots, or packed child aliases
- `rowHandle(rowIndex)` returns a positional row cursor with `read(alias)`, `field(alias)`, and `getAliasSchema(alias)`
- writable session row handles also expose `write(alias, value)` and `reset(alias)`
- read-only store row handles do not expose write methods
- table storage participates in hash/profile serialization when `hash` is true

Aliases are direct flat storage identifiers. Managed storage reads and writes the
declared alias key directly; future composite storage should own any generated
backing keys internally.

Storage axis defaults:

| Declaration | Persisted config | Session/staged UI | Hash/profile |
| --- | --- | --- | --- |
| omitted flags | yes | yes | yes |
| `persist = false, hash = false` | no | yes | no |
| `stage = false, hash = false` | yes | no | no |
| `hash = false` | yes | yes | no |

Invalid storage combinations fail during storage validation:
- `hash = true` requires `persist = true`
- `hash = true` requires `stage = true`

Reserved aliases:
- `Enabled`
- `DebugMode`

### `session`

Managed staged UI state for the module.

Useful surface:
- `session.view`
- `session.read(alias)`
- `session.table(alias)`
- `session.field(alias)`
- `session.getAliasSchema(alias)`
- `session.write(alias, value)`
- `session.stageAction(actionKey, value)`
- `session.readAction(actionKey)`
- `session.clearAction(actionKey)`
- `session.hasActions()`
- `session.reset(alias)`
- `session.isDirty()`
- `session.auditMismatches()`

Host/framework plumbing methods:
- `session._flushToConfig()`
- `session._reloadFromConfig()`
- `session._captureDirtyConfigSnapshot()`
- `session._restoreConfigSnapshot(snapshot)`

When a module is rendered through a Lib host, draw callbacks receive a restricted author-facing session view with:
- `view`
- `read(alias)`
- `table(alias)`
- `field(alias)`
- `write(alias, value)`
- `stageAction(actionKey, value)`
- `readAction(actionKey)`
- `clearAction(actionKey)`
- `hasActions()`
- `reset(alias)`
- `getAliasSchema(alias)`
- `resetToDefaults(opts?)`

The session action methods are compatibility helpers for the draw action
service. New draw code should prefer `draw.actions.get(actionKey)`.

`session.getAliasSchema(alias)` exposes prepared storage schema metadata for UI
and widget plumbing. Treat the returned nodes as read-only metadata owned by Lib
storage preparation. Widgets use this metadata for composite storage such as
packed roots.

`session.field(alias)` and `row:field(alias)` return `StorageField` targets for
widgets and UI helpers. A storage field is a resolved leaf value target; storage
and table APIs own traversal, while widgets render the final field.

Behavior:
- persisted aliases stage in `session` and only hit config on flush/commit
- transient aliases live only in `session`
- staged actions are transient "last intent wins" command slots that make the
  session dirty and are delivered to `onSettingsCommitted(host, store, commit)`
- packed child aliases re-encode their owning packed root automatically

`session.read(alias)` returns:
- staged value

## Reset Helpers

### `host.resetToDefaults(opts?)`

Resets changed persistent storage roots back to their defaults in the host's staged session.

Returns:
- `changed`
- `count`

Options:
- `exclude = { Alias = true }` skips specific root aliases.

Draw callbacks receive the same reset behavior through
`draw.session.resetToDefaults(opts?)`.

## `host.hooks`

Reload-stable wrappers around ModUtil path hooks.

Hosted modules declare hooks on the author host returned by
`lib.createModule(...)`. Lib scopes those declarations to the host's
module owner id, derived from `pluginGuid`.

### `host.hooks.wrap(path, handler)`

Registers or updates a stable `modutil.mod.Path.Wrap(...)` dispatcher.

Also supports:
- `host.hooks.wrap(path, key, handler)`

Use the keyed form when one module registers more than one wrap against the same path.

### `host.hooks.override(path, replacement)`

Registers or updates a stable `modutil.mod.Path.Override(...)`.

Also supports:
- `host.hooks.override(path, key, replacement)`

`replacement` must be a function. Function replacements are dispatched through
a stable wrapper so reloading updates behavior without stacking another
override.

### `host.hooks.contextWrap(path, context)`

Registers or updates a stable `modutil.mod.Path.Context.Wrap(...)` dispatcher.

Also supports:
- `host.hooks.contextWrap(path, key, context)`

These APIs are only valid before `host.activate()`. Lib-owned ModUtil
dispatchers are private infrastructure, not a public owner-token surface.

### Typical module pattern

```lua
local function registerHooks(host, store)
    host.hooks.wrap("GetEligibleLootNames", function(base, ...)
        local result = base(...)
        if host.isEnabled() and store.read("FeatureEnabled") then
            -- inspect or transform the wrapped call here
        end
        return result
    end)
end

local PLUGIN_GUID = _PLUGIN.guid
local data = import("mods/data.lua")
local ui = import("mods/ui.lua").bind(data)

local host, store = lib.createModule({
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
local host, store = lib.createModule({
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
local runtime = lib.createFrameworkRuntime("adamant-ModpackFramework")

runtime.overlays.define("pack", "hud", function(overlays)
    overlays.createLine("hash", {
        region = "middleRightStack",
        order = runtime.overlays.order.framework,
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
- runtime-cache aliases
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

Enabled/debug transitions, activation-time mutation sync, and session commit/resync are host responsibilities. Use the returned module host surface (`host.setEnabled`, `host.setDebugMode`, `host.flush`, `host.resync`) instead of calling internals directly.

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
  - `Resync Session`
- then calls `moduleHost.drawTab(...)`
- commits dirty staged state through `moduleHost.commitIfDirty()`

## `frameworkRuntime.modules`

Framework-only live module host discovery returned by
`lib.createFrameworkRuntime("adamant-ModpackFramework")`.

### `frameworkRuntime.modules.getLiveHost(pluginGuid)`

Returns the full runtime host registered by module activation, or `nil` when
the plugin guid is invalid or no live host is registered.

This is infrastructure API for Framework discovery. Normal module code should
keep the author host returned by `lib.createModule(...)` and use
`store`/callback sessions for state access.

## Draw Services

Draw-safe module services are available on the module draw object as
`draw.services`.

Built-ins:
- `draw.services.log(fmt, ...)`
- `draw.services.logIf(fmt, ...)`
- `draw.services.isHostEnabled()`
- `draw.services.invokeIntegration(id, methodName, fallback, ...)`

These helpers are the sanctioned draw-time access path for narrow module
services. `draw.host` is not available in module UI. `draw.services` is
intentionally not a full host facade: it does not expose registration,
activation, lifecycle mutation, storage mutation, hook declaration, overlay
declaration, or mutation declaration APIs.

## Draw Actions

Draw callbacks expose `draw.actions` for transient UI intent:

- `draw.actions.get(actionKey)`
- `draw.actions.hasAny()`

`draw.actions.get(actionKey)` returns a ref:

- `action:stage(value)`
- `action:read()`
- `action:clear()`
- `action:has()`

Runtime commit callbacks receive the same action snapshot through
`commit.actions`:

- `commit.actions.get(actionKey)`
- `commit.actions.hasAny()`

`commit.actions.get(actionKey)` returns a read-only ref with:

- `action:read()`
- `action:has()`

The old `session.stageAction(...)` and `commit.readAction(...)` forms remain as
compatibility helpers during the migration. Prefer action refs in new code.

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
- `draw.widgets.mappedDropdown(target, opts?)`
- `draw.widgets.packedDropdown(target, opts?)`
- `draw.widgets.getPackedChoiceAlias(target, opts?)`
- `draw.widgets.radio(target, opts?)`
- `draw.widgets.mappedRadio(target, opts?)`
- `draw.widgets.packedRadio(target, opts?)`
- `draw.widgets.stepper(target, opts?)`
- `draw.widgets.steppedRange(minTarget, maxTarget, opts?)`
- `draw.widgets.checkbox(target, opts?)`
- `draw.widgets.packedCheckboxList(target, opts?)`

These are direct immediate-mode helpers. `draw.widgets` is bound to the current
`imgui` and author session for the render call. Value widgets accept either a
root alias string or a `StorageField`:

```lua
function ui.drawTab(draw)
    draw.widgets.checkbox("FeatureEnabled", {
        label = "Enable Feature",
    })

    draw.imgui.SameLine()
    draw.widgets.dropdown("Mode", {
        label = "Mode",
        values = { "Default", "Custom" },
    })
end
```

Use `draw.field(alias)` for an explicit root storage field, and
`row:field(alias)` for table-backed fields:

```lua
local mode = draw.field("Mode")
draw.widgets.dropdown(mode, opts)

local row = draw.session.table("Rows"):rowHandle(1)
draw.widgets.packedDropdown(row:field("PackedChoices"), opts)
```

`getPackedChoiceAlias(...)` returns the selected child alias for packed
dropdown/radio use cases, or `nil` when the selected choice is none or
multiple. It uses the same `selectionMode` option as `packedDropdown(...)` and
`packedRadio(...)`.

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

### `draw.nav.isVisible(condition)`

Evaluates a `visibleIf`-style condition against the draw session.

Supported forms:
- `"AliasName"`
- `{ alias = "AliasName", value = ... }`
- `{ alias = "AliasName", anyOf = { ... } }`

