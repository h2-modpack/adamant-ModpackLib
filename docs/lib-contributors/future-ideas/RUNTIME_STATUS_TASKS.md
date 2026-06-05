# Runtime Status Tasks

This note records an open direction for simplifying UI/runtime coordination
after the controls cleanup settles. It is not an accepted API plan yet.

## Current Pressure

The current public primitives are mechanically clear but conceptually split:

```lua
ui.actions.trigger("StartRecording", payload)
runtime.data.runtimeOwned.write("RecordingActive", true)
ui.data.runtimeOwned.read("RecordingActive")
```

`actions` are UI intent crossing into runtime after UI commit.
`runtimeOwned` storage is runtime-published state that UI can read. These two
often participate in the same feature loop:

```text
UI intent -> runtime work -> UI-readable runtime status
```

The split is especially visible for recording-like workflows. The UI triggers a
recording action, runtime observes or completes the work, and UI reads status to
show whether recording is still active.

## Working Boundary

Keep the distinction between commands and state-bearing runtime workflows:

```text
actions = intent only, no readable runtime state
status/task = runtime-published state required, optional UI trigger
```

The state requirement is important. If a future task concept allows
intent-only declarations, it overlaps with actions and becomes another broad
UI/runtime bucket. A clean decision tree is:

```text
Does UI need to read runtime status after this?
  yes -> status/task
  no  -> action
```

Examples:

- `ResetAll`, `ClearSession`, `RefreshNow`: actions.
- `Recording`, `RuntimeWarning`, `ObservedBiome`: possible state-bearing
  status/tasks.

## Execution Model

Do not introduce a runtime pull/consume model unless there is strong evidence
that the existing action buffer cannot express the workflow.

If a future status/task has a UI trigger, its intent should be implemented using
the same post-commit action execution path that already exists:

```text
ui trigger -> existing action buffer -> runtime callback -> status write
```

Avoid an API such as `runtime.tasks.get("Recording"):consume()` as the default
shape. That would create a second execution model where runtime pulls pending
intent on its own schedule, increasing lifecycle complexity without a proven
need.

## Naming

`task` is only a placeholder. If state is mandatory and intent is optional, the
name should be checked against state-only examples, not only recording.

Possible names to revisit:

- `status`
- `runtimeStatus`
- `monitor`
- `task`
- `channel`

Names such as `signal` may conflict with shared event terminology.

## Relationship To Controls

Controls should remain configuration composites. They should not declare
runtime-owned coordination state or command actions.

If a control needs to display runtime status, UI composition should read the
module-level status and pass it to the control view. If many controls start
hand-threading action refs or status refs through bespoke option shapes, that is
evidence for a first-class status/task binding design.

## Build Order

Separate the subtractive and additive decisions:

1. Keep runtime-owned state narrow and module-level.
2. Avoid presenting runtime-owned state as normal control storage.
3. Keep actions command-only.
4. Defer a first-class status/task abstraction until multiple real workflows
   need the same paired command/status shape.

This avoids committing to an abstraction shaped around a single recording-style
use case while preserving the option to later hide `runtimeOwned` behind a more
coherent public status/task surface.
