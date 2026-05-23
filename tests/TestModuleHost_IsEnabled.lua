local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestModuleHost_IsEnabled = {}

function TestModuleHost_IsEnabled:setUp()
    self.h = createModuleHostHarness()
end

function TestModuleHost_IsEnabled:makeStore(enabled)
    local definition = self.h:prepareDefinition({}, {
        id = "IsEnabledStore",
        name = "Is Enabled Store",
        storage = {},
    })
    local store = self.h:createModuleState({ Enabled = enabled }, definition)
    return store
end

function TestModuleHost_IsEnabled:testEnabledUncoordinated()
    lu.assertTrue(self.h.hostLifecycle.isEnabled(self:makeStore(true)))
end

function TestModuleHost_IsEnabled:testDisabledUncoordinated()
    lu.assertFalse(self.h.hostLifecycle.isEnabled(self:makeStore(false)))
end

function TestModuleHost_IsEnabled:testEnabledNoPackId()
    lu.assertTrue(self.h.hostLifecycle.isEnabled(self:makeStore(true)))
    lu.assertFalse(self.h.hostLifecycle.isEnabled(self:makeStore(false)))
end

function TestModuleHost_IsEnabled:testEnabledWithCoordinatorEnabled()
    self.h.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertTrue(self.h.hostLifecycle.isEnabled(self:makeStore(true)))
end

function TestModuleHost_IsEnabled:testDisabledWithCoordinatorEnabled()
    self.h.coordinator.register("test-pack", { ModEnabled = true })
    lu.assertFalse(self.h.hostLifecycle.isEnabled(self:makeStore(false)))
end

function TestModuleHost_IsEnabled:testEnabledWithCoordinatorDisabled()
    self.h.coordinator.register("test-pack", { ModEnabled = false })
    lu.assertTrue(self.h.hostLifecycle.isEnabled(self:makeStore(true)))
end

function TestModuleHost_IsEnabled:testDisabledWithCoordinatorDisabled()
    self.h.coordinator.register("test-pack", { ModEnabled = false })
    lu.assertFalse(self.h.hostLifecycle.isEnabled(self:makeStore(false)))
end
