# Migrating To Plugin-Guid Runtime Identity

This note covers the module lifecycle identity change that removes normal
module-authored `owner` tokens.

## What Changed

- `lib.createModule(...)` no longer accepts
  `owner`.
- `pluginGuid` is the stable lookup identity for a module host.
- The committed host is the managed lifecycle owner for hooks, overlays,
  integrations, activation metadata, and structural hot-reload comparison.
- Mutation runtime is still module-owner scoped because raw game-table edits
  are process-global. For module hosts, that owner id is derived from
  `pluginGuid`.
- `definition.id` remains the module's domain/UI/profile/hash identity.
- `modpack` remains coordinator grouping.
- Stateless capability backends use `ownerId`, not `pluginGuid`. Module-host
  adapters derive that owner id from `pluginGuid`; system scopes provide their
  own deliberately scoped owner ids.

## Module Migration

Before:

```lua
local host = lib.createModule({
    owner = internal,
    pluginGuid = PLUGIN_GUID,
    config = config,
    definition = internal.definition,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
})
```

After:

```lua
local data = import("mods/data.lua")
local logic = import("mods/logic.lua")
local ui = import("mods/ui.lua")

local host, store = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})
logic.registerHooks(host, store)
```

Modules should use `host.fallbackUi.attachGuiOnce(...)` for stable fallback UI
callbacks instead of keeping private persistent tables for UI handles. Private
persistent tables are still valid for truly module-owned cached data, but they
should not be passed to Lib as lifecycle owners.

## Hook And Overlay Notes

Normal module hooks are declared on the returned author host before activation:

```lua
local function registerHooks(host, store)
    host.hooks.wrap("SomeGameFunction", function(base, ...)
        return base(...)
    end)
end
```

Lib scopes those declarations to the module's `pluginGuid` at the host-adapter
boundary, then passes a generic `ownerId` into the stateless hook backend.
Explicit-owned and ownerless ambient hook APIs were retired for normal
authoring. Lib infrastructure uses private system scopes for first-party
ownership, while Framework consumes first-party capability namespaces through
`lib.createFrameworkRuntime("adamant-ModpackFramework")`.

## Integration Notes

Integration providers are declared with `host.integrations.provide(...)`
before activation and refreshed by the module's `pluginGuid`. The `providerId`
inside the registration opts is still the public integration provider identity,
not the lifecycle owner. It can remain a module/domain id chosen for consumers.
