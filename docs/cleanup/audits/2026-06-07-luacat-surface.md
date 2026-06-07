# LuaCAT Surface Audit

## Commands

```powershell
rg -n -e "^\s*---" src --glob "!def.lua"
rg -n -e "---@class|---@field|---@alias|---@param|---@return|---@type" src --glob "!def.lua"
```

## Decision

`src/def.lua` is the canonical author-visible LuaCAT surface. Implementation
files should not carry duplicate public type declarations or partial internal
type sketches because they are not the file authors consume and they drift from
the real API contract.

Implementation files may still use ordinary `--` comments for local code
clarity. `---@diagnostic` directives may remain when they configure tooling for
a file, because they are not API documentation.

## Edits

- Removed implementation-side `---@class`, `---@field`, `---@alias`,
  `---@param`, `---@return`, and related triple-dash doc blocks outside
  `src/def.lua`.
- Left `src/main.lua`'s `---@diagnostic disable: lowercase-global` directive in
  place.

## Result

The only LuaCAT API surface is `src/def.lua`. Implementation files now avoid
author-facing type noise and rely on normal code plus targeted comments for
local maintainability.
