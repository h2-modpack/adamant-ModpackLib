local lu = require('luaunit')

-- =============================================================================
-- isEnabled
-- =============================================================================

TestIsEnabled = {}

local function makeStore(enabled)
    return lib.createStore({ Enabled = enabled }, lib.prepareDefinition({}, { storage = {} }))
end

-- Reset the "test-pack" coordinator slot before each test.
function TestIsEnabled:setUp()
    lib.lifecycle.registerCoordinator("test-pack", nil)
end

-- no coordinator registered
function TestIsEnabled:testEnabledStandalone()
    lu.assertTrue(lib.isModuleEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledStandalone()
    lu.assertFalse(lib.isModuleEnabled(makeStore(false), "test-pack"))
end

function TestIsEnabled:testEnabledNoPackId()
    lu.assertTrue(lib.isModuleEnabled(makeStore(true)))
    lu.assertFalse(lib.isModuleEnabled(makeStore(false)))
end

-- coordinator registered with ModEnabled = true
function TestIsEnabled:testEnabledWithCoordEnabled()
    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })
    lu.assertTrue(lib.isModuleEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledWithCoordEnabled()
    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })
    lu.assertFalse(lib.isModuleEnabled(makeStore(false), "test-pack"))
end

-- coordinator registered with ModEnabled = false (pack-level off overrides module)
function TestIsEnabled:testEnabledWithCoordDisabled()
    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = false })
    lu.assertFalse(lib.isModuleEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledWithCoordDisabled()
    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = false })
    lu.assertFalse(lib.isModuleEnabled(makeStore(false), "test-pack"))
end

-- =============================================================================
-- isCoordinated
-- =============================================================================

TestIsCoordinated = {}

function TestIsCoordinated:setUp()
    lib.lifecycle.registerCoordinator("test-pack", nil)
    lib.lifecycle.registerCoordinator("other-pack", nil)
end

function TestIsCoordinated:testNotCoordinatedByDefault()
    lu.assertFalse(lib.isModuleCoordinated("test-pack"))
end

function TestIsCoordinated:testCoordinatedAfterRegister()
    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })
    lu.assertTrue(lib.isModuleCoordinated("test-pack"))
end

function TestIsCoordinated:testUnrelatedPackNotCoordinated()
    lib.lifecycle.registerCoordinator("other-pack", { ModEnabled = true })
    lu.assertFalse(lib.isModuleCoordinated("test-pack"))
end

function TestIsCoordinated:testClearedByNilRegister()
    lib.lifecycle.registerCoordinator("test-pack", { ModEnabled = true })
    lib.lifecycle.registerCoordinator("test-pack", nil)
    lu.assertFalse(lib.isModuleCoordinated("test-pack"))
end

-- =============================================================================
-- registerCoordinator — multiple packs coexist
-- =============================================================================

TestRegisterCoordinator = {}

function TestRegisterCoordinator:setUp()
    lib.lifecycle.registerCoordinator("pack-a", nil)
    lib.lifecycle.registerCoordinator("pack-b", nil)
end

function TestRegisterCoordinator:testMultiplePacksIndependent()
    lib.lifecycle.registerCoordinator("pack-a", { ModEnabled = true })
    lib.lifecycle.registerCoordinator("pack-b", { ModEnabled = false })
    lu.assertTrue(lib.isModuleCoordinated("pack-a"))
    lu.assertTrue(lib.isModuleCoordinated("pack-b"))
    lu.assertTrue(lib.isModuleEnabled(makeStore(true), "pack-a"))
    lu.assertFalse(lib.isModuleEnabled(makeStore(true), "pack-b"))
end

