# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.0.0] - 2026-04-20

Initial public release of the adamant Modpack Lib surface.

### Added

- managed module storage through `lib.createStore(config, definition, dataDefaults?)`
- explicit staged UI state through the returned `session`
- host-based module wiring through `lib.createModuleHost(...)`
- standalone window/menu hosting through `lib.standaloneHost(...)`
- lifecycle helpers under `lib.lifecycle.*`
- mutation helpers under `lib.mutation.*`
- hashing and packed-bit helpers under `lib.hashing.*`
- immediate-mode widget helpers under `lib.widgets.*`
- immediate-mode navigation helpers under `lib.nav.*`
- shared logging helpers under `lib.logging.*`
- managed storage support for:
  - `bool`
  - `int`
  - `string`
  - `packedInt`
- transactional session commit/resync support for host and framework flows
- coordinated-pack enable-state support through `lib.isModuleCoordinated(...)` and `lib.isModuleEnabled(...)`
- standalone and framework-friendly module authoring contract based on:
  - `public.definition`
  - `public.host`
  - direct draw functions such as `DrawTab(imgui, session)`

### Notes

- this release documents the current immediate-mode Lib contract
- legacy declarative UI authoring is not part of the supported public surface for this release

[unreleased]: https://github.com/h2-modpack/adamant-ModpackLib/compare/1.0.0...HEAD
[1.0.0]: https://github.com/h2-modpack/adamant-ModpackLib/compare/39bee9364299ddbc4447ec92c0e33662dbb43ab5...1.0.0
