# Managed State

Managed state gives each module validated storage, committed runtime data, draw
state, draw actions, and hash/profile participation.

## Surfaces

| Surface | Use it for | Phase |
| --- | --- | --- |
| `runtime.data` | committed setting reads | runtime callbacks |
| `runtime.data.runtimeOwned` | read/write `mode = "runtime"` storage | runtime callbacks |
| `ui.data` | staged UI reads/writes | draw callbacks |
| `ui.data.runtimeOwned` | read `mode = "runtime"` storage | draw callbacks |
| `ui.actions` | one-shot draw intent | draw callbacks |
| `ui.controls` | declared composite control refs | draw callbacks |
| `ui.resetAll` | queue a full module reset | draw callbacks |
| `runtime.controls` | declared composite control reads | runtime callbacks |
| `runtime.data.cache` | declared current-run cache | runtime callbacks |

Draw callbacks receive `(host, ui)`. Runtime callbacks receive `(host, runtime)`.
Use [../DRAW_LIFECYCLE.md](../DRAW_LIFECYCLE.md) for the full draw/commit
order.

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
runtime.data.runtimeOwned.write("RecordingReady", true)
```

Draw code reads through the runtime-owned lane:

```lua
local ready = ui.data.runtimeOwned.read("RecordingReady")
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

Table handles use colon syntax. Runtime-owned table roots use the same handle
model:

```lua
runtime.data.runtimeOwned.write("Rows", 1, "Enabled", true)
local enabled = ui.data.runtimeOwned.read("Rows", 1, "Enabled")
local rows = ui.data.runtimeOwned.get("Rows"):snapshots()
```

Use `snapshot(rowIndex)` or `snapshots()` when you need copied table data.

## Reset

Use `ui.resetAll(opts?)` from draw code to reset the whole module:

```lua
if ui.draw.widgets.confirmButton("ResetModule", "Reset To Defaults") then
    ui.resetAll()
end
```

`ui.resetAll(...)` resets UI-owned, transient, and control-backed storage during
draw, then queues `mode = "runtime"` storage to reset during the current commit.
Pass `exclude = { Alias = true }` to skip specific root aliases.

## Packed Values

Use `packedInt` when one numeric root should expose named child aliases.
Packed widgets can write child aliases, and Lib repacks the root.

`packedInt` roots must declare an explicit `width` from 1 to 32. Child
`offset + width` must stay inside the root width. Integer storage bounds and
packed widths are validated during storage preparation so hashes and profile
packing can trust prepared metadata.

## Draw Actions

Actions are declared before activation:

```lua
module.actions.define({
    StartRecording = function(host, runtime, value)
        host.logIf("Starting recording")
        runtime.data.runtimeOwned.write("RecordingReady", value == true)
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

Action handlers run during commit after staged state flush and mutation sync.
They receive:

- `host`: narrow logging/metadata/enabled host projection
- `runtime`: runtime context with committed data, cache, shared, and controls
- `value`: staged action payload

`runtime.data` reads the values just committed by the draw that staged the
action.

Action handlers may update `runtime.data.runtimeOwned`, but runtime-owned state
is not a mutation input. Mutation sync is triggered by committed UI-owned
settings changes; if mutation behavior should change, declare normal UI-owned
storage for that setting.

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
- Do not use draw mutation objects such as `ui.actions` or writable `ui.data`
  refs outside draw callbacks.
- Do not use actions as persistent settings.
