# Integrations

Integrations are optional cross-module provider methods. They let one module publish a small domain capability and let other modules consume it without hard dependency coupling.

Use integrations when modules can cooperate but should still work when the provider is absent.

## Provider Shape

Hosted modules register providers on the author host before activation:

```lua
local host, store, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})
if not host then return end

host.integrations.register("run-director.god-availability", {
    providerId = MODULE_ID,
    methods = {
        isActive = {
            handler = function()
                return true
            end,
        },
        isAvailable = {
            reads = { "ZeusEnabled" },
            handler = function(scope, godKey)
                if godKey == "Zeus" then
                    return scope.read("ZeusEnabled") ~= false
                end
                return true
            end,
        },
    },
})

host.activate()
```

`providerId` is the public provider identity returned to consumers. It does not need to match `pluginGuid`.

Provider methods receive a scoped read object as their first argument. The scope
is deliberately narrow:

- `scope.read(alias, ...)` reads a declared alias from the provider's staged state.
- `scope.get(alias)` returns a read-only field or table ref for a declared alias.

Each method must declare the storage aliases it reads with `reads`. The scope is
valid only while that provider method is running, so do not cache it or refs
returned by `scope.get(...)`.

`reads` must be an array of aliases. Declaring a table root allows read-only
access to that table's rows. Packed root and packed child aliases are declared
independently: if a method reads a packed child through `readAlias(...)`, declare
that child alias.

## Consumer Shape

Consumers should prefer `invoke(...)`:

```lua
local active = host.integrations.invoke("run-director.god-availability", "isActive", false)
if active then
    return host.integrations.invoke("run-director.god-availability", "isAvailable", true, godKey) ~= false
end
return true
```

`invoke(...)` resolves the current preferred enabled provider at call time and returns the fallback when the provider or method is absent. Disabled provider hosts are skipped before provider code runs.
Runtime consumer code should use the author host passed into hook, overlay,
mutation, and module helper paths. Draw code should use
`services.invokeIntegration(...)`.

`host.integrations.invoke(...)` is a runtime helper. Draw callbacks receive the
narrower `services.invokeIntegration(...)` instead, so draw code can perform
draw-safe cross-module queries without gaining host lifecycle authority.

## Public Surface

Use:

- `host.integrations.register(id, { providerId = providerId, methods = methods })`
- `host.integrations.invoke(id, methodName, fallback, ...)`
- `services.invokeIntegration(id, methodName, fallback, ...)`

Hosted provider registrations should use `host.integrations.register(...)`.
They are owned by the module lifecycle owner and are retired when that owner is
replaced.

Provider declarations close when activation begins. Register the complete
current provider set before calling `host.activate()`.

Provider method tables should be small and reload-safe. Consumers should call
through `invoke(...)` instead of caching provider behavior, because a provider
module reload replaces the current implementation.

## Naming

Integration ids should describe domain behavior, not a specific consumer:

```text
run-director.god-availability
run-director.route-state
```

Provider ids should identify the module or provider implementation.

## Common Mistakes

- Do not make consumers require a provider to exist unless it is truly mandatory.
- Do not cache provider method tables or integration read scopes across reloads.
- Do not close over broad module internals when a scoped read declaration is enough.
- Do not assume provider id and `pluginGuid` are the same concept.

See also:
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
