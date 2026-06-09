local deps = ...

local logging = deps.logging
local coordinatorRegistry = deps.coordinatorRegistry

-- Hot-reload-stable coordinator registries.
coordinatorRegistry.configs = coordinatorRegistry.configs or {}
coordinatorRegistry.displayNames = coordinatorRegistry.displayNames or {}
coordinatorRegistry.rebuilds = coordinatorRegistry.rebuilds or {}

local coordinator = {}
local configs = coordinatorRegistry.configs
local displayNames = coordinatorRegistry.displayNames
local rebuilds = coordinatorRegistry.rebuilds

function coordinator.isRegistered(packId)
    return configs[packId] ~= nil
end

function coordinator.hasRegistrations()
    return next(configs) ~= nil
end

function coordinator.getConfig(packId)
    return configs[packId]
end

function coordinator.getDisplayName(packId)
    return displayNames[packId]
end

function coordinator.register(packId, displayName, config)
    if type(packId) ~= "string" or packId == "" then
        logging.violate(
            "coordinator.invalid_registration",
            "coordinator.register: packId must be a non-empty string"
        )
    end
    if config == nil then
        if displayName ~= nil then
            logging.violate(
                "coordinator.invalid_registration",
                "coordinator.register: displayName must be nil when clearing registration"
            )
        end
        configs[packId] = nil
        displayNames[packId] = nil
        return
    end
    if type(displayName) ~= "string" or displayName == "" then
        logging.violate(
            "coordinator.invalid_registration",
            "coordinator.register: displayName must be a non-empty string"
        )
    end
    if config ~= nil and type(config) ~= "table" then
        logging.violate(
            "coordinator.invalid_registration",
            "coordinator.register: config must be a table when provided"
        )
    end
    if config ~= nil and type(config.ModEnabled) ~= "boolean" then
        logging.violate(
            "coordinator.invalid_registration",
            "coordinator.register: config.ModEnabled must be a boolean"
        )
    end
    configs[packId] = config
    displayNames[packId] = displayName
end

function coordinator.registerRebuild(packId, callback)
    if callback == nil then
        rebuilds[packId] = nil
        return
    end

    if type(callback) ~= "function" then
        logging.violate(
            "coordinator.invalid_rebuild_callback",
            "coordinator.registerRebuild: callback must be a function when provided"
        )
    end
    rebuilds[packId] = callback
end

function coordinator.requestRebuild(packId, reason)
    local callback = packId and rebuilds[packId] or nil
    if callback == nil then
        return false
    end

    return callback(reason or {}) == true
end

return coordinator
