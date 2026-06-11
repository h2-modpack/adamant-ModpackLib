local lu = require("luaunit")
local createLibHarness = require("tests/harness/create_lib_harness")

TestSystemScope = {}

function TestSystemScope:setUp()
    self.h = createLibHarness()
end

function TestSystemScope:tearDown()
    self.h = nil
end

function TestSystemScope:testInternalSystemScopeReturnsManagedScope()
    local system = self.h.createSystem("framework.fallbackHud")

    lu.assertEquals(type(system), "table")
    lu.assertEquals(system.getOwnerId(), "framework.fallbackHud")
    lu.assertEquals(type(system.hooks.define), "function")
    lu.assertEquals(type(system.overlays.define), "function")
end

function TestSystemScope:testInternalSystemScopeRejectsInvalidOwnerId()
    lu.assertErrorMsgContains("createSystem: ownerId must be a non-empty string", function()
        self.h.createSystem("")
    end)

    lu.assertErrorMsgContains("createSystem: ownerId must be a non-empty string", function()
        self.h.createSystem({})
    end)
end

function TestSystemScope:testSystemScopeIsSeparateFromModuleRegistry()
    local system = self.h.createSystem("framework.scope")

    lu.assertNil(self.h.moduleRegistry.getRecord(system))
    lu.assertEquals(system.getOwnerId(), "framework.scope")
end
