local uiHost = {}

---@param authorHost AuthorHost
---@return DrawServices
function uiHost.create(authorHost)
    return {
        log = function(fmt, ...)
            return authorHost.log(fmt, ...)
        end,
        logIf = function(fmt, ...)
            return authorHost.logIf(fmt, ...)
        end,
        isHostEnabled = function()
            return authorHost.isEnabled()
        end,
        invokeIntegration = function(id, methodName, fallback, ...)
            return authorHost.integrations.invoke(id, methodName, fallback, ...)
        end,
    }
end

return uiHost
