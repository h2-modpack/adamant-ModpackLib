local deps = ...

local logging = deps.logging
local storageService = deps.storage
local values = deps.values
local chalk = deps.chalk

local moduleState = {}

local persistenceBackend = import('core/module_state/persistent/backend.lua', nil, {
    chalk = chalk,
})
local storageConfigAdapter = import('core/module_state/persistent/storage_config_adapter.lua')
local persistentCacheStore = import('core/module_state/persistent/persistent_cache_store.lua')

local persistentStateModule = import('core/module_state/persistent/persistent_state.lua', nil, {
    logging = logging,
    storage = storageService,
    values = values,
})

local actionBufferModule = import('core/module_state/actions/action_buffer.lua', nil, {
    logging = logging,
    values = values,
})
moduleState.actionBuffer = actionBufferModule

local uiActionsModule = import('core/module_state/actions/ui_actions.lua')
moduleState.uiActions = uiActionsModule

local stagedStateModule = import('core/module_state/staged/staged_state.lua', nil, {
    logging = logging,
    storage = storageService,
    values = values,
})

local uiStateModule = import('core/module_state/staged/ui_state.lua')
moduleState.uiState = uiStateModule

local storeModule = import('core/module_state/persistent/store.lua')

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
---@field persistentState PersistentState
---@field stagedState StagedState
---@field cacheStore PersistentCacheStore

---@class ActionBuffer
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

---@class PersistentState
---@field get fun(alias: string): StorageField|StorageTableReadOnly|nil
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableReadOnly|nil
---@field getAliasSchema fun(alias: string): StorageNode|PackedBitNode|nil

---@class Store
---@field get fun(alias: string): StorageField|StorageTableReadOnly|nil
---@field read fun(alias: string, ...): any

---@class StagedState
---@field view table<string, any>
---@field get fun(alias: string): StorageField|StorageTableStagedState|nil
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableStagedState|nil
---@field field fun(alias: string): StorageField
---@field getAliasSchema fun(alias: string): StorageNode|PackedBitNode|nil
---@field write fun(alias: string, value: any)
---@field reset fun(alias: string)
---@field resetAll fun(opts: table|nil): boolean, number
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
    local backend = persistenceBackend.create(modConfig)
    local storageConfig = storageConfigAdapter.create(modConfig, backend)
    local persistentState = persistentStateModule.create(storageConfig, storage)
    local stagedState = stagedStateModule.createStagedState(storageConfig, storage)
    local cacheStore = persistentCacheStore.create(modConfig, backend)

    return {
        persistentState = persistentState,
        stagedState = stagedState,
        cacheStore = cacheStore,
    }
end

-- Internal API: narrows persistent state to the author-facing runtime store.
function moduleState.createStore(persistentState)
    return storeModule.create(persistentState)
end

function moduleState.createActionBuffer()
    return actionBufferModule.createBuffer()
end

function moduleState.createCommitActions(actionSnapshot)
    return actionBufferModule.createCommitActions(actionSnapshot)
end

return moduleState
