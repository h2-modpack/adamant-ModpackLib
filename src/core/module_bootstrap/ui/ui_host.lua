local deps = ...

local phaseGate = deps.phaseGate

local uiHost = {}

---@param authorHost AuthorHost
---@return DrawServices
function uiHost.create(authorHost)
    return {
        log = function(fmt, ...)
            phaseGate.requireAnyDraw()
            return authorHost.log(fmt, ...)
        end,
        logIf = function(fmt, ...)
            phaseGate.requireAnyDraw()
            return authorHost.logIf(fmt, ...)
        end,
        invokeIntegration = function(id, methodName, fallback, ...)
            phaseGate.requireAnyDraw()
            return authorHost.integrations.invoke(id, methodName, fallback, ...)
        end,
    }
end

return uiHost
