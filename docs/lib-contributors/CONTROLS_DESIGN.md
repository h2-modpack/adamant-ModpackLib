# Controls Design

Contributor design spec for the `controls` capability.

This document describes the design and the first implemented Lib slice. It is
kept as an audit guide while first-party modules prove the shape.

## Status

Initial backend implemented.

Lib now has the backend pieces needed to support this:

- module declarations finalize during `module.activate()`
- storage/actions/cache/hash/draw are declared on `module`
- runtime callbacks receive `host, runtime`
- draw callbacks receive `host, ui`
- storage supports a trusted Lib-only `_` alias lane
- actions support a trusted Lib-only `_` key lane
- author-facing `ui.data` and `runtime.data` reject `_` aliases
- author-facing `ui.actions` and commit-action lookup reject `_` keys
- widgets render `StorageField` refs; write safety lives on the refs/actions
- `module.controls.defineTemplates(...)` and `module.controls.define(...)`
  compile to private storage/actions during activation
- `runtime.controls`, `ui.controls`, and `ui.draw.control(...)` are available

## Problem

Storage is good at durable typed data.

Widgets are good at leaf rendering.

UI-heavy modules need something in between: repeated domain controls that own a
small bundle of storage, semantic reads/writes, and one or more standard render
paths.

Representative patterns:

- priority selector controls
- category/subcategory controls
- packed selection pool controls
- route controls
- mode/range controls
- packed availability controls

Today those modules usually build:

```text
domain/catalog data -> storage aliases -> UI option tables -> widget calls -> logic readers
```

That is correct but verbose. The same domain concept gets split across data,
storage, UI, and logic files. The result is hard to audit because the unit the
author thinks about is larger than a storage field but smaller than a module.

## Decision

Add a `controls` capability.

Use plural `controls` for namespaces and declaration surfaces:

```lua
module.controls.defineTemplates(...)
module.controls.define(...)
ui.controls.get(...)
runtime.controls.get(...)
ui.draw.control(...)
```

Use singular `control` for one returned object or one template instance.

Controls are not storage metadata. They are module-declared composite
primitives that compile to private storage plus runtime/UI adapters.

Controls are also not custom widgets. A custom widget is still a draw-only
primitive: it renders already-existing data refs. A control crosses declaration,
UI, and runtime planes:

```text
control declaration -> private storage/actions -> UI renderer -> runtime reader
```

That wider contract is why controls deserve their own namespace instead of
being hidden under `ui.draw.widgets`.

The useful mental model is:

```text
control template = managed module-side class
control declaration = one object instance definition
ui.controls.get(...) / runtime.controls.get(...) = phase-specific object ref
private storage/actions = object fields hidden behind the control interface
```

Lib is not adding object orientation to Lua. Authors can already write normal
module-side classes. Lib controls are valuable only when that class spans the
UI/runtime line and needs Lib-managed storage, actions, phases, activation,
fingerprinting, and privacy.

Use a plain module class when the object is only code/data organization. Use a
Lib control when the object owns persisted/staged fields, table rows, packed
fields, scoped commands, or runtime/UI refs that should be managed consistently
with the rest of the module lifecycle.

## Goals

- Give UI-heavy modules a first-class way to define reusable composite controls.
- Support managed module-side classes when their objects need Lib-owned
  storage/action/phase/lifecycle integration.
- Keep storage as storage, not a declarative UI language.
- Keep widgets as leaf renderers.
- Let controls own private storage aliases without exposing those aliases to
  authors.
- Make control refs cacheable like storage refs.
- Make runtime and UI access phase-explicit through `runtime.controls` and
  `ui.controls`.
- Keep controls compatible with hashes/profiles through the existing storage
  backend.
- Support table-backed leaf controls when they expose semantic methods instead
  of raw table internals.
- Keep the first version small enough to prove scalar bundles and table-backed
  controls without broadening into layout.

## Non-Goals

- Do not reintroduce storage `ui = {...}` metadata.
- Do not reintroduce `draw.field(...)`.
- Do not make Lib storage/control internals know game catalogs.
- Do not build a retained UI tree.
- Do not make controls a second storage backend.
- Do not make controls a screen/layout/catalog builder.
- Do not hide controls under `ui.draw.widgets.*` as custom widgets.
- Do not ship domain-specific Lib templates in v1.
- Do not allow authors to read/write generated `_` aliases through normal
  `ui.data` or `runtime.data`.
- Do not support nested controls in the first version.
- Do not make controls own hooks, overlays, shared events, cache, mutation
  plans, commit observers, or lifecycle behavior.

## Author Model

A module declares templates and instances before activation:

```lua
module.controls.defineTemplates({
    RangeSelector = controls.RangeSelectorTemplate,
})

module.controls.define({
    PrioritySlot1 = {
        template = "RangeSelector",
        label = "Priority 1",
        values = VALUE_KEYS,
        displayValues = VALUE_LABELS,
        defaultMode = "Any",
        defaultMin = 1,
        defaultMax = 3,
        min = 1,
        max = 5,
        hash = true,
    },
})
```

Runtime code reads the semantic object:

```lua
module.hooks.wrap("Some.Path", function(host, runtime, base, ...)
    local priority = runtime.controls.get("PrioritySlot1")
    if priority:matches(currentValue) then
        -- runtime behavior
    end
    return base(...)
end)
```

UI code renders or manipulates the same semantic object:

```lua
module.ui.tab(function(host, ui)
    local priority = ui.controls.get("PrioritySlot1")
    ui.draw.control(priority)
end)
```

Manual UI remains possible when the default control renderer is not the right
fit for a screen:

```lua
module.ui.tab(function(host, ui)
    local priority = ui.controls.get("PrioritySlot1")
    ui.draw.widgets.dropdown(priority:field("Mode"), PRIORITY_MODE_OPTS)
    ui.draw.widgets.stepper(priority:field("Min"), PRIORITY_MIN_OPTS)
    ui.draw.widgets.stepper(priority:field("Max"), PRIORITY_MAX_OPTS)
end)
```

The raw generated aliases are not part of the author contract.

Modules may generate control declarations from module-owned catalog metadata
before activation. That is different from making Lib understand those catalogs:

```text
hand-authored source definitions
  -> domain/catalog hydration
  -> pure metadata
  -> control declarations
```

Controls consume prepared metadata. They should not perform external/game-data
hydration themselves.

## Template Contract

A control template is a module-owned class definition. It describes how one
control instance maps to private storage/actions and how phase-specific object
refs are constructed.

The template owns the methods exposed on the returned control object. Lib only
requires enough common shape to compile, cache, phase-gate, and draw refs. The
domain interface belongs to the template:

```text
RangeSelector object methods: read(), matches(...), field(...)
SelectionGroup object methods: selectedMask(...), isSelected(...)
RouteSlot object methods: readRoute(), writeRoute(...), reset()
```

Do not force unrelated templates into one broad shared method surface. Their
commonality is lifecycle/plumbing, not domain behavior.

Candidate shape:

```lua
local RangeSelector = {}

function RangeSelector.prepare(instance)
    if instance.min > instance.max then
        return nil, "min must be <= max"
    end
    return instance
end

function RangeSelector.storage(instance)
    return {
        {
            key = "Mode",
            type = "string",
            default = instance.defaultMode or "Any",
            maxLen = 32,
            hash = instance.hash ~= false,
        },
        {
            key = "Min",
            type = "int",
            default = instance.defaultMin or instance.min or 0,
            min = instance.min,
            max = instance.max,
            hash = instance.hash ~= false,
        },
        {
            key = "Max",
            type = "int",
            default = instance.defaultMax or instance.max or 0,
            min = instance.min,
            max = instance.max,
            hash = instance.hash ~= false,
        },
    }
end

function RangeSelector.createRuntime(fields, instance)
    local control = {}

    function control:name()
        return instance.name
    end

    function control:read()
        return {
            mode = fields.Mode:read(),
            min = fields.Min:read(),
            max = fields.Max:read(),
        }
    end

    function control:matches(value)
        -- template-owned semantics
    end

    return control
end

function RangeSelector.createUi(fields, instance)
    local control = {}

    function control:name()
        return instance.name
    end

    function control:read()
        return {
            mode = fields.Mode:read(),
            min = fields.Min:read(),
            max = fields.Max:read(),
        }
    end

    function control:writeMode(value)
        return fields.Mode:write(value)
    end

    function control:field(key)
        return fields[key]
    end

    return control
end
```

A table-backed control can expose a richer typed object without leaking table
internals:

```lua
local SelectionGroup = {}

function SelectionGroup.storage(instance)
    return {
        {
            key = "Rows",
            type = "table",
            minRows = 1,
            maxRows = instance.maxRows,
            defaultRows = instance.defaultRows,
            row = {
                {
                    key = "Selection",
                    type = "packedInt",
                    default = 0,
                    width = instance.width,
                    bits = instance.bits,
                },
            },
        },
    }
end

function SelectionGroup.createRuntime(fields, instance)
    local control = {}

    function control:count()
        return fields.Rows:count()
    end

    function control:selectedMask(rowIndex)
        return fields.Rows:get(rowIndex or 1, "Selection"):read() or 0
    end

    function control:isSelected(itemKey, rowIndex)
        local item = instance.itemByKey[itemKey]
        return item and bit32.band(self:selectedMask(rowIndex), item.mask) ~= 0
    end

    return control
end

function SelectionGroup.createUi(fields, instance)
    local control = {}

    function control:count()
        return fields.Rows:count()
    end

    function control:setCount(count)
        -- append/remove rows through fields.Rows
    end

    function control:selectionField(rowIndex)
        return fields.Rows:get(rowIndex or 1, "Selection")
    end

    function control:items()
        return instance.items
    end

    function control:isCustomized()
        -- inspect configured selection masks
    end

    return control
end
```

The packed-field helper names above are illustrative. The implementation can
settle on the actual packed child/ref API while keeping the same contract:
runtime methods return semantic scalar values, and UI methods return draw-safe
field refs when rendering needs a primitive widget.

The exact callback names can settle during implementation, but the split should
remain:

- `prepare(instance)` validates and normalizes template-specific fields
- `storage(instance)` returns field descriptors, not full public aliases
- `commands(instance)` or `commands = {...}` optionally returns scoped commands
- `createRuntime(fields, instance)` returns the runtime control object
- `createUi(fields, instance)` returns the UI control object
- `draw(draw, control, instance, opts)` draws the default UI control view
- `views = { ... }` optionally defines named UI control views

`prepare(instance)` is the template contact point. It owns domain validation for
fields like mode values, display values, range bounds, packed bit options, and
defaults. After a prepared instance enters the control compiler, downstream
control internals should trust it.

The returned control object is part of the template's author-facing contract.
Template docs should describe which methods exist on runtime refs, which
methods exist on UI refs, and which methods are shared.

For example:

```text
SelectionGroup runtime ref:
  count()
  selectedMask(rowIndex)
  isSelected(itemKey, rowIndex)

SelectionGroup UI ref:
  count()
  setCount(count)
  selectionField(rowIndex)
  items()
  isCustomized()
```

Templates may also declare scoped commands:

```lua
commands = {
    Reset = function(host, uiData, runtimeData, control, value)
        control:field("Mode"):write("Any")
    end,
}
```

Control commands are a mini version of actions. They lower into the existing
action subsystem using generated private action keys, just as control storage
lowers into generated private storage aliases. They are scoped to one control
instance and exposed only through that control ref.

```lua
function RangeSelector.draw(draw, control, instance, opts)
    draw.widgets.dropdown(control:field("Mode"), instance.modeOpts or opts.mode)
    draw.widgets.steppedRange(control:field("Min"), control:field("Max"), instance.rangeOpts or opts.range)
end
```

Advanced templates can define named views:

```lua
SelectionGroup.views = {
    default = function(draw, control, instance, opts)
        return SelectionGroup.views.list(draw, control, instance, opts)
    end,

    setup = function(draw, control, instance, opts)
        -- configured row count
    end,

    list = function(draw, control, instance, opts)
        -- search controls, reset buttons, packed checkbox list
    end,

    compactRow = function(draw, control, instance, opts)
        -- one compact packed dropdown row
    end,
}
```

Lib normalizes simple templates into a view table:

```text
template.draw -> template.views.default
```

Rules:

- missing view name uses `"default"`
- view names must be stable identifiers
- every template must have a default view, either via `draw` or `views.default`
- `ui.draw.control(control, "name", ...)` dispatches through the normalized
  template view table and passes remaining arguments to the selected view
- unknown view names are rejected by Lib at the draw boundary
- templates should not manually dispatch on a view option when `views` can
  model the variants directly

## Instance Declaration

Control declaration keys are stable public control names:

```lua
module.controls.define({
    PrioritySlot1 = {
        template = "RangeSelector",
        -- template-specific fields
    },
})
```

Rules:

- control names must be stable identifiers
- template names must be stable identifiers
- each instance must reference a declared template
- template-specific fields are validated by the template
- declarations close when activation begins
- controls participate in structural fingerprinting

## Private Storage Compilation

Controls compile to Lib-owned internal storage before definition preparation.

Generated aliases should be stable and private:

```text
_<ControlName>:<FieldKey>
```

Example:

```text
_PrioritySlot1:Mode
_PrioritySlot1:Min
_PrioritySlot1:Max
```

Generation rules:

- only Lib generates these aliases
- generated aliases must start with `_`
- generated traversal segments are separated with `:`
- generated aliases must be globally unique within the module storage schema
- generated aliases are passed to `prepareDefinitionWithInternalDeclarations(...)`
- normal `module.data.define(...)` cannot declare these aliases
- author-facing `ui.data` and `runtime.data` reject direct access to these
  aliases

Control field descriptors map to normal storage nodes after alias generation:

```lua
{
    key = "Min",
    type = "int",
    default = 1,
    min = 0,
    max = 5,
    hash = true,
}
```

becomes:

```lua
{
    alias = "_PrioritySlot1:Min",
    type = "int",
    default = 1,
    min = 0,
    max = 5,
    hash = true,
}
```

The storage engine remains the source of truth for normalization, persistence,
runtime mode, hashing, profiles, tables, packed ints, and config hydration.

Generated aliases are a clean new storage contract. Porting an existing module
from public aliases to controls can change persisted config/profile keys unless
the implementation intentionally supports explicit legacy aliases. Treat that
as a per-port migration decision, not as a reason to expose generated aliases.

## Data Access

Controls are exposed through phase control namespaces, not through raw storage
aliases.

Runtime:

```lua
runtime.controls.get("PrioritySlot1")
runtime.controls.read("PrioritySlot1")
```

UI:

```lua
ui.controls.get("PrioritySlot1")
ui.controls.read("PrioritySlot1")
```

`get(...)` returns a cached control object.

`read(...)` is optional convenience sugar and should only exist if the control
template exposes a `read` method. It should be equivalent to:

```lua
local control = ui.controls.get(name)
return control and control:read()
```

Returned refs are variant-shaped:

- runtime controls expose runtime/read-only methods
- UI controls expose draw/staged methods
- escaped write/action refs remain guarded by their mutation methods

## Drawing

Rendering belongs to draw, not to data.

Preferred:

```lua
ui.draw.control(ui.controls.get("PrioritySlot1"))
```

Manual rendering remains:

```lua
local priority = ui.controls.get("PrioritySlot1")
ui.draw.widgets.dropdown(priority:field("Mode"), MODE_OPTS)
ui.draw.widgets.stepper(priority:field("Min"), MIN_OPTS)
ui.draw.widgets.stepper(priority:field("Max"), MAX_OPTS)
```

Why `ui.draw.control(...)` instead of `control:draw(...)`:

- draw remains the rendering authority
- controls remain semantic data/UI adapters
- raw ImGui and widgets stay under the draw object
- phase errors stay consistent with the rest of draw

The renderer can still dispatch by the control template internally.

Why singular `control`:

- `ui.draw` is already the verb
- the control object carries the concrete type/template
- the operation renders one control object
- widget names are different because widget names are the draw operation

The intended contrast is:

```lua
ui.draw.widgets.dropdown(field, opts) -- primitive draw operation by name
ui.draw.control(control, view, ...)   -- typed object chooses its renderer
```

Controls may expose named render variants through first-class template views and
explicit draw options:

```lua
ui.draw.control(source, "setup")
ui.draw.control(source, "list", 1, "primary")
ui.draw.control(source, "compactRow", 2)
```

This is explicit single dispatch. The view name selects an alternate projection
of the same semantic control data from the template's normalized `views` table,
and the selected view owns the remaining positional arguments.

Allowed:

```text
setup
list
compactRow
```

Not allowed:

```text
drawWholeCategoryTab
drawWholeFeatureScreen
drawAllModuleSettings
```

The guardrail is simple: a view may render one control's data in a different
shape. It must not become a screen/layout builder.

Query and metadata helpers belong on the control object, not the draw namespace:

```lua
control:canDraw()
control:kind()
control:name()
```

Do not add `ui.draw.controls.canRender(...)` or similar namespace helpers unless
the query is truly about the draw backend rather than the control object.

## Relationship To Catalogs And Layout

Modules own catalogs and layout.

Controls are leaf composites. They should know how to read, write, and draw one
domain unit, but they should not know where that unit belongs on a screen.

Module-owned code should continue to own:

- game/domain catalogs
- grouping and ordering
- tabs and sections
- render order
- visibility rules
- cross-control orchestration

The control replaces repeated alias/binding/widget/reader bundles. It does not
replace the catalog or UI file that decides which controls render in which
order.

Do not add nested controls in v1 to solve layout. Parent/group composites can
stay module-local tables that organize leaf controls.

## Relationship To Widgets

Widgets stay leaf renderers:

```lua
ui.draw.widgets.dropdown(field, opts)
ui.draw.widgets.checkbox(field, opts)
```

Controls are composites that may call widgets:

```lua
ui.draw.control(control)
```

Controls should not replace widgets. They should reduce boilerplate for repeated
domain patterns while leaving immediate-mode UI explicit for one-off layouts.

This is the intended distinction:

```text
widget  = render/edit one field
control = own and expose a repeated data-backed UI unit
layout  = module-owned screen/domain composition
```

If something only draws existing refs, make it a widget/helper. If it also owns
private storage and runtime semantics, make it a control.

## Relationship To Templates

Lib provides the control mechanism, not the domain template library.

Templates should normally live in the module or in pack-level shared helper
code. A template should move into Lib only after unrelated modules prove that
the data shape, draw behavior, and runtime semantics are all stable and
domain-neutral.

Examples like `RangeSelector`, `RouteSlot`, `SelectionGroup`, and
`PackedRewardGroup` are good module templates. They carry domain assumptions
about modes, ranges, options, labels, filtering, and conditional visibility.
Those assumptions should not become Lib primitives prematurely.

Templates can be generated from pure module metadata. A source definition can be
hand-authored while the metadata is hydrated elsewhere:

```lua
PrimaryRewards = {
    template = "SelectionGroup",
    label = "Primary Rewards",
    group = "Rewards",
    color = catalog.PrimaryRewards.color,
    maxRows = 10,
    defaultRows = 5,
    items = catalog.PrimaryRewards.items,
}
```

The template receives `items` as already-hydrated metadata. It does not know how
those items were discovered.

## Relationship To Storage

Storage remains the primitive data schema.

Controls use storage internally, but they do not expose storage aliases as the
main author API.

Authors should not be asked to declare:

```lua
{ alias = "PrioritySlot1Mode", ... }
{ alias = "PrioritySlot1Min", ... }
{ alias = "PrioritySlot1Max", ... }
```

when they mean:

```lua
PrioritySlot1 = { template = "RangeSelector", ... }
```

Controls are the owner of those generated fields.

## Relationship To Actions

Controls that directly edit UI-backed storage should behave like widgets:

```text
draw -> widget/control edit -> staged UI data
```

Actions remain the explicit bridge for side effects:

```text
draw -> action intent -> post-draw action handler
```

Controls can define scoped commands for behavior that is intrinsic to the
control, such as a reset button inside a repeated control template:

```lua
commands = {
    Reset = function(host, uiData, runtimeData, control, value)
        control:reset()
    end,
}

function RouteSlot.draw(draw, control)
    draw.widgets.button("Reset", {
        action = control:command("Reset"),
    })
end
```

Rules:

- command names are local to the template/control instance
- generated action keys are private and not visible through `ui.actions.get(...)`
- command refs are only exposed through the control ref
- commands run in the same post-draw action phase as normal actions
- commands receive the specific control ref
- module-level `module.actions.define(...)` remains the right surface for
  module-wide commands

Do not use control commands for lifecycle behavior. A control command may edit
the control's data or bridge simple UI intent into runtime-owned data. If the
behavior needs commit observation, hooks, overlays, shared events, cache, or
mutation, it belongs at module level.

Example module-level coordination:

```lua
module.onCommit(function(host, runtime, commit)
    local routeSlot = runtime.controls.get("RouteSlot1")
    -- module-level behavior that consumes the control
end)
```

Controls compose data, draw, and basic scoped commands. Everything beyond that
is the module itself.

## Hashes And Profiles

Controls compile to storage, so hash/profile support comes from storage.

Rules:

- generated control storage with `hash = true` participates in hashes
- generated control storage with `hash = false` is excluded

Do not expose generated aliases to solve hash size. If hashes become too long,
shorten the final canonical string through a transport compression layer instead
of adding control-specific bit layouts.

## Tables

Controls may compile to table storage. Table-backed controls are part of the v1
target because they prove that controls can support repeated row data without
exposing raw table internals.

The first useful controls are likely scalar bundles and table-backed leaf
controls:

- dropdown + range
- label + packed selection
- enabled flag + numeric limit
- priority slot
- configurable row groups
- table row containing a packed selection mask
- table-backed route slots

If a control needs rows, prefer a control method that exposes semantic row
operations instead of leaking table internals:

```lua
local routes = ui.controls.get("Routes")
routes:count()
routes:readRoute(index)
routes:writeRoute(index, route)
```

Table-backed example:

```lua
local source = runtime.controls.get("PrimaryRewards")
source:count()
source:selectedMask(2)
source:isSelected("RewardA", 2)

local source = ui.controls.get("PrimaryRewards")
source:setCount(3)
ui.draw.control(source, "list", 2)
```

Do not add nested controls in v1.

## Internal Architecture

Files:

```text
src/core/controls/00_init.lua
src/core/controls/declarations.lua
src/core/controls/compiler.lua
src/core/controls/refs.lua
src/core/controls/draw_controls.lua
```

Responsibilities:

### `declarations.lua`

Own declaration contact-point validation:

- template table shape
- template `draw`/`views` shape
- stable view names
- default view presence
- instance table shape
- stable names
- duplicate names
- missing template reference
- template callbacks are functions when present

### `compiler.lua`

Turn validated declarations into:

- internal storage nodes
- internal action declarations for scoped control commands
- prepared control catalog
- per-instance generated alias bindings
- renderer dispatch metadata

This runs during activation finalization before
`prepareDefinitionWithInternalDeclarations(...)`.

### `refs.lua`

Build runtime and UI control access over trusted `persistentState` and
`stagedState`.

It may call internal/private aliases because it is not the author `runtime.data`
or `ui.data` facade. Returned refs are variant-shaped and cached per facade.

### `draw_controls.lua`

Render UI control refs by dispatching to the template renderer.

This plugs into `ui.draw.control(...)`.

## Activation Flow

Activation flow:

```text
module.controls.defineTemplates(...)
module.controls.define(...)
module.activate()
  controls.compile(declarations.controls)
    -> internalStorage
    -> internalActions
    -> controlCatalog
  prepareDefinitionWithInternalDeclarations(..., internalStorage, internalActions)
  moduleState.create(config, definition)
  managedModule.create(...)
    runtime.controls = controls.refs.createRuntime(...)
    ui.controls = controls.refs.createUi(...)
    ui.draw.control = controls.draw.render
```

The important boundary is:

```text
controls compile before storage preparation
control refs build after state creation
```

## Public Surface

Public additions:

```lua
module.controls.defineTemplates(templates)
module.controls.define(instances)
runtime.controls.get(name)
runtime.controls.read(name, ...)
ui.controls.get(name)
ui.controls.read(name, ...)
ui.draw.control(control)
ui.draw.control(control, viewName, ...)
```

Potential later additions:

```lua
runtime.controls.names()
ui.controls.names()
```

Avoid adding list/introspection helpers until first-party modules need them.

## Validation Policies

Policies:

- `controls.invalid_declaration`
- `controls.duplicate_name`
- `controls.unknown_template`
- `controls.invalid_template`
- `controls.invalid_field`
- `controls.unknown_control`
- `controls.invalid_render_target`

Validation should happen at contact points:

- `module.controls.defineTemplates(...)`
- `module.controls.define(...)`
- activation compilation
- `ui.controls.get(...)` / `runtime.controls.get(...)` unknown names
- `ui.draw.control(...)` target shape

After compilation, internal code should trust the prepared control catalog.

## Performance

Controls must not allocate on every draw call.

Requirements:

- `ui.controls.get(name)` caches refs per module UI phase object
- `runtime.controls.get(name)` caches refs per module runtime object
- control refs cache generated field refs
- `ui.draw.control(...)` does not build option tables internally
- named views use `ui.draw.control(control, viewName, ...)` so templates can
  receive explicit positional arguments instead of draw-time option blobs
- template authors should keep static opts and option lists outside draw loops

The private alias check remains on author data facades only. Control adapters
use trusted internal state directly, so rendering controls should not pay a
private-alias rejection cost on every field access.

## Validation Scenarios

These scenarios motivated the design. They are not normative Lib requirements.
They are kept here as concrete checks that the generic control contract is not
too weak.

### BiomeControl

Reference pattern:

```text
domain catalog -> ordered rooms/minibosses/NPCs/specials -> control names/refs
UI files -> explicit sections/order -> ui.draw.control(...)
logic files -> runtime.controls.get(...) or catalog-indexed control refs
```

The control should replace repeated alias/binding/widget/reader bundles. It
should not replace the biome catalog or the UI file that decides render order.

Useful control shapes:

- scalar range/mode selectors
- route/priority slots
- room/miniboss/trial-room controls with different UI views

### BoonBans

Stress-test pattern:

```text
source definitions -> hydrated reward metadata -> selection-control declarations
root groups -> module-owned layout
selection control -> setup/list/rarity/compact-row views
runtime logic -> selection masks, overrides, configured row count
```

The control should replace repeated table access, packed-bit label hydration,
packed refs, and runtime mask reads. It should not replace module-owned root
groups, active-tab state, or cross-root panels.

Useful control shapes:

- table-backed selection group
- packed reward/trait masks
- optional secondary packed values such as rarity/priority overrides
- multiple named views over the same control data

## First Implementation Slice

Implemented enough to prove the model:

1. Add `controls` declaration buckets.
2. Add template and instance validation.
3. Compile scalar and table field descriptors into internal `_` storage aliases.
4. Compile scoped commands into internal action declarations.
5. Add prepared control catalog to the managed module record.
6. Add `runtime.controls.get`.
7. Add `ui.controls.get`.
8. Add `ui.draw.control`.
9. Add tests for:
   - generated `_` aliases cannot be read through `ui.data` or `runtime.data`
   - controls can read/write their own generated storage
   - scoped commands run through the normal post-draw action phase
   - control refs are cached
   - phase gates reject escaped refs
   - `ui.draw.control(...)` dispatches to the template renderer
   - `ui.draw.control(...)` dispatches explicit string view variants
   - simple `draw(...)` templates are normalized into `views.default`
   - unknown view names are rejected
   - table-backed controls can expose semantic row methods without leaking raw
     private aliases
10. Port one narrow first-party scalar-bundle slice with a clear alias/migration
   decision.
11. Then port one first-party table-backed slice before broadening the API. This
   is the stress test for table-backed controls, hydrated metadata, and view
   variants.

## Risks

- Controls can become a declarative UI language by accident.
- Template callbacks can become broad context blobs.
- Scoped commands can become a hidden lifecycle system.
- Generated aliases can make hashes/profiles harder to explain.
- Too much template genericity can make module code less readable than direct UI.
- Nested controls can create a mini component framework; avoid them initially.
- Control renderers can hide too much immediate-mode layout.
- View variants can become a disguised screen builder.
- Table-backed controls can leak table internals if their methods are too thin.

## Guardrails

- Keep storage, logic, and drawing roles explicit.
- Keep catalogs, grouping, ordering, and screen layout in module code.
- Prefer small module-local templates over a global abstract template library.
- Keep render order in UI files, not inside large orchestration helpers.
- Do not make controls mandatory for simple fields.
- Do not move dynamic game catalog projection into storage.
- Keep game-data hydration in module-owned catalog code; controls consume pure
  metadata.
- Do not expose generated aliases as a workaround.
- Do not let controls register lifecycle callbacks or external capabilities.
- Add first-party ports one module slice at a time and stop if readability gets
  worse.

## Settled Choices

- Template declaration uses `defineTemplates(...)` plus `define(...)`. Do not
  add inline templates in v1; the friction is intentional because controls
  should pay for themselves through reuse.
- Rendering one control uses `ui.draw.control(control, viewName, ...)`, not
  `ui.draw.controls.render(...)`.
- `ui.draw.control(control, viewName, ...)` accepts a stable view name and
  forwards remaining arguments to the selected view. Template view functions own
  those positional arguments.
- Control-specific queries belong on the control object, not the draw namespace.
- Template methods define the control object's author-facing interface. Lib
  manages lifecycle/plumbing; it does not impose one broad domain method set.
- Template views are first-class. Simple `draw(...)` templates normalize to
  `views.default`; advanced templates define `views = { default = ..., ... }`.
- Explicit string view dispatch is allowed through the normalized view table for
  alternate render projections of the same control data.
- Generated private storage hashes normally. If profile/hash size becomes a real
  issue, prefer final-string compression over control-specific bit grouping.
- Lib does not ship built-in templates in v1. Controls are domain-specific, so
  first-party modules should define local templates until patterns stabilize.
- Controls are data-backed composites, not custom widgets. Do not route control
  templates through `ui.draw.widgets`.
- Modules own catalogs and layout. Controls own repeated leaf data/draw/runtime
  units.
- Table-backed controls are in scope for v1 when they remain leaf controls and
  expose semantic methods instead of raw table internals.

## Open Questions

No blocking design questions for v1. Implementation details such as exact helper
names for packed child refs can settle during the first slice.
