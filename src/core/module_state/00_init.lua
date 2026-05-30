local deps = ...

local logging = deps.logging
local storageService = deps.storage
local values = deps.values
local chalk = deps.chalk
local phaseGate = deps.phaseGate

local moduleState = {}

local persistenceBackend = import('core/module_state/persistent/backend.lua', nil, {
    chalk = chalk,
})
local storageConfigAdapter = import('core/module_state/persistent/storage_config_adapter.lua')

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

local uiActionsModule = import('core/module_state/actions/ui_actions.lua', nil, {
    phaseGate = phaseGate,
    actionRefs = actionBufferModule,
})
moduleState.uiActions = uiActionsModule

local stagedStateModule = import('core/module_state/staged/staged_state.lua', nil, {
    logging = logging,
    storage = storageService,
    values = values,
})

local storageRefAdapter = import('core/module_state/storage_ref_adapter.lua', nil, {
    logging = logging,
    phaseGate = phaseGate,
    storage = storageService,
})

local uiStateModule = import('core/module_state/staged/ui_state.lua', nil, {
    logging = logging,
    phaseGate = phaseGate,
    storageRefAdapter = storageRefAdapter,
})
moduleState.uiState = uiStateModule

local storeModule = import('core/module_state/persistent/store.lua', nil, {
    phaseGate = phaseGate,
    storageRefAdapter = storageRefAdapter,
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
---@field persistentState PersistentState
---@field stagedState StagedState

---@class ActionBuffer
---@field stage fun(actionKey: string, value: any)
---@field read fun(actionKey: string): any
---@field clear fun(actionKey: string)
---@field has fun(actionKey: string): boolean
---@field hasAny fun(): boolean
---@field captureSnapshot fun(): table
---@field clearAll fun()
---@field getRef fun(actionKey: string): table
---@field emitShared fun(id: string, eventName: string, payload: any)
---@field executePendingActions fun(host: Host, uiData: DrawState, actionRuntime: ActionRuntimeBridge)
---@field flushPendingSharedEvents fun(host: Host)

---@class ActionRuntimeBridge
---@field read fun(alias: string, ...): any
---@field set fun(alias: string, value: any): boolean
---@field clear fun(alias: string): boolean

---@class PersistentState
---@field get fun(alias: string): StorageField|StorageTableReadOnly|nil
---@field read fun(alias: string): any
---@field table fun(alias: string): StorageTableReadOnly|nil
---@field getAliasSchema fun(alias: string): StorageNode|PackedBitNode|nil

---@class Store
---@field get fun(alias: string): StorageField|StorageTableReadOnly|nil
---@field cache table|nil
---@field shared table|nil
---@field runtime table|nil
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
---@field cache table|nil
---@field actions table<string, fun(host: Host, uiData: DrawState, actionRuntime: ActionRuntimeBridge, value: any)>|nil
---@field _actionOrder string[]|nil

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
    local stagedState = stagedStateModule.createStagedState(storageConfig, storage, persistentState)

    return {
        persistentState = persistentState,
        stagedState = stagedState,
    }
end

-- Internal API: narrows persistent state to the runtime store.
function moduleState.createStore(persistentState, cache, shared)
    return storeModule.create(persistentState, cache, shared)
end

function moduleState.createActionBuffer(actionCatalog)
    return actionBufferModule.createBuffer(actionCatalog)
end

function moduleState.createCommitActions(actionSnapshot)
    return actionBufferModule.createCommitActions(actionSnapshot)
end

return moduleState
