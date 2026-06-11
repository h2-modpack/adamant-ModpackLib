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
    local store = self.h:createModuleState({ Enabled = enabled }, definition)
    return store
end

function TestManagedModule_IsEnabled:testEnabledUncoordinated()
    lu.assertTrue(self.h.managedModuleLifecycle.isEnabled(self:makeStore(true)))
end

function TestManagedModule_IsEnabled:testDisabledUncoordinated()
    lu.assertFalse(self.h.managedModuleLifecycle.isEnabled(self:makeStore(false)))
end

function TestManagedModule_IsEnabled:testEnabledNoPackId()
    lu.assertTrue(self.h.managedModuleLifecycle.isEnabled(self:makeStore(true)))
    lu.assertFalse(self.h.managedModuleLifecycle.isEnabled(self:makeStore(false)))
end

function TestManagedModule_IsEnabled:testEnabledWithCoordinatorEnabled()
    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = true })
    lu.assertTrue(self.h.managedModuleLifecycle.isEnabled(self:makeStore(true)))
end

function TestManagedModule_IsEnabled:testDisabledWithCoordinatorEnabled()
    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = true })
    lu.assertFalse(self.h.managedModuleLifecycle.isEnabled(self:makeStore(false)))
end

function TestManagedModule_IsEnabled:testEnabledWithCoordinatorDisabled()
    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = false })
    lu.assertTrue(self.h.managedModuleLifecycle.isEnabled(self:makeStore(true)))
end

function TestManagedModule_IsEnabled:testDisabledWithCoordinatorDisabled()
    self.h.coordinator.register("test-pack", "Test Pack", { ModEnabled = false })
    lu.assertFalse(self.h.managedModuleLifecycle.isEnabled(self:makeStore(false)))
end
