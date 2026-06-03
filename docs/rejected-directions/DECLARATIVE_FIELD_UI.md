# Declarative Field UI

## Context

During the declared draw-action work, we explored storage-backed default field
editors:

```lua
{
    type = "int",
    alias = "MaxGodsPerRun",
    default = 4,
    ui = {
        widget = "dropdown",
        label = "Max Gods Per Run",
        values = { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
    },
}
```

The intended draw call was:

```lua
draw.field(state.get("MaxGodsPerRun"))
```

## What Worked

- Static form-like settings became concise.
- Simple repeated labels and options could live near storage declarations.
- Basic modules with mostly fixed controls looked cleaner.

## What Failed

The model mixed durable storage ownership with immediate-mode UI projection.
Real module UI often depends on current game data, filters, cross-module cache,
catalog indexes, local layout, slot-specific validity, and display/color
projection.

Encoding those concerns in storage would require storage declarations to learn:

- option providers
- filtered value sets
- display and color projections
- slot-specific validity
- cross-module availability
- normalization rules
- composite field relationships

That turns storage from a data schema into a view-model system. It may be valid
for a form-heavy application, but it is the wrong default for this immediate-mode
mod UI.

## Decision

Do not add storage `ui` metadata.

Do not add `draw.field(...)`.

Do not reorganize module catalogs or storage just to make declarative field
rendering fit.

Keep storage as data, actions as commit-time command intent, and draw code as the
owner of UI projection. Authors should cache option tables near module UI code
and render with `draw.widgets.*` or `draw.imgui`.

## Revisit Only If

Revisit only with an explicit view-model or control-declaration layer that is
separate from storage, owns dynamic projection honestly, and does not split the
ordinary draw language for immediate-mode code.
