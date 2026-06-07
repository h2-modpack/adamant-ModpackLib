# Fallback UI And Framework Runtime Audit

## Commands

```powershell
rg -n "createFallbackMarker|ui\.status|runtime-owned|runtime owned|ui\.data provides|missing identity|storage contract|live module registry" adamant-ModpackLib adamant-ModpackFramework
rg -n "function renderWindow|imgui\.Begin|drawTabAndCommit|imgui\.End|xpcall|beganWindow|PopTheme" adamant-ModpackLib\src\core\fallback\fallback_ui.lua adamant-ModpackFramework\src\core\ui\window.lua
```

## Scope

- Lib fallback UI and fallback HUD.
- Lib framework runtime facade exposed to Framework.
- Framework module registry snapshot path.
- Framework window runtime, coordinator docs, and callback-surface doc wording.
- Existing fallback/framework runtime tests.

## Findings

- `document`: Framework docs still described runtime-authored status as
  read-only runtime-owned data under `ui.data`. They now describe the current
  split: staged configuration through `ui.data`, runtime-authored status through
  `ui.status`, and shared publication through `ui.shared`.
- `document`: several module-author docs listed draw callback objects without
  `ui.status` or `ui.shared`. Those lists now match the current draw surface.
- `document`: Framework docs said missing identity/storage contracts are skipped
  by Framework. The current runtime boundary is stricter: Lib validates modules
  before publishing them, and Framework discovers only Lib-published live
  modules for the pack.
- `fix`: fallback window rendering was less exception-safe than the coordinated
  Framework window. It now wraps the window body in `xpcall`, calls `imgui.End()`
  after a successful `imgui.Begin(...)`, and rethrows with a traceback.
- `keep`: `createFallbackMarker()` remains as a small fallback UI seam. It is
  used by Lib's once-loaded hook and the fallback harness, and the broader
  one-line helper audit already deferred it to fallback-specific work.

## Coverage

- Fallback UI runtime replacement, rollback, fallback marker visibility, menu
  toggling, run-data close flush, and overlay suppression are covered in
  `TestFallbackUi`.
- Framework discovery snapshots, quick content live-module refresh, startup
  mutation sync ownership, module enable/disable rollback, reset-all behavior,
  GUI close, and run-data flush are covered in `TestMain`.

## Result

Fallback UI now mirrors the coordinated Framework window cleanup pattern for
ImGui window balancing. The remaining edits were coordinator/runtime and
module-author documentation updates, plus this audit note.
