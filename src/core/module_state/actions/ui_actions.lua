local uiActions = {}

---@param actionBuffer ActionBuffer
---@return DrawActions
function uiActions.create(actionBuffer)
    return {
        get = function(actionKey)
            return actionBuffer.getRef(actionKey)
        end,
        hasAny = function()
            return actionBuffer.hasAny()
        end,
    }
end

return uiActions
