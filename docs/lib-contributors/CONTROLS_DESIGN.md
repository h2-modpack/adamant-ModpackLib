# Controls Design

Contributor design spec for a future `controls` capability.

This document describes the backend shape only. It does not implement controls.

## Status

Proposed.

Lib now has the backend pieces needed to support this:

- module declarations finalize during `module.activate()`
- storage/actions/cache/hash/draw are declared on `module`
- runtime callbacks receive `host, runtime`
- draw callbacks receive `host, ui`
- storage supports a trusted Lib-only `_` alias lane
- actions support a trusted Lib-only `_` key lane
- author-facing `ui.data` and `runtime.data` reject `_` aliases
- author-facing `ui.actions` and commit-action lookup reject `_` keys
- widgets render `StorageField` refs and are phase-gated by `ui.draw`

## Problem

Storage is good at durable typed data.

Widgets are good at leaf rendering.

UI-heavy modules need something in between: repeated domain controls that own a
small bundle of storage, semantic reads/writes, and one or more standard render
paths.

Examples from first-party modules:

- biome priority controls
- room/miniboss/trial room controls
- boon-ban pool controls
- NPC route controls
- mode/range controls
- packed availability controls

Today those modules usually build:

```text
game/catalog data -> storage aliases -> UI option tables -> widget calls -> logic readers
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

## Goals

- Give UI-heavy modules a first-class way to define reusable composite controls.
- Keep storage as storage, not a declarative UI language.
- Keep widgets as leaf renderers.
- Let controls own private storage aliases without exposing those aliases to
  authors.
- Make control refs cacheable like storage refs.
- Make runtime and UI access phase-explicit through `runtime.controls` and
  `ui.controls`.
- Keep controls compatible with hashes/profiles through the existing storage
  backend.
- Keep the first version small enough to prove on BiomeControl and BoonBans.

## Non-Goals

- Do not reintroduce storage `ui = {...}` metadata.
- Do not reintroduce `draw.field(...)`.
- Do not make storage declarations depend on game catalogs.
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
    ModeRange = controls.modeRangeTemplate,
})

module.controls.define({
    BiomePriority1 = {
        template = "ModeRange",
        label = "Priority 1",
        values = BIOME_KEYS,
        displayValues = BIOME_LABELS,
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
    local priority = runtime.controls.get("BiomePriority1")
    if priority:matches(currentBiome) then
        -- runtime behavior
    end
    return base(...)
end)
```

UI code renders or manipulates the same semantic object:

```lua
module.ui.tab(function(host, ui)
    local priority = ui.controls.get("BiomePriority1")
    ui.draw.control(priority)
end)
```

Manual UI remains possible when the default control renderer is not the right
fit for a screen:

```lua
module.ui.tab(function(host, ui)
    local priority = ui.controls.get("BiomePriority1")
    ui.draw.widgets.dropdown(priority:field("Mode"), PRIORITY_MODE_OPTS)
    ui.draw.widgets.stepper(priority:field("Min"), PRIORITY_MIN_OPTS)
    ui.draw.widgets.stepper(priority:field("Max"), PRIORITY_MAX_OPTS)
end)
```

The raw generated aliases are not part of the author contract.

## Template Contract

A control template is a Lib-facing module-owned object. It describes how one
control instance maps to private storage and how phase-specific refs are
constructed.

Candidate shape:

```lua
local ModeRange = {}

function ModeRange.prepare(instance)
    if instance.min > instance.max then
        return nil, "min must be <= max"
    end
    return instance
end

function ModeRange.storage(instance)
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

function ModeRange.createRuntime(fields, instance)
    return {
        read = function(self)
            return {
                mode = fields.Mode:read(),
                min = fields.Min:read(),
                max = fields.Max:read(),
            }
        end,
        matches = function(self, value)
            -- template-owned semantics
        end,
    }
end

function ModeRange.createUi(fields, instance)
    return {
        read = function(self)
            return {
                mode = fields.Mode:read(),
                min = fields.Min:read(),
                max = fields.Max:read(),
            }
        end,
        writeMode = function(self, value)
            return fields.Mode:write(value)
        end,
        field = function(self, key)
            return fields[key]
        end,
    }
end

function ModeRange.draw(draw, control, instance, opts)
    draw.widgets.dropdown(control:field("Mode"), instance.modeOpts or opts.mode)
    draw.widgets.steppedRange(control:field("Min"), control:field("Max"), instance.rangeOpts or opts.range)
end

return ModeRange
```

The exact callback names can settle during implementation, but the split should
remain:

- `prepare(instance)` validates and normalizes template-specific fields
- `storage(instance)` returns field descriptors, not full public aliases
- `createRuntime(fields, instance)` returns runtime control ref
- `createUi(fields, instance)` returns UI control ref
- `draw(draw, control, instance, opts)` draws the UI control

`prepare(instance)` is the template contact point. It owns domain validation for
fields like mode values, display values, range bounds, packed bit options, and
defaults. After a prepared instance enters the control compiler, downstream
control internals should trust it.

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

## Instance Declaration

Control declaration keys are stable public control names:

```lua
module.controls.define({
    BiomePriority1 = {
        template = "ModeRange",
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
_<ControlName>_<FieldKey>
```

Example:

```text
_BiomePriority1_Mode
_BiomePriority1_Min
_BiomePriority1_Max
```

Generation rules:

- only Lib generates these aliases
- generated aliases must start with `_`
- generated aliases must be globally unique within the module storage schema
- generated aliases are passed to `prepareDefinitionWithInternalStorage(...)`
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
    alias = "_BiomePriority1_Min",
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
runtime.controls.get("BiomePriority1")
runtime.controls.read("BiomePriority1")
```

UI:

```lua
ui.controls.get("BiomePriority1")
ui.controls.read("BiomePriority1")
```

`get(...)` returns a cached control object.

`read(...)` is optional convenience sugar and should only exist if the control
template exposes a `read` method. It should be equivalent to:

```lua
local control = ui.controls.get(name)
return control and control:read()
```

Returned refs are phase-gated:

- runtime controls reject during draw
- UI controls reject outside draw
- escaped control refs remain unusable outside their phase

## Drawing

Rendering belongs to draw, not to data.

Preferred:

```lua
ui.draw.control(ui.controls.get("BiomePriority1"))
```

Manual rendering remains:

```lua
local priority = ui.controls.get("BiomePriority1")
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
ui.draw.control(control, opts)        -- typed object chooses its renderer
```

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

BiomeControl3 is the reference scenario:

```text
biome catalog -> ordered rooms/minibosses/NPCs/specials -> control names/refs
UI files -> explicit sections/order -> ui.draw.control(...)
logic files -> runtime.controls.get(...) or catalog-indexed control refs
```

The control replaces the repeated alias/binding/widget/reader bundle. It does
not replace the biome catalog or the UI file that decides that Ephyra renders
rooms, then minibosses, then rewards.

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

BiomeControl examples like `modeRange`, `npcModeRange`, and
`packedRewardBans` are good module templates. They carry domain assumptions
about room modes, forced ranges, packed reward options, labels, and conditional
visibility. Those assumptions should not become Lib primitives prematurely.

## Relationship To Storage

Storage remains the primitive data schema.

Controls use storage internally, but they do not expose storage aliases as the
main author API.

Authors should not be asked to declare:

```lua
{ alias = "BiomePriority1Mode", ... }
{ alias = "BiomePriority1Min", ... }
{ alias = "BiomePriority1Max", ... }
```

when they mean:

```lua
BiomePriority1 = { template = "ModeRange", ... }
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
- module `hashGroups` should not reference generated private aliases directly
- control-specific hash grouping is out of scope for the first version

If control hash compaction becomes necessary, add a control-level hash hint
later:

```lua
BiomePriority1 = {
    template = "ModeRange",
    hashGroup = "BiomePriority",
}
```

Do not expose generated aliases to solve hash grouping.

## Tables

Controls may compile to table storage, but the first version should avoid table
control templates unless a concrete module needs one.

The first useful controls are likely scalar bundles:

- dropdown + range
- label + packed selection
- enabled flag + numeric limit
- priority slot

If a control needs rows, prefer a control method that exposes semantic row
operations instead of leaking table internals:

```lua
local routes = ui.controls.get("Routes")
routes:count()
routes:readRoute(index)
routes:writeRoute(index, route)
```

Do not add nested controls in v1.

## Internal Architecture

Suggested files:

```text
src/core/controls/00_init.lua
src/core/controls/declarations.lua
src/core/controls/compiler.lua
src/core/controls/runtime_controls.lua
src/core/controls/ui_controls.lua
src/core/controls/draw_controls.lua
```

Responsibilities:

### `declarations.lua`

Own declaration contact-point validation:

- template table shape
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

This runs during activation finalization before `prepareDefinitionWithInternalStorage`.

### `runtime_controls.lua`

Build runtime control access over trusted `persistentState`.

It may call internal/private aliases because it is not the author `runtime.data`
facade.

### `ui_controls.lua`

Build UI control access over trusted `stagedState`.

It may call internal/private aliases because it is not the author `ui.data`
facade.

Returned refs are draw-gated.

### `draw_controls.lua`

Render UI control refs by dispatching to the template renderer.

This plugs into `ui.draw.control(...)`.

## Activation Flow

Target activation flow:

```text
module.controls.defineTemplates(...)
module.controls.define(...)
module.activate()
  controls.compile(declarations.controls)
    -> internalStorage
    -> internalActions
    -> controlCatalog
  prepareDefinitionWithInternalStorage(..., internalStorage)
  moduleState.create(config, definition)
  controls.createRuntime(persistentState, controlCatalog)
  controls.createUi(stagedState, controlCatalog)
  ui.draw.control = controls.createDraw(controlCatalog)
  managedModule.create(...)
```

The important boundary is:

```text
controls compile before storage preparation
control refs build after state creation
```

## Public Surface

Proposed public additions:

```lua
module.controls.defineTemplates(templates)
module.controls.define(instances)
runtime.controls.get(name)
runtime.controls.read(name, ...)
ui.controls.get(name)
ui.controls.read(name, ...)
ui.draw.control(control, opts)
```

Potential later additions:

```lua
runtime.controls.names()
ui.controls.names()
```

Avoid adding list/introspection helpers until first-party modules need them.

## Validation Policies

Likely policies:

- `controls.invalid_declaration`
- `controls.duplicate_name`
- `controls.unknown_template`
- `controls.invalid_template`
- `controls.invalid_field`
- `controls.unknown_control`
- `controls.invalid_phase`
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
- `ui.draw.control(...)` does not build option tables internally unless
  the template explicitly does so
- template authors should keep static opts and option lists outside draw loops

The private alias check remains on author data facades only. Control adapters
use trusted internal state directly, so rendering controls should not pay a
private-alias rejection cost on every field access.

## First Implementation Slice

Implement only enough to prove the model:

1. Add `controls` declaration buckets.
2. Add template and instance validation.
3. Compile simple scalar field descriptors into internal `_` storage aliases.
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
10. Port one narrow first-party slice, preferably one BiomeControl control with
   a clear alias/migration decision, before broadening the API.

## Risks

- Controls can become a declarative UI language by accident.
- Template callbacks can become broad context blobs.
- Scoped commands can become a hidden lifecycle system.
- Generated aliases can make hashes/profiles harder to explain.
- Too much template genericity can make module code less readable than direct UI.
- Nested controls can create a mini component framework; avoid them initially.
- Control renderers can hide too much immediate-mode layout.

## Guardrails

- Keep storage, logic, and drawing roles explicit.
- Keep catalogs, grouping, ordering, and screen layout in module code.
- Prefer small module-local templates over a global abstract template library.
- Keep render order in UI files, not inside large orchestration helpers.
- Do not make controls mandatory for simple fields.
- Do not move dynamic game catalog projection into storage.
- Do not expose generated aliases as a workaround.
- Do not let controls register lifecycle callbacks or external capabilities.
- Add first-party ports one module slice at a time and stop if readability gets
  worse.

## Settled Choices

- Template declaration uses `defineTemplates(...)` plus `define(...)`. Do not
  add inline templates in v1; the friction is intentional because controls
  should pay for themselves through reuse.
- Rendering one control uses `ui.draw.control(control, opts)`, not
  `ui.draw.controls.render(...)`.
- `ui.draw.control(control, opts)` accepts draw-time `opts`. Template draw
  functions own how to interpret or pass through those options.
- Control-specific queries belong on the control object, not the draw namespace.
- Control-level hash grouping is out of scope for v1. Generated private storage
  hashes normally; add grouping only if a real profile/hash size issue appears.
- Lib does not ship built-in templates in v1. Controls are domain-specific, so
  first-party modules should define local templates until patterns stabilize.
- Controls are data-backed composites, not custom widgets. Do not route control
  templates through `ui.draw.widgets`.
- Modules own catalogs and layout. Controls own repeated leaf data/draw/runtime
  units.

## Open Questions

No open design questions for v1.
