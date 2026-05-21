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

TestModuleState_Store = {}

function TestModuleState_Store:setUp()
    self.harness = createLibHarness()
end

function TestModuleState_Store:tearDown()
    self.harness = nil
end

function TestModuleState_Store:testCreateStoreReadsAndWritesScalarAliases()
    local config = { Enabled = false, MaxGods = 4 }
    local store, session = createModuleState(self.harness, config, makeScalarDefinition(self.harness))

    lu.assertFalse(store.read("Enabled"))
    lu.assertEquals(store.read("MaxGods"), 4)
    lu.assertErrorMsgContains("store.unknown_alias", function()
        store.read("MaxGodsPerRun")
    end)

    session.write("Enabled", true)
    session.write("MaxGods", 12)
    session._flushToConfig()

    lu.assertTrue(config.Enabled)
    lu.assertEquals(config.MaxGods, 9)
    lu.assertEquals(store.read("MaxGods"), 9)
end

function TestModuleState_Store:testPackedAliasReadWriteUpdatesOwningRoot()
    local config = { Packed = 0 }
    local store, session = createModuleState(self.harness, config, makePackedDefinition(self.harness))

    lu.assertFalse(store.read("EnabledBit"))
    lu.assertEquals(store.read("ModeBits"), 0)
    lu.assertEquals(store.read("Packed"), 0)

    session.write("EnabledBit", true)
    session._flushToConfig()
    lu.assertEquals(config.Packed, 1)
    lu.assertTrue(store.read("EnabledBit"))

    session.write("ModeBits", 3)
    session._flushToConfig()
    lu.assertEquals(config.Packed, 7)
    lu.assertEquals(store.read("ModeBits"), 3)
end

function TestModuleState_Store:testTransientAliasesAreNotReadableThroughStore()
    local config = { Enabled = false }
    local store, session = createModuleState(self.harness, config, makeTransientDefinition(self.harness))

    lu.assertErrorMsgContains("store.invalid_surface", function()
        store.read("FilterText")
    end)
    lu.assertEquals(session.view.FilterText, "")
end

function TestModuleState_Store:testTableReadOnlyHandleClampsRawPersistedRows()
    local config = {
        Tiers = {
            { Limit = 1 },
            { Limit = 2 },
            { Limit = 3 },
            { Limit = 4 },
        },
    }
    local store = createModuleState(self.harness, config, makeTableDefinition(self.harness))
    local tiers = store.table("Tiers")

    lu.assertEquals(#config.Tiers, 3)
    lu.assertNil(config.Tiers[4])
    lu.assertEquals(tiers:count(), 3)
    lu.assertEquals(tiers:rowHandle(3).read("Limit"), 3)
    lu.assertNil(tiers:rowHandle(4).read("Limit"))
end

function TestModuleState_Store.testDowngradedTableErrorsReturnNilSafely()
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
            local store = createModuleState(harness, { Enabled = true, MaxGods = 5 }, makeScalarDefinition(harness))
            local missing = store.table("Missing")
            local wrongType = store.table("MaxGods")

            lu.assertNil(missing)
            lu.assertNil(wrongType)
            lu.assertEquals(#lines, 2)
        end)
    end)
end

