local deps = ...

local logging = deps.logging
local storageService = deps.storage
local values = deps.values
local chalk = deps.chalk

local moduleState = {}

local backendModule = import('core/module_state/backend.lua', nil, {
    chalk = chalk,
})
local storageAdapter = import('core/module_state/adapter_storage.lua')
local cacheAdapter = import('core/module_state/adapter_cache.lua')

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
})

---@class ConfigBackendEntry
---@field get fun(self: ConfigBackendEntry): any
---@field set fun(self: ConfigBackendEntry, value: any)

---@class PersistenceBackend
---@field rawConfig table
---@field getEntry fun(section: string, key: string): ConfigBackendEntry|nil
---@field ensure fun(section: string, key: string, value: any): boolean
---@field read fun(section: string, key: string): any
---@field write fun(section: string, key: string, value: any): boolean
---@field clear fun(section: string, key: string): boolean

---@class StorageConfigAdapter
---@field getEntry fun(alias: string): ConfigBackendEntry|nil
---@field ensureValue fun(alias: string, value: any): boolean
---@field readValue fun(alias: string): any
---@field writeValue fun(alias: string, value: any): boolean

---@class ModuleState
---@field store ManagedStore
---@field session Session
---@field cacheStore PersistentCacheStore

---@class ActionState
---@field stage fun(actionKey: string, value: any)
---@field read fun(actionKey: string): any
---@field clear fun(actionKey: string)
---@field has fun(actionKey: string): boolean
---@field hasAny fun(): boolean
---@field captureSnapshot fun(): table
---@field clearAll fun()
---@field getRef fun(actionKey: string): table

---@class PersistentCacheStore
---@field read fun(key: string): any
---@field has fun(key: string): boolean
---@field write fun(key: string, value: any): boolean
---@field clear fun(key: string): boolean

---@class ManagedStore
---@field get fun(alias: string): StorageField|StorageTableReadOnly|nil
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableReadOnly|nil
---@field getAliasSchema fun(alias: string): StorageNode|PackedBitNode|nil

---@class AuthorStore
---@field get fun(alias: string): StorageField|StorageTableReadOnly|nil
---@field read fun(alias: string, ...): any

---@class Session
---@field view table<string, any>
---@field get fun(alias: string): StorageField|StorageTableSession|nil
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
    local persistenceBackend = backendModule.create(modConfig)
    local storageConfig = storageAdapter.create(modConfig, persistenceBackend)
    local store = managedStore.create(storageConfig, storage)
    local session = sessionModule.createSession(storageConfig, storage)
    local cacheStore = cacheAdapter.create(modConfig, persistenceBackend)

    return {
        store = store,
        session = session,
        cacheStore = cacheStore,
    }
end

-- Internal API: writes storage through a Lib-created managed store.
function moduleState.writePersisted(store, alias, value)
    return managedStore.writePersisted(store, alias, value)
end

-- Internal API: narrows a full managed store to the author-facing runtime surface.
function moduleState.createAuthorStore(store)
    return managedStore.createAuthorStore(store)
end

-- Internal API: narrows a full staged session to the author-facing UI surface.
function moduleState.createAuthorSession(session, opts)
    return sessionModule.createAuthorSession(session, opts)
end

function moduleState.createDrawActions(actions)
    return actionsModule.createDrawActions(actions)
end

function moduleState.createActionState()
    return actionsModule.createState()
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

    for _, node in ipairs(storageService.getSessionRoots(storage)) do
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
