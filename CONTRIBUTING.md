# Contributing to adamant-Lib

Shared utility library for all adamant modpack modules. Provides the module contract, UI primitives, state management, and field type system.

## Architecture

Single-file library (`src/main.lua`) loaded as `adamant-Modpack_Lib`. Modules access it with:

```lua
local lib = rom.mods['adamant-Modpack_Lib']
```

## Public API

| Function | Purpose |
|---|---|
| `lib.isEnabled(modConfig)` | True if module + master toggle are both on |
| `lib.warn(msg)` | Debug-guarded print (requires Core's DebugMode) |
| `lib.createBackupSystem()` | Returns `backup, revert` for isolated state save/restore |
| `lib.standaloneUI(def, config, apply, revert)` | Returns menu-bar callback for standalone mode |
| `lib.readPath(tbl, key)` | Read from table using string or path key |
| `lib.writePath(tbl, key, value)` | Write to table using string or path key |
| `lib.encodeField(field, value, addBits)` | Encode a field into a bit stream |
| `lib.decodeField(field, readBits)` | Decode a field from a bit stream |
| `lib.drawField(imgui, field, value, width)` | Render a field widget, returns `(newValue, changed)` |
| `lib.validateSchema(schema, label)` | Validate field descriptors at declaration time |
| `lib.createSpecialState(config, schema)` | Returns `staging, snapshot, sync` for special modules |
| `lib.FieldTypes` | The field type registry table |

## Module contract

Every module must expose `public.definition`:

```lua
public.definition = {
    id           = "MyMod",        -- unique key (hash-stable)
    name         = "My Mod",       -- display name
    category     = "Bug Fixes",    -- tab label in Core UI, e.g. "Bug Fixes" | "Run Modifiers" | "QoL"
    group        = "General",      -- UI group header
    tooltip      = "...",          -- hover text
    default      = true,           -- default Enabled value
    dataMutation = true,           -- true if apply() changes game tables
}

public.definition.apply  = apply   -- mutate game state
public.definition.revert = revert  -- restore vanilla state
```

- `apply` is called when the module is enabled
- `revert` is called when disabled (typically the closure from `createBackupSystem`)
- Core wraps both in pcall -- a failing module won't crash the framework

### Inline options (optional)

Boolean modules can declare options rendered below their checkbox:

```lua
public.definition.options = {
    { type = "checkbox", configKey = "Strict", label = "Strict Mode", default = false },
    { type = "dropdown", configKey = "Mode",   label = "Mode",
      values = {"Vanilla", "Always", "Never"}, default = "Vanilla" },
}
```

`configKey` can be a string (`"Mode"`) or a table path (`{"Parent", "Child"}`) for nested config. Hash bits are auto-calculated from `#values` when `field.bits` is omitted.

### Special modules

Special modules get their own sidebar tab and custom state:

```lua
public.definition.special    = true
public.definition.tabLabel   = "Hammers"
public.definition.stateSchema = { ... }  -- field descriptors for hashing

public.SnapshotStaging = snapshotStaging  -- re-read config into staging
public.SyncToConfig    = syncToConfig     -- flush staging to config

function public.DrawTab(imgui, onChanged, theme) ... end
function public.DrawQuickContent(imgui, onChanged, theme) ... end
```

## Field type system

All field types live in the `FieldTypes` registry in main.lua. Each type implements:

| Method | Signature | Purpose |
|---|---|---|
| `bits(field)` | `-> number` | Number of bits for hash encoding |
| `validate(field, prefix)` | | Declaration-time checks |
| `encode(field, value, addBits)` | | Write value into bit stream |
| `decode(field, readBits)` | `-> any` | Read value from bit stream |
| `toStaging(val)` | `-> any` | Transform config value for staging table |
| `draw(imgui, field, value, width)` | `-> newValue, changed` | Render the ImGui widget |

### Adding a new field type

Add one entry to the registry -- all consumers (encoding, decoding, UI, validation, staging) pick it up automatically:

```lua
FieldTypes.mytype = {
    bits     = function(field) return field.bits or 1 end,
    validate = function(field, prefix) end,
    encode   = function(field, current, addBits) ... end,
    decode   = function(field, readBits) ... end,
    toStaging = function(val) return val end,
    draw     = function(imgui, field, value, width) ... end,
}
```

## Templates

The canonical templates live in the [h2-modpack-template](https://github.com/h2-modpack/h2-modpack-template) repo:

- `src/main.lua` -- boolean module starting point
- `src/main_special.lua` -- special module starting point

Copy the relevant template as `src/main.lua` in a new mod repo and fill in the marked sections.

## Standalone mode

Every module works without Core installed. Boolean modules get a menu-bar toggle via `lib.standaloneUI()`. Special modules render their own ImGui window. When Core is installed, standalone UI is automatically suppressed.
