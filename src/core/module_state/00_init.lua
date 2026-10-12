local deps = ...

local logging = deps.logging
local storageApi = deps.storage
local values = deps.values
local rom = deps.rom

local moduleState = {}

local backendFactory = import('core/module_state/persistent/backend_factory.lua', nil, {
    logging = logging,
    rom = rom,
})
local storageConfigAdapter = import('core/module_state/persistent/storage_config_adapter.lua', nil, {
    storage = storageApi,
})
local persistentStateModule = import('core/module_state/persistent/persistent_state.lua', nil, {
    logging = logging,
    storage = storageApi,
    values = values,
})
local stagedStateModule = import('core/module_state/staged/staged_state.lua', nil, {
    logging = logging,
    storage = storageApi,
    values = values,
})
local statusStateModule = import('core/module_state/status_state.lua', nil, {
    logging = logging,
    storage = storageApi,
})
local actionBufferModule = import('core/module_state/actions/action_buffer.lua', nil, {
    logging = logging,
    values = values,
})
local uiActionsModule = import('core/module_state/actions/ui_actions.lua', nil, {
    actionRefs = actionBufferModule,
})
local storageRefAdapter = import('core/module_state/storage_ref_adapter.lua', nil, {
    logging = logging,
    storage = storageApi,
})
local transactionModule = import('core/module_state/transaction.lua', nil, {
    values = values,
})

---@param persistentState AdamantModpackLib.PersistentState
---@param stagedView AdamantModpackLib.StagedState
---@param status AdamantModpackLib.StatusState
---@param actionBuffer table
---@return AdamantModpackLib.ModuleStateLanes
local function createLanes(persistentState, stagedView, status, actionBuffer)
    return {
        runtimeData = storageRefAdapter.createLane({
            get = persistentState.get,
            source = "runtime.data",
        }),
        runtimeStatus = storageRefAdapter.createLane({
            get = status.get,
            source = "runtime.status",
            writable = true,
            resetRoot = status.reset,
        }),
        uiData = storageRefAdapter.createLane({
            get = stagedView.get,
            source = "ui.data",
            writable = true,
        }),
        uiStatus = storageRefAdapter.createLane({
            get = status.get,
            source = "ui.status",
        }),
        uiActions = uiActionsModule.create(actionBuffer),
    }
end

---Construct one module's state: committed persistent data, staged view,
---status, action buffer, author lanes, and the lifecycle transaction.
---@param definition AdamantModpackLib.PreparedDefinition
---@param opts? table Backend options (`configPath`, `pluginGuid`).
---@return AdamantModpackLib.ModuleState
function moduleState.create(definition, opts)
    if type(definition) ~= "table" or definition._preparedDefinition ~= true then
        logging.violate(
            "store.invalid_create_args",
            "createModuleState expects a prepared definition"
        )
    end

    local storage = definition.storage
    local backend = backendFactory.create(opts or {})
    local storageConfig = storageConfigAdapter.create(backend, definition.name or definition.id)
    local persistentState, committed = persistentStateModule.create(storageConfig, storage)
    local stagedView, stagedInternals = stagedStateModule.create(storageConfig, storage, committed)
    local status = statusStateModule.create(committed)
    local actionBuffer = actionBufferModule.createBuffer({
        actions = definition.actions,
        order = definition._actionOrder,
    })

    return {
        persistent = persistentState,
        staged = stagedView,
        status = status,
        actionBuffer = actionBuffer,
        lanes = createLanes(persistentState, stagedView, status, actionBuffer),
        txn = transactionModule.create(persistentState, stagedView, stagedInternals, status, actionBuffer),
    }
end

moduleState.isDrawActionRef = actionBufferModule.isDrawActionRef
moduleState.createCommitActions = actionBufferModule.createCommitActions

return moduleState
