# Widget, Action, And Field Editor Design

This note describes the planned cleanup for draw widgets, draw actions, and
storage-backed default field editors.

## Goals

- Field widgets edit declared storage fields.
- Command widgets stage declared actions.
- Storage schema may optionally declare a default editor for a field.
- Draw code composes layout and placement without recreating widget option
  tables or running arbitrary side effects.
- Raw ImGui remains available for custom imperative UI, but first-party widget
  helpers should stay inside the storage/action model.

## Current Shape

Field widgets already follow the desired direction:

```lua
draw.widgets.dropdown(state.get("MaxGodsPerRun"), opts)
draw.widgets.checkbox(state.get("Enabled"), opts)
```

They receive a `StorageField`, mutate staged draw state, and optionally stage
`opts.action`.

Buttons are the exception. `draw.widgets.button(...)` and
`draw.widgets.confirmButton(...)` still support `onClick` and `onConfirm`,
which run arbitrary code directly during draw. That callback path is both a
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
- Execution order is deterministic declaration order.
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

Public callback fields should be removed:

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

## Storage UI Metadata

Storage nodes may optionally declare default editor metadata:

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

`ui` is editor metadata only. It should describe how to edit the field, not
where it appears, what panel owns it, or what arbitrary side effects should run.

Allowed default editors:

- `checkbox`
- `inputText`
- `dropdown`
- `radio`
- `stepper`
- `packedCheckboxList`
- `packedDropdown`
- `packedRadio`

Initial support should not include callbacks or buttons inside storage `ui`.
Table roots should not get a root-level editor at first; table row fields may
carry `ui` metadata through their row schema.

## draw.field

Add a draw helper for default field editors:

```lua
draw.field(state.get("MaxGodsPerRun"))
draw.field(rows:get(index, "Bans"))
```

Behavior:

- Requires draw phase.
- Requires a `StorageField`.
- Reads prepared `field:schema().ui`.
- Dispatches to the matching widget helper.
- Returns the widget changed boolean.
- Fails clearly if the field has no default editor.

Optional shallow overrides may be supported for local placement tweaks:

```lua
draw.field(state.get("MaxGodsPerRun"), {
    label = "",
})
```

Overrides should be the exception. The preferred fast path is prepared storage
UI metadata with no per-frame option allocation.

## Migration Order

1. Add module `actions` definition validation and deterministic storage.
2. Execute declared staged actions after draw and before flush.
3. Make `actions.get(key)` reject undeclared keys.
4. Port module button callbacks to declared actions.
5. Remove `onClick` and `onConfirm` from Lib button widgets, defs, and docs.
6. Add storage `ui` validation and preparation at the storage-schema boundary.
7. Add `draw.field(field, overrides?)`.
8. Move obvious static field-widget opts from modules into storage `ui`.
9. Keep complex or dynamic UI on `draw.widgets.*`.

This preserves immediate-mode composition while giving module authors a
low-boilerplate path: define data once, optionally describe its default editor
there, then place it with `draw.field(...)`.
