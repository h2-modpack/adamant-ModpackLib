local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestCoordinator = {}

function TestCoordinator:setUp()
    self.harness = createLibHarness()
    self.coordinator = self.harness.coordinator
end

function TestCoordinator:testInternalSurfaceContainsCoordinatorOperations()
    lu.assertEquals(type(self.coordinator.register), "function")
    lu.assertEquals(type(self.coordinator.registerRebuild), "function")
    lu.assertEquals(type(self.coordinator.isRegistered), "function")
    lu.assertEquals(type(self.coordinator.hasRegistrations), "function")
    lu.assertEquals(type(self.coordinator.getConfig), "function")
    lu.assertEquals(type(self.coordinator.requestRebuild), "function")
end

function TestCoordinator:testNotRegisteredByDefault()
    lu.assertFalse(self.coordinator.isRegistered("test-pack"))
    lu.assertFalse(self.coordinator.hasRegistrations())
    lu.assertNil(self.coordinator.getConfig("test-pack"))
    lu.assertEquals(type(self.harness.registry.coordinators.configs), "table")
    lu.assertEquals(type(self.harness.registry.coordinators.rebuilds), "table")
end

function TestCoordinator:testRegisterAddsPackConfig()
    local config = { ModEnabled = true }

    self.coordinator.register("test-pack", config)

    lu.assertTrue(self.coordinator.isRegistered("test-pack"))
    lu.assertTrue(self.coordinator.hasRegistrations())
    lu.assertIs(self.coordinator.getConfig("test-pack"), config)
end

function TestCoordinator:testUnrelatedPackIsIndependent()
    self.coordinator.register("other-pack", { ModEnabled = true })

    lu.assertTrue(self.coordinator.isRegistered("other-pack"))
    lu.assertFalse(self.coordinator.isRegistered("test-pack"))
    lu.assertNil(self.coordinator.getConfig("test-pack"))
end

function TestCoordinator:testNilRegisterClearsPack()
    self.coordinator.register("test-pack", { ModEnabled = true })
    self.coordinator.register("test-pack", nil)

    lu.assertFalse(self.coordinator.isRegistered("test-pack"))
    lu.assertFalse(self.coordinator.hasRegistrations())
    lu.assertNil(self.coordinator.getConfig("test-pack"))
end

function TestCoordinator:testMultiplePacksCoexist()
    local packA = { ModEnabled = true }
    local packB = { ModEnabled = false }

    self.coordinator.register("pack-a", packA)
    self.coordinator.register("pack-b", packB)

    lu.assertTrue(self.coordinator.isRegistered("pack-a"))
    lu.assertTrue(self.coordinator.isRegistered("pack-b"))
    lu.assertIs(self.coordinator.getConfig("pack-a"), packA)
    lu.assertIs(self.coordinator.getConfig("pack-b"), packB)
end

function TestCoordinator:testRegisterRejectsInvalidConfig()
    lu.assertErrorMsgContains("packId must be a non-empty string", function()
        self.coordinator.register("", { ModEnabled = true })
    end)
    lu.assertErrorMsgContains("config must be a table", function()
        self.coordinator.register("bad-pack", true)
    end)
    lu.assertErrorMsgContains("config.ModEnabled must be a boolean", function()
        self.coordinator.register("bad-pack", {})
    end)
end

function TestCoordinator:testRebuildRequestsUseRegisteredCallback()
    local observedReason = nil
    self.coordinator.registerRebuild("pack-a", function(reason)
        observedReason = reason
        return true
    end)

    local reason = {
        kind = "test",
    }

    lu.assertTrue(self.coordinator.requestRebuild("pack-a", reason))
    lu.assertIs(observedReason, reason)
    lu.assertFalse(self.coordinator.requestRebuild("missing-pack", reason))
end

function TestCoordinator:testRebuildCallbackCanBeCleared()
    self.coordinator.registerRebuild("pack-a", function()
        return true
    end)
    self.coordinator.registerRebuild("pack-a", nil)

    lu.assertFalse(self.coordinator.requestRebuild("pack-a", {
        kind = "test",
    }))
end

function TestCoordinator:testRegisterRebuildRejectsInvalidCallback()
    lu.assertErrorMsgContains("callback must be a function", function()
        self.coordinator.registerRebuild("pack-a", true)
    end)
end

function TestCoordinator.testCoordinatorRegistrySurvivesLibReload()
    local runtimeRoot = {}
    local first = createLibHarness({ runtime = runtimeRoot })
    local rebuildCount = 0

    first.coordinator.register("pack-a", { ModEnabled = false })
    first.coordinator.registerRebuild("pack-a", function(reason)
        rebuildCount = rebuildCount + 1
        return reason.kind == "test"
    end)

    local second = createLibHarness({ runtime = runtimeRoot })

    lu.assertTrue(second.coordinator.isRegistered("pack-a"))
    lu.assertEquals(second.coordinator.getConfig("pack-a"), { ModEnabled = false })
    lu.assertTrue(second.coordinator.requestRebuild("pack-a", {
        kind = "test",
    }))
    lu.assertEquals(rebuildCount, 1)
end
