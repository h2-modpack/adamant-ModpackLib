# Draw Lifecycle

Draw is the UI staging lane for a module. Runtime callbacks read committed
state; draw callbacks edit staged state and queue intent that Lib commits later.

This split keeps UI code immediate-mode friendly without making runtime/gameplay
code depend on half-edited UI values.

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
| `ui.data.runtimeOwned` | read runtime-owned storage |
| `ui.actions` | stage one-shot commands and shared emits |
| `ui.shared` | read shared data |
| `ui.controls` | get draw refs for declared controls |

Runtime callbacks receive `(host, runtime)` instead. They read committed data
through `runtime.data`, write runtime-owned storage through
`runtime.data.runtimeOwned`, and read controls through `runtime.controls`.

## One Draw Commit Cycle

Framework owns the draw and commit timing. For a framework-rendered module, the
normal cycle is:

1. Framework calls the module draw callback.
2. Draw code renders immediate UI.
3. Draw code stages storage edits through `ui.data`.
4. Draw code stages commands through `ui.actions.trigger(...)`.
5. Draw code may queue shared events through `ui.actions.emit(...)`.
6. The draw callback returns. Shared events are not delivered here.
7. Framework asks the live module to commit if it has staged work.
8. Lib runs staged action handlers.
9. Lib delivers queued shared events.
10. Lib flushes dirty staged storage to config.
11. Lib clears the live staged action/shared-event buffer.
12. Lib applies/reverts mutation state if committed settings changed.
13. Lib runs `module.onCommit(...)` observers with the captured action snapshot.

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

## Runtime-Owned Storage

Use `mode = "runtime"` storage for runtime-written/UI-read state:

```lua
module.data.define({
    {
        type = "bool",
        alias = "RecordingReady",
        mode = "runtime",
        persist = true,
        hash = false,
        default = false,
    },
})
```

Runtime writes:

```lua
runtime.data.runtimeOwned.set("RecordingReady", true)
```

Draw reads:

```lua
local ready = ui.data.runtimeOwned.read("RecordingReady")
```

This is the explicit runtime-owned lane. Do not model this as a normal staged
UI setting when gameplay code owns the value.

## Actions

Use actions when a draw interaction should run command logic at commit:

```lua
module.actions.define({
    StartRecording = function(host, runtime, value)
        runtime.data.runtimeOwned.set("RecordingReady", value == true)
    end,
})

local function drawTab(host, ui)
    ui.draw.widgets.button("Start", {
        action = ui.actions.get("StartRecording"),
        value = true,
    })
end
```

Action handlers run during commit after draw returns and before staged storage
flush. They receive `(host, runtime, value)`.

Actions are one-shot intent, not storage. If a value needs to survive across
frames, declare storage for that value.

## Shared Events

Draw code can queue shared events:

```lua
ui.actions.emit("run-director.route-state", "routeChanged", {
    route = ui.data.read("Route"),
})
```

The event is staged during draw and delivered during commit after action
handlers. Listeners run outside the draw callback and should use their runtime
context or module-local dependencies, not captured draw refs.

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

- reset buttons
- import/export/apply commands
- draw interactions that should write runtime-owned storage
- shared events emitted from draw interactions

Use `runtime.data` for:

- hook/mutation/overlay logic that reads committed settings
- game behavior decisions
- derived runtime helpers that should not observe half-edited UI state

Use `runtime.data.runtimeOwned` plus `ui.data.runtimeOwned` for:

- gameplay/runtime-written state shown in UI
- runtime counters, availability flags, and status values
- values that should not look like normal UI-owned settings

## Common Mistakes

- Do not capture `ui.data`, `ui.actions`, or draw refs and use them from runtime
  callbacks.
- Do not expect runtime hooks to see staged UI edits before commit.
- Do not use actions as settings.
- Do not emit shared events directly from draw with `host.shared.emit(...)`; use
  `ui.actions.emit(...)` so delivery happens during commit.
- Do not use normal staged storage for runtime-owned values.
