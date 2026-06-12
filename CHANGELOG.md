# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [3.0.0] - 2026-06-12

### Breaking Changes

- lib: module.overlays.order.framework was replaced by module.overlays.order.system and module.overlays.order.modpack. (
1d9ce5)
- lib: lib.createFrameworkRuntime is no longer exported. (
2b56eb)
- modpack: Modpack profile hashes now emit _v=3. (
ec3892)
- lib: lib.createModule no longer accepts the config option. Module persistence is owned by the native backend and module-state creation takes backend options instead of a config table. (
58a7e7)
- lib: Generated internal storage/control config aliases now use (
6d5853)
- coordinator: coordinator registration now stores a display name for active packs. Clearing remains register(packId, nil). (
4caba5)

### Added

- modpack: bump hash version (
ec3892)
- lib: add native modpack runtime (
5e561c)
- lib: add modpack subsystem (
a59586)
- lib: use native module config backend (
58a7e7)
- lib: add native config backend (
e8d051)
- coordinator: add pack display names (
4caba5)

### Fixed

- lib: warn on volatile persistence (
3efc58)
- lib: stabilize config hydration (
6d5853)

### Changed

- storage: rename modpack restore marker (
895bbd)
- lib: retire Framework remnants (
1d9ce5)
- lib: remove Framework runtime (
2b56eb)

### Documentation

- lib: update modpack API docs (
7c340d)
- modpack: port coordinator guides (
a0c0d1)
- lib: define module test boundary (
387fe5)

## [2.0.0] - 2026-06-09

### Changed

- Storage declarations now use direct flat `alias` identifiers as the canonical managed storage backing keys.
- Removed old `configKey`, `lifetime`, `runtime`, and `stage` storage declaration compatibility in favor of explicit `persist` and `hash` axes.
- Lib now injects `Enabled` and `DebugMode` as built-in prepared storage aliases instead of requiring module-authored config defaults.
- Module definitions now require both stable `id` and display `name`; `modpack` remains optional.
- Module callbacks receive the narrow callback host consistently: UI callbacks receive `(host, ui)`, action handlers receive `(host, runtime, value)`, commit observers receive `(host, runtime, commit)`, and mutation patches receive `(host, runtime, plan)`.
- Runtime hooks are now declared through `module.hooks.*` before activation; the old ownerless `lib.hooks.*` registration surface and `createModule({ registerHooks = ... })` path have been removed.
- Shared events are now event-only: modules declare lifecycle-owned listeners with `module.shared.listen(...)`, emit from runtime through `runtime.shared.emit(...)`, and queue draw-time emits through `ui.shared.emit(...)`.
- Removed old provider/polling APIs, scoped reads, reserved `providerChanged` events, and draw-time `services.pollIntegration(...)`; declared shared values are now the supported read-sharing path.
- Retained module overlays are now declared with `module.overlays.*` before activation; the old `createModule({ registerOverlays = ... })` path has been removed.
- The global `lib.overlays.*` namespace has been removed; use `module.overlays.*`, `lib.createFrameworkRuntime(...).overlays`, or `lib.createFrameworkRuntime(...).ui` depending on the consumer.
- The global `lib.createSystem(...)` helper has been removed; Framework owns non-module overlays through `lib.createFrameworkRuntime(...).overlays`, while Lib system scopes remain internal.
- The global `lib.hashing.*` namespace has been removed; Framework consumes hashing through `lib.createFrameworkRuntime(...).hashing`.
- `module.hashGroups.define(...)` and `hashGroupPlan` have been removed; hash/profile output now uses semantic module/storage keys.
- The global `lib.config` export has been removed; Framework controls Lib diagnostics through `lib.createFrameworkRuntime(...).diagnostics`.
- The global `lib.getLiveModuleHost(...)` helper has been removed; Framework resolves live modules through `lib.createFrameworkRuntime(...).modules`.
- `lib.createFrameworkRuntime(...)` now requires the Framework plugin guid, while Framework overlays take the pack id at definition time to scope retained owners.
- Framework now consumes coordinator registration through `lib.createFrameworkRuntime(...).coordinator`, so coordinator mods can route pack registration through Framework.
- The global `lib.coordinator.*` namespace has been removed; Framework consumes coordinator registration through `lib.createFrameworkRuntime(...).coordinator`.
- The global `lib.resetStorageToDefaults(...)` helper has been removed; use draw-scoped `ui.resetAll(...)` in module UI code or Framework live-module reset helpers in orchestration code.
- Cache is now declared through `createModule({ cache = ... })` and accessed through phase-scoped `store.cache`; the old global and host cache surfaces have been removed.
- Added `mode = "runtime"` storage for runtime-owned values that draw state can read while staying outside staged writes and hash/profile flows.
- Added declared shared values for owner-published live read-model projections and cheap runtime/draw reads.
- Shared value table writes are copied once and reads return recursive read-only views.
- Modules can now declare managed cache refs in `createModule({ cache = ... })` and access them through phase-scoped `store.cache`; shared values remain available through `store.shared` and `state.shared`.
- `lib.createModule(...)` now accepts module definition fields directly; the old nested `definition = { ... }` option has been removed.
- Bound draw value widgets now target `StorageField` values from `state.get(...)` or table handles; root alias string targets and widget rebinding helpers have been removed.
- Draw `ui.data` exposes `get(alias)`, `read(alias, ...)`, and `write(alias, ...)`; module-wide draw resets go through `ui.resetAll(opts?)`.
- Module authors now receive a narrowed runtime `store` with `get(alias)` and `read(alias, ...)`; direct table/schema helpers remain internal Lib plumbing.
- The global `lib.widgets.*` and `lib.nav.*` namespaces have been removed; module draw callbacks use `draw.widgets.*` and `draw.nav.*`.
- The global `lib.imguiHelpers.*` namespace has been removed; Framework and Lib keep their low-level ImGui binding helpers private.
- Session and commit action compatibility helpers have been removed; draw code stages transient intent through `ui.actions.get(...)`, and commit observers read through `commit.actions.get(...)`.
- Draw action handlers now receive `(host, runtime, value)`, making actions the sanctioned UI-to-runtime command bridge for post-draw handlers.
- Shared event delivery now skips disabled listener hosts, queues nested emits, and continues after listener failures.
- Store, draw state, draw actions, widgets, nav, and draw-safe logging are now phase-gated at their author-facing surfaces.
- Fallback UI now matches Framework module tabs by collapsing module draw content while the module is disabled.
- Module authors now construct through `lib.createModule(...)` and activate through `module.activate()`; lower-level definition/state/host construction is internal.
- Cache, shared events, hooks, and similar capability modules now return named service/author/public bundles where applicable so backend services, host facades, and remaining `lib.*` exports stay separated.
- Host activation now stages and commits hooks, shared events, overlays, and mutation sync through host-owned receipts, so omitted registrations are removed on reload and activation failures roll back candidate effects.
- `module.hooks.override(...)` accepts function replacements only, matching the host-owned dispatcher model.
- Retired separate internal lifecycle design notes; accepted lifecycle tradeoffs now live in `docs/references/KNOWN_LIMITATIONS.md`.
- Removed persistent cache; runtime markers now use `mode = "runtime"` storage and `runtime.data.runtimeOwned`.
- Added first-class table storage roots with row-scoped aliases, staged table handles, read-only store table handles, packed child row access, and hash/profile serialization.
- Table storage handles use colon method syntax, such as `tiers:read(rowIndex, alias)`.

## [1.1.0] - 2026-05-05

### Added

- Added `lib.prepareDefinition(...)` as the canonical definition-preparation step before store and host creation.
- Added a LuaLS public definition file at `src/def.lua` for the Lib module export, storage/session types, module host contract, lifecycle helpers, mutation plans, widgets, nav, hooks, shared events, hashing, logging, and ImGui helpers.
- Added Lib-owned live-module publication and lookup through `lib.getLiveModuleHost(...)`.
- Added reload-stable ModUtil hook registration through `lib.hooks.Wrap(...)`, `lib.hooks.Override(...)`, and `lib.hooks.Context.Wrap(...)`.
- Added coordinated pack rebuild callbacks through `lib.coordinator.registerRebuild(...)` and `lib.coordinator.requestRebuild(...)`.
- Added optional cross-module integration registration through `lib.integrations.*`.
- Added `lib.imguiHelpers.*` enum/value helpers for low-level ImGui binding use.
- Added `lib.overlays.*` retained HUD overlay helpers with managed `middleRightStack` layout, stacked text, stacked rows, and framework/module/debug order bands.
- Added token-based `lib.overlays.suppressForUi()` overlay suppression for foreground ImGui configuration windows.
- Added global helpers for namespaced runtime cache attached to live game tables.
- Added runtime-only persisted storage aliases through `runtime = true` plus `store.getRuntimeState()`.
- Added `definition.onSettingsCommitted(host, store, commit)` as a post-commit observer for rebuilding derived runtime/UI structures after staged config commits and staged session actions.
- Added docs for hot-reload architecture and known limitations under `docs/`.
- Added player-facing `THUNDERSTORE_README.md` packaging support.

### Changed

- Module authoring now uses the explicit `prepareDefinition(...) -> createModuleState(...) -> createModuleHost(...)` flow.
- Effective storage defaults are hydrated during definition preparation, before structural fingerprinting.
- Structural definition changes are fingerprinted separately from behavior-only changes.
- Coordinated modules can request a Framework rebuild when structural definition shape changes during hot reload.
- `createModuleHost(...)` now owns live-module publication and requires `drawTab`.
- Public module host surface was narrowed around stable host accessors and behavior calls; direct raw definition access was removed.
- `createModuleHost(...)` and fallback UI now require an explicit plugin guid captured at module load time.
- Manual lifecycle hooks now receive the active author host and runtime store as `apply(host, store)` and `revert(host, store)`.
- Mutation lifecycle state is tracked by stable module identity where available, making reload/reapply behavior more robust.
- Host startup sync now reverts active tracked mutation state when a module reloads disabled.
- Store creation now requires prepared definitions with explicit storage.
- Runtime-only storage aliases are excluded from session staging, profile/hash surfaces, and whole-session reset flows.
- Host `writeAndFlush(...)` and `flush()` now notify `onSettingsCommitted` after successful dirty commits.
- The fallback HUD marker now participates in the shared overlay layout instead of owning a separate HUD placement path.
- Fallback module UI now suppresses Lib overlays while open and restores them on close after pending runtime flushes.
- Internal helper duplication was consolidated into shared internal value/store utilities.
- Widget packed dropdown/radio helpers avoid repeated packed-choice classification work per frame.
- Long-form guides and reference docs now live under `docs/`.
- Packaged README content moved out of `src/README.md`; package metadata now points at `THUNDERSTORE_README.md`.

### Fixed

- Fixed fallback/coordinated checks to read persistent coordinator state instead of transient captured tables.
- Fixed fallback HUD marker hook registration so it no longer stacks raw ModUtil wraps across reloads.
- Fixed manual mutation lifecycle paths so manual `apply`/`revert` receive the store consistently.
- Fixed storage default fingerprinting so config default changes are part of the structural contract.
- Fixed string hash serialization by escaping reserved token characters inside persisted keys and values.
- Fixed rebuild-request handling so rejected coordinator rebuild callbacks are not reported as successful.

### Documentation

- Expanded `API.md` to describe the current public Lib surface.
- Updated module authoring docs around prepared definitions, Lib-owned host publication, fallback UI, lifecycle behavior, hooks, shared events, widgets, and hash helpers.
- Updated hot-reload docs around author-facing module reload support and infrastructure reload limitations.
- Moved known limitations into Lib docs so shared modpack constraints have one home.

### Tests

- Expanded test coverage for prepared definitions, lifecycle validation, stores/sessions, hooks, hashing, logging, mutation plans, nav, widgets, shared events, fallback UI, and host publication.

## [1.0.0] - 2026-04-20

Initial public release of the adamant Modpack Lib surface.

### Added

- managed module storage through `lib.createModuleState(config, definition)`
- explicit staged UI state through the returned `session`
- host-based module wiring through `lib.createModuleHost(...)`
- standalone window/menu hosting through `lib.standaloneHost(...)`
- coordinator helpers under `lib.coordinator.*`
- mutation helpers under `lib.mutation.*`
- hashing and packed-bit helpers under `lib.hashing.*`
- immediate-mode widget helpers under `lib.widgets.*`
- immediate-mode navigation helpers under `lib.nav.*`
- managed storage support for:
  - `bool`
  - `int`
  - `string`
  - `packedInt`
- transactional session commit/resync support for host and framework flows
- coordinated-pack enable-state support through `lib.coordinator.isRegistered(...)` and `host.isEnabled()`
- standalone and framework-friendly module authoring contract based on:
  - `public.definition`
  - `public.host`
  - direct draw functions such as `DrawTab(imgui, session, host)`

### Notes

- this release documents the current immediate-mode Lib contract
- legacy declarative UI authoring is not part of the supported public surface for this release

[unreleased]: https://github.com/h2-modpack/adamant-ModpackLib/compare/2.0.0...HEAD
[2.0.0]: https://github.com/h2-modpack/adamant-ModpackLib/compare/1.1.0...2.0.0
[1.1.0]: https://github.com/h2-modpack/adamant-ModpackLib/compare/1.0.0...1.1.0
[1.0.0]: https://github.com/h2-modpack/adamant-ModpackLib/compare/39bee9364299ddbc4447ec92c0e33662dbb43ab5...1.0.0
