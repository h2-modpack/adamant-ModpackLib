# Retained Overlay Subsystem Design

## Purpose

The overlay subsystem provides host-scoped retained UI elements for module HUD projections plus narrow system-scoped HUD lines for first-party infrastructure.
Modules declare the maximum retained structure they need, then update named elements from explicit
projection events.

Lib owns:

- Retained overlay handles, layout, cleanup, and hot-reload refresh.
- Host scoping and name collision prevention.
- Activation rollback for overlay declarations and subscriptions.
- Event dispatch for supported overlay projection triggers.

Modules own:

- Domain state.
- Projection from domain state into overlay line/table values.
- Visibility rules that are specific to module settings.

## Non-Goals

- Do not add a general custom event bus in the overlay subsystem.
- Do not allow overlay callbacks to mutate store values directly.
- Do not make overlay callbacks equivalent to hooks; overlay callbacks are projection callbacks.
- Do not expose low-level HUD/stacked renderer primitives as module-author APIs.

## Module API

Modules declare retained overlays through the author-host overlay namespace:

```lua
host.overlays.createLine("summary.igt", spec)
host.overlays.onCommit(function(ctx, commit)
    ctx.setLine("summary.igt", BuildSummary())
    ctx.refresh("summary.igt")
end)
```

Declarations are open after host construction and close when activation starts.
The candidate host owns the overlay receipt, and overlay activation participates
in host activation rollback.

## Host Scoping

Overlay element names are local to the module owner id derived from
`pluginGuid` plus the committed host lifecycle:

```lua
host.overlays.createLine("summary.igt", spec)
host.overlays.createTable("runs", spec)
```

Lib builds globally stable backing identifiers from:

- Capability owner id.
- Local overlay name.
- Retained table row slot, when applicable.
- Column key, when applicable.

Two modules may use the same local overlay name without colliding.

## System Overlays

Framework and Lib may need retained HUD lines that are not declared by a module.
Lib internals use private system scopes, while Framework consumes the scoped
runtime overlay facade:

```lua
local frameworkRuntime = lib.createFrameworkRuntime("adamant-ModpackFramework")

frameworkRuntime.overlays.define("pack", "hud", function(overlays)
    overlays.createLine("hash.marker", spec)
end)
```

The system registrar intentionally exposes only `createLine(...)` and
`onCommit(...)`. Tables, intervals, and `afterHook(...)` remain module host
overlay capabilities.

System overlays are trusted first-party infrastructure for Lib fallback and
Framework HUD markers. They refresh directly through private system scopes or
the Framework runtime overlay facade; they do not participate in module host
activation receipts.

## Retained Elements

### Lines

A line is a single retained display row. The name intentionally avoids `row` so table row language stays
unambiguous.

```lua
host.overlays.createLine("summary.igt", {
    region = "middleRightStack",
    order = 100,
    visible = function()
        return true
    end,
    columnGap = 20,
    columns = {
        {
            key = "label",
            minWidth = 40,
            justify = "Left",
            textArgs = { Font = "P22UndergroundSCMedium" },
        },
        {
            key = "time",
            minWidth = 80,
            justify = "Left",
            textArgs = { Font = "NumericP22UndergroundSCMedium" },
        },
    },
})
```

Projection callbacks update lines by name:

```lua
ctx.setLine("summary.igt", { label = "IGT:", time = "12:34.56" })
ctx.setLine("message", "Ready")
```

String values are a convenience for one-column lines.

### Tables

A table is a fixed retained table projection with named columns and a maximum row count.

```lua
host.overlays.createTable("runs", {
    region = "middleRightStack",
    order = 200,
    maxRows = 11,
    visible = function()
        return true
    end,
    columnGap = 10,
    columns = {
        {
            key = "label",
            minWidth = 96,
            justify = "Left",
            textArgs = { Font = "P22UndergroundSCMedium" },
        },
        {
            key = "igt",
            minWidth = 78,
            justify = "Left",
            visible = function()
                return store.read("ShowIGT") == true
            end,
            textArgs = { Font = "NumericP22UndergroundSCMedium" },
        },
    },
})
```

Projection callbacks update tables by name:

```lua
ctx.setTable("runs", {
    { key = "run1", label = "Run 1", igt = "01:23.45" },
    { key = "current", label = "Current", igt = "00:12.34" },
})
```

Table behavior:

- Fixed column definitions.
- Per-column visibility is evaluated during refresh.
- Visible columns are compacted.
- Rows beyond `maxRows` are ignored.
- Unused retained rows are hidden.
- No sorting, scrolling, selection, dynamic columns, row actions, or custom row widgets in v1.

## Projection Context

Overlay callbacks receive a small projection context:

```lua
callback(ctx, event)
```

The context exposes:

```lua
ctx.read(alias)
ctx.isEnabled()
ctx.log(fmt, ...)
ctx.logIf(fmt, ...)
ctx.setLine(name, values)
ctx.setTable(name, rows)
ctx.setCell(tableName, rowKey, columnKey, value)
ctx.refresh(name)
ctx.refreshRegion(region)
ctx.refreshAll()
```

The context does not expose:

- `store.write`.
- The full store object.
- The `ModuleHost`.
- Mutation plans.
- Hook registration.

The context is not a durable public object family like store, session, or host. It is an event callback
projection surface.

## Supported Events

The retained overlay event surface is intentionally fixed:

- Settings commit projections.
- Interval projections.
- After-hook projections.

Custom module events are outside the v1 overlay subsystem. If module-emitted events become necessary,
they should be designed as a separate Lib capability and then made available to overlays.

### Settings Commit

```lua
host.overlays.onCommit(function(ctx, commit)
    ctx.setTable("runs", BuildRunRows())
    ctx.refreshRegion("middleRightStack")
end)
```

Commit ordering:

1. Framework commits staged session values and actions.
2. Module `onSettingsCommitted(host, store, commit)` runs.
3. Overlay `onCommit(ctx, commit)` callbacks run.

This lets module logic consume staged actions and update module state before overlays project the final
state.

### Intervals

```lua
host.overlays.onInterval("tick", 0.05, function(ctx)
    UpdateSnapshot()
    ctx.setLine("summary.igt", BuildIgtLine())
    ctx.refresh("summary.igt")
end, {
    when = function()
        return HasActiveDisplayLoop()
    end,
})
```

Lib owns interval lifecycle. Intervals are removed on hot-reload omission, activation rollback, and module
replacement. `when` controls callback execution; it does not unregister the interval.

### After Hooks

```lua
host.overlays.afterHook("StartNewRun", function(ctx, event)
    ctx.setTable("runs", BuildInitialRunRows(event.result))
    ctx.refreshRegion("middleRightStack")
end)
```

After-hook subscriptions are observers:

- They run after the normal hook stack and base function complete.
- They receive hook arguments and results.
- They cannot alter arguments or return values.
- They do not replace normal hook registration.

The event payload includes:

```lua
event.args
event.result
event.results
```

`event.result` is the first return value convenience field. `event.results`
contains the full return-value array for multi-return hooks.

## Hot Reload And Rollback

Overlay refresh is private retained-registry plumbing behind host receipts and
the narrow system/framework overlay APIs:

```lua
overlays.installForHost(host, authorHost, store)
frameworkRuntime.overlays.define(packId, "hud", register)
```

`installForHost` participates in host activation rollback.
The Framework overlay facade is a direct first-party refresh path for fixed
Framework infrastructure overlays. Lib-owned fixed overlays use private system
scopes.

Refresh behavior:

- Execute the registration callback against a fresh declaration pass.
- Mark seen retained elements and event subscriptions.
- Remove omitted elements and subscriptions after a successful refresh.
- Preserve previous overlay state if refresh fails.

Activation behavior:

- Host activation stages overlays alongside hooks and integrations.
- If a later activation step fails, rollback disposes candidate overlay registrations.
- Failed activation must not leave newly created overlay elements or subscriptions active.

## Renderer Internals

The retained API builds on private HUD component and stacked-layout renderer functions. Module authors
should not register HUD components or stacked rows directly.

- `frameworkRuntime.overlays.define` is the Framework retained overlay entry point.
- Module `host.overlays.*` is the retained module-overlay entry point.
- Framework overlay suppression is exposed through `frameworkRuntime.ui`.
- Fallback module UI suppression uses the internal overlay service.

New code should use host-owned module declarations, Framework runtime overlays,
or private Lib system scopes only.

## Timer Target Shape

The Speedrun Timer should become a retained overlay consumer with structure similar to:

```lua
function timerApi.declareOverlays(host, store)
    host.overlays.createLine("summary.igt", summaryIgtSpec)
    host.overlays.createLine("summary.rta", summaryRtaSpec)
    host.overlays.createLine("summary.lrt", summaryLrtSpec)
    host.overlays.createTable("batch", batchTableSpec)
    host.overlays.createTable("splits", splitsTableSpec)

    host.overlays.onCommit(function(ctx, commit)
        ApplyCommittedDisplayState(commit)
        ctx.setLine("summary.igt", BuildSummaryLine("igt"))
        ctx.setLine("summary.rta", BuildSummaryLine("rta"))
        ctx.setLine("summary.lrt", BuildSummaryLine("lrt"))
        ctx.setTable("batch", BuildBatchRows())
        ctx.setTable("splits", BuildSplitRows())
        ctx.refreshRegion("middleRightStack")
    end)

    host.overlays.onInterval("tick", TIMER_REFRESH_INTERVAL, function(ctx)
        UpdateTimerSnapshot()
        ctx.setLine("summary.igt", BuildSummaryLine("igt"))
        ctx.setLine("summary.rta", BuildSummaryLine("rta"))
        ctx.setLine("summary.lrt", BuildSummaryLine("lrt"))
        ctx.setTable("batch", BuildBatchRows())
        ctx.setTable("splits", BuildLiveSplitRows())
        ctx.refreshRegion("middleRightStack")
    end, {
        when = HasActiveDisplayLoop,
    })

    host.overlays.afterHook("StartNewRun", function(ctx)
        ctx.setTable("batch", BuildBatchRows())
        ctx.setTable("splits", BuildSplitRows())
        ctx.refreshRegion("middleRightStack")
    end)
end
```

Timer code should stop owning retained overlay handles directly. It should expose projection builders that
return line values and table rows.

## Test Checklist

Lib tests:

- `host.overlays.*` records declarations before activation.
- `createLine` creates a host-scoped retained line.
- `setLine` updates retained line values.
- `createTable` creates fixed-capacity retained rows.
- `setTable` shows provided rows up to `maxRows` and hides unused rows.
- Column visibility compacts visible table columns.
- Omitted retained declarations are cleaned up after successful refresh.
- Failed overlay refresh preserves previous declarations.
- Failed activation rolls back overlay declarations and subscriptions.
- `onCommit` runs after module `onSettingsCommitted`.
- `onInterval` runs while active and is cleaned up on refresh/removal.
- `afterHook` observes hook args/results and cannot alter return values.
- Framework runtime overlays and private system overlays support first-party HUD lines and clean omitted declarations.

Timer tests:

- Staged recording actions commit through `onSettingsCommitted`.
- Timer projection builders produce expected summary lines.
- Timer projection builders produce expected batch and split rows.
- Interval projection updates retained summary values.
- Settings commit updates column visibility and structure.
