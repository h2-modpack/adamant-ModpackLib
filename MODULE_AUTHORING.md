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
- `shortName` is optional and only needed when a compact UI surface should use a shorter label than `name`
- storage may still use nested raw config paths
- alias names are the UI and `uiState` access surface

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
{ type = "checkbox", binds = { value = "EnabledFlag" }, label = "Enabled" }
{ type = "stepper", binds = { value = "Count" }, label = "Count", min = 1, max = 9, step = 1 }
{ type = "dropdown", binds = { value = "Mode" }, label = "Mode", values = { "Vanilla", "Chaos" } }
{ type = "packedCheckboxList", binds = { value = "PackedFlags" } }
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
```

### Module-local custom widgets and layouts

Modules may declare `definition.customTypes` when they want reusable UI pieces that should not be promoted into Lib:

```lua
public.definition.customTypes = {
    widgets = {
        myWidget = {
            binds = { value = { storageType = "int" } },
            geometry = { "controlStart", "controlWidth" }, -- optional supported geometry keys
            validate = function(node, prefix) end,
            draw = function(imgui, node, bound, width) end,
        },
    },
    layouts = {
        myLayout = {
            validate = function(node, prefix) end,
            render = function(imgui, node) return true end,
        },
    },
}
```

These custom types can be used by:
- hosted regular-module UI
- standalone Lib helpers
- Framework rendering
- special-module calls to `lib.drawUiNode(...)` / `lib.drawUiTree(...)`

Built-in widgets may also accept a widget-local `geometry` bag for manual horizontal placement.
`controlStart`, `control2Start`, and `separatorStart` are relative to the current row origin after any `indent`.
`decrementStart`, `valueStart`, `valueWidth`, and `incrementStart` are relative to the enclosing stepper control start.
`valueStart` is the absolute value-text position.
`valueAlign` may be `center` or `right` and aligns the value text inside an explicit `valueWidth` slot derived after the decrement button.
Start positions must be non-negative.
`valueAlign` requires an explicit `valueWidth`.
`valueStart` cannot be combined with `valueWidth` or `valueAlign`.

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
            separatorStart = 260,
            control2Start = 300,
            valueWidth = 14,
            valueAlign = "center",
            incrementStart = 42,
        },
        min = 1,
        max = 10,
        step = 1,
    },
}
```

### `visibleIf`

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
