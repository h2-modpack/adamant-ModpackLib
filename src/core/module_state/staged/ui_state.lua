local deps = ...

local logging = deps.logging
local storageRefAdapter = deps.storageRefAdapter

local uiState = {}

local function createDataRoot(stagedState)
    return {
        get = function(alias)
            local node = stagedState.getAliasSchema(alias)
            if node and node._mode == "runtime" then
                logging.violate(
                    "staged_state.invalid_surface",
                    "ui.data.get: alias '%s' is status, not data storage",
                    tostring(alias))
                return nil
            end
            return stagedState.get(alias)
        end,
    }
end

function uiState.create(stagedState, shared)
    local refs = storageRefAdapter.create({
        root = createDataRoot(stagedState),
        source = "ui.data.get",
        writable = true,
    })

    return {
        get = refs.get,
        shared = shared,
        read = function(alias, ...)
            storageRefAdapter.rejectPrivateAlias("ui.data.read", alias)
            local ref = refs.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
        write = function(alias, ...)
            storageRefAdapter.rejectPrivateAlias("ui.data.write", alias)
            local ref = refs.get(alias)
            if ref == nil then
                return nil
            end
            if type(ref.write) ~= "function" then
                logging.violate(
                    "staged_state.invalid_surface",
                    "ui.data.write: alias '%s' is not writable from draw state",
                    tostring(alias))
                return nil
            end
            return ref:write(...)
        end,
    }
end

return uiState
