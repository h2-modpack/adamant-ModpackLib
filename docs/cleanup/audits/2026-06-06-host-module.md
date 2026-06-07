# Host/Module Audit - 2026-06-06

Commands were run from `adamant-ModpackLib` after the status cleanup.

## Current Rule

The current contributor vocabulary is coherent:

- `Host` is the narrow callback projection passed to authored callbacks.
- `AuthorModule` is the declaration facade returned by `lib.createModule(...)`.
- `ManagedModule` is the activated live runtime object consumed by Framework,
  fallback UI, and Lib internals.
- `ownerId` is the capability-backend identity once a module/system crosses into
  subsystem logic.

So the cleanup target is not "remove host". It is:

- keep `host` for callback parameters and `AdamantModpackLib.Host`
- keep `ownerId` inside capability registries
- rename stale internal names where `host` means `ManagedModule`
- rename test harness names last, after production names settle

## Search Counts

```powershell
rg -n "\bhost\b|Host|host\." src
rg -n "\bhost\b|Host|host\." docs API.md
rg -n "\bhost\b|Host|host\." tests
```

Current hit counts:

```text
src: 108
docs/API.md: 194
tests: 624
```

Tests still dominate the count because many tests intentionally use `host` for
callback projections or live-module handles. The obvious managed-module harness
and suite names have been renamed.

## Keep

- `AdamantModpackLib.Host` in `src/def.lua`.
- Callback parameter names like `function(host, runtime)` and
  `function(host, ui)` in docs and tests.
- Author examples using `host.isEnabled()`, `host.log(...)`, and
  `host.logIf(...)`.
- `ownerId` inside cache, hooks, shared, mutation, and overlay registries.
- `frameworkRuntime.modules.getLiveModule(...)`; this already matches the new
  public Framework runtime shape.

## Rename Candidates

These are the highest-signal cleanup targets.

## Progress

Completed in the first cleanup patch:

- `mutation.applyForHost/syncForHost/revertForHost` -> `applyForModule/syncForModule/revertForModule`.
- `shared.emitForHost` -> `shared.emitForModule`.
- `core/hooks/host_install.lua` -> `core/hooks/owner_install.lua`.
- test harness fields `moduleHost` and `hostLifecycle` -> `managedModule` and
  `managedModuleLifecycle`.
- obvious API wording: "Host/framework plumbing", "Hosted modules", and
  "Host-scoped module overlays".

Completed in the second cleanup patch:

- public/internal `getHostId()` -> `getOwnerId()`.
- fallback UI `handleHostGuiClosed()` -> `handleGuiClosed()`.

Completed in the test cleanup patch:

- `tests/harness/create_module_host_harness.lua` ->
  `tests/harness/create_managed_module_harness.lua`.
- `createModuleHostHarness()` -> `createManagedModuleHarness()`.
- managed-module harness helpers `createHost()` / `createActivatedHost()` ->
  `createManagedModule()` / `createActivatedManagedModule()`.
- `TestModuleHost*` suites -> `TestManagedModule*`,
  `TestModuleDefinitionContract`, and `TestCreateModule`.
- obvious test helper entry points such as `createHostWithHooks`,
  `createHostWithOverlays`, `createLibHost`, and `activateHost` now use
  module-oriented names.

Still intentionally deferred:

- callback parameters and author-facing assertions named `host`.
- test IDs that only carry historical names and are not API contact points.

### Managed Module Service Names

Observed names:

```powershell
rg -n "moduleHost|hostLifecycle|managed module lifecycle service" src tests docs API.md
```

Findings:

- `tests/harness/create_lib_harness.lua` exposes the imported
  `core/module_bootstrap/managed_module.lua` service as `moduleHost`.
- `tests/harness/create_module_host_harness.lua` is still named after the old
  service shape.
- `tests/TestModuleHost*.lua` still name managed-module behavior as host
  behavior.
- `hostLifecycle` in tests points at `managed_module_lifecycle.lua`; this should
  read as managed-module lifecycle, not host lifecycle.

Recommended pass:

1. Rename test harness fields from `moduleHost` to `managedModule`.
2. Rename `hostLifecycle` to `managedModuleLifecycle`.
3. Rename `create_module_host_harness.lua` only after call sites are already
   using the new field names.
4. Rename `TestModuleHost*` files last, because those are mostly test-suite
   organization and will create noisy churn.

### Internal ForHost Functions That Take ManagedModule

Observed names:

```powershell
rg -n "applyForHost|syncForHost|revertForHost|emitForHost|installForHost" src tests docs API.md
```

Findings:

- `src/core/mutations/adapters/module_lifecycle.lua` has
  `applyForHost`, `syncForHost`, and `revertForHost`, but each expects a managed
  module record and reports `expected managed module record`.
- `src/core/shared/00_init.lua` has `emitForHost`, but current callers pass a
  managed module.
- `src/core/hooks/host_install.lua` is actually an owner-scoped install receipt.

Recommended pass:

1. Rename mutation adapter functions to `applyForModule`, `syncForModule`, and
   `revertForModule`.
2. Rename `shared.emitForHost` to `shared.emitForModule`.
3. Rename `hooks/host_install.lua` only if the file rename can stay narrow; a
   good destination would be `owner_install.lua`.

### Identity Methods

Observed names:

```powershell
rg -n "getOwnerId|OwnerId" src docs API.md tests
```

Findings:

- `Host.getOwnerId()` is valid for the callback projection if we keep the
  callback object named `host`.
- `ManagedModule.getOwnerId()` and `AuthorModule.getOwnerId()` are more ambiguous:
  they return the plugin guid / owner identity, not a separate host object id.
- Capability adapters immediately convert this into `ownerId`.

Resolution:

- Renamed `getHostId()` to `getOwnerId()`.
- Chose `getOwnerId()` over `getPluginGuid()` because capability ownership is
  the dominant use once construction crosses into Lib internals.

### Fallback UI GUI Close Names

Observed names:

```powershell
rg -n "HostGui|handleHostGuiClosed|handleGuiClosed" src tests docs API.md
```

Findings:

`fallback_ui.handleHostGuiClosed` was not the same concept as managed module
host. It was fallback GUI lifecycle naming.

Resolution:

- Renamed `handleHostGuiClosed()` to `handleGuiClosed()`.
- The fallback UI namespace already provides the context, so repeating
  `Fallback` or `Host` in the method name is unnecessary.

## Docs To Touch

Observed wording that should be cleaned with the code pass:

- `API.md`: "Host/framework plumbing methods"
- `API.md`: "Hosted modules declare hooks..."
- `API.md`: "Host-scoped module overlays..."
- `docs/lib-contributors/README.md`: currently useful and should remain the
  anchor for this cleanup.

Suggested replacements:

- "Framework plumbing methods"
- "Modules declare hooks..."
- "Module-scoped overlays..."

## Test Cleanup Order

Do not start with tests. They are noisy and will hide the real API changes.

Recommended order:

1. Production internal function names (`ForHost` where the input is a
   `ManagedModule`).
2. Production doc wording that directly references those names.
3. Harness field names (`moduleHost`, `hostLifecycle`).
4. Harness/file names (`create_module_host_harness.lua`, `TestModuleHost*.lua`).

## Open Decisions

- Whether noisy test suite/file names such as `TestModuleHost*` and
  `create_module_host_harness.lua` should be renamed now or left as historical
  test grouping names.

## Follow-up Scan - 2026-06-07

Commands were rerun after phase-gate removal and the status/controls cleanup.

```powershell
rg -n "\bhost\b|Host|host\." src
rg -n "\bhost\b|Host|host\." docs API.md
rg -n "\bhost\b|Host|host\." tests
rg -n "host-owned|host/framework|Lib host|host id|later host|fresh host|host-adapter" docs API.md src tests
rg -n "activeRuntime\.host|installFallbackRuntime\(|createRuntime\(host\)|---@field host table" src/core/fallback tests
rg -n "createSimpleActivatedHost|getHostLifecycle|createMutationHost|activateMutationHost|createSharedHost|activateAndEnableHost|configureHost|SharedHost|Host Module|Host Mutation|OverlayHost|HostOverlay|HostHook" tests docs src
```

Current broad hit counts:

```text
src: 103
docs/API.md: 196
tests: 622
```

The broad counts are mostly intentional callback `host` vocabulary. Current
actionable residue is narrower.

### Production Rename

Completed in the first follow-up cleanup patch:

- `FallbackUiRuntime.host` -> `module`.
- `createRuntime(host)` -> `createRuntime(module)`.
- `activeRuntime.host` -> `activeRuntime.module`.
- fallback UI harness `installFallbackRuntime(host)` ->
  `installFallbackRuntime(module)`.

This object was not the narrow callback `Host`; it was the managed module
surface used by fallback UI for `setEnabled`, `setDebugMode`,
`drawTabAndCommit`, `read`, `resync`, and metadata.

### Production Comment/Diagnostics

Completed in the first follow-up cleanup patch:

- `src/core/module_state/staged/ui_state.lua`: "Host internals keep..." ->
  "Module internals keep...".
- `src/core/shared/data.lua`: duplicate declaration diagnostics say "this
  module" instead of "this host".

### Docs/API Wording

Completed in the docs/test wording cleanup patch:

- `host/framework flow` -> `module/framework flow`.
- `host-owned semantic helpers` -> `module-owned semantic helpers`.
- `Lib host` -> `live module`.
- `later/fresh host` -> `later/fresh module instance`.
- `host id` -> `owner id`.
- `host-adapter boundary` -> `callback-host adapter boundary`.

Callback shape docs still intentionally say `(host, ui)` and
`(host, runtime)`.

### Test Cleanup

Completed in the docs/test wording cleanup patch:

- `createSimpleActivatedHost(...)` -> `createSimpleActivatedManagedModule(...)`.
- `getHostLifecycle(...)` -> `getManagedModuleLifecycle(...)`.
- `createMutationHost(...)` / `activateMutationHost(...)` ->
  `createMutationModule(...)` / `activateMutationModule(...)`.
- `createSharedHost(...)`, `activateAndEnableHost(...)`, and `configureHost`
  helpers now use module-oriented names.
- stale test names such as `testHostOverlay...` and `testHostHook...` now use
  module-oriented names.
- fixture labels such as `OverlayHost`, `SharedHost`, and `Host Mutation Patch`
  now use module wording.

Local variables named `host` remain when they are callback hosts or broad test
setup handles where renaming would add churn without clarifying a public or
internal contact point.

### Keep

- `AdamantModpackLib.Host`.
- callback parameters named `host`.
- `record.host` in `managed_module.lua`, overlays, shared listeners, mutation
  lifecycle, hooks, actions, and declaration callback adapters. These store the
  callback-safe host projection.
- `host.getOwnerId()` on the callback projection.
- docs explaining `(host, ui)` and `(host, runtime)` callback shapes.

### Suggested Next Patch Order

1. Rename fallback UI runtime `host` field to `module`.
2. Fix low-risk production comments/diagnostics.
3. Clean public docs wording.
4. Decide whether to clean tests now or leave them as historical scan noise.
