# Storage and UI Registries

This document replaces the old field-centric model.

Lib now has three registries:
- `lib.StorageTypes`
- `lib.WidgetTypes`
- `lib.LayoutTypes`

Lib also reserves:
- `lib.WidgetHelpers`

These registries are separate on purpose.

## Why the Split Exists

The old field model mixed:
- persistence
- hashing
- staging
- widget rendering
- layout

The new model separates those concerns:
- storage owns persistence and hashing
- widgets own interaction
- layout owns presentation structure

## Storage Types

Storage types validate, normalize, and serialize persisted values.

Required methods:
- `validate(node, prefix)`
- `normalize(node, value)`
- `toHash(node, value)`
- `fromHash(node, str)`

Built-ins:
- `bool`
- `int`
- `string`
- `packedInt`

### Root storage nodes

Every root storage node must have:
- `type`
- either `configKey` or `lifetime = "transient"`

Persisted roots:
- declare `configKey`
- may omit `alias`, in which case it defaults to the stringified `configKey`

Transient roots:
- declare `lifetime = "transient"`
- must declare an explicit `alias`
- do not persist, hash, or flush directly

Example:

```lua
{ type = "bool", alias = "Enabled", configKey = "Enabled", default = false }
```

Transient example:

```lua
{ type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 }
```

### Packed storage nodes

`packedInt` is a root storage type whose children are alias-addressable packed partitions.

Use `packedInt` when you want to reduce Chalk config entries by co-locating related flags. For most modules, separate `bool` roots are the right choice.

Example:

```lua
{
    type = "packedInt",
    alias = "PackedAphrodite",
    configKey = "PackedAphrodite",
    bits = {
        { alias = "AttackBanned", offset = 0, width = 1, type = "bool", default = false },
        { alias = "RarityOverride", offset = 4, width = 2, type = "int", default = 0 },
    },
}
```

Rules:
- packed child aliases must be unique across the module
- packed bit ranges may not overlap
- packed child defaults are encoded into the root default when the root default is omitted
- only the root persists and hashes directly

By default each storage root hashes as its own key. Framework supports optional `hashGroups` for coordinators that want to compress multiple independent small roots into a single base62 token — see the coordinator guide. This is an optimization; modules do not need to declare `hashGroups` for hashing to work correctly.

`hashGroups` may include:
- root `bool`
- root `int`
- root `packedInt` with a derivable width

`hashGroups` may not include:
- packed child aliases from inside a `packedInt`
- transient root aliases

## Widget Types

Widget types own rendering and interaction only.

Required methods:
- `validate(node, prefix)`
- `draw(imgui, node, bound, width?, uiState?)`

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

Widgets bind by alias:

```lua
{ type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" }
```

Each declared bind becomes a bound entry passed into `draw(...)`:

- `bound.<name>.get()`
- `bound.<name>.set(value)`

For widgets bound to a packed root, Lib may also expose:

- `bound.<name>.children`

which is how `packedCheckboxList` receives packed child rows.

Some widgets also support a widget-local `geometry` bag for manual horizontal placement.

First-pass built-in support:
- `text`: `value`
- `button`: `control`
- `confirmButton`: `control`
- `checkbox`: `control`
- `inputText`: `label`, `control`
- `dropdown`: `label`, `control`
- `mappedDropdown`: `label`, `control`
- `mappedRadio`: `label`
- `radio`: `label`, dynamic `option:N`
- `stepper`: `label`, `decrement`, `value`, `increment`, optional `fastDecrement`, `fastIncrement`
- `steppedRange`: `label`, `min.*`, `separator`, `max.*`
- `packedCheckboxList`: dynamic `item:N`; `slotCount` defaults to `32` when omitted

Geometry is expressed through `geometry.slots`, a list of slot descriptors.
Each slot descriptor may declare:
- `name`
- `line`
- `start`
- `width`
- `align`

`line` defaults to `1` and must be a positive integer when present.
`line` is the public vertical placement surface. Lib resolves row `y` internally; raw `y` is not part of the geometry contract.
`start` is relative to the current row origin after any `indent`.
`width` must be positive when present.
`align` may be `center` or `right` and requires an explicit `width`.
Slots are rendered in ascending `line`.
Within the same line, slots with explicit `start` values are ordered by `start`.
Otherwise declaration order breaks ties and preserves slots without explicit `start`.
`radio` supports `option:N` slot names for each entry in `node.values`.
`packedCheckboxList` supports `item:N` slot names. If `slotCount` is omitted, Lib defaults it to `32`.

`slotCount` is the declaration-time slot capacity for `packedCheckboxList`. Packed children may be omitted at runtime, but the widget does not invent new slots beyond the declared count.

`radio` option slots and packed list `item:N` slots currently use `line` and
`start` meaningfully. `width` and `align` are accepted by the generic geometry
parser but warn because those widgets do not consume them.

### Slot intent by built-in widget

The generic parser accepts `line`, `start`, `width`, and `align`, but built-in
widgets do not all consume every key the same way. Authors should treat the
following as the meaningful geometry surface:

- `text.value`
  - use `line` / `start` to place the text block
  - `width` + `align` are meaningful when you want centered/right-aligned text inside a fixed slot
- `button.control`
  - use `line` / `start` to place the button
  - `width` + `align` are meaningful when you want the button aligned inside a fixed slot
- `confirmButton.control`
  - use `line` / `start` to place the button
  - `width` + `align` are most meaningful for the idle button placement; the armed confirm row expands inline
- `checkbox.control`
  - use `line` / `start` to place the whole checkbox row
  - `width` / `align` are not meaningful for the built-in checkbox draw path
- `inputText.label`
  - use `line` / `start` to place the label text
  - `width` / `align` are not meaningful
- `inputText.control`
  - use `line` / `start` to place the input field
  - `width` is meaningful and sets the input width
  - `align` is not meaningful and currently warn
- `dropdown.label`
  - use `line` / `start` to place the label text
  - `width` / `align` are not meaningful
- `dropdown.control`
  - use `line` / `start` to place the combo box
  - `width` is meaningful and sets the combo width
  - `align` is not meaningful
- `mappedDropdown.label`
  - use `line` / `start` to place the label text
  - `width` / `align` are not meaningful
- `mappedDropdown.control`
  - use `line` / `start` to place the combo box
  - `width` is meaningful and sets the combo width
  - `align` is not meaningful
- `mappedRadio.label`
  - use `line` / `start` to place the label text
  - `width` / `align` are not meaningful
- `radio.label`
  - use `line` / `start` to place the label text
  - `width` / `align` are not meaningful
- `radio.option:N`
  - use `line` / `start` to place each option explicitly
  - `width` / `align` are not meaningful and currently warn
- `stepper.label`
  - use `line` / `start` to place the label text
  - `width` / `align` are not meaningful
- `stepper.decrement`, `stepper.increment`, `stepper.fastDecrement`, `stepper.fastIncrement`
  - use `line` / `start` to place the buttons
  - `width` / `align` are not meaningful
- `stepper.value`
  - use `line` / `start` to place the numeric value slot
  - `width` + `align` are meaningful and control value-slot alignment
- `steppedRange.label`
  - use `line` / `start` to place the shared label text
  - `width` / `align` are not meaningful
- `steppedRange.min.value`, `steppedRange.max.value`
  - use `line` / `start` to place the value slots
  - `width` + `align` are meaningful and control value-slot alignment
- `steppedRange.min.decrement`, `steppedRange.min.increment`, `steppedRange.min.fastDecrement`, `steppedRange.min.fastIncrement`
  - use `line` / `start` to place the left-side buttons
  - `width` / `align` are not meaningful
- `steppedRange.max.decrement`, `steppedRange.max.increment`, `steppedRange.max.fastDecrement`, `steppedRange.max.fastIncrement`
  - use `line` / `start` to place the right-side buttons
  - `width` / `align` are not meaningful
- `steppedRange.separator`
  - use `line` / `start` to place the separator text
  - `width` + `align` are meaningful when you want the separator aligned inside a fixed slot
- `packedCheckboxList.item:N`
  - use `line` / `start` to place each packed child row
  - when `binds.filterText` is provided, item slots target the visible filtered rows after compaction
  - `width` / `align` are not meaningful and currently warn

### `steppedRange`

`steppedRange` is a widget, not storage.

It binds to two existing aliases:
- `binds.min`
- `binds.max`

Example:

```lua
{ type = "steppedRange",
  label = "Depth",
  binds = { min = "DepthMin", max = "DepthMax" },
  geometry = {
    slots = {
      { name = "min.decrement", start = 0 },
      { name = "min.value", start = 24, width = 14, align = "center" },
      { name = "min.increment", start = 42 },
      { name = "separator", start = 260 },
      { name = "max.decrement", start = 300 },
      { name = "max.value", start = 324, width = 14, align = "center" },
      { name = "max.increment", start = 342 },
    },
  },
  min = 1,
  max = 10,
  step = 1 }
```

## Layout Types

Layout types never store data.

Required methods:
- `validate(node, prefix)`
- `render(imgui, node, drawChild)`

Built-ins:
- `separator`
- `group`
- `horizontalTabs`
- `verticalTabs`
- `panel`

Layout nodes may carry `children`.

Example:

```lua
{
    type = "group",
    label = "Options",
    children = {
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled" },
    },
}
```

`panel` is a first-pass child-placement layout:

```lua
{
    type = "panel",
    columns = {
        { name = "label", start = 0, width = 220 },
        { name = "control", start = 240, width = 180 },
    },
    children = {
        {
            type = "dropdown",
            binds = { value = "Mode" },
            values = { "A", "B" },
            panel = { column = "control", line = 1 },
        },
    },
}
```

Rules:
- `columns` is a non-empty list
- each column may declare `name`, `start`, `width`, and `align`
- child `panel.column` may be a column name or 1-based index
- child `panel.line` defaults to `1`
- child `panel.key` provides a stable identity for the child within the panel

`panel` positions children row-by-row.
`panel.line` remains the public vertical descriptor. Lib resolves explicit internal row `y` values and settles row advancement after each rendered child group.

`horizontalTabs` is a thin layout wrapper over ImGui tab bars:

```lua
{
    type = "horizontalTabs",
    id = "RootViews##Apollo",
    children = {
        {
            type = "panel",
            tabLabel = "Force",
            children = { ... },
        },
        {
            type = "panel",
            tabLabel = "Rarity",
            tabId = "rarity",
            children = { ... },
        },
    },
}
```

Rules:
- `id` is required and must be a non-empty string
- each child must declare `tabLabel`
- child `tabLabelColor = { r, g, b }` or `{ r, g, b, a }` is optional and colors that tab label only
- child `tabId` is optional and, when present, is appended as `##<tabId>` to the rendered tab item label
- `horizontalTabs` owns child rendering and only draws the child for the currently open tab item
- v1 intentionally mirrors ImGui tab-bar behavior and does not introduce separate alias-backed selection state

`verticalTabs` is a split layout with a left selectable tab list and a right active-detail pane:

```lua
{
    type = "verticalTabs",
    id = "BoonDomains",
    sidebarWidth = 220,
    children = {
        {
            type = "group",
            tabLabel = "Olympians",
            children = { ... },
        },
        {
            type = "group",
            tabLabel = "NPCs",
            tabId = "npcs",
            children = { ... },
        },
    },
}
```

Rules:
- `id` is required and must be a non-empty string
- `sidebarWidth` is optional and defaults to `180`
- each child must declare `tabLabel`
- child `tabLabelColor = { r, g, b }` or `{ r, g, b, a }` is optional and colors that tab label only
- child `tabId` is optional and, when present, is used as the stable internal active-tab key
- `verticalTabs` keeps its current active child on the prepared node and defaults to the first child when no active tab has been chosen yet
- `verticalTabs` owns child rendering and only draws the active child in the detail pane
- `verticalTabs` uses explicit internal pane positioning; callers still describe structure declaratively rather than supplying raw `y`

## Binding Rules

### Aliases

All storage access inside Lib-managed UI is alias-based.

That means:
- widgets bind by alias
- `visibleIf` can use:
  - a bool alias string
  - `{ alias = "...", value = ... }`
  - `{ alias = "...", anyOf = { ... } }`
- `uiState` stages by alias

### Raw keys

Raw `configKey` access still exists through:
- `store.read(keyOrAlias)`
- `store.write(keyOrAlias, value)`

But UI declarations should not bind to raw keys.

## Validation Rules

Lib validates:
- alias uniqueness
- root `configKey` uniqueness
- packed overlap
- widget/storage type compatibility
- `visibleIf` alias validity

Lib hard-validates registry contracts through:
- `lib.validateRegistries()`

## Built-In Behavior Notes

### `bool`
- normalizes to `true` or `false`
- hashes as `"1"` or `"0"`

### `int`
- clamps to declared `min` and `max` when present
- hashes as canonical decimal string

### `string`
- normalizes to string
- supports optional `maxLen` validation

### `text`
- presentational widget with no binds
- renders `node.text` or `node.label`
- supports optional `color = { r, g, b }` or `{ r, g, b, a }`

### `button`
- presentational action widget with no binds
- renders `node.label` as a push button
- optional `onClick(uiState, node, imgui)` runs when the button is pressed

### `confirmButton`
- presentational action widget with no binds
- renders `node.label` as an idle button
- first click arms a confirmation row for `timeoutSeconds` seconds
- armed state is node-local and does not require transient storage
- optional `confirmLabel` and `cancelLabel` customize the armed buttons
- optional `onConfirm(uiState, node, imgui)` runs only when the confirm button is pressed

### `checkbox`
- expects bool storage

### `inputText`, `dropdown`, `mappedDropdown`, `mappedRadio`, and `radio`
- `inputText` expects string storage
- `inputText` supports optional `geometry`
- `inputText.control` is the meaningful width-bearing slot
- `inputText.control` does not consume `align`
- `dropdown` and `radio` expect direct choice storage backed by either `string` or `int`
- `dropdown` and `radio` support optional `displayValues[value]` and `valueColors[value]` keyed by the declared choice values
- `mappedDropdown` accepts any bound storage type and delegates preview/option semantics to callbacks
- `mappedRadio` accepts any bound storage type and delegates option semantics to callbacks
- `dropdown` and `radio` validate value lists and expect `node.values` entries to be strings or integers
- `dropdown` supports optional `geometry`
- `dropdown.control` is the meaningful width-bearing slot
- `mappedDropdown` supports optional `geometry`
- `mappedDropdown.control` is the meaningful width-bearing slot
- `mappedDropdown.label` does not consume `width` / `align`
- `mappedDropdown.control` does not consume `align`
- `mappedRadio` supports optional label placement only; option layout is internal
- `radio` is mainly a `line` / `start` placement widget; option slots do not consume `width` / `align`

### `stepper`
- expects int storage
- supports `step`, `fastStep`, and optional `geometry`
- optional `displayValues[value]` overrides the rendered value label without changing storage
- optional `valueColors[value]` colors the rendered value label
- `value` is the meaningful aligned slot
- button slots are best treated as explicit `line` / `start` positions

### `packedCheckboxList`
- expects `binds.value` to be an `int`-kind alias whose root type is explicitly `packedInt`
- renders checkbox rows for the packed child aliases under that root
- optionally accepts a string bind at `binds.filterText`; when present, only matching child labels are rendered
- optionally accepts a string bind at `binds.filterMode`; supported values are `all`, `checked`, and `unchecked`
- optional `valueColors[childAlias]` colors the rendered checkbox label for that packed child row
- useful when a module wants a generic packed-flag checklist without hand-writing the child loop
- visible children are those whose `label` contains the current filter text (case-insensitive substring match) and whose checked state matches the current filter mode
- `item:N` geometry targets the visible rows after compaction when filtering is active

### `separator`
- layout only
- no binding

### `group`
- layout only
- optional `children`
- optional `collapsible`

## Authoring Guidance

Prefer:
- storage nodes for persistence
- widget nodes for reusable UI
- layout nodes for structure

Do not:
- put persistence rules in widgets
- put widget bindings in storage
- use old field helpers or old schema contracts

## Module-Local Extensions

Modules may extend the built-in registries with:

- `definition.customTypes.widgets`
- `definition.customTypes.layouts`
- custom widgets must declare `binds`
- custom widgets must declare `draw(...)`

`lib.WidgetHelpers` is currently reserved and intentionally empty.
It exists as the future home for widget-specific authoring/tooling helpers without mixing those helpers into the runtime `WidgetTypes` contract table.

Rules:
- custom widget names may not collide with built-in widget or layout names
- custom layout names may not collide with built-in widget or layout names
- custom widgets must declare `binds`
- custom widgets must implement `validate(...)` and `draw(...)`
- widget bind specs may declare `storageType` for value-kind matching, optional `rootType` for exact storage node matching, and optional `optional = true` for non-required binds
- custom widgets may optionally declare `slots = { ... }` to whitelist supported `node.geometry.slots[*].name` values
- custom widgets may optionally declare `defaultGeometry = { slots = { ... } }` as their baseline slot layout
- custom widgets may optionally declare `dynamicSlots(node, slotName) -> ok, err` for declaration-time-dependent slot names
- custom layouts must implement `validate(...)` and `render(...)`
- custom layouts may declare `handlesChildren = true` when they own child placement
- custom layout `render(...)` receives `(imgui, node, drawChild)`
- simple layouts may ignore `drawChild` and return just `open`
- layouts with `handlesChildren = true` should return `open, changed`
- layouts with `handlesChildren = true` should call `drawChild(child)` themselves and report child changes through `changed`

Structured rendering contract:
- parents/layouts assign child start positions
- structured children should begin rendering from that assigned start
- structured children should leave the cursor settled at the bottom of the space they consumed before returning
- Lib uses that settled end position as the parent footprint signal
- this contract applies to Lib-managed slot rendering, `panel`, `verticalTabs`, and custom layouts that own child placement

Leaf-widget rule:
- widgets should be treated as leaf renderers by default
- widget-local immediate-mode composition is fine when it stays self-contained inside the widget
- recursively drawing another full structured widget/layout from inside a widget should be treated as an exception, not the default authoring model

Custom widgets may stay fully imperative, but widgets that declare `slots` and `defaultGeometry` can call `lib.drawWidgetSlots(...)` from inside `draw(...)` to reuse Lib-managed slot ordering and geometry merging.

Custom types are merged into the registry surface for:
- `lib.validateUi(...)`
- `lib.prepareUiNode(...)`
- `lib.prepareUiNodes(...)`
- `lib.drawUiNode(...)`
- `lib.drawUiTree(...)`
- `lib.collectQuickUiNodes(...)`

## Minimal Example

```lua
public.definition = {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    storage = {
        { type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false },
        { type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 },
    },
    ui = {
        { type = "checkbox", binds = { value = "EnabledFlag" }, label = "Enabled" },
        { type = "stepper", binds = { value = "Count" }, label = "Count", min = 1, max = 9, step = 1 },
    },
}
```
