local deps = ...

local logging = deps.logging
local storageRefAdapter = deps.storageRefAdapter

local runtimeStatus = {}

local function createStatusRoot(persistentState, status)
    return {
        get = function(alias)
            local node = persistentState.getAliasSchema(alias)
            if not node then
                logging.violate("status.unknown_alias", "runtime.status.get: unknown status alias '%s'",
                    tostring(alias))
                return nil
            end
            if node._mode ~= "runtime" then
                logging.violate("status.invalid_surface",
                    "runtime.status.get: alias '%s' is data storage, not status",
                    tostring(alias))
                return nil
            end
            return status.get(alias)
        end,
    }
end

function runtimeStatus.create(persistentState)
    local status = persistentState.status
    if not status then
        return nil
    end

    local statusRefs = storageRefAdapter.create({
        root = createStatusRoot(persistentState, status),
        source = "runtime.status.get",
        writable = true,
    })

    return {
        get = statusRefs.get,
        read = function(alias, ...)
            storageRefAdapter.rejectPrivateAlias("runtime.status.read", alias)
            local ref = statusRefs.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
        write = function(alias, ...)
            storageRefAdapter.rejectPrivateAlias("runtime.status.write", alias)
            local ref = statusRefs.get(alias)
            if ref == nil then
                return nil
            end
            if type(ref.write) ~= "function" then
                logging.violate(
                    "status.invalid_surface",
                    "runtime.status.write: alias '%s' is not writable",
                    tostring(alias))
                return nil
            end
            return ref:write(...)
        end,
        reset = function(alias, ...)
            storageRefAdapter.rejectPrivateAlias("runtime.status.reset", alias)
            local ref = statusRefs.get(alias)
            if ref == nil then
                return nil
            end
            if select("#", ...) == 0 then
                return status.reset(alias)
            end
            if type(ref.reset) ~= "function" then
                logging.violate(
                    "status.invalid_surface",
                    "runtime.status.reset: alias '%s' is not resettable",
                    tostring(alias))
                return nil
            end
            return ref:reset(...)
        end,
    }
end

return runtimeStatus
