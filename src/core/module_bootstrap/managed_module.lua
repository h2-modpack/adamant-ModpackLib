local deps = ...

local logging = deps.logging
local cache = deps.cache
local shared = deps.shared
local sharedData = deps.sharedData
local moduleState = deps.moduleState
local overlays = deps.overlays
local mutation = deps.mutation
local definition = deps.definition
local moduleRegistry = deps.moduleRegistry
local storage = deps.storage
local uiDraw = deps.uiDraw
local controls = deps.controls
local managedModule = {
    prepareDefinition = definition.prepareDefinition,
    prepareDefinitionWithInternalStorage = definition.prepareDefinitionWithInternalStorage,
    prepareDefinitionWithInternalDeclarations = definition.prepareDefinitionWithInternalDeclarations,
}
local phaseGate = deps.phaseGate
local uiPhaseModule = import('core/module_bootstrap/ui/phase.lua', nil, {
    uiDraw = uiDraw,
    moduleState = moduleState,
    phaseGate = phaseGate,
})
local moduleLifecycle = import('core/module_bootstrap/managed_module_lifecycle.lua', nil, {
    logging = logging,
    mutation = mutation,
    moduleState = moduleState,
})
local moduleActivation = import('core/module_bootstrap/managed_module_activation.lua', nil, {
    logging = logging,
    shared = deps.shared,
    hooks = deps.hooks,
    overlays = overlays,
    mutation = mutation,
    fallbackUi = deps.fallbackUi,
    coordinator = deps.coordinator,
    moduleRegistry = moduleRegistry,
})

function managedModule.getRecord(module)
    return moduleRegistry.getRecord(module)
end

function managedModule.addEffectReceipt(module, name, receipt)
    local record = moduleRegistry.getRecord(module)
    if not record then
        logging.violate("host.invalid_activate_opts", "managedModule.addEffectReceipt: module is required")
    end
    if record.activated ~= true then
        logging.violate("host.not_activated", "managedModule.addEffectReceipt requires an activated module")
    end
    if type(name) ~= "string" or name == "" then
        logging.violate("host.invalid_activate_opts", "managedModule.addEffectReceipt: receipt name is required")
    end
    if type(receipt) ~= "table" or type(receipt.dispose) ~= "function" then
        logging.violate("host.invalid_activate_opts", "managedModule.addEffectReceipt: receipt dispose function is required")
    end

    record.effectReceipts = record.effectReceipts or {}
    record.effectReceipts[#record.effectReceipts + 1] = {
        name = name,
        receipt = receipt,
    }
end

---@class ManagedModuleCreateOpts
---@field definition ModuleDefinition
---@field pluginGuid string
---@field persistentState PersistentState
---@field stagedState StagedState
---@field onActivate fun(host: Host, runtime: RuntimeContext)|nil
---@field onCommit fun(host: Host, runtime: RuntimeContext, commit: table)|nil
---@field drawTab fun(host: Host, ui: UiContext)
---@field drawQuickContent fun(host: Host, ui: UiContext)|nil

---@class DrawContext
---@field imgui table
---@field widgets DrawWidgets
---@field nav DrawNav
---@field log fun(fmt: string, ...): nil
---@field logIf fun(fmt: string, ...): nil

---@class DrawActions
---@field get fun(actionKey: string): DrawActionRef
---@field trigger fun(actionKey: string, value: any|nil)
---@field emit fun(id: string, eventName: string, payload: any)

---@class DrawActionRef
---@field stage fun(self: DrawActionRef, value: any)
---@field read fun(self: DrawActionRef): any
---@field clear fun(self: DrawActionRef)
---@field has fun(self: DrawActionRef): boolean

---@class ManagedModule
---@field getHostId fun(): string
---@field getModuleId fun(): string
---@field getPackId fun(): string|nil
---@field getMeta fun(): table
---@field affectsRunData fun(): boolean
---@field getStorage fun(): StorageSchema|nil
---@field read fun(alias: string): any
---@field writeAndFlush fun(alias: string, value: any): boolean
---@field stage fun(alias: string, value: any): boolean
---@field flush fun(): boolean
---@field reloadFromConfig fun()
---@field resync fun(): string[]
---@field resetAll fun(opts: table|nil): boolean, number
---@field commitIfDirty fun(): boolean, string|nil, boolean
---@field isEnabled fun(): boolean
---@field setEnabled fun(enabled: boolean): boolean, string|nil
---@field setDebugMode fun(enabled: boolean)
---@field applyMutation fun(): boolean, string|nil
---@field revertMutation fun(): boolean, string|nil
---@field activate fun(): boolean, string|nil
---@field drawTab fun()
---@field drawQuickContent fun()|nil

function managedModule.getLiveHost(pluginGuid)
    return moduleRegistry.getLiveModule(pluginGuid)
end

local KnownModuleCreateOpts = {
    definition = true,
    pluginGuid = true,
    persistentState = true,
    stagedState = true,
    mutationBundle = true,
    hookDeclarations = true,
    sharedDataDeclarations = true,
    sharedEventRegistrations = true,
    overlayDeclarations = true,
    onActivate = true,
    onCommit = true,
    drawTab = true,
    drawQuickContent = true,
    controlCatalog = true,
}

local function validateKnownOpts(opts, context)
    for key in pairs(opts) do
        if not KnownModuleCreateOpts[key] then
            logging.violate("host.unknown_opt", "%s: unknown option '%s'", context, tostring(key))
        end
    end
end

local function createMutationBundle()
    return {
        patchMutation = nil,
    }
end

local function validateLifecycleObservers(opts)
    if opts.onActivate ~= nil and type(opts.onActivate) ~= "function" then
        logging.violate("host.invalid_create_opts", "managedModule.create: onActivate must be a function")
    end
    if opts.onCommit ~= nil and type(opts.onCommit) ~= "function" then
        logging.violate("host.invalid_create_opts", "managedModule.create: onCommit must be a function")
    end
    return opts.onCommit
end

local function createRuntimeContext(store)
    return {
        data = store,
        cache = store and store.cache or nil,
        shared = store and store.shared or nil,
        controls = store and store.controls or nil,
    }
end

local function rejectPrivateAlias(context, alias)
    if storage.isPrivateAlias(alias) then
        logging.violate(
            "storage.private_alias",
            "%s: private Lib storage alias '%s' is not author-accessible",
            context,
            tostring(alias)
        )
    end
end

local function createActionRuntimeBridge(persistentState)
    local runtimeOwned = persistentState.runtimeOwned
    return {
        read = function(alias, ...)
            rejectPrivateAlias("actions.runtime.read", alias)
            local ref = persistentState.get(alias)
            if ref == nil then
                return nil
            end
            return ref:read(...)
        end,
        runtimeOwned = runtimeOwned and {
            get = function(alias)
                rejectPrivateAlias("actions.runtimeOwned.get", alias)
                return runtimeOwned.get(alias)
            end,
            read = function(alias)
                rejectPrivateAlias("actions.runtimeOwned.read", alias)
                return runtimeOwned.read(alias)
            end,
            set = function(alias, value)
                rejectPrivateAlias("actions.runtimeOwned.set", alias)
                return runtimeOwned.set(alias, value)
            end,
            clear = function(alias)
                rejectPrivateAlias("actions.runtimeOwned.clear", alias)
                return runtimeOwned.clear(alias)
            end,
        } or nil,
    }
end

--- Creates a managed module for Framework and fallback UI.
--- Activation is explicit through the returned module.
---@param opts ManagedModuleCreateOpts
---@return ManagedModule module Managed lifecycle module.
---@return Store store Module runtime store view.
function managedModule.create(opts)
    if type(opts) ~= "table" then
        logging.violate("host.invalid_create_opts", "managedModule.create: opts must be a table")
    end
    validateKnownOpts(opts, "managedModule.create")
    local def = opts.definition
    local pluginGuid = opts.pluginGuid
    local persistentState = opts.persistentState
    local stagedState = opts.stagedState
    if type(def) ~= "table" or def._preparedDefinition ~= true then
        logging.violate("host.invalid_create_opts", "managedModule.create: prepared definition is required")
    end
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        logging.violate("host.invalid_create_opts", "managedModule.create: pluginGuid is required")
    end
    if not (persistentState and type(persistentState.get) == "function" and type(persistentState.read) == "function") then
        logging.violate("host.invalid_create_opts", "managedModule.create: persistentState is required")
    end
    if not (stagedState and type(stagedState.get) == "function" and type(stagedState.isDirty) == "function"
        and type(stagedState.write) == "function" and type(stagedState.getAliasSchema) == "function") then
        logging.violate("host.invalid_create_opts", "managedModule.create: stagedState is required")
    end

    local drawTab = opts.drawTab
    local drawQuickContent = opts.drawQuickContent
    local actionBuffer = moduleState.createActionBuffer({
        actions = def.actions,
        order = def._actionOrder,
    })
    local mutationBundle = opts.mutationBundle or createMutationBundle()
    local commitObserver = validateLifecycleObservers(opts)
    local store
    local runtimeContext
    local actionRuntimeBridge
    local host
    local controlCatalog = opts.controlCatalog or {
        instances = {},
        order = {},
    }

    if type(drawTab) ~= "function" then
        logging.violate("host.invalid_create_opts", "managedModule.create: drawTab is required")
    end
    ---@type ManagedModule
    local module = {}

    local function notifyCommit(commit)
        local observerOk = true
        local observerResult = nil
        if commitObserver ~= nil then
            observerOk, observerResult = pcall(commitObserver, host, runtimeContext, commit)
        end

        local overlayOk, overlayErr = pcall(overlays.dispatchCommit, module, commit)
        if not observerOk then
            if not overlayOk then
                error(tostring(observerResult) .. " (overlay dispatch failed: " .. tostring(overlayErr) .. ")", 0)
            end
            error(observerResult, 0)
        end
        if not overlayOk then
            error(overlayErr, 0)
        end
        return observerResult
    end

    local function requireActivated(methodName)
        local record = moduleRegistry.getRecord(module)
        if not record or record.activated ~= true then
            logging.violate("host.not_activated", "module.%s requires module.activate() before it can run", methodName)
        end
    end

    function module.getHostId()
        return pluginGuid
    end

    function module.getModuleId()
        return def.id
    end

    function module.getPackId()
        return def.modpack
    end

    function module.getMeta()
        return {
            name = def.name,
            shortName = def.shortName,
            tooltip = def.tooltip,
        }
    end

    function module.affectsRunData()
        return mutation.affectsRunData(mutationBundle)
    end

    function module.getStorage()
        return def.storage
    end

    function module.read(alias)
        return persistentState.read(alias)
    end

    function module.writeAndFlush(alias, value)
        requireActivated("writeAndFlush")
        stagedState.write(alias, value)
        local ok, err = moduleLifecycle.commitStagedState(module, def, mutationBundle, notifyCommit, persistentState,
            stagedState, actionBuffer)
        return ok, err
    end

    function module.stage(alias, value)
        stagedState.write(alias, value)
        return true
    end

    function module.flush()
        requireActivated("flush")
        if not stagedState.isDirty() and not actionBuffer.hasAny() then
            return true
        end
        return moduleLifecycle.commitStagedState(module, def, mutationBundle, notifyCommit, persistentState, stagedState,
            actionBuffer)
    end

    function module.reloadFromConfig()
        requireActivated("reloadFromConfig")
        stagedState._reloadFromConfig()
        actionBuffer.clearAll()
    end

    function module.resync()
        requireActivated("resync")
        return moduleLifecycle.resyncStagedState(def, stagedState, actionBuffer)
    end

    function module.resetAll(resetOpts)
        requireActivated("resetAll")
        return stagedState.resetAll(resetOpts)
    end

    function module.commitIfDirty()
        requireActivated("commitIfDirty")
        if not stagedState.isDirty() and not actionBuffer.hasAny() then
            return true, nil, false
        end
        local ok, err = moduleLifecycle.commitStagedState(module, def, mutationBundle, notifyCommit, persistentState,
            stagedState, actionBuffer)
        return ok, err, ok == true
    end

    function module.isEnabled()
        return moduleLifecycle.isEnabled(persistentState)
    end

    function module.setEnabled(enabled)
        requireActivated("setEnabled")
        return moduleLifecycle.setEnabled(module, def, mutationBundle, notifyCommit, persistentState, stagedState,
            actionBuffer, enabled)
    end

    function module.setDebugMode(enabled)
        requireActivated("setDebugMode")
        return moduleLifecycle.setDebugMode(module, def, mutationBundle, notifyCommit, persistentState, stagedState,
            actionBuffer, enabled)
    end

    function module.suspendForPackDisable()
        requireActivated("suspendForPackDisable")
        return moduleLifecycle.suspendForPackDisable(module, def, mutationBundle, notifyCommit, persistentState,
            stagedState, actionBuffer)
    end

    function module.ensureSuspendedForPackDisable()
        requireActivated("ensureSuspendedForPackDisable")
        return moduleLifecycle.ensureSuspendedForPackDisable(module, def, mutationBundle, notifyCommit,
            persistentState, stagedState, actionBuffer)
    end

    function module.restoreForPackEnable()
        requireActivated("restoreForPackEnable")
        return moduleLifecycle.restoreForPackEnable(module, def, mutationBundle, notifyCommit, persistentState,
            stagedState, actionBuffer)
    end

    function module.rollbackPackTransition(receipt)
        requireActivated("rollbackPackTransition")
        return moduleLifecycle.rollbackPackTransition(module, def, mutationBundle, notifyCommit, persistentState,
            stagedState, actionBuffer, receipt)
    end

    function module.restorePackTransitionState(receipt)
        requireActivated("restorePackTransitionState")
        return moduleLifecycle.restorePackTransitionState(stagedState, actionBuffer, receipt)
    end

    local logPrefix = "[" .. tostring(def.id or pluginGuid) .. "] "

    function module.log(fmt, ...)
        logging.printWithPrefix(logPrefix, fmt, ...)
    end

    function module.logIf(fmt, ...)
        logging.printWithPrefixIf(persistentState.read("DebugMode") == true, logPrefix, fmt, ...)
    end

    host = {
        getHostId = module.getHostId,
        getModuleId = module.getModuleId,
        getPackId = module.getPackId,
        getMeta = module.getMeta,
        isEnabled = module.isEnabled,
        log = module.log,
        logIf = module.logIf,
        shared = {
            emit = function(id, eventName, payload)
                return shared.emitForHost(module, id, eventName, payload)
            end,
        },
    }

    function module.applyMutation()
        requireActivated("applyMutation")
        return mutation.applyForHost(module)
    end

    function module.revertMutation()
        requireActivated("revertMutation")
        return mutation.revertForHost(module)
    end

    function module.activate()
        return managedModule.activate(module)
    end

    local record = {
        definition = def,
        mutationBundle = mutationBundle,
        hookDeclarations = opts.hookDeclarations,
        sharedDataDeclarations = opts.sharedDataDeclarations,
        sharedEventRegistrations = opts.sharedEventRegistrations,
        overlayDeclarations = opts.overlayDeclarations,
        pluginGuid = pluginGuid,
        persistentState = persistentState,
        stagedState = stagedState,
        store = nil,
        runtime = nil,
        host = host,
        controlCatalog = controlCatalog,
        onActivate = opts.onActivate,
        actionBuffer = actionBuffer,
        effectReceipts = {},
        fallbackUiRequested = false,
        activated = false,
    }
    moduleRegistry.setRecord(module, record)

    store = moduleState.createStore(persistentState, cache.data.create({
        definition = def,
        ownerId = pluginGuid,
        source = "store.cache",
    }), sharedData.create({
        host = module,
        record = record,
        phase = "runtime",
        source = "store.shared",
    }))
    store.controls = controls.refs.createRuntime(persistentState, controlCatalog)
    runtimeContext = createRuntimeContext(store)
    actionRuntimeBridge = createActionRuntimeBridge(persistentState)
    record.store = store
    record.runtime = runtimeContext

    local uiPhase = uiPhaseModule.create({
        definition = def,
        stagedState = stagedState,
        shared = sharedData.create({
            host = module,
            record = record,
            phase = "draw",
            source = "state.shared",
        }),
        actionBuffer = actionBuffer,
        host = host,
        actionRuntime = actionRuntimeBridge,
        controls = controls.refs.createUi(stagedState, controlCatalog, actionBuffer),
    })

    function module.drawTab()
        requireActivated("drawTab")
        return uiPhase.run(drawTab)
    end

    if type(drawQuickContent) == "function" then
        function module.drawQuickContent()
            requireActivated("drawQuickContent")
            return uiPhase.run(drawQuickContent)
        end
    end

    return module, store
end

--- Activates a constructed module by registering external side effects.
---@param module ManagedModule
function managedModule.activateOrThrow(module)
    return moduleActivation.activateOrThrow(module)
end

--- Safely activates a constructed module by registering external side effects.
--- Returns false plus the activation error instead of throwing.
---@param module ManagedModule
---@return boolean ok
---@return string|nil err
function managedModule.activate(module)
    return moduleActivation.activate(module)
end

return managedModule
