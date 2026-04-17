local lu = require('luaunit')

-- =============================================================================
-- isEnabled
-- =============================================================================

TestIsEnabled = {}

local function makeStore(enabled)
    return lib.store.create({ Enabled = enabled }, { storage = {} })
end

-- Reset the "test-pack" coordinator slot before each test.
function TestIsEnabled:setUp()
    lib.coordinator.register("test-pack", nil)
end

-- no coordinator registered
function TestIsEnabled:testEnabledStandalone()
    lu.assertTrue(lib.coordinator.isEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledStandalone()
    lu.assertFalse(lib.coordinator.isEnabled(makeStore(false), "test-pack"))
end

function TestIsEnabled:testEnabledNoPackId()
    lu.assertTrue(lib.coordinator.isEnabled(makeStore(true)))
    lu.assertFalse(lib.coordinator.isEnabled(makeStore(false)))
end

-- coordinator registered with ModEnabled = true
function TestIsEnabled:testEnabledWithCoordEnabled()
    lib.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertTrue(lib.coordinator.isEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledWithCoordEnabled()
    lib.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertFalse(lib.coordinator.isEnabled(makeStore(false), "test-pack"))
end

-- coordinator registered with ModEnabled = false (pack-level off overrides module)
function TestIsEnabled:testEnabledWithCoordDisabled()
    lib.coordinator.register("test-pack", { ModEnabled = false })
    lu.assertFalse(lib.coordinator.isEnabled(makeStore(true), "test-pack"))
end

function TestIsEnabled:testDisabledWithCoordDisabled()
    lib.coordinator.register("test-pack", { ModEnabled = false })
    lu.assertFalse(lib.coordinator.isEnabled(makeStore(false), "test-pack"))
end

-- =============================================================================
-- isCoordinated
-- =============================================================================

TestIsCoordinated = {}

function TestIsCoordinated:setUp()
    lib.coordinator.register("test-pack", nil)
    lib.coordinator.register("other-pack", nil)
end

function TestIsCoordinated:testNotCoordinatedByDefault()
    lu.assertFalse(lib.coordinator.isCoordinated("test-pack"))
end

function TestIsCoordinated:testCoordinatedAfterRegister()
    lib.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertTrue(lib.coordinator.isCoordinated("test-pack"))
end

function TestIsCoordinated:testUnrelatedPackNotCoordinated()
    lib.coordinator.register("other-pack", { ModEnabled = true })
    lu.assertFalse(lib.coordinator.isCoordinated("test-pack"))
end

function TestIsCoordinated:testClearedByNilRegister()
    lib.coordinator.register("test-pack", { ModEnabled = true })
    lib.coordinator.register("test-pack", nil)
    lu.assertFalse(lib.coordinator.isCoordinated("test-pack"))
end

-- =============================================================================
-- registerCoordinator — multiple packs coexist
-- =============================================================================

TestRegisterCoordinator = {}

function TestRegisterCoordinator:setUp()
    lib.coordinator.register("pack-a", nil)
    lib.coordinator.register("pack-b", nil)
end

function TestRegisterCoordinator:testMultiplePacksIndependent()
    lib.coordinator.register("pack-a", { ModEnabled = true })
    lib.coordinator.register("pack-b", { ModEnabled = false })
    lu.assertTrue(lib.coordinator.isCoordinated("pack-a"))
    lu.assertTrue(lib.coordinator.isCoordinated("pack-b"))
    lu.assertTrue(lib.coordinator.isEnabled(makeStore(true), "pack-a"))
    lu.assertFalse(lib.coordinator.isEnabled(makeStore(true), "pack-b"))
end
