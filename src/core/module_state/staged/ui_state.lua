local deps = ...

local logging = deps.logging
local phaseGate = deps.phaseGate
local storageRefAdapter = deps.storageRefAdapter

local uiState = {}

---@class DrawState
---@field get fun(alias: string): StorageField|StorageTableStagedState|nil
---@field shared table|nil
---@field read fun(alias: string, ...): any
---@field write fun(alias: string, ...): boolean|nil

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

--- Narrows full staged state to the module UI surface.
--- Host internals keep the private commit/reload/snapshot methods.
---@param stagedState StagedState
---@param shared table|nil
---@return DrawState
function uiState.create(stagedState, shared)
    local refs = storageRefAdapter.create({
        root = createDataRoot(stagedState),
        phase = "draw",
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
            phaseGate.requireAnyDraw()
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
