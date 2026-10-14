# Hotkeys

Hotkeys let a module react to a key press without polling keys itself.

A module **requests** a hotkey for an event. Lib owns the binding, decides
which request owns each key, dispatches presses, and **responds** with a status
your UI can show. Two modules can never fire on the same key: one owns it, the
others see a conflict that names the owner.

Design background: [../../lib-contributors/HOTKEYS_DESIGN.md](../../lib-contributors/HOTKEYS_DESIGN.md).

## Request

Declare requests before `module.activate()`:

```lua
module.hotkeys.request("TogglePause", {
    label = "Pause hotkey",            -- shown in pickers, statuses, and the Hotkeys page
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

## Draw

```lua
module.ui.tab(function(host, ui)
    ui.draw.widgets.hotkey(ui.hotkeys.get("TogglePause"))
end)
```

`draw.widgets.hotkey(ref, opts?)` draws the label, a modifier dropdown (None,
Ctrl, Shift, Alt, Ctrl+Shift, Ctrl+Alt, Shift+Alt), a key dropdown (None,
F1-F12), and a status line. It writes the combined binding to the staged
alias; the module commits it like any other staged edit. It returns `true` when
it wrote a new binding.

Options:

- `label` (default: the request label; `""` hides it)
- `tooltip` (default: the request tooltip)
- `modifierWidth`, `keyWidth`
- `showStatus = false` to hide the status line

Standalone modules show the widget in their own fallback window; coordinated
modules show it in their tab and on the modpack window's Hotkeys page.

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
    text = "Ctrl+F5 - active",                                      -- the widget's status line
}
```

- `active`: this request owns the key and fires.
- `conflict`: another request owns the key; this binding is inactive.
- `reserved`: the key is the Hell2Modding overlay key or is listed in Lib's
  reserved list.
- `unbound`: no binding.
- `invalid`: the stored binding is not a valid binding.
- `disabled`: the module is disabled, so the request is not a candidate.

The status table is replaced only when its state changes. Unknown ids raise
`hotkeys.unknown_request`.

## Ownership

- A request is a candidate for its key when its module is live and enabled and
  its binding is valid, not reserved, and not unbound.
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
  keep free, edited on the modpack window's Hotkeys page. An entry without
  modifiers (`F2`) reserves the key under every modifier combination; an entry
  with modifiers (`Ctrl+F2`) reserves exactly that combination.
