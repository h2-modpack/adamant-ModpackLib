local deps = ...

local logging = deps.logging
local cache = deps.cache
local sharedData = deps.sharedData
local moduleState = deps.moduleState
local overlays = deps.overlays
local mutation = deps.mutation
local definition = deps.definition
local hostRegistry = deps.hostRegistry
local uiDraw = deps.uiDraw
local authorHostService = deps.authorHost
local moduleHost = {
    prepareDefinition = definition.prepareDefinition,
}
local phaseGate = deps.phaseGate
local uiPhaseModule = import('core/module_bootstrap/ui/phase.lua', nil, {
    uiDraw = uiDraw,
    moduleState = moduleState,
    phaseGate = phaseGate,
})
local hostLifecycle = import('core/module_bootstrap/host_lifecycle.lua', nil, {
    logging = logging,
    mutation = mutation,
    moduleState = moduleState,
})
local hostActivation = import('core/module_bootstrap/host_activation.lua', nil, {
    logging = logging,
    shared = deps.shared,
    hooks = deps.hooks,
    overlays = overlays,
    mutation = mutation,
    fallbackUi = deps.fallbackUi,
    coordinator = deps.coordinator,
    hostRegistry = hostRegistry,
})

function moduleHost.getRecord(host)
    return hostRegistry.getRecord(host)
end

function moduleHost.addEffectReceipt(host, name, receipt)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("host.invalid_activate_opts", "moduleHost.addEffectReceipt: host is required")
    end
    if record.activated ~= true then
        logging.violate("host.not_activated", "moduleHost.addEffectReceipt requires an activated host")
    end
    if type(name) ~= "string" or name == "" then
        logging.violate("host.invalid_activate_opts", "moduleHost.addEffectReceipt: receipt name is required")
    end
    if type(receipt) ~= "table" or type(receipt.dispose) ~= "function" then
        logging.violate("host.invalid_activate_opts", "moduleHost.addEffectReceipt: receipt dispose function is required")
    end

    record.effectReceipts = record.effectReceipts or {}
    record.effectReceipts[#record.effectReceipts + 1] = {
        name = name,
        receipt = receipt,
    }
end

---@class ModuleHostOpts
---@field definition ModuleDefinition
---@field pluginGuid string
---@field persistentState PersistentState
---@field stagedState StagedState
---@field cacheStore PersistentCacheStore|nil
---@field onSettingsCommitted fun(host: AuthorHost, store: Store, commit: table)|nil
---@field drawTab fun(draw: DrawContext, state: DrawState, actions: DrawActions)
---@field drawQuickContent fun(draw: DrawContext, state: DrawState, actions: DrawActions)|nil

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

---@class ModuleHost
---@field getHostId fun(): string
---@field getModuleId fun(): string
---@field getPackId fun(): string|nil
---@field getMeta fun(): table
---@field affectsRunData fun(): boolean
---@field getHashHints fun(): table|nil
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

function moduleHost.getLiveHost(pluginGuid)
    return hostRegistry.getLiveHost(pluginGuid)
end

local KnownHostOpts = {
    definition = true,
    pluginGuid = true,
    persistentState = true,
    stagedState = true,
    cacheStore = true,
    onSettingsCommitted = true,
    drawTab = true,
    drawQuickContent = true,
}

local function ValidateKnownOpts(opts, context)
    for key in pairs(opts) do
        if not KnownHostOpts[key] then
            logging.violate("host.unknown_opt", "%s: unknown option '%s'", context, tostring(key))
        end
    end
end

local function CreateMutationBundle()
    return {
        patchMutation = nil,
    }
end

local function ValidateSettingsObserver(opts)
    if opts.onSettingsCommitted ~= nil and type(opts.onSettingsCommitted) ~= "function" then
        logging.violate("host.invalid_create_opts", "moduleHost.create: onSettingsCommitted must be a function")
    end
    return opts.onSettingsCommitted
end

--- Creates full and author-facing host objects for Framework and fallback UI.
--- Activation is explicit through the returned author host.
---@param opts ModuleHostOpts
---@return ModuleHost host Full module host.
---@return AuthorHost authorHost Module author host view.
---@return Store store Module author store view.
function moduleHost.create(opts)
    if type(opts) ~= "table" then
        logging.violate("host.invalid_create_opts", "moduleHost.create: opts must be a table")
    end
    ValidateKnownOpts(opts, "moduleHost.create")
    local def = opts.definition
    local pluginGuid = opts.pluginGuid
    local persistentState = opts.persistentState
    local stagedState = opts.stagedState
    local cacheStore = opts.cacheStore
    if type(def) ~= "table" or def._preparedDefinition ~= true then
        logging.violate("host.invalid_create_opts", "moduleHost.create: prepared definition is required")
    end
    if type(pluginGuid) ~= "string" or pluginGuid == "" then
        logging.violate("host.invalid_create_opts", "moduleHost.create: pluginGuid is required")
    end
    if not (persistentState and type(persistentState.get) == "function" and type(persistentState.read) == "function") then
        logging.violate("host.invalid_create_opts", "moduleHost.create: persistentState is required")
    end
    if not (stagedState and type(stagedState.get) == "function" and type(stagedState.isDirty) == "function"
        and type(stagedState.write) == "function" and type(stagedState.getAliasSchema) == "function") then
        logging.violate("host.invalid_create_opts", "moduleHost.create: stagedState is required")
    end

    local drawTab = opts.drawTab
    local drawQuickContent = opts.drawQuickContent
    local actionBuffer = moduleState.createActionBuffer({
        actions = def.actions,
        order = def._actionOrder,
    })
    local mutationBundle = CreateMutationBundle()
    local settingsObserver = ValidateSettingsObserver(opts)
    local store

    if type(drawTab) ~= "function" then
        logging.violate("host.invalid_create_opts", "moduleHost.create: drawTab is required")
    end
    ---@type ModuleHost
    local host = {}
    ---@type AuthorHost
    local authorHost

    local function notifySettingsCommitted(commit)
        local observerOk = true
        local observerResult = nil
        if settingsObserver ~= nil then
            observerOk, observerResult = pcall(settingsObserver, authorHost, store, commit)
        end

        local overlayOk, overlayErr = pcall(overlays.dispatchCommit, host, commit)
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
        local record = hostRegistry.getRecord(host)
        if not record or record.activated ~= true then
            logging.violate("host.not_activated", "host.%s requires host.activate() before it can run", methodName)
        end
    end

    function host.getHostId()
        return pluginGuid
    end

    function host.getModuleId()
        return def.id
    end

    function host.getPackId()
        return def.modpack
    end

    function host.getMeta()
        return {
            name = def.name,
            shortName = def.shortName,
            tooltip = def.tooltip,
        }
    end

    function host.affectsRunData()
        return mutation.affectsRunData(mutationBundle)
    end

    function host.getHashHints()
        return def.hashGroupPlan
    end

    function host.getStorage()
        return def.storage
    end

    function host.read(alias)
        return persistentState.read(alias)
    end

    function host.writeAndFlush(alias, value)
        requireActivated("writeAndFlush")
        stagedState.write(alias, value)
        local ok, err = hostLifecycle.commitStagedState(host, def, mutationBundle, notifySettingsCommitted, persistentState,
            stagedState, actionBuffer)
        return ok, err
    end

    function host.stage(alias, value)
        stagedState.write(alias, value)
        return true
    end

    function host.flush()
        requireActivated("flush")
        if not stagedState.isDirty() and not actionBuffer.hasAny() then
            return true
        end
        return hostLifecycle.commitStagedState(host, def, mutationBundle, notifySettingsCommitted, persistentState, stagedState,
            actionBuffer)
    end

    function host.reloadFromConfig()
        requireActivated("reloadFromConfig")
        stagedState._reloadFromConfig()
        actionBuffer.clearAll()
    end

    function host.resync()
        requireActivated("resync")
        return hostLifecycle.resyncStagedState(def, stagedState, actionBuffer)
    end

    function host.resetAll(resetOpts)
        requireActivated("resetAll")
        return stagedState.resetAll(resetOpts)
    end

    function host.commitIfDirty()
        requireActivated("commitIfDirty")
        if not stagedState.isDirty() and not actionBuffer.hasAny() then
            return true, nil, false
        end
        local ok, err = hostLifecycle.commitStagedState(host, def, mutationBundle, notifySettingsCommitted, persistentState,
            stagedState, actionBuffer)
        return ok, err, ok == true
    end

    function host.isEnabled()
        return hostLifecycle.isEnabled(persistentState)
    end

    function host.setEnabled(enabled)
        requireActivated("setEnabled")
        return hostLifecycle.setEnabled(host, def, mutationBundle, notifySettingsCommitted, persistentState, stagedState,
            actionBuffer, enabled)
    end

    function host.setDebugMode(enabled)
        requireActivated("setDebugMode")
        return hostLifecycle.setDebugMode(host, def, mutationBundle, notifySettingsCommitted, persistentState, stagedState,
            actionBuffer, enabled)
    end

    function host.suspendForPackDisable()
        requireActivated("suspendForPackDisable")
        return hostLifecycle.suspendForPackDisable(host, def, mutationBundle, notifySettingsCommitted, persistentState,
            stagedState, actionBuffer)
    end

    function host.ensureSuspendedForPackDisable()
        requireActivated("ensureSuspendedForPackDisable")
        return hostLifecycle.ensureSuspendedForPackDisable(host, def, mutationBundle, notifySettingsCommitted,
            persistentState, stagedState, actionBuffer)
    end

    function host.restoreForPackEnable()
        requireActivated("restoreForPackEnable")
        return hostLifecycle.restoreForPackEnable(host, def, mutationBundle, notifySettingsCommitted, persistentState,
            stagedState, actionBuffer)
    end

    function host.rollbackPackTransition(receipt)
        requireActivated("rollbackPackTransition")
        return hostLifecycle.rollbackPackTransition(host, def, mutationBundle, notifySettingsCommitted, persistentState,
            stagedState, actionBuffer, receipt)
    end

    function host.restorePackTransitionState(receipt)
        requireActivated("restorePackTransitionState")
        return hostLifecycle.restorePackTransitionState(stagedState, actionBuffer, receipt)
    end

    local logPrefix = "[" .. tostring(def.id or pluginGuid) .. "] "

    function host.log(fmt, ...)
        logging.printWithPrefix(logPrefix, fmt, ...)
    end

    function host.logIf(fmt, ...)
        logging.printWithPrefixIf(persistentState.read("DebugMode") == true, logPrefix, fmt, ...)
    end

    function host.applyMutation()
        requireActivated("applyMutation")
        return mutation.applyForHost(host)
    end

    function host.revertMutation()
        requireActivated("revertMutation")
        return mutation.revertForHost(host)
    end

    function host.activate()
        return moduleHost.activate(host)
    end

    local record = {
        definition = def,
        mutationBundle = mutationBundle,
        pluginGuid = pluginGuid,
        persistentState = persistentState,
        stagedState = stagedState,
        store = nil,
        actionBuffer = actionBuffer,
        cacheStore = cacheStore,
        persistentCacheRefs = {},
        authorHost = nil,
        effectReceipts = {},
        fallbackUiRequested = false,
        activated = false,
    }
    hostRegistry.setRecord(host, record)

    store = moduleState.createStore(persistentState, cache.data.create({
        definition = def,
        host = host,
        record = record,
        ownerId = pluginGuid,
        cacheStore = cacheStore,
        persistentRefs = record.persistentCacheRefs,
        phase = "runtime",
        source = "store.cache",
    }), sharedData.create({
        host = host,
        record = record,
        phase = "runtime",
        source = "store.shared",
    }))
    record.store = store

    authorHost = authorHostService.create(host)
    record.authorHost = authorHost
    local uiPhase = uiPhaseModule.create({
        definition = def,
        stagedState = stagedState,
        cache = cache.data.create({
            definition = def,
            host = host,
            record = record,
            ownerId = pluginGuid,
            cacheStore = cacheStore,
            persistentRefs = record.persistentCacheRefs,
            phase = "draw",
            source = "state.cache",
        }),
        shared = sharedData.create({
            host = host,
            record = record,
            phase = "draw",
            source = "state.shared",
        }),
        actionBuffer = actionBuffer,
        authorHost = authorHost,
        logPrefix = logPrefix,
        isDebugEnabled = function()
            return persistentState.read("DebugMode") == true
        end,
    })

    function host.drawTab()
        requireActivated("drawTab")
        return uiPhase.run(drawTab)
    end

    if type(drawQuickContent) == "function" then
        function host.drawQuickContent()
            requireActivated("drawQuickContent")
            return uiPhase.run(drawQuickContent)
        end
    end

    return host, authorHost, store
end

--- Activates a constructed module host by registering external side effects.
---@param host ModuleHost
---@return AuthorHost host Module author host view.
function moduleHost.activateOrThrow(host)
    return hostActivation.activateOrThrow(host)
end

--- Safely activates a constructed module host by registering external side effects.
--- Returns false plus the activation error instead of throwing.
---@param host ModuleHost
---@return boolean ok
---@return string|nil err
function moduleHost.activate(host)
    return hostActivation.activate(host)
end

return moduleHost
