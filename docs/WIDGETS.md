# Widgets, Nav, Session, and Hashing

This document covers:
- storage typing and packing
- session helpers
- hash/profile packing helpers
- immediate-mode widgets
- navigation helpers

## Storage Schema

Module storage is declared on `definition.storage`, prepared by `lib.prepareDefinition(...)`, and then consumed by `lib.createStore(...)`.

Built-in root types:
- `bool`
- `int`
- `string`
- `packedInt`

Storage metadata helpers used for hash/profile work live under `lib.hashing`.

## Reset Helpers

- `lib.resetStorageToDefaults(storage, session, opts?)`

## Hashing

Hash/profile serialization helpers live under `lib.hashing`.

Supported helpers:
- `lib.hashing.getRoots(storage)`
- `lib.hashing.getAliases(storage)`
- `lib.hashing.valuesEqual(node, a, b)`
- `lib.hashing.getPackWidth(node)`
- `lib.hashing.toHash(node, value)`
- `lib.hashing.fromHash(node, str)`
- `lib.hashing.readPackedBits(...)`
- `lib.hashing.writePackedBits(...)`

## Widgets

Widgets live under `lib.widgets`.

Built-ins:
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

These are direct immediate-mode helpers. Call them inside module draw functions to render one control at a time.

Typical call shape:

```lua
lib.widgets.dropdown(ui, session, "Mode", {
    label = "Mode",
    values = { "Vanilla", "Chaos" },
    controlWidth = 180,
})
```

All bound widgets return:
- `true` when they changed staged `session`
- `false` otherwise

## Common concepts

### Bound widgets

Most widgets bind to one staged session alias:
- `checkbox`
- `inputText`
- `dropdown`
- `mappedDropdown`
- `radio`
- `mappedRadio`
- `stepper`

Some bind to packed roots and therefore also need `store`:
- `packedDropdown`
- `packedRadio`
- `packedCheckboxList`

The `store` argument is used for packed-root metadata lookup.

One binds to two aliases:
- `steppedRange(minAlias, maxAlias, ...)`

Author draw code can read staged values through `session.view.SomeAlias` for readability. Widget internals use `session.read(alias)` and write changes through `session.write(alias, value)`.

### Labels and tooltips

Most leaf widgets support:
- `label`
- `tooltip`

The label is rendered inline by the widget itself.
Use `labelWidth` on labeled controls when several rows should align their controls to the same X position. `labelWidth` is measured from the row start to the control start. If a label is longer than that width, the widget falls back to normal gap spacing so the label does not overlap the control.
If you need more custom layout than that, write the surrounding ImGui yourself and use the widget with an empty label.

### Colors

Some widgets support value coloring:
- `text.color`
- `checkbox.color`
- `dropdown.valueColors`
- `mappedDropdown` option colors
- `radio.valueColors`
- `mappedRadio` option colors
- packed widget `valueColors`

Colors are RGBA tables:

```lua
{ 1, 0.8, 0, 1 }
```

## Base widgets

### `lib.widgets.separator(imgui)`

Thin wrapper around `imgui.Separator()`.

Use when:
- you want a Lib-level helper for consistency

### `lib.widgets.text(imgui, text, opts?)`

Options:
- `color`
- `tooltip`
- `alignToFramePadding`

Use when:
- you want a text line with optional color or tooltip

Example:

```lua
lib.widgets.text(ui, "Underworld", {
    color = { 0.8, 0.7, 0.4, 1 },
    alignToFramePadding = true,
})
```

### `lib.widgets.button(imgui, label, opts?)`

Options:
- `id`
- `tooltip`
- `onClick(imgui)`

Notes:
- returns whether the button was clicked
- `onClick` is optional convenience only; you can ignore it and use the boolean return directly

### `lib.widgets.confirmButton(imgui, id, label, opts?)`

Renders a button that opens a confirmation popup.

Options:
- `tooltip`
- `confirmLabel`
- `cancelLabel`
- `onConfirm(imgui)`

Notes:
- returns `true` only when the confirm action is taken
- this is good for destructive or global reset actions

## Input widget

### `lib.widgets.inputText(imgui, session, alias, opts?)`

Options:
- `label`
- `tooltip`
- `maxLen`
- `labelWidth`
- `controlWidth`
- `controlGap`

Behavior:
- reads current text from `session.read(alias)`
- writes the edited string back through `session.write(alias, nextValue)`

Use when:
- the bound alias is a string field
- you need plain text entry or a simple filter box

## Choice widgets

### `lib.widgets.dropdown(imgui, session, alias, opts?)`

Options:
- `label`
- `tooltip`
- `values`
- `default`
- `displayValues`
- `valueColors`
- `labelWidth`
- `controlWidth`
- `controlGap`

Behavior:
- binds one alias to one value from `values`
- preview text comes from `displayValues[value]` when present, else `tostring(value)`
- if the staged value is invalid, it falls back to:
  - a valid `default`
  - else the first entry in `values`

Use when:
- the widget owns a fixed explicit choice list

### `lib.widgets.mappedDropdown(imgui, session, alias, opts?)`

Options:
- `label`
- `tooltip`
- `labelWidth`
- `controlWidth`
- `controlGap`
- `getPreview(view)`
- `getPreviewColor(view)`
- `getOptions(view)`

Each returned option may include:
- `id`
- `label`
- `value`
- `color`
- `onSelect(option, session)`

Behavior:
- the option list is computed from live staged state
- `getPreview`, `getPreviewColor`, and `getOptions` receive `session.view`
- if an option provides `onSelect`, that callback owns the write behavior
- otherwise the widget writes `option.value` to `alias`

Use when:
- the choice list is dynamic
- preview text depends on derived state
- selecting an option needs custom logic

Example:

```lua
lib.widgets.mappedDropdown(ui, session, "SelectedRoot", {
    label = "Root",
    controlWidth = 220,
    getPreview = function(view)
        return view.SelectedRoot ~= "" and view.SelectedRoot or "Choose Root"
    end,
    getOptions = function(view)
        return {
            { label = "Aphrodite", value = "Aphrodite" },
            { label = "Apollo", value = "Apollo" },
            {
                label = "Clear",
                onSelect = function(_, state)
                    state.write("SelectedRoot", "")
                    return true
                end,
            },
        }
    end,
})
```

### `lib.widgets.packedDropdown(imgui, session, alias, store, opts?)`

Single-choice dropdown over a packed root.

Options:
- `label`
- `tooltip`
- `labelWidth`
- `controlWidth`
- `controlGap`
- `displayValues`
- `valueColors`
- `noneLabel`
- `multipleLabel`
- `selectionMode`

`selectionMode`:
- `singleEnabled`
- `singleDisabled`

Behavior:
- resolves packed children from store storage metadata
- packed widgets require the `store` argument so child metadata stays out of `session`
- classifies current packed state as:
  - none
  - single
  - multiple

Use when:
- a packed root represents one selected child out of many
- or the inverse "single false / all others true" style via `singleDisabled`

Example:

```lua
lib.widgets.packedDropdown(ui, session, "PackedForcedBoon", store, {
    label = "Force 1",
    noneLabel = "None",
    selectionMode = "singleEnabled",
    displayValues = {
        PackedForcedBoon_Attack = "Attack",
        PackedForcedBoon_Special = "Special",
        PackedForcedBoon_Cast = "Cast",
    },
    controlWidth = 180,
})
```

### `lib.widgets.radio(imgui, session, alias, opts?)`

Options:
- `label`
- `values`
- `default`
- `displayValues`
- `valueColors`
- `optionsPerLine`
- `optionGap`

Use when:
- the choice list is small and visible all at once is better than a combo

### `lib.widgets.mappedRadio(imgui, session, alias, opts?)`

Options:
- `label`
- `optionsPerLine`
- `optionGap`
- `getOptions(view)`

Each returned option may include:
- `label`
- `value`
- `color`
- `selected`
- `onSelect(option, session)`

Use when:
- the visible options are dynamic
- you need custom selection behavior

Note:
- `getOptions` receives `session.view`

### `lib.widgets.packedRadio(imgui, session, alias, store, opts?)`

Packed single-choice radio surface.

Options:
- `label`
- `displayValues`
- `valueColors`
- `noneLabel`
- `selectionMode`
- `optionsPerLine`
- `optionGap`

Use when:
- the packed root is better represented as always-visible choices rather than a combo

## Numeric widgets

### `lib.widgets.stepper(imgui, session, alias, opts?)`

Stepper with `-` and `+` buttons around a rendered value.

Options:
- `label`
- `default`
- `min`
- `max`
- `step`
- `displayValues`
- `labelWidth`
- `valueWidth`
- `buttonSpacing`

Behavior:
- normalizes through integer storage rules
- clamps against `min` / `max`
- can show friendly names through `displayValues[number]`

Use when:
- the value is small and ordinal
- button stepping is more readable than typing

### `lib.widgets.steppedRange(imgui, session, minAlias, maxAlias, opts?)`

Two coupled steppers rendered as:
- min stepper
- `"to"`
- max stepper

Options:
- all `StepperOpts`
- `defaultMax`
- `rangeGap`

Behavior:
- min stepper is limited by current max
- max stepper is limited by current min

Use when:
- both ends of the range should stay visible together
- you want stepper interaction instead of two dropdowns

## Boolean widgets

### `lib.widgets.checkbox(imgui, session, alias, opts?)`

Options:
- `label`
- `tooltip`
- `color`

Behavior:
- binds one boolean alias

Use when:
- the field is a plain toggle

### `lib.widgets.packedCheckboxList(imgui, session, alias, store, opts?)`

Checkbox list over packed child aliases.

Options:
- `filterText`
- `filterMode`
- `valueColors`
- `slotCount`
- `optionsPerLine`
- `optionGap`

`filterMode`:
- `all`
- `checked`
- `unchecked`

Behavior:
- resolves packed children from store storage metadata
- text filter is case-insensitive substring match on option labels
- items are laid out inline according to `optionsPerLine`
- rendering stops after `slotCount` matches

Use when:
- a packed root is really a bitmask of many independent bool choices
- boon-ban style lists

Example:

```lua
lib.widgets.packedCheckboxList(ui, session, "PackedBannedAphrodite", store, {
    filterText = session.view.BanFilterText,
    optionsPerLine = 2,
    valueColors = {
        PackedBannedAphrodite_Attack = { 1, 0.8, 0.8, 1 },
        PackedBannedAphrodite_Special = { 1, 0.8, 0.8, 1 },
    },
})
```

## Choosing the right widget

Use:
- `dropdown` when the choices are static
- `mappedDropdown` when the choices or preview are dynamic
- `packedDropdown` when one packed child is effectively selected
- `radio` when the static choices should stay visible
- `mappedRadio` when visible choices are dynamic
- `packedRadio` when packed single-choice state should stay visible
- `checkbox` for one bool
- `packedCheckboxList` for many packed bool flags
- `stepper` for one bounded int
- `steppedRange` for two coupled ints

## Nav

Navigation helpers live under `lib.nav`.

Surface:
- `lib.nav.verticalTabs(ui, opts)`
- `lib.nav.isVisible(session, condition)`

`verticalTabs(...)` renders a simple immediate-mode vertical tab rail.

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

## Scope

Widgets are direct immediate-mode helpers. Each call draws one control and returns its value and change flag. Composition is ordinary Lua control flow: authors call the helpers they want, in the order they want, inside their own `drawTab` function.
