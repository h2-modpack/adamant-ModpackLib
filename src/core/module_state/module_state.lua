local deps = ...

local logging = deps.logging
local storageService = deps.storage
local values = deps.values
local chalk = deps.chalk

local moduleState = {}

local backendModule = import('core/module_state/backend.lua', nil, {
    chalk = chalk,
})

local managedStore = import('core/module_state/store.lua', nil, {
    logging = logging,
    storage = storageService,
    values = values,
})

local actionsModule = import('core/module_state/actions.lua', nil, {
    logging = logging,
    values = values,
})
moduleState.actions = actionsModule

local sessionModule = import('core/module_state/session.lua', nil, {
    logging = logging,
    storage = storageService,
    values = values,
    actions = actionsModule,
})

---@class ConfigBackendEntry
---@field get fun(self: ConfigBackendEntry): any
---@field set fun(self: ConfigBackendEntry, value: any)

---@class ConfigBackend
---@field rawConfig table
---@field getEntry fun(alias: string): ConfigBackendEntry|nil
---@field ensureValue fun(alias: string, value: any): boolean
---@field readValue fun(alias: string): any
---@field writeValue fun(alias: string, value: any): boolean

---@class ModuleState
---@field store ManagedStore
---@field session Session

---@class ManagedStore
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableReadOnly|nil
---@field writeUnstaged fun(alias: string, value: any)

---@class Session
---@field view table<string, any>
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableSession|nil
---@field field fun(alias: string): StorageField
---@field getAliasSchema fun(alias: string): StorageNode|PackedBitNode|nil
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field _flushToConfig fun()
---@field _reloadFromConfig fun()
---@field _captureDirtyConfigSnapshot fun(): table[]
---@field _restoreConfigSnapshot fun(snapshot: table[]|nil)
---@field isDirty fun(): boolean
---@field auditMismatches fun(): string[]

---@class ModuleDefinition
---@field modpack string|nil
---@field id string|nil
---@field name string|nil
---@field shortName string|nil
---@field tooltip string|nil
---@field default boolean|nil
---@field storage StorageSchema|nil
---@field hashGroupPlan table|nil

--- Creates module state access surfaces around a prepared definition and config table.
---@param modConfig table Module config table used for persisted reads and writes.
---@param definition ModuleDefinition Prepared module definition declaring storage and mutation behavior.
---@return ModuleState state Managed state surfaces for runtime and staged UI access.
function moduleState.create(modConfig, definition)
    if type(modConfig) ~= "table" then
        logging.violate("store.invalid_config", "createModuleState expects config to be a table")
    end
    if type(definition) ~= "table" or definition._preparedDefinition ~= true then
        logging.violate(
            "store.invalid_create_args",
            "createModuleState expects a prepared definition"
        )
    end

    local storage = definition.storage
    local backend = backendModule.getConfigBackend(modConfig)
    local store = managedStore.create(modConfig, backend, storage)
    local session = sessionModule.createSession(modConfig, backend, storage)

    return {
        store = store,
        session = session,
    }
end

-- Internal API: writes storage through a Lib-created managed store.
function moduleState.writePersisted(store, alias, value)
    return managedStore.writePersisted(store, alias, value)
end

-- Internal API: narrows a full staged session to the author-facing UI surface.
function moduleState.createAuthorSession(session, opts)
    return sessionModule.createAuthorSession(session, opts)
end

function moduleState.createDrawActions(session)
    return sessionModule.createDrawActions(session)
end

function moduleState.createCommitActions(actions)
    return actionsModule.createCommitActions(actions)
end

--- Resets persistent storage roots to defaults in a staged session.
---@param storage StorageSchema Validated storage schema.
---@param session Session Staged session returned by `moduleState.create`.
---@param opts table|nil Optional `{ exclude = { Alias = true } }` map.
---@return boolean changed True when at least one alias was reset.
---@return number count Number of aliases reset.
function moduleState.resetSessionToDefaults(storage, session, opts)
    local exclude = type(opts) == "table" and type(opts.exclude) == "table" and opts.exclude or {}
    local count = 0

    for _, node in ipairs(storageService.getStageRoots(storage)) do
        local alias = node.alias
        if node._persist and alias ~= nil and not exclude[alias] then
            local current = session.read(alias)
            if not storageService.valuesEqual(node, current, node.default) then
                session.reset(alias)
                count = count + 1
            end
        end
    end

    return count > 0, count
end

return moduleState
