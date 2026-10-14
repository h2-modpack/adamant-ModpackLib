-- Window-session bookkeeping shared by the fallback module window and the modpack window:
-- deferred run-data rebuild, overlay suppression while a window is open, and GUI-close edges.
local uiSession = {}

---@class AdamantModpackLib.UiSession
---@field markRunDataDirty fun()
---@field flushRunData fun()
---@field suppressOverlays fun()
---@field releaseOverlays fun()

--- Creates one window's session state.
---@param setupRunData fun() Run-data rebuild (`gameDeps.runData.SetupRunData`).
---@param overlaySurface { suppressForUi: fun(): AdamantModpackLib.UiSuppressionToken } Late-read per suppress.
---@return AdamantModpackLib.UiSession
function uiSession.create(setupRunData, overlaySurface)
    local runDataDirty = false
    local suppressionToken = nil
    local session = {}

    function session.markRunDataDirty()
        runDataDirty = true
    end

    --- Runs the deferred run-data rebuild once if anything marked it dirty.
    function session.flushRunData()
        if not runDataDirty then
            return
        end
        setupRunData()
        runDataDirty = false
    end

    --- Suppresses overlays while the window is open; idempotent per frame.
    function session.suppressOverlays()
        if not suppressionToken then
            suppressionToken = overlaySurface.suppressForUi()
        end
    end

    function session.releaseOverlays()
        if suppressionToken then
            suppressionToken.release()
            suppressionToken = nil
        end
    end

    return session
end

--- Per-frame GUI open->closed edge detector. `state.wasGuiOpen` holds the previous frame's
--- open state; `onClosed` runs on the frame the GUI closes, before the state advances.
---@param state { wasGuiOpen: boolean? }
---@param isGuiOpen boolean
---@param onClosed fun()
function uiSession.trackGuiClose(state, isGuiOpen, onClosed)
    if state.wasGuiOpen and not isGuiOpen then
        onClosed()
    end
    state.wasGuiOpen = isGuiOpen
end

return uiSession
