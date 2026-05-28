# Managed State

Managed state gives each module validated storage, committed runtime data, draw
state, draw actions, and hash/profile participation.

## Surfaces

| Surface | Use it for | Phase |
| --- | --- | --- |
| `runtime.data` | committed setting/runtime reads | runtime callbacks |
| `runtime.data.runtime` | writes to `mode = "runtime"` storage | runtime callbacks |
| `ui.data` | staged UI reads/writes | draw callbacks |
| `ui.actions` | one-shot draw intent | draw callbacks |
| `runtime.data.cache` | declared current-run cache | runtime callbacks |

Draw callbacks receive `(host, ui)`. Runtime callbacks receive `(host, runtime)`.

```lua
local function drawTab(host, ui)
    ui.draw.widgets.checkbox(ui.data.get("FeatureEnabled"), {
        label = "Enable Feature",
    })
end

module.hooks.wrap("SomeGameFunction", function(host, runtime, base, ...)
    if host.isEnabled() and runtime.data.read("FeatureEnabled") then
        -- Runtime behavior reads committed state.
    end
    return base(...)
end)
```

## Storage

Declare storage before activation:

```lua
module.data.define({
    { type = "bool", alias = "FeatureEnabled", default = false },
    { type = "string", alias = "Mode", default = "Vanilla", maxLen = 32 },
    { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
})
```

Rules:

- normal roots persist and hash by default
- `persist = false, hash = false` creates draw-only transient UI state
- `hash = false` keeps a persisted value out of hashes/profiles
- `mode = "runtime"` creates runtime-owned storage and cannot hash
- `Enabled` and `DebugMode` are Lib-owned built-ins

## Runtime-Owned Storage

Use runtime-owned storage for values written by gameplay/runtime code and read
by UI:

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

Runtime code writes:

```lua
runtime.data.runtime.set("RecordingReady", true)
```

Draw code reads:

```lua
local ready = ui.data.read("RecordingReady")
```

## Tables

Table storage models compact ordered rows with one shared row schema:

```lua
module.data.define({
    {
        type = "table",
        alias = "Tiers",
        maxRows = 10,
        defaultRows = 1,
        row = {
            { type = "bool", alias = "Enabled", default = true },
            { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
        },
    },
})
```

Draw use:

```lua
local tiers = ui.data.get("Tiers")
tiers:append({ Enabled = true, Limit = 3 })
tiers:write(1, "Limit", 4)
draw.widgets.stepper(tiers:get(1, "Limit"), { label = "Limit" })
```

Runtime read use:

```lua
local limit = runtime.data.read("Tiers", 1, "Limit")
```

Table handles use colon syntax.

## Packed Values

Use `packedInt` when one numeric root should expose named child aliases.
Packed widgets can write child aliases, and Lib repacks the root.

## Draw Actions

Actions are declared before activation:

```lua
module.actions.define({
    StartRecording = function(host, uiData, actionRuntime, value)
        host.logIf("Starting recording")
        actionRuntime.set("RecordingReady", value == true)
    end,
})
```

Draw code stages actions:

```lua
ui.actions.trigger("StartRecording", true)
```

or passes refs to widgets:

```lua
ui.draw.widgets.button("Start", {
    action = ui.actions.get("StartRecording"),
    value = true,
})
```

Action handlers run after the draw callback and before staged state flush. They
receive:

- `host`: narrow logging/metadata/enabled host projection
- `uiData`: current draw state
- `actionRuntime`: narrow runtime bridge with `read`, `set`, and `clear`
- `value`: staged action payload

## Commit Observer

Use `module.onCommit(...)` to observe committed settings/actions:

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

`commit` exposes:

- `commit.actions.get(actionKey)`
- `commit.actions.hasAny()`
- `commit.hadConfigChanges()`

## Common Mistakes

- Do not read transient aliases from `runtime.data`.
- Do not write raw Chalk config from draw code.
- Do not cache draw-phase objects or refs outside draw callbacks.
- Do not use actions as persistent settings.
