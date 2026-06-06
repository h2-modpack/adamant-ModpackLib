# Runtime Status

This note records the target shape for replacing the public `runtimeOwned`
storage lane with a clearer `status` capability. It is an audit target before
implementation, not a committed API yet.

## Current Pressure

The current public primitives are mechanically correct but conceptually noisy:

```lua
ui.actions.trigger("StartRecording", payload)
runtime.data.runtimeOwned.write("RecordingReady", true)
ui.data.runtimeOwned.read("RecordingReady")
```

`actions` are UI intent crossing into runtime after UI commit. `runtimeOwned`
storage is runtime-authored state that UI can read. Both concepts are useful,
but putting runtime-authored state under `data.runtimeOwned` makes it look like
a special case of normal configuration storage.

The LiveSplit module is the concrete consumer that keeps this lane load-bearing:
it stores `RecordingReady` as `mode = "runtime"`, `persist = true`, and
`hash = false` so recording readiness can survive reloads. The capability should
be reframed, not removed.

## Capability Boundaries

Use one public concept for each direction:

```text
data    = UI-authored configuration/state that runtime reads
status  = runtime-authored state that UI reads
actions = UI intent executed by runtime after commit
cache   = runtime-internal working memory
shared  = cross-module state/events
```

`status` is not normal storage with a `mode` flag. It is its own module-level
capability because it has the opposite ownership direction from `data`.

## Target Declaration

Status declarations should move out of `module.data.define(...)`:

```lua
module.status.define({
    RecordingReady = {
        type = "bool",
        default = false,
        persist = true,
    },

    InfoFeed = {
        type = "table",
        default = {},
        persist = false,
    },
})
```

Rules:

- No `mode = "runtime"` in author-facing declarations.
- No `hash` option. Status is never part of the run hash.
- `persist` remains available because some runtime-authored state, such as
  LiveSplit recording readiness, intentionally survives reloads.
- New status declarations should not inherit storage's broad defaults blindly.
  Prefer explicit persistence in docs/examples so authors choose the lifetime.
- Scalar, packed, bounded, and table shapes should reuse the existing storage
  schema vocabulary where it fits.
- Tables and collections are supported through the existing handle/snapshot
  model. Status is for bounded runtime-to-UI state, including small logs or
  recent event lists.

## Target Access

Expose phase-specific facades over one backing value:

```lua
runtime.status.read("RecordingReady")
runtime.status.write("RecordingReady", true)
runtime.status.reset("RecordingReady")
runtime.status.get("InfoFeed"):append(row)

ui.status.read("RecordingReady")
ui.status.get("InfoFeed"):snapshot()
```

Runtime owns writes and resets. UI gets read-only access. This mirrors the
existing `runtime.data.runtimeOwned` and `ui.data.runtimeOwned` mechanics, but
the author-facing namespace says what the lane means instead of how it is
implemented.

Implementation can initially compile `module.status.define(...)` into the same
internal runtime-owned persistent/staged state machinery. The public name should
be `status`; the backend can be renamed later if that cleanup is worthwhile.

## Public Surface Reduction

The target is not to add `status` beside the current runtime-owned public API.
The target is to narrow the author-facing surface:

```text
runtime.data.runtimeOwned -> runtime.status
ui.data.runtimeOwned      -> ui.status
mode = "runtime"          -> module.status.define(...)
```

After migration, `data` should only expose UI-authored storage. Runtime-authored
state should not appear as a sub-namespace of `data`, and normal storage
declarations should not accept `mode = "runtime"` as the public way to define
that lane.

The existing runtime-owned backend can remain as an implementation detail while
the public API is narrowed. Compatibility shims, if used, should be temporary
and should not be documented as the primary module-author path.

## Actions Stay Separate

Do not bundle actions into status in the first implementation.

LiveSplit currently has three commands around one runtime marker:

```lua
recordingStart
recordingStop
recordingClear
```

That shape argues against a single `status:trigger(...)` API for now. Actions
remain the command lane:

```lua
ui.actions.trigger("recordingStart")
```

Status remains the runtime-authored state lane:

```lua
runtime.status.write("RecordingReady", true)
```

If multiple modules later repeat the same action/status pairing pattern, a
first-class bundled design can be added. Until then, bundling would overfit the
API around recording.

## Execution Model

Do not introduce a runtime pull/consume model.

If a future bundled status command exists, it should still use the existing
post-commit action buffer:

```text
ui trigger -> existing action buffer -> runtime callback -> status write
```

Avoid an API such as `runtime.tasks.get("Recording"):consume()` as the default
shape. That would create a second execution model where runtime pulls pending
intent on its own schedule.

## Status Vs Cache

Status is the public runtime-to-UI read surface. Cache remains runtime-internal
working memory.

Use status for:

- runtime counters, flags, and status strings
- bounded collections such as small logs or recent event snapshots
- persisted runtime intent/state that should survive reloads

Use cache for:

- runtime-only scratch data
- large or lifecycle-bound working sets the UI does not read directly

If a future UI needs a large runtime-produced buffer, prefer adding a
buffer-backed status field type over exposing cache as a second UI-readable
lane. That keeps the public model contract-first.

## Relationship To Controls

Controls remain configuration composites. They should not declare status fields
or command actions.

If a control needs to display runtime status, UI composition should read the
module-level status and pass it to the control view. If many controls start
hand-threading action refs or status refs through bespoke option shapes, that is
evidence for a later first-class binding design.

## Build Order

1. Add `module.status.define(...)`, `runtime.status`, and `ui.status` as the
   public names for runtime-authored state.
2. Compile status declarations through the existing runtime-owned backend.
3. Keep `runtimeOwned` as a compatibility/internal term only as long as needed.
4. Migrate docs and modules away from `mode = "runtime"` and
   `data.runtimeOwned`.
5. Keep actions command-only.
6. Revisit action/status bundling only after real modules show repeated
   hand-wired pairings.
