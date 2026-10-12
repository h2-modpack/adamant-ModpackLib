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
local uiDraw = deps.uiDraw
local controls = deps.controls
local managedModule = {
    prepareDefinition = definition.prepareDefinition,
    prepareDefinitionWithInternalStorage = definition.prepareDefinitionWithInternalStorage,
    prepareDefinitionWithInternalDeclarations = definition.prepareDefinitionWithInternalDeclarations,
}
local ReloadReasons = {
    manual = true,
    frameworkSnapshot = true,
    hashReload = true,
    driftRepair = true,
}
local uiContextModule = import('core/module_bootstrap/ui/context.lua', nil, {
    uiDraw = uiDraw,
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

function managedModule.getLiveModule(pluginGuid)
    return moduleRegistry.getLiveModule(pluginGuid)
end

local KnownModuleCreateOpts = {
    definition = true,
    pluginGuid = true,
    state = true,
    mutationBundle = true,
    hookDeclarations = true,
    sharedDataDeclarations = true,
    sharedEventRegistrations = true,
    overlayDeclarations = true,
    onActivate = true,
    onCommit = true,
    onReload = true,
    drawTab = true,
    drawQuickContent = true,
    controlCatalog = true,
}

local function validateKnownOpts(opts, context)
    for key in pairs(opts) do
        if not KnownModuleCreateOpts[key] then
            logging.violate("module.unknown_opt", "%s: unknown option '%s'", context, tostring(key))
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
        logging.violate("module.invalid_create_opts", "managedModule.create: onActivate must be a function")
    end
    if opts.onCommit ~= nil and type(opts.onCommit) ~= "function" then
        logging.violate("module.invalid_create_opts", "managedModule.create: onCommit must be a function")
    end
    if opts.onReload ~= nil and type(opts.onReload) ~= "function" then
        logging.violate("module.invalid_create_opts", "managedModule.create: onReload must be a function")
    end
    return opts.onCommit, opts.onReload
end

local function createRuntimeContext(store, status)
    return {
        data = store,
        status = status,
        cache = store and store.cache or nil,
        shared = store and store.shared or nil,
        controls = store and store.controls or nil,
    }
end

function managedModule.create(opts)
    if type(opts) ~= "table" then
        logging.violate("module.invalid_create_opts", "managedModule.create: opts must be a table")
    end
    validateKnownOpts(opts, "managedModule.create")
    local def = opts.definition
    local pluginGuid = opts.pluginGuid
    local state = opts.state
    if type(def) ~= "table" or def._preparedDefinition ~= true then
        logging.violate("module.invalid_create_opts", "managedModule.create: prepared definition is required")
    end
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        logging.violate("module.invalid_create_opts", "managedModule.create: pluginGuid is required")
    end
    if type(state) ~= "table" or type(state.txn) ~= "table" then
        logging.violate("module.invalid_create_opts", "managedModule.create: module state is required")
    end
    local persistentState = state.persistent
    local stagedState = state.staged
    local txn = state.txn
    local lanes = state.lanes

    local drawTab = opts.drawTab
    local drawQuickContent = opts.drawQuickContent
    local actionBuffer = state.actionBuffer
    local mutationBundle = opts.mutationBundle or createMutationBundle()
    local commitObserver, reloadObserver = validateLifecycleObservers(opts)
    local store
    local runtimeContext
    local host
    local controlCatalog = opts.controlCatalog or {
        instances = {},
        order = {},
    }

    if type(drawTab) ~= "function" then
        logging.violate("module.invalid_create_opts", "managedModule.create: drawTab is required")
    end
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

    local function reloadContext(reason, receipt)
        receipt = receipt or {}
        return {
            reason = function()
                return reason
            end,
            hadCommittedChanges = function()
                return receipt.hadCommittedChanges == true
            end,
            hadSettingChanges = function()
                return receipt.hadSettingChanges == true
            end,
            hadStatusChanges = function()
                return receipt.hadStatusChanges == true
            end,
        }
    end

    local function notifyReload(reason, receipt)
        local context = reloadContext(reason, receipt)
        if reloadObserver == nil then
            return context
        end
        local ok, result = pcall(reloadObserver, host, runtimeContext, context)
        if not ok then
            logging.violate("lifecycle.on_reload_failed", "%s: onReload failed: %s",
                tostring(def.name or def.id or "module"), tostring(result))
        elseif result == false then
            logging.violate("lifecycle.on_reload_false", "%s: onReload returned false",
                tostring(def.name or def.id or "module"))
        end
        return context
    end

    local function normalizeReloadReason(reason)
        reason = reason or "manual"
        if ReloadReasons[reason] ~= true then
            logging.violate(
                "lifecycle.invalid_reload_reason",
                "module.reloadFromConfig: unknown reason '%s'",
                tostring(reason)
            )
        end
        return reason
    end

    local function executeActionsDuringCommit(actionSnapshot)
        return actionBuffer.executeCommittedActions(host, runtimeContext, actionSnapshot)
    end

    local function emitSharedEvent(id, eventName, payload)
        return shared.emitForModule(module, id, eventName, payload)
    end

    local function flushSharedEventsDuringCommit()
        return actionBuffer.flushPendingSharedEvents(emitSharedEvent)
    end

    local function requireActivated(methodName)
        local record = moduleRegistry.getRecord(module)
        if not record or record.activated ~= true then
            logging.violate("managed_module.not_activated", "module.%s requires module.activate() before it can run", methodName)
        end
    end

    function module.getOwnerId()
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
            hash = def.hash,
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
        local ok, err = moduleLifecycle.commitStagedState(module, def, mutationBundle, notifyCommit, txn,
            executeActionsDuringCommit, flushSharedEventsDuringCommit)
        return ok, err
    end

    function module.stage(alias, value)
        stagedState.write(alias, value)
        return true
    end

    function module.flush()
        requireActivated("flush")
        if not txn.hasPending() then
            return true
        end
        return moduleLifecycle.commitStagedState(module, def, mutationBundle, notifyCommit, txn,
            executeActionsDuringCommit, flushSharedEventsDuringCommit)
    end

    function module.reloadFromConfig(reason)
        requireActivated("reloadFromConfig")
        reason = normalizeReloadReason(reason)
        return notifyReload(reason, txn.reload())
    end

    function module.resync()
        requireActivated("resync")
        local mismatches, receipt = moduleLifecycle.resyncStagedState(def, txn)
        if receipt ~= nil then
            return mismatches, notifyReload("driftRepair", receipt)
        end
        return mismatches, nil
    end

    function module.resetAll(resetOpts)
        requireActivated("resetAll")
        return txn.queueResetAll(resetOpts)
    end

    function module.commitIfDirty()
        requireActivated("commitIfDirty")
        if not txn.hasPending() then
            return true, nil, false
        end
        local ok, err = moduleLifecycle.commitStagedState(module, def, mutationBundle, notifyCommit, txn,
            executeActionsDuringCommit, flushSharedEventsDuringCommit)
        return ok, err, ok == true
    end

    function module.isEnabled()
        return persistentState.read("Enabled") == true
    end

    function module.setEnabled(enabled)
        requireActivated("setEnabled")
        return moduleLifecycle.setEnabled(module, def, mutationBundle, notifyCommit, txn,
            executeActionsDuringCommit, flushSharedEventsDuringCommit, enabled)
    end

    function module.setDebugMode(enabled)
        requireActivated("setDebugMode")
        return moduleLifecycle.setDebugMode(module, def, mutationBundle, notifyCommit, txn,
            executeActionsDuringCommit, flushSharedEventsDuringCommit, enabled)
    end

    function module.suspendForPackDisable()
        requireActivated("suspendForPackDisable")
        return moduleLifecycle.suspendForPackDisable(module, def, mutationBundle, notifyCommit, txn,
            executeActionsDuringCommit, flushSharedEventsDuringCommit)
    end

    function module.ensureSuspendedForPackDisable()
        requireActivated("ensureSuspendedForPackDisable")
        return moduleLifecycle.ensureSuspendedForPackDisable(module, def, mutationBundle, notifyCommit, txn,
            executeActionsDuringCommit, flushSharedEventsDuringCommit)
    end

    function module.restoreForPackEnable()
        requireActivated("restoreForPackEnable")
        return moduleLifecycle.restoreForPackEnable(module, def, mutationBundle, notifyCommit, txn,
            executeActionsDuringCommit, flushSharedEventsDuringCommit)
    end

    function module.rollbackPackTransition(receipt)
        requireActivated("rollbackPackTransition")
        return moduleLifecycle.rollbackPackTransition(module, def, mutationBundle, notifyCommit, txn,
            executeActionsDuringCommit, flushSharedEventsDuringCommit, receipt)
    end

    function module.restorePackTransitionState(receipt)
        requireActivated("restorePackTransitionState")
        return moduleLifecycle.restorePackTransitionState(txn, receipt)
    end

    local logPrefix = "[" .. tostring(def.id or pluginGuid) .. "] "

    function module.log(fmt, ...)
        logging.printWithPrefix(logPrefix, fmt, ...)
    end

    function module.logIf(fmt, ...)
        logging.printWithPrefixIf(persistentState.read("DebugMode") == true, logPrefix, fmt, ...)
    end

    host = {
        getOwnerId = module.getOwnerId,
        getModuleId = module.getModuleId,
        getPackId = module.getPackId,
        getMeta = module.getMeta,
        isEnabled = module.isEnabled,
        log = module.log,
        logIf = module.logIf,
    }

    function module.applyMutation()
        requireActivated("applyMutation")
        return mutation.applyForModule(module)
    end

    function module.revertMutation()
        requireActivated("revertMutation")
        return mutation.revertForModule(module)
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
        state = state,
        store = nil,
        runtime = nil,
        host = host,
        controlCatalog = controlCatalog,
        onActivate = opts.onActivate,
        effectReceipts = {},
        fallbackUiRequested = false,
        activated = false,
    }
    moduleRegistry.setRecord(module, record)

    store = lanes.runtimeData
    store.cache = cache.data.create({
        definition = def,
        ownerId = pluginGuid,
        source = "store.cache",
    })
    store.shared = sharedData.create({
        host = module,
        record = record,
        lane = "runtime",
        source = "store.shared",
    })
    store.controls = controls.refs.createRuntime(persistentState, controlCatalog)
    runtimeContext = createRuntimeContext(store, lanes.runtimeStatus)
    record.store = store
    record.runtime = runtimeContext

    local uiShared = sharedData.create({
        host = module,
        record = record,
        lane = "ui",
        source = "state.shared",
        actionBuffer = actionBuffer,
    })
    lanes.uiData.shared = uiShared
    local uiContext = uiContextModule.create({
        lanes = lanes,
        shared = uiShared,
        host = host,
        controls = controls.refs.createUi(stagedState, controlCatalog),
        resetAll = txn.queueResetAll,
    })

    local function runDrawLifecycle(drawCallback)
        uiContext.run(drawCallback)
        return module.commitIfDirty()
    end

    function module.drawTab()
        requireActivated("drawTab")
        return uiContext.run(drawTab)
    end

    function module.drawTabAndCommit()
        requireActivated("drawTabAndCommit")
        return runDrawLifecycle(drawTab)
    end

    if type(drawQuickContent) == "function" then
        function module.drawQuickContent()
            requireActivated("drawQuickContent")
            return uiContext.run(drawQuickContent)
        end

        function module.drawQuickContentAndCommit()
            requireActivated("drawQuickContentAndCommit")
            return runDrawLifecycle(drawQuickContent)
        end
    end

    return module, store
end

function managedModule.activateOrThrow(module)
    return moduleActivation.activateOrThrow(module)
end

function managedModule.activate(module)
    return moduleActivation.activate(module)
end

return managedModule
