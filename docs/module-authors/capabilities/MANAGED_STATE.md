# Managed State

Managed state is the core Lib feature most module code builds on. It gives each module:

- a validated storage schema
- a persisted runtime `store`
- a staged UI `session`
- built-in `Enabled` and `DebugMode` aliases
- hash/profile participation for stable settings
- table and packed-value helpers

The normal entrypoint is `lib.createModule(...)`. It prepares the definition, creates the store/session pair, and passes the right handle to each callback.

## State Surfaces

Use each state surface for one job:

| Surface | Use it for | Where it appears |
| --- | --- | --- |
| `store` | persisted runtime reads | host capability declarations, hook/overlay helpers, mutation callbacks |
| `session` | staged UI reads/writes | `drawTab`, `drawQuickContent` |
| `config` | Chalk-owned backing table | local to `main.lua` |

Draw code should stage changes through `session`. Gameplay, hooks, overlays, integrations, and mutations should read committed values through `store`.

```lua
function ui.drawTab(draw)
    draw.widgets.checkbox("FeatureEnabled", {
        label = "Enable Feature",
    })
end

function logic.registerHooks(host, store)
    host.hooks.wrap("SomeGameFunction", function(base, ...)
        if host.isEnabled() and store.read("FeatureEnabled") then
            -- Runtime behavior reads committed state.
        end
        return base(...)
    end)
end
```

Host/framework plumbing owns commit, reload, hash/profile import, and config flush behavior. Module draw callbacks receive a draw context with the author-facing session, not the private full session.

## Storage Roots

Storage lives on `definition.storage`:

```lua
function data.buildStorage()
    return {
        { type = "bool", alias = "FeatureEnabled", default = false },
        { type = "string", alias = "Mode", default = "Vanilla", maxLen = 32 },
        { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
    }
end
```

Rules:

- `alias` is the storage, session, widget, and persisted config key.
- Normal roots persist and hash by default.
- `persist = false, hash = false` creates session-only transient UI state.
- `hash = false` keeps a persisted staged value out of hash/profile serialization.
- `hash = true` requires `persist = true`.

Lib injects these aliases into every prepared module:

| Alias | Purpose |
| --- | --- |
| `Enabled` | module behavior toggle |
| `DebugMode` | diagnostic toggle, excluded from hashes/profiles |

Do not declare `Enabled` or `DebugMode` yourself.

## Runtime Cache Values

Runtime markers that should survive reloads or restarts but should not appear
in UI staging, profiles, or hashes should use `host.cache.persistent.*`.

## Tables

Use `type = "table"` for compact ordered rows with one shared row schema:

```lua
{
    type = "table",
    alias = "Tiers",
    minRows = 0,
    maxRows = 10,
    defaultRows = 1,
    row = {
        { type = "bool", alias = "Enabled", default = true },
        { type = "int", alias = "Limit", default = 2, min = 0, max = 5 },
    },
}
```

Table rules:

- The table root owns `persist` and `hash`.
- Row aliases are scoped to one row and do not leak into `session.read(...)`.
- Rows are compact ordered arrays with no row ids or holes.
- `defaultRows` creates the default row count.

Use `session.table(alias)` for staged UI edits:

```lua
local tiers = session.table("Tiers")
tiers:append({ Enabled = true, Limit = 3 })
tiers:write(1, "Limit", 4)
local limit = tiers:read(1, "Limit")
```

Use `store.table(alias)` for read-only runtime access. Table handles use colon method syntax.

## Packed Values

Use `packedInt` when one numeric root should expose named child aliases:

```lua
{
    type = "packedInt",
    alias = "PackedFlags",
    bits = {
        { alias = "AttackBanned", offset = 0, width = 1, type = "bool", default = false },
        { alias = "RarityOverride", offset = 1, width = 2, type = "int", default = 0 },
    },
}
```

Packed widgets can write child aliases through the same session. Lib handles repacking the root.

## Draw Actions

Draw callbacks expose action staging through `draw.actions`:

- `draw.actions.get(actionKey)`
- `draw.actions.hasAny()`

`draw.actions.get(actionKey)` returns an action ref:

- `action:stage(value)`
- `action:read()`
- `action:clear()`
- `action:has()`

Action refs are object handles; call their methods with colon syntax.

Use actions for one-shot UI intent that should be observed by runtime commit
plumbing, not for ordinary persistent settings. Stage actions through
`draw.actions`, not through `session`.

Observe committed actions with `onSettingsCommitted(host, store, commit)`:

```lua
local function onSettingsCommitted(host, store, commit)
    local clearCache = commit.actions.get("ClearCache")
    if clearCache:has() then
        local scope = clearCache:read()
        host.logIf("Clearing cache for %s", tostring(scope))
    end

    if commit.hadConfigChanges() then
        -- Rebuild derived state from committed store values here.
    end
end

local host = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    onSettingsCommitted = onSettingsCommitted,
    drawTab = ui.drawTab,
})
host.activate()
```

`commit` exposes:

- `commit.actions.get(actionKey)`
- `commit.actions.hasAny()`
- `commit.hadConfigChanges()`

Read action payloads through `commit.actions.get(actionKey)`. Buttons can stage
actions for this path through a `draw.actions.get(...)` ref passed in their
`action` option. Actions are cleared after the commit pass.

## Common Mistakes

- Do not read transient aliases from `store`; they only live in `session`.
- Do not write raw Chalk config from draw code.
- Do not call private session flush/reload helpers from module UI.
- Do not use draw actions as persistent settings.
- Do not put gameplay behavior in `ui.lua`; UI stages state, runtime code consumes committed state.

See also:
- [WIDGETS.md](WIDGETS.md)
- [../../../API.md](../../../API.md)
