local deps = ...

local phaseGate = deps.phaseGate
local actionRefs = deps.actionRefs

local uiActions = {}

---@param actionBuffer ActionBuffer
---@param phaseOwner table
---@return DrawActions
function uiActions.create(actionBuffer, phaseOwner)
    local refs = {}

    return {
        get = function(actionKey)
            phaseGate.requireOwnerDraw(phaseOwner)
            local ref = refs[actionKey]
            if ref ~= nil then
                return ref
            end
            ref = actionRefs.createGatedDrawActionRef(actionBuffer, actionKey, phaseGate, phaseOwner)
            refs[actionKey] = ref
            return ref
        end,
        hasAny = function()
            phaseGate.requireOwnerDraw(phaseOwner)
            return actionBuffer.hasAny()
        end,
    }
end

return uiActions
