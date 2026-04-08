# adamant-ModpackLib API

This is the supported Lib surface after the storage/UI hard cut.

## Core Model

Modules now declare:
- `definition.storage`
- `definition.ui`
- optional `definition.customTypes`

There is no compatibility layer for:
- `definition.options`
- `definition.stateSchema`

Storage owns persistence and hashing.
UI owns widgets and layout.

## Store

### `lib.createStore(config, definition?, dataDefaults?)`

Creates the module-owned store facade around persisted config.

`dataDefaults` is the static table returned by `import("config.lua")`.
When provided, Lib uses it to seed storage-node defaults for nodes that do not
declare an explicit `default`.

Normal access:
- `store.read(keyOrAlias)`
- `store.write(keyOrAlias, value)`

Raw packed access:
- `store.readBits(configKey, offset, width)`
- `store.writeBits(configKey, offset, width, value)`

Managed state:
- `store.storage`
- `store.ui`
- `store.uiState` when `definition.storage` exists

Rules:
- pass the full `public.definition`
- root storage aliases default to `configKey` when omitted
- packed child aliases are required
- widgets bind by alias, not raw `configKey`
- `store.read/write` accept either a storage alias or a raw config key

### `store.read(keyOrAlias)`

Reads:
- a root storage alias
- a packed child alias
- or a raw config key fallback

Examples:

```lua
store.read("Enabled")
store.read("BridalGlowTargetBoon")
store.read("AttackBanned")
store.read("PackedAphrodite")
```

### `store.write(keyOrAlias, value)`

Writes:
- a root storage alias
- a packed child alias
- or a raw config key fallback

Packed child writes re-encode the owning packed root automatically.

### `store.readBits(configKey, offset, width)`

Raw numeric packed read.

- no alias lookup
- no bool coercion
- no widget semantics

### `store.writeBits(configKey, offset, width, value)`

Raw numeric packed write.

- clamps to the target bit width
- updates only the selected bit range

## Storage Helpers

### `lib.validateStorage(storage, label)`

Validates and prepares a storage declaration table.

Validation covers:
- alias uniqueness
- root `configKey` uniqueness
- packed bit overlap
- packed child alias registration

### `lib.getStorageRoots(storage)`

Returns the prepared root storage nodes.

Only root nodes:
- persist directly
- hash directly
- flush directly

### `lib.getStorageAliases(storage)`

Returns the prepared alias map:

```lua
local aliases = lib.getStorageAliases(definition.storage)
local node = aliases.AttackBanned
```

Includes:
- root aliases
- packed child aliases

### `lib.valuesEqual(node, a, b)`

Semantic equality helper used by:
- hash default elision
- UI state drift checks

Uses storage-type `equals(...)` when provided, otherwise deep structural equality.

## UI Helpers

### `lib.validateUi(ui, label, storage, customTypes?)`

Validates a UI declaration table against storage.

The `storage` argument may be:
- raw `definition.storage`
- or already-prepared storage metadata

Validation covers:
- widget/layout node types
- alias existence
- widget/storage type compatibility
- `visibleIf` alias validity
- module-local custom widget/layout contracts when `customTypes` is provided

### `lib.prepareUiNode(node, label?, storage, customTypes?)`

Validates and prepares one UI node in isolation.

Useful for special modules that build reusable widget/layout nodes at load time.

The `storage` argument may be:
- raw `definition.storage`
- or already-prepared storage metadata

Store creation is not required before calling this helper.

### `lib.prepareUiNodes(nodes, label?, storage, customTypes?)`

Validates and prepares an ordered UI node list.

### `lib.isUiNodeVisible(node, values)`

Evaluates `visibleIf` against the current alias-value table.

### `lib.drawUiNode(imgui, node, uiState, width?, customTypes?)`

Draws one prepared UI node against alias-backed `uiState`.

Supports:
- scalar widgets through `binds`
- `steppedRange` through `binds.min` / `binds.max`
- `packedCheckboxList` through packed child alias expansion
- layout recursion through `children`
- module-local custom widget/layout registries through `customTypes`

### `lib.drawUiTree(imgui, nodes, uiState, width?, customTypes?)`

Draws an ordered UI node list.

### `lib.collectQuickUiNodes(nodes, out?, customTypes?)`

Returns all widget nodes marked `quick = true`, recursing through layout `children`.

Quick candidate ids:
- use `node.quickId` when provided
- otherwise derive from `node.binds`

### `lib.getQuickUiNodeId(node)`

Returns the stable quick candidate id used by quick-selection callbacks.

Modules may optionally define:

```lua
definition.selectQuickUi = function(store, uiState, quickNodes)
    return { "value=SomeAlias" }
end
```

Behavior:
- callback runs at Quick Setup render time
- return `nil` to render all quick candidates
- return a string, array of strings, or `{ [quickId] = true }` set
- only matching quick candidates are rendered

## Module-Local Custom Types

Modules may optionally declare:

```lua
definition.customTypes = {
    widgets = {
        myWidget = {
            binds = { value = { storageType = "int" } },
            geometry = { "controlStart", "controlWidth" }, -- optional supported geometry keys
            validate = function(node, prefix) ... end,
            draw = function(imgui, node, bound, width) ... end,
        },
    },
    layouts = {
        myLayout = {
            validate = function(node, prefix) ... end,
            render = function(imgui, node) ... end,
        },
    },
}
```

Rules:
- custom widget and layout type names may not collide with built-in names
- custom widgets must declare `binds`
- custom widgets may optionally declare `geometry = { ... }` to whitelist supported `node.geometry` keys
- all UI helpers that accept `customTypes` merge them with built-ins for validation and draw

## Widget Geometry

Certain widgets support a widget-local `geometry` bag for manual horizontal placement:

```lua
{
    type = "dropdown",
    binds = { value = "Mode" },
    label = "Mode",
    values = { "Vanilla", "Forced" },
    geometry = {
        controlStart = 220,
        controlWidth = 180,
    },
}
```

Current built-in support:
- `dropdown`: `controlStart`, `controlWidth`
- `stepper`: `controlStart`, `decrementStart`, `valueStart`, `valueWidth`, `valueAlign`, `incrementStart`
- `steppedRange`: `controlStart`, `control2Start`, `separatorStart`, plus the shared stepper keys above

Behavior:
- `controlStart`, `control2Start`, and `separatorStart` are relative to the current row origin after any `indent`
- `decrementStart`, `valueStart`, `valueWidth`, and `incrementStart` are relative to the enclosing stepper control start
- `valueStart` is the absolute value-text position
- `valueAlign` may be `center` or `right` and aligns the value text inside an explicit `valueWidth` slot derived after the decrement button
- start positions must be non-negative
- `valueAlign` requires an explicit `valueWidth`
- `valueStart` cannot be combined with `valueWidth` or `valueAlign`
- if a geometry key is omitted, the widget falls back to its default rendering
- unknown geometry keys warn during validation

## Managed UI State

`store.uiState` stages by alias, not by field/config key.

Surface:
- `uiState.view`
- `uiState.get(alias)`
- `uiState.set(alias, value)`
- `uiState.update(alias, fn)`
- `uiState.toggle(alias)`
- `uiState.reloadFromConfig()`
- `uiState.flushToConfig()`
- `uiState.isDirty()`

Behavior:
- packed child alias writes update the owning packed root in staging
- flush writes only dirty root storage nodes
- `view` is read-only

### `lib.runUiStatePass(opts)`

Runs one draw pass for managed alias-backed state and flushes or commits if dirty.

Important options:
- `uiState`
- `draw(imgui, uiState, theme)`
- `commit(uiState)` optional transactional commit hook
- `onFlushed()` optional success callback

### `lib.commitUiState(def, store, uiState)`

Transactional managed-state commit helper.

Behavior:
- snapshots dirty persisted root values
- flushes staged values
- if needed, reapplies runtime state
- on failure, restores persisted values and reloads `uiState`

### `lib.auditAndResyncUiState(name, uiState)`

Audits staged alias state against persisted config, warns on drift, then reloads staged values.

## Mutation Lifecycle

### `lib.inferMutationShape(def)`

Infers one of:
- `patch`
- `manual`
- `hybrid`
- `nil`

### `lib.applyDefinition(def, store)`

Applies a module definition using the inferred lifecycle shape.

### `lib.revertDefinition(def, store)`

Reverts a module definition using the inferred lifecycle shape.

### `lib.reapplyDefinition(def, store)`

Reverts then reapplies a definition. Stops if revert fails.

### `lib.setDefinitionEnabled(def, store, enabled)`

Transactional enable or disable helper:
- runs lifecycle work first
- only writes `Enabled` after success

Behavior:
- `false -> true`: apply
- `true -> true`: reapply
- `true -> false`: revert
- `false -> false`: no-op

### `lib.createBackupSystem()`

Returns:
- `backup(tbl, ...)`
- `restore()`

Use this for manual mutation modules that need first-write backup or restore semantics.

### `lib.createMutationPlan()`

Creates a reversible patch plan for data-mutation modules.

Supported operations:
- `plan:set(tbl, key, value)`
- `plan:setMany(tbl, kv)`
- `plan:transform(tbl, key, fn)`
- `plan:append(tbl, key, value)`
- `plan:appendUnique(tbl, key, value, equivalentFn?)`
- `plan:removeElement(tbl, key, value, equivalentFn?)`
- `plan:setElement(tbl, key, oldValue, newValue, equivalentFn?)`
- `plan:apply()`
- `plan:revert()`

## Registries

### `lib.StorageTypes`

Lib-owned storage registry.

Built-ins:
- `bool`
- `int`
- `string`
- `packedInt`

### `lib.WidgetTypes`

Lib-owned widget registry.

Built-ins:
- `checkbox`
- `dropdown`
- `radio`
- `stepper`
- `steppedRange`
- `packedCheckboxList`

### `lib.LayoutTypes`

Lib-owned layout registry.

Built-ins:
- `separator`
- `group`

### `lib.validateRegistries()`

Hard-validates registry contracts.

## Standalone Helpers

### `lib.standaloneUI(def, store)`

Returns a menu-bar callback for regular modules running without a coordinator.

### `lib.standaloneSpecialUI(def, store, uiState?, opts?)`

Returns `{ renderWindow, addMenuBar }` for special modules running without a coordinator.

If `def.ui` exists and no custom `DrawTab` is supplied, the helper renders `def.ui` automatically.

## Path Helpers

### `lib.readPath(tbl, key)`

Reads from a flat key or nested path array.

### `lib.writePath(tbl, key, value)`

Writes to a flat key or nested path array, creating intermediate tables as needed.

## Coordinator Helpers

### `lib.isEnabled(store, packId?)`

Returns `true` only when:
- the module store has `Enabled = true`
- and, if coordinated, the pack-level `ModEnabled` flag is also true

### `lib.affectsRunData(def)`

Returns whether successful lifecycle or config changes require run-data rebuild behavior.

## Warnings and Logging

### `lib.warn(packId, enabled, fmt, ...)`

Debug-gated framework warning.

### `lib.contractWarn(packId, fmt, ...)`

Always-on framework contract or compatibility warning.

### `lib.log(name, enabled, fmt, ...)`

Module-local debug trace helper.
