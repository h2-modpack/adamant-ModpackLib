# Hotkeys Design

Status: implemented (`src/core/hotkeys/`). Author guide:
[../module-authors/capabilities/HOTKEYS.md](../module-authors/capabilities/HOTKEYS.md).

## Problem

Modules poll keys themselves (Quick Pause's pause key, LiveSplit's page keys), each with its own
always-draw tick and anchor. No module can see another module's bindings, so two modules can bind
the same key and one press fires both. Keys are scarce, and the Hell2Modding overlay key is user
configurable (`F1`, `Insert`, even `1` are all in use in practice), so a hardcoded reserved key is
wrong.

## Model: request and response

A module **requests** a hotkey for an event. Lib owns the binding, decides which request owns
each key, dispatches presses, and **responds** with a status the UI shows right after each change.
Selection is never blocked; conflicts are explained, not prevented.

## Author surface

Declared before `module.activate()` (validated at declaration, like other capabilities):

```lua
module.hotkeys.request("TogglePause", {
    label = "Pause hotkey",            -- shown in pickers, statuses and the overview
    default = "F9",                    -- binding string, or "" for unbound
    alias = "Hotkey",                  -- optional storage alias; defaults to "Hotkey_<id>"
    tooltip = "Freeze the game without opening the pause menu.",
    onPress = function(host, runtime) ... end,
})
```

- Lib declares the binding's storage itself: a `string` data root (`hash = false`) at `alias`.
  `alias` lets a module keep the storage name it already used, so saved bindings carry over.
  A module must not also declare that alias in `module.data.define`.
- `onPress` runs on the runtime lane `(host, runtime)`. Module-specific gating (for example
  "only during gameplay") stays in the handler.

Draw and status:

```lua
ui.draw.widgets.hotkey(ui.hotkeys.get("TogglePause"))   -- modifier + key dropdowns, status line
ui.hotkeys.status("TogglePause")
runtime.hotkeys.status("TogglePause")
--> { state = "active" | "conflict" | "reserved" | "unbound" | "invalid",
--    binding = "Ctrl+F5",
--    owner = { moduleName = "Quick Pause", label = "Pause hotkey" } }  -- conflict only
```

The widget draws a modifier dropdown (None, Ctrl, Shift, Alt, Ctrl+Shift, Ctrl+Alt, Shift+Alt)
and a key dropdown (None, F1-F12), writes the combined binding string, and draws the status line
under them, for example:

- `Ctrl+F5 - active`
- `F9 is used by Quick Pause (Pause hotkey); this binding is inactive`
- `F1 is reserved (Hell2Modding overlay)`

## Bindings

- Format: `""` (unbound) or `[Ctrl+][Shift+][Alt+]<Key>`, modifiers in that canonical order,
  `<Key>` one of `F1`-`F12`. Anything else has state `invalid` (user-edited config).
- Matching is exact: `F5` fires only with no modifier held; `Ctrl+F5` needs Ctrl held and Shift
  and Alt released. Presses use `ImGui.IsKeyPressed(key, false)`; modifiers use `ImGui.IsKeyDown`
  on the left and right modifier keys (`LeftCtrl`/`RightCtrl`, ...).

## Ownership and conflicts

Only active bindings dispatch, so one key never fires two actions.

- A request is a candidate for its key when its module is live and enabled and its binding is
  valid, not reserved, and not unbound.
- **Existing owner keeps the key.** When a key gains another candidate, the current owner stays
  active; the newcomer gets `conflict` naming the owner.
- **Tie-break without history** (load time, or the owner left): pack module order, then plugin
  GUID, then request declaration order. Modules outside a pack sort after pack modules. The
  modpack layer pushes its module order down to the hotkey registry; hotkeys never read modpack
  state.
- Ownership history is in memory only (an anchor), so the tie-break decides after a restart.
- Resolution is recomputed when the inputs change (install, retire, binding or enabled change,
  reserved keys change), not every frame.

## Reserved keys

- Auto-detected: Hell2Modding's overlay key, read from `gui_toggle` in
  `Hell2Modding-Hell2Modding-Hotkeys.cfg` (TOML) in the profile config folder. Values are VK names
  (`VK_F1`, `VK_INSERT`) or a key character; Lib maps the ones it can express and ignores the rest.
- Manual: a Lib config list (default empty) for keys other tools use.
- Reserved bindings get `reserved` and never dispatch.
- Dispatch also pauses while the Hell2Modding overlay is open (`rom.gui.is_open()`), whatever its
  key.

## Runtime

- One always-draw tick for all modules, registered once on a persistent anchor under
  `AdamantModpackLib_Runtime.registry.hotkeys`; it late-reads the current dispatch table so a Lib
  reload swaps behavior without a second registration.
- Each module installs its requests through an activation receipt (`helpers/receipt.lua`):
  commit adds them to the registry, rollback restores the previous generation's requests, retire
  removes only this generation's. Recompute ownership after each.
- `onPress` errors are caught and reported once per request until the binding changes.

## Overview

The modpack window gets a **Hotkeys** page:

- one row per request across every live Lib module: module, action label, the hotkey widget,
  status;
- conflicts listed first;
- reserved keys: the detected Hell2Modding key and the manual list editor.

Edits from the overview write the owning module's binding through its staged state and commit,
the same way the window already edits module enabled state. Standalone modules show the widget
in their own fallback window.

## Migration

Quick Pause (`Hotkey`) and LiveSplit (`PagePrevKey`, `PageNextKey`) drop their own storage,
ticks and anchors and request through `module.hotkeys` with `alias` set to their old storage
names. Both then require the Lib release that ships this capability.

## Implementation Notes

- Code: `src/core/hotkeys/` (`bindings.lua` grammar, `declarations.lua` contact point and storage
  compile, `resolution.lua` pure ownership, `reserved.lua` detection and the manual list,
  `00_init.lua` registry/receipt/tick, `widget.lua`), and `src/core/modpack/ui/hotkeys.lua` (page).
- Change signal: a revision on the `registry.hotkeys` anchor (install commit/rollback/retire, pack
  order) plus a per-frame compare of each request's committed binding, its module's enabled state,
  and the Lib config reserved string. Resolution runs only when one of those changed; status tables
  are replaced only when their signature changes, so status text is built once per change.
- A request whose module is disabled reports state `disabled` (not a candidate), so the overview
  can tell it apart from an active binding.
- The Lib config manual list is one comma-separated string, `ReservedHotkeys` (default `""`).
- A reserved entry without modifiers reserves its key under every modifier combination, because
  Hell2Modding matches a single key whatever modifiers are held: the detected `VK_F1` reserves
  `F1`, `Ctrl+F1`, and so on. An entry with modifiers (manual list only) reserves exactly that
  combination.
- A new or changed pack order counts as load-time ordering: recorded ownership is dropped and the
  tie-break decides again. Pushing an unchanged order keeps ownership.
