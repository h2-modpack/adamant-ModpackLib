# Widgets, Nav, and Storage

Current live coverage:
- storage typing and packing
- immediate-mode widgets
- navigation helpers

It does not describe a declarative UI tree/runtime anymore.

## Storage

Storage lives under `lib.storage`.

Built-in root types:
- `bool`
- `int`
- `string`
- `packedInt`

Supported helpers:
- `lib.storage.validate(storage, label)`
- `lib.storage.getRoots(storage)`
- `lib.storage.getAliases(storage)`
- `lib.storage.getPackWidth(node)`
- `lib.storage.valuesEqual(node, a, b)`
- `lib.storage.toHash(node, value)`
- `lib.storage.fromHash(node, str)`
- `lib.storage.readPackedBits(...)`
- `lib.storage.writePackedBits(...)`

Storage is now the only typed schema layer left in Lib.

## Widgets

Widgets live under `lib.widgets`.

Current built-ins:
- `separator`
- `text`
- `button`
- `confirmButton`
- `inputText`
- `dropdown`
- `mappedDropdown`
- `packedDropdown`
- `radio`
- `mappedRadio`
- `packedRadio`
- `stepper`
- `steppedRange`
- `checkbox`
- `packedCheckboxList`

These are direct immediate-mode helpers.

They are not:
- prepared nodes
- registry entries
- declarative widget descriptors

Typical call shape:

```lua
lib.widgets.dropdown(ui, uiState, "Mode", {
    label = "Mode",
    values = { "Vanilla", "Chaos" },
    controlWidth = 180,
})
```

## Nav

Navigation helpers live under `lib.nav`.

Current surface:
- `lib.nav.verticalTabs(ui, opts)`
- `lib.nav.isVisible(uiState, condition)`

`verticalTabs(...)` is the current replacement for the old vertical tab layout runtime.

Example:

```lua
activeKey = lib.nav.verticalTabs(ui, {
    id = "ExampleTabs",
    navWidth = 220,
    activeKey = activeKey,
    tabs = {
        { key = "settings", label = "Settings" },
        { key = "advanced", label = "Advanced", color = { 1, 0.8, 0, 1 } },
    },
})
```

## What Was Removed

The old field-registry/declarative UI surface is no longer the live model.

Do not write new code around:
- widget registries
- layout registries
- `prepareUiNode(...)`
- `prepareWidgetNode(...)`
- `drawTree(...)`
- quick-node collection
- custom widget/layout registry extension

If a module still carries that shape, it is historical compatibility residue, not the preferred contract.
