local deps = ...

local logging = deps.logging
local storageApi = deps.storage
local values = deps.values
local chalk = deps.chalk

local moduleState = {}

local persistenceBackend = import('core/module_state/persistent/backend.lua', nil, {
    chalk = chalk,
})
local storageConfigAdapter = import('core/module_state/persistent/storage_config_adapter.lua')

local persistentStateModule = import('core/module_state/persistent/persistent_state.lua', nil, {
    logging = logging,
    storage = storageApi,
    values = values,
})

local actionBufferModule = import('core/module_state/actions/action_buffer.lua', nil, {
    logging = logging,
    values = values,
})
moduleState.actionBuffer = actionBufferModule

local uiActionsModule = import('core/module_state/actions/ui_actions.lua', nil, {
    actionRefs = actionBufferModule,
})
moduleState.uiActions = uiActionsModule

local stagedStateModule = import('core/module_state/staged/staged_state.lua', nil, {
    logging = logging,
    storage = storageApi,
    values = values,
})

local storageRefAdapter = import('core/module_state/storage_ref_adapter.lua', nil, {
    logging = logging,
    storage = storageApi,
})

local uiStateModule = import('core/module_state/staged/ui_state.lua', nil, {
    logging = logging,
    storageRefAdapter = storageRefAdapter,
})
moduleState.uiState = uiStateModule

local storeModule = import('core/module_state/persistent/store.lua', nil, {
    logging = logging,
    storageRefAdapter = storageRefAdapter,
})

local runtimeStatusModule = import('core/status/adapters/runtime_status.lua', nil, {
    logging = logging,
    storageRefAdapter = storageRefAdapter,
})

local uiStatusModule = import('core/status/adapters/ui_status.lua', nil, {
    logging = logging,
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

---@class CommittedRootState
---@field readRoot fun(root: StorageNode): any
---@field replaceRoot fun(root: StorageNode, value: any)
---@field reloadFromConfig fun()

---@class ActionBuffer
---@field stage fun(actionKey: string, value: any)
---@field read fun(actionKey: string): any
---@field clear fun(actionKey: string)
---@field has fun(actionKey: string): boolean
---@field hasAny fun(): boolean
---@field captureSnapshot fun(): table
---@field captureInternalSnapshot fun(): table
---@field clearAll fun()
---@field clearPublicIntent fun()
---@field stageInternal fun(actionKey: string, value: any)
---@field emitShared fun(id: string, eventName: string, payload: any)
---@field executeCommittedActions fun(host: Host, runtime: RuntimeContext, actionSnapshot: table)
---@field flushPendingSharedEvents fun(emitSharedEvent: fun(id: string, eventName: string, payload: any))

---@class PersistentState
---@field get fun(alias: string): StorageField|StorageTableReadOnly|nil
---@field read fun(alias: string): any
---@field status StatusState
---@field table fun(alias: string): StorageTableReadOnly|nil
---@field getAliasSchema fun(alias: string): StorageNode|PackedBitNode|nil

---@class StatusState
---@field get fun(alias: string): StorageField|StorageTableStagedState|nil
---@field read fun(alias: string, ...): any
---@field write fun(alias: string, ...): boolean
---@field reset fun(alias: string, ...): boolean
---@field countResettable fun(opts: table|nil): boolean, number
---@field resetAll fun(opts: table|nil): boolean, number

---@class Store
---@field get fun(alias: string): StorageField|StorageTableReadOnly|nil
---@field cache table|nil
---@field shared table|nil
---@field read fun(alias: string, ...): any

---@class RuntimeStatusState
---@field get fun(alias: string): StorageField|StorageTableStagedState|nil
---@field read fun(alias: string, ...): any
---@field write fun(alias: string, ...): boolean
---@field reset fun(alias: string, ...): boolean

---@class UiStatusState
---@field get fun(alias: string): StorageField|StorageTableReadOnly|nil
---@field read fun(alias: string, ...): any

---@class StagedState
---@field get fun(alias: string): StorageField|StorageTableStagedState|nil
---@field read fun(alias: string): any
---@field status table
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
---@field actions table<string, fun(host: Host, runtime: RuntimeContext, value: any)>|nil
---@field _actionOrder string[]|nil

local function createCommittedRootAdapter(persistentState)
    return {
        readRoot = function(root)
            return persistentState._readRoot(root)
        end,
        replaceRoot = function(root, value)
            persistentState._replaceRoot(root, value)
        end,
        reloadFromConfig = function()
            persistentState._reloadFromConfig()
        end,
    }
end

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
    local committedRoots = createCommittedRootAdapter(persistentState)
    local stagedState = stagedStateModule.createStagedState(storageConfig, storage, committedRoots)

    return {
        persistentState = persistentState,
        stagedState = stagedState,
    }
end

-- Internal API: narrows persistent state to the runtime store.
function moduleState.createStore(persistentState, cache, shared)
    return storeModule.create(persistentState, cache, shared)
end

function moduleState.createRuntimeStatus(persistentState)
    return runtimeStatusModule.create(persistentState)
end

function moduleState.createUiStatus(stagedState)
    return uiStatusModule.create(stagedState)
end

function moduleState.createActionBuffer(actionCatalog)
    return actionBufferModule.createBuffer(actionCatalog)
end

function moduleState.createCommitActions(actionSnapshot)
    return actionBufferModule.createCommitActions(actionSnapshot)
end

return moduleState
