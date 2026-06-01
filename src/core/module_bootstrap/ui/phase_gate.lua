local deps = ...

local logging = deps.logging

local phaseGate = {}
local activeDraw = false

local function packResults(...)
    return {
        n = select("#", ...),
        ...,
    }
end

local function withTraceback(err)
    if debug and type(debug.traceback) == "function" then
        return debug.traceback(tostring(err), 2)
    end
    return tostring(err)
end

function phaseGate.enterDraw()
    if activeDraw then
        logging.violate("phase.nested_draw", "cannot enter draw phase while another draw callback is active")
    end

    activeDraw = true
end

function phaseGate.leaveDraw()
    if not activeDraw then
        logging.violate(
            "phase.invalid_leave",
            "cannot leave draw phase because no draw callback is active"
        )
    end

    activeDraw = false
end

function phaseGate.requireAnyDraw()
    if not activeDraw then
        logging.violate("phase.invalid_ui_access", "draw-phase object can only run during a draw callback")
    end
end

function phaseGate.requireRuntime()
    if activeDraw then
        logging.violate("phase.invalid_runtime_access", "runtime object cannot run during a draw callback")
    end
end

local function runDraw(callback, ...)
    phaseGate.enterDraw()
    local args = { ... }
    local results = packResults(xpcall(function()
        return callback(table.unpack(args))
    end, withTraceback))
    local leaveOk, leaveErr = pcall(phaseGate.leaveDraw)
    if not leaveOk then
        error(leaveErr, 0)
    end
    if not results[1] then
        error(results[2], 0)
    end
    return table.unpack(results, 2, results.n)
end

function phaseGate.runDraw(callback, ...)
    return runDraw(callback, ...)
end

return phaseGate
