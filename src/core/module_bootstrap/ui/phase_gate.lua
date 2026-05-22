local deps = ...

local logging = deps.logging

local phaseGate = {}
local activeDrawOwner = nil

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

function phaseGate.enterDraw(owner)
    if owner == nil then
        logging.violate("phase.invalid_ui_access", "draw phase requires an owner")
    end
    if activeDrawOwner ~= nil then
        logging.violate("phase.nested_draw", "cannot enter draw phase while another draw callback is active")
    end

    activeDrawOwner = owner
end

function phaseGate.leaveDraw(owner)
    if activeDrawOwner ~= owner then
        logging.violate(
            "phase.invalid_leave",
            "cannot leave draw phase because the owner does not match the active draw callback"
        )
    end

    activeDrawOwner = nil
end

function phaseGate.requireAnyDraw()
    if activeDrawOwner == nil then
        logging.violate("phase.invalid_ui_access", "draw-phase object can only run during a draw callback")
    end
end

function phaseGate.requireOwnerDraw(owner)
    if activeDrawOwner ~= owner then
        logging.violate("phase.invalid_ui_access", "draw-phase object can only run during its owning draw callback")
    end
end

function phaseGate.requireRuntime(owner)
    if activeDrawOwner == owner then
        logging.violate("phase.invalid_runtime_access", "runtime object cannot run during its owning draw callback")
    end
end

function phaseGate.runDraw(owner, callback, ...)
    phaseGate.enterDraw(owner)
    local args = { ... }
    local results = packResults(xpcall(function()
        return callback(table.unpack(args))
    end, withTraceback))
    local leaveOk, leaveErr = pcall(phaseGate.leaveDraw, owner)
    if not leaveOk then
        error(leaveErr, 0)
    end
    if not results[1] then
        error(results[2], 0)
    end
    return table.unpack(results, 2, results.n)
end

return phaseGate
