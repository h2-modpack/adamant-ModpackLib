local lu = require("luaunit")
local createManagedModuleHarness = require("tests/harness/create_managed_module_harness")

TestManagedModule_IsEnabled = {}

function TestManagedModule_IsEnabled:setUp()
    self.h = createManagedModuleHarness()
end

function TestManagedModule_IsEnabled:makeStore(enabled)
    local definition = self.h:prepareDefinition({}, {
        id = "IsEnabledStore",
        name = "Is Enabled Store",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({ Enabled = enabled }, definition)
    local module = self.h:createManagedModule("test-is-enabled-store", {
        definition = definition,
        state = moduleState,
        drawTab = function() end,
    })
    return module
end

function TestManagedModule_IsEnabled:testEnabledUncoordinated()
    lu.assertTrue(self:makeStore(true).isEnabled())
end

function TestManagedModule_IsEnabled:testDisabledUncoordinated()
    lu.assertFalse(self:makeStore(false).isEnabled())
end

function TestManagedModule_IsEnabled:testEnabledNoPackId()
    lu.assertTrue(self:makeStore(true).isEnabled())
    lu.assertFalse(self:makeStore(false).isEnabled())
end

function TestManagedModule_IsEnabled:testEnabledWithCoordinatorEnabled()
    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = true })
    lu.assertTrue(self:makeStore(true).isEnabled())
end

function TestManagedModule_IsEnabled:testDisabledWithCoordinatorEnabled()
    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = true })
    lu.assertFalse(self:makeStore(false).isEnabled())
end

function TestManagedModule_IsEnabled:testEnabledWithCoordinatorDisabled()
    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = false })
    lu.assertTrue(self:makeStore(true).isEnabled())
end

function TestManagedModule_IsEnabled:testDisabledWithCoordinatorDisabled()
    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = false })
    lu.assertFalse(self:makeStore(false).isEnabled())
end
