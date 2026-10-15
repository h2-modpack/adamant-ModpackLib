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
- Live-module and weak module-record tables are activation anchors under `AdamantModpackLib_Runtime.registry.modules`. `module_registry` is their only surface: `getRecord`/`setRecord` and `getLiveModule`/`setLiveModule`.
- Hotkey installs, ownership history, pushed pack order, and the shared always-draw tick live under `AdamantModpackLib_Runtime.registry.hotkeys` (`core/hotkeys/00_init.lua`). The tick is registered once and late-reads `dispatch`; the resolved view (status tables, dispatch list, overview rows) is a rebuildable cache local to the import.
- Lib's settings window callback lives under `AdamantModpackLib_Runtime.registry.ui` (`libWindowRegistered`, `renderLibWindow`); it is registered once and late-reads the renderer.
- Fallback UI bridges and GUI-close callbacks are runtime anchors because external callers keep their handles; keep live fallback UI runtimes under `AdamantModpackLib_Runtime.registry.fallback`, and make callbacks late-read that table.

## Composition Root

`core/init.lua` imports every subsystem once, in dependency order, and passes
each one the named services it needs. It also composes the module capability
list and hands it to `managed_module_activation.lua`; add a capability by adding
an install function there, not by editing activation.

Stateless helpers shared across subsystems live in `core/helpers/` and are
imported once by `init.lua`, then passed down:

- `values.lua`: deep copy and value equality.
- `receipt.lua`: capability install receipts (below).
- `identifiers.lua`: stable identifier validation shared by storage, controls, status, and shared declarations.
- `method_self.lua`: `requireMethodSelf` for `ref:method()` misuse checks.

`core/ui/` holds UI pieces shared by the fallback window and the modpack window:
`theme.lua`, `session.lua` (deferred run-data rebuild, overlay suppression
token, GUI-close edge), `status_colors.lua`, `module_frame.lua` (the shared
module frame: Enabled, optional header, module tabs, Lib's Hotkeys & Advanced
tab; each host passes its own enable/debug/resync/commit paths as `ops`), and
`lib_window.lua` (Lib's `adamant-lib` settings window: Hotkeys and Debug tabs).

## Capability Installs And Receipts

Every capability install takes explicit inputs and returns a receipt built by
`helpers/receipt.lua` (`receipt.create`, `receipt.noop`, `receipt.composite`),
or nil when the module declares nothing for it:

- `hooks.install(ownerId, ownerToken, declarations)`
- `shared.install(ownerId, { data, events })`
- `overlays.install(ownerId, { owner, declarations, host, runtime })`
- `mutation.bind(ownerId, bundle, host, runtime).sync()`
- `fallbackUi.install(ownerId, owner)`
- `hotkeys.install(ownerId, { requests, host, runtime, readCommitted })`

Receipt contract:

- `commit()` applies the install once; repeating it after success is a no-op.
- `rollback()` undoes the install and restores what it replaced. Activation uses it when a later step fails.
- `retire()` removes only what this install still owns and never restores replaced state. Activation uses it on the previous module after its successor committed.
- An optional `discard` runs instead of rollback/retire when the receipt never committed, to drop install-time staging.
- Rollback and retire run at most once; callbacks are pcall-wrapped and report `ok, err`.
- `phase` orders commits: `receipt.PHASE_GAME_DATA` (mutations) before `receipt.PHASE_EFFECTS` (everything else). Release runs in reverse commit order.

Capabilities never read the module record.

## Module Layer

- The declaration facade (`module/declaration_facade.lua`) is the builder: it collects declarations and tracks only `sealing` plus the instance it produced. `module/activation_finalizer.lua` compiles the declarations, prepares the definition, builds module state, creates the instance, and activates it.
- `managedModule.create` builds the instance from Lib-built inputs only (finalizer or test harness), so it asserts invariants instead of re-validating options. Identity on both the facade and the instance comes from `identity.lua`.
- The record (`module_registry.getRecord(module)`) holds activation state (`activated`, `activating`, `effectReceipts`), `definition`, `host`, `runtime`, `onActivate`, and `capabilityInputs`, the slices activation hands each install. Only `module_bootstrap` reads it (tests also inspect it). Its `activated`/`activating` flags are the one activation state machine. A pending coordinator rebuild travels on the prepared definition (`_pendingCoordinatorRebuild`).
- `module_contexts.lua` builds the runtime and UI contexts once; lane fields are attached at construction through `moduleState.createLanes`.
- `managed_module_lifecycle.bind(session)` returns the commit, reload, enable, and pack-transition operations. Each one is exposed as an activation-gated module method of the same name.

## Module State

`moduleState.create(definition, opts)` returns one object per module:
`{ persistent, staged, status, actionBuffer, txn }`.

- `staged` is the view (`get/read/write/reset/table/getAliasSchema`), handed to UI lanes and controls.
- `txn` is the transaction (stage, dirty and pending checks, `beginCommit`/`rollback`/`finish`, `reload`, `queueResetAll`, the queued status reset), handed only to the lifecycle.
- `status` holds status semantics (`module_state/status_state.lua`). A status reset is queued on the txn and applied during a successful commit.
- `moduleState.createLanes(state, fields)` builds the author lanes (`runtime.data`, `runtime.status`, `ui.data`, `ui.status`) on one `storage_ref_adapter` lane builder. Private-alias rejection happens once, in that builder.

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
