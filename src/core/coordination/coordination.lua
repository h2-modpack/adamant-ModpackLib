local deps = ...

local logging = deps.logging
local coordinationRegistry = deps.coordinationRegistry

-- Hot-reload-stable modpack coordination registries.
coordinationRegistry.configs = coordinationRegistry.configs or {}
coordinationRegistry.displayNames = coordinationRegistry.displayNames or {}
coordinationRegistry.rebuilds = coordinationRegistry.rebuilds or {}

local coordination = {}
local configs = coordinationRegistry.configs
local displayNames = coordinationRegistry.displayNames
local rebuilds = coordinationRegistry.rebuilds

function coordination.isRegistered(packId)
    return configs[packId] ~= nil
end

function coordination.hasRegistrations()
    return next(configs) ~= nil
end

function coordination.getConfig(packId)
    return configs[packId]
end

function coordination.getDisplayName(packId)
    return displayNames[packId]
end

function coordination.register(packId, displayName, config)
    if type(packId) ~= "string" or packId == "" then
        logging.violate(
            "coordinator.invalid_registration",
            "modpack.coordination.register: packId must be a non-empty string"
        )
    end
    if config == nil then
        if displayName ~= nil then
            logging.violate(
                "coordinator.invalid_registration",
                "modpack.coordination.register: displayName must be nil when clearing registration"
            )
        end
        configs[packId] = nil
        displayNames[packId] = nil
        return
    end
    if type(displayName) ~= "string" or displayName == "" then
        logging.violate(
            "coordinator.invalid_registration",
            "modpack.coordination.register: displayName must be a non-empty string"
        )
    end
    if config ~= nil and type(config) ~= "table" then
        logging.violate(
            "coordinator.invalid_registration",
            "modpack.coordination.register: config must be a table when provided"
        )
    end
    if config ~= nil and type(config.ModEnabled) ~= "boolean" then
        logging.violate(
            "coordinator.invalid_registration",
            "modpack.coordination.register: config.ModEnabled must be a boolean"
        )
    end
    configs[packId] = config
    displayNames[packId] = displayName
end

function coordination.registerRebuild(packId, callback)
    if callback == nil then
        rebuilds[packId] = nil
        return
    end

    if type(callback) ~= "function" then
        logging.violate(
            "coordinator.invalid_rebuild_callback",
            "modpack.coordination.registerRebuild: callback must be a function when provided"
        )
    end
    rebuilds[packId] = callback
end

function coordination.requestRebuild(packId, reason)
    local callback = packId and rebuilds[packId] or nil
    if callback == nil then
        return false
    end

    return callback(reason or {}) == true
end

return coordination
