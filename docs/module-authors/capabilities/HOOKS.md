# Hooks

Hooks let a module participate in game or ModUtil call paths without owning the
ModUtil hook installation lifetime directly.

Use hooks when the module needs to inspect, transform, or replace runtime
behavior at a named path. Do not use hooks for configuration UI or declarative
run-data edits; use [WIDGETS.md](WIDGETS.md) and [MUTATIONS.md](MUTATIONS.md)
for those.

## Normal Shape

Create the host, declare hooks on `host.hooks`, then activate:

```lua
local function registerHooks(host, store)
    host.hooks.wrap("GetEligibleLootNames", function(base, ...)
        local result = base(...)
        if host.isEnabled() and store.get("FeatureEnabled"):read() then
            -- inspect or transform result here
        end
        return result
    end)
end

local host, store = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
})

registerHooks(host, store)
host.activate()
```

`host.hooks` is bound to the module host, so hook declarations do not need an
owner token and do not rely on an ambient registration context.

## Supported Hook Forms

Use:

- `host.hooks.wrap(path, handler)`
- `host.hooks.wrap(path, key, handler)`
- `host.hooks.override(path, replacement)`
- `host.hooks.override(path, key, replacement)`
- `host.hooks.contextWrap(path, context)`
- `host.hooks.contextWrap(path, key, context)`

Use a keyed overload when one module needs more than one registration for the
same path.

## Lifecycle

Hook declarations are open after `lib.createModule(...)` returns and close when
activation starts. Calling `host.hooks.*` after activation is an author error.

`host.activate()` installs the declared hooks. Lib owns:

- installing the stable ModUtil dispatcher
- refreshing behavior on module reload
- removing hook behavior omitted by a later host for the same module owner id,
  derived from `pluginGuid`
- rolling back activation when hook setup fails

Hook declarations should be complete and repeatable. A hot reload should create
a fresh host and declare the complete current hook set before activation.

## Runtime State

Hook callbacks should read committed state from `store`:

```lua
if host.isEnabled() and store.get("FeatureEnabled"):read() then
    -- enabled committed behavior
end
```

Do not read draw-session state inside hook callbacks. Draw sessions are staged
UI state; hooks run against committed runtime behavior.

## Wrap vs Override

Prefer `wrap` when the original behavior should still run. Use `override` only
when the module must fully replace the target path.

Overrides are inherently higher risk because only one replacement behavior can
own the path at a time. Keep override handlers small, stable, and easy to
reason about.

## Common Mistakes

- Do not call `host.hooks.*` after `host.activate()`.
- Do not use random keys for keyed hooks; keys are part of hook identity.
- Do not capture staged UI session state in runtime hooks.
- Do not use hooks for declarative table edits that fit mutation plans.

See also:
- [MUTATIONS.md](MUTATIONS.md)
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
