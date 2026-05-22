local deps = ...

local logging = deps.logging
local moduleState = deps.moduleState
local integrations = deps.integrations
local hooks = deps.hooks
local overlays = deps.overlays
local mutation = deps.mutation
local fallbackUi = deps.fallbackUi
local coordinator = deps.coordinator
local definition = deps.definition
local hostRegistry = deps.hostRegistry
local uiDraw = deps.uiDraw
local authorHostService = deps.authorHost
local moduleHost = {
    prepareDefinition = definition.prepareDefinition,
}
local uiHost = import('core/module_bootstrap/ui/ui_host.lua')
local uiPhaseModule = import('core/module_bootstrap/ui/phase.lua', nil, {
    uiDraw = uiDraw,
    moduleState = moduleState,
    uiHost = uiHost,
})
local hostLifecycle = import('core/module_bootstrap/host_lifecycle.lua', nil, {
    logging = logging,
    mutation = mutation,
    moduleState = moduleState,
    coordinator = coordinator,
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
---@field drawTab fun(draw: DrawContext, state: DrawState, actions: DrawActions, services: DrawServices)
---@field drawQuickContent fun(draw: DrawContext, state: DrawState, actions: DrawActions, services: DrawServices)|nil

---@class DrawContext
---@field imgui table
---@field widgets DrawWidgets
---@field nav DrawNav

---@class DrawActions
---@field get fun(actionKey: string): DrawActionRef
---@field hasAny fun(): boolean

---@class DrawActionRef
---@field stage fun(self: DrawActionRef, value: any)
---@field read fun(self: DrawActionRef): any
---@field clear fun(self: DrawActionRef)
---@field has fun(self: DrawActionRef): boolean

---@class DrawServices
---@field log fun(fmt: string, ...): nil
---@field logIf fun(fmt: string, ...): nil
---@field isHostEnabled fun(): boolean
---@field invokeIntegration fun(id: string, methodName: string, fallback: any, ...): any, string|nil

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

local function CreatePluginInfo(pluginGuid, def)
    return {
        pluginGuid = pluginGuid,
        packId = def.modpack,
        moduleId = def.id,
        name = def.name,
    }
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
    local actionBuffer = moduleState.createActionBuffer()
    local mutationBundle = CreateMutationBundle()
    local settingsObserver = ValidateSettingsObserver(opts)
    local store = moduleState.createStore(persistentState)

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
        return hostLifecycle.isEnabled(persistentState, def.modpack)
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

    local logPrefix = "[" .. tostring(def.id or pluginGuid) .. "] "

    function host.log(fmt, ...)
        print(logging.formatLogMessage(logPrefix, fmt, ...))
    end

    function host.logIf(fmt, ...)
        if persistentState.read("DebugMode") == true then
            host.log(fmt, ...)
        end
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

    authorHost = authorHostService.create(host)
    local uiPhase = uiPhaseModule.create({
        definition = def,
        stagedState = stagedState,
        actionBuffer = actionBuffer,
        authorHost = authorHost,
    })

    function host.drawTab()
        requireActivated("drawTab")
        return drawTab(uiPhase.draw, uiPhase.state, uiPhase.actions, uiPhase.services)
    end

    if type(drawQuickContent) == "function" then
        function host.drawQuickContent()
            requireActivated("drawQuickContent")
            return drawQuickContent(uiPhase.draw, uiPhase.state, uiPhase.actions, uiPhase.services)
        end
    end

    hostRegistry.setRecord(host, {
        definition = def,
        mutationBundle = mutationBundle,
        pluginGuid = pluginGuid,
        persistentState = persistentState,
        store = store,
        actionBuffer = actionBuffer,
        cacheStore = cacheStore,
        authorHost = authorHost,
        effectReceipts = {},
        fallbackUiRequested = false,
        activated = false,
    })

    return host, authorHost, store
end

local function callReceipt(receipt, methodName)
    if not (receipt and type(receipt[methodName]) == "function") then
        return true, nil
    end

    local ok, result, err = pcall(receipt[methodName])
    if not ok then
        return false, result
    end
    if result == false then
        return false, err
    end
    return true, nil
end

local function warnReceiptDisposal(warningId, warningPrefix, errors)
    if warningId == "host.retire_failed" then
        logging.violate("host.retire_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
    elseif warningId == "host.activation_rollback_failed" then
        logging.violate("host.activation_rollback_failed", "%s: %s", warningPrefix, table.concat(errors, "; "))
    end
end

local function disposeReceipts(receipts, warningId, warningPrefix)
    local errors = {}
    for index = #receipts, 1, -1 do
        local entry = receipts[index]
        local ok, err = callReceipt(entry.receipt, "dispose")
        if not ok then
            errors[#errors + 1] = tostring(entry.name or "receipt") .. ": " .. tostring(err)
        end
    end
    if #errors > 0 then
        warnReceiptDisposal(warningId, warningPrefix, errors)
    end
    return errors
end

local function commitReceipt(entry)
    local ok, err = callReceipt(entry.receipt, "commit")
    if not ok then
        return false, tostring(entry.name or "receipt") .. " commit failed: " .. tostring(err)
    end
    return true, nil
end

local function retireOldHost(previousHost, replacementLabel)
    local oldRecord = hostRegistry.getRecord(previousHost)
    local receipts = oldRecord and oldRecord.effectReceipts or nil
    if type(receipts) ~= "table" or #receipts == 0 then
        return
    end
    disposeReceipts(receipts, "host.retire_failed", tostring(replacementLabel) .. " old host retirement failed")
    oldRecord.effectReceipts = {}
end

--- Activates a constructed module host by registering external side effects.
---@param host ModuleHost
---@return AuthorHost host Module author host view.
function moduleHost.activateOrThrow(host)
    local record = hostRegistry.getRecord(host)
    if not record then
        logging.violate("host.invalid_activate_opts", "moduleHost.activateOrThrow: host is required")
    end

    local pluginGuid = host.getHostId()
    local store = record.store
    local authorHost = record.authorHost
    local def = record.definition

    if record.activated == true then
        logging.violate("host.already_activated", "moduleHost.activateOrThrow: host is already activated")
    end
    if record.activating == true then
        logging.violate("host.activation_in_progress", "moduleHost.activateOrThrow: host activation is already in progress")
    end
    local meta = host.getMeta()
    local moduleId = host.getModuleId()
    local packId = host.getPackId()
    local pendingCoordinatorRebuild = hostRegistry.getPendingCoordinatorRebuild(def)
    local hasPendingCoordinatorRebuild = pendingCoordinatorRebuild ~= nil
    local previousHost = hostRegistry.getLiveHost(pluginGuid)
    local previousPluginInfo = hostRegistry.getPluginInfo(pluginGuid)
    local candidateReceipts = {}
    local retireReceipts = {}
    local published = false
    record.activating = true

    local function addReceipt(name, receipt, retire)
        local entry = {
            name = name,
            receipt = receipt,
        }
        candidateReceipts[#candidateReceipts + 1] = entry
        if retire == true then
            retireReceipts[#retireReceipts + 1] = entry
        end
        return entry
    end

    local ok, err = pcall(function()
        addReceipt("integrations", integrations.installForHost(host), true)
        addReceipt("hooks", hooks.installForHost(host), true)
        addReceipt("overlays", overlays.installForHost(host, authorHost, store), true)

        if not hasPendingCoordinatorRebuild then
            addReceipt("mutation", mutation.syncForHost(host), false)
        elseif hasPendingCoordinatorRebuild then
            local requested = coordinator.requestRebuild(packId, pendingCoordinatorRebuild)
            if requested then
                hostRegistry.setPendingCoordinatorRebuild(def, nil)
            else
                logging.violate(
                    "host.structural_rebuild_unavailable",
                    "%s structural definition changed during hot reload; full reload required",
                    tostring(meta.name or moduleId or "module"))
            end
        end
        if record.fallbackUiRequested == true then
            addReceipt("fallbackUi", fallbackUi.installForHost(host), true)
        end

        for _, entry in ipairs(candidateReceipts) do
            if entry.name == "mutation" then
                local commitOk, commitErr = commitReceipt(entry)
                if not commitOk then
                    error(commitErr, 0)
                end
            end
        end

        for _, entry in ipairs(candidateReceipts) do
            if entry.name ~= "mutation" then
                local commitOk, commitErr = commitReceipt(entry)
                if not commitOk then
                    error(commitErr, 0)
                end
            end
        end

        record.effectReceipts = retireReceipts
        record.activating = false
        record.activated = true
        hostRegistry.setLiveHost(pluginGuid, host)
        hostRegistry.setPluginInfo(pluginGuid, CreatePluginInfo(pluginGuid, def))
        published = true
    end)

    if not ok then
        record.activating = false
        record.activated = false
        disposeReceipts(candidateReceipts, "host.activation_rollback_failed",
            tostring(meta.name or moduleId or "module") .. " activation rollback failed")
        if published then
            hostRegistry.setLiveHost(pluginGuid, previousHost)
            hostRegistry.setPluginInfo(pluginGuid, previousPluginInfo)
        end
        error(err, 0)
    end

    retireOldHost(previousHost, meta.name or moduleId or "module")
    return authorHost
end

--- Safely activates a constructed module host by registering external side effects.
--- Returns false plus the activation error instead of throwing.
---@param host ModuleHost
---@return boolean ok
---@return string|nil err
function moduleHost.activate(host)
    local ok, err = pcall(moduleHost.activateOrThrow, host)
    if ok then
        return true, nil
    end

    err = tostring(err)
    logging.violate("host.activate_failed", "host.activate failed; skipping module: %s", err)
    return false, err
end

return moduleHost
