# Migrating Session Actions

Session action helpers have been removed from the module-author `session`
surface. `session` now represents staged storage data only.

Use draw action refs for transient UI intent:

```lua
-- Before
draw.session.stageAction("ClearCache", { scope = "run" })

-- After
draw.actions.get("ClearCache"):stage({ scope = "run" })
```

Buttons also require action refs now:

```lua
-- Before
draw.widgets.button("Clear", {
    action = "ClearCache",
    value = { scope = "run" },
})

-- After
draw.widgets.button("Clear", {
    action = draw.actions.get("ClearCache"),
    value = { scope = "run" },
})
```

For draw-time action reads:

```lua
local clearCache = draw.actions.get("ClearCache")
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
