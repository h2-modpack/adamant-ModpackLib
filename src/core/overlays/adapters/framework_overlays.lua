local deps = ...

local logging = deps.logging
local suppression = deps.suppression
local system = deps.system
local overlayOrder = deps.order

local framework = {}

local function validatePackId(packId)
    if type(packId) ~= "string" or packId == "" then
        logging.violate(
            "framework_runtime.invalid_pack",
            "frameworkRuntime.overlays.define: packId must be a non-empty string"
        )
    end
end

local function validateName(name)
    if type(name) ~= "string" or name == "" then
        logging.violate(
            "framework_runtime.invalid_overlay_scope",
            "frameworkRuntime.overlays.define: name must be a non-empty string"
        )
    end
end

local function define(packId, name, register)
    validatePackId(packId)
    validateName(name)
    if type(register) ~= "function" then
        logging.violate(
            "overlays.invalid_registration",
            "frameworkRuntime.overlays.define: register must be a function"
        )
    end

    local scopedOwnerId = "adamant-framework." .. packId .. "." .. name
    return system.create(nil, scopedOwnerId).define(register)
end

function framework.create()
    return {
        order = overlayOrder,
        define = function(packId, name, register)
            return define(packId, name, register)
        end,
    }
end

return {
    create = framework.create,
    ui = {
        suppressOverlays = suppression.suppressForUi,
        areOverlaysSuppressed = suppression.isUiSuppressed,
    },
}
