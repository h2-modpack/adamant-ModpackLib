# Mutations

Mutations are for reversible live run-data edits. A module describes what
should change while Lib owns apply, revert, enable/disable, settings commit,
profile load, hot reload, and rollback behavior.

## Normal Shape

Declare one patch builder before activation:

```lua
module.mutation.patch(function(host, runtime, plan)
    if runtime.data.read("FeatureEnabled") then
        plan:set(SomeGameTable, "Enabled", true)
        plan:appendUnique(SomeGameTable, "Pool", "NewEntry")
    end
end)
```

The callback receives committed runtime state through `runtime.data`. It should
describe the mutation for an enabled module. Lib owns enabled gating, including
enable/disable transitions and coordinated pack suspension/restore. Do not
guard plan construction with `host.isEnabled()`.

Mutation callbacks run in runtime space, not draw space. Read committed values
from `runtime.data`. Use draw `ui.actions` and `module.onCommit(...)` for
one-shot UI intent.

## Plan Operations

Mutation plans support:

- `plan:set(tbl, key, value)`
- `plan:setMany(tbl, values)`
- `plan:transform(tbl, key, fn)`
- `plan:append(tbl, key, value)`
- `plan:appendUnique(tbl, key, value)`
- `plan:removeElement(tbl, key, value)`
- `plan:setElement(tbl, key, oldValue, newValue, equivalentFn)`

Use the narrowest operation that describes the intended change.

## Transform Rules

`plan:transform(tbl, key, fn)` tracks and restores only `tbl[key]`.

```lua
plan:transform(SomeGameTable, "Weights", function(weights)
    weights.Special = 10
    return weights
end)
```

Do not mutate unrelated global state inside a transform callback.

## Common Mistakes

- Do not hand-write apply/revert pairs in module code.
- Do not guard patch-plan construction with `host.isEnabled()`.
- Do not read draw `ui.data` values in mutation callbacks.
- Do not use mutation callbacks for one-shot actions.
- Do not mutate unrelated tables inside `plan:transform(...)`.
