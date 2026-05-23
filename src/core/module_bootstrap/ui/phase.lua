local deps = ...

local uiDraw = deps.uiDraw
local moduleState = deps.moduleState
local uiHost = deps.uiHost
local phaseGate = deps.phaseGate

local uiPhase = {}

local function packResults(...)
    return {
        n = select("#", ...),
        ...
    }
end

---@class UiPhaseObjects
---@field draw DrawContext
---@field state DrawState
---@field actions DrawActions
---@field services DrawServices
---@field run fun(callback: fun(
---    draw: DrawContext,
---    state: DrawState,
---    actions: DrawActions,
---    services: DrawServices
---): any): any

---@class UiPhaseCreateOpts
---@field definition ModuleDefinition
---@field stagedState StagedState
---@field actionBuffer ActionBuffer
---@field authorHost AuthorHost

---@param opts UiPhaseCreateOpts
---@return UiPhaseObjects
function uiPhase.create(opts)
    local objects = {
        draw = uiDraw.get(),
        state = moduleState.uiState.create(opts.stagedState),
        actions = moduleState.uiActions.create(opts.actionBuffer),
        services = uiHost.create(opts.authorHost),
    }

    function objects.run(callback)
        return phaseGate.runDraw(function(draw, state, actions, services)
            local results = packResults(callback(draw, state, actions, services))
            opts.actionBuffer.executePending(state, services)
            return table.unpack(results, 1, results.n)
        end, objects.draw, objects.state, objects.actions, objects.services)
    end

    return objects
end

return uiPhase
