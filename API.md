# adamant-ModpackLib API

This is the current public Lib surface.

Preferred usage is namespaced:
- `lib.store.*`
- `lib.storage.*`
- `lib.mutation.*`
- `lib.host.*`
- `lib.coordinator.*`
- `lib.logging.*`
- `lib.widgets.*`
- `lib.nav.*`

Old flat `lib.*` names should be treated as obsolete compatibility only.

## Core Model

Modules now declare:
- `definition.modpack`
- `definition.id`
- `definition.name`
- `definition.storage`
- optional mutation lifecycle fields:
  - `affectsRunData`
  - `patchPlan`
  - `apply`
  - `revert`

Modules render UI directly:
- `public.DrawTab(ui, uiState)`
- optional `public.DrawQuickContent(ui, uiState)`

There is no supported new authoring based on:
- `definition.ui`
- `definition.customTypes`
- `selectQuickUi`

Those fields are ignored under the current lean contract and only exist as stale compatibility surface.

## `lib.store`

### `lib.store.create(config, definition, dataDefaults?)`

Creates the managed store facade around persisted module config.

What it does:
- warns on malformed top-level definition fields
- seeds missing storage defaults from `dataDefaults`
- validates and prepares `definition.storage`
- creates `store.uiState`
- exposes persisted read/write helpers

Typical use:

```lua
public.store = lib.store.create(config, public.definition, dataDefaults)
store = public.store
```

Returned surface:
- `store.read(keyOrAlias)`
- `store.write(keyOrAlias, value)`
- `store.readBits(configKey, offset, width)`
- `store.writeBits(configKey, offset, width, value)`
- `store.getPackedAliases(alias)`
- `store.storage`
- `store.uiState`

Rules:
- widgets and draw code should usually read staged values from `store.uiState.view`
- runtime/gameplay code should read persisted values through `store.read(...)`
- transient aliases are not readable or writable through `store.read/write`

### `store.uiState`

Managed staged UI state for the module.

Useful surface:
- `uiState.view`
- `uiState.get(alias)`
- `uiState.set(alias, value)`
- `uiState.update(alias, fn)`
- `uiState.toggle(alias)`
- `uiState.reset(alias)`
- `uiState.isDirty()`
- `uiState.flushToConfig()`
- `uiState.reloadFromConfig()`
- `uiState.collectConfigMismatches()`
- `uiState.getAliasNode(alias)`

Behavior:
- persisted aliases stage in `uiState` and only hit config on flush/commit
- transient aliases live only in `uiState`
- packed child aliases re-encode their owning packed root automatically

## `lib.storage`

### `lib.storage.validate(storage, label)`

Validates and prepares a storage declaration table in place.

Validation covers:
- alias uniqueness
- persistent root key uniqueness
- packed bit overlap
- lifetime rules
- storage-type-specific validation

### `lib.storage.getRoots(storage)`

Returns prepared persisted root nodes.

### `lib.storage.getAliases(storage)`

Returns the prepared alias map.

Includes:
- persisted root aliases
- transient root aliases
- packed child aliases

### `lib.storage.getPackWidth(node)`

Returns the derived pack width for a node type that supports packing.

### `lib.storage.valuesEqual(node, a, b)`

Storage-aware equality helper.

### `lib.storage.toHash(node, value)`

Encodes one storage value for hash/profile serialization.

### `lib.storage.fromHash(node, str)`

Decodes one storage value from hash/profile serialization.

### `lib.storage.readPackedBits(packed, offset, width)`

Raw numeric bit extraction helper.

### `lib.storage.writePackedBits(packed, offset, width, value)`

Raw numeric bit write helper.

## `lib.mutation`

### `lib.mutation.inferShape(def)`

Infers the mutation lifecycle shape:
- `patch`
- `manual`
- `hybrid`
- or `nil`

### `lib.mutation.mutatesRunData(def)`

Returns whether `def.affectsRunData == true`.

### `lib.mutation.createBackup()`

Returns:
- `backup(tbl, ...)`
- `restore()`

For reversible table mutation capture.

### `lib.mutation.createPlan()`

Creates a reversible mutation plan with:
- `plan:set(...)`
- `plan:setMany(...)`
- `plan:transform(...)`
- `plan:append(...)`
- `plan:appendUnique(...)`
- `plan:removeElement(...)`
- `plan:setElement(...)`
- `plan:apply()`
- `plan:revert()`

### `lib.mutation.apply(def, store)`

Applies the module’s mutation lifecycle.

### `lib.mutation.revert(def, store)`

Reverts the module’s mutation lifecycle.

### `lib.mutation.reapply(def, store)`

Reverts and reapplies the module’s mutation lifecycle.

### `lib.mutation.setEnabled(def, store, enabled)`

Transitions persisted enabled state and applies/reverts mutation state as needed.

## `lib.host`

### `lib.host.runDerivedText(uiState, entries, cache?)`

Recomputes derived transient text aliases from staged UI state.

Use this only when it actually helps readability.
Most current module UI should compute strings directly at draw time.

### `lib.host.auditAndResyncState(name, uiState)`

Audits staged state against persisted config, logs drift, then reloads staged values from config.

### `lib.host.commitState(def, store, uiState)`

Transactional commit helper for staged `uiState`.

Behavior:
- flushes staged persisted values to config
- if the module is enabled and `affectsRunData`, reapplies mutation state
- on failure, restores the previous config snapshot and reloads `uiState`

### `lib.host.standaloneUI(def, store, uiState?, opts?)`

Creates a standalone window/menu-bar runtime for a module.

Useful when the module is not framework-hosted.

Returned surface:
- `runtime.renderWindow()`
- `runtime.addMenuBar()`

Current optional hooks in `opts`:
- `getDrawTab`
- `getDrawQuickContent`
- `getBeforeDrawTab`
- `getAfterDrawTab`
- `drawTab`
- `drawQuickContent`
- `beforeDrawTab`
- `afterDrawTab`
- `windowTitle`

Note:
- framework-hosted modules no longer use before/after draw hooks
- they still exist here for standalone callers that may still need them

## `lib.coordinator`

### `lib.coordinator.register(packId, config)`

Registers coordinator config for a pack.

### `lib.coordinator.isCoordinated(packId)`

Returns whether a pack id is registered.

### `lib.coordinator.isEnabled(store, packId?)`

Returns whether a module should currently be treated as enabled, taking pack-level coordination into account when present.

## `lib.logging`

### `lib.logging.warnIf(packId, enabled, fmt, ...)`

Conditionally emits a module-scoped warning.

### `lib.logging.warn(packId, fmt, ...)`

Unconditionally emits a module-scoped warning.

### `lib.logging.logIf(name, enabled, fmt, ...)`

Conditionally emits a module-scoped log line.

## `lib.widgets`

Immediate-mode widget helpers.

Current built-ins:
- `lib.widgets.separator(imgui)`
- `lib.widgets.text(imgui, text, opts?)`
- `lib.widgets.button(imgui, label, opts?)`
- `lib.widgets.confirmButton(imgui, id, label, opts?)`
- `lib.widgets.inputText(imgui, uiState, alias, opts?)`
- `lib.widgets.dropdown(imgui, uiState, alias, opts?)`
- `lib.widgets.mappedDropdown(imgui, uiState, alias, opts?)`
- `lib.widgets.packedDropdown(imgui, uiState, alias, store, opts?)`
- `lib.widgets.radio(imgui, uiState, alias, opts?)`
- `lib.widgets.mappedRadio(imgui, uiState, alias, opts?)`
- `lib.widgets.packedRadio(imgui, uiState, alias, store, opts?)`
- `lib.widgets.stepper(imgui, uiState, alias, opts?)`
- `lib.widgets.steppedRange(imgui, uiState, minAlias, maxAlias, opts?)`
- `lib.widgets.checkbox(imgui, uiState, alias, opts?)`
- `lib.widgets.packedCheckboxList(imgui, uiState, alias, store, opts?)`

These are direct immediate-mode helpers, not declarative node renderers.

## `lib.nav`

### `lib.nav.verticalTabs(imgui, opts)`

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

### `lib.nav.isVisible(uiState, condition)`

Evaluates a `visibleIf`-style condition against `uiState.view`.

Supported forms:
- `"AliasName"`
- `{ alias = "AliasName", value = ... }`
- `{ alias = "AliasName", anyOf = { ... } }`
