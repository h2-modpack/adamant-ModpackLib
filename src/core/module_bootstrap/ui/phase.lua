local deps = ...

local uiDraw = deps.uiDraw
local moduleState = deps.moduleState
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
---@field run fun(callback: fun(
---    draw: DrawContext,
---    state: DrawState,
---    actions: DrawActions
---): any): any

---@class UiPhaseCreateOpts
---@field definition ModuleDefinition
---@field stagedState StagedState
---@field cache table|nil
---@field shared table|nil
---@field actionBuffer ActionBuffer
---@field authorHost AuthorHost
---@field logPrefix string
---@field isDebugEnabled fun(): boolean

---@param opts UiPhaseCreateOpts
---@return UiPhaseObjects
function uiPhase.create(opts)
    local objects = {
        draw = uiDraw.get(),
        state = moduleState.uiState.create(opts.stagedState, opts.cache, opts.shared),
        actions = moduleState.uiActions.create(opts.actionBuffer),
    }

    function objects.run(callback)
        return phaseGate.runDrawWithContext({
            logPrefix = opts.logPrefix,
            debugEnabled = opts.isDebugEnabled() == true,
        }, function(draw, state, actions)
            local results = packResults(callback(draw, state, actions))
            opts.actionBuffer.executePending(opts.authorHost, state)
            return table.unpack(results, 1, results.n)
        end, objects.draw, objects.state, objects.actions)
    end

    return objects
end

return uiPhase
