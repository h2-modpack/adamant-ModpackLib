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

Before storage/UI validation, Lib also runs `lib.validateDefinition(...)` on the
flat `definition` table to catch unknown keys, ignored special/regular fields,
and incomplete lifecycle declarations early.

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

### `lib.validateDefinition(def, label?)`

Runs the early definition warning pass for the flat module definition table.

Current warnings cover:
- unknown top-level definition keys
- wrong value types for known definition fields
- regular-only fields used on specials
- special-only fields used on regular modules
- incomplete manual lifecycle declarations like `apply` without `revert`
- `affectsRunData = true` without any supported lifecycle

This helper does not replace storage/UI validation.
It exists to keep authoring mistakes visible without changing the flat shape of
`definition`.

### `store.read(keyOrAlias)`

Reads:
- a root storage alias
- a packed child alias
- or a raw config key fallback

Transient aliases are UI-only and are not readable through `store.read(...)`; use `store.uiState`.

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

Transient aliases are UI-only and are not writable through `store.write(...)`; use `store.uiState`.

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
- root lifetime validation

### `lib.getStorageRoots(storage)`

Returns the prepared root storage nodes.

Only root nodes:
- persist directly
- hash directly
- flush directly

Transient roots declared with `lifetime = "transient"` are intentionally excluded.

### `lib.getStorageAliases(storage)`

Returns the prepared alias map:

```lua
local aliases = lib.getStorageAliases(definition.storage)
local node = aliases.AttackBanned
```

Includes:
- root aliases
- packed child aliases
- transient root aliases

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

### `lib.prepareWidgetNode(node, label?, customTypes?)`

Validates and prepares one direct-draw widget node without requiring storage binds.

Useful for transitional custom widgets that are drawn manually with synthetic bound values, but still want cached slot geometry and normal custom-widget validation.

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
- `packedCheckboxList` through packed child alias expansion and optional filter binds (`filterText`, `filterMode`)
- layout recursion through `children`
- module-local custom widget/layout registries through `customTypes`

Contract:
- pass prepared nodes created through `lib.prepareUiNode(...)` / `lib.prepareUiNodes(...)`
- Lib owns structured child start positions during draw
- structured children are expected to settle the cursor at the bottom of the space they consumed before returning

### `lib.drawUiTree(imgui, nodes, uiState, width?, customTypes?)`

Draws an ordered UI node list.

### `lib.drawWidgetSlots(imgui, node, slots, rowStart?, rowStartY?)`

Public helper for custom widget `draw(...)` implementations that want Lib-managed slot placement.

Behavior:
- uses the prepared slot geometry from `node.geometry`
- defaults `rowStart` to the current cursor X
- defaults `rowStartY` to the current cursor Y
- keeps `line` as the public vertical descriptor; actual row `y` is resolved internally by Lib
- slots with explicit `start` use explicit positioning; slots without `start` may still use inline horizontal flow within the resolved row
- pass `rowStartY` explicitly when a custom widget is composing a local atomic sub-structure and should not inherit the ambient cursor baseline
- returns `true` if any slot draw returns `true`

### `lib.alignSlotContent(imgui, slot, contentWidth)`

Applies slot-local `width` / `align` positioning for already-measured content.

Useful inside custom widget slot draws when the widget knows the content width but wants Lib to handle the centering/right-align math.

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
            slots = { "label", "control" }, -- optional supported geometry slot names
            defaultGeometry = { slots = { ... } }, -- optional widget-owned baseline geometry
            dynamicSlots = function(node, slotName) ... end, -- optional declaration-time slot validator
            validate = function(node, prefix) ... end,
            draw = function(imgui, node, bound, width, uiState) ... end,
        },
    },
    layouts = {
        myLayout = {
            handlesChildren = true, -- optional: layout owns child drawing
            validate = function(node, prefix) ... end,
            render = function(imgui, node, drawChild) ... end,
        },
    },
}
```

Rules:
- custom widget and layout type names may not collide with built-in names
- custom widgets must declare `binds`
- custom widgets must declare `draw(...)`
- widget bind specs may declare `storageType` for value-kind matching, optional `rootType` for exact storage node matching, and optional `optional = true` for non-required binds
- custom widgets may optionally declare `slots = { ... }` to whitelist supported `node.geometry.slots[*].name` values
- custom widgets may optionally declare `defaultGeometry = { slots = { ... } }` as their baseline slot layout
- custom widgets may optionally declare `dynamicSlots(node, slotName) -> ok, err` for declaration-time-dependent slot names
- all UI helpers that accept `customTypes` merge them with built-ins for validation and draw

Custom widget `draw(...)` may either:
- ignore slots entirely and render imperatively
- or call `lib.drawWidgetSlots(...)` to let Lib handle slot ordering, default geometry, and node geometry

When a custom widget uses `lib.drawWidgetSlots(...)`, `slots` and `defaultGeometry` become the normal placement surface rather than validation-only metadata.

Custom layout `render(...)` contract:
- `render(imgui, node, drawChild)` always receives `drawChild`
- return `open` for simple layouts that let Lib recurse children normally
- layouts that own child placement should declare `handlesChildren = true`
- when `handlesChildren = true`, `render(...)` should return `open, changed`
- when `handlesChildren = true`, the layout owns child rendering and should call `drawChild(child)` itself
- when `handlesChildren = true`, `changed` must include any child-driven state change
- Lib-managed structured layouts assign child start positions explicitly; custom layouts that own child placement should preserve the same rule
- child widgets/layouts should settle the cursor at the bottom of the space they consumed before control returns to the parent layout

## Widget Geometry

Certain widgets support a widget-local `geometry` bag for manual horizontal placement:

```lua
{
    type = "dropdown",
    binds = { value = "Mode" },
    label = "Mode",
    values = { "Vanilla", "Forced" },
    geometry = {
        slots = {
            { name = "control", start = 220, width = 180 },
        },
    },
}
```

Current built-in support:
- `text`: `value`
- `button`: `control`
- `confirmButton`: `control`
- `checkbox`: `control`
- `inputText`: `label`, `control`
- `dropdown`: `label`, `control` (`string` or `int` choice storage)
- `mappedDropdown`: `label`, `control`
- `mappedRadio`: `label`
- `radio`: `label`, dynamic `option:N` (`string` or `int` choice storage)
- `stepper`: `label`, `decrement`, `value`, `increment`, optional `fastDecrement`, `fastIncrement`
- `steppedRange`: `label`, `min.*`, `separator`, `max.*`
- `packedCheckboxList`: dynamic `item:N`; `slotCount` defaults to `32` when omitted

Behavior:
- `geometry.slots` is a list of slot descriptors
- each slot descriptor may declare `name`, `line`, `start`, `width`, and `align`
- `line` defaults to `1` and must be a positive integer when present
- `line` is the public vertical placement surface; Lib resolves it to explicit internal row `y`
- `start` is relative to the current row origin after any `indent`
- `width` must be positive when present
- `align` may be `center` or `right` and requires an explicit `width`
- slots are rendered in ascending `line`
- within the same line, slots with explicit `start` values are ordered by `start`
- otherwise declaration order breaks ties and preserves slots without explicit `start`
- `radio` supports `option:N` slot names for each entry in `node.values`
- `packedCheckboxList` supports `item:N` slot names
- `slotCount` is the declaration-time slot capacity for `packedCheckboxList`; if omitted, Lib defaults it to `32`
- packed children may be omitted at runtime, but the widget does not create new slots beyond the declared capacity
- if a slot is omitted, the widget falls back to its default rendering for that slot
- unknown top-level geometry keys and unsupported slot names warn during validation
- `radio` option slots and packed list `item:N` slots meaningfully use `line` and `start`; `width` and `align` are accepted by the generic parser but currently warn because those widgets do not consume them

Built-in slot intent:
- `text.value`: use `line` / `start`; `width` + `align` are meaningful
- `button.control`: use `line` / `start`; `width` + `align` are meaningful when you want to place the button inside a fixed slot
- `confirmButton.control`: use `line` / `start`; `width` + `align` are most meaningful for the idle button placement; the armed confirm row expands inline
- `checkbox.control`: use `line` / `start`; `width` / `align` are not meaningful
- `inputText.label`: use `line` / `start`; `width` / `align` are not meaningful
- `inputText.control`: use `line` / `start`; `width` is meaningful; `align` is not and currently warns
- `dropdown.label`: use `line` / `start`; `width` / `align` are not meaningful
- `dropdown.control`: use `line` / `start`; `width` is meaningful; `align` is not; `displayValues` / `valueColors` affect rendered presentation only
- `mappedDropdown.label`: use `line` / `start`; `width` / `align` are not meaningful
- `mappedDropdown.control`: use `line` / `start`; `width` is meaningful; `align` is not
- `mappedRadio.label`: use `line` / `start`; `width` / `align` are not meaningful
- `radio.option:N`: use `line` / `start`; `width` / `align` are not meaningful and currently warn; `displayValues` / `valueColors` affect rendered presentation only
- `stepper.value`: use `line` / `start`; `width` + `align` are meaningful; `displayValues` / `valueColors` affect rendered presentation only
- `stepper` button slots: use `line` / `start`; `width` / `align` are not meaningful
- `steppedRange.min.value`, `steppedRange.max.value`: use `line` / `start`; `width` + `align` are meaningful
- `steppedRange.separator`: use `line` / `start`; `width` + `align` are meaningful
- `steppedRange` button slots: use `line` / `start`; `width` / `align` are not meaningful
- `packedCheckboxList.item:N`: use `line` / `start`; `width` / `align` are not meaningful and currently warn; optional `filterText`, `filterMode`, and `valueColors[childAlias]` affect which packed rows render and how their labels are styled

Text/tab presentation:
- `text.color = { r, g, b }` or `{ r, g, b, a }` colors a single rendered text node
- `horizontalTabs` and `verticalTabs` children may declare `tabLabelColor = { r, g, b }` or `{ r, g, b, a }` to color that child tab label

## Managed UI State

`store.uiState` stages by alias, not by field/config key.

Surface:
- `uiState.view`
- `uiState.get(alias)`
- `uiState.set(alias, value)`
- `uiState.reset(alias)`
- `uiState.update(alias, fn)`
- `uiState.toggle(alias)`
- `uiState.reloadFromConfig()`
- `uiState.flushToConfig()`
- `uiState.isDirty()`

Behavior:
- packed child alias writes update the owning packed root in staging
- `reset(alias)` restores the declared default for that alias
- flush writes only dirty root storage nodes
- transient aliases never flush to config
- `reloadFromConfig()` reloads persisted aliases and resets transient aliases to defaults
- `isDirty()` reflects persisted dirty state only
- `view` is read-only

### `lib.runUiStatePass(opts)`

Runs one draw pass for managed alias-backed state and flushes or commits if dirty.

Important options:
- `uiState`
- `beforeDraw(imgui, uiState, theme)` optional pre-draw hook
- `draw(imgui, uiState, theme)`
- `afterDraw(imgui, uiState, theme, changed)` optional post-draw hook
- `commit(uiState)` optional transactional commit hook
- `onFlushed()` optional success callback

Behavior:
- `beforeDraw(...)` runs before `draw(...)`
- `draw(...)` may return `true` to indicate a meaningful UI change during that draw pass
- `afterDraw(...)` runs after `draw(...)` and receives that boolean `changed` signal
- `beforeDraw(...)` and `afterDraw(...)` may still stage `uiState` changes; commit/flush handling runs after both hooks complete

### `lib.runDerivedText(uiState, entries, cache?)`

Runs a lightweight derived-text pass for transient string aliases.

Use this for:
- summaries
- empty-state messages
- status lines

Entry shape:

```lua
{
    alias = "SummaryText",
    compute = function(uiState)
        return "Current: " .. tostring(uiState.view.Mode)
    end,
    signature = function(uiState)
        return uiState.view.Mode
    end, -- optional
}
```

Behavior:
- `compute(uiState)` returns the next text value
- values are normalized with `tostring(...)`
- `signature(uiState)` may be used to skip recomputation when inputs are unchanged
- `cache` is caller-owned and optional
- when a cache is used, the caller owns its lifecycle and invalidation boundary; changing the derived-text entry set or meaningfully changing `signature(...)` inputs should produce a new signature value or a fresh cache
- only writes `uiState.set(alias, value)` when the derived text changed

This helper is intentionally limited to string display state. It is not a general reactive widget or layout system.

### `lib.getCachedPreparedNode(cacheEntry, signature, buildFn, opts?)`

Reusable prepared-node cache helper for special modules and other caller-owned UI builders.

Returns:
- `cacheEntry`
- `node`
- `rebuilt`
- `previousNode`

Behavior:
- if `cacheEntry.signature == signature` and `cacheEntry.node` exists, returns the cached prepared node unchanged
- otherwise calls `buildFn(previousNode)` to produce the next node
- if `opts.reuseState(node, previousNode)` is provided, it runs after rebuild so caller-owned node state can be copied forward explicitly
- the caller owns the cache table, signature contents, and invalidation boundary

Cache ownership convention:
- Lib owns mechanical caches attached to prepared nodes and internal helper tables
- modules own semantic cache signatures and invalidation policy
- change the signature when the rendered structure meaningfully changes
- use explicit invalidation when cached semantic summaries or labels become stale because underlying domain data changed outside the node-builder path

Typical use:
- cache prepared tab trees, panels, and other reusable node subtrees in special modules
- preserve small pieces of caller-owned UI state through `reuseState(...)` when rebuild is necessary

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
- `text`
- `button`
- `confirmButton`
- `checkbox`
- `inputText`
- `dropdown`
- `mappedDropdown`
- `mappedRadio`
- `radio`
- `stepper`
- `steppedRange`
- `packedCheckboxList`

Widget definitions may also declare optional flat capability functions such as:
- `dynamicSlots(node, slotName)`
- `defaultGeometry(node)`

### `lib.WidgetHelpers`

Public namespace for small widget-authoring helpers that do not belong on `lib.WidgetTypes`.

Current helpers:
- `lib.WidgetHelpers.drawStructuredAt(imgui, startX, startY, fallbackHeight, drawFn)`
- `lib.WidgetHelpers.estimateRowAdvanceY(imgui)`

Use these for atomic custom widgets that need positioned local composition but should still participate honestly in the parent footprint contract.

These helpers are intended for:
- custom widget internals
- local leaf-widget composition

They are **not** a generic invitation to recursively draw full prepared widgets from inside other widgets.

### `lib.LayoutTypes`

Lib-owned layout registry.

Built-ins:
- `separator`
- `group`
- `horizontalTabs`
- `verticalTabs`
- `panel`

### `lib.validateRegistries()`

Hard-validates registry contracts.

## Standalone Helpers

### `lib.standaloneUI(def, store)`

Returns a menu-bar callback for regular modules running without a coordinator.

### `lib.standaloneSpecialUI(def, store, uiState?, opts?)`

Returns `{ renderWindow, addMenuBar }` for special modules running without a coordinator.

If `def.ui` exists and no custom `DrawTab` is supplied, the helper renders `def.ui` automatically.

Supported optional hook accessors:
- `getBeforeDrawQuickContent()`
- `getAfterDrawQuickContent()`
- `getBeforeDrawTab()`
- `getAfterDrawTab()`

Static hook options are also accepted:
- `beforeDrawQuickContent`
- `afterDrawQuickContent`
- `beforeDrawTab`
- `afterDrawTab`

These hooks are forwarded into `lib.runUiStatePass(...)` for the quick-content and tab passes respectively.

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
