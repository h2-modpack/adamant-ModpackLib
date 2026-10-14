local deps = ...

-- Global overlay visibility gate. UI suppression is global because foreground configuration
-- UI and gameplay overlays should not compete for screen space.
local overlayRegistry = deps.state
local suppression = {}

function suppression.isUiSuppressed()
    return next(overlayRegistry.uiSuppressors) ~= nil
end

--- Binds token-based suppression to the renderer refresh that applies a gate change.
---@param refreshAll fun()
---@return fun(): { release: fun() } suppressForUi
function suppression.bindSuppressForUi(refreshAll)
    return function()
        overlayRegistry.nextUiSuppressorId = overlayRegistry.nextUiSuppressorId + 1
        local id = overlayRegistry.nextUiSuppressorId
        local wasSuppressed = suppression.isUiSuppressed()
        overlayRegistry.uiSuppressors[id] = true
        if not wasSuppressed then
            refreshAll()
        end

        local released = false
        return {
            release = function()
                if released then
                    return
                end
                released = true
                overlayRegistry.uiSuppressors[id] = nil
                if not suppression.isUiSuppressed() then
                    refreshAll()
                end
            end,
        }
    end
end

return suppression
