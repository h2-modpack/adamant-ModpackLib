# Lib Contributor Docs

Use these docs when changing ModpackLib itself.

Recommended order:

1. [../../CONTRIBUTING.md](../../CONTRIBUTING.md)
2. [LIB_INTERNALS.md](LIB_INTERNALS.md)
3. [HOT_RELOAD_ARCHITECTURE.md](HOT_RELOAD_ARCHITECTURE.md)
4. [CACHE_OBJECT_DESIGN.md](CACHE_OBJECT_DESIGN.md)
5. [TESTING.md](TESTING.md)

For public API behavior, use [../../API.md](../../API.md).

Future design notes live under [future-ideas](future-ideas/). They are not
accepted implementation plans unless a specific note says otherwise.

## Host Vocabulary

Use these terms consistently in contributor docs and implementation notes:

- `ModuleHost`: the full Lib object created by `moduleHost.create(...)`. It is
  the Framework/runtime surface for discovery, draw dispatch, staged writes,
  commit, enable/disable, mutation apply/revert, activation, rollback, and live
  host publication.
- `live module host`: an activated `ModuleHost` published in Lib's live-host
  registry and consumed by Framework or fallback UI.
- `AuthorHost`: the module-facing facade returned by `lib.createModule(...)`
  and passed to authored callbacks. It exposes author-safe identity, metadata,
  activation, logging, and future host-owned capability namespaces.
- `lifecycle`: a responsibility of `ModuleHost`, not the canonical type name.

Runtime identity uses `pluginGuid`. Pack id and module id are Lib/Framework
domain metadata used for coordination, profiles, hashes, labels, and debug
translation. The low-level `lib_bootstrap/registry` service owns Lib's
hot-reload-stable root buckets. The host bucket currently includes live-host
lookup, plugin metadata, and the backing weak side table used by
`lib_bootstrap/host_registry`.

Capability backends use `ownerId`, not `pluginGuid`. `pluginGuid` belongs at
the module bootstrap/runtime/host-adapter boundary. Once a capability call
crosses into stateless subsystem logic, the value is only a unique owner id.
Module-host adapters derive `ownerId` from `host.getHostId()`; system adapters
receive an explicit `ownerId` from the managed system scope.

System scopes are Lib-created owner objects for first-party behavior that is
not owned by a module host. They close over explicit owner ids and do not own
module host records. System owner ids must be deliberately scoped, such as
`adamant-lib.overlays.renderer` or `adamant-framework.<pack>.hud`, so they do
not collide with module plugin guids or with other system capabilities.

Module author docs can simply call the returned `AuthorHost` `host`. Framework
and Lib contributor docs should say `ModuleHost` or `live module host` when they
mean the full runtime surface.
