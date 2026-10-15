local deps = ...

local logging = deps.logging
local shared = deps.shared
local overlays = deps.overlays
local mutation = deps.mutation
local moduleRegistry = deps.moduleRegistry
local moduleActivation = deps.moduleActivation
local managedModule = {}

local moduleIdentity = import('core/module_bootstrap/identity.lua', nil, {
    logging = logging,
})
local moduleLifecycle = import('core/module_bootstrap/managed_module_lifecycle.lua', nil, {
    logging = logging,
    moduleState = deps.moduleState,
})
local moduleContexts = import('core/module_bootstrap/module_contexts.lua', nil, {
    moduleState = deps.moduleState,
    cache = deps.cache,
    sharedRefs = shared.refs,
    controlRefs = deps.controlRefs,
    hotkeys = deps.hotkeys,
    uiContext = import('core/module_bootstrap/ui/context.lua', nil, {
        draw = deps.draw,
    }),
})

local TAB_STATES = {
    attention = true,
    muted = true,
}

---Frame layout read by the shared module frame. Built once per instance; the frame rebuilds its
---labels only when the layout table changes (a reloaded module).
---@param tabs AdamantModpackLib.ModuleTabDeclaration[]?
---@param drawHeader AdamantModpackLib.UiCallback?
---@return AdamantModpackLib.ModuleUiLayout
local function createUiLayout(tabs, drawHeader)
    local layout = {
        hasHeader = drawHeader ~= nil,
        tabs = nil,
    }
    if tabs ~= nil then
        layout.tabs = {}
        for index, tab in ipairs(tabs) do
            layout.tabs[index] = {
                id = tab.id,
                label = tab.label,
                hasState = tab.state ~= nil,
            }
        end
    end
    return layout
end

---Build one managed module instance from Lib-built inputs. The author contact point is
---`lib.createModule(...)` and the declaration facade; this only asserts the prepared-definition
---and drawTab/tabs invariants.
---@param opts AdamantModpackLib.ManagedModuleCreateOpts
---@return AdamantModpackLib.ManagedModule module
---@return { host: AdamantModpackLib.Host, runtime: AdamantModpackLib.RuntimeContext } contexts
function managedModule.create(opts)
    local def = opts.definition
    if type(def) ~= "table" or def._preparedDefinition ~= true then
        logging.violate("module.invalid_create_opts", "managedModule.create: prepared definition is required")
    end
    -- Either one `ui.tab` callback or a declaration-validated `ui.tabs` list; both draw through
    -- the same indexed tab list.
    local tabs = opts.tabs
    if tabs == nil then
        if type(opts.drawTab) ~= "function" then
            logging.violate("module.invalid_create_opts", "managedModule.create: drawTab is required unless tabs are given")
        end
        tabs = { { draw = opts.drawTab } }
    end
    local drawHeader = opts.drawHeader
    local uiLayout = createUiLayout(opts.tabs, drawHeader)
    local drawQuickContent = opts.drawQuickContent
    local pluginGuid = opts.pluginGuid
    local state = opts.state
    local persistentState = state.persistent
    local actionBuffer = state.actionBuffer
    local record

    local module = moduleIdentity.create(def, pluginGuid, function()
        return persistentState.read("DebugMode") == true
    end)

    function module.isEnabled()
        return persistentState.read("Enabled") == true
    end

    function module.getStorage()
        return def.storage
    end

    function module.read(alias)
        return persistentState.read(alias)
    end

    function module.stage(alias, value)
        state.staged.write(alias, value)
        return true
    end

    function module.activate()
        return moduleActivation.activate(module)
    end

    local host = {
        getOwnerId = module.getOwnerId,
        getModuleId = module.getModuleId,
        getPackId = module.getPackId,
        getMeta = module.getMeta,
        isEnabled = module.isEnabled,
        log = module.log,
        logIf = module.logIf,
    }

    -- Runtime-lane emit: immediate delivery, gated on activation and the committed Enabled state.
    local function emitSharedEvent(id, eventName, payload)
        if record.activated ~= true then
            logging.violate("shared.invalid_args", "shared.emit requires module.activate() before it can run")
        end
        if module.isEnabled() ~= true then
            return true, 0
        end
        return shared.events.emit("shared.emit", id, eventName, payload)
    end

    -- UI-lane emit: validated now, staged on the action buffer, delivered by the commit flush.
    local function stageSharedEvent(id, eventName, payload)
        shared.events.validate("state.shared.emit", id, eventName)
        return actionBuffer.emitShared(id, eventName, payload)
    end

    local runtime, uiContext = moduleContexts.create({
        state = state,
        ownerId = pluginGuid,
        cacheDeclarations = def.cache,
        sharedDeclarations = opts.sharedDataDeclarations,
        emitShared = emitSharedEvent,
        stageShared = stageSharedEvent,
        controlCatalog = opts.controlCatalog,
        hotkeyRequests = opts.hotkeyRequests,
        host = host,
    })
    local boundMutation = mutation.bind(pluginGuid, opts.mutationBundle, host, runtime)

    function module.affectsRunData()
        return boundMutation.affectsRunData()
    end

    local lifecycleOps = moduleLifecycle.bind({
        def = def,
        txn = state.txn,
        mutation = boundMutation,
        notifyCommit = moduleLifecycle.createCommitNotifier({
            onCommit = opts.onCommit,
            host = host,
            runtime = runtime,
            dispatchOverlayCommit = function(commit)
                return overlays.dispatchCommit(module, commit)
            end,
        }),
        notifyReload = moduleLifecycle.createReloadNotifier({
            def = def,
            onReload = opts.onReload,
            host = host,
            runtime = runtime,
        }),
        runActions = function(actionSnapshot)
            return actionBuffer.executeCommittedActions(host, runtime, actionSnapshot)
        end,
        flushSharedEvents = function()
            return actionBuffer.flushPendingSharedEvents(emitSharedEvent)
        end,
    })

    -- Activation state plus the explicit slices activation hands each capability install.
    -- Capabilities never read this record.
    record = {
        definition = def,
        pluginGuid = pluginGuid,
        host = host,
        runtime = runtime,
        onActivate = opts.onActivate,
        capabilityInputs = {
            hookDeclarations = opts.hookDeclarations,
            shared = {
                data = opts.sharedDataDeclarations,
                events = opts.sharedEventRegistrations,
            },
            overlays = {
                declarations = opts.overlayDeclarations,
                host = host,
                runtime = runtime,
            },
            mutation = boundMutation,
            fallbackUiRequested = opts.fallbackUiRequested == true,
            hotkeys = {
                requests = opts.hotkeyRequests,
                host = host,
                runtime = runtime,
                readCommitted = persistentState.read,
            },
        },
        effectReceipts = {},
        activated = false,
    }
    moduleRegistry.setRecord(module, record)

    -- Side-effecting module methods are gated on the instance's activation state.
    local function defineActivated(methodName, fn)
        module[methodName] = function(...)
            if record.activated ~= true then
                logging.violate("managed_module.not_activated",
                    "module.%s requires module.activate() before it can run", methodName)
            end
            return fn(...)
        end
    end

    for methodName, fn in pairs(lifecycleOps) do
        defineActivated(methodName, fn)
    end
    defineActivated("applyMutation", boundMutation.apply)
    defineActivated("revertMutation", boundMutation.revert)
    -- Module frame surface: the frame draws the header and the active tab through these, then
    -- commits once per frame through its mode's `commitIfDirty` path.
    function module.getUiLayout()
        return uiLayout
    end
    defineActivated("drawHeader", function()
        if drawHeader ~= nil then
            uiContext.run(drawHeader)
        end
    end)
    defineActivated("drawTab", function(index)
        return uiContext.run(tabs[index or 1].draw)
    end)
    -- Draws the header and the first tab, then commits: a whole-frame draw for callers outside the
    -- module frame (tests and tools drive modules this way).
    defineActivated("drawTabAndCommit", function()
        if drawHeader ~= nil then
            uiContext.run(drawHeader)
        end
        uiContext.run(tabs[1].draw)
        return module.commitIfDirty()
    end)
    defineActivated("readTabState", function(index)
        local stateCallback = tabs[index].state
        if stateCallback == nil then
            return nil
        end
        local tabState = uiContext.run(stateCallback)
        if tabState ~= nil and not TAB_STATES[tabState] then
            logging.violate("module.invalid_tab_state",
                "%s tab '%s' state must be \"attention\", \"muted\" or nil, got '%s'",
                tostring(module.getModuleId()), tostring(tabs[index].id), tostring(tabState))
        end
        return tabState
    end)
    if type(drawQuickContent) == "function" then
        defineActivated("drawQuickContent", function()
            return uiContext.run(drawQuickContent)
        end)
        defineActivated("drawQuickContentAndCommit", function()
            uiContext.run(drawQuickContent)
            return module.commitIfDirty()
        end)
    end

    return module, {
        host = host,
        runtime = runtime,
    }
end

return managedModule
