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

local function createCommittedRootAdapter(persistentState)
    return {
        readRoot = function(root)
            return persistentState._readRoot(root)
        end,
        replaceRoot = function(root, value)
            persistentState._replaceRoot(root, value)
        end,
        reloadFromConfig = function()
            return persistentState._reloadFromConfig()
        end,
    }
end

function moduleState.create(definition, opts)
    if type(definition) ~= "table" or definition._preparedDefinition ~= true then
        logging.violate(
            "store.invalid_create_args",
            "createModuleState expects a prepared definition"
        )
    end

    opts = opts or {}
    local storage = definition.storage
    local backend = backendFactory.create(opts)
    local storageConfig = storageConfigAdapter.create(backend, definition.name or definition.id)
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
