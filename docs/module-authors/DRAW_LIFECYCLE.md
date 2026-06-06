# Draw Lifecycle

Draw is the UI staging lane for a module. Runtime callbacks read committed
state; draw callbacks edit staged state and queue intent that Lib commits later.

This split keeps UI code immediate-mode friendly without making runtime/gameplay
code depend on half-edited UI values.

Use [DATA_LANES.md](DATA_LANES.md) to decide which state lane owns a value.

## Callback Shape

Draw callbacks receive:

```lua
local function drawTab(host, ui)
    -- render and stage edits
end
```

`host` is the callback-safe module host projection. Use it for small unphased
module operations such as logging and enabled-state checks.

`ui` is the draw context:

| Surface | Use it for |
| --- | --- |
| `ui.draw` | ImGui, widgets, nav, and control drawing |
| `ui.data` | staged UI storage reads/writes |
| `ui.status` | read runtime-authored status |
| `ui.actions` | stage one-shot runtime actions and shared emits |
| `ui.shared` | read shared data |
| `ui.controls` | get draw refs for declared controls |
| `ui.resetAll` | queue a full module reset for commit |

Runtime callbacks receive `(host, runtime)` instead. They read committed data
through `runtime.data`, write runtime-authored status through `runtime.status`,
and read controls through `runtime.controls`.

## One Draw Commit Cycle

Framework owns the draw and commit timing. For a framework-rendered module, the
normal cycle is:

1. Framework calls the module draw callback.
2. Draw code renders immediate UI.
3. Draw code stages storage edits through `ui.data`.
4. Draw code stages runtime actions through `ui.actions.trigger(...)`.
5. Draw code may queue shared events through `ui.actions.emit(...)`.
6. Draw code may reset staged module state and queue status reset through `ui.resetAll(...)`.
7. The draw callback returns. Shared events are not delivered here.
8. Framework asks the live module to commit if it has staged work.
9. Lib flushes dirty staged storage to config.
10. Lib applies/reverts mutation state if committed UI-owned settings changed.
11. Lib runs staged action handlers against committed runtime data.
12. Lib applies queued status reset requests.
13. Lib delivers queued shared events.
14. Lib clears the live staged action/shared-event buffer.
15. Lib runs `module.onCommit(...)` observers with the captured action snapshot.

The important boundary: runtime/gameplay code only sees committed settings.
Values written through `ui.data` become runtime-visible after commit.

## Staged Storage

Use `ui.data` for UI-owned settings:

```lua
ui.draw.widgets.checkbox(ui.data.get("FeatureEnabled"), {
    label = "Enable Feature",
})
```

During the draw callback, `ui.data.read("FeatureEnabled")` reads the staged
value. Runtime callbacks continue to read the previous committed value until the
commit step flushes the edit.

Use `persist = false, hash = false` storage for UI-only view state such as
selected tabs and filters. It still lives in the staged UI lane, but it does not
persist or participate in profile hashes.

## Status

Use status for runtime-written/UI-read state:

```lua
module.status.define({
    RecordingReady = {
        type = "bool",
        persist = true,
        default = false,
    },
})
```

Runtime writes:

```lua
runtime.status.write("RecordingReady", true)
```

Draw reads:

```lua
local ready = ui.status.read("RecordingReady")
```

This is the explicit runtime-authored lane. Do not model this as a normal
staged UI setting when gameplay code owns the value. Status values are not
mutation inputs; if a value should affect `module.mutation.patch(...)`, model
it as normal UI-owned storage instead.

## Reset

Use `ui.resetAll(opts?)` when a draw interaction should restore the module to
defaults:

```lua
if ui.draw.widgets.confirmButton("ResetModule", "Reset To Defaults") then
    ui.resetAll()
end
```

This resets UI-owned, transient, and control-backed storage during draw, cancels
pending draw-staged actions/shared emits from the same frame, then queues status
storage to reset during the same commit. The status reset is not exposed as a
public `commit.actions` entry.

## Actions

Use actions when a draw interaction should run runtime side-effect logic at commit:

```lua
module.actions.define({
    StartRecording = function(host, runtime, value)
        runtime.status.write("RecordingReady", value == true)
    end,
})

local function drawTab(host, ui)
    ui.draw.widgets.button("Start", {
        action = ui.actions.get("StartRecording"),
        value = true,
    })
end
```

Action handlers run during commit after staged storage flushes and mutation sync
succeeds. They receive `(host, runtime, value)`, and `runtime.data` reads the
values just committed by the draw that staged the action.

Actions may update status, but they are not a second settings lane. Mutation
sync is driven by committed UI-owned storage changes, not by status writes.

Actions are one-shot intent, not storage. If a value needs to survive across
frames, declare storage for that value.

## Shared Events

Draw code can queue shared events:

```lua
ui.actions.emit("run-director.route-state", "routeChanged", {
    route = ui.data.read("Route"),
})
```

The event is staged during draw and delivered during commit after mutation sync,
action handlers, and queued status resets. Listeners run outside the draw
callback and should use their runtime context or module-local dependencies, not
captured draw refs.

This keeps shared events from observing partially rendered UI state while still
letting draw interactions emit module-to-module signals.

## Commit Observers

Use `module.onCommit(...)` for post-commit observation:

```lua
module.onCommit(function(host, runtime, commit)
    if commit.actions.get("StartRecording"):has() then
        host.logIf("recording command committed")
    end

    if commit.hadConfigChanges() then
        -- Rebuild derived runtime state from runtime.data.
    end
end)
```

`onCommit` runs after staged storage has flushed and mutation state has synced.
Use it when code needs to observe the final committed module state.

## Common Patterns

Use `ui.data` for:

- checkboxes, dropdowns, sliders, and tables edited by UI
- selected tabs and filters when the UI owns the value
- control draw refs and widget data refs

Use `ui.actions` for:

- import/export/apply commands
- draw interactions that should write status
- shared events emitted from draw interactions

Use `runtime.data` for:

- hook/mutation/overlay logic that reads committed settings
- game behavior decisions
- derived runtime helpers that should not observe half-edited UI state

Use `runtime.status` plus `ui.status` for:

- gameplay/runtime-written state shown in UI
- runtime counters, availability flags, and status values
- values that should not look like normal UI-owned settings

## Common Mistakes

- Do not capture `ui.data`, `ui.actions`, or draw refs and use them from runtime
  callbacks.
- Do not expect runtime hooks to see staged UI edits before commit.
- Do not use actions as settings.
- Do not use status action writes as mutation inputs.
- Do not emit shared events directly from draw with `host.shared.emit(...)`; use
  `ui.actions.emit(...)` so delivery happens during commit.
- Do not use normal staged storage for runtime-authored status values.
