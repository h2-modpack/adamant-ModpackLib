# Module Authoring

This guide covers the supported module contract after the storage/UI redesign.

## Shared Rules

Every module exposes:

```lua
local dataDefaults = import("config.lua")

public.definition = {
    modpack = PACK_ID,
}

public.store = lib.createStore(config, public.definition, dataDefaults)
store = public.store
```

Every module now declares:
- `definition.storage`
- `definition.ui` when it wants Lib-managed rendering
- optional `definition.customTypes` for module-local reusable widgets/layouts

There is no supported use of:
- `definition.options`
- `definition.stateSchema`

`lib.createStore(...)` now runs an early definition warning pass before storage/UI
validation. It warns on:
- unknown top-level definition keys
- fields that exist but are ignored by the current module kind
- incomplete lifecycle declarations like `apply` without `revert`

That warning pass keeps the flat `definition` shape, but makes authoring mistakes
visible much earlier.

## Definition By Consumer

The runtime shape stays flat, but authors should think about `definition` in
consumer groups.

Framework discovery and routing reads:
- `modpack`
- `special`
- `id`
- `name`
- `shortName`
- `category`
- `subgroup`
- `tooltip`
- `default`

Lib store and hosted UI reads:
- `storage`
- `ui`
- `customTypes`

Framework hosted Quick Setup reads:
- `selectQuickUi`

Lifecycle and run-data behavior reads:
- `affectsRunData`
- `patchPlan`
- `apply`
- `revert`

Framework hash/profile encoding may also read:
- `hashGroups`

Authoring rule:
- keep the table flat
- but place fields mentally by consumer so you know why each field exists

## Special vs Regular Decision Guide

Use a regular module when:
- the module belongs under a category/subgroup in the main Framework UI
- the module can be described through `definition.ui`
- Quick Setup should come from `quick = true` widget nodes
- the stable hash namespace should be `definition.id`

Use a special module when:
- the module owns its own dedicated sidebar tab
- the module needs custom `DrawTab` and/or `DrawQuickContent`
- the module wants the special-module hash namespace based on `modName`
- category/subgroup routing does not make sense

Framework-visible differences:
- regular modules are routed by `definition.category` / `definition.subgroup`
- special modules ignore `definition.category` / `definition.subgroup`
- regular modules use `definition.id` as their hash namespace
- special modules use `modName` as their hash namespace
- regular modules can filter hosted quick nodes through `definition.selectQuickUi`
- special modules ignore `definition.selectQuickUi`; Quick Setup uses `DrawQuickContent`
- regular modules ignore `shortName`
- special modules may use `shortName` for compact sidebar labels

Validation and warning rule:
- if you put a special-only field on a regular module, or a regular-only field on a special module, Lib/Framework now warn instead of silently leaving the mismatch implicit

## State Access Rules

These are contract rules:
- keep raw Chalk config local to `main.lua`
- after `public.store = lib.createStore(config, public.definition, dataDefaults)`, other module files should use `store.read(...)` and `store.write(...)`
- special UI should use `store.uiState`

Avoid:

```lua
if config.Strict then
    -- ...
end
```

Use:

```lua
if store.read("Strict") then
    -- ...
end
```

## Regular Modules

Regular modules participate in category/subgroup rendering and may expose hosted declarative UI.

Example:

```lua
public.definition = {
    modpack = PACK_ID,
    id = "ExampleModule",
    name = "Example Module",
    category = "Run Mods",
    subgroup = "General",
    tooltip = "What this module does.",
    default = false,
    affectsRunData = false,
    storage = {
        { type = "bool", alias = "Strict", configKey = "Strict", default = false },
        { type = "string", alias = "Label", configKey = "Label", default = "", maxLen = 64 },
    },
    ui = {
        { type = "checkbox", binds = { value = "Strict" }, label = "Strict Mode", quick = true },
        { type = "separator", label = "Naming" },
        { type = "dropdown", binds = { value = "Label" }, label = "Label", values = { "", "A", "B" } },
    },
    selectQuickUi = function(store, uiState, quickNodes)
        return nil
    end,
}
```

Rules:
- `definition.id` is the regular-module hash namespace
- coordinated regular modules should declare `definition.id`
- storage aliases should be stable after release
- root aliases default to `configKey` when omitted
- widgets bind by alias
- `quick = true` marks quick candidates
- `quickId` is optional but recommended when runtime quick filtering is used
- `selectQuickUi(...)` runs at Quick Setup render time and may filter which quick candidates are shown

Standalone helper:

```lua
rom.gui.add_to_menu_bar(lib.standaloneUI(public.definition, public.store))
```

## Special Modules

Special modules get their own framework tab and usually own more of their layout.

Example:

```lua
public.definition = {
    modpack = PACK_ID,
    id = "ExampleSpecial",
    name = "Example Special",
    shortName = "Example",
    special = true,
    default = false,
    affectsRunData = true,
    storage = {
        { type = "string", alias = "Mode", configKey = "Mode", default = "A" },
        { type = "string", alias = "TargetKey", configKey = "TargetKey", default = "", maxLen = 128 },
        { type = "bool", alias = "NestedFlag", configKey = { "Nested", "Flag" }, default = false },
    },
    ui = {},
}
```

Rules:
- special-module hash namespace is the module `modName`
- coordinated special modules should declare `definition.name`
- `shortName` is optional and only needed when a compact UI surface should use a shorter label than `name`
- storage may still use nested raw config paths
- alias names are the UI and `uiState` access surface
- `category`, `subgroup`, and `selectQuickUi` are ignored on special modules

Supported public UI entrypoints:
- `public.DrawQuickContent(ui, uiState, theme)`
- `public.DrawTab(ui, uiState, theme)`

If `public.DrawTab` is absent and `definition.ui` exists, Lib can render `definition.ui` automatically.

Standalone helper:

```lua
local specialUi = lib.standaloneSpecialUI(
    public.definition,
    public.store,
    public.store.uiState,
    {
        getDrawQuickContent = function() return public.DrawQuickContent end,
        getDrawTab = function() return public.DrawTab end,
    }
)

rom.gui.add_imgui(specialUi.renderWindow)
rom.gui.add_to_menu_bar(specialUi.addMenuBar)
```

## Storage Authoring

### Scalar storage

```lua
{ type = "bool", alias = "EnabledFlag", configKey = "EnabledFlag", default = false }
{ type = "int", alias = "Count", configKey = "Count", default = 3, min = 1, max = 9 }
{ type = "string", alias = "Mode", configKey = "Mode", default = "Vanilla", maxLen = 64 }
```

### Transient UI storage

Use `lifetime = "transient"` for alias-backed UI state that should not persist to Chalk, hashes, or profiles:

```lua
{ type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 }
{ type = "string", alias = "FilterMode", lifetime = "transient", default = "all", maxLen = 16 }
```

Rules:
- persisted roots use `configKey`
- transient roots use `lifetime = "transient"`
- `configKey` and `lifetime` are mutually exclusive
- transient roots must declare an explicit `alias`
- transient roots are UI-only and must be accessed through `store.uiState`
- transient `packedInt` roots are not supported in v1

When to use transient aliases:
- use transient aliases when multiple UI elements need to coordinate through the same state
- use transient aliases when declarative UI conditions like `visibleIf` or multiple widgets need to read the same UI state generically
- keep state module-local when it is only internal navigation or scratch for one contained widget/view
- do not promote purely local widget navigation into transient storage unless another UI surface actually needs to read it

Derived display text:
- use transient string aliases plus `lib.runDerivedText(...)` when a plain `text` widget should display computed summaries, empty-state messages, or status lines
- keep the compute logic module-side; Lib only provides the lightweight refresh helper
- this helper is intentionally string-only and should not be used to drive dynamic widget or layout structure

### Packed storage

Use `packedInt` when you want alias-addressable packed children:

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

If a module only treats a packed value as a raw mask, it can remain a plain root `int`.

## UI Authoring

### Widget nodes

Examples:

```lua
{ type = "text", text = "Section Title" }
{ type = "text", text = "Warning", color = { 1, 0.5, 0.2, 1 } }
{ type = "button", label = "Reset Filter", onClick = function(uiState) uiState.reset("FilterText") end }
{ type = "checkbox", binds = { value = "EnabledFlag" }, label = "Enabled" }
{ type = "inputText", binds = { value = "FilterText" }, label = "Filter" }
{ type = "stepper", binds = { value = "Count" }, label = "Count", min = 1, max = 9, step = 1 }
{ type = "dropdown", binds = { value = "Mode" }, label = "Mode", values = { "Vanilla", "Chaos" } }
{ type = "packedCheckboxList", binds = { value = "PackedFlags" } } -- defaults to slotCount = 32
{ type = "packedCheckboxList", binds = { value = "PackedFlags" }, slotCount = 8 }
```

### Layout nodes

Examples:

```lua
{ type = "separator", label = "Options" }

{
    type = "group",
    label = "Advanced",
    children = {
        { type = "checkbox", binds = { value = "EnabledFlag" }, label = "Enabled" },
    },
}

{
    type = "panel",
    columns = {
        { name = "label", start = 0, width = 220 },
        { name = "control", start = 240, width = 180 },
    },
    children = {
        { type = "text", text = "Mode" },
        {
            type = "dropdown",
            binds = { value = "Mode" },
            values = { "Vanilla", "Chaos" },
            panel = { column = "control", line = 1 },
        },
    },
}
```

### Module-local custom widgets and layouts

Modules may declare `definition.customTypes` when they want reusable UI pieces that should not be promoted into Lib:

```lua
public.definition.customTypes = {
    widgets = {
        myWidget = {
            binds = { value = { storageType = "int" } },
            slots = { "label", "control" }, -- optional supported geometry slot names
            dynamicSlots = function(node, slotName) end, -- optional declaration-time slot validator
            validate = function(node, prefix) end,
            draw = function(imgui, node, bound, width, uiState) end,
        },
    },
    layouts = {
        myLayout = {
            handlesChildren = true, -- optional: layout owns child drawing
            validate = function(node, prefix) end,
            render = function(imgui, node, drawChild) return true end,
        },
    },
}
```

Widget bind specs may declare:
- `storageType` for value-kind matching such as `bool`, `int`, or `string`
- optional `rootType` for exact storage node matching such as `packedInt`
- optional `optional = true` when the widget can operate without that bind being declared

These custom types can be used by:
- hosted regular-module UI
- standalone Lib helpers
- Framework rendering
- special-module calls to `lib.drawUiNode(...)` / `lib.drawUiTree(...)`

Custom widget `draw(...)` may stay fully imperative, or it may call `lib.drawWidgetSlots(...)` to let Lib manage slot ordering and geometry merging.
`dynamicSlots(...)` is the optional escape hatch for declaration-time-dependent slot names like `option:N`.
Custom layout `render(...)` always receives `drawChild`.
Simple layouts can ignore it and return just `open`.
Layouts that want to own child placement should declare `handlesChildren = true`, return `open, changed`, and call `drawChild(child)` themselves.

Built-in widgets may also accept a widget-local `geometry` bag for manual horizontal placement.
Geometry is now expressed through `geometry.slots`, where each slot descriptor may declare:
- `name`
- `line`
- `start`
- `width`
- `align`

`line` defaults to `1` and must be a positive integer when present.
`start` is relative to the current row origin after any `indent`.
`width` must be positive when present.
`align` may be `center` or `right` and requires an explicit `width`.
Slots are rendered in ascending `line`.
Within the same line, slots with explicit `start` values are ordered by `start`.
Otherwise declaration order breaks ties and preserves slots without explicit `start`.
`text` supports a single `value` slot.
`text.color` may be used to color a single text node.
`button` supports a single `control` slot.
`checkbox` supports a single `control` slot.
`inputText` supports `label` and `control`.
`radio` supports `option:N` slot names for each entry in `node.values`.
`packedCheckboxList` supports `item:N` slot names. If `slotCount` is omitted, Lib defaults it to `32`.

`slotCount` is the declaration-time slot capacity for `packedCheckboxList`. Packed children may be omitted at runtime, but the widget does not create new slots beyond the declared capacity.

Meaningful built-in slot intent:
- `text.value`: use `start`, and optional `width` + `align` when you want text aligned inside a slot
- `button.control`: use `line` / `start`; optional `width` + `align` can be used to place the button inside a fixed slot
- `checkbox.control`: use `start` to move the whole checkbox row
- `inputText.control`: use `start` and `width`; `label` is mainly a text-position slot
- `dropdown.control`: use `start` and `width`; `label` is mainly a text-position slot
- `radio.option:N`: use `line` / `start` to place each option; do not expect `width` / `align` to do anything useful
- `stepper.value`: this is the slot where `width` + `align` matter
- `stepper` button slots are mainly explicit `line` / `start` anchors
- `steppedRange.min.value` / `max.value`: these are the meaningful aligned value slots
- `steppedRange.separator`: may also use `width` + `align` if you want the separator text in a fixed slot
- `packedCheckboxList.item:N`: use `line` / `start` to place rows; do not expect `width` / `align` to do anything useful

Tabbed layout presentation:
- `horizontalTabs` / `verticalTabs` children may declare `tabLabelColor = { r, g, b }` or `{ r, g, b, a }` to color the child tab label

### `steppedRange`

This is now a pure widget bound to two aliases:

```lua
storage = {
    { type = "int", alias = "DepthMin", configKey = "DepthMin", default = 1, min = 1, max = 10 },
    { type = "int", alias = "DepthMax", configKey = "DepthMax", default = 10, min = 1, max = 10 },
}

ui = {
    {
        type = "steppedRange",
        binds = { min = "DepthMin", max = "DepthMax" },
        label = "Depth",
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
        step = 1,
    },
}
```

### `visibleIf`

`visibleIf` is part of the static contract. Lib evaluates the condition from managed alias
state before widget/layout dispatch. It is conditional visibility, not planner-style runtime
tree mutation.

`visibleIf` works on both widgets and layouts such as `group` and `panel`.

Simple bool gate:

```lua
{ type = "checkbox", binds = { value = "EnabledFlag" }, label = "Enabled", visibleIf = "GateEnabled" }
```

Equality gate:

```lua
{ type = "stepper", binds = { value = "Count" }, label = "Count", visibleIf = { alias = "Mode", value = "Forced" } }
```

Multiple allowed values:

```lua
{ type = "stepper", binds = { value = "Count" }, label = "Count", visibleIf = { alias = "Mode", anyOf = { "Forced", "Chaos" } } }
```

Layout gate:

```lua
{
    type = "panel",
    visibleIf = "ShowAdvanced",
    columns = {
        { name = "content", start = 0, width = 180 },
    },
    children = {
        { type = "checkbox", binds = { value = "Enabled" }, label = "Enabled", panel = { column = "content", line = 1 } },
    },
}
```

### Quick UI filtering

Any widget node may opt into Quick Setup by setting:

```lua
quick = true
```

Quick candidate ids are:
- `node.quickId` when explicitly provided
- otherwise derived from `node.binds`

Modules may optionally filter which quick nodes are shown at runtime:

```lua
public.definition.selectQuickUi = function(store, uiState, quickNodes)
    return { "value=Strict" }
end
```

Return:
- `nil` to show all quick candidates
- one quick id string
- an array of quick id strings
- or a `{ [quickId] = true }` set

## Managed UI State

When a module declares `definition.storage`, Lib creates `public.store.uiState`.

Use:
- `uiState.view` for rendering
- `uiState.get(alias)` for explicit reads
- `uiState.set(alias, value)` for edits
- `uiState.update(alias, fn)` for derived edits
- `uiState.toggle(alias)` for bool edits

Notes:
- persisted aliases stage in `uiState` and flush to Chalk on commit
- transient aliases also live in `uiState`, but never flush to Chalk
- `uiState.reloadFromConfig()` resets transient aliases to defaults
- `uiState.reset(alias)` resets one alias to its declared default
- `store.read/write(...)` remain persisted/runtime-facing; transient aliases are UI-state only

Example filter row:

```lua
public.definition.storage = {
    { type = "string", alias = "FilterText", lifetime = "transient", default = "", maxLen = 64 },
    { type = "string", alias = "FilterMode", lifetime = "transient", default = "all", maxLen = 16 },
}

public.definition.ui = {
    {
        type = "panel",
        columns = {
            { name = "label", start = 0, width = 80 },
            { name = "field", start = 88, width = 180 },
            { name = "action", start = 276, width = 90 },
        },
        children = {
            {
                type = "text",
                text = "Filter",
                panel = { line = 1, column = "label" },
            },
            {
                type = "inputText",
                binds = { value = "FilterText" },
                panel = { line = 1, column = "field", slots = { control = true } },
            },
            {
                type = "button",
                label = "Clear",
                onClick = function(uiState)
                    uiState.reset("FilterText")
                    uiState.reset("FilterMode")
                end,
                panel = { line = 1, column = "action" },
            },
        },
    },
}
```

Optional bind example:

```lua
public.definition.ui = {
    {
        type = "packedCheckboxList",
        binds = {
            value = "PackedFlags",
            filterText = "FilterText", -- optional; omit to render all packed rows
            filterMode = "FilterMode", -- optional; all/checked/unchecked
        },
        slotCount = 16,
        valueColors = {
            FlagBoss = { 0.85, 0.3, 0.3, 1 },
        },
    },
}
```

Do not write alias-backed config directly during draw.

Hosted Framework UI and standalone Lib helpers already:
- commit `uiState` transactionally
- roll persisted state back on failed reapply
- call `SetupRunData()` after successful commits when required

## Modules That Affect Run Data

If successful changes require run-data rebuild behavior, declare:

```lua
public.definition.affectsRunData = true
```

Lifecycle shape is inferred from exports.

### Patch-only

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(RoomData.RoomA, "ForcedReward", "Devotion")
    plan:appendUnique(NamedRequirementsData, "SomeKey", { Name = "Req" })
end
```

### Manual-only

```lua
local backup, restore = lib.createBackupSystem()

public.definition.apply = function()
    backup(SomeTable, "SomeKey")
    SomeTable.SomeKey = 123
end

public.definition.revert = restore
```

### Hybrid

```lua
public.definition.patchPlan = function(plan, store)
    plan:set(SomeTable, "SomeKey", 123)
end

public.definition.apply = function()
    -- procedural remainder
end

public.definition.revert = function()
    -- procedural remainder revert
end
```

Ordering:
- apply: patch, then manual
- revert: manual, then patch

## Hash/Profile Stability

After release, treat these as compatibility-sensitive:
- regular `definition.id`
- special `modName`
- storage root `alias` values — these are the hash keys
- storage defaults
- storage type hash encodings

`alias` is the frozen hash surface. If you omit `alias` on a root, it defaults to the stringified `configKey`, which means `configKey` is effectively frozen for that root too. If you declare an explicit `alias`, you can safely rename the underlying `configKey` (restructure Chalk config) without breaking saved hashes or profiles — the alias stays stable.

If those change, existing hashes and saved profiles may stop mapping cleanly.
