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
- Controls should not declare status or status intents. UI composition can pass
  status or action refs into control views when needed.

## Design Questions

- Is `ui.status.get("Name"):trigger("intent")` the right author-facing shape,
  or should intent refs stay under `ui.actions`?
- Should an intent callback receive the status ref directly, or just
  `host, runtime, payload` like actions do today?
- How should multiple intents on one status value be named in diagnostics and
  tests?
- Would this actually reduce real module boilerplate, or just move the same
  concept under a cleverer namespace?
