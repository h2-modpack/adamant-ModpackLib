# adamant-ModpackLib

Reusable runtime library for Hades II mod authors building modpacks, large
configuration-heavy mods, or coordinated feature bundles.

ModpackLib provides the common plumbing that those projects usually need:

- typed storage definitions for module settings
- draw-phase `ui.data` and `ui.actions` for responsive ImGui config screens
- runtime `runtime.data` for committed hook, mutation, overlay, and shared-event logic
- profile and hash helpers for saving, loading, and identifying settings
- mutation helpers for modules that patch run data
- managed module helpers for coordinated and fallback UI usage
- reusable ImGui widgets and navigation helpers

The library is designed around immediate-mode UI. Module authors write normal
draw functions, then expose them through a module declaration facade:

```lua
local function init()
    local data = import("mods/data.lua")
    local logic = import("mods/logic.lua").bind(data)
    local ui = import("mods/ui.lua").bind(data)

    local module, err = lib.createModule({
        pluginGuid = PLUGIN_GUID,
        config = config,
        modpack = PACK_ID,
        id = "ExampleModule",
        name = "Example Module",
    })
    if not module then return end

    module.data.define(data.buildStorage())
    module.ui.tab(ui.drawTab)
    module.ui.quickContent(ui.drawQuickContent)
    logic.attach(module)
    module.activate()
end
```

`pluginGuid` is the stable runtime identity; Lib owns the internal hot-reload
state for hooks, overlays, shared events, cache, mutation runtime, and
structural reload tracking. Declare runtime hooks on `module.hooks.*` before activation.
`module.activate()` registers the live module for coordinated discovery and installs requested fallback UI.
Every module definition must declare a stable `id` and display `name`; `modpack`
is optional and marks modules that participate in Lib modpack coordination.

## Getting Started

For the full new-pack walkthrough, start with the
[`ModpackBootstrap` Getting Started guide](https://github.com/h2-modpack/ModpackBootstrap/blob/main/docs/GETTING_STARTED.md).
This repo documents the Lib module contract once you are editing module code.

Use the stack entrypoint that matches the job:

- Create a new pack with
  [`ModpackBootstrap`](https://github.com/h2-modpack/ModpackBootstrap).
- Add modules to an existing pack with
  `ModpackTools/run ModpackTools/new_module/create.py --package-id My_Module --title "My Module"`.
- Start standalone module code from
  [`ModpackModuleTemplate`](https://github.com/h2-modpack/ModpackModuleTemplate).
- Validate a full shell workspace with `ModpackTools/run ModpackTools/local_test/all.py`.

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

Modpack authors:
- [docs/modpack-authors/COORDINATOR_GUIDE.md](docs/modpack-authors/COORDINATOR_GUIDE.md)
  Coordinator bootstrap, discovery, and GUI wiring through `lib.modpack`.
- [docs/modpack-authors/QUICK_SETUP.md](docs/modpack-authors/QUICK_SETUP.md)
  Coordinator and module Quick Setup rendering contract.
- [docs/modpack-authors/HASH_PROFILE_ABI.md](docs/modpack-authors/HASH_PROFILE_ABI.md)
  Hash/profile compatibility rules for shipped modules and profiles.

Lib contributors:
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for changing the public Lib contract.
- [docs/lib-contributors/LIB_INTERNALS.md](docs/lib-contributors/LIB_INTERNALS.md)
  Internal composition, dependency flow, runtime anchors, and service-surface rules.
- [docs/lib-contributors/HOT_RELOAD_ARCHITECTURE.md](docs/lib-contributors/HOT_RELOAD_ARCHITECTURE.md)
  Stack hot-reload contract for Lib, coordinators, and coordinated modules.
- [docs/lib-contributors/TESTING.md](docs/lib-contributors/TESTING.md)
  Lib and repo-level validation workflow.

Reference and historical notes:
- [docs/README.md](docs/README.md)
  Full docs map.
- [docs/references/KNOWN_LIMITATIONS.md](docs/references/KNOWN_LIMITATIONS.md)
  Accepted architecture boundaries and runtime constraints.

## Public Surface

- `module.data`
- `module.actions`
- `module.cache`
- `module.controls`
- `module.ui`
- `module.onCommit`
- `module.hooks`
- `module.mutation`
- `module.overlays`
- `module.shared`
- `module.fallbackUi`

Common top-level helpers:
- `lib.createModule(...)`
- `lib.modpack.*`

Most authors start with `lib.createModule(...)`. It returns `nil, err`
instead of throwing when construction fails, so invalid modules can be logged
and skipped without stopping sibling modules. Activation remains explicit
through `module.activate()`.
See [docs/module-authors/GETTING_STARTED.md](docs/module-authors/GETTING_STARTED.md) for the recommended project shape.

## Validation

```bash
cd adamant-ModpackLib
lua52.exe tests/all.lua
```
