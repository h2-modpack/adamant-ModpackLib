local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestMutation_DefinitionLifecycle = {}

local function patchMutation(fn)
    return {
        patchMutation = function(callbackHost, runtime, plan)
            return fn(plan, callbackHost, runtime and runtime.data or nil, runtime)
        end,
    }
end

local function createModuleState(harness, config, definition)
    return harness:createModuleState(config, definition)
end

-- Minimal lifecycle transaction over one mirrored boolean alias.
local function createMirrorTxn(store, mirroredAlias, readStaged, writeStaged, hooks)
    local txn = {
        readCommitted = store.read,
        isDirty = hooks.isDirty,
        hasPending = hooks.isDirty,
        applyStatusReset = function() end,
        finish = function() end,
    }
    function txn.stage(alias, value)
        if alias == mirroredAlias then
            if readStaged() ~= value then
                hooks.setDirty(true)
            end
            writeStaged(value)
        end
    end
    function txn.syncFromCommitted()
        hooks.sync()
        hooks.setDirty(false)
    end
    function txn.beginCommit()
        local hadConfigChanges = hooks.isDirty()
        if hadConfigChanges then
            hooks.commit()
            hooks.setDirty(false)
        end
        return { actionSnapshot = {}, hadConfigChanges = hadConfigChanges }
    end
    function txn.rollback()
        hooks.reload()
        hooks.setDirty(false)
    end
    function txn.reload()
        hooks.reload()
        hooks.setDirty(false)
    end
    return txn
end

function TestMutation_DefinitionLifecycle:setUp()
    self.harness = createLibHarness()
    self.mutation = self.harness.mutation
    self.mutationPlan = self.harness.mutationPlan
    self.managedModule = self.harness.managedModule
    self.moduleDefinition = self.harness.moduleDefinition
    self.managedModuleLifecycle = self.harness.managedModuleLifecycle
    self.coordinator = self.harness.coordinator
end

function TestMutation_DefinitionLifecycle:applyPlan(plan)
    return self.mutationPlan.applyPlan(plan)
end

function TestMutation_DefinitionLifecycle:revertPlan(plan)
    return self.mutationPlan.revertPlan(plan)
end

function TestMutation_DefinitionLifecycle:makeStore(enabled)
    return createModuleState(self.harness, { Enabled = enabled }, self.moduleDefinition.prepareDefinition({}, {
        id = "LifecycleStore",
        name = "Lifecycle Store",
        storage = {},
    }))
end

function TestMutation_DefinitionLifecycle:bindMutation(pluginGuid, def, mutationBundle, callbackHost, store)
    pluginGuid = pluginGuid or ("test-" .. tostring(def and def.id or "mutation"))
    -- Managed modules always bind a bundle; "no mutation" is an empty one.
    return self.mutation.bind(pluginGuid, mutationBundle or {}, callbackHost, {
        data = store,
    })
end

function TestMutation_DefinitionLifecycle:applyMutation(pluginGuid, def, mutationBundle, callbackHost, store)
    return self:bindMutation(pluginGuid, def, mutationBundle, callbackHost, store).apply()
end

function TestMutation_DefinitionLifecycle:revertMutation(pluginGuid, def, mutationBundle, callbackHost, store)
    return self:bindMutation(pluginGuid, def, mutationBundle, callbackHost, store).revert()
end

local function noop() end

function TestMutation_DefinitionLifecycle:bindLifecycle(def, bound, txn, commitNotifier)
    return self.managedModuleLifecycle.bind({
        def = def,
        txn = txn,
        mutation = bound,
        notifyCommit = commitNotifier or noop,
        notifyReload = noop,
        runActions = noop,
        flushSharedEvents = noop,
    })
end

function TestMutation_DefinitionLifecycle:commitStagedState(def, mutationBundle, commitNotifier, callbackHost, store, txn,
        pluginGuid)
    local bound = self:bindMutation(pluginGuid, def, mutationBundle, callbackHost, store)
    return self:bindLifecycle(def, bound, txn, commitNotifier).flush()
end

function TestMutation_DefinitionLifecycle:setEnabled(def, mutationBundle, callbackHost, store, txn, enabled, pluginGuid)
    local bound = self:bindMutation(pluginGuid, def, mutationBundle, callbackHost, store)
    return self:bindLifecycle(def, bound, txn).setEnabled(enabled)
end

function TestMutation_DefinitionLifecycle:activateMutationModule(pluginGuid, definition, config, patchCallback)
    local store, _, moduleState = createModuleState(self.harness, config, definition)
    local module = self.harness:createManagedInstance({
        pluginGuid = pluginGuid,
        definition = definition,
        state = moduleState,
        mutationBundle = patchCallback ~= nil and {
            patchMutation = function(callbackHost, runtime, plan)
                return patchCallback(plan, callbackHost, runtime and runtime.data or nil, runtime)
            end,
        } or nil,
        drawTab = function() end,
    })
    local ok, err = module.activate()
    return ok, err, store
end

function TestMutation_DefinitionLifecycle:testSetApplyAndRevert()
    local plan = self.mutationPlan.createPlan()
    local tbl = { HP = 100 }

    plan:set(tbl, "HP", 250)

    lu.assertTrue(self:applyPlan(plan))
    lu.assertEquals(tbl.HP, 250)
    lu.assertTrue(self:revertPlan(plan))
    lu.assertEquals(tbl.HP, 100)
end

function TestMutation_DefinitionLifecycle:testSetClonesTableValue()
    local plan = self.mutationPlan.createPlan()
    local replacement = { Damage = 100 }
    local tbl = { Data = { Damage = 10 } }

    plan:set(tbl, "Data", replacement)
    self:applyPlan(plan)
    replacement.Damage = 999

    lu.assertEquals(tbl.Data.Damage, 100)
    self:revertPlan(plan)
    lu.assertEquals(tbl.Data.Damage, 10)
end

function TestMutation_DefinitionLifecycle:testSetManyApplyAndRevert()
    local plan = self.mutationPlan.createPlan()
    local tbl = { A = 1, B = 2, C = 3 }

    plan:setMany(tbl, { A = 10, B = 20 })
    self:applyPlan(plan)

    lu.assertEquals(tbl.A, 10)
    lu.assertEquals(tbl.B, 20)
    lu.assertEquals(tbl.C, 3)

    self:revertPlan(plan)
    lu.assertEquals(tbl.A, 1)
    lu.assertEquals(tbl.B, 2)
    lu.assertEquals(tbl.C, 3)
end

function TestMutation_DefinitionLifecycle:testTransformApplyAndRevert()
    local plan = self.mutationPlan.createPlan()
    local tbl = { Requirements = { "A" } }
    local deepCopy = self.harness.rom.game.DeepCopyTable

    plan:transform(tbl, "Requirements", function(current)
        local nextValue = deepCopy(current)
        table.insert(nextValue, "B")
        return nextValue
    end)

    self:applyPlan(plan)
    lu.assertEquals(tbl.Requirements, { "A", "B" })

    self:revertPlan(plan)
    lu.assertEquals(tbl.Requirements, { "A" })
end

function TestMutation_DefinitionLifecycle:testAppendCreatesMissingListAndRestoresNil()
    local plan = self.mutationPlan.createPlan()
    local tbl = {}

    plan:append(tbl, "Values", "A")
    self:applyPlan(plan)

    lu.assertEquals(tbl.Values, { "A" })

    self:revertPlan(plan)
    lu.assertNil(tbl.Values)
end

function TestMutation_DefinitionLifecycle:testAppendUniqueUsesDeepEquivalenceByDefault()
    local plan = self.mutationPlan.createPlan()
    local tbl = {
        Requirements = {
            { Path = { "CurrentRun", "Hero" }, Value = 1 },
        },
    }

    plan:appendUnique(tbl, "Requirements", { Path = { "CurrentRun", "Hero" }, Value = 1 })
    self:applyPlan(plan)

    lu.assertEquals(#tbl.Requirements, 1)
    self:revertPlan(plan)
    lu.assertEquals(#tbl.Requirements, 1)
end

function TestMutation_DefinitionLifecycle:testAppendUniqueCanUseCustomComparator()
    local plan = self.mutationPlan.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 } } }

    plan:appendUnique(tbl, "Values", { Name = "A", Count = 2 }, function(a, b)
        return a.Name == b.Name
    end)
    self:applyPlan(plan)

    lu.assertEquals(#tbl.Values, 1)
end

function TestMutation_DefinitionLifecycle:testApplyAndRevertAreRepeatSafe()
    local plan = self.mutationPlan.createPlan()
    local tbl = { Values = {} }

    plan:append(tbl, "Values", "A")
    lu.assertTrue(self:applyPlan(plan))
    lu.assertFalse(self:applyPlan(plan))
    lu.assertEquals(tbl.Values, { "A" })

    lu.assertTrue(self:revertPlan(plan))
    lu.assertFalse(self:revertPlan(plan))
    lu.assertEquals(tbl.Values, {})
end

function TestMutation_DefinitionLifecycle:testAppendErrorsOnNonTableTarget()
    local plan = self.mutationPlan.createPlan()
    local tbl = { Values = 5 }

    plan:append(tbl, "Values", "A")
    lu.assertError(function()
        self:applyPlan(plan)
    end)
end

function TestMutation_DefinitionLifecycle:testAppendUniqueDoesNotAliasInsertedTable()
    local plan = self.mutationPlan.createPlan()
    local entry = { Name = "A", Meta = { Count = 1 } }
    local tbl = { Values = {} }

    plan:appendUnique(tbl, "Values", entry)
    self:applyPlan(plan)
    entry.Meta.Count = 999

    lu.assertEquals(tbl.Values[1].Meta.Count, 1)
end

function TestMutation_DefinitionLifecycle:testRemoveElementApplyAndRevert()
    local plan = self.mutationPlan.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:removeElement(tbl, "Values", "B")
    self:applyPlan(plan)

    lu.assertEquals(tbl.Values, { "A", "C" })

    self:revertPlan(plan)
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestMutation_DefinitionLifecycle:testRemoveElementCanUseCustomComparator()
    local plan = self.mutationPlan.createPlan()
    local tbl = { Values = { { Name = "A", Count = 1 }, { Name = "B", Count = 2 } } }

    plan:removeElement(tbl, "Values", { Name = "A", Count = 999 }, function(a, b)
        return a.Name == b.Name
    end)
    self:applyPlan(plan)

    lu.assertEquals(#tbl.Values, 1)
    lu.assertEquals(tbl.Values[1].Name, "B")
end

function TestMutation_DefinitionLifecycle:testSetElementApplyAndRevert()
    local plan = self.mutationPlan.createPlan()
    local tbl = { Values = { "A", "B", "C" } }

    plan:setElement(tbl, "Values", "B", "Z")
    self:applyPlan(plan)

    lu.assertEquals(tbl.Values, { "A", "Z", "C" })

    self:revertPlan(plan)
    lu.assertEquals(tbl.Values, { "A", "B", "C" })
end

function TestMutation_DefinitionLifecycle:testSetElementClonesReplacementTable()
    local plan = self.mutationPlan.createPlan()
    local replacement = { Name = "Z", Meta = { Count = 10 } }
    local tbl = { Values = { { Name = "A" }, { Name = "B" } } }

    plan:setElement(tbl, "Values", { Name = "B" }, replacement, function(a, b)
        return a.Name == b.Name
    end)
    self:applyPlan(plan)
    replacement.Meta.Count = 999

    lu.assertEquals(tbl.Values[2].Name, "Z")
    lu.assertEquals(tbl.Values[2].Meta.Count, 10)
end

function TestMutation_DefinitionLifecycle:testRemoveElementErrorsOnNonTableTarget()
    local plan = self.mutationPlan.createPlan()
    local tbl = { Values = 5 }

    plan:removeElement(tbl, "Values", "A")
    lu.assertError(function()
        self:applyPlan(plan)
    end)
end

function TestMutation_DefinitionLifecycle:testSetElementErrorsOnNonTableTarget()
    local plan = self.mutationPlan.createPlan()
    local tbl = { Values = 5 }

    plan:setElement(tbl, "Values", "A", "B")
    lu.assertError(function()
        self:applyPlan(plan)
    end)
end

function TestMutation_DefinitionLifecycle:testAffectsRunDataUsesPatchDeclarationOnly()
    local function affectsRunData(bundle)
        return self.mutation.bind("test-affects-run-data", bundle, {}, {}).affectsRunData()
    end
    lu.assertFalse(affectsRunData({ affectsRunData = true }))
    lu.assertTrue(affectsRunData({ patchMutation = function() end }))
    lu.assertFalse(affectsRunData({ affectsRunData = false }))
    lu.assertFalse(affectsRunData({ dataMutation = true }))
    lu.assertFalse(affectsRunData({}))
end

function TestMutation_DefinitionLifecycle:testCommitStagedStateCallsSettingsObserverAfterFlush()
    local calls = 0
    local observedValue = nil
    local config = {
        Enabled = true,
        Value = false,
    }
    local definition = self.moduleDefinition.prepareDefinition({}, {
        id = "CommitStagedStateObserver",
        name = "Commit stagedState Observer",
        storage = {
            {
                type = "bool",
                alias = "Value",
                default = false,
            },
        },
    })
    local store, stagedState, moduleState = createModuleState(self.harness, config, definition)
    local settingsObserver = function()
        calls = calls + 1
        observedValue = store.read("Value")
    end

    stagedState.write("Value", true)
    local ok, err = self:commitStagedState(definition, nil, settingsObserver, nil, store, moduleState.txn)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
    lu.assertTrue(config.Value)

    ok, err = self:commitStagedState(definition, nil, settingsObserver, nil, store, moduleState.txn)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
end

function TestMutation_DefinitionLifecycle:testCommitStagedStateCallsSettingsObserverForActions()
    local calls = 0
    local observedAction = nil
    local observedHasAction = nil
    local observedHasAnyAction = nil
    local observedConfigChange = nil
    local config = {
        Enabled = true,
    }
    local definition = self.moduleDefinition.prepareDefinition({}, {
        id = "CommitStagedStateActionObserver",
        name = "Commit stagedState Action Observer",
        storage = {},
        actions = {
            recording = function() end,
        },
    })
    local store, _, moduleState = createModuleState(self.harness, config, definition)
    local actionBuffer = moduleState.actionBuffer
    local settingsObserver = function(commit)
        calls = calls + 1
        local recording = commit.actions.get("recording")
        observedAction = recording:read()
        observedHasAction = recording:has()
        observedHasAnyAction = commit.actions.hasAny()
        observedConfigChange = commit.hadConfigChanges()
    end

    actionBuffer.stage("recording", { kind = "start" })
    local ok, err = self:commitStagedState(definition, nil, settingsObserver, nil, store, moduleState.txn)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertEquals(observedAction, { kind = "start" })
    lu.assertTrue(observedHasAction)
    lu.assertTrue(observedHasAnyAction)
    lu.assertFalse(observedConfigChange)
    lu.assertFalse(actionBuffer.hasAny())
    lu.assertFalse(moduleState.txn.isDirty())

    ok, err = self:commitStagedState(definition, nil, settingsObserver, nil, store, moduleState.txn)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
end

function TestMutation_DefinitionLifecycle:testCommitStagedStateAppliesMutationFromRawEnabledState()
    local buildCalls = 0
    local target = { Value = "base" }
    local config = {
        Enabled = true,
        Value = false,
    }
    local definition = self.moduleDefinition.prepareDefinition({}, {
        modpack = "test-pack-disabled-commit",
        id = "CommitStagedStateRawEnabled",
        name = "Commit stagedState Raw Enabled",
        storage = {
            {
                type = "bool",
                alias = "Value",
                default = false,
            },
        },
    })
    local store, stagedState, moduleState = createModuleState(self.harness, config, definition)
    local mutation = patchMutation(function(plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", "patched")
    end)

    stagedState.write("Value", true)
    local ok, err = self:commitStagedState(definition, mutation, nil, nil, store, moduleState.txn,
        "test-commit-raw-enabled")

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(config.Value)
    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "patched")
end

function TestMutation_DefinitionLifecycle:testApplyDefinitionSupportsPatchOnly()
    local store = self:makeStore(false)
    local target = { Value = 1 }
    local def = { id = "PatchOnly" }
    local pluginGuid = "test-patch-only"
    local mutation = patchMutation(function(plan)
        plan:set(target, "Value", 7)
    end)

    local ok, err = self:applyMutation(pluginGuid, def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 7)

    ok, err = self:revertMutation(pluginGuid, def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)
end

function TestMutation_DefinitionLifecycle:testPatchRuntimeSurvivesRecreatedStoreByPluginGuid()
    local target = { Value = 1 }
    local storeA = self:makeStore(true)
    local defA = {
        modpack = "test-pack",
        id = "StablePatchRuntimeA",
    }
    local mutationA = patchMutation(function(plan)
        plan:set(target, "Value", 7)
    end)

    local ok, err = self:applyMutation("test-stable-patch-runtime", defA, mutationA, nil, storeA)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 7)

    local storeB = self:makeStore(true)
    local defB = {
        modpack = "other-pack",
        id = "StablePatchRuntimeB",
    }
    local mutationB = patchMutation(function(plan)
        plan:set(target, "Value", 9)
    end)

    ok, err = self:applyMutation("test-stable-patch-runtime", defB, mutationB, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 9)

    ok, err = self:revertMutation("test-stable-patch-runtime", defB, mutationB, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)
end

function TestMutation_DefinitionLifecycle:testActivationSyncRevertsStablePatchWhenReloadedDisabled()
    local target = { Value = 1 }
    local pluginGuid = "test-disabled-reload-patch-runtime"
    local def = self.moduleDefinition.prepareDefinition({}, {
        id = "DisabledReloadPatchRuntime",
        name = "Disabled Reload Patch Runtime",
        storage = {},
    })
    local patch = function(plan)
        plan:set(target, "Value", 7)
    end

    local ok, err = self:activateMutationModule(pluginGuid, def, {
        Enabled = true,
        DebugMode = false,
    }, patch)
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(target.Value, 7)

    ok, err = self:activateMutationModule(pluginGuid, def, {
        Enabled = false,
        DebugMode = false,
    }, patch)

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(target.Value, 1)
end

function TestMutation_DefinitionLifecycle:testApplyDefinitionNoOpsWhenLifecycleMissingAndRunDataUnaffected()
    local store = self:makeStore(false)
    local def = { id = "NoLifecycle" }
    local pluginGuid = "test-no-lifecycle"

    local ok, err = self:applyMutation(pluginGuid, def, nil, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)

    ok, err = self:revertMutation(pluginGuid, def, nil, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
end

function TestMutation_DefinitionLifecycle:testApplyFailureRestoresPreviousPatchRuntime()
    local target = { Value = "base" }
    local storeA = self:makeStore(true)
    local pluginGuid = "test-restore-patch-runtime-on-apply-failure"
    local def = {
        modpack = "test-pack",
        id = "RestorePatchRuntimeOnApplyFailure",
    }
    local mutationA = patchMutation(function(plan)
        plan:set(target, "Value", "first")
    end)

    local ok, err = self:applyMutation(pluginGuid, def, mutationA, nil, storeA)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "first")

    local storeB = self:makeStore(true)
    local mutationB = patchMutation(function()
        error("replacement patch boom")
    end)

    ok, err = self:applyMutation(pluginGuid, def, mutationB, nil, storeB)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "replacement patch boom")
    lu.assertEquals(target.Value, "first")

    ok, err = self:revertMutation(pluginGuid, def, mutationA, nil, storeB)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "base")
end

function TestMutation_DefinitionLifecycle:testReapplyFailureRestoresPreviousPatchRuntime()
    local target = { Value = "base" }
    local store = self:makeStore(true)
    local pluginGuid = "test-restore-patch-runtime-on-reapply-failure"
    local def = {
        modpack = "test-pack",
        id = "RestorePatchRuntimeOnReapplyFailure",
    }
    local mutationA = patchMutation(function(plan)
        plan:set(target, "Value", "first")
    end)

    local ok, err = self:applyMutation(pluginGuid, def, mutationA, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "first")

    local mutationB = patchMutation(function()
        error("reapply patch boom")
    end)

    ok, err = self:applyMutation(pluginGuid, def, mutationB, nil, store)

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "reapply patch boom")
    lu.assertEquals(target.Value, "first")

    ok, err = self:revertMutation(pluginGuid, def, mutationA, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "base")
end

function TestMutation_DefinitionLifecycle:testActivationSyncDisabledDoesNotBuildInactivePatch()
    local buildCalls = 0
    local pluginGuid = "test-inactive-patch-revert"
    local def = self.moduleDefinition.prepareDefinition({}, {
        id = "InactivePatchRevert",
        name = "Inactive Patch Revert",
        storage = {},
    })

    local ok, err = self:activateMutationModule(pluginGuid, def, {
        Enabled = false,
        DebugMode = false,
    }, function()
        buildCalls = buildCalls + 1
    end)

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(buildCalls, 0)
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledCommitsOnlyAfterSuccessfulEnable()
    local store, _, moduleState = self:makeStore(false)
    local target = { Value = false }
    local def = { id = "SuccessfulEnable" }
    local mutation = patchMutation(function(plan)
        plan:set(target, "Value", true)
    end)

    local ok, err = self:setEnabled(def, mutation, nil, store, moduleState.txn, true, "test-successful-enable")

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(target.Value)
    lu.assertTrue(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledDoesNotCommitFailedEnable()
    local store, _, moduleState = self:makeStore(false)
    local def = { id = "FailedEnable" }
    local mutation = patchMutation(function()
        error("enable boom")
    end)

    local ok, err = self:setEnabled(def, mutation, nil, store, moduleState.txn, true, "test-failed-enable")

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "enable boom")
    lu.assertFalse(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledReappliesWhenAlreadyEnabled()
    local store, _, moduleState = self:makeStore(true)
    local target = { Value = 0 }
    local buildCalls = 0
    local def = { id = "ReapplyEnabled" }
    local pluginGuid = "test-reapply-enabled"
    local mutation = patchMutation(function(plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", buildCalls)
    end)

    local ok, err = self:applyMutation(pluginGuid, def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, 1)

    ok, err = self:setEnabled(def, mutation, nil, store, moduleState.txn, true, pluginGuid)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(buildCalls, 2)
    lu.assertEquals(target.Value, 2)
    lu.assertTrue(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledDisablesActivePatch()
    local store, _, moduleState = self:makeStore(true)
    local target = { Value = "base" }
    local def = { id = "DisableActivePatch" }
    local pluginGuid = "test-disable-active-patch"
    local mutation = patchMutation(function(plan)
        plan:set(target, "Value", "patched")
    end)

    local ok, err = self:applyMutation(pluginGuid, def, mutation, nil, store)
    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "patched")

    ok, err = self:setEnabled(def, mutation, nil, store, moduleState.txn, false, pluginGuid)

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(target.Value, "base")
    lu.assertFalse(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledNoOpsWhenAlreadyDisabled()
    local store, _, moduleState = self:makeStore(false)
    local buildCalls = 0
    local def = { id = "AlreadyDisabled" }
    local mutation = patchMutation(function()
        buildCalls = buildCalls + 1
    end)

    local ok, err = self:setEnabled(def, mutation, nil, store, moduleState.txn, false, "test-already-disabled")

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(buildCalls, 0)
    lu.assertFalse(store.read("Enabled"))
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledCommitsWhenStagedMirrorIsStale()
    local committed = true
    local staged = false
    local dirty = false
    local reloads = 0
    local committedSyncs = 0
    local def = { id = "StaleEnabledMirror" }
    local store = {
        read = function(alias)
            if alias == "Enabled" then
                return committed
            end
            return nil
        end,
    }
    local txn = createMirrorTxn(store, "Enabled", function()
        return staged
    end, function(value)
        staged = value
    end, {
        isDirty = function()
            return dirty
        end,
        setDirty = function(value)
            dirty = value
        end,
        commit = function()
            committed = staged
        end,
        reload = function()
            reloads = reloads + 1
            staged = committed
        end,
        sync = function()
            committedSyncs = committedSyncs + 1
            staged = committed
        end,
    })

    local ok, err = self:setEnabled(def, nil, nil, store, txn, false, "test-stale-enabled-mirror")

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(err)
    lu.assertFalse(committed)
    lu.assertFalse(staged)
    lu.assertEquals(reloads, 0)
    lu.assertEquals(committedSyncs, 1)
end

function TestMutation_DefinitionLifecycle:testSetDebugModeCommitsWhenStagedMirrorIsStale()
    local committed = false
    local staged = true
    local dirty = false
    local reloads = 0
    local committedSyncs = 0
    local def = { id = "StaleDebugMirror" }
    local store = {
        read = function(alias)
            if alias == "DebugMode" then
                return committed
            end
            if alias == "Enabled" then
                return false
            end
            return nil
        end,
    }
    local txn = createMirrorTxn(store, "DebugMode", function()
        return staged
    end, function(value)
        staged = value
    end, {
        isDirty = function()
            return dirty
        end,
        setDirty = function(value)
            dirty = value
        end,
        commit = function()
            committed = staged
        end,
        reload = function()
            reloads = reloads + 1
            staged = committed
        end,
        sync = function()
            committedSyncs = committedSyncs + 1
            staged = committed
        end,
    })
    local bound = self:bindMutation("test-stale-debug-mirror", def, nil, nil, store)

    local ok, err = self:bindLifecycle(def, bound, txn).setDebugMode(true)

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(err)
    lu.assertTrue(committed)
    lu.assertTrue(staged)
    lu.assertEquals(reloads, 0)
    lu.assertEquals(committedSyncs, 1)
end

function TestMutation_DefinitionLifecycle:testSetDefinitionEnabledAppliesFromRawEnabledState()
    local store, _, moduleState = self:makeStore(false)
    local target = { Value = "base" }
    local buildCalls = 0
    local def = {
        modpack = "test-pack-disabled-enable",
        id = "RawEnabledEnable",
    }
    local mutation = patchMutation(function(plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", "patched")
    end)

    local ok, err = self:setEnabled(def, mutation, nil, store, moduleState.txn, true,
        "test-pack-disabled-enable")

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertTrue(store.read("Enabled"))
    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "patched")
end
