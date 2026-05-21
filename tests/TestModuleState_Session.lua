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
local makeTableDefinition = helpers.makeTableDefinition
local makeMinRowsTableDefinition = helpers.makeMinRowsTableDefinition

TestModuleState_Session = {}

function TestModuleState_Session:setUp()
    self.harness = createLibHarness()
end

function TestModuleState_Session:tearDown()
    self.harness = nil
end

function TestModuleState_Session:testSessionStagesScalarAliases()
    local config = { Enabled = true, MaxGods = 5 }
    local _, session = createModuleState(self.harness, config, makeScalarDefinition(self.harness))

    lu.assertTrue(session.view.Enabled)
    lu.assertEquals(session.view.MaxGods, 5)
    lu.assertFalse(session.isDirty())

    session.write("Enabled", false)
    lu.assertTrue(session.isDirty())
    lu.assertFalse(session.view.Enabled)

    session._flushToConfig()
    lu.assertFalse(session.isDirty())
    lu.assertFalse(config.Enabled)
end

function TestModuleState_Session:testPackedAliasEditReencodesPackedRootOnFlush()
    local config = { Packed = 0 }
    local _, session = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    session.write("ModeBits", 2)

    lu.assertTrue(session.isDirty())
    lu.assertEquals(session.view.ModeBits, 2)
    lu.assertEquals(session.view.Packed, 4)
    lu.assertEquals(config.Packed, 0)

    session._flushToConfig()

    lu.assertEquals(config.Packed, 4)
    lu.assertFalse(session.isDirty())
end

function TestModuleState_Session:testInternalReloadFromConfigRebuildsPackedChildren()
    local config = { Packed = 0 }
    local _, session = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    config.Packed = 5
    session._reloadFromConfig()

    lu.assertEquals(session.view.Packed, 5)
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.ModeBits, 2)
end

function TestModuleState_Session:testResyncSessionDetectsPackedDrift()
    local config = { Packed = 0 }
    local _, session = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    config.Packed = 5
    local mismatches = getHostLifecycle(self.harness).resyncSession({ name = "PackedSession" }, session)

    table.sort(mismatches)
    lu.assertEquals(mismatches, { "EnabledBit", "ModeBits", "Packed" })
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.ModeBits, 2)
    lu.assertEquals(session.view.Packed, 5)
end

function TestModuleState_Session:testReadonlyViewRejectsWrites()
    local config = { Enabled = true, MaxGods = 5 }
    local _, session = createModuleState(self.harness, config, makeScalarDefinition(self.harness))

    local ok, err = pcall(function()
        session.view.Enabled = false
    end)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "read-only")
end

function TestModuleState_Session:testTransientAliasesLiveOnlyInSession()
    local config = { Enabled = false }
    local _, session = createModuleState(self.harness, config, makeTransientDefinition(self.harness))

    lu.assertEquals(session.view.FilterText, "")
    lu.assertEquals(session.view.FilterMode, "all")
    lu.assertFalse(session.isDirty())

    session.write("FilterText", "Poseidon")
    session.write("FilterMode", "allowed")

    lu.assertEquals(session.view.FilterText, "Poseidon")
    lu.assertEquals(session.view.FilterMode, "allowed")
    lu.assertFalse(session.isDirty())

    session._flushToConfig()
    lu.assertFalse(session.isDirty())
    lu.assertNil(config.FilterText)
end

function TestModuleState_Session:testInternalReloadFromConfigResetsTransientAliasesToDefaults()
    local config = { Enabled = true }
    local _, session = createModuleState(self.harness, config, makeTransientDefinition(self.harness))

    session.write("FilterText", "Hera")
    session.write("FilterMode", "banned")
    config.Enabled = false

    session._reloadFromConfig()

    lu.assertFalse(session.view.Enabled)
    lu.assertEquals(session.view.FilterText, "")
    lu.assertEquals(session.view.FilterMode, "all")
end

function TestModuleState_Session:testResetRestoresTransientAliasDefault()
    local config = { Enabled = true }
    local _, session = createModuleState(self.harness, config, makeTransientDefinition(self.harness))

    session.write("FilterText", "Hermes")
    session.reset("FilterText")

    lu.assertEquals(session.view.FilterText, "")
    lu.assertFalse(session.isDirty())
end

function TestModuleState_Session:testResetRestoresPersistedAliasDefaultAndMarksDirty()
    local config = { Enabled = true, MaxGods = 5 }
    local _, session = createModuleState(self.harness, config, makeScalarDefinition(self.harness))

    session.reset("Enabled")

    lu.assertFalse(session.view.Enabled)
    lu.assertTrue(session.isDirty())

    session._flushToConfig()
    lu.assertFalse(config.Enabled)
end

function TestModuleState_Session:testResetRestoresPackedChildDefault()
    local config = { Packed = 0 }
    local _, session = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    session.write("EnabledBit", true)
    session.write("ModeBits", 3)
    session.reset("ModeBits")

    lu.assertEquals(session.view.ModeBits, 0)
    lu.assertTrue(session.view.EnabledBit)
    lu.assertEquals(session.view.Packed, 1)
end

function TestModuleState_Session:testTableStorageHydratesDefaultRows()
    local config = {}
    local _, session = createModuleState(self.harness, config, makeTableDefinition(self.harness))

    lu.assertEquals(session.table("Tiers"):count(), 1)
    lu.assertTrue(session.table("Tiers"):read(1, "Enabled"))
    lu.assertEquals(session.table("Tiers"):read(1, "Limit"), 2)
    lu.assertEquals(session.table("Tiers"):read(1, "PackedChoices"), 0)
    lu.assertEquals(#config.Tiers, 1)
end

function TestModuleState_Session:testTableStorageStagesRowWritesAndFlushesRoot()
    local config = {}
    local store, session = createModuleState(self.harness, config, makeTableDefinition(self.harness))
    local tiers = session.table("Tiers")

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

    session._flushToConfig()

    lu.assertEquals(#config.Tiers, 2)
    lu.assertEquals(config.Tiers[2].PackedChoices, 7)
    lu.assertEquals(config.Tiers[2].Limit, 5)
    lu.assertEquals(store.table("Tiers"):read(2, "ChoiceMode"), 3)
end

function TestModuleState_Session:testTableRowHandleReadsAndWritesThroughParentTable()
    local config = {}
    local store, session = createModuleState(self.harness, config, makeTableDefinition(self.harness))
    local tiers = session.table("Tiers")

    tiers:append({ Limit = 3, ChoiceA = true })
    local row = tiers:rowHandle(2)

    lu.assertEquals(row.read("Limit"), 3)
    lu.assertTrue(row.read("ChoiceA"))
    lu.assertEquals(row.getAliasSchema("PackedChoices").alias, "PackedChoices")

    lu.assertTrue(row.write("ChoiceMode", 2))
    lu.assertEquals(row.read("PackedChoices"), 5)
    lu.assertTrue(row.reset("ChoiceA"))
    lu.assertFalse(row.read("ChoiceA"))

    session._flushToConfig()
    local storeRow = store.table("Tiers"):rowHandle(2)

    lu.assertEquals(storeRow.read("ChoiceMode"), 2)
    lu.assertEquals(storeRow.getAliasSchema("ChoiceMode").alias, "ChoiceMode")
    lu.assertNil(storeRow.write)
    lu.assertNil(storeRow.reset)
end

function TestModuleState_Session:testSessionAndRowsCreateStorageFields()
    local _, session = createModuleState(self.harness, { Enabled = true, MaxGods = 5 }, makeScalarDefinition(self.harness))
    local rootField = session.field("MaxGods")

    lu.assertEquals(rootField:alias(), "MaxGods")
    lu.assertEquals(rootField:schema().alias, "MaxGods")
    lu.assertEquals(rootField:read(), 5)
    rootField:write(7)
    lu.assertEquals(session.read("MaxGods"), 7)

    local _, tableSession = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local row = tableSession.table("Tiers"):rowHandle(1)
    local rowField = row:field("Limit")

    lu.assertEquals(rowField:alias(), "Limit")
    lu.assertEquals(rowField:schema().alias, "Limit")
    lu.assertEquals(rowField:read(), 2)
    rowField:write(4)
    lu.assertEquals(row.read("Limit"), 4)
end

function TestModuleState_Session:testTableRowHandleIsPositionalAndMissingRowsAreNil()
    local _, session = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = session.table("Tiers")
    local row = tiers:rowHandle(2)

    lu.assertNil(row.read("Limit"))
    lu.assertFalse(row.write("Limit", 4))

    tiers:append({ Limit = 4 })
    lu.assertEquals(row.read("Limit"), 4)
end

function TestModuleState_Session:testTableStorageMutatesRowsAsCompactList()
    local config = {}
    local _, session = createModuleState(self.harness, config, makeTableDefinition(self.harness))
    local tiers = session.table("Tiers")

    tiers:append({ Limit = 1 })
    tiers:insert(2, { Limit = 3 })
    lu.assertEquals(tiers:count(), 3)
    lu.assertEquals(tiers:read(2, "Limit"), 3)

    tiers:remove(2)
    lu.assertEquals(tiers:count(), 2)
    lu.assertEquals(tiers:read(2, "Limit"), 1)

    tiers:resetRow(2)
    lu.assertEquals(tiers:read(2, "Limit"), 2)

    lu.assertTrue(tiers:clear())
    lu.assertEquals(tiers:count(), 0)
end

function TestModuleState_Session:testTableStorageClearReportsNoChangeWhenAlreadyDefault()
    local _, session = createModuleState(self.harness, {}, makeMinRowsTableDefinition(self.harness))
    local rows = session.table("Rows")

    lu.assertEquals(rows:count(), 1)
    lu.assertFalse(rows:clear())
    lu.assertEquals(rows:count(), 1)
    lu.assertFalse(session.isDirty())
end

function TestModuleState_Session:testTableStorageUnknownRowAliasFails()
    local _, session = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = session.table("Tiers")

    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:read(1, "MissingRowAlias")
    end)
    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:write(1, "MissingRowAlias", true)
    end)
    lu.assertErrorMsgContains("storage.unknown_table_row_alias", function()
        tiers:reset(1, "MissingRowAlias")
    end)
end

function TestModuleState_Session:testTableStorageHandleRequiresColonSyntax()
    local _, session = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = session.table("Tiers")

    lu.assertErrorMsgContains("storage.invalid_table_handle_args", function()
        tiers.read(1, "Enabled")
    end)
    lu.assertErrorMsgContains("storage.invalid_table_handle_args", function()
        tiers.count()
    end)
end

function TestModuleState_Session:testTableStorageAppendRespectsMaxRows()
    local _, session = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = session.table("Tiers")

    lu.assertTrue(tiers:append())
    lu.assertTrue(tiers:append())
    lu.assertFalse(tiers:append())
    lu.assertEquals(tiers:count(), 3)
end

function TestModuleState_Session:testTableStorageDoesNotLeakRowAliasesGlobally()
    local _, session = createModuleState(self.harness, {}, makeTableDefinition(self.harness))

    lu.assertErrorMsgContains("session.unknown_alias", function()
        session.read("Limit")
    end)
    lu.assertErrorMsgContains("session.unknown_alias", function()
        session.read("ChoiceA")
    end)
end

function TestModuleState_Session:testSessionWriteUnknownAliasFails()
    local _, session = createModuleState(self.harness, {}, makeScalarDefinition(self.harness))

    lu.assertErrorMsgContains("unknown alias 'Nope'", function()
        session.write("Nope", true)
    end)
end

function TestModuleState_Session:testSessionReadUnknownAliasFails()
    local _, session = createModuleState(self.harness, {}, makeScalarDefinition(self.harness))

    lu.assertErrorMsgContains("session.unknown_alias", function()
        session.read("Nope")
    end)
end

function TestModuleState_Session:testSessionResetUnknownAliasFails()
    local _, session = createModuleState(self.harness, {}, makeScalarDefinition(self.harness))

    lu.assertErrorMsgContains("unknown alias 'Nope'", function()
        session.reset("Nope")
    end)
end

function TestModuleState_Session.testDowngradedSessionResetUnknownAliasReturnsSafely()
    withLoggingPolicy({
        ["session.unknown_alias"] = {
            severity = "warn",
            description = "Test downgraded session reset policy.",
        },
    }, function(harness)
        withCapturedPrint(harness, function(lines)
            local _, session = createModuleState(harness, {}, makeScalarDefinition(harness))

            session.reset("Nope")

            lu.assertFalse(session.isDirty())
            lu.assertEquals(#lines, 1)
        end)
    end)
end

function TestModuleState_Session:testSessionTableWrongAliasFails()
    local _, session = createModuleState(self.harness, {}, makeScalarDefinition(self.harness))

    lu.assertErrorMsgContains("is not table storage", function()
        session.table("Enabled")
    end)
end

function TestModuleState_Session.testDowngradedSessionTableErrorsReturnNilSafely()
    withLoggingPolicy({
        ["session.unknown_alias"] = {
            severity = "warn",
            description = "Test downgraded unknown session table policy.",
        },
        ["session.invalid_table_alias"] = {
            severity = "warn",
            description = "Test downgraded invalid session table policy.",
        },
    }, function(harness)
        withCapturedPrint(harness, function(lines)
            local _, session = createModuleState(harness, { Enabled = true, MaxGods = 5 }, makeScalarDefinition(harness))
            local missing = session.table("Missing")
            local wrongType = session.table("MaxGods")

            lu.assertNil(missing)
            lu.assertNil(wrongType)
            lu.assertEquals(#lines, 2)
        end)
    end)
end

function TestModuleState_Session:testReadonlyViewDoesNotExposeMutableTableRoot()
    local _, session = createModuleState(self.harness, {}, makeTableDefinition(self.harness))

    local snapshot = session.view.Tiers
    snapshot[1].Limit = 5

    lu.assertEquals(session.table("Tiers"):read(1, "Limit"), 2)
end

function TestModuleState_Session:testTableStorageHashRoundTripsRows()
    local definition = makeTableDefinition(self.harness)
    local tableNode = definition.storage[3]
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

function TestModuleState_Session:testDrawActionsAreSeparateFromSessionDirtyState()
    local definition = prepareDefinition(self.harness, {
        id = "DrawActionTest",
        name = "Draw Action Test",
        storage = {},
    })
    local _, session = createModuleState(self.harness, {}, definition)
    local actionState = self.harness.moduleState.createActionState()
    local actions = self.harness.moduleState.createDrawActions(actionState)
    local recording = actions.get("recording")

    lu.assertFalse(actions.hasAny())
    lu.assertFalse(recording:has())

    recording:stage({ kind = "start" })

    lu.assertTrue(actions.hasAny())
    lu.assertTrue(actionState.hasAny())
    lu.assertFalse(session.isDirty())
    lu.assertTrue(recording:has())
    lu.assertEquals(recording:read(), { kind = "start" })

    recording:clear()

    lu.assertFalse(actions.hasAny())
    lu.assertFalse(actionState.hasAny())
    lu.assertFalse(session.isDirty())
end

function TestModuleState_Session:testActionRefsRequireMethodCallSyntax()
    local actionState = self.harness.moduleState.createActionState()
    local drawAction = self.harness.moduleState.createDrawActions(actionState).get("recording")
    local commitAction = self.harness.moduleState.createCommitActions({ recording = true }).get("recording")

    lu.assertErrorMsgContains("api.invalid_method_call", function()
        drawAction.stage(true)
    end)
    lu.assertErrorMsgContains("api.invalid_method_call", function()
        commitAction.read()
    end)
end
