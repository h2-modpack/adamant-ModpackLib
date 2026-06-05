# Controls

Contributor guidance and implementation contract for the `controls`
capability.

Controls are module-declared composite leaf objects. Use this doc when deciding
whether controls are appropriate for a module and when changing Lib internals
that compile or render controls.

## Problem

Immediate-mode UI scales well for simple screens, but repeated data-backed UI
can become hard to trace when the same concept is split across:

- storage declarations
- runtime readers
- draw-time widget calls
- option tables
- labels/tooltips
- hash/profile grouping
- module catalogs

The problem is not that widgets are weak. Widgets are good leaf renderers. The
problem is that large modules often think in larger leaf concepts than one
widget call:

```text
choice setting
flag setting
mode plus range setting
packed selection set
priority slot
```

When those concepts are repeated many times, the UI file becomes a low-level
dump of storage refs and widget calls instead of a readable composition of
module concepts.

## Escalation Ladder

Use the lowest abstraction that keeps the module easy to read.

### Simple UI

Use direct `ui.data`, `ui.draw.widgets`, and `ui.draw.imgui` code.

This is the right default for small modules and one-off settings. A single
checkbox or dropdown does not need a control object only to avoid one widget
call.

### One Large Or Repeated Element

Define one control for the repeated or semantic element, and keep the rest of
the screen as widgets/direct ImGui.

This is useful when one setting is really a small object with more than one
field, a semantic runtime interface, or repeated draw behavior. Examples:

- mode plus range
- route slot
- priority selector
- packed selection set

### Complex Control-Heavy UI

Use controls for the repeated leaf settings and let UI files compose those
controls into sections, tabs, and rows.

In this style, the UI file should read as screen composition:

```text
draw section
draw named control
draw named control
draw section
draw named control
```

The control template owns the leaf's storage, default rendering, runtime reads,
and internal conditional visibility.

## Boundary

Controls are leaf elements rendered as one unit.

Controls may own:

- private configuration storage fields
- labels, tooltips, options, defaults, and display values
- semantic runtime reads
- field-level writes during draw
- default draw behavior
- alternate views over the same leaf data
- conditional visibility inside their own data structure

Controls should not own:

- tabs
- sections
- screen ordering
- sibling placement
- cross-screen orchestration
- module lifecycle behavior
- hooks, overlays, mutation plans, shared events, or cache declarations
- runtime-owned coordination state or command actions

If visibility depends only on fields owned by the control, keep it inside the
control. If visibility depends on sibling controls or screen state, keep that in
the UI composition code or merge the fields into one larger leaf control.

## Metadata

Definitions should describe the module concept, not the draw implementation.

Prefer semantic setting/control metadata:

```text
Flag
Choice
Mode
ModeWithRange
PackedSet
```

Avoid making catalogs depend on raw rendering language:

```text
Dropdown
Checkbox
StepperRow
```

The template can choose whether a `Flag` is rendered as a checkbox, toggle, icon
button, or compact row. The draw code should not need to change when that
presentation changes.

This decoupling is the main benefit of controls for large modules:

```text
definition declares leaf control
control template owns fields and behavior
UI composes named controls
logic reads named controls
```

## Widgets Position

Controls do eat into part of the normal `ui.draw.widgets` design space. That is
acceptable if it is intentional.

Recommended stack:

```text
controls = named data-backed leaf setting objects
widgets = low-level immediate-mode renderers
imgui = raw escape hatch
```

Widgets remain first-class. They are still the right tool for custom draw code,
simple modules, unusual UI, and control template internals. They should not be
treated as deprecated just because large control-heavy modules benefit from a
higher-level layer.

## Public Surface

Controls use plural names for namespaces and declaration surfaces:

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

Use singular `control` for one returned object or one template instance.

Controls are not storage metadata and they are not custom widgets. A custom
widget renders already-existing refs. A control crosses declaration, UI, and
runtime planes:

```text
control declaration -> private storage -> UI renderer -> runtime reader
```

The useful mental model:

```text
control template = managed module-side class
control declaration = one object instance definition
ui.controls.get(...) / runtime.controls.get(...) = phase-specific object ref
private storage = object fields hidden behind the control interface
```

Use a plain module class when the object is only code/data organization. Use a
Lib control when the object owns persisted/staged fields, table rows, packed
fields, or runtime/UI refs that should be managed consistently with the rest of
the module lifecycle.

## Template Contract

A control template is a module-owned class definition. It describes how one
control instance maps to private storage and how phase-specific object
refs are constructed.

Common template entry points:

- `storage(instance)` returns private storage descriptors using `key` rather
  than public `alias`.
- `createRuntime(fields, instance)` returns the runtime control ref.
- `createUi(fields, instance)` returns the UI control ref.
- `draw(draw, control, instance, ...)` defines the default view.
- `views = { name = function(draw, control, instance, ...) end }` defines
  named views.

The template owns the methods exposed on returned refs. Lib only requires
enough common shape to compile, cache, build phase-specific refs, and draw refs.

Generated field keys are compiled to private `_` storage aliases. Author-facing
`ui.data` and `runtime.data` reject those aliases; control internals access
them through trusted adapters.

## Activation Flow

Controls compile before storage preparation:

```text
module.controls.defineTemplates(...)
module.controls.define(...)
module.activate()
  controls.compile(declarations.controls)
    -> internalStorage
    -> controlCatalog
  prepareDefinitionWithInternalDeclarations(..., internalStorage)
  moduleState.create(config, definition)
  managedModule.create(...)
    runtime.controls = controls.refs.createRuntime(...)
    ui.controls = controls.refs.createUi(...)
    ui.draw.control = controls.draw.render
```

The important boundary:

```text
controls compile before storage preparation
control refs build after state creation
```

## Validation

Validate controls at contact points:

- `module.controls.defineTemplates(...)`
- `module.controls.define(...)`
- activation compilation
- `ui.controls.get(...)` and `runtime.controls.get(...)` unknown names
- `ui.draw.control(...)` target shape

Common diagnostic families:

- `controls.invalid_declaration`
- `controls.duplicate_name`
- `controls.unknown_template`
- `controls.invalid_template`
- `controls.invalid_field`
- `controls.unknown_control`
- `controls.invalid_render_target`

After compilation, internal code should trust the prepared control catalog.

## Performance

Controls must not allocate on every draw call.

Requirements:

- `ui.controls.get(name)` caches refs per module UI phase object.
- `runtime.controls.get(name)` caches refs per module runtime object.
- control refs cache generated field refs.
- `ui.draw.control(...)` does not build option tables internally.
- named views use `ui.draw.control(control, viewName, ...)` so templates can
  receive explicit positional arguments instead of draw-time option blobs.
- template authors should keep static opts and option lists outside draw loops.

The private alias check remains on author data facades only. Control adapters
use trusted internal state directly, so rendering controls should not pay a
private-alias rejection cost on every field access.

## Tables And Hashes

Controls may compile to table storage when the control remains a leaf and
exposes semantic methods instead of raw table internals.

Controls compile to storage, so hash/profile behavior comes from storage:

- generated control storage with `hash = true` participates in hashes
- generated control storage with `hash = false` is excluded

Do not expose generated aliases to solve hash size. If hashes become too long,
shorten the final canonical string through a transport compression layer instead
of adding control-specific bit layouts.

## Guardrails

- Do not make controls mandatory for simple settings.
- Do not turn controls into a retained UI tree.
- Do not put layout in control metadata.
- Do not add built-in Lib templates until repeated first-party modules prove
  the same shape.
- Prefer module-local semantic templates before generalizing into Lib.
- Keep UI files responsible for visible composition.
- Keep game-data hydration in module catalog code; controls should consume
  prepared metadata.
- Stop and revert to widgets if the control abstraction makes the module harder
  to inspect.

## Practical Rule

Use widgets when reading the draw code is enough to understand the setting.

Use controls when understanding the setting otherwise requires jumping between
storage, UI, runtime logic, options, labels, and generated aliases.
