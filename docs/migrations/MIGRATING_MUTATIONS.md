# Migrating Runtime Mutations

This note covers the mutation API change that removes manual apply/revert
callbacks and makes patch plans the only supported run-data mutation model.

## What Changed

- `registerManualMutation` is no longer a recognized module creation option.
- `registerPatchMutation` moved from `lib.createModule(...)` opts to
  `module.mutation.patch(...)` before activation.
- Hybrid patch/manual mutation lifecycles are no longer supported.
- `lib.mutation.createBackup()` is no longer public API.
- `lib.mutation.createPlan()` is no longer public API.
- Patch plans no longer expose public `apply`/`revert` execution methods.
- `plan:transform(tbl, key, fn)` now calls `fn(currentCopy)` only.
- `transform` callbacks must return the replacement value for `tbl[key]`.

The host lifecycle still applies and reverts active patch plans internally.
Module authors describe operations on the provided plan; Lib owns execution and
rollback.

## Why

Manual apply/revert made arbitrary side effects look supported even though Lib
could not inspect them, order them safely, or prove that rollback was complete.
Patch plans keep mutation state trackable: Lib knows which table slots were
changed and can restore them during disable, profile load, hot reload, and
failure rollback paths.

If a module needs an operation that the patch plan cannot currently express,
add a new patch-plan operation instead of bypassing the tracked lifecycle.

## Manual Mutation Migration

Before:

```lua
local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = internal.definition,
    registerManualMutation = {
        apply = function(host, store)
            SomeGameTable.SomeKey = true
        end,
        revert = function(host, store)
            SomeGameTable.SomeKey = false
        end,
    },
    drawTab = internal.DrawTab,
})
```

After:

```lua
local data = import("mods/data.lua")
local ui = import("mods/ui.lua")

local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
})
if not module then return end

module.data.define(data.buildStorage())
module.ui.tab(ui.drawTab)
module.mutation.patch(function(host, runtime, plan)
    plan:set(SomeGameTable, "SomeKey", true)
end)
module.activate()
```

For list edits, prefer the existing list operations:

```lua
plan:appendUnique(SomeGameTable, "Requirements", requirement)
plan:removeElement(SomeGameTable, "Requirements", requirement)
plan:setElement(SomeGameTable, "Requirements", oldRequirement, newRequirement)
```

For computed replacement values, use `transform`:

```lua
plan:transform(SomeGameTable, "Requirements", function(requirements)
    local nextRequirements = requirements or {}
    nextRequirements[#nextRequirements + 1] = requirement
    return nextRequirements
end)
```

The `requirements` argument is a copy. Mutating it is safe, but only the returned
value is written back to `SomeGameTable.Requirements`.

## Transform Callback Migration

Before, callbacks could receive `current, key, tbl`:

```lua
plan:transform(room, "GameStateRequirements", function(current, key, tbl)
    return buildRequirements(current, tbl.RoomSetName)
end)
```

Now callbacks receive only the copied current value:

```lua
plan:transform(room, "GameStateRequirements", function(current)
    return buildRequirements(current, room.RoomSetName)
end)
```

Capture any needed table/key context from the surrounding scope. Do not mutate
unrelated globals inside `transform`; the plan tracks only the target key.

## Non-Table Side Effects

Do not move arbitrary side effects into `transform` to replace manual mutation.
Use the lifecycle surface that owns the side effect:

- hooks: `module.hooks.*` declarations before activation
- overlays: `module.overlays.*` declarations before activation
- shared events: `module.shared.listen(...)` before activation; emit runtime events after activation
- persistent runtime values: `mode = "runtime"` storage plus
  `runtime.data.runtimeOwned`
- unrepresented run-data edits: add a patch-plan operation
