# Runtime Status Intents

`status` is implemented as the runtime-authored state lane:

```text
runtime.status = runtime writes state
ui.status      = UI reads state
ui.actions     = UI sends one-shot runtime intent
```

This note keeps the only remaining open design question: whether some status
entries should also be able to declare their own UI-to-runtime intents.

## Pressure

Some features are naturally a pair:

- UI sends an intent such as `startRecording`.
- Runtime performs work and updates status such as `RecordingReady`.
- UI reads that status on later frames.

Today that is expressed as two module-level declarations:

```lua
module.actions.define({
    recordingStart = function(host, runtime, payload)
        runtime.status.write("RecordingReady", false)
        -- start runtime work
    end,
})

module.status.define({
    RecordingReady = {
        type = "bool",
        default = false,
        persist = true,
    },
})
```

That is mechanically clean, but repeated action/status pairings may become
ceremony if more modules follow this pattern.

This pairing should stay module-level. Controls are composite configuration
objects; they can render or read status supplied by the surrounding UI, but
they should not own runtime coordination state.

## Possible Direction

If this becomes common enough, status could grow an optional intent section.
The status state remains the primary concept; the intent is attached because it
advances or requests work for that state.

Sketch only:

```lua
module.status.define({
    RecordingReady = {
        type = "bool",
        default = false,
        persist = true,
        intents = {
            start = function(host, runtime, payload)
                runtime.status.write("RecordingReady", false)
                -- start runtime work
            end,
            stop = function(host, runtime)
                -- stop runtime work
            end,
        },
    },
})

ui.status.get("RecordingReady"):trigger("start", payload)
```

The exact API should wait for another real module that repeats this shape.

## Rules

- Status state is mandatory. Intent-only entries remain normal actions.
- Intents execute through the existing post-commit action buffer.
- Do not add a runtime pull/consume model.
- Status remains runtime-authored and UI-readable.
- Actions remain the right tool for pure one-shot commands with no UI-readable
  runtime state.
- Controls should not declare status or status intents. UI composition can read
  or retrieve module-level status/action refs and pass them into control views
  as explicit view arguments.

## Controls Boundary

Controls remain leaf configuration objects backed by private generated storage.
That keeps the compiler single-purpose: it lowers control fields to normal
config storage and builds UI/runtime refs over that storage.

Status is different. It is runtime-authored coordination state for the module's
behavior loop. A control may display status, but the status declaration belongs
to the module:

```lua
local recording = ui.status.read("RecordingReady")
ui.draw.control(ui.controls.get("Recorder"), "default", recording)
```

If status intents are added later, controls should consume them the same way:
the UI composition layer retrieves the module-level ref and passes it to the
control view. The control remains a consumer of coordination lanes, not their
owner.

## Design Questions

- Is `ui.status.get("Name"):trigger("intent")` the right author-facing shape,
  or should intent refs stay under `ui.actions`?
- Should an intent callback receive the status ref directly, or just
  `host, runtime, payload` like actions do today?
- How should multiple intents on one status value be named in diagnostics and
  tests?
- Would this actually reduce real module boilerplate, or just move the same
  concept under a cleverer namespace?
