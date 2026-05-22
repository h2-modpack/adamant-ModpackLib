local deps = ...

local phaseGate = deps.phaseGate
local actionRefs = deps.actionRefs

local uiActions = {}

---@param actionBuffer ActionBuffer
---@return DrawActions
function uiActions.create(actionBuffer)
    local refs = {}

    return {
        get = function(actionKey)
            phaseGate.requireAnyDraw()
            local ref = refs[actionKey]
            if ref ~= nil then
                return ref
            end
            ref = actionRefs.createGatedDrawActionRef(actionBuffer, actionKey, phaseGate)
            refs[actionKey] = ref
            return ref
        end,
        hasAny = function()
            phaseGate.requireAnyDraw()
            return actionBuffer.hasAny()
        end,
    }
end

return uiActions
