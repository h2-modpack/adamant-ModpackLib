local deps = ...

local coordinator = deps.coordinator
local overlays = deps.overlays
local createSystem = deps.createSystem
local runtimes = deps.runtimes
local state = deps.state

local FALLBACK_OWNER = "adamant-lib.fallback-hud"
local MARKER_TEXT = "Modded"

local fallbackHud = {}

local function isRuntimeUncoordinated(activeRuntime)
    local host = activeRuntime and activeRuntime.host
    if type(host) ~= "table" or type(host.getPackId) ~= "function" then
        return false
    end

    local packId = host.getPackId()
    return not (packId and coordinator.isRegistered(packId))
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
    if state.initialized then
        return
    end
    state.initialized = true
    local system = createSystem(FALLBACK_OWNER)
    system.overlays.define(function(overlay)
        overlay.createLine("marker", {
            componentName = "ModpackMark_FallbackUi",
            region = "middleRightStack",
            order = 0,
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
