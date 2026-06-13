# Lib Internals

Contributor rules for Lib's internal composition model.

Lib uses explicit dependency composition rather than a broad internal bus.
`core/init.lua` is the composition root: it constructs or imports subsystem
services, captures the service objects that later subsystems need, and passes
targeted dependencies through import args. Persistent globals are reserved for
hot-reload-stable runtime anchors.

## Returned Service Surface

- Return a service object only when downstream Lib code needs a service from the subsystem.
- Public-only modules should assign their public table and return nothing.
- A public object may be returned to its immediate subsystem composer for local fan-out, but it should not be captured by `core/init.lua` as a Lib-wide service.
- Mixed modules should keep public-only functions off the returned service.
- The returned object is the real internal subsystem surface, not automatically the public API surface.
- Define exported behavior directly on the service table:

```lua
function service.doThing(...)
    ...
end
```

- Do not write a local function only to immediately assign it onto the service table unless that local is genuinely private.
- Keep returned services behavior-focused. Do not expose private storage tables only because tests want to inspect or mutate them.

## Private State

- Subsystem state is private by default.
- Configuration defaults belong in their source files. If a source file changes, a new import should rebuild from that source.
- Do not preserve runtime state across Lib re-imports unless it is a real lifetime anchor.
- Comment only actual persistence anchors: owner identities, hook/overlay lifecycle state, runtime registries, or other tables whose identity must survive.
- `core/init.lua` owns creation of `AdamantModpackLib_Runtime`; `core/lib_bootstrap/registry.lua` is the only file that shapes Lib-owned root registry buckets below it.
- Keep persistent runtime registries under `AdamantModpackLib_Runtime.registry.<subsystem>`. The root registry creates only subsystem buckets; each subsystem owns the leaf tables inside its bucket.
- Runtime tables closed over by installed game/ModUtil callbacks are legitimate hot-reload anchors, but should still be owned by a scoped registry bucket rather than a broad dependency bus.
- Runtime tables that keep active plans/receipts revertible across Lib re-imports are also real anchors; keep them under the scoped registry bucket and comment the reason.
- Weak implementation side tables and rebuildable caches, like module-state backend/store side tables, should stay local to the service import rather than living under `AdamantModpackLib_Runtime`.
- Live-module, pending-rebuild, and weak module-record tables are activation anchors; keep the tables under `AdamantModpackLib_Runtime.registry.modules`, but keep lifecycle behavior on the returned `managedModule` service.
- Fallback UI bridges and GUI-close callbacks are runtime anchors because external callers keep their handles; keep live fallback UI runtimes under `AdamantModpackLib_Runtime.registry.fallback`, and make callbacks late-read that table.

## Temporary Internal Bridges

- The retired Lib internal namespace should stay retired.
- Do not add new mirror assignments for ordinary services.
- If a future transition genuinely needs a temporary bridge, keep it explicitly short-lived, behavior-only, and remove it before the subsystem is considered clean.

## Dependency Flow

- `core/init.lua` should capture each returned subsystem object.
- Later subsystems should receive named dependency objects through import args.
- Do not reach back into global namespaces for ordinary services once a dependency can be passed explicitly.
- Pass targeted services, not broad context blobs.
- If a subsystem needs behavior that also has a public API, put the behavior on a named service and let the public API call it; do not call `public.*` from another Lib subsystem.

## Tests

- Tests should mirror the subsystem dependency graph where practical.
- A subsystem is not clean if its tests depend on retired internal-bus surfaces for that subsystem.
- Do not add production APIs only for tests.
- If tests need alternate dependency behavior, mock the import or dependency in the test harness.
- Use grep to verify retired names are gone from `src` and `tests`.

## Validation

For each leaf cleanup:

1. Run targeted tests for the touched subsystem.
2. Run the full Lib suite.
3. Run the repo-level `ModpackTools/run ModpackTools/local_test/all.py`.
4. Run `git diff --check`.
5. Search for stale internal-bus references before moving on.
