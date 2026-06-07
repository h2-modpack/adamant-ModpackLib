local deps = ...

local uiDraw = deps.uiDraw
local moduleState = deps.moduleState

local uiContext = {}

local function packResults(...)
    return {
        n = select("#", ...),
        ...
    }
end

local function withTraceback(err)
    if debug and type(debug.traceback) == "function" then
        return debug.traceback(tostring(err), 2)
    end
    return tostring(err)
end

local function runCallback(callback, ...)
    local args = { ... }
    local results = packResults(xpcall(function()
        return callback(table.unpack(args))
    end, withTraceback))
    if not results[1] then
        error(results[2], 0)
    end
    return table.unpack(results, 2, results.n)
end

---@class UiCallbackObjects
---@field draw DrawContext
---@field state DrawState
---@field actions DrawActions
---@field run fun(callback: fun(
---    draw: DrawContext,
---    state: DrawState,
---    actions: DrawActions
---): any): any

---@class UiCallbackCreateOpts
---@field definition ModuleDefinition
---@field stagedState StagedState
---@field shared table|nil
---@field actionBuffer ActionBuffer
---@field host Host
---@field controls table|nil
---@field status table|nil
---@field resetAll fun(opts: table|nil)|nil

---@param opts UiCallbackCreateOpts
---@return UiCallbackObjects
function uiContext.create(opts)
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
        status = opts.status,
        resetAll = function(resetOpts)
            return opts.resetAll(resetOpts)
        end,
    }

    function objects.run(callback)
        local results = packResults(runCallback(function()
            return callback(opts.host, objects.ui)
        end))

        return table.unpack(results, 1, results.n)
    end

    return objects
end

return uiContext
