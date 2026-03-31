# Changelog

## [Unreleased]

### Added
- `isFieldVisible(field, values)` - returns true when `field.visibleIf` is absent or its referenced key is true; used by Framework option rendering and `standaloneUI`
- `int32` field type - numeric value with `min`/`max`/`default`, clamped and floored, display-only widget
- `stepper` field type - `-`/`+` button widget with `min`/`max`/`step`/`default`; step resolved to integer
- `separator` field type - horizontal separator line with optional label, not encoded in hash

### Changed
- `warn(packId, enabled, fmt, ...)` and `log(name, enabled, fmt, ...)` now accept printf-style arguments; string building is deferred past the enabled gate, eliminating string allocation when disabled
- `backup(tbl, ...)` vararg iteration now uses `select('#', ...)` / `select(i, ...)` instead of `{...}` table allocation
- `validateSchema` now caches `field._schemaKey` (stable hash key for path-style configKeys) and `field._imguiId` (ImGui widget ID) on each field descriptor at declaration time
- `stepper` validate now caches `field._step` (resolved integer step) at declaration time, removing per-frame recomputation
- `stepper` draw now caches `field._lastStepperStr` / `field._lastStepperVal` to avoid `tostring()` allocation every frame
- `captureSpecialConfigSnapshot` and `warnIfSpecialConfigBypassedState` use `field._schemaKey` instead of recomputing the key on every call

### Added (initial release)
- `createBackupSystem()` - isolated backup/revert with first-call-only semantics
- `createSpecialState()` - managed `specialState` object for special modules
- `standaloneUI()` - menu-bar toggle callback for regular modules running without Core
- `isEnabled()` - checks module config and coordinator master toggle
- `readPath()` / `writePath()` - string and table-path accessors for nested config keys
- `drawField()` - ImGui widget renderer delegating to the FieldTypes registry
- `validateSchema()` - declaration-time field descriptor validation
- `captureSpecialConfigSnapshot()` / `warnIfSpecialConfigBypassedState()` - debug helpers for detecting schema-backed config writes outside `public.specialState`
- FieldTypes registry with `checkbox`, `dropdown`, and `radio` types
- Luacheck linting on push/PR
- Unit tests for field types, path helpers, validation, backup system, special state, and isEnabled (LuaUnit, Lua 5.1)
- Branch protection on `main` requiring CI pass

[Unreleased]:
