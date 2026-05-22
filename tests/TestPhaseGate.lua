-- luacheck: globals TestPhaseGate

local lu = require("luaunit")
local createLibHarness = require("tests/harness/create_lib_harness")

TestPhaseGate = {}

function TestPhaseGate:setUp()
    self.h = createLibHarness()
    self.phase = self.h.import("core/module_bootstrap/ui/phase_gate.lua", nil, {
        logging = self.h.logging,
    })
end

function TestPhaseGate:tearDown()
    self.phase = nil
    self.h = nil
end

function TestPhaseGate:testRuntimeIsOpenByDefault()
    local owner = {}

    self.phase.requireRuntime(owner)

    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        self.phase.requireAnyDraw()
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        self.phase.requireOwnerDraw(owner)
    end)
end

function TestPhaseGate:testDrawPhaseOpensOwnerAndClosesOwnerRuntime()
    local owner = {}
    local otherOwner = {}

    self.phase.enterDraw(owner)
    self.phase.requireAnyDraw()
    self.phase.requireOwnerDraw(owner)
    self.phase.requireRuntime(otherOwner)

    lu.assertErrorMsgContains("phase.invalid_runtime_access", function()
        self.phase.requireRuntime(owner)
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        self.phase.requireOwnerDraw(otherOwner)
    end)

    self.phase.leaveDraw(owner)
    self.phase.requireRuntime(owner)
end

function TestPhaseGate:testNestedDrawIsRejected()
    local owner = {}
    local otherOwner = {}

    self.phase.enterDraw(owner)
    lu.assertErrorMsgContains("phase.nested_draw", function()
        self.phase.enterDraw(otherOwner)
    end)
    self.phase.leaveDraw(owner)
end

function TestPhaseGate:testLeaveMustMatchActiveOwner()
    local owner = {}
    local otherOwner = {}

    self.phase.enterDraw(owner)
    lu.assertErrorMsgContains("phase.invalid_leave", function()
        self.phase.leaveDraw(otherOwner)
    end)
    self.phase.leaveDraw(owner)
end

function TestPhaseGate:testRunDrawClearsPhaseAfterCallbackError()
    local owner = {}

    lu.assertErrorMsgContains("callback boom", function()
        self.phase.runDraw(owner, function()
            error("callback boom")
        end)
    end)

    self.phase.requireRuntime(owner)
end

function TestPhaseGate:testRunDrawAddsTracebackToCallbackError()
    local owner = {}

    lu.assertErrorMsgContains("stack traceback", function()
        self.phase.runDraw(owner, function()
            error("traceback boom")
        end)
    end)
end

function TestPhaseGate:testRunDrawPassesArgsAndReturnValues()
    local owner = {}

    local a, b, c = self.phase.runDraw(owner, function(first, second)
        self.phase.requireOwnerDraw(owner)
        return first .. second, nil, 9
    end, "a", "b")

    lu.assertEquals(a, "ab")
    lu.assertNil(b)
    lu.assertEquals(c, 9)
end
