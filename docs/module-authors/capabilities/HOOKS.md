# Hooks

Hooks let a module participate in game or ModUtil call paths without owning the
ModUtil hook installation lifetime directly.

Use hooks when the module needs to inspect, transform, or replace runtime
behavior at a named path. Do not use hooks for configuration UI or declarative
run-data edits; use [WIDGETS.md](WIDGETS.md) and [MUTATIONS.md](MUTATIONS.md)
for those.

## Normal Shape

Create the module, declare hooks on `module.hooks`, then activate:

```lua
local function registerHooks(module)
    module.hooks.wrap("GetEligibleLootNames", function(host, runtime, base, ...)
        local result = base(...)
        if host.isEnabled() and runtime.data.read("FeatureEnabled") then
            -- inspect or transform result here
        end
        return result
    end)
end

local module, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = MODULE_ID,
    name = "Example Module",
})
if not module then return end

module.data.define(data.buildStorage())
module.ui.tab(ui.drawTab)
registerHooks(module)
module.activate()
```

`module.hooks` is bound to the module, so hook declarations do not need a
separate owner argument and do not rely on an ambient registration context.

## Supported Hook Forms

Use:

- `module.hooks.wrap(path, handler)`
- `module.hooks.wrap(path, key, handler)`
- `module.hooks.override(path, replacement)`
- `module.hooks.override(path, key, replacement)`
- `module.hooks.contextWrap(path, context)`
- `module.hooks.contextWrap(path, key, context)`

Use a keyed overload when one module needs more than one registration for the
same path.

## Lifecycle

Hook declarations are open after `lib.createModule(...)` returns and close when
activation starts. Calling `module.hooks.*` after activation is an author error.

`module.activate()` installs the declared hooks. Lib owns:

- installing the stable ModUtil dispatcher
- refreshing behavior on module reload
- removing hook behavior omitted by a later host for the same module owner id,
  derived from `pluginGuid`
- rolling back activation when hook setup fails

Hook declarations should be complete and repeatable. A hot reload should create
a fresh host and declare the complete current hook set before activation.

## Runtime State

Hook callbacks should read committed state from `runtime.data`:

```lua
if host.isEnabled() and runtime.data.read("FeatureEnabled") then
    -- enabled committed behavior
end
```

Do not read draw-state values inside hook callbacks. Draw state is staged UI state; hooks run against committed runtime behavior.
Store access is runtime-phase access. It is valid in hook callbacks and normal
runtime helper code, but not while any module draw callback is running.

## Wrap vs Override

Prefer `wrap` when the original behavior should still run. Use `override` only
when the module must fully replace the target path.

Overrides are inherently higher risk because only one replacement behavior can
own the path at a time. Keep override handlers small, stable, and easy to
reason about.

## Common Mistakes

- Do not call `module.hooks.*` after `module.activate()`.
- Do not use random keys for keyed hooks; keys are part of hook identity.
- Do not capture staged UI state in runtime hooks.
- Do not use hooks for declarative table edits that fit mutation plans.

See also:
- [MUTATIONS.md](MUTATIONS.md)
- [MANAGED_STATE.md](MANAGED_STATE.md)
- [../../../API.md](../../../API.md)
