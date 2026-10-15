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

Authors only declare requests; Lib draws every hotkey control (see UI below). Status:

```lua
ui.hotkeys.status("TogglePause")
runtime.hotkeys.status("TogglePause")
--> { state = "active" | "conflict" | "reserved" | "unbound" | "invalid" | "disabled",
--    binding = "Ctrl+F5",
--    owner = { moduleName = "Quick Pause", label = "Pause hotkey" },  -- conflict only
--    reason = "Hell2Modding overlay",                                 -- reserved only
--    text = "In use by Quick Pause",                                  -- short inline status
--    detail = "Ctrl+F5 is used by Quick Pause (Pause hotkey); ..." }  -- tooltip sentence or nil
```

Lib's internal hotkey picker (`widget.lua`) draws a modifier dropdown (None, Ctrl, Shift, Alt,
Ctrl+Shift, Ctrl+Alt, Shift+Alt) and a key dropdown (None, F1-F12), writes the combined binding
string, and draws the short status on the same row, coloured by state, with `detail` as its
tooltip:

| State | `text` | `detail` |
| --- | --- | --- |
| `active` | `Active` | nil |
| `conflict` | `In use by Quick Pause` | `F9 is used by Quick Pause (Pause hotkey); this binding is inactive until one of them changes.` |
| `reserved` | `Reserved (Hell2Modding overlay)` | `F1 is reserved (Hell2Modding overlay), so this binding never fires.` |
| `unbound` | `Not set` | nil |
| `invalid` | `Invalid` | `'ctrl+f5' is not a valid hotkey; pick a key to replace it.` |
| `disabled` | `Module disabled` | `This binding is inactive while the module is disabled.` |

Reserved reasons are `"Hell2Modding overlay"` (detected) and `"Lib settings"` (manual list).

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

## UI

Hotkey controls are Lib-owned; there is no author widget or ref (no `draw.widgets.hotkey`, no
`ui.hotkeys.get`). There are two hotkey UI layers: the module's own Lib tab and Lib's global view.
Packs draw no hotkey UI of their own beyond the projection on their Settings page;
their part is pushing module order for the tie-break.

**Module Lib tab** (`module_block.lua`, inside `core/ui/module_frame.lua`). The shared module
frame, drawn by the modpack window module page and the standalone fallback window, ends its tab
bar with a Lib tab: Debug Mode and Resync State for this module, then one picker row per request
in declaration order and an **All hotkeys...** button that opens Lib's window on its Hotkeys tab.
The tab is labelled `Hotkeys & Advanced`, or `Advanced` for a module without requests, with a
`(!)` suffix while any request is `conflict`, `reserved`, or `invalid` (the block's `attention`
flag). A disabled module draws only its Enabled checkbox, so its bindings are edited from Lib's
window.

**Lib window** (`core/ui/lib_window.lua`). The `adamant-lib` menu is always shown, with or without
packs; its **Settings** item opens the `adamant-lib` window. Its **Hotkeys** tab draws
`overview.drawAll`: one row per request across every live module in every pack and standalone,
conflicts first, disabled modules last, a separator between modules, then the reserved keys
(detected Hell2Modding key, Detect again, manual list editor). This is the only reserved-key
editor. Its **Debug** tab holds Lib Policy Debug and the Lib diagnostics toggles. The ImGui
callback is registered once per process (`registry.ui.libWindowRegistered`) and late-reads
`registry.ui.renderLibWindow`, which every import overwrites.

**Pack Settings page** (`modpack/ui/settings.lua`). `overview.drawForOwners` draws the same rows
limited to the pack's modules (a conflict with another pack's module names that owner in the
status), `overview.drawDetectedKey` adds a read-only line for the Hell2Modding key when one was
detected, and **All hotkeys...** opens Lib's window. No reserved-key editor.

**Edits** from every surface go through `row_refs.lua`: a row ref reads the live module's
committed binding and writes with `writeAndFlush` (stage + commit), the same path the modpack
window uses for module enabled state, in pack and fallback mode alike. Blocks (rows + attention)
and status text are built by the registry when resolution runs, and labels are built once per
owner, so the draw path does not allocate per frame.

## Migration

Quick Pause (`Hotkey`) and LiveSplit (`PagePrevKey`, `PageNextKey`) drop their own storage,
ticks and anchors and request through `module.hotkeys` with `alias` set to their old storage
names. Both then require the Lib release that ships this capability.

## Implementation Notes

- Code: `src/core/hotkeys/` (`bindings.lua` grammar, `declarations.lua` contact point and storage
  compile, `resolution.lua` pure ownership, `reserved.lua` detection and the manual list,
  `00_init.lua` registry/receipt/tick, `widget.lua` picker, `row_refs.lua`, `module_block.lua`,
  `overview.lua`), `src/core/ui/module_frame.lua` (module Lib tab), `src/core/ui/lib_window.lua`
  (Lib window), and `src/core/modpack/ui/settings.lua` (pack projection).
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
