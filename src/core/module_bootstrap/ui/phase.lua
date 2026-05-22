local deps = ...

local uiDraw = deps.uiDraw
local moduleState = deps.moduleState
local uiHost = deps.uiHost

local uiPhase = {}

---@class UiPhaseObjects
---@field draw DrawContext
---@field state DrawState
---@field actions DrawActions
---@field services DrawServices

---@class UiPhaseCreateOpts
---@field definition ModuleDefinition
---@field stagedState StagedState
---@field actionBuffer ActionBuffer
---@field authorHost AuthorHost

---@param opts UiPhaseCreateOpts
---@return UiPhaseObjects
function uiPhase.create(opts)
    return {
        draw = uiDraw.get(),
        state = moduleState.uiState.create(opts.stagedState),
        actions = moduleState.uiActions.create(opts.actionBuffer),
        services = uiHost.create(opts.authorHost),
    }
end

return uiPhase
