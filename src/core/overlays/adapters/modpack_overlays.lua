local deps = ...

local logging = deps.logging
local suppression = deps.suppression
local system = deps.system
local overlayOrder = deps.order

local modpack = {}

local function validatePackId(packId)
    if type(packId) ~= "string" or packId == "" then
        logging.violate(
            "modpack.overlays.invalid_pack",
            "modpack.overlays.define: packId must be a non-empty string"
        )
    end
end

local function validateName(name)
    if type(name) ~= "string" or name == "" then
        logging.violate(
            "modpack.overlays.invalid_scope",
            "modpack.overlays.define: name must be a non-empty string"
        )
    end
end

local function define(packId, name, register)
    validatePackId(packId)
    validateName(name)
    if type(register) ~= "function" then
        logging.violate(
            "overlays.invalid_registration",
            "modpack.overlays.define: register must be a function"
        )
    end

    local scopedOwnerId = "adamant-modpack." .. packId .. "." .. name
    return system.create(nil, scopedOwnerId).define(register)
end

function modpack.create()
    return {
        order = overlayOrder,
        define = function(packId, name, register)
            return define(packId, name, register)
        end,
        suppressForUi = suppression.suppressForUi,
        isUiSuppressed = suppression.isUiSuppressed,
    }
end

return {
    create = modpack.create,
}
