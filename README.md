# adamant-ModpackLib

Reusable runtime library for Hades II mod authors building modpacks, large
configuration-heavy mods, or coordinated feature bundles.

ModpackLib provides the common plumbing that those projects usually need:

- typed storage definitions for module settings
- a staged UI `session` model for responsive ImGui config screens
- a persistent `store` model for runtime hook logic
- profile and hash helpers for saving, loading, and identifying settings
- mutation helpers for modules that patch run data
- module host helpers for coordinated and standalone usage
- reusable ImGui widgets and navigation helpers

The library is designed around immediate-mode UI. Module authors write normal
draw functions, then expose them through a module host:

```lua
local definition = lib.prepareDefinition(internal, dataDefaults, {
    ...
})

public.host = lib.createModuleHost({
    definition = definition,
    store = store,
    session = session,
    hookOwner = internal,
    registerHooks = internal.RegisterHooks,
    drawTab = internal.DrawTab,
    drawQuickContent = internal.DrawQuickContent,
})
```

`hookOwner` and `registerHooks` are the standard way to declare a module's runtime hooks when it uses `lib.hooks.*`.

## Docs

- [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md)
  Start here for the core concepts, file roles, and first module flow.
- [API.md](API.md)
  Public namespaces, functions, and data contracts.
- [docs/MODULE_AUTHORING.md](docs/MODULE_AUTHORING.md)
  Deeper authoring guide for storage, sessions, lifecycle, and hosting.
- [docs/WIDGETS.md](docs/WIDGETS.md)
  Widget and navigation helpers for module UIs.
- [docs/UI_PERFORMANCE.md](docs/UI_PERFORMANCE.md)
  Render-path guidance for responsive ImGui screens.
- [docs/IMGUI_LUA_REFERENCE.md](docs/IMGUI_LUA_REFERENCE.md)
  Notes on the Dear ImGui Lua binding used by the stack.
- [docs/RELOAD_MODUTIL_CHALK_REFERENCE.md](docs/RELOAD_MODUTIL_CHALK_REFERENCE.md)
  Third-party stack reference for ReLoad, ModUtil, and Chalk behavior.
- [docs/HOT_RELOAD_ARCHITECTURE.md](docs/HOT_RELOAD_ARCHITECTURE.md)
  Stack hot-reload contract for Lib, Framework, Core, and coordinated modules.
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for changing the public Lib contract.

## Public Surface

- `lib.config`
- `lib.logging`
- `lib.lifecycle`
- `lib.mutation`
- `lib.hashing`
- `lib.hooks`
- `lib.integrations`
- `lib.widgets`
- `lib.nav`

Common top-level helpers:
- `lib.prepareDefinition(...)`
- `lib.createStore(...)`
- `lib.createModuleHost(...)`
- `lib.standaloneHost(...)`
- `lib.isModuleEnabled(...)`
- `lib.isModuleCoordinated(...)`
- `lib.resetStorageToDefaults(...)`

Most authors start with `lib.createStore(...)` and `lib.createModuleHost(...)`.
See [docs/GETTING_STARTED.md](docs/GETTING_STARTED.md) for the recommended project shape.

For structural module contracts, author raw definitions through `lib.prepareDefinition(...)`.
That includes optional `hashGroupPlan` declarations for complex grouped hash layouts; Lib preserves those hints as part of the prepared contract and Framework compiles them when building canonical config hashes.

## Validation

```bash
cd adamant-ModpackLib
lua5.2 tests/all.lua
```
