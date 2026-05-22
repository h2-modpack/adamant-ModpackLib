local deps = ...

local phaseGate = deps.phaseGate
local storageRefAdapter = deps.storageRefAdapter

local uiState = {}

---@class DrawState
---@field get fun(alias: string): StorageField|StorageTableStagedState|nil
---@field read fun(alias: string, ...): any
---@field write fun(alias: string, ...): boolean|nil
---@field resetAll fun(opts: table|nil): boolean, number

--- Narrows full staged state to the module author UI surface.
--- Host internals keep the private commit/reload/snapshot methods.
---@param stagedState StagedState
---@param phaseOwner table
---@return DrawState
function uiState.create(stagedState, phaseOwner)
    local refs = storageRefAdapter.create({
        root = stagedState,
        phaseOwner = phaseOwner,
        phase = "draw",
        source = "state.get",
        writable = true,
    })

    return {
        get = refs.get,
        read = function(alias, ...)
            phaseGate.requireOwnerDraw(phaseOwner)
            local ref = stagedState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
        write = function(alias, ...)
            phaseGate.requireOwnerDraw(phaseOwner)
            local ref = stagedState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:write(...)
        end,
        resetAll = function(opts)
            phaseGate.requireOwnerDraw(phaseOwner)
            return stagedState.resetAll(opts)
        end,
    }
end

return uiState
