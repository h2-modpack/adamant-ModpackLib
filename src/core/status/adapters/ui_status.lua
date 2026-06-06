local deps = ...

local logging = deps.logging
local storageRefAdapter = deps.storageRefAdapter

local uiStatus = {}

local function createStatusRoot(stagedState)
    return {
        get = function(alias)
            local node = stagedState.getAliasSchema(alias)
            if not node then
                logging.violate("status.unknown_alias", "ui.status.get: unknown status alias '%s'",
                    tostring(alias))
                return nil
            end
            if node._mode ~= "runtime" then
                logging.violate("status.invalid_surface",
                    "ui.status.get: alias '%s' is data storage, not status",
                    tostring(alias))
                return nil
            end
            return stagedState.status.get(alias)
        end,
    }
end

function uiStatus.create(stagedState)
    local statusRefs = storageRefAdapter.create({
        root = createStatusRoot(stagedState),
        phase = "draw",
        source = "ui.status.get",
        writable = false,
    })

    return {
        get = statusRefs.get,
        read = function(alias, ...)
            storageRefAdapter.rejectPrivateAlias("ui.status.read", alias)
            local ref = statusRefs.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
    }
end

return uiStatus
