local deps = ...

local logging = deps.logging
local libConfig = deps.config
local frameworkRuntime = {}

local FRAMEWORK_PLUGIN_GUID = "adamant-ModpackFramework"

local function validateArgs(frameworkPluginGuid, unexpectedPackId)
    if frameworkPluginGuid ~= FRAMEWORK_PLUGIN_GUID then
        logging.violate(
            "framework_runtime.invalid_framework_plugin",
            "createFrameworkRuntime: frameworkPluginGuid must be adamant-ModpackFramework"
        )
    end
    if unexpectedPackId ~= nil then
        logging.violate(
            "framework_runtime.unexpected_pack",
            "createFrameworkRuntime: packId is not accepted; pass packId to frameworkRuntime.overlays.define"
        )
    end
end

function frameworkRuntime.create(frameworkPluginGuid, unexpectedPackId)
    validateArgs(frameworkPluginGuid, unexpectedPackId)

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
                        "frameworkRuntime.diagnostics.setLibDebugEnabled: enabled must be a boolean"
                    )
                end
                libConfig.DebugMode = enabled
            end,
        },
        hashing = deps.hashing,
        coordinator = {
            register = function(packId, config)
                return deps.coordinator.register(packId, config)
            end,
            registerRebuild = function(packId, callback)
                return deps.coordinator.registerRebuild(packId, callback)
            end,
            isRegistered = function(packId)
                return deps.coordinator.isRegistered(packId)
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

return frameworkRuntime
