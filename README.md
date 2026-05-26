# adamant-ModpackLib

Reusable runtime library for Hades II mod authors building modpacks, large
configuration-heavy mods, or coordinated feature bundles.

ModpackLib provides the common plumbing that those projects usually need:

- typed storage definitions for module settings
- draw-phase `state` and `actions` for responsive ImGui config screens
- a persistent `store` model for runtime hook logic
- profile and hash helpers for saving, loading, and identifying settings
- mutation helpers for modules that patch run data
- module host helpers for coordinated and fallback UI usage
- reusable ImGui widgets and navigation helpers

The library is designed around immediate-mode UI. Module authors write normal
draw functions, then expose them through a module host:

```lua
local data = import("mods/data.lua")
local logic = import("mods/logic.lua").bind(data)
local ui = import("mods/ui.lua").bind(data)

local host, store, err = lib.createModule({
    pluginGuid = PLUGIN_GUID,
    config = config,
    id = "ExampleModule",
    name = "Example Module",
    storage = data.buildStorage(),
    drawTab = ui.drawTab,
    drawQuickContent = ui.drawQuickContent,
})
if not host then return end

logic.registerHooks(host, store)
host.activate()
```

`pluginGuid` is the stable runtime identity; Lib owns the internal hot-reload
state for hooks, overlays, shared events, cache, mutation runtime, and
structural reload tracking. Declare runtime hooks on `host.hooks.*` before activation.
`host.activate()` registers the live host for coordinated discovery and installs requested fallback UI.
Every module definition must declare a stable `id` and display `name`; `modpack`
is optional and marks modules that participate in Framework coordination.

## Docs

Start with the route that matches what you are doing.

Module authors:
- [docs/module-authors/GETTING_STARTED.md](docs/module-authors/GETTING_STARTED.md)
  First module flow, file roles, and core concepts.
- [docs/module-authors/MODULE_AUTHORING.md](docs/module-authors/MODULE_AUTHORING.md)
  Full authoring contract for managed state, lifecycle, hooks, overlays, mutations, and hosting.
- [docs/module-authors/capabilities/README.md](docs/module-authors/capabilities/README.md)
  Focused guides for managed state, widgets, hooks, mutations, overlays, shared events, and cache.
- [API.md](API.md)
  Public namespaces, functions, and data contracts.

Lib contributors:
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for changing the public Lib contract.
- [docs/lib-contributors/LIB_INTERNALS.md](docs/lib-contributors/LIB_INTERNALS.md)
  Internal composition, dependency flow, runtime anchors, and service-surface rules.
- [docs/lib-contributors/HOT_RELOAD_ARCHITECTURE.md](docs/lib-contributors/HOT_RELOAD_ARCHITECTURE.md)
  Stack hot-reload contract for Lib, Framework, Core, and coordinated modules.
- [docs/lib-contributors/TESTING.md](docs/lib-contributors/TESTING.md)
  Lib and repo-level validation workflow.

Reference and historical notes:
- [docs/README.md](docs/README.md)
  Full docs map.
- [docs/references/KNOWN_LIMITATIONS.md](docs/references/KNOWN_LIMITATIONS.md)
  Accepted architecture boundaries and runtime constraints.

## Public Surface

- `host.hooks`
- `host.overlays`
- `host.shared`
- `host.fallbackUi`

Common top-level helpers:
- `lib.createModule(...)`
- `lib.createFrameworkRuntime(...)`

Most authors start with `lib.createModule(...)`. It returns `nil, nil, err`
instead of throwing when construction fails, so invalid modules can be logged
and skipped without stopping sibling modules. Activation remains explicit
through `host.activate()`.
See [docs/module-authors/GETTING_STARTED.md](docs/module-authors/GETTING_STARTED.md) for the recommended project shape.

## Validation

```bash
cd adamant-ModpackLib
lua52.exe tests/all.lua
```
