local deps = ...

local logging = deps.logging
local system = deps.system

-- Overlay surface Lib modpack runtimes use for pack HUD lines and UI suppression.
return {
    order = deps.order,
    define = function(packId, name, register)
        if type(packId) ~= "string" or packId == "" then
            logging.violate(
                "modpack.overlays.invalid_pack",
                "modpack.overlays.define: packId must be a non-empty string"
            )
        end
        if type(name) ~= "string" or name == "" then
            logging.violate(
                "modpack.overlays.invalid_scope",
                "modpack.overlays.define: name must be a non-empty string"
            )
        end
        if type(register) ~= "function" then
            logging.violate(
                "overlays.invalid_registration",
                "modpack.overlays.define: register must be a function"
            )
        end

        local scopedOwnerId = "adamant-modpack." .. packId .. "." .. name
        return system.create(nil, scopedOwnerId).define(register)
    end,
    suppressForUi = deps.suppressForUi,
}
