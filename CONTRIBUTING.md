# Contributing to adamant-Lib

Shared utility library for adamant modpack modules. Provides the module contract, UI primitives, managed special-state handling, and the field type system.

## Architecture

Single-file library (`src/main.lua`) loaded as `adamant-ModpackLib`. Modules access it with:

```lua
local lib = rom.mods["adamant-ModpackLib"]
```

## Public API

| Function | Purpose |
|---|---|
| `lib.isEnabled(modConfig, packId)` | True if module plus coordinator master toggle are both on |
| `lib.warn(packId, enabled, fmt, ...)` | Framework diagnostic print, printf-style. For framework-detected problems. Do not use for normal module tracing. |
| `lib.log(name, enabled, fmt, ...)` | Module trace print, printf-style, gated by the caller-supplied boolean |
| `lib.createBackupSystem()` | Returns `backup, revert` for isolated state save/restore |
| `lib.standaloneUI(def, config, apply, revert)` | Returns menu-bar callback for standalone regular modules |
| `lib.readPath(tbl, key)` | Read from table using string or path key |
| `lib.writePath(tbl, key, value)` | Write to table using string or path key |
| `lib.drawField(imgui, field, value, width)` | Render a regular-module option widget, returns `(newValue, changed)` |
| `lib.validateSchema(schema, label)` | Validate field descriptors at declaration time |
| `lib.createSpecialState(config, schema)` | Returns a managed `specialState` object for special modules |
| `lib.captureSpecialConfigSnapshot(modConfig, schema)` | Debug helper for detecting direct config writes in special-module UI |
| `lib.warnIfSpecialConfigBypassedState(name, enabled, specialState, modConfig, schema, before)` | Debug helper that logs when a special writes schema-backed config directly during draw |
| `lib.isFieldVisible(field, values)` | Returns true if `field.visibleIf` is absent or `values[field.visibleIf] == true` |
| `lib.FieldTypes` | The field type registry table |

## Module contract

Every module must expose `public.definition`:

```lua
public.definition = {
    id           = "MyMod",
    name         = "My Mod",
    category     = "Bug Fixes",
    group        = "General",
    tooltip      = "...",
    default      = true,
    dataMutation = true,
}

public.definition.apply  = apply
public.definition.revert = revert
```

- `apply` is called when the module is enabled
- `revert` is called when disabled, usually the closure from `createBackupSystem()`
- Framework wraps both in `pcall`; a failing module should not crash the pack UI

### Inline options (regular modules)

Boolean modules can declare options rendered below their checkbox:

```lua
public.definition.options = {
    { type = "checkbox", configKey = "Strict", label = "Strict Mode", default = false },
    { type = "dropdown", configKey = "Mode", label = "Mode",
      values = { "Vanilla", "Always", "Never" }, default = "Vanilla" },
}
```

`configKey` must be a flat string. Table-path keys are only valid in `definition.stateSchema` for special modules.

### Special modules

Special modules get their own sidebar tab and custom state:

```lua
public.definition.special     = true
public.definition.tabLabel    = "Hammers"
public.definition.stateSchema = { ... }
public.specialState           = lib.createSpecialState(config, public.definition.stateSchema)

function public.DrawTab(imgui, specialState, theme) ... end
function public.DrawQuickContent(imgui, specialState, theme) ... end
```

`public.specialState` is the managed state object for schema-backed UI state.

It exposes:
- `specialState.view` - read-only render view
- `specialState.get(path)`
- `specialState.set(path, value)`
- `specialState.update(path, fn)`
- `specialState.toggle(path)`
- `specialState.reloadFromConfig()`
- `specialState.flushToConfig()`
- `specialState.isDirty()`

### Schema caching

`lib.validateSchema` writes two cached values onto each field descriptor at declaration time:

| Field | Value | Purpose |
|---|---|---|
| `field._schemaKey` | `table.concat(configKey, ".")` for path keys, `tostring(configKey)` for strings | Stable hash key used by `captureSpecialConfigSnapshot`, `warnIfSpecialConfigBypassedState`, and the hash encode/decode loops |
| `field._imguiId` | `"##" .. tostring(configKey)` | Stable ImGui widget ID reused by `drawField` every frame |

These are written once and never recomputed. Do not overwrite them.

### Special-module rules

For schema-backed state:
- read from `specialState.view`
- mutate only through `specialState.set/update/toggle`
- do not write `config` directly during `DrawTab` / `DrawQuickContent`

Framework-owned hosted flow:
- Framework calls `DrawTab` / `DrawQuickContent`
- if `specialState.isDirty()` is true after draw, Framework calls `specialState.flushToConfig()`
- Framework then invalidates the cached hash and updates the HUD fingerprint

Standalone special-module flow:
- the module renders its own window
- after `DrawTab` / `DrawQuickContent`, the module should call `specialState.flushToConfig()` if dirty
- the module may use `lib.captureSpecialConfigSnapshot(...)` and `lib.warnIfSpecialConfigBypassedState(...)` in debug mode to detect direct config writes during draw

## Field type system

All field types live in the `FieldTypes` registry in `src/main.lua`. Each type implements:

| Method | Purpose |
|---|---|
| `validate(field, prefix)` | Declaration-time checks |
| `toHash(field, value)` | Serialize value to canonical hash string |
| `fromHash(field, str)` | Deserialize value from canonical hash string |
| `toStaging(val)` | Transform config value for managed special-state staging |
| `draw(imgui, field, value, width)` | Render the ImGui widget for regular-module options |

### Built-in field types

| Type | Widget | Notes |
|---|---|---|
| `checkbox` | `imgui.Checkbox` | `default` must be boolean |
| `dropdown` | `imgui.BeginCombo` | `values` must be a non-empty list of strings |
| `radio` | `imgui.RadioButton` | `values` must be a non-empty list of strings |
| `int32` | display only (no widget) | `default`, `min`, `max` must be numbers; value is clamped and floored |
| `stepper` | `-` / `+` buttons + text | `default`, `min`, `max` must be numbers; `step` optional positive number |
| `separator` | `imgui.Separator` | `label` optional; no `configKey`, not encoded in hash |

All string-valued types (`dropdown`, `radio`) reject values containing `|` since that character is used as the hash delimiter.

For `stepper`, the resolved step value is cached on `field._step` at `validateSchema` time to avoid recomputation every frame.

Note: special modules use field types as typed state descriptors for hashing and state management, but Framework does not render `stateSchema` fields automatically.

### Adding a new field type

Add one entry to the registry and all consumers pick it up automatically:

```lua
FieldTypes.mytype = {
    validate  = function(field, prefix) end,
    toHash    = function(field, value) return tostring(value) end,
    fromHash  = function(field, str) return str end,
    toStaging = function(val) return val end,
    draw      = function(imgui, field, value, width) ... end,
}
```

## Templates

The canonical templates live in the `h2-modpack-template` repo:
- `src/main.lua` - regular module starting point
- `src/main_special.lua` - special module starting point

## Standalone mode

Every module works without Core installed.
- Regular modules get a menu-bar toggle via `lib.standaloneUI()`
- Special modules render their own window and use `public.specialState` there too

When Core is installed, standalone UI is automatically suppressed.

## Debug system

Two distinct functions, two distinct purposes:

| Function | Purpose | Gated by |
|---|---|---|
| `lib.warn(packId, enabled, fmt, ...)` | Framework-detected problems such as schema errors, discovery errors, skipped modules | Caller-supplied coordinator debug flag |
| `lib.log(name, enabled, fmt, ...)` | Module author traces and debug warnings | Caller-supplied boolean, usually `config.DebugMode` |

Both functions accept printf-style arguments — string building is deferred past the gate, so no allocation occurs when disabled:

```lua
lib.warn(packId, config.DebugMode, "Skipping %s: missing id", modName)
lib.log("MyMod", config.DebugMode, "hook fired: value=%s", value)
```

Console output is visually distinct:

```text
[run-director] Skipping special foo: missing public.specialState
[MyMod] hook fired: value=Always
```

Module authors should use `lib.log(...)` for all intentional diagnostics. `lib.warn(...)` is for framework-level problems.
