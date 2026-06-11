local deps = ...

local logging = deps.logging
local libConfig = deps.config
local services = {}

function services.create()
    local overlayUi = deps.overlays.ui
    local runtime = {
        diagnostics = {
            isLibDebugEnabled = function()
                return libConfig.DebugMode == true
            end,
            setLibDebugEnabled = function(enabled)
                if type(enabled) ~= "boolean" then
                    logging.violate(
                        "framework_runtime.invalid_debug_mode",
                        "modpack.services.diagnostics.setLibDebugEnabled: enabled must be a boolean"
                    )
                end
                libConfig.DebugMode = enabled
            end,
        },
        hashing = deps.hashing,
        coordinator = {
            register = function(packId, displayName, config)
                return deps.coordinator.register(packId, displayName, config)
            end,
            registerRebuild = function(packId, callback)
                return deps.coordinator.registerRebuild(packId, callback)
            end,
            isRegistered = function(packId)
                return deps.coordinator.isRegistered(packId)
            end,
            getDisplayName = function(packId)
                return deps.coordinator.getDisplayName(packId)
            end,
        },
        modules = {
            getLiveModule = function(pluginGuid)
                if type(pluginGuid) ~= "string" or pluginGuid == "" then
                    return nil
                end
                return deps.managedModule.getLiveModule(pluginGuid)
            end,
        },
        overlays = deps.overlays.create(),
        ui = {
            suppressOverlays = overlayUi.suppressOverlays,
            areOverlaysSuppressed = overlayUi.areOverlaysSuppressed,
        },
    }

    return runtime
end

return services
