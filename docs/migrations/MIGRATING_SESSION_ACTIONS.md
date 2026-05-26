# Migrating Session Actions

Session action helpers have been removed from the old module-author `session`
surface. The current draw callback receives staged storage through `state` and
transient action refs through `actions`.

Action handlers declared on `createModule({ actions = ... })` now receive
`host, state, value`. They run after the draw callback and before staged state
flush:

```lua
actions = {
    ClearCache = function(host, state, value)
        host.logIf("Clear cache: %s", tostring(value and value.scope))
    end,
}
```

Use `actions.trigger(...)` for direct transient UI intent:

```lua
-- Before
session.stageAction("ClearCache", { scope = "run" })

-- After
actions.trigger("ClearCache", { scope = "run" })
```

Use `actions.get(...)` when a widget needs an action ref:

Widget `action` options require action refs now. The widget still performs its
normal data edit; the action is an optional staged intent for commit observers.

```lua
-- Before
draw.widgets.button("Clear", {
    action = "ClearCache",
    value = { scope = "run" },
})

-- After
draw.widgets.button("Clear", {
    action = actions.get("ClearCache"),
    value = { scope = "run" },
})
```

This applies to all interactive widgets that expose `action`, not only buttons.
When `value` is omitted, value widgets stage their edited value by default.

For draw-time action reads:

```lua
local clearCache = actions.get("ClearCache")
if clearCache:has() then
    local payload = clearCache:read()
end
```

For commit observers, use `commit.actions`:

```lua
local function onSettingsCommitted(host, store, commit)
    local clearCache = commit.actions.get("ClearCache")
    if clearCache:has() then
        local payload = clearCache:read()
    end
end
```

The old `commit.readAction(...)`, `commit.hasAction(...)`, and
`commit.hasActions()` helpers have also been removed.
