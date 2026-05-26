local deps = ...

local phaseGate = deps.phaseGate
local actionRefs = deps.actionRefs

local uiActions = {}

---@param actionBuffer ActionBuffer
---@return DrawActions
function uiActions.create(actionBuffer)
    local refs = {}

    local actions = {}

    function actions.get(actionKey)
        phaseGate.requireAnyDraw()
        local ref = refs[actionKey]
        if ref ~= nil then
            return ref
        end
        ref = actionRefs.createGatedDrawActionRef(actionBuffer, actionKey, phaseGate)
        refs[actionKey] = ref
        return ref
    end

    function actions.trigger(actionKey, value)
        actions.get(actionKey):stage(value == nil and true or value)
    end

    function actions.emit(id, eventName, payload)
        phaseGate.requireAnyDraw()
        actionBuffer.emitShared(id, eventName, payload)
    end

    return actions
end

return uiActions
