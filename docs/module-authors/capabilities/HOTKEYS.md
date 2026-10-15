# Hotkeys

Hotkeys let a module react to a key press without polling keys itself.

A module **requests** a hotkey for an event. Lib owns the binding, decides
which request owns each key, dispatches presses, and **responds** with a status
your UI can show. Two modules can never fire on the same key: one owns it, the
others see a conflict that names the owner.

You only declare requests. Lib draws the controls for them in your module's
**Hotkeys & Advanced** tab and in Lib's Hotkeys overview; your own tabs draw
nothing for hotkeys.

Design background: [../../lib-contributors/HOTKEYS_DESIGN.md](../../lib-contributors/HOTKEYS_DESIGN.md).

## Request

Declare requests before `module.activate()`:

```lua
module.hotkeys.request("TogglePause", {
    label = "Pause hotkey",            -- shown on the hotkey row, statuses, and the overview
    default = "F9",                    -- binding string, or "" (the default) for unbound
    alias = "Hotkey",                  -- optional storage alias; defaults to "Hotkey_<id>"
    tooltip = "Freeze the game without opening the pause menu.",
    onPress = function(host, runtime)
        -- runtime lane: runtime.data, runtime.status, runtime.shared, ...
    end,
})
```

Rules, checked when you call `request`:

- `id` and `alias` are stable identifiers (letters, digits, underscores, starting
  with a letter); each is unique within the module.
- `label` is a non-empty string; `onPress` is a function; `tooltip` is an
  optional string.
- `default` is `""` or a valid binding (see below).

`onPress` runs only while your module is enabled and its request owns the key.
Keep extra gating (for example "only during gameplay") inside the handler.
Errors raised by `onPress` are caught and reported once per request until its
binding changes.

## Binding storage

Lib declares the binding storage for you: a persisted `string` data root at
`alias`, excluded from hashes and profiles (`hash = false`). It is ordinary
committed data, so `runtime.data.read("Hotkey")` works.

Do not declare the alias yourself in `module.data.define`; activation fails
with `hotkeys.alias_collision` if you do. Set `alias` to a storage name your
module already used so saved bindings carry over.

## Bindings

A binding is `""` (unbound) or `[Ctrl+][Shift+][Alt+]<Key>`:

- modifiers appear in that order: `Ctrl+F5`, `Ctrl+Shift+F5`, `Shift+Alt+F12`;
- `<Key>` is `F1` through `F12`.

Anything else (for example a hand-edited `ctrl+f5` or `F13`) has state
`invalid` and never fires.

Matching is exact: `F5` fires only with no modifier held; `Ctrl+F5` needs Ctrl
held and Shift and Alt released. Either the left or the right modifier key
counts. Presses do not repeat while the key is held. Nothing fires while the
Hell2Modding overlay is open.

## Where users edit bindings

Every module Lib draws (modpack window module page and standalone fallback
window) ends its tab bar with a Lib-owned tab. It is labelled **Hotkeys &
Advanced** when the module requests hotkeys and **Advanced** otherwise, and
reads **Hotkeys & Advanced (!)** while any request is `conflict`, `reserved`,
or `invalid`. It holds Debug Mode and Resync State for this module, then:

- One row per request, in declaration order: the label, a modifier dropdown
  (None, Ctrl, Shift, Alt, Ctrl+Shift, Ctrl+Alt, Shift+Alt), a key dropdown
  (None, F1-F12), and the short status (`text`) on the same row. Hovering the
  status shows `detail` when there is one.
- **All hotkeys...**, which opens Lib's window on its Hotkeys tab.

An edit writes the binding through the module's staged state and commits it
right away, like the Enabled checkbox. A disabled module draws only its Enabled
checkbox, so its bindings are edited from Lib's Hotkeys tab (state
`disabled`).

**Lib's Hotkeys tab** (`adamant-lib` menu > **Settings**, or **All
hotkeys...**) lists every request across every pack and standalone module:
conflicts first, disabled modules last, a separator between modules. It also
shows the reserved keys and is the only place to edit the manual reserved list.

A modpack window's **Settings** page shows the same rows limited to that
pack's modules, plus the detected Hell2Modding key when one was detected.

## Status

```lua
local status = ui.hotkeys.status("TogglePause")       -- draw lane
local status = runtime.hotkeys.status("TogglePause")  -- runtime lane
```

Returns:

```lua
{
    state = "active" | "conflict" | "reserved" | "unbound" | "invalid" | "disabled",
    binding = "Ctrl+F5",
    owner = { moduleName = "Quick Pause", label = "Pause hotkey" }, -- conflict only
    reason = "Hell2Modding overlay",                                -- reserved only
    text = "In use by Quick Pause",                                 -- short status Lib draws on the row
    detail = "Ctrl+F5 is used by Quick Pause (Pause hotkey); ...",  -- tooltip sentence, or nil
}
```

| State | Meaning | `text` |
| --- | --- | --- |
| `active` | this request owns the key and fires | `Active` |
| `conflict` | another request owns the key; this binding is inactive | `In use by <module>` |
| `reserved` | the key is the Hell2Modding overlay key or in Lib's reserved list | `Reserved (<reason>)` |
| `unbound` | no binding | `Not set` |
| `invalid` | the stored binding is not a valid binding | `Invalid` |
| `disabled` | the module is disabled, so the request is not a candidate | `Module disabled` |

`detail` is set for `conflict`, `reserved`, `invalid`, and `disabled`.
`reason` is `"Hell2Modding overlay"` or `"Lib settings"` (the manual list).

The status table is replaced only when its contents change. Unknown ids raise
`hotkeys.unknown_request`.

## Ownership

- A request is a candidate for its key when its module is live and enabled and
  its binding is valid, not reserved, and not unbound. Only the owner
  dispatches.
- The current owner keeps its key when another request starts using it.
- Without an owner (load time, or the owner left), the tie-break is pack module
  order, then plugin GUID, then declaration order. Modules outside a pack come
  after pack modules.
- Ownership history is kept in memory only; after a restart the tie-break
  decides.

## Reserved keys

- Hell2Modding's overlay key is read from `gui_toggle` in
  `Hell2Modding-Hell2Modding-Hotkeys.cfg` in the ReturnOfModding config folder.
  `VK_F1`-`VK_F12` reserve that F-key under every modifier combination
  (Hell2Modding fires whatever modifiers are held); other keys (`VK_INSERT`,
  `1`, ...) are shown but cannot collide with an F-key binding.
- Lib config `ReservedHotkeys` is a comma-separated list of extra bindings to
  keep free, edited only in Lib's Hotkeys tab. An entry without
  modifiers (`F2`) reserves the key under every modifier combination; an entry
  with modifiers (`Ctrl+F2`) reserves exactly that combination.
