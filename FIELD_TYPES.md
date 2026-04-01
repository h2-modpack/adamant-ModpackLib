# Field Types in adamant-ModpackLib

This document defines the field type contract used by Lib and Framework.

Field types are not only UI widgets. They participate in:

- declaration validation
- hash serialization
- hash deserialization
- special-module staging
- regular-module option rendering

That means a field type is part of both runtime behavior and compatibility behavior.

## Registry

Field types live in the `FieldTypes` registry in `src/main.lua` and are exposed as:

```lua
local lib = rom.mods["adamant-ModpackLib"]
local FieldTypes = lib.FieldTypes
```

Treat `lib.FieldTypes` as Lib-owned infrastructure. Extending it deliberately is supported.
Mutating existing built-in behavior casually is not.

## Required Methods

Every field type must provide all of these methods:

| Method | Purpose |
|---|---|
| `validate(field, prefix)` | Declaration-time checks and normalization |
| `toHash(field, value)` | Encode runtime value to canonical hash string |
| `fromHash(field, str)` | Decode string from hash back to runtime value |
| `toStaging(val)` | Convert persisted config value into special-state staging value |
| `draw(imgui, field, value, width)` | Render regular-module widget and return `(newValue, changed)` |

If a type is missing required methods, later consumers will be inconsistent or fail.

## Where Each Method Is Used

### `validate(field, prefix)`

Used by `lib.validateSchema(...)` to validate and normalize declarations.

Typical responsibilities:

- ensure required properties exist
- ensure types are correct
- reject invalid value sets
- cache normalized runtime metadata on the field when appropriate

Example:

- `stepper` resolves and caches `field._step`

### `toHash(field, value)`

Used during hash creation.

Requirements:

- return a canonical string representation
- keep formatting stable across releases unless you are doing ABI work
- do not include the top-level `|` delimiter in encoded string values

### `fromHash(field, str)`

Used during hash decode.

Requirements:

- parse the string form produced by `toHash(...)`
- degrade predictably on invalid input
- preserve compatibility expectations for old hashes where applicable

### `toStaging(val)`

Used when special modules build managed `specialState.view` from persisted config.

Requirements:

- return the staging representation used by special-module UI code
- avoid sharing mutable tables unexpectedly
- treat the returned value as UI-owned staged state

Most simple scalar types return the value unchanged.

### `draw(imgui, field, value, width)`

Used only for regular-module hosted and standalone option rendering.

Requirements:

- render the widget for the field
- return `(newValue, changed)`
- do not mutate module store/config directly from inside the field type
- keep the behavior aligned with `validate`, `toHash`, and `fromHash`

Note:

- special module `stateSchema` fields use field types for typing, validation, and hashing
- Framework does not auto-render special schema fields through `draw(...)`

## Built-in Types

### `checkbox`

- widget: `imgui.Checkbox`
- `default` must be boolean
- hash form should remain stable boolean string encoding

### `dropdown`

- widget: `imgui.BeginCombo`
- `values` must be a non-empty list of strings
- values containing `|` are invalid because `|` is the hash delimiter
- decode should fall back safely when the incoming value is not in `values`

### `radio`

- widget: `imgui.RadioButton`
- same value constraints and hash considerations as `dropdown`

### `int32`

- no normal interactive widget in hosted options
- `default`, `min`, and `max` must be numbers
- values are clamped and floored

### `stepper`

- widget: decrement/increment buttons plus text
- `default`, `min`, and `max` must be numbers
- `step` is optional and must be positive when present
- resolved step is cached on `field._step`

### `separator`

- widget: `imgui.Separator`
- `label` optional
- no `configKey`
- not encoded into hash
- not part of schema-backed state

## Compatibility Rules

Field types are part of the hash/profile ABI.

Changing any of these can be compatibility work:

- `toHash(...)`
- `fromHash(...)`
- accepted value set for string-backed enums
- normalization behavior that changes what values are considered default-equivalent

Treat serialization behavior as frozen after release unless you are intentionally doing migration
work.

See [HASH_PROFILE_ABI.md](../adamant-ModpackFramework/HASH_PROFILE_ABI.md) for the broader ABI policy.

## Invalid Field Types

Current system behavior:

- unknown field types warn during validation
- invalid fields are excluded from schema-backed processing
- hash encode warns and skips invalid fields
- hash decode warns and defaults rather than crashing

This means invalid declarations degrade safely, but they are still authoring errors that should be
fixed.

## Adding a New Field Type

Minimum skeleton:

```lua
FieldTypes.mytype = {
    validate = function(field, prefix)
    end,

    toHash = function(field, value)
        return tostring(value)
    end,

    fromHash = function(field, str)
        return str
    end,

    toStaging = function(val)
        return val
    end,

    draw = function(imgui, field, value, width)
        return value, false
    end,
}
```

Before adding one, decide all of:

1. What is the canonical hash encoding?
2. What is the decode fallback behavior?
3. What is the staging representation?
4. Is the rendered value shape the same as the staged value shape?
5. What declaration-time properties must be validated?

If those are not explicit up front, the type will be brittle.

## Authoring Guidelines

### Keep encode/decode symmetric

`fromHash(toHash(x))` should recover the intended runtime value for supported inputs.

### Prefer canonical encodings

Do not emit multiple string forms for the same logical value unless you deliberately need decode
compatibility for older hashes.

### Avoid hidden mutation in `draw(...)`

The field type should report value changes, not mutate store/config directly.

### Normalize at validation time when practical

If a derived property is used every frame, compute and cache it during `validate(...)`.

### Be careful with mutable staging values

If `toStaging(...)` returns a table, make sure special-state staging does not accidentally share a
mutable object across fields or modules.

## Descriptor Mutation and Caches

Lib and Framework mutate field descriptors in place with runtime metadata such as:

- `_imguiId`
- `_schemaKey`
- `_hashKey`
- `_pushId`
- `_step`

That means field descriptor tables are not immutable pure declarations after validation/discovery.

Practical rule:

- declare field tables fresh
- do not share one descriptor table between unrelated modules or schemas
- do not mutate cached metadata from module code

## What Not to Do

Do not:

- hand-roll partial field types with only `draw(...)`
- change built-in `toHash/fromHash` casually after release
- assume special modules render through `draw(...)`
- reuse descriptor tables across modules to “save boilerplate”
- treat `lib.FieldTypes` as arbitrary mutable shared state

## Recommended Test Coverage for New Types

At minimum, test:

1. validation accepts good declarations
2. validation rejects bad declarations
3. `toHash(...)` output is canonical
4. `fromHash(...)` handles invalid input safely
5. `toStaging(...)` produces the expected staged value
6. `draw(...)` returns correct `(newValue, changed)` semantics
7. old and new hash values remain compatible if you changed an existing type
