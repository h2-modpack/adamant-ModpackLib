# Widgets and Navigation

This document covers `draw.widgets.*` and `draw.nav.*` from a module draw-code point of view.

Draw callbacks receive `host, ui`. Widget authoring normally uses
`ui.draw.widgets`, which calls the current draw pass `imgui` backend without
making modules thread `imgui` through widget calls. Navigation helpers use
`ui.draw.nav` the same way.

`ui.draw`, `ui.data`, `ui.actions`, and `ui.controls` are draw-callback objects.
Use them from the draw callback that receives them. Do not cache draw objects
for runtime use.

Use [../DRAW_LIFECYCLE.md](../DRAW_LIFECYCLE.md) for the full draw/commit
order.

For storage schema, table handles, packed roots, and runtime/UI data rules, read [MANAGED_STATE.md](MANAGED_STATE.md).

## Widgets

Module draw code calls the draw widget surface at `draw.widgets`.

Built-ins:
- `separator`
- `text`
- `button`
- `confirmButton`
- `inputText`
- `dropdown`
- `packedDropdown`
- `radio`
- `packedRadio`
- `stepper`
- `steppedRange`
- `checkbox`
- `packedCheckboxList`

These are direct immediate-mode helpers. Call them inside module draw functions to render one control at a time.

Typical call shape:

```lua
local draw = ui.draw
local state = ui.data

draw.widgets.dropdown(state.get("Mode"), {
    label = "Mode",
    values = { "Vanilla", "Chaos" },
    controlWidth = 180,
})
```

Value-bound widgets return `true` when they changed staged `state` and
`false` otherwise. Button-style widgets return whether they were clicked or
confirmed. Display-only helpers such as `separator` and `text` draw and return
nothing.

## Common concepts

### Bound Widgets And Storage Fields

Most widgets target one storage field:
- `checkbox`
- `inputText`
- `dropdown`
- `radio`
- `packedDropdown`
- `packedRadio`
- `packedCheckboxList`
- `stepper`

Use `state.get(alias)` to pass root storage fields to widgets:

```lua
draw.widgets.checkbox(state.get("Enabled"), {
    label = "Enabled",
})
```

Table rows produce `StorageField` targets through the table API:

```lua
local rows = state.get("Rows")
draw.widgets.checkbox(rows:get(1, "Enabled"), {
    label = "Enabled",
})
```

Widgets use `field:controlId()` for default ImGui control identity. Root fields
use their alias as the control id; table cells include table alias, row index,
and cell alias, so row-local widgets are unique without manual `id` options.

Packed widgets resolve packed child metadata through the `StorageField` schema.

One binds to two targets:
- `steppedRange(minTarget, maxTarget, ...)`

Widgets do not traverse table storage. Table/path APIs should resolve to a
final `StorageField`, then widgets render that field.

```lua
local rows = state.get("Rows")
draw.widgets.packedDropdown(rows:get(1, "PackedChoices"), opts)
```

Author draw code can read staged values through `state.get(alias):read()`.
Widget internals use storage fields to read and write values.

### Optional widget actions

Interactive widgets may also stage one draw action by passing:
- `action = actions.get("ActionName")`
- `value = payload`

The widget still performs its normal data edit. The optional action is for
side effects or commit observers that need to know an interaction happened.
When `value` is omitted, value widgets stage their edited value by default:
- text, dropdown, radio, checkbox, and stepper widgets stage the new field value
- packed single-choice widgets stage the selected child alias, or `false` for none
- `packedCheckboxList` stages `{ alias = childAlias, value = editedBoolean }`
- buttons stage `true`

Use explicit `value` when the commit observer needs a stable command payload
instead of the edited value.

Do not use actions for normal field edits. The widget's default data edit
should remain the source of truth; actions are extra draw intent for commit-time
logic.

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
- `radio.valueColors`
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

Notes:
- returns whether the button was clicked
- when `action` is a `ui.actions.get(...)` ref, stages `value` on that action, or `true` when `value` is omitted
- command side effects should be declared in `createModule({ actions = ... })` and staged through `action`
- for fully custom imperative behavior, use raw `draw.imgui.Button(...)` and own the side effect at the call site

### `draw.widgets.confirmButton(id, label, opts?)`

Renders a button that opens a confirmation popup.

Options:
- `tooltip`
- `confirmLabel`
- `cancelLabel`
- `action`
- `value`

Notes:
- returns `true` only when the confirm action is taken
- when `action` is a `ui.actions.get(...)` ref, stages `value` on that action, or `true` when `value` is omitted
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
- `action`
- `value`

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
- `visibleValues`
- `labelWidth`
- `controlWidth`
- `controlGap`
- `action`
- `value`

Behavior:
- binds one storage field to one value from `values`
- preview text comes from `displayValues[value]` when present, else `tostring(value)`
- entries with `visibleValues[value] == false` are hidden; omitted values remain visible
- if the staged value is invalid, it falls back to:
  - a valid `default`
  - else the first visible entry in `values`

Use when:
- the widget owns a fixed explicit choice list
- the full value domain is stable, but current availability changes through a reused visibility map

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
- `action`
- `value`

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
draw.widgets.packedDropdown(state.get("PackedForcedBoon"), {
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
- `visibleValues`
- `optionsPerLine`
- `optionGap`
- `action`
- `value`

Use when:
- the choice list is small and visible all at once is better than a combo
- the full value domain is stable, but current availability changes through a reused visibility map

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
- `action`
- `value`

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
- `action`
- `value`

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
- `action`
- `value`

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
- `action`
- `value`

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
- `action`
- `value`

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
draw.widgets.packedCheckboxList(state.get("PackedBannedAphrodite"), {
    filterText = state.get("BanFilterText"):read(),
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
- `packedDropdown` when one packed child is effectively selected
- `radio` when the static choices should stay visible
- `packedRadio` when packed single-choice state should stay visible
- `checkbox` for one bool
- `packedCheckboxList` for many packed bool flags
- `stepper` for one bounded int
- `steppedRange` for two coupled ints

## Nav

Navigation helpers live under the draw surface at `draw.nav`.

Surface:
- `draw.nav.verticalTabs(opts)`

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

## Scope

Widgets are direct immediate-mode helpers. Bound controls return a boolean
changed or clicked flag; display-only helpers such as `separator` and `text`
draw and return nothing. Composition is ordinary Lua control flow: authors call
the helpers they want, in the order they want, inside their own draw callback
function.
