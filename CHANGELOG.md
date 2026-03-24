# Changelog

## [Unreleased]

### Added
- Initial release of adamant-Modpack_Lib shared library
- `createBackupSystem()` — isolated backup/revert with first-call-only semantics
- `createSpecialState()` — staging table, `SnapshotStaging`, and `SyncToConfig` for special modules
- `standaloneUI()` — menu-bar toggle callback for modules running without Core
- `isEnabled()` — checks module config and Core master toggle
- `warn()` — debug-guarded print (requires Core's DebugMode flag)
- `readPath()` / `writePath()` — string and table-path accessors for nested config keys
- `encodeField()` / `decodeField()` — bit-stream field encoding for config hashing
- `drawField()` — ImGui widget renderer delegating to the FieldTypes registry
- `validateSchema()` — declaration-time field descriptor validation
- FieldTypes registry with `checkbox`, `dropdown`, and `radio` types
- Luacheck linting on push/PR
- Unit tests for field types, path helpers, validation, backup system, special state, and isEnabled (LuaUnit, Lua 5.1)
- Branch protection on `main` requiring CI pass


[Unreleased]:

