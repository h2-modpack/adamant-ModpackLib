# Widgets and Navigation

This document covers `draw.widgets.*` and `draw.nav.*` from a module draw-code point of view.

Draw callbacks receive a `draw` object. Widget authoring normally uses
`draw.widgets`, which binds the current `imgui` and root storage field scope for
the render call. Navigation helpers use `draw.nav`, which binds the current
`imgui` and session for the same draw call.

For storage schema, table handles, packed roots, and session/store rules, read [MANAGED_STATE.md](MANAGED_STATE.md).

## Widgets

Module draw code calls the bound widget surface at `draw.widgets`.

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
draw.widgets.dropdown("Mode", {
    label = "Mode",
    values = { "Vanilla", "Chaos" },
    controlWidth = 180,
})
```

Value-bound widgets return `true` when they changed staged `session` and
`false` otherwise. Button-style widgets return whether they were clicked or
confirmed. Display-only helpers such as `separator` and `text` draw and return
nothing.

## Common concepts

### Bound Widgets And Storage Fields

Most widgets target one storage field:
- `checkbox`
- `inputText`
- `dropdown`
- `mappedDropdown`
- `radio`
- `mappedRadio`
- `packedDropdown`
- `packedRadio`
- `packedCheckboxList`
- `stepper`

String targets are shorthand for root fields on `draw.session`:

```lua
draw.widgets.checkbox("Enabled", {
    label = "Enabled",
})
```

The explicit root-field form is available when a helper needs to pass a target
around:

```lua
local enabled = draw.field("Enabled")
draw.widgets.checkbox(enabled, {
    label = "Enabled",
})
```

Table rows produce `StorageField` targets through the table API:

```lua
local row = draw.session.table("Rows"):rowHandle(1)
draw.widgets.checkbox(row:field("Enabled"), {
    label = "Enabled",
})
```

Packed widgets resolve packed child metadata through the `StorageField` schema.

One binds to two targets:
- `steppedRange(minTarget, maxTarget, ...)`

Widgets do not traverse table storage. Table/path APIs should resolve to a
final `StorageField`, then widgets render that field.

```lua
local row = draw.session.table("Rows"):rowHandle(1)
draw.widgets.packedDropdown(row:field("PackedChoices"), opts)
```

Author draw code can read staged values through `draw.session.view.SomeAlias`
for readability. Widget internals use storage fields to read and write values.

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

### `draw.widgets.separator()`

Thin wrapper around `imgui.Separator()`.

Use when:
- you want a Lib-level helper for consistency

### `draw.widgets.text(text, opts?)`

Options:
- `color`
- `tooltip`
- `alignToFramePadding`

Use when:
- you want a text line with optional color or tooltip

Example:

```lua
draw.widgets.text("Underworld", {
    color = { 0.8, 0.7, 0.4, 1 },
    alignToFramePadding = true,
})
```

### `draw.widgets.button(label, opts?)`

Options:
- `id`
- `tooltip`
- `action`
- `value`
- `onClick(imgui)`

Notes:
- returns whether the button was clicked
- when `action` is a `draw.actions.get(...)` ref, stages `value` on that action
- legacy string action keys are still accepted during migration
- `onClick` is optional convenience only; you can ignore it and use the boolean return directly

### `draw.widgets.confirmButton(id, label, opts?)`

Renders a button that opens a confirmation popup.

Options:
- `tooltip`
- `confirmLabel`
- `cancelLabel`
- `action`
- `value`
- `onConfirm(imgui)`

Notes:
- returns `true` only when the confirm action is taken
- when `action` is a `draw.actions.get(...)` ref, stages `value` on that action
- legacy string action keys are still accepted during migration
- this is good for destructive or global reset actions

## Input widget

### `draw.widgets.inputText(target, opts?)`

Options:
- `id`
- `label`
- `tooltip`
- `maxLen`
- `labelWidth`
- `controlWidth`
- `controlGap`

Behavior:
- reads current text from the storage field
- writes the edited string back through the storage field

Use when:
- the bound target is a string field
- you need plain text entry or a simple filter box

## Choice widgets

### `draw.widgets.dropdown(target, opts?)`

Options:
- `id`
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
- binds one storage field to one value from `values`
- preview text comes from `displayValues[value]` when present, else `tostring(value)`
- if the staged value is invalid, it falls back to:
  - a valid `default`
  - else the first entry in `values`

Use when:
- the widget owns a fixed explicit choice list

### `draw.widgets.mappedDropdown(target, opts?)`

Options:
- `id`
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
- `onSelect(option, owner)`

Behavior:
- the option list is computed from live staged state
- `getPreview`, `getPreviewColor`, and `getOptions` receive the target owner's view
- if an option provides `onSelect`, that callback owns the write behavior
- otherwise the widget writes `option.value` to the storage field

Use when:
- the choice list is dynamic
- preview text depends on derived state
- selecting an option needs custom logic

Example:

```lua
draw.widgets.mappedDropdown("SelectedRoot", {
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

### `draw.widgets.packedDropdown(target, opts?)`

Single-choice dropdown over a packed root.

Options:
- `id`
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
- resolves packed children from the storage field schema
- classifies current packed state as:
  - none
  - single
  - multiple
- `id` overrides the ImGui control id when multiple widgets bind the same row-local alias

Use when:
- a packed root represents one selected child out of many
- or the inverse "single false / all others true" style via `singleDisabled`

Example:

```lua
draw.widgets.packedDropdown("PackedForcedBoon", {
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

### `draw.widgets.radio(target, opts?)`

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

### `draw.widgets.mappedRadio(target, opts?)`

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
- `onSelect(option, owner)`

Use when:
- the visible options are dynamic
- you need custom selection behavior

Note:
- `getOptions` receives the target owner's view

### `draw.widgets.packedRadio(target, opts?)`

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

### `draw.widgets.stepper(target, opts?)`

Stepper with `-` and `+` buttons around a rendered value.

Options:
- `id`
- `label`
- `default`
- `min`
- `max`
- `step`
- `displayValues`
- `valueWidth`
- `buttonSpacing`

Behavior:
- normalizes through integer storage rules
- clamps against `min` / `max`
- can show friendly names through `displayValues[number]`

Use when:
- the value is small and ordinal
- button stepping is more readable than typing

### `draw.widgets.steppedRange(minTarget, maxTarget, opts?)`

Two coupled steppers rendered as:
- min stepper
- `"to"`
- max stepper

Options:
- `label`
- `default`
- `defaultMax`
- `min`
- `max`
- `step`
- `valueWidth`
- `buttonSpacing`
- `rangeGap`

Behavior:
- min stepper is limited by current max
- max stepper is limited by current min

Use when:
- both ends of the range should stay visible together
- you want stepper interaction instead of two dropdowns

## Boolean widgets

### `draw.widgets.checkbox(target, opts?)`

Options:
- `label`
- `tooltip`
- `color`

Behavior:
- binds one boolean storage field

Use when:
- the field is a plain toggle

### `draw.widgets.packedCheckboxList(target, opts?)`

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
- resolves packed children from the storage field schema
- text filter is case-insensitive substring match on option labels
- items are laid out inline according to `optionsPerLine`
- rendering stops after `slotCount` matches

Use when:
- a packed root is really a bitmask of many independent bool choices
- boon-ban style lists

Example:

```lua
draw.widgets.packedCheckboxList("PackedBannedAphrodite", {
    filterText = draw.session.view.BanFilterText,
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

Navigation helpers live under the bound draw surface at `draw.nav`.

Surface:
- `draw.nav.verticalTabs(opts)`
- `draw.nav.isVisible(condition)`

`verticalTabs(...)` renders a simple immediate-mode vertical tab rail.

Example:

```lua
activeKey = draw.nav.verticalTabs({
    id = "ExampleTabs",
    navWidth = 220,
    activeKey = activeKey,
    tabs = {
        { key = "settings", label = "Settings" },
        { key = "advanced", label = "Advanced", color = { 1, 0.8, 0, 1 } },
    },
})
```

`isVisible(...)` evaluates a storage-backed visibility condition against the
draw session:

```lua
if draw.nav.isVisible({ alias = "ShowAdvanced", value = true }) then
    draw.widgets.checkbox("AdvancedFlag", {
        label = "Advanced Flag",
    })
end
```

## Scope

Widgets are direct immediate-mode helpers. Bound controls return a boolean
changed or clicked flag; display-only helpers such as `separator` and `text`
draw and return nothing. Composition is ordinary Lua control flow: authors call
the helpers they want, in the order they want, inside their own `drawTab(draw)`
function.
