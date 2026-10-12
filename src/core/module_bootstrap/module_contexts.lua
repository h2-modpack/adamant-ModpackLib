local deps = ...

local moduleState = deps.moduleState
local cache = deps.cache
local sharedRefs = deps.sharedRefs
local controlRefs = deps.controlRefs
local uiContextModule = deps.uiContext

local moduleContexts = {}

---Build one module's callback contexts in one place. `runtime.data` carries
---`cache`/`shared`/`controls` from construction; `runtime.cache/shared/controls`
---alias the same objects. `ui.data.shared` is the UI-lane (staged emit) shared surface.
---@param inputs AdamantModpackLib.ModuleContextInputs
---@return AdamantModpackLib.RuntimeContext runtime
---@return table uiContext `{ ui, draw, run(callback) }`
function moduleContexts.create(inputs)
    local state = inputs.state
    local ownerId = inputs.ownerId
    local runtimeCache = cache.data.create({
        declarations = inputs.cacheDeclarations,
        ownerId = ownerId,
        source = "store.cache",
    })
    local runtimeShared = sharedRefs.create({
        ownerId = ownerId,
        declarations = inputs.sharedDeclarations,
        emit = inputs.emitShared,
        source = "store.shared",
    })
    local runtimeControls = controlRefs.createRuntime(state.persistent, inputs.controlCatalog)
    local uiShared = sharedRefs.create({
        ownerId = ownerId,
        declarations = inputs.sharedDeclarations,
        emit = inputs.stageShared,
        source = "state.shared",
    })

    local lanes = moduleState.createLanes(state, {
        runtimeData = {
            cache = runtimeCache,
            shared = runtimeShared,
            controls = runtimeControls,
        },
        uiData = {
            shared = uiShared,
        },
    })

    local runtime = {
        data = lanes.runtimeData,
        status = lanes.runtimeStatus,
        cache = runtimeCache,
        shared = runtimeShared,
        controls = runtimeControls,
    }
    local uiContext = uiContextModule.create({
        lanes = lanes,
        shared = uiShared,
        host = inputs.host,
        controls = controlRefs.createUi(state.staged, inputs.controlCatalog),
        resetAll = state.txn.queueResetAll,
    })
    return runtime, uiContext
end

return moduleContexts
