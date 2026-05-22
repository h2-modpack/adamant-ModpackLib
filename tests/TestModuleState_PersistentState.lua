local lu = require('luaunit')
local helpers = require('tests/harness/module_state_helpers')

local createLibHarness = helpers.createLibHarness
local createModuleState = helpers.createModuleState
local withLoggingPolicy = helpers.withLoggingPolicy
local withCapturedPrint = helpers.withCapturedPrint
local makeScalarDefinition = helpers.makeScalarDefinition
local makePackedDefinition = helpers.makePackedDefinition
local makeTransientDefinition = helpers.makeTransientDefinition
local makeTableDefinition = helpers.makeTableDefinition

TestModuleState_PersistentState = {}

function TestModuleState_PersistentState:setUp()
    self.harness = createLibHarness()
end

function TestModuleState_PersistentState:tearDown()
    self.harness = nil
end

function TestModuleState_PersistentState:testCreatePersistentStateReadsAndWritesScalarAliases()
    local config = { Enabled = false, MaxGods = 4 }
    local persistentState, stagedState = createModuleState(self.harness, config, makeScalarDefinition(self.harness))

    lu.assertFalse(persistentState.read("Enabled"))
    lu.assertEquals(persistentState.read("MaxGods"), 4)
    lu.assertErrorMsgContains("store.unknown_alias", function()
        persistentState.read("MaxGodsPerRun")
    end)

    stagedState.write("Enabled", true)
    stagedState.write("MaxGods", 12)
    stagedState._flushToConfig()

    lu.assertTrue(config.Enabled)
    lu.assertEquals(config.MaxGods, 9)
    lu.assertEquals(persistentState.read("MaxGods"), 9)
end

function TestModuleState_PersistentState:testPersistentStateGetReturnsReadOnlyFieldOrTableHandle()
    local config = { Enabled = false, MaxGods = 4 }
    local persistentState, stagedState = createModuleState(self.harness, config, makeScalarDefinition(self.harness))
    local maxGods = persistentState.get("MaxGods")

    lu.assertIs(maxGods, persistentState.get("MaxGods"))
    lu.assertEquals(maxGods:alias(), "MaxGods")
    lu.assertEquals(maxGods:controlId(), "MaxGods")
    lu.assertEquals(maxGods:schema().alias, "MaxGods")
    lu.assertEquals(maxGods:read(), 4)
    lu.assertErrorMsgContains("storage.readonly_field", function()
        maxGods:write(6)
    end)

    stagedState.write("MaxGods", 8)
    stagedState._flushToConfig()
    lu.assertEquals(maxGods:read(), 8)

    local tableState = createModuleState(self.harness, {}, makeTableDefinition(self.harness))
    local tiers = tableState.get("Tiers")

    lu.assertIs(tiers, tableState.get("Tiers"))
    lu.assertEquals(tiers:count(), 1)
    lu.assertEquals(tiers:read(1, "Limit"), 2)
    local limit = tiers:get(1, "Limit")
    lu.assertIs(limit, tiers:get(1, "Limit"))
    lu.assertEquals(limit:alias(), "Limit")
    lu.assertEquals(limit:controlId(), "Tiers:1:Limit")
    lu.assertEquals(limit:schema().alias, "Limit")
    lu.assertEquals(limit:read(), 2)
    lu.assertErrorMsgContains("storage.readonly_field", function()
        limit:write(3)
    end)
    lu.assertNil(tiers.write)
end

function TestModuleState_PersistentState:testPackedAliasReadWriteUpdatesOwningRoot()
    local config = { Packed = 0 }
    local persistentState, stagedState = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    lu.assertFalse(persistentState.read("EnabledBit"))
    lu.assertEquals(persistentState.read("ModeBits"), 0)
    lu.assertEquals(persistentState.read("Packed"), 0)

    stagedState.write("EnabledBit", true)
    stagedState._flushToConfig()
    lu.assertEquals(config.Packed, 1)
    lu.assertTrue(persistentState.read("EnabledBit"))

    stagedState.write("ModeBits", 3)
    stagedState._flushToConfig()
    lu.assertEquals(config.Packed, 7)
    lu.assertEquals(persistentState.read("ModeBits"), 3)
end

function TestModuleState_PersistentState:testTransientAliasesAreNotReadableThroughPersistentState()
    local config = { Enabled = false }
    local persistentState, stagedState = createModuleState(self.harness, config, makeTransientDefinition(self.harness))

    lu.assertErrorMsgContains("store.invalid_surface", function()
        persistentState.read("FilterText")
    end)
    lu.assertEquals(stagedState.view.FilterText, "")
end

function TestModuleState_PersistentState:testPersistentStateGetRejectsTransientAndUnknownAliases()
    local config = { Enabled = false }
    local persistentState = createModuleState(self.harness, config, makeTransientDefinition(self.harness))

    lu.assertErrorMsgContains("store.invalid_surface", function()
        persistentState.get("FilterText")
    end)
    lu.assertErrorMsgContains("store.unknown_alias", function()
        persistentState.get("Missing")
    end)
end

function TestModuleState_PersistentState:testTableReadOnlyHandleClampsRawPersistedRows()
    local config = {
        Tiers = {
            { Limit = 1 },
            { Limit = 2 },
            { Limit = 3 },
            { Limit = 4 },
        },
    }
    local persistentState = createModuleState(self.harness, config, makeTableDefinition(self.harness))
    local tiers = persistentState.table("Tiers")

    lu.assertEquals(#config.Tiers, 3)
    lu.assertNil(config.Tiers[4])
    lu.assertEquals(tiers:count(), 3)
    lu.assertEquals(tiers:read(3, "Limit"), 3)
    lu.assertNil(tiers:read(4, "Limit"))
end

function TestModuleState_PersistentState.testDowngradedTableErrorsReturnNilSafely()
    withLoggingPolicy({
        ["store.unknown_alias"] = {
            severity = "warn",
            description = "Test downgraded unknown store table policy.",
        },
        ["store.invalid_table_alias"] = {
            severity = "warn",
            description = "Test downgraded invalid store table policy.",
        },
    }, function(harness)
        withCapturedPrint(harness, function(lines)
            local persistentState = createModuleState(harness, { Enabled = true, MaxGods = 5 }, makeScalarDefinition(harness))
            local missing = persistentState.table("Missing")
            local wrongType = persistentState.table("MaxGods")

            lu.assertNil(missing)
            lu.assertNil(wrongType)
            lu.assertEquals(#lines, 2)
        end)
    end)
end

