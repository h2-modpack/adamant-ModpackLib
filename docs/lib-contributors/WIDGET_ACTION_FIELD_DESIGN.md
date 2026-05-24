# Widget And Action Design

This note records the draw-widget and draw-action cleanup. It also records the
discarded storage-backed field-editor direction so future work does not repeat
the same declarative-UI detour without a deliberate redesign.

## Goals

- Field widgets edit declared storage fields.
- Command widgets stage declared actions.
- Draw code composes layout and placement directly.
- Raw ImGui remains available for custom imperative UI, but first-party widget
  helpers should stay inside the storage/action model.
- Storage remains a data schema, not a UI projection system.

## Current Shape

Field widgets already follow the desired direction:

```lua
draw.widgets.dropdown(state.get("MaxGodsPerRun"), opts)
draw.widgets.checkbox(state.get("Enabled"), opts)
```

They receive a `StorageField`, mutate staged draw state, and optionally stage
`opts.action`.

Buttons used to be the exception. `draw.widgets.button(...)` and
`draw.widgets.confirmButton(...)` supported `onClick` and `onConfirm`, which
ran arbitrary code directly during draw. That callback path was both a
conceptual bypass around draw actions and a recurring source of per-frame
closure/option-table allocation.

Draw actions currently exist as lazy draw-phase refs:

```lua
local action = actions.get("resetAll")
action:stage(true)
```

The action buffer is captured during host flush and exposed to commit callbacks
as `commit.actions`, but action keys are not declared up front and no handler
is executed before staged state is flushed.

## Declared Actions

Module definitions should gain an optional `actions` table, parallel to
`storage`:

```lua
lib.createModule({
    storage = data.buildStorage(),

    actions = {
        resetAll = function(state, services)
            state.resetAll()
        end,

        banAll = function(state, services, banPoolKey)
            uiActions.BanAllGodBans(banPoolKey, state, services)
        end,
    },

    drawTab = ui.drawTab,
})
```

Action handler signature:

```lua
fun(state: DrawState, services: DrawServices, value: any)
```

Do not pass `draw`, `imgui`, `actions`, or a broad context object to action
handlers. These callbacks are post-draw UI commands: they may mutate staged
state and use draw-safe services, but they do not render and they do not stage
more actions.

Rules:

- `prepareDefinition(...)` validates action keys and callback shape.
- `actions.get(key)` rejects undeclared keys.
- Staged actions execute after the draw callback returns and before staged
  state is flushed.
- Execution order is deterministic prepared order. Because Lua map literals do
  not preserve source order, prepared action keys are sorted by key.
- `nil` staged value means absent.
- `commit.actions` continues to expose the captured action snapshot to commit
  observers after execution.

## Button Widgets

Buttons should become action-only command widgets.

```lua
draw.widgets.confirmButton("reset", "Reset All", {
    confirmLabel = "Confirm Reset All",
    action = actions.get("resetAll"),
})
```

```lua
draw.widgets.button("Ban All", {
    id = "ban_all_" .. banPoolKey,
    action = actions.get("banAll"),
    value = banPoolKey,
})
```

Public callback fields have been removed:

- `ButtonOpts.onClick`
- `ConfirmButtonOpts.onConfirm`

If a button has no action, it may still return the clicked/confirmed boolean
for simple local control flow, but it should not run a first-party side effect.
Custom imperative button behavior belongs in explicit raw ImGui code:

```lua
if draw.imgui.Button("Do Custom Thing") then
    -- caller owns the imperative side effect
end
```

## Rejected: Storage UI Metadata

We explored letting storage nodes declare default editor metadata:

```lua
{
    type = "int",
    alias = "MaxGodsPerRun",
    default = 4,
    min = 1,
    max = 9,
    ui = {
        widget = "dropdown",
        label = "Max Gods Per Run",
        values = { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        controlWidth = 60,
        controlGap = 20,
    },
}
```

The idea was attractive for static settings, but it creates the wrong pressure
for this project. It teaches authors that storage knows how it is drawn, while
most module UI is immediate-mode projection over current game state, filters,
cross-module cache, catalog indexes, and local layout.

Static declarations worked for simple form-like settings, but dynamic controls
quickly needed more than storage can honestly know:

- option providers
- filtered value sets
- display/color projections
- slot-specific validity
- cross-module availability
- normalization rules
- composite field relationships

Adding those concepts would turn storage from durable state into a view-model
system. That may be a valid architecture for a form-heavy application, but it is
not the current Lib contract.

Decision:

- Do not add storage `ui` metadata.
- Do not add `draw.field(...)`.
- Do not reorganize module catalogs or storage just to make declarative field
  rendering fit.
- Authors should cache widget option tables near module UI code and draw with
  `draw.widgets.*` or `draw.imgui` directly.

## Draw Language

The draw surface intentionally has one explicit widget language:

```lua
draw.widgets.dropdown(state.get("Mode"), MODE_DROPDOWN_OPTS)
draw.widgets.checkbox(state.get("Enabled"), ENABLED_OPTS)
draw.widgets.confirmButton("reset", "Reset All", {
    confirmLabel = "Confirm Reset All",
    action = actions.get("resetAll"),
})
```

Use raw ImGui when the UI is inherently custom or when the caller owns an
imperative local side effect:

```lua
if draw.imgui.Button("Do Custom Thing") then
    -- caller owns this imperative local behavior
end
```

This keeps the projection local to draw code. Storage fields remain explicit
data refs passed into widgets.

## Option Allocation

Immediate-mode draw code should avoid allocating option tables every frame.
Preferred patterns:

- declare static option tables at module scope or in `bind(...)`
- cache derived option tables by stable key
- mutate cached draw-local fields such as `opts.values` only when that object is
  intentionally reused for the active draw path
- use raw ImGui for one-off local controls that do not benefit from widget
  abstraction

Lib should not solve per-frame allocation by moving dynamic projection into
storage declarations.

## Migration Order

1. Add module `actions` definition validation and deterministic storage.
2. Execute declared staged actions after draw and before flush.
3. Make `actions.get(key)` reject undeclared keys.
4. Port module button callbacks to declared actions.
5. Remove `onClick` and `onConfirm` from Lib button widgets, defs, and docs. Done.
6. Keep all field rendering on explicit `draw.widgets.*` calls.
7. Keep dynamic and custom UI on `draw.widgets.*` or `draw.imgui`.

The storage-backed field-editor migration was prototyped and discarded before
publication. The retained API direction is: storage is data, actions are
post-draw intent, and draw code owns UI projection.
