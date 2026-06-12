--- Create the HUD subsystem for one coordinator pack.
--- @param packId string Pack identifier used for component naming.
--- @param packIndex number Stable vertical stacking index for this pack.
--- @param configHash table Config-hash subsystem returned by `createConfigHash(...)`.
--- @param theme table Theme object returned by `core/modpack/ui/theme.lua`.
--- @param config table Coordinator config table containing `ModEnabled`.
--- @param hideHashMarker boolean|nil Optional pack-level flag to suppress the HUD fingerprint marker.
--- @param overlaySurface table Modpack overlay surface returned by Lib.
--- @return table hud HUD object exposing marker/hash update helpers.
local function createHud(packId, packIndex, configHash, theme, config, hideHashMarker, overlaySurface)
    assert(type(overlaySurface) == "table"
        and type(overlaySurface.define) == "function",
        "modpack.createPack: adamant-ModpackLib modpack overlays are not available")

    local componentName = "ModpackMark_" .. packId

    local _, initFingerprint = configHash.GetConfigHash()
    local currentHash = config.ModEnabled and initFingerprint or ""
    local hashDirty = false
    local markerHidden = hideHashMarker == true
    local markerContext = nil

    local function defineOverlay()
        overlaySurface.define(packId, "hud", function(overlays)
            if markerHidden then
                return
            end

            overlays.createLine("hash", {
                componentName = componentName,
                region = "middleRightStack",
                order = overlaySurface.order.framework + packIndex,
                visible = function()
                    return config.ModEnabled == true and currentHash ~= ""
                end,
                minWidth = 120,
                textArgs = {
                    Color = theme.colors.text,
                },
            })
            overlays.onCommit(function(ctx)
                markerContext = ctx
                ctx.setLine("hash", currentHash)
                ctx.refresh("hash")
            end)
        end)
    end

    local function UpdateModMark()
        if markerContext then
            markerContext.setLine("hash", currentHash)
            markerContext.refresh("hash")
        end
    end

    local function updateHash()
        local _, fingerprint = configHash.GetConfigHash()
        currentHash = fingerprint
        hashDirty = false
        UpdateModMark()
    end

    local function markHashDirty()
        hashDirty = true
    end

    local function flushPendingHash()
        if hashDirty and config.ModEnabled then
            updateHash()
        end
    end

    local function setModMarker(enabled)
        if enabled then
            local _, fingerprint = configHash.GetConfigHash()
            currentHash = fingerprint
            hashDirty = false
        else
            currentHash = ""
            hashDirty = false
        end
        UpdateModMark()
    end

    return {
        install         = defineOverlay,
        setModMarker    = setModMarker,
        markHashDirty   = markHashDirty,
        flushPendingHash = flushPendingHash,
        updateHash      = updateHash,
        getConfigHash   = configHash.GetConfigHash,
        applyConfigHash = configHash.ApplyConfigHash,
    }
end

return createHud
