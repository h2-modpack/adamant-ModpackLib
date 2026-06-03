# UI Action Runtime Bridge

Contributor note. The action-handler part of this design has converged into the
current draw lifecycle. Runtime-owned storage replaced the cache bridge
discussed here, and action handlers now run after staged UI storage flushes.

## Problem

Draw callbacks receive:

```lua
drawTab(host, ui)
```

`ui.actions` stages transient UI intent during draw. Pending action handlers run
during commit after staged state flush and mutation sync, so they read committed
runtime data.

Action handlers intentionally receive the module `host` and runtime context
because some UI actions intentionally cross from UI into runtime behavior.

Example:

- UI button starts recording the next `N` game events.
- Runtime hooks consume and update recording progress as events happen.
- Runtime-owned storage is the natural state for this marker.

That flow needs a bridge from draw intent to runtime capability access.

## Action Model

Treat draw actions as a UI-to-runtime side-effect bridge.

Handler shape:

```lua
actions = {
    StartRecording = function(host, runtime, value)
        -- host: runtime capability authority
        -- runtime: committed runtime data and runtime-owned writers
        -- value: staged action payload
    end,
}
```

Execution order remains:

```text
draw callback runs
staged state flushes to config
pending action handlers run
mutation sync runs
shared events deliver
onCommit(host, runtime, commit) runs
```

## Semantics

- Draw code stages intent; it should not perform runtime side effects directly.
- Action handlers may use `host` for runtime side effects.
- Action handlers read committed runtime data after the normal flush.
- Action handlers receive staged `value` payloads from widgets or custom draw
  code.
- the draw object should not be passed to action handlers; draw is a render
  surface, while actions are side-effect execution.

## Example

```lua
local function drawTab(host, ui)
    ui.draw.widgets.button("Start Recording", {
        action = ui.actions.get("StartRecording"),
        value = {
            count = ui.data.read("RecordingCount"),
        },
    })
end

local actions = {
    StartRecording = function(_, runtime, value)
        local count = value and value.count or runtime.data.read("RecordingCount")
        runtime.data.runtimeOwned.write("RecordingRemaining", count)
    end,
}
```

Runtime hooks can then consume and update the runtime-owned marker.

## Why Host Belongs Here

`host` is the module's runtime capability authority. Giving action handlers
`host` makes the side-effect boundary explicit:

```text
draw: render and stage intent
actions: execute UI-triggered runtime side effect
runtime hooks: continue runtime state machine
```

This is cleaner than routing these through `onCommit` only, because actions
express UI intent explicitly and receive their payload without making commit
observers infer button clicks from storage state.

## Cache Relationship

This design makes the recording-style scenario realizable with runtime-owned
storage:

```text
UI stages StartRecording
commit flushes staged UI storage
action handler writes runtime-owned marker through `runtime.data.runtimeOwned`
runtime hook updates marker after each game event
UI can later read a sanctioned draw-safe projection
```

The broader cache-access shape is still under discussion. In particular:

- runtime-owned storage should not become directly draw-writable
- current-run cache should remain runtime/logic scratch state
- shared data remains the likely draw-safe read projection
- current-run cache remains under `store.cache`
- draw-safe runtime-owned values should come from `ui.data.runtimeOwned`

Do not treat this note as a full cache-v2 design.

## Completed Shape

- Draw action handler invocation is `(host, runtime, value)`.
- `draw` is not passed to action handlers.
- `commit.actions` is unchanged; it remains the post-flush observation path.
