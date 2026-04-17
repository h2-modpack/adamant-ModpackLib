# adamant-ModpackLib

Shared runtime and immediate-mode UI toolkit for adamant modpack modules.

Lib now owns:
- managed module storage and `uiState`
- storage typing, normalization, and hash encoding
- mutation lifecycle helpers for `affectsRunData` modules
- standalone hosting helpers
- immediate-mode widgets and navigation helpers

Lib does not own a declarative UI tree/runtime anymore.
New module UI should be written directly in `DrawTab(ui, uiState)` and optional `DrawQuickContent(ui, uiState)`.

## Docs

- [API.md](API.md)
  Reference for the current public namespaces and functions.
- [MODULE_AUTHORING.md](MODULE_AUTHORING.md)
  How to author a module against the current immediate-mode contract.
- [WIDGETS.md](WIDGETS.md)
  Widgets, nav, and storage notes for the live surface.
- [SPECIAL_MODULE_PERFORMANCE.md](SPECIAL_MODULE_PERFORMANCE.md)
  Render-path guidance for immediate-mode module UIs.
- [IMGUI_LUA_REFERENCE.md](IMGUI_LUA_REFERENCE.md)
  Notes on the Dear ImGui Lua binding used by the stack.
- [RELOAD_MODUTIL_CHALK_REFERENCE.md](RELOAD_MODUTIL_CHALK_REFERENCE.md)
  Stack reference for ReLoad, ModUtil, and Chalk behavior.
- [CONTRIBUTING.md](CONTRIBUTING.md)
  Contributor expectations for changing the public Lib contract.

## Current Public Namespaces

- `lib.config`
- `lib.coordinator`
- `lib.logging`
- `lib.host`
- `lib.mutation`
- `lib.storage`
- `lib.store`
- `lib.widgets`
- `lib.nav`

## Validation

```bash
cd adamant-ModpackLib
lua5.2 tests/all.lua
```
