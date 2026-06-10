# Chalk String Config Note

This note records the current understanding of a Chalk-side config issue that
affects Lib backend design. It is intentionally separate from the implementation
plan because the root fix belongs upstream in `SGG_Modding-Chalk`, and any PR may
take time to review and publish.

## Short Version

Chalk writes `.cfg` string values in a form that is not valid TOML, but then
tries to preload the same `.cfg` through `rom.toml.decodeFromFile`. When that
TOML decode fails, Chalk can fall back to merging only defaults, which risks
resetting existing user config values.

Strings are currently stored like this:

```toml
# Setting type: string
# Default value: I
_DreamRoute-Biome2 = I
```

but TOML decoding expects string values to be quoted:

```toml
# Setting type: string
# Default value: "I"
_DreamRoute-Biome2 = "I"
```

The actual value line matters most. The `# Default value:` comment is useful
evidence in generated files, but the parser failure is caused by the unquoted
assignment value.

## Important Correction

This does not mean strings never load. They can still load correctly through
`rom.config.config_file:new(path, true)`, which is the real `.cfg` backend.

The issue is narrower:

1. Chalk first tries `rom.toml.decodeFromFile(path)`.
2. Bare string values can make that TOML decode fail.
3. Chalk still opens the `.cfg` through `rom.config.config_file:new(path, true)`.
4. If a Lua default table exists, the failed TOML preload can put Chalk on a
   default-only merge path.
5. That merge path can overwrite existing entries with default values.

So the observed problem is not "strings always default." The risk is
"TOML-preload failure can make default merging destructive even though the `.cfg`
backend itself may have been able to read the existing string entries."

## Chalk Code Shape

In Chalk 2.1.1, `public.load` attempts TOML preload first:

```lua
local success, data = pcall(rom.toml.decodeFromFile, path)
if success then
    loaded = select(2,next(data))
end
```

It then creates the `.cfg` backend:

```lua
local config = rom.config.config_file:new(path, true)
```

If `loaded` is nil and a Lua default table exists, Chalk merges defaults:

```lua
elseif default ~= nil then
    return public.merge(config, default, descript, section)
end
```

`merge` writes flat values with `config:bind(...)` when missing, but calls
`c:set(v)` when an entry already exists:

```lua
if c == nil then
    config:bind(section,k,v,d or '')
else
    c:set(v)
end
```

That makes the TOML preload result important. If preload fails, user values that
exist in the `.cfg` backend may still be overwritten by defaults.

## Targeted Chalk Fix

The smallest safe Chalk-side fix is not to make strings load through TOML at all
costs. The safer behavior is:

- If TOML preload succeeds, keep the existing behavior.
- If TOML preload fails but `config_file:new(path, true)` exposes existing
  entries, do not run the normal overwriting default merge.
- Instead, merge missing defaults only.

The shape is:

```lua
local success, data = pcall(rom.toml.decodeFromFile, path)
local loaded
if success then
    loaded = select(2, next(data))
end

local config = rom.config.config_file:new(path, true)

if loaded ~= nil and default ~= nil then
    -- existing behavior
elseif loaded ~= nil then
    -- existing behavior
elseif default ~= nil then
    if not success and has_existing_entries(config) then
        return public.merge_missing(config, default, descript, section)
    end
    return public.merge(config, default, descript, section)
else
    return public.wrapper(config), config
end
```

`merge_missing` should recursively bind missing defaults without calling `set` on
existing entries.

## Larger Chalk Fix

A broader fix would make generated `.cfg` string values TOML-decodable. That
sounds simple but may be less targeted because the actual file writer is
`rom.config.config_file`. If Chalk passes quoted strings as stored values, the
runtime value may become `"I"` rather than `I` unless Chalk also adds a decode
layer.

For this reason, the targeted non-destructive fallback is the lower-risk upstream
fix.

## Lib Interim Stance

Until Chalk is fixed and released, Lib should not depend on TOML preload
succeeding for string-heavy configs.

Practical guidance:

- Prefer int-backed controls for closed option sets such as dropdowns, radios,
  mode selects, god choices, and biome choices.
- Reserve string storage for real free text or externally meaningful identifiers.
- Treat `rom.config.config_file` as the runtime source of truth where possible.
- Avoid Lib workarounds that quote strings naively; they can change runtime
  values or oscillate when Chalk rewrites the file.

This does not require immediate broad migration, but new controls should prefer
numeric persisted values when the value set is closed and stable.
