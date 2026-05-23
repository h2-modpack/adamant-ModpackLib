local deps = ...

local phaseGate = deps.phaseGate

local uiHost = {}

---@param authorHost AuthorHost
---@return DrawServices
function uiHost.create(authorHost)
    return {
        cache = {
            shared = {
                read = function(id, fallback)
                    phaseGate.requireAnyDraw()
                    return authorHost.cache.shared.read(id, fallback)
                end,
                write = function(id, value)
                    phaseGate.requireAnyDraw()
                    return authorHost.cache.shared.write(id, value)
                end,
                clear = function(id)
                    phaseGate.requireAnyDraw()
                    return authorHost.cache.shared.clear(id)
                end,
            },
        },
        log = function(fmt, ...)
            phaseGate.requireAnyDraw()
            return authorHost.log(fmt, ...)
        end,
        logIf = function(fmt, ...)
            phaseGate.requireAnyDraw()
            return authorHost.logIf(fmt, ...)
        end,
        pollIntegration = function(id, methodName, fallback, ...)
            phaseGate.requireAnyDraw()
            return authorHost.integrations.poll(id, methodName, fallback, ...)
        end,
    }
end

return uiHost
