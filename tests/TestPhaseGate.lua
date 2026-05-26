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
    self.phase.requireRuntime()

    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        self.phase.requireAnyDraw()
    end)
end

function TestPhaseGate:testDrawPhaseOpensDrawAndClosesRuntime()
    self.phase.enterDraw()
    self.phase.requireAnyDraw()

    lu.assertErrorMsgContains("phase.invalid_runtime_access", function()
        self.phase.requireRuntime()
    end)

    self.phase.leaveDraw()
    self.phase.requireRuntime()
end

function TestPhaseGate:testNestedDrawIsRejected()
    self.phase.enterDraw()
    lu.assertErrorMsgContains("phase.nested_draw", function()
        self.phase.enterDraw()
    end)
    self.phase.leaveDraw()
end

function TestPhaseGate:testLeaveRequiresActiveDraw()
    lu.assertErrorMsgContains("phase.invalid_leave", function()
        self.phase.leaveDraw()
    end)

    self.phase.enterDraw()
    self.phase.leaveDraw()
    lu.assertErrorMsgContains("phase.invalid_leave", function()
        self.phase.leaveDraw()
    end)
end

function TestPhaseGate:testRunDrawClearsPhaseAfterCallbackError()
    lu.assertErrorMsgContains("callback boom", function()
        self.phase.runDraw(function()
            error("callback boom")
        end)
    end)

    self.phase.requireRuntime()
end

function TestPhaseGate:testRunDrawAddsTracebackToCallbackError()
    lu.assertErrorMsgContains("stack traceback", function()
        self.phase.runDraw(function()
            error("traceback boom")
        end)
    end)
end

function TestPhaseGate:testRunDrawPassesArgsAndReturnValues()
    local a, b, c = self.phase.runDraw(function(first, second)
        self.phase.requireAnyDraw()
        return first .. second, nil, 9
    end, "a", "b")

    lu.assertEquals(a, "ab")
    lu.assertNil(b)
    lu.assertEquals(c, 9)
end

function TestPhaseGate:testRunDrawWithContextExposesContextOnlyDuringDraw()
    local observed = nil

    self.phase.runDrawWithContext({ marker = "active" }, function()
        observed = self.phase.getActiveDrawContext().marker
    end)

    lu.assertEquals(observed, "active")
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        self.phase.getActiveDrawContext()
    end)
end
