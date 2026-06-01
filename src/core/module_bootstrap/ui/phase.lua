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
---@field shared table|nil
---@field actionBuffer ActionBuffer
---@field host Host
---@field actionRuntime ActionRuntimeBridge
---@field controls table|nil

---@param opts UiPhaseCreateOpts
---@return UiPhaseObjects
function uiPhase.create(opts)
    local objects = {
        draw = uiDraw.get(),
        state = moduleState.uiState.create(opts.stagedState, opts.shared),
        actions = moduleState.uiActions.create(opts.actionBuffer),
    }
    objects.ui = {
        draw = objects.draw,
        data = objects.state,
        actions = objects.actions,
        shared = opts.shared,
        controls = opts.controls,
    }

    function objects.run(callback)
        local results = packResults(phaseGate.runDraw(function()
            local results = packResults(callback(opts.host, objects.ui))
            opts.actionBuffer.executePendingActions(opts.host, objects.state, opts.actionRuntime, {
                controls = opts.controls,
            })
            return table.unpack(results, 1, results.n)
        end))

        opts.actionBuffer.flushPendingSharedEvents(opts.host)
        return table.unpack(results, 1, results.n)
    end

    return objects
end

return uiPhase
