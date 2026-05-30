# UI Control Ergonomics

Future design note for deciding when module UI should use raw ImGui, widgets,
or declared controls.

This is not an implementation spec. It records module-organization guidance for
future control-heavy work.

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

- private storage/action fields
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
