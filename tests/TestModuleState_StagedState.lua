local lu = require('luaunit')
local helpers = require('tests/harness/module_state_helpers')

local createLibHarness = helpers.createLibHarness
local prepareDefinition = helpers.prepareDefinition
local createModuleState = helpers.createModuleState
local getHostLifecycle = helpers.getHostLifecycle
local withLoggingPolicy = helpers.withLoggingPolicy
local withCapturedPrint = helpers.withCapturedPrint
local makeScalarDefinition = helpers.makeScalarDefinition
local makePackedDefinition = helpers.makePackedDefinition
local makeTransientDefinition = helpers.makeTransientDefinition
local makeRuntimeDefinition = helpers.makeRuntimeDefinition
local makeTableDefinition = helpers.makeTableDefinition
local makeMinRowsTableDefinition = helpers.makeMinRowsTableDefinition

TestModuleState_StagedState = {}

local function inDraw(harness, callback)
    return harness.phaseGate.runDraw(callback)
end

function TestModuleState_StagedState:setUp()
    self.harness = createLibHarness()
end

function TestModuleState_StagedState:tearDown()
    self.harness = nil
end

function TestModuleState_StagedState:testStagedStateStagesScalarAliases()
    local config = { Enabled = true, MaxGods = 5 }
    local _, stagedState = createModuleState(self.harness, config, makeScalarDefinition(self.harness))

    lu.assertTrue(stagedState.view.Enabled)
    lu.assertEquals(stagedState.view.MaxGods, 5)
    lu.assertFalse(stagedState.isDirty())

    stagedState.write("Enabled", false)
    lu.assertTrue(stagedState.isDirty())
    lu.assertFalse(stagedState.view.Enabled)

    stagedState._flushToConfig()
    lu.assertFalse(stagedState.isDirty())
    lu.assertFalse(config.Enabled)
end

function TestModuleState_StagedState:testPackedAliasEditReencodesPackedRootOnFlush()
    local config = { Packed = 0 }
    local _, stagedState = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    stagedState.write("ModeBits", 2)

    lu.assertTrue(stagedState.isDirty())
    lu.assertEquals(stagedState.view.ModeBits, 2)
    lu.assertEquals(stagedState.view.Packed, 4)
    lu.assertEquals(config.Packed, 0)

    stagedState._flushToConfig()

    lu.assertEquals(config.Packed, 4)
    lu.assertFalse(stagedState.isDirty())
end

function TestModuleState_StagedState:testInternalReloadFromConfigRebuildsPackedChildren()
    local config = { Packed = 0 }
    local _, stagedState = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    config.Packed = 5
    stagedState._reloadFromConfig()

    lu.assertEquals(stagedState.view.Packed, 5)
    lu.assertTrue(stagedState.view.EnabledBit)
    lu.assertEquals(stagedState.view.ModeBits, 2)
end

function TestModuleState_StagedState:testResyncStagedStateDetectsPackedDrift()
    local config = { Packed = 0 }
    local _, stagedState = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    config.Packed = 5
    local mismatches = getHostLifecycle(self.harness).resyncStagedState({ name = "PackedStagedState" }, stagedState)

    table.sort(mismatches)
    lu.assertEquals(mismatches, { "EnabledBit", "ModeBits", "Packed" })
    lu.assertTrue(stagedState.view.EnabledBit)
    lu.assertEquals(stagedState.view.ModeBits, 2)
    lu.assertEquals(stagedState.view.Packed, 5)
end

function TestModuleState_StagedState:testReadonlyViewRejectsWrites()
    local config = { Enabled = true, MaxGods = 5 }
    local _, stagedState = createModuleState(self.harness, config, makeScalarDefinition(self.harness))

    local ok, err = pcall(function()
        stagedState.view.Enabled = false
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "read-only")
end

function TestModuleState_StagedState:testTransientAliasesLiveOnlyInStagedState()
    local config = { Enabled = false }
    local _, stagedState = createModuleState(self.harness, config, makeTransientDefinition(self.harness))

    lu.assertEquals(stagedState.view.FilterText, "")
    lu.assertEquals(stagedState.view.FilterMode, "all")
    lu.assertFalse(stagedState.isDirty())

    stagedState.write("FilterText", "Poseidon")
    stagedState.write("FilterMode", "allowed")

    lu.assertEquals(stagedState.view.FilterText, "Poseidon")
    lu.assertEquals(stagedState.view.FilterMode, "allowed")
    lu.assertFalse(stagedState.isDirty())

    stagedState._flushToConfig()
    lu.assertFalse(stagedState.isDirty())
    lu.assertNil(config.FilterText)
end

function TestModuleState_StagedState:testRuntimeStorageIsReadOnlyFromStagedState()
    local persistentState, stagedState = createModuleState(self.harness, {}, makeRuntimeDefinition(self.harness))

    lu.assertFalse(stagedState.view.RuntimeFlag)
    lu.assertTrue(persistentState.runtimeOwned.set("RuntimeFlag", true))
    lu.assertTrue(stagedState.view.RuntimeFlag)
    lu.assertTrue(stagedState.runtimeOwned.read("RuntimeFlag"))
    lu.assertTrue(stagedState.runtimeOwned.get("RuntimeFlag"):read())
    lu.assertErrorMsgContains("runtime-owned", function()
        stagedState.read("RuntimeFlag")
    end)
    lu.assertErrorMsgContains("runtime-owned", function()
        stagedState.get("RuntimeFlag")
    end)
    lu.assertErrorMsgContains("runtime-owned", function()
        stagedState.write("RuntimeFlag", false)
    end)
    lu.assertErrorMsgContains("runtime-owned", function()
        stagedState.write("RuntimeBit", true)
    end)
    lu.assertTrue(stagedState.view.RuntimeFlag)

    local runtimeRows = stagedState.runtimeOwned.get("RuntimeRows")
    lu.assertEquals(runtimeRows:count(), 1)
    lu.assertFalse(runtimeRows:read(1, "Enabled"))
    lu.assertNil(runtimeRows.write)
    lu.assertNil(runtimeRows.append)
end

function TestModuleState_StagedState:testRuntimeTableWriteThroughDrawStateFailsSemantically()
    local persistentState, stagedState = createModuleState(self.harness, {}, makeRuntimeDefinition(self.harness))
    local state = self.harness.moduleState.uiState.create(stagedState)
    persistentState.runtimeOwned.set("RuntimeFlag", true)

    inDraw(self.harness, function()
        lu.assertTrue(state.runtimeOwned.read("RuntimeFlag"))
        lu.assertTrue(state.runtimeOwned.get("RuntimeFlag"):read())
        lu.assertErrorMsgContains("runtime-owned", function()
            state.read("RuntimeFlag")
        end)
        lu.assertErrorMsgContains("runtime-owned", function()
            state.get("RuntimeFlag")
        end)
    end)

    lu.assertErrorMsgContains("staged_state.invalid_surface", function()
        inDraw(self.harness, function()
            state.write("RuntimeRows", 1, "Enabled", true)
        end)
    end)
end

function TestModuleState_StagedState:testInternalReloadFromConfigResetsTransientAliasesToDefaults()
    local config = { Enabled = true }
    local _, stagedState = createModuleState(self.harness, config, makeTransientDefinition(self.harness))

    stagedState.write("FilterText", "Hera")
    stagedState.write("FilterMode", "banned")
    config.Enabled = false

    stagedState._reloadFromConfig()

    lu.assertFalse(stagedState.view.Enabled)
    lu.assertEquals(stagedState.view.FilterText, "")
    lu.assertEquals(stagedState.view.FilterMode, "all")
end

function TestModuleState_StagedState:testResetRestoresTransientAliasDefault()
    local config = { Enabled = true }
    local _, stagedState = createModuleState(self.harness, config, makeTransientDefinition(self.harness))

    stagedState.write("FilterText", "Hermes")
    stagedState.reset("FilterText")

    lu.assertEquals(stagedState.view.FilterText, "")
    lu.assertFalse(stagedState.isDirty())
end

function TestModuleState_StagedState:testResetRestoresPersistedAliasDefaultAndMarksDirty()
    local config = { Enabled = true, MaxGods = 5 }
    local _, stagedState = createModuleState(self.harness, config, makeScalarDefinition(self.harness))

    stagedState.reset("Enabled")

    lu.assertFalse(stagedState.view.Enabled)
    lu.assertTrue(stagedState.isDirty())

    stagedState._flushToConfig()
    lu.assertFalse(config.Enabled)
end

function TestModuleState_StagedState:testResetRestoresPackedChildDefault()
    local config = { Packed = 0 }
    local _, stagedState = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    stagedState.write("EnabledBit", true)
    stagedState.write("ModeBits", 3)
    stagedState.reset("ModeBits")

    lu.assertEquals(stagedState.view.ModeBits, 0)
    lu.assertTrue(stagedState.view.EnabledBit)
    lu.assertEquals(stagedState.view.Packed, 1)
end

function TestModuleState_StagedState:testResetAllRestoresPersistedRootsOnly()
    local definition = prepareDefinition(self.harness, {
        storage = {
            { type = "int", alias = "MaxGods", default = 3, min = 1, max = 9 },
            { type = "string", alias = "FilterText", persist = false, hash = false, default = "", maxLen = 64 },
        },
    })
    local _, stagedState = createModuleState(self.harness, { MaxGods = 7 }, definition)

    stagedState.write("MaxGods", 5)
    stagedState.write("FilterText", "Hermes")
    local changed, count = stagedState.resetAll()

    lu.assertTrue(changed)
    lu.assertEquals(count, 1)
    lu.assertEquals(stagedState.view.MaxGods, 3)
    lu.assertEquals(stagedState.view.FilterText, "Hermes")
    lu.assertTrue(stagedState.isDirty())
end

function TestModuleState_StagedState:testResetAllHonorsExcludedRoots()
    local _, stagedState = createModuleState(self.harness, { MaxGods = 7 }, makeScalarDefinition(self.harness))

    stagedState.write("MaxGods", 5)
    local changed, count = stagedState.resetAll({
        exclude = {
            MaxGods = true,
        },
    })

    lu.assertFalse(changed)
    lu.assertEquals(count, 0)
    lu.assertEquals(stagedState.view.MaxGods, 5)
end

function TestModuleState_StagedState:testTableStorageHydratesDefaultRows()
    local config = {}
    local _, stagedState = createModuleState(self.harness, config, makeTableDefinition(self.harness))

    lu.assertEquals(stagedState.table("Tiers"):count(), 1)
    lu.assertTrue(stagedState.table("Tiers"):read(1, "Enabled"))
    lu.assertEquals(stagedState.table("Tiers"):read(1, "Limit"), 2)
    lu.assertEquals(stagedState.table("Tiers"):read(1, "PackedChoices"), 0)
    lu.assertEquals(#config.Tiers, 1)
end

function TestModuleState_StagedState:testTableStorageStagesRowWritesAndFlushesRoot()
    local config = {}
    local store, stagedState = createModuleState(self.harness, config, makeTableDefinition(self.harness))
    local tiers = stagedState.table("Tiers")

    lu.assertTrue(tiers:append({ Enabled = false, Limit = 4, ChoiceA = true }))
    lu.assertTrue(tiers:write(2, "ChoiceMode", 3))
    lu.assertTrue(tiers:write(2, "Limit", 9))

    lu.assertEquals(tiers:count(), 2)
    lu.assertFalse(tiers:read(2, "Enabled"))
    lu.assertTrue(tiers:read(2, "ChoiceA"))
    lu.assertEquals(tiers:read(2, "ChoiceMode"), 3)
    lu.assertEquals(tiers:read(2, "PackedChoices"), 7)
    lu.assertEquals(tiers:read(2, "Limit"), 5)
    lu.assertEquals(#config.Tiers, 1)

    stagedState._flushToConfig()

    lu.assertEquals(#config.Tiers, 2)
    lu.assertEquals(config.Tiers[2].PackedChoices, 7)
    lu.assertEquals(config.Tiers[2].Limit, 5)
    lu.assertEquals(store.table("Tiers"):read(2, "ChoiceMode"), 3)
end

function TestModuleState_StagedState:testTableHandleReadsWritesAndCreatesCellFields()
    local config = {}
    local store, stagedState = createModuleState(self.harness, config, makeTableDefinition(self.harness))
    local tiers = stagedState.table("Tiers")

    tiers:append({ Limit = 3, ChoiceA = true })

    lu.assertEquals(tiers:read(2, "Limit"), 3)
    lu.assertTrue(tiers:read(2, "ChoiceA"))
    lu.assertEquals(tiers:get(2, "PackedChoices"):schema().alias, "PackedChoices")

    lu.assertTrue(tiers:write(2, "ChoiceMode", 2))
    lu.assertEquals(tiers:read(2, "PackedChoices"), 5)
    lu.assertTrue(tiers:reset(2, "ChoiceA"))
    lu.assertFalse(tiers:read(2, "ChoiceA"))

    stagedState._flushToConfig()
    local storeTiers = store.table("Tiers")
    local publicStore = self.harness.moduleState.createStore(store)
    local publicStoreTiers = publicStore.get("Tiers")
    local publicStoreChoiceMode = publicStoreTiers:get(2, "ChoiceMode")

    lu.assertEquals(storeTiers:read(2, "ChoiceMode"), 2)
    lu.assertEquals(publicStoreChoiceMode:schema().alias, "ChoiceMode")
    lu.assertNil(publicStoreChoiceMode.write)
end

function TestModuleState_StagedState:testStagedStateAndRowsCreateStorageFields()
    local _, stagedState = createModuleState(self.harness, { Enabled = true, MaxGods = 5 }, makeScalarDefinition(self.harness))
    local rootField = stagedState.field("MaxGods")

    lu.assertEquals(rootField:alias(), "MaxGods")
    lu.assertEquals(rootField:controlId(), "MaxGods")
    lu.assertEquals(rootField:schema().alias, "MaxGods")
    lu.assertEquals(rootField:read(), 5)
    rootField:write(7)
    lu.assertEquals(stagedState.read("MaxGods"), 7)

    local _, tableStagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local rows = tableStagedState.table("Tiers")
    local rowField = rows:get(1, "Limit")

    lu.assertEquals(rowField:alias(), "Limit")
    lu.assertEquals(rowField:controlId(), "Tiers:1:Limit")
    lu.assertEquals(rowField:schema().alias, "Limit")
    lu.assertEquals(rowField:read(), 2)
    rowField:write(4)
    lu.assertEquals(rows:read(1, "Limit"), 4)
end

function TestModuleState_StagedState:testStagedStateGetReturnsFieldOrTableHandle()
    local _, stagedState = createModuleState(self.harness, { Enabled = true, MaxGods = 5 }, makeScalarDefinition(self.harness))
    local maxGods = stagedState.get("MaxGods")

    lu.assertIs(maxGods, stagedState.get("MaxGods"))
    lu.assertEquals(maxGods:alias(), "MaxGods")
    lu.assertEquals(maxGods:controlId(), "MaxGods")
    lu.assertEquals(maxGods:schema().alias, "MaxGods")
    lu.assertEquals(maxGods:read(), 5)
    maxGods:write(7)
    lu.assertEquals(stagedState.read("MaxGods"), 7)

    local _, tableStagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = tableStagedState.get("Tiers")

    lu.assertIs(tiers, tableStagedState.get("Tiers"))
    lu.assertEquals(tiers:count(), 1)
    lu.assertEquals(tiers:read(1, "Limit"), 2)
    local limit = tiers:get(1, "Limit")
    lu.assertIs(limit, tiers:get(1, "Limit"))
    lu.assertEquals(limit:alias(), "Limit")
    lu.assertEquals(limit:controlId(), "Tiers:1:Limit")
    lu.assertEquals(limit:schema().alias, "Limit")
    lu.assertEquals(limit:read(), 2)
    limit:write(5)
    lu.assertEquals(tiers:read(1, "Limit"), 5)
    limit:reset()
    lu.assertEquals(tiers:read(1, "Limit"), 2)
    lu.assertTrue(tiers:write(1, "Limit", 4))
    lu.assertEquals(tableStagedState.table("Tiers"):read(1, "Limit"), 4)
end

function TestModuleState_StagedState:testTableSnapshotsReturnCopiedRows()
    local _, stagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = stagedState.get("Tiers")

    local rowSnapshot = tiers:snapshot(1)
    rowSnapshot.Limit = 5
    lu.assertEquals(tiers:read(1, "Limit"), 2)

    local allSnapshots = tiers:snapshots()
    allSnapshots[1].Limit = 6
    lu.assertEquals(tiers:read(1, "Limit"), 2)
    lu.assertNil(tiers:snapshot(99))
end

function TestModuleState_StagedState:testTableStructuralEditsRefreshControlIdCache()
    local _, stagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = stagedState.get("Tiers")

    tiers:append({ Limit = 4 })
    tiers:append({ Limit = 6 })
    local thirdLimit = tiers:get(3, "Limit")
    lu.assertEquals(thirdLimit:controlId(), "Tiers:3:Limit")

    lu.assertTrue(tiers:remove(2))
    lu.assertEquals(tiers:get(2, "Limit"):controlId(), "Tiers:2:Limit")

    lu.assertTrue(tiers:insert(2, { Limit = 5 }))
    lu.assertEquals(tiers:get(3, "Limit"):controlId(), "Tiers:3:Limit")

    lu.assertTrue(tiers:clear())
    lu.assertTrue(tiers:append({ Limit = 8 }))
    lu.assertEquals(tiers:get(1, "Limit"):controlId(), "Tiers:1:Limit")
end

function TestModuleState_StagedState:testTableCellFieldsArePositionalAndMissingRowsAreNil()
    local _, stagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = stagedState.table("Tiers")
    local limit = tiers:get(2, "Limit")

    lu.assertNil(limit:read())
    lu.assertFalse(limit:write(4))

    tiers:append({ Limit = 4 })
    lu.assertEquals(limit:read(), 4)
end

function TestModuleState_StagedState:testTableStorageMutatesRowsAsCompactList()
    local config = {}
    local _, stagedState = createModuleState(self.harness, config, makeTableDefinition(self.harness))
    local tiers = stagedState.table("Tiers")

    tiers:append({ Limit = 1 })
    tiers:insert(2, { Limit = 3 })
    lu.assertEquals(tiers:count(), 3)
    lu.assertEquals(tiers:read(2, "Limit"), 3)

    tiers:remove(2)
    lu.assertEquals(tiers:count(), 2)
    lu.assertEquals(tiers:read(2, "Limit"), 1)

    lu.assertTrue(tiers:clear())
    lu.assertEquals(tiers:count(), 0)
end

function TestModuleState_StagedState:testTableStorageClearReportsNoChangeWhenAlreadyDefault()
    local _, stagedState = createModuleState(self.harness, {}, makeMinRowsTableDefinition(self.harness))
    local rows = stagedState.table("Rows")

    lu.assertEquals(rows:count(), 1)
    lu.assertFalse(rows:clear())
    lu.assertEquals(rows:count(), 1)
    lu.assertFalse(stagedState.isDirty())
end

function TestModuleState_StagedState:testTableStorageUnknownRowAliasFails()
    local _, stagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = stagedState.table("Tiers")

    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:read(1, "MissingRowAlias")
    end)
    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:get(1, "MissingRowAlias")
    end)
    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:write(1, "MissingRowAlias", true)
    end)
    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:reset(1, "MissingRowAlias")
    end)
end

function TestModuleState_StagedState:testTableStorageHandleRequiresColonSyntax()
    local _, stagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = stagedState.table("Tiers")

    lu.assertErrorMsgContains("storage.invalid_table_handle_args", function()
        tiers.read(1, "Enabled")
    end)
    lu.assertErrorMsgContains("storage.invalid_table_handle_args", function()
        tiers.get(1, "Enabled")
    end)
    lu.assertErrorMsgContains("storage.invalid_table_handle_args", function()
        tiers.count()
    end)
end

function TestModuleState_StagedState:testTableStorageAppendRespectsMaxRows()
    local _, stagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = stagedState.table("Tiers")

    lu.assertTrue(tiers:append())
    lu.assertTrue(tiers:append())
    lu.assertFalse(tiers:append())
    lu.assertEquals(tiers:count(), 3)
end

function TestModuleState_StagedState:testTableStorageDoesNotLeakRowAliasesGlobally()
    local _, stagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))

    lu.assertErrorMsgContains("staged_state.unknown_alias", function()
        stagedState.read("Limit")
    end)
    lu.assertErrorMsgContains("staged_state.unknown_alias", function()
        stagedState.read("ChoiceA")
    end)
end

function TestModuleState_StagedState:testStagedStateWriteUnknownAliasFails()
    local _, stagedState = createModuleState(self.harness, {}, makeScalarDefinition(self.harness))

    lu.assertErrorMsgContains("unknown alias 'Nope'", function()
        stagedState.write("Nope", true)
    end)
end

function TestModuleState_StagedState:testStagedStateReadUnknownAliasFails()
    local _, stagedState = createModuleState(self.harness, {}, makeScalarDefinition(self.harness))

    lu.assertErrorMsgContains("staged_state.unknown_alias", function()
        stagedState.read("Nope")
    end)
end

function TestModuleState_StagedState:testStagedStateGetUnknownAliasFails()
    local _, stagedState = createModuleState(self.harness, {}, makeScalarDefinition(self.harness))

    lu.assertErrorMsgContains("staged_state.unknown_alias", function()
        stagedState.get("Nope")
    end)
end

function TestModuleState_StagedState:testStagedStateResetUnknownAliasFails()
    local _, stagedState = createModuleState(self.harness, {}, makeScalarDefinition(self.harness))

    lu.assertErrorMsgContains("unknown alias 'Nope'", function()
        stagedState.reset("Nope")
    end)
end

function TestModuleState_StagedState.testDowngradedStagedStateResetUnknownAliasReturnsSafely()
    withLoggingPolicy({
        ["staged_state.unknown_alias"] = {
            severity = "warn",
            description = "Test downgraded stagedState reset policy.",
        },
    }, function(harness)
        withCapturedPrint(harness, function(lines)
            local _, stagedState = createModuleState(harness, {}, makeScalarDefinition(harness))

            stagedState.reset("Nope")

            lu.assertFalse(stagedState.isDirty())
            lu.assertEquals(#lines, 1)
        end)
    end)
end

function TestModuleState_StagedState:testStagedStateTableWrongAliasFails()
    local _, stagedState = createModuleState(self.harness, {}, makeScalarDefinition(self.harness))

    lu.assertErrorMsgContains("is not table storage", function()
        stagedState.table("Enabled")
    end)
end

function TestModuleState_StagedState.testDowngradedStagedStateTableErrorsReturnNilSafely()
    withLoggingPolicy({
        ["staged_state.unknown_alias"] = {
            severity = "warn",
            description = "Test downgraded unknown stagedState table policy.",
        },
        ["staged_state.invalid_table_alias"] = {
            severity = "warn",
            description = "Test downgraded invalid stagedState table policy.",
        },
    }, function(harness)
        withCapturedPrint(harness, function(lines)
            local _, stagedState = createModuleState(harness, { Enabled = true, MaxGods = 5 }, makeScalarDefinition(harness))
            local missing = stagedState.table("Missing")
            local wrongType = stagedState.table("MaxGods")

            lu.assertNil(missing)
            lu.assertNil(wrongType)
            lu.assertEquals(#lines, 2)
        end)
    end)
end

function TestModuleState_StagedState:testReadonlyViewDoesNotExposeMutableTableRoot()
    local _, stagedState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))

    local snapshot = stagedState.view.Tiers
    snapshot[1].Limit = 5

    lu.assertEquals(stagedState.table("Tiers"):read(1, "Limit"), 2)
end

function TestModuleState_StagedState:testTableStorageHashRoundTripsRows()
    local definition = makeTableDefinition(self.harness)
    local tableNode = definition.storage[4]
    local value = {
        { Enabled = false, Limit = 4, PackedChoices = 5 },
        { Enabled = true, Limit = 1, ChoiceMode = 2, Note = "a|b=%c" },
    }

    local encoded = self.harness.hashing.toHash(tableNode, value)
    local decoded = self.harness.hashing.fromHash(tableNode, encoded)

    lu.assertEquals(#decoded, 2)
    lu.assertFalse(decoded[1].Enabled)
    lu.assertEquals(decoded[1].Limit, 4)
    lu.assertEquals(decoded[1].PackedChoices, 5)
    lu.assertTrue(decoded[2].Enabled)
    lu.assertEquals(decoded[2].Limit, 1)
    lu.assertEquals(decoded[2].Note, "a|b=%c")
    lu.assertEquals(decoded[2].PackedChoices, 4)
end

function TestModuleState_StagedState:testDrawActionsAreSeparateFromStagedStateDirtyState()
    local definition = prepareDefinition(self.harness, {
        id = "DrawActionTest",
        name = "Draw Action Test",
        storage = {},
    })
    local _, stagedState = createModuleState(self.harness, {}, definition)
    local actionBuffer = self.harness.moduleState.createActionBuffer()
    local actions = self.harness.uiActions.create(actionBuffer)
    local recording = inDraw(self.harness, function()
        return actions.get("recording")
    end)

    inDraw(self.harness, function()
        lu.assertFalse(actionBuffer.hasAny())
        lu.assertFalse(recording:has())

        actions.trigger("recording", { kind = "start" })

        lu.assertTrue(actionBuffer.hasAny())
        lu.assertFalse(stagedState.isDirty())
        lu.assertTrue(recording:has())
        lu.assertEquals(recording:read(), { kind = "start" })

        recording:clear()

        lu.assertFalse(actionBuffer.hasAny())
    end)

    lu.assertFalse(stagedState.isDirty())
    lu.assertFalse(actionBuffer.hasAny())
end

function TestModuleState_StagedState:testActionRefsRequireMethodCallSyntax()
    local actionBuffer = self.harness.moduleState.createActionBuffer()
    local actions = self.harness.uiActions.create(actionBuffer)
    local drawAction = inDraw(self.harness, function()
        return actions.get("recording")
    end)
    local commitAction = self.harness.moduleState.createCommitActions({ recording = true }).get("recording")

    lu.assertErrorMsgContains("api.invalid_method_call", function()
        inDraw(self.harness, function()
            drawAction.stage(true)
        end)
    end)
    lu.assertErrorMsgContains("api.invalid_method_call", function()
        commitAction.read()
    end)
end
