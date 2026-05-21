# Mutations

Mutations are for reversible live run-data edits. They let a module describe what should change while Lib owns apply, revert, enable/disable, settings commit, profile load, hot reload, and rollback behavior.

Use mutations when the module changes live game tables based on committed settings. Do not use them for UI staging or optional cross-module APIs.

## Normal Shape

Declare `host.mutation.patch(function(plan, host, store) ... end)` before activation:

```lua
local function buildPatchPlan(plan, host, store)
    if store.get("FeatureEnabled"):read() then
        plan:set(SomeGameTable, "Enabled", true)
        plan:appendUnique(SomeGameTable, "Pool", "NewEntry")
    end
end

local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})
host.mutation.patch(buildPatchPlan)
host.activate()
```

The callback receives committed runtime state through `store`.
It should describe the mutation for an enabled module. Lib owns enabled gating,
including enable/disable transitions and coordinated pack enablement. Do not
guard the plan with `host.isEnabled()`; during an enable transition, Lib may
build the plan before the persisted `Enabled` alias has been written.

## Plan Operations

Mutation plans support:

- `plan:set(tbl, key, value)`
- `plan:setMany(tbl, values)`
- `plan:transform(tbl, key, fn)`
- `plan:append(tbl, key, value)`
- `plan:appendUnique(tbl, key, value)`
- `plan:removeElement(tbl, key, value)`
- `plan:setElement(tbl, key, index, value)`

Use the narrowest operation that describes the intended change.

## Transform Rules

`plan:transform(tbl, key, fn)` tracks and restores only `tbl[key]`.

The callback receives a copy of the current value and must return the replacement value for that key:

```lua
plan:transform(SomeGameTable, "Weights", function(weights)
    weights.Special = 10
    return weights
end)
```

Do not mutate unrelated global state inside a transform callback.

## Lifecycle

Lib owns mutation execution through the live host. Module authors normally only provide the plan callback.

Activation and later host operations apply or refresh the plan when needed. If activation fails, Lib rolls back side effects where possible.

## When Not To Use Mutations

Do not use mutation plans for:

- transient UI state
- optional cross-module provider APIs
- state that should live on a game object instance
- arbitrary side effects that cannot be restored

If a real run-data edit cannot be expressed by the current plan surface, add a first-class plan operation instead of bypassing the tracked lifecycle.

## Common Mistakes

- Do not hand-write apply/revert pairs in module code.
- Do not guard patch-plan construction with `host.isEnabled()`.
- Do not read staged `session` values in mutation callbacks.
- Do not use mutation callbacks for one-shot actions.
- Do not mutate unrelated tables inside `plan:transform(...)`.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [HOOKS.md](HOOKS.md)
- [../../../API.md](../../../API.md)
