# Initial RG Audit - 2026-06-06

Commands were run from `adamant-ModpackLib`.

## runtimeOwned/status

Command:

```powershell
rg -n "runtimeOwned|store\.runtimeOwned|stagedState\.runtimeOwned|RuntimeOwned" src tests docs API.md
```

Raw output:

```text
src\def.lua:92:---@field runtimeOwned AdamantModpackLib.RuntimeOwnedState
src\def.lua:109:---@class AdamantModpackLib.RuntimeOwnedState: AdamantModpackLib.RuntimeStatus
tests\TestModuleHost.lua:283:function TestModuleHost:testHostResetAllResetsStagedAndRuntimeOwnedState()
tests\TestModuleHost.lua:307:    store.runtimeOwned.write("RuntimeFlag", true)
tests\TestModuleHost.lua:316:    lu.assertTrue(store.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleHost.lua:320:    lu.assertFalse(store.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleHost.lua:396:    store.runtimeOwned.write("RuntimeFlag", true)
tests\TestModuleHost.lua:402:    lu.assertTrue(store.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleHost.lua:409:    lu.assertFalse(store.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleHost.lua:707:    lu.assertTrue(store.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleState_StagedState.lua:127:    lu.assertTrue(persistentState.runtimeOwned.write("RuntimeFlag", true))
tests\TestModuleState_StagedState.lua:129:    lu.assertTrue(stagedState.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleState_StagedState.lua:130:    lu.assertTrue(stagedState.runtimeOwned.get("RuntimeFlag"):read())
tests\TestModuleState_StagedState.lua:145:    local runtimeRows = stagedState.runtimeOwned.get("RuntimeRows")
tests\TestModuleState_StagedState.lua:156:    persistentState.runtimeOwned.write("RuntimeFlag", true)
tests\TestModuleState_PersistentState.lua:59:    lu.assertFalse(persistentState.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleState_PersistentState.lua:60:    lu.assertEquals(persistentState.runtimeOwned.read("RuntimeCount"), 1)
tests\TestModuleState_PersistentState.lua:61:    lu.assertFalse(persistentState.runtimeOwned.read("RuntimeBit"))
tests\TestModuleState_PersistentState.lua:63:    lu.assertTrue(persistentState.runtimeOwned.write("RuntimeFlag", true))
tests\TestModuleState_PersistentState.lua:64:    lu.assertTrue(persistentState.runtimeOwned.write("RuntimeCount", 10))
tests\TestModuleState_PersistentState.lua:65:    lu.assertTrue(persistentState.runtimeOwned.write("RuntimePacked", 1))
tests\TestModuleState_PersistentState.lua:66:    lu.assertTrue(persistentState.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleState_PersistentState.lua:67:    lu.assertEquals(persistentState.runtimeOwned.read("RuntimeCount"), 5)
tests\TestModuleState_PersistentState.lua:68:    lu.assertTrue(persistentState.runtimeOwned.read("RuntimeBit"))
tests\TestModuleState_PersistentState.lua:76:    lu.assertTrue(persistentState.runtimeOwned.reset("RuntimeFlag"))
tests\TestModuleState_PersistentState.lua:77:    lu.assertFalse(persistentState.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleState_PersistentState.lua:80:    lu.assertTrue(persistentState.runtimeOwned.write("RuntimeBit", false))
tests\TestModuleState_PersistentState.lua:82:    lu.assertFalse(persistentState.runtimeOwned.read("RuntimeBit"))
tests\TestModuleState_PersistentState.lua:83:    lu.assertTrue(persistentState.runtimeOwned.write("RuntimeBit", true))
tests\TestModuleState_PersistentState.lua:85:    lu.assertTrue(persistentState.runtimeOwned.reset("RuntimeBit"))
tests\TestModuleState_PersistentState.lua:87:    lu.assertFalse(persistentState.runtimeOwned.read("RuntimeBit"))
tests\TestModuleState_PersistentState.lua:90:        persistentState.runtimeOwned.write("SettingFlag", true)
tests\TestModuleState_PersistentState.lua:103:        persistentState.runtimeOwned.read("RuntimeRows")
tests\TestModuleState_PersistentState.lua:106:    local rows = persistentState.runtimeOwned.get("RuntimeRows")
tests\TestModuleState_PersistentState.lua:117:    lu.assertTrue(persistentState.runtimeOwned.read("RuntimeRows", 1, "Enabled"))
tests\TestModuleState_PersistentState.lua:121:        persistentState.runtimeOwned.write("RuntimeRows", {
tests\TestModuleState_PersistentState.lua:127:    lu.assertTrue(persistentState.runtimeOwned.write("RuntimeRows", 1, "Enabled", false))
tests\TestModuleState_PersistentState.lua:142:    lu.assertTrue(persistentState.runtimeOwned.reset("RuntimeRows"))
tests\TestModuleState_PersistentState.lua:154:    lu.assertFalse(persistentState.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleState_PersistentState.lua:155:    lu.assertTrue(persistentState.runtimeOwned.write("RuntimeFlag", true))
tests\TestModuleState_PersistentState.lua:156:    lu.assertTrue(persistentState.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleState_PersistentState.lua:159:    lu.assertTrue(persistentState.runtimeOwned.read("RuntimeFlag"))
tests\TestModuleState_PersistentState.lua:161:    lu.assertTrue(persistentState.runtimeOwned.reset("RuntimeFlag"))
tests\TestModuleState_PersistentState.lua:162:    lu.assertFalse(persistentState.runtimeOwned.read("RuntimeFlag"))
src\core\controls\compiler.lua:53:local function rejectRuntimeOwnedField(controlName, fieldKey)
src\core\controls\compiler.lua:82:            rejectRuntimeOwnedField(controlName, parentKey .. ":" .. key)
src\core\controls\compiler.lua:112:            rejectRuntimeOwnedField(controlName, parentKey .. ":" .. rowKey)
src\core\controls\compiler.lua:147:            rejectRuntimeOwnedField(controlName, key)
src\core\module_state\00_init.lua:110:---@field runtimeOwned RuntimeOwnedState
src\core\module_state\00_init.lua:114:---@class RuntimeOwnedState
src\core\module_state\00_init.lua:142:---@field runtimeOwned table
src\core\module_state\staged\staged_state.lua:23:    local runtimeOwnedFieldHandles = {}
src\core\module_state\staged\staged_state.lua:146:                    "stagedState.read: alias '%s' is runtime-owned; use stagedState.runtimeOwned.read",
src\core\module_state\staged\staged_state.lua:157:    local runtimeOwnedReadBackend = {
src\core\module_state\staged\staged_state.lua:168:                    "stagedState.runtimeOwned.read: alias '%s' is not runtime-owned storage",
src\core\module_state\staged\staged_state.lua:175:            logging.violate("staged_state.unknown_alias", "stagedState.runtimeOwned.read: unknown alias '%s'",
src\core\module_state\staged\staged_state.lua:191:                    "stagedState.write: alias '%s' is runtime-owned; use stagedState.runtimeOwned on the read side",
src\core\module_state\staged\staged_state.lua:240:    local function readRuntimeOwnedValue(alias)
src\core\module_state\staged\staged_state.lua:241:        return storageInternal.readAlias(aliasNodes, runtimeOwnedReadBackend, alias)
src\core\module_state\staged\staged_state.lua:244:    local runtimeOwnedFieldOwner = {
src\core\module_state\staged\staged_state.lua:245:        read = readRuntimeOwnedValue,
src\core\module_state\staged\staged_state.lua:251:    local function getRuntimeOwnedFieldHandleForNode(alias, node)
src\core\module_state\staged\staged_state.lua:252:        local cached = runtimeOwnedFieldHandles[alias]
src\core\module_state\staged\staged_state.lua:257:        local field = storageInternal.field.createKnown(runtimeOwnedFieldOwner, alias, node, "stagedState.runtimeOwned.get")
src\core\module_state\staged\staged_state.lua:258:        runtimeOwnedFieldHandles[alias] = field
src\core\module_state\staged\staged_state.lua:305:                "stagedState.table: alias '%s' is runtime-owned; use stagedState.runtimeOwned.table", tostring(alias))
src\core\module_state\staged\staged_state.lua:364:                "stagedState.get: alias '%s' is runtime-owned; use stagedState.runtimeOwned.get",
src\core\module_state\staged\staged_state.lua:374:    local function getRuntimeOwnedDataObject(alias)
src\core\module_state\staged\staged_state.lua:377:            logging.violate("staged_state.unknown_alias", "stagedState.runtimeOwned.get: unknown alias '%s'",
src\core\module_state\staged\staged_state.lua:384:                "stagedState.runtimeOwned.get: alias '%s' is not runtime-owned storage",
src\core\module_state\staged\staged_state.lua:391:        return getRuntimeOwnedFieldHandleForNode(alias, node)
src\core\module_state\staged\staged_state.lua:394:    local function getRuntimeOwnedTable(alias)
src\core\module_state\staged\staged_state.lua:397:            logging.violate("staged_state.unknown_alias", "stagedState.runtimeOwned.table: unknown alias '%s'",
src\core\module_state\staged\staged_state.lua:403:                "stagedState.runtimeOwned.table: alias '%s' is not runtime-owned storage", tostring(alias))
src\core\module_state\staged\staged_state.lua:408:                "stagedState.runtimeOwned.table: alias '%s' is not table storage", tostring(alias))
src\core\module_state\staged\staged_state.lua:425:        runtimeOwned = {
src\core\module_state\staged\staged_state.lua:426:            read = readRuntimeOwnedValue,
src\core\module_state\staged\staged_state.lua:427:            get = getRuntimeOwnedDataObject,
src\core\module_state\staged\staged_state.lua:428:            table = getRuntimeOwnedTable,
src\core\status\adapters\ui_status.lua:23:            return stagedState.runtimeOwned.get(alias)
src\core\status\adapters\runtime_status.lua:9:local function createStatusRoot(persistentState, runtimeOwned)
src\core\status\adapters\runtime_status.lua:24:            return runtimeOwned.get(alias)
src\core\status\adapters\runtime_status.lua:30:    local runtimeOwned = persistentState.runtimeOwned
src\core\status\adapters\runtime_status.lua:31:    if not runtimeOwned then
src\core\status\adapters\runtime_status.lua:36:        root = createStatusRoot(persistentState, runtimeOwned),
src\core\status\adapters\runtime_status.lua:76:                return runtimeOwned.reset(alias)
src\core\module_bootstrap\managed_module.lua:19:local INTERNAL_RESET_RUNTIME_OWNED_ACTION = "_ResetRuntimeOwned"
src\core\module_bootstrap\managed_module.lua:249:    local function queueRuntimeOwnedReset(resetOpts)
src\core\module_bootstrap\managed_module.lua:251:        local runtimeChanged, runtimeCount = persistentState.runtimeOwned.countResettable(resetOpts)
src\core\module_bootstrap\managed_module.lua:258:        local runtimeChanged, runtimeCount = queueRuntimeOwnedReset(resetOpts)
src\core\module_bootstrap\managed_module.lua:268:            persistentState.runtimeOwned.resetAll(resetOpts)
src\core\module_state\persistent\persistent_state.lua:17:    local runtimeOwnedTableHandles = {}
src\core\module_state\persistent\persistent_state.lua:19:    local runtimeOwnedFieldHandles = {}
src\core\module_state\persistent\persistent_state.lua:127:                    "store.read: alias '%s' is runtime-owned; use store.runtimeOwned.read",
src\core\module_state\persistent\persistent_state.lua:164:    local runtimeOwnedWriteBackend = {
src\core\module_state\persistent\persistent_state.lua:167:            return getRuntimeNode(alias, "store.runtimeOwned.write", true) ~= nil
src\core\module_state\persistent\persistent_state.lua:171:            logging.violate("store.unknown_alias", "store.runtimeOwned.write: unknown storage alias '%s'",
src\core\module_state\persistent\persistent_state.lua:177:        local node = getRuntimeNode(alias, "store.runtimeOwned.write", true)
src\core\module_state\persistent\persistent_state.lua:183:                "store.runtimeOwned.write: alias '%s' is table storage; use a table handle or table cell write",
src\core\module_state\persistent\persistent_state.lua:187:        return storageInternal.writeAlias(aliasNodes, runtimeOwnedWriteBackend, alias, value)
src\core\module_state\persistent\persistent_state.lua:191:        local node = getRuntimeNode(alias, "store.runtimeOwned.reset")
src\core\module_state\persistent\persistent_state.lua:199:        local node = getRuntimeNode(alias, "store.runtimeOwned.reset", true)
src\core\module_state\persistent\persistent_state.lua:251:    local runtimeOwnedReadBackend = {
src\core\module_state\persistent\persistent_state.lua:254:            return getRuntimeNode(alias, "store.runtimeOwned.read", true) ~= nil
src\core\module_state\persistent\persistent_state.lua:257:            logging.violate("store.unknown_alias", "store.runtimeOwned.read: unknown storage alias '%s'",
src\core\module_state\persistent\persistent_state.lua:263:    local getRuntimeOwnedTableHandleForNode
src\core\module_state\persistent\persistent_state.lua:266:    local runtimeOwnedFieldOwner = {
src\core\module_state\persistent\persistent_state.lua:268:            local node = getRuntimeNode(alias, "store.runtimeOwned.read", true)
src\core\module_state\persistent\persistent_state.lua:272:            return storageInternal.readAlias(aliasNodes, runtimeOwnedReadBackend, alias)
src\core\module_state\persistent\persistent_state.lua:281:    local function getRuntimeOwnedFieldHandleForNode(alias, node)
src\core\module_state\persistent\persistent_state.lua:282:        local cached = runtimeOwnedFieldHandles[alias]
src\core\module_state\persistent\persistent_state.lua:287:        local field = storageInternal.field.createKnown(runtimeOwnedFieldOwner, alias, node, "store.runtimeOwned.get")
src\core\module_state\persistent\persistent_state.lua:288:        runtimeOwnedFieldHandles[alias] = field
src\core\module_state\persistent\persistent_state.lua:292:    local function getRuntimeOwnedDataObject(alias)
src\core\module_state\persistent\persistent_state.lua:293:        local node = getRuntimeNode(alias, "store.runtimeOwned.get", true)
src\core\module_state\persistent\persistent_state.lua:298:            return getRuntimeOwnedTableHandleForNode(alias, node)
src\core\module_state\persistent\persistent_state.lua:300:        return getRuntimeOwnedFieldHandleForNode(alias, node)
src\core\module_state\persistent\persistent_state.lua:303:    persistentState.runtimeOwned = {
src\core\module_state\persistent\persistent_state.lua:305:            local ref = getRuntimeOwnedDataObject(alias)
src\core\module_state\persistent\persistent_state.lua:311:        get = getRuntimeOwnedDataObject,
src\core\module_state\persistent\persistent_state.lua:313:            local node = getRuntimeNode(alias, "store.runtimeOwned.table", true)
src\core\module_state\persistent\persistent_state.lua:319:                    "store.runtimeOwned.table: alias '%s' is not table storage", tostring(alias))
src\core\module_state\persistent\persistent_state.lua:322:            return getRuntimeOwnedTableHandleForNode(alias, node)
src\core\module_state\persistent\persistent_state.lua:329:            local ref = getRuntimeOwnedDataObject(alias)
src\core\module_state\persistent\persistent_state.lua:334:                logging.violate("store.invalid_surface", "store.runtimeOwned.write: alias '%s' is not writable",
src\core\module_state\persistent\persistent_state.lua:345:            local ref = getRuntimeOwnedDataObject(alias)
src\core\module_state\persistent\persistent_state.lua:350:                logging.violate("store.invalid_surface", "store.runtimeOwned.reset: alias '%s' is not resettable",
src\core\module_state\persistent\persistent_state.lua:374:    getRuntimeOwnedTableHandleForNode = function(alias, node)
src\core\module_state\persistent\persistent_state.lua:375:        local cached = runtimeOwnedTableHandles[alias]
src\core\module_state\persistent\persistent_state.lua:385:        runtimeOwnedTableHandles[alias] = handle
src\core\module_state\persistent\persistent_state.lua:412:                "store.table: alias '%s' is runtime-owned; use store.runtimeOwned.table", tostring(alias))
src\core\module_state\persistent\persistent_state.lua:432:                "store.get: alias '%s' is runtime-owned; use store.runtimeOwned.get",
```

Initial read:

- Public docs mostly use `status`, but internal module-state diagnostics still say `runtimeOwned`.
- Tests still exercise the internal backend directly. That may be acceptable, but any public-facing test names should probably move to `status` vocabulary.
- `src/def.lua` still exposes `RuntimeOwnedState` as an alias layer over `RuntimeStatus`.

## Services/integration/poll/provider

Command:

```powershell
rg -n "\bservices?\b|\bintegration\b|\bintegrations\b|\bpoll\b|\bprovider\b|\bproviders\b" src tests docs API.md
```

Raw output:

```text
API.md:825:internal overlay service.
docs\rejected-directions\DECLARATIVE_FIELD_UI.md:42:- option providers
tests\TestModuleHost.lua:143:            self.h.fallbackUiBundle.service.attachGuiOnce(module, function() end)
tests\TestModuleHost.lua:182:            attached = self.h.fallbackUiBundle.service.attachGuiOnce(module, function() end)
tests\TestModuleHost_CreateModule.lua:168:    lu.assertNil(drawContext.services)
tests\TestModuleHost_CreateModule.lua:406:    lu.assertNil(host.shared.poll)
src\core\cache\00_init.lua:9:local service = {}
src\core\cache\00_init.lua:15:service.currentRun = {
src\core\cache\00_init.lua:24:    service = service,
src\core\cache\00_init.lua:26:service.data = dataCache
src\core\cache\00_init.lua:29:    service = service,
docs\lib-contributors\README.md:40:translation. The low-level `lib_bootstrap/registry` service owns Lib's
docs\lib-contributors\LIB_INTERNALS.md:7:services, captures the service objects that later subsystems need, and passes
docs\lib-contributors\LIB_INTERNALS.md:13:- Return a service object only when downstream Lib code needs a service from the subsystem.
docs\lib-contributors\LIB_INTERNALS.md:15:- A public object may be returned to its immediate subsystem composer for local fan-out, but it should not be captured by `core/init.lua` as a Lib-wide service.
docs\lib-contributors\LIB_INTERNALS.md:16:- Mixed modules should keep public-only functions off the returned service.
docs\lib-contributors\LIB_INTERNALS.md:18:- Define exported behavior directly on the service table:
docs\lib-contributors\LIB_INTERNALS.md:21:function service.doThing(...)
docs\lib-contributors\LIB_INTERNALS.md:26:- Do not write a local function only to immediately assign it onto the service table unless that local is genuinely private.
docs\lib-contributors\LIB_INTERNALS.md:27:- Keep returned services behavior-focused. Do not expose private storage tables only because tests want to inspect or mutate them.
docs\lib-contributors\LIB_INTERNALS.md:39:- Weak implementation side tables and rebuildable caches, like module-state backend/store side tables, should stay local to the service import rather than living under `AdamantModpackLib_Runtime`.
docs\lib-contributors\LIB_INTERNALS.md:40:- Live-module, pending-rebuild, and weak module-record tables are activation anchors; keep the tables under `AdamantModpackLib_Runtime.registry.modules`, but keep lifecycle behavior on the returned `managedModule` service.
docs\lib-contributors\LIB_INTERNALS.md:46:- Do not add new compatibility assignments for ordinary services.
docs\lib-contributors\LIB_INTERNALS.md:53:- Do not reach back into global namespaces for ordinary services once a dependency can be passed explicitly.
docs\lib-contributors\LIB_INTERNALS.md:54:- Pass targeted services, not broad context blobs.
docs\lib-contributors\LIB_INTERNALS.md:55:- If a subsystem needs behavior that also has a public API, put the behavior on a named service and let the public API call it; do not call `public.*` from another Lib subsystem.
src\core\cache\adapters\data_cache.lua:5:local service = deps.service
src\core\cache\adapters\data_cache.lua:47:    return wrapGetClearRef(service.currentRun.create(opts.ownerId, declaration.key, {
src\core\hooks\00_init.lua:40:local service = {
src\core\hooks\00_init.lua:45:    service = service,
tests\harness\module_state_helpers.lua:19:        "managed module lifecycle service missing")
src\core\init.lua:87:local shared = sharedBundle.service
src\core\init.lua:95:local hooks = hooksBundle.service
src\core\init.lua:110:local overlays = overlaysBundle.service
src\core\init.lua:127:local mutation = mutationBundle.service
src\core\init.lua:155:    cache = cacheBundle.service,
src\core\init.lua:160:    fallbackUi = fallbackUiBundle.service,
src\core\init.lua:188:    fallbackUi = fallbackUiBundle.service,
src\core\fallback\fallback_ui.lua:386:    service = fallbackUi,
tests\harness\create_lib_harness.lua:239:        cache = imports["core/cache/00_init.lua"].service,
tests\harness\create_lib_harness.lua:250:        shared = imports["core/shared/00_init.lua"].service,
tests\harness\create_lib_harness.lua:252:        hooks = imports["core/hooks/00_init.lua"].service,
tests\harness\create_lib_harness.lua:254:        overlays = imports["core/overlays/00_init.lua"].service,
tests\harness\create_lib_harness.lua:256:        mutation = imports["core/mutations/00_init.lua"].service,
tests\harness\create_lib_harness.lua:267:        fallbackUi = imports["core/fallback/fallback_ui.lua"].service,
src\core\mutations\00_init.lua:22:local service = import('core/mutations/adapters/module_lifecycle.lua', nil, {
src\core\mutations\00_init.lua:29:    service = service,
src\core\overlays\00_init.lua:3:local service = {}
src\core\overlays\00_init.lua:39:        return service.dispatchIntervals(now)
src\core\overlays\00_init.lua:67:service.installForModule = moduleAdapter.installForModule
src\core\overlays\00_init.lua:68:service.suppressForUi = suppression.suppressForUi
src\core\overlays\00_init.lua:69:service.isUiSuppressed = suppression.isUiSuppressed
src\core\overlays\00_init.lua:79:function service.dispatchCommit(owner, commit)
src\core\overlays\00_init.lua:84:function service.dispatchIntervals(now)
src\core\overlays\00_init.lua:89:function service.dispatchAfterHook(owner, path, args, results)
src\core\overlays\00_init.lua:94:    service = service,
src\core\shared\adapters\data_shared.lua:5:local service = deps.service
src\core\shared\adapters\data_shared.lua:53:    local rawRef = service.data.createDeclaredRef(opts.record, opts.host, name, opts.source)
src\core\shared\00_init.lua:35:local service = {
src\core\shared\00_init.lua:40:function service.emitForHost(host, id, eventName, payload)
src\core\shared\00_init.lua:57:    service = service,
src\core\shared\00_init.lua:61:    service = service,
```

Initial read:

- `service` is still current internal vocabulary in contributor docs and core bundles.
- `poll` and public `services` are only negative assertions in tests, which is good cleanup residue to keep until confidence is high.
- No obvious live `integration provider` API remains.

## Compat/legacy/deprecated/shim/migration/old

Command:

```powershell
rg -n "\bcompat\b|\blegacy\b|\bdeprecated\b|\bshim\b|\bmigration\b|\bold\b" src tests docs API.md
```

Raw output:

```text
API.md:977:The old `session.stageAction(...)` form has been removed. Use
tests\TestModuleHost_CreateModule.lua:692:            pluginGuid = "test-create-module-legacy-definition",
tests\TestModuleHost_PrepareDefinition.lua:619:        tooltip = "old",
tests\TestMutation_DefinitionLifecycle.lua:545:    local ok, err = self:applyMutation("test-deprecated-affected-flag", def,
tests\TestMutation.lua:28:        Nested = { Value = "old" },
tests\TestMutation.lua:39:    lu.assertEquals(tbl.Nested, { Value = "old" })
tests\TestMutation.lua:46:        Name = "old",
tests\TestMutation.lua:69:        Name = "old",
tests\TestMutation.lua:184:            { id = 1, value = "old" },
tests\TestMutation.lua:204:        { id = 1, value = "old" },
src\core\module_bootstrap\managed_module_activation.lua:75:    disposeReceipts(receipts, "managed_module.retire_failed", tostring(replacementLabel) .. " old module retirement failed")
docs\lib-contributors\CACHE_OBJECT_DESIGN.md:25:Status replaces the old persistent-cache use case. If a module needs a value
docs\lib-contributors\CONTROL_ERGONOMICS.md:161:treated as deprecated just because large control-heavy modules benefit from a
docs\lib-contributors\LIB_INTERNALS.md:45:- The old Lib internal namespace has been retired.
docs\lib-contributors\LIB_INTERNALS.md:47:- If a future migration genuinely needs a temporary bridge, keep it explicitly short-lived, behavior-only, and remove it before the subsystem is considered clean.
docs\lib-contributors\LIB_INTERNALS.md:67:For each leaf migration:
docs\lib-contributors\future-ideas\HASH_STRING_COMPRESSION.md:22:- changing a packed layout could make old hashes unrecoverable without keeping
docs\lib-contributors\future-ideas\HASH_STRING_COMPRESSION.md:26:but adding a storage field can shift positional bits and invalidate old profile
docs\lib-contributors\future-ideas\HASH_STRING_COMPRESSION.md:28:old values.
docs\lib-contributors\future-ideas\HASH_STRING_COMPRESSION.md:88:to defaults, and old keys keep their meaning.
docs\references\KNOWN_LIMITATIONS.md:62:Lib module activation is designed to keep the old live module active until the replacement module has usable managed runtime effects.
docs\references\KNOWN_LIMITATIONS.md:66:- failed activation preserves the old live module when rollback succeeds
docs\references\KNOWN_LIMITATIONS.md:114:- if candidate mutation activation fails, Lib attempts to restore the prior raw patch state and keep the old module live
```

Initial read:

- Most hits are legitimate examples or activation semantics.
- `LIB_INTERNALS.md` still has migration wording that may be historical now.
- `API.md` still has one old-form note that may be useful public migration guidance or may be stale depending on how much historical support we want in the API reference.

## Host/module vocabulary

Command:

```powershell
rg -n "\bhost\b|Host|host\." src tests docs API.md
```

The full output was 1263 lines, so it is too large for a useful one-shot dump.
Counts by area:

```text
src: 174
tests: 972
docs/API.md: 117
```

Suggested split:

```powershell
rg -n "\bhost\b|Host|host\." docs API.md
rg -n "\bhost\b|Host|host\." src\core\module_bootstrap src\core\module_state src\def.lua
rg -n "\bhost\b|Host|host\." src\core\shared src\core\mutations src\core\overlays src\core\fallback
rg -n "\bhost\b|Host|host\." tests\TestModuleHost*.lua tests\harness
rg -n "\bhost\b|Host|host\." tests --glob "!TestModuleHost*.lua" --glob "!harness/**"
```

Initial read:

- Docs intentionally expose `host` as the callback-safe projection, so not every hit is stale.
- Internal APIs still use names like `getHostId` and `applyForHost`; those need case-by-case classification because some may be stable internal vocabulary.
- Tests account for most hits and should be renamed last, after public/internal vocabulary is settled.
