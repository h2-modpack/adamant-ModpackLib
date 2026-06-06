# Data Lanes

ModpackLib has several state surfaces because module data moves in different
directions. Pick the lane by ownership first, then by lifetime.

Use [DRAW_LIFECYCLE.md](DRAW_LIFECYCLE.md) for when these lanes flush during a
draw/commit cycle. Use the capability guides for exact API details.

## Overview

| Lane | Owner | Writes | Reads | Lifetime | Hash | Use For |
| --- | --- | --- | --- | --- | --- | --- |
| `data` | UI/config | `ui.data` | `ui.data`, `runtime.data` | persisted by default | hashed by default | user settings and UI-authored module state |
| transient `data` | UI/session | `ui.data` | `ui.data` | current module session | no | selected tabs, filters, temporary view state |
| `status` | runtime | `runtime.status` | `runtime.status`, `ui.status` | explicit `persist` | no | runtime counters, readiness flags, runtime-to-UI state |
| `cache` | runtime lifecycle | runtime cache APIs | runtime code | lifecycle-bound | no | current-run scratch data and derived runtime worksets |
| `shared.data` | one module | owner module | reader modules | shared subsystem | no | cross-module readable state |
| `shared events` | emitting module | `ui.actions.emit` or `host.shared.emit` | listeners | event delivery only | no | cross-module notifications |
| `actions` | UI intent | `ui.actions` | commit/runtime handlers | one commit | no | buttons and commands that should run after commit |
| `controls` | module template | generated from data refs | UI/runtime control refs | follows inner storage | follows inner storage | reusable UI/data composites |

Controls are not a storage lane by themselves. They are a composition layer over
declared data storage with generated refs and optional draw/runtime methods.

## Decision Tree

Use `data` when UI owns the value and runtime reads it:

```lua
module.data.define({
    { type = "bool", alias = "FeatureEnabled", default = false },
})

ui.draw.widgets.checkbox(ui.data.get("FeatureEnabled"), {
    label = "Feature Enabled",
})

if runtime.data.read("FeatureEnabled") then
    -- runtime behavior
end
```

Use transient `data` when only the UI needs the value:

```lua
module.data.define({
    {
        type = "string",
        alias = "FilterText",
        persist = false,
        hash = false,
        default = "",
        maxLen = 64,
    },
})
```

Use `status` when runtime owns the value and UI displays it:

```lua
module.status.define({
    RecordingReady = {
        type = "bool",
        persist = true,
        default = false,
    },
})

runtime.status.write("RecordingReady", true)
local ready = ui.status.read("RecordingReady")
```

Use `cache` when the value is runtime-only working memory:

```lua
local runCache = runtime.data.cache.currentRun.get("RoutingScratch")
```

Use `shared` when another module needs the value or event:

```lua
module.shared.data.owner("route", {
    id = "run-director.route",
    default = "default",
})
```

Use `actions` when UI sends one-shot intent to runtime:

```lua
module.actions.define({
    StartRecording = function(host, runtime, payload)
        runtime.status.write("RecordingReady", payload == true)
    end,
})

ui.actions.trigger("StartRecording", true)
```

Use `controls` when a repeated domain concept should expose one coherent
UI/runtime object instead of loose fields:

```lua
ui.draw.control(ui.controls.get("RoomMode"))
local mode = runtime.controls.read("RoomMode")
```

## Data

`module.data.define(...)` declares UI-authored storage. Draw code edits staged
values through `ui.data`. Runtime code reads committed values through
`runtime.data`.

Normal roots:

- persist by default
- participate in run hashes/profiles by default
- are the right lane for mutation settings

Do not use `data` for runtime-authored values. If gameplay code writes it and
UI reads it, use `status`.

## Transient Data

Transient data is still UI-owned `data`, but it has no config persistence and
does not participate in hashes:

```lua
{ type = "string", alias = "SelectedTab", persist = false, hash = false, default = "main" }
```

Use it for UI view state that should not survive a reload and should not affect
profiles. Runtime callbacks should not depend on transient UI values.

## Status

`module.status.define(...)` declares runtime-authored state. Runtime callbacks
write it through `runtime.status`; draw callbacks read it through `ui.status`.

Status is useful for:

- recording readiness
- runtime counters
- availability flags
- compact runtime-produced rows or recent-event snapshots

Status must declare `persist` explicitly. Status never participates in hashes.
Status is not a mutation input; use normal `data` for values that should change
mutation plans.

## Cache

Cache is runtime working memory. It exists for values that belong to a game
lifecycle, such as current run state, derived lookup tables, or temporary
runtime bookkeeping.

Use cache when:

- UI does not need direct access
- the value is too operational to be a module setting
- the value is tied to a gameplay lifecycle rather than config lifetime

If UI needs to display a small runtime-authored value, publish that value as
`status` instead of exposing cache as UI-readable state.

## Shared

Shared data and shared events cross module boundaries.

Use shared data when another module needs to read your module's published state.
Use shared events when another module needs to react to a committed event.

Draw code should emit shared events through `ui.actions.emit(...)` so delivery
happens during commit. Runtime code can emit through `host.shared.emit(...)`
when it is already outside the draw staging lane.

## Actions

Actions are one-shot UI intent. They are staged during draw and executed during
commit after staged data flushes and mutation sync succeeds.

Use actions for:

- reset/import/export/apply commands
- buttons that should invoke runtime code after commit
- draw interactions that update status through runtime code

Do not use actions as storage. If a value must be visible on future frames,
store it in `data`, `status`, `cache`, or `shared` depending on ownership.

## Controls

Controls bundle repeated data/interface patterns. They generate private storage
aliases and expose domain-shaped UI/runtime refs.

Use controls when a repeated domain concept has:

- a predictable data shape
- a specific draw representation
- runtime reads through a domain method

Controls declare configuration storage only. They should not declare status or
actions; UI composition can pass status/action refs into a control draw call
when needed.

## Common Mistakes

- Do not put runtime-owned values under `module.data.define(...)`.
- Do not use `status` for values that should affect `module.mutation.patch(...)`.
- Do not use `cache` because a value feels temporary if UI needs to read it.
- Do not use actions to remember state.
- Do not expose a shared lane for data only one module uses.
- Do not make a control just to wrap one plain widget unless it improves a
  repeated domain pattern.

## Related Docs

- [DRAW_LIFECYCLE.md](DRAW_LIFECYCLE.md)
- [capabilities/MANAGED_STATE.md](capabilities/MANAGED_STATE.md)
- [capabilities/CACHE.md](capabilities/CACHE.md)
- [capabilities/SHARED.md](capabilities/SHARED.md)
- [capabilities/CONTROLS.md](capabilities/CONTROLS.md)
