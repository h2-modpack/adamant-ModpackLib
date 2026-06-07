local deps = ...

local logging = deps.logging
local coordinatorRegistry = deps.coordinatorRegistry

-- Hot-reload-stable coordinator registries.
coordinatorRegistry.configs = coordinatorRegistry.configs or {}
coordinatorRegistry.rebuilds = coordinatorRegistry.rebuilds or {}

local coordinator = {}
local configs = coordinatorRegistry.configs
local rebuilds = coordinatorRegistry.rebuilds

---@class CoordinatorConfig
---@field ModEnabled boolean

--- Returns whether a pack id has coordinator metadata registered.
---@param packId string Unique coordinator pack identifier.
---@return boolean coordinated True when the pack id is registered with the coordinator.
function coordinator.isRegistered(packId)
    return configs[packId] ~= nil
end

--- Returns whether any coordinator metadata has been registered.
---@return boolean registered True when at least one coordinator exists.
function coordinator.hasRegistrations()
    return next(configs) ~= nil
end

--- Returns coordinator configuration for an internal pack id.
---@param packId string Unique coordinator pack identifier.
---@return CoordinatorConfig|nil config Registered coordinator config, or nil.
function coordinator.getConfig(packId)
    return configs[packId]
end

--- Registers coordinator metadata for Framework-owned pack bootstrap.
---@param packId string Unique coordinator pack identifier.
---@param config CoordinatorConfig Coordinator configuration table.
function coordinator.register(packId, config)
    if type(packId) ~= "string" or packId == "" then
        logging.violate(
            "coordinator.invalid_registration",
            "coordinator.register: packId must be a non-empty string"
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
end

--- Registers a Framework rebuild callback for coordinated module structural changes.
---@param packId string Unique coordinator pack identifier.
---@param callback fun(reason: table)|nil Callback invoked when Lib requests a framework rebuild.
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

--- Requests a coordinated pack-level rebuild after a structural module change.
---@param packId string Unique coordinator pack identifier.
---@param reason table Reason metadata describing the rebuild request.
---@return boolean requested True when a rebuild callback was registered and accepted the request.
function coordinator.requestRebuild(packId, reason)
    local callback = packId and rebuilds[packId] or nil
    if callback == nil then
        return false
    end

    return callback(reason or {}) == true
end


return coordinator
