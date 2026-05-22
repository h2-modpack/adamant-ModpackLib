local deps = ...

local uiDraw = deps.uiDraw
local moduleState = deps.moduleState
local uiHost = deps.uiHost
local phaseGate = deps.phaseGate

local uiPhase = {}

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
---@field phaseOwner table

---@param opts UiPhaseCreateOpts
---@return UiPhaseObjects
function uiPhase.create(opts)
    local phaseOwner = opts.phaseOwner
    local objects = {
        draw = uiDraw.get(),
        state = moduleState.uiState.create(opts.stagedState, phaseOwner),
        actions = moduleState.uiActions.create(opts.actionBuffer, phaseOwner),
        services = uiHost.create(opts.authorHost, phaseOwner),
    }

    function objects.run(callback)
        return phaseGate.runDraw(phaseOwner, callback, objects.draw, objects.state, objects.actions, objects.services)
    end

    return objects
end

return uiPhase
