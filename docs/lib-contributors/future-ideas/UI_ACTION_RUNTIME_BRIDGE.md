# UI Action Runtime Bridge

Contributor note. The action-handler part of this design is implemented; the
related cache shape is still open.

## Problem

Draw callbacks currently receive:

```lua
drawTab(draw, state, actions, services)
```

`actions` stages transient UI intent during draw. Pending action handlers run
after draw and before staged state flush.

Action handlers intentionally receive the module `host` instead of draw
`services`, because some UI actions are commands that intentionally cross from
UI into runtime behavior.

Example:

- UI button starts recording the next `N` game events.
- Runtime hooks consume and update recording progress as events happen.
- Persistent cache is the natural runtime-owned state for this marker.

That flow needs a bridge from draw intent to runtime capability access.

## Action Model

Treat draw actions as a UI-to-runtime command bridge.

Handler shape:

```lua
actions = {
    StartRecording = function(host, state, value)
        -- host: runtime capability authority
        -- state: staged draw data, useful for command parameters
        -- value: staged action payload
    end,
}
```

Execution order remains:

```text
draw callback runs
pending action handlers run
staged state flushes to config
onSettingsCommitted(host, store, commit) runs
```

## Semantics

- Draw code stages intent; it should not perform runtime side effects directly.
- Action handlers may use `host` for runtime side effects.
- Action handlers may read or write `state` before the normal flush.
- Action handlers receive staged `value` payloads from widgets or custom draw
  code.
- If command logic needs committed storage after flush, use
  `onSettingsCommitted(host, store, commit)` instead.
- `services` should not be passed to action handlers. Services is a draw-safe
  surface, while actions are command execution.

## Example

```lua
local function drawTab(draw, state, actions)
    draw.widgets.button("Start Recording", {
        action = actions.get("StartRecording"),
        value = {
            count = state.read("RecordingCount"),
        },
    })
end

local actions = {
    StartRecording = function(_, state, value)
        local count = value and value.count or state.read("RecordingCount")
        -- Future bridge would need an explicit runtime cache writer here.
    end,
}
```

Runtime hooks can then consume and update the persistent cache marker.

## Why Host Belongs Here

`host` is the module's runtime capability authority. Giving action handlers
`host` makes the side-effect boundary explicit:

```text
draw: render and stage intent
actions: execute UI-triggered runtime command
runtime hooks: continue runtime state machine
```

This is cleaner than routing all such commands through `onSettingsCommitted`
only, because actions can read staged UI state before flush and execute commands
that are not necessarily settings commits.

## Cache Relationship

This design makes the recording-style scenario realizable with persistent
cache:

```text
UI stages StartRecording
action handler writes persistent runtime marker through host
runtime hook updates marker after each game event
UI can later read a sanctioned draw-safe projection
```

The broader cache-access shape is still under discussion. In particular:

- persistent cache should not become directly draw-writable
- current-run cache should remain runtime/logic scratch state
- shared cache remains the likely draw-safe read projection
- future cache declarations may move cache refs under data access objects
- `services.cache.*` was a migration bridge, not a permanent data-access
  surface; draw-safe cache refs should come from `state.cache`

Do not treat this note as a full cache-v2 design.

## Completed Shape

- Draw action handler invocation is `(host, state, value)`.
- `services` is not passed to action handlers.
- `commit.actions` is unchanged; it remains the post-flush observation path.
