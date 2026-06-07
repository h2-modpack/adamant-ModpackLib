local deps = ...

local actionRefs = deps.actionRefs

local uiActions = {}

---@param actionBuffer ActionBuffer
---@return DrawActions
function uiActions.create(actionBuffer)
    local refs = {}

    local actions = {}

    function actions.get(actionKey)
        local ref = refs[actionKey]
        if ref ~= nil then
            return ref
        end
        ref = actionRefs.createDrawActionRef(actionBuffer, actionKey)
        refs[actionKey] = ref
        return ref
    end

    function actions.trigger(actionKey, value)
        actions.get(actionKey):stage(value == nil and true or value)
    end

    return actions
end

return uiActions
