local deps = ...

local coordination = deps.coordination
local overlays = deps.overlays
local createSystem = deps.createSystem
local runtimes = deps.runtimes

local FALLBACK_OWNER = "adamant-lib.fallback-hud"
local MARKER_TEXT = "Modded"

local fallbackHud = {}
-- Import-local on purpose: a Lib re-import redefines the marker once, and the system
-- overlay define replaces the previous import's marker for the fallback owner.
local markerDefined = false

local function isRuntimeUncoordinated(activeRuntime)
    local packId = activeRuntime.module.getPackId()
    return not (packId and coordination.isRegistered(packId))
end

local function shouldShowFallbackMarker()
    for _, activeRuntime in pairs(runtimes) do
        if isRuntimeUncoordinated(activeRuntime) then
            return true
        end
    end
    return false
end

function fallbackHud.refreshMarker()
    overlays.dispatchCommit(FALLBACK_OWNER, {})
end

function fallbackHud.createMarker()
    if markerDefined then
        return
    end
    markerDefined = true
    local system = createSystem(FALLBACK_OWNER)
    system.overlays.define(function(overlay)
        overlay.createStamp("marker", {
            hudVisibility = "independent",
            componentName = "ModpackMark_FallbackUi",
            region = "middleRightStack",
            order = system.overlays.order.system,
            visible = shouldShowFallbackMarker,
            minWidth = 80,
        })
        overlay.onCommit(function(retained)
            retained.setLine("marker", MARKER_TEXT)
            retained.refresh("marker")
        end)
    end)
end

return fallbackHud
