local deps = ...

local phaseGate = deps.phaseGate

local uiHost = {}

---@param authorHost AuthorHost
---@param phaseOwner table
---@return DrawServices
function uiHost.create(authorHost, phaseOwner)
    return {
        log = function(fmt, ...)
            phaseGate.requireOwnerDraw(phaseOwner)
            return authorHost.log(fmt, ...)
        end,
        logIf = function(fmt, ...)
            phaseGate.requireOwnerDraw(phaseOwner)
            return authorHost.logIf(fmt, ...)
        end,
        isHostEnabled = function()
            phaseGate.requireOwnerDraw(phaseOwner)
            return authorHost.isEnabled()
        end,
        invokeIntegration = function(id, methodName, fallback, ...)
            phaseGate.requireOwnerDraw(phaseOwner)
            return authorHost.integrations.invoke(id, methodName, fallback, ...)
        end,
    }
end

return uiHost
