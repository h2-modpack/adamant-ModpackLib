local deps = ...

local overlayRegistry = deps.state
local renderer = deps.renderer
local isUiSuppressed = deps.isUiSuppressed
local suppression = {}

function suppression.suppressForUi()
    overlayRegistry.nextUiSuppressorId = overlayRegistry.nextUiSuppressorId + 1
    local id = overlayRegistry.nextUiSuppressorId
    local wasSuppressed = isUiSuppressed()
    overlayRegistry.uiSuppressors[id] = true
    if not wasSuppressed then
        renderer.refreshAll()
    end

    local released = false
    return {
        release = function()
            if released then
                return
            end
            released = true
            overlayRegistry.uiSuppressors[id] = nil
            if not isUiSuppressed() then
                renderer.refreshAll()
            end
        end,
    }
end

function suppression.isUiSuppressed()
    return isUiSuppressed()
end

return suppression
