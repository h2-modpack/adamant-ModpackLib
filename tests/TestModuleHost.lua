local lu = require("luaunit")
local createModuleHostHarness = require("tests/harness/create_module_host_harness")

TestModuleHost = {}

function TestModuleHost:setUp()
    self.h = createModuleHostHarness()
    self.h:captureWarnings()
    self.previousImGui = self.h.rom.ImGui
    self.previousImGuiCond = self.h.rom.ImGuiCond
end

function TestModuleHost:tearDown()
    self.h.rom.ImGui = self.previousImGui
    self.h.rom.ImGuiCond = self.previousImGuiCond
    self.h:restoreWarnings()
end

local function createActivatedHost(h, pluginGuid, opts)
    local function adaptDrawCallback(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(callbackHost, ui)
            return callback(ui.draw, ui.data, ui.actions, ui, callbackHost)
        end
    end

    local function adaptCommitCallback(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(callbackHost, runtime, commit)
            return callback(runtime, callbackHost, commit)
        end
    end

    local function adaptPatchMutation(callback)
        if type(callback) ~= "function" then
            return callback
        end
        return function(callbackHost, runtime, plan)
            return callback(plan, callbackHost, runtime.data, runtime, callbackHost)
        end
    end

    local mutationBundle = {
        patchMutation = adaptPatchMutation(opts.patchMutation),
    }
    local sharedEventRegistrations = h.sharedBundle.registrations.create()
    local host
    local store
    for _, listener in ipairs(opts.sharedListeners or {}) do
        h.sharedBundle.registrations.stageListener(
            sharedEventRegistrations,
            function()
                local record = h.moduleHost.getRecord(host)
                return record and record.host or nil
            end,
            listener.id,
            listener.eventName,
            function(payload)
                local record = h.moduleHost.getRecord(host)
                return listener.callback(record and record.host or nil, record and record.runtime or nil, payload)
            end)
    end
    host, store = h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = opts.definition,
        persistentState = opts.persistentState,
        stagedState = opts.stagedState,
        mutationBundle = mutationBundle,
        sharedEventRegistrations = sharedEventRegistrations,
        onCommit = adaptCommitCallback(opts.onCommit),
        drawTab = adaptDrawCallback(opts.drawTab),
        drawQuickContent = adaptDrawCallback(opts.drawQuickContent),
    })
    if type(opts.beforeActivate) == "function" then
        opts.beforeActivate(host, store)
    end
    host.activate()
    return host, host, store
end

local function createSimpleActivatedHost(h, pluginGuid, id)
    local definition = h.moduleHost.prepareDefinition({}, {
        id = id or pluginGuid,
        name = id or pluginGuid,
        storage = {},
    })
    local store, stagedState = h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    return createActivatedHost(h, pluginGuid, {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })
end

local function emitShared(h, module, id, eventName, payload)
    local record = h.moduleHost.getRecord(module)
    return record.host.shared.emit(id, eventName, payload)
end

function TestModuleHost:testFallbackUiWarnsWhenStagedStateCommitFails()
    local drawCalls = 0
    local pluginGuid = "test-fallback-ui-commit"
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = "fallback-pack",
        id = "FallbackUiTest",
        name = "Fallback UI Test",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)

    local function noop() end

    self.h.rom.ImGuiCond = { FirstUseEver = 1 }
    self.h.rom.ImGui = {
        BeginMenu = function() return true end,
        MenuItem = function() return true end,
        EndMenu = noop,
        SetNextWindowSize = noop,
        Begin = function() return true, true end,
        End = noop,
        Checkbox = function(_, current) return current, false end,
        Button = function() return false end,
        Separator = noop,
        Spacing = noop,
    }

    createActivatedHost(self.h, pluginGuid, {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        beforeActivate = function(module)
            self.h.fallbackUiBundle.service.attachGuiOnce(module, function() end)
        end,
        drawTab = function()
            drawCalls = drawCalls + 1
        end,
    })
    local moduleHost = self.h.moduleHost.getLiveModule(pluginGuid)
    moduleHost.commitIfDirty = function()
        return false, "commit boom", false
    end

    local runtime = self.h.registry.fallback.runtimes[pluginGuid]
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(drawCalls, 1)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "Fallback UI Test staged state commit failed")
    lu.assertStrContains(self.h.warnings[1], "commit boom")
    lu.assertEquals(self.h.moduleHost.getLiveModule(pluginGuid), moduleHost)
end

function TestModuleHost:testFallbackUiInstallsDuringActivation()
    local pluginGuid = "test-fallback-ui-activation"
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "FallbackUiRegistryHost",
        name = "Fallback UI Registry Host",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local attached = nil
    createActivatedHost(self.h, pluginGuid, {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        beforeActivate = function(module)
            attached = self.h.fallbackUiBundle.service.attachGuiOnce(module, function() end)
        end,
        drawTab = function() end,
    })
    local host = self.h.moduleHost.getLiveModule(pluginGuid)

    local runtime = self.h.registry.fallback.runtimes[pluginGuid]

    lu.assertTrue(attached)
    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(self.h.moduleHost.getLiveModule(pluginGuid), host)
end

function TestModuleHost:testFlushNotifiesSettingsObserver()
    local calls = 0
    local observedValue = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "SettingsObserverHost",
        name = "Settings Observer Host",
        storage = {
            { type = "bool", alias = "Value", default = false },
        },
    })
    local store, stagedState = self.h:createModuleState({
        Value = false,
    }, definition)
    createActivatedHost(self.h, "test-settings-observer-host", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        onCommit = function(runtime)
            calls = calls + 1
            observedValue = runtime.data.read("Value")
        end,
        drawTab = function() end,
    })
    local host = self.h.moduleHost.getLiveModule("test-settings-observer-host")

    host.stage("Value", true)
    local ok, err = host.flush()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
end

function TestModuleHost:testPatchMutationReceivesCallbackHostAndRuntimeData()
    local target = { Value = false }
    local patchHost = nil
    local patchStore = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "PatchHostModule",
        name = "Patch Host Module",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = createActivatedHost(self.h, "test-patch-host", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        patchMutation = function(plan, activeHost, activeStore)
            patchHost = activeHost
            patchStore = activeStore
            plan:set(target, "Value", true)
        end,
        drawTab = function() end,
    })
    local ok, err = host.applyMutation()

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(patchHost, self.h.moduleHost.getRecord(host).host)
    lu.assertEquals(patchStore, self.h.moduleHost.getRecord(host).store)
    lu.assertNotEquals(patchStore, store)
    lu.assertTrue(target.Value)
end

function TestModuleHost:testSideEffectingHostMethodsRequireActivation()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "InactiveHost",
        name = "Inactive Host",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({}, definition)
    local host = self.h.moduleHost.create({
        pluginGuid = "test-inactive-host",
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("managed_module.not_activated", function()
        host.flush()
    end)
end

function TestModuleHost:testHostAndUiStateResetAllDelegateToStagedState()
    local capturedState = nil
    local doAuthorReset = false
    local authorChanged = nil
    local authorCount = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "ResetHost",
        name = "Reset Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "int", alias = "Count", default = 2, min = 0, max = 9 },
        },
    })
    local store, stagedState = self.h:createModuleState({
        EnabledFlag = true,
        Count = 7,
    }, definition)
    createActivatedHost(self.h, "test-reset-host", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(_, state)
            capturedState = state
            if doAuthorReset then
                authorChanged, authorCount = state.resetAll({
                    exclude = { Count = true },
                })
            end
        end,
    })
    local host = self.h.moduleHost.getLiveModule("test-reset-host")

    host.drawTab()

    local changed, count = host.resetAll()
    lu.assertTrue(changed)
    lu.assertEquals(count, 2)
    lu.assertEquals(stagedState.read("EnabledFlag"), false)
    lu.assertEquals(stagedState.read("Count"), 2)

    stagedState.write("EnabledFlag", true)
    stagedState.write("Count", 6)
    doAuthorReset = true
    host.drawTab()
    lu.assertTrue(authorChanged)
    lu.assertEquals(authorCount, 1)
    lu.assertEquals(stagedState.read("EnabledFlag"), false)
    lu.assertEquals(stagedState.read("Count"), 6)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        capturedState.resetAll()
    end)
end

function TestModuleHost:testCreateModuleHostPassesCallbackHostToCallbacks()
    local callbackHost = nil
    local quickArgs = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = "author-pack",
        id = "AuthorModuleModule",
        name = "author module Module",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = true,
    }, definition)
    createActivatedHost(self.h, "test-author-module", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(_, _, _, _, activeHost)
            callbackHost = activeHost
        end,
        drawQuickContent = function(draw, state, actions)
            quickArgs = { draw = draw, state = state, actions = actions }
        end,
    })

    local host = self.h.moduleHost.getLiveModule("test-author-module")
    host.drawTab()
    host.drawQuickContent()

    lu.assertEquals(type(quickArgs.draw.widgets), "table")
    lu.assertNil(quickArgs.draw.log)
    lu.assertNil(quickArgs.draw.logIf)
    lu.assertEquals(type(quickArgs.state.get), "function")
    lu.assertEquals(type(quickArgs.actions.get), "function")
    lu.assertEquals(type(quickArgs.actions.trigger), "function")
    lu.assertEquals(type(quickArgs.actions.emit), "function")
    lu.assertNil(quickArgs.actions.hasAny)
    lu.assertEquals(callbackHost.getHostId(), "test-author-module")
    lu.assertEquals(callbackHost.getModuleId(), "AuthorModuleModule")
    lu.assertEquals(callbackHost.getPackId(), "author-pack")
    lu.assertNil(callbackHost.getIdentity)
    lu.assertEquals(callbackHost.getMeta().name, "author module Module")
    lu.assertTrue(callbackHost.isEnabled())
    lu.assertEquals(type(callbackHost.log), "function")
    lu.assertEquals(type(callbackHost.logIf), "function")
    lu.assertNil(callbackHost.fallbackUi)
    lu.assertNil(callbackHost.cache)
    lu.assertNil(callbackHost.hooks)
    lu.assertNil(callbackHost.activate)
    lu.assertNil(callbackHost.read)
    lu.assertNil(callbackHost.setEnabled)

    local warningCount = #self.h.warnings
    callbackHost.log("plain %s", "message")
    callbackHost.logIf("debug %d", 7)
    lu.assertEquals(self.h.warnings[warningCount + 1], "[AuthorModuleModule] plain message")
    lu.assertEquals(self.h.warnings[warningCount + 2], "[AuthorModuleModule] debug 7")
    lu.assertEquals(#self.h.warnings, warningCount + 2)
end

function TestModuleHost:testDrawPhaseClearsAfterDrawCallbackError()
    local secondDraws = 0
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawPhaseError",
        name = "Draw Phase Error",
        storage = {},
    })
    local firstStore, firstStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local secondStore, secondStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)

    local firstHost = createActivatedHost(self.h, "test-draw-phase-error-first", {
        definition = definition,
        persistentState = firstStore,
        stagedState = firstStagedState,
        drawTab = function()
            error("draw boom")
        end,
    })
    local secondHost = createActivatedHost(self.h, "test-draw-phase-error-second", {
        definition = definition,
        persistentState = secondStore,
        stagedState = secondStagedState,
        drawTab = function()
            secondDraws = secondDraws + 1
        end,
    })

    lu.assertErrorMsgContains("draw boom", function()
        firstHost.drawTab()
    end)

    secondHost.drawTab()

    lu.assertEquals(secondDraws, 1)
end

function TestModuleHost:testNestedDrawEntryIsRejected()
    local nestedDraws = 0
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "NestedDraw",
        name = "Nested Draw",
        storage = {},
    })
    local firstStore, firstStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local secondStore, secondStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local secondHost
    local firstHost = createActivatedHost(self.h, "test-nested-draw-first", {
        definition = definition,
        persistentState = firstStore,
        stagedState = firstStagedState,
        drawTab = function()
            secondHost.drawTab()
        end,
    })
    secondHost = createActivatedHost(self.h, "test-nested-draw-second", {
        definition = definition,
        persistentState = secondStore,
        stagedState = secondStagedState,
        drawTab = function()
            nestedDraws = nestedDraws + 1
        end,
    })

    lu.assertErrorMsgContains("phase.nested_draw", function()
        firstHost.drawTab()
    end)

    secondHost.drawTab()

    lu.assertEquals(nestedDraws, 1)
end

function TestModuleHost:testDrawDoesNotExposeLogging()
    local drawContext = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawNoLog",
        name = "Draw No Log",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedHost(self.h, "test-draw-no-log", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(draw)
            drawContext = draw
        end,
    })
    local host = self.h.moduleHost.getLiveModule("test-draw-no-log")

    host.drawTab()

    lu.assertNil(drawContext.log)
    lu.assertNil(drawContext.logIf)
end

function TestModuleHost:testDrawActionsOnlyGateMutationsOutsideOwningDrawPhase()
    local actions = nil
    local actionRef = nil
    local observed = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawActionsPhase",
        name = "Draw Actions Phase",
        storage = {},
        actions = {
            recording = function() end,
        },
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedHost(self.h, "test-draw-actions-phase", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(_, _, drawActions)
            actions = drawActions
            actionRef = actions.get("recording")
            actionRef:stage({ kind = "start" })
            observed = {
                has = actionRef:has(),
                value = actionRef:read(),
            }
        end,
    })
    local host = self.h.moduleHost.getLiveModule("test-draw-actions-phase")

    host.drawTab()

    lu.assertTrue(observed.has)
    lu.assertEquals(observed.value, { kind = "start" })
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actions.trigger("recording")
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actions.emit("test.events", "changed", {})
    end)
    lu.assertEquals(actionRef:read(), { kind = "start" })
    lu.assertTrue(actionRef:has())
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actionRef:stage({ kind = "again" })
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actionRef:clear()
    end)
end

function TestModuleHost:testDeclaredActionsExecuteDuringCommit()
    local observedActionHost = nil
    local observedCallbackHost = nil
    local observedRuntime = nil
    local observedRuntimeValue = nil
    local observedCommitAction = nil
    local observedConfigChange = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "DeclaredDrawActions",
        name = "Declared Draw Actions",
        storage = {
            { type = "bool", alias = "Flag", default = false },
            { type = "bool", alias = "RuntimeFlag", mode = "runtime", default = false },
        },
        actions = {
            setFlag = function(callbackHost, runtime, value)
                local host = callbackHost
                observedActionHost = host
                observedCallbackHost = callbackHost
                observedRuntime = runtime
                runtime.data.runtimeOwned.set("RuntimeFlag", value == true)
                observedRuntimeValue = runtime.data.runtimeOwned.read("RuntimeFlag")
            end,
        },
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        Flag = false,
        RuntimeFlag = false,
    }, definition)
    createActivatedHost(self.h, "test-declared-draw-actions", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        onCommit = function(_, _, commit)
            observedCommitAction = commit.actions.get("setFlag"):read()
            observedConfigChange = commit.hadConfigChanges()
        end,
        drawTab = function(_, _, actions)
            actions.trigger("setFlag")
        end,
    })
    local host = self.h.moduleHost.getLiveModule("test-declared-draw-actions")

    host.drawTab()

    lu.assertNil(observedActionHost)
    lu.assertFalse(stagedState.read("Flag"))
    lu.assertFalse(store.read("Flag"))

    local ok, err = host.commitIfDirty()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(err)
    lu.assertEquals(observedActionHost.getHostId(), "test-declared-draw-actions")
    lu.assertEquals(observedCallbackHost.getHostId(), "test-declared-draw-actions")
    lu.assertEquals(observedCallbackHost.isEnabled(), true)
    lu.assertEquals(type(observedRuntime.data.read), "function")
    lu.assertEquals(observedRuntimeValue, true)
    lu.assertFalse(store.read("Flag"))
    lu.assertTrue(store.runtimeOwned.read("RuntimeFlag"))
    lu.assertTrue(observedCommitAction)
    lu.assertFalse(observedConfigChange)
end

function TestModuleHost:testOnCommitReceivesRuntimeAndCallbackHost()
    local observedRuntime = nil
    local observedHost = nil
    local observedCommit = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "OnCommit",
        name = "On Commit",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        Flag = false,
    }, definition)
    local host = createActivatedHost(self.h, "test-on-commit", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        onCommit = function(runtime, callbackHost, commit)
            observedRuntime = runtime
            observedHost = callbackHost
            observedCommit = commit
        end,
        drawTab = function(_, state)
            state.write("Flag", true)
        end,
    })

    host.drawTab()
    lu.assertTrue(host.commitIfDirty())

    lu.assertEquals(observedRuntime.data.read("Flag"), true)
    lu.assertEquals(observedHost.getHostId(), "test-on-commit")
    lu.assertTrue(observedHost.isEnabled())
    lu.assertTrue(observedCommit.hadConfigChanges())
end

function TestModuleHost:testDrawActionsEmitSharedEventsDuringCommit()
    local delivered = nil
    local actionRan = false
    local actionRanAtDelivery = nil
    local sharedId = "test.draw-action-emit"
    local listenerDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawActionEmitListener",
        name = "Draw Action Emit Listener",
        storage = {
            { type = "bool", alias = "ListenerFlag", default = true },
        },
    })
    local listenerStore, listenerState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        ListenerFlag = true,
    }, listenerDefinition)
    local listenerStoreRead = nil
    createActivatedHost(self.h, "test-draw-action-emit-listener", {
        definition = listenerDefinition,
        persistentState = listenerStore,
        stagedState = listenerState,
        sharedListeners = {
            {
                id = sharedId,
                eventName = "changed",
                callback = function(_, _, payload)
                    listenerStoreRead = listenerStore.read("ListenerFlag")
                    actionRanAtDelivery = actionRan
                    delivered = payload
                end,
            },
        },
        drawTab = function() end,
    })

    local emitterDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawActionEmitEmitter",
        name = "Draw Action Emit Emitter",
        storage = {},
        actions = {
            mark = function()
                actionRan = true
            end,
        },
    })
    local emitterStore, emitterState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, emitterDefinition)
    createActivatedHost(self.h, "test-draw-action-emit-emitter", {
        definition = emitterDefinition,
        persistentState = emitterStore,
        stagedState = emitterState,
        drawTab = function(_, _, actions)
            actions.trigger("mark", true)
            actions.emit(sharedId, "changed", { value = 42 })
            lu.assertNil(delivered)
        end,
    })
    local emitter = self.h.moduleHost.getLiveModule("test-draw-action-emit-emitter")

    emitter.drawTab()

    lu.assertNil(delivered)
    lu.assertTrue(emitter.commitIfDirty())
    lu.assertEquals(delivered, { value = 42 })
    lu.assertTrue(actionRanAtDelivery)
    lu.assertTrue(listenerStoreRead)
    lu.assertEquals(#self.h.warnings, 0)
end

function TestModuleHost:testDrawActionsEmitSharedEventsDuringCommitWithoutAction()
    local delivered = nil
    local sharedId = "test.draw-action-emit-only"
    local listenerDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawActionEmitOnlyListener",
        name = "Draw Action Emit Only Listener",
        storage = {},
    })
    local listenerStore, listenerState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, listenerDefinition)
    createActivatedHost(self.h, "test-draw-action-emit-only-listener", {
        definition = listenerDefinition,
        persistentState = listenerStore,
        stagedState = listenerState,
        sharedListeners = {
            {
                id = sharedId,
                eventName = "changed",
                callback = function(_, _, payload)
                    delivered = payload
                end,
            },
        },
        drawTab = function() end,
    })

    local emitterDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawActionEmitOnlyEmitter",
        name = "Draw Action Emit Only Emitter",
        storage = {},
    })
    local emitterStore, emitterState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, emitterDefinition)
    createActivatedHost(self.h, "test-draw-action-emit-only-emitter", {
        definition = emitterDefinition,
        persistentState = emitterStore,
        stagedState = emitterState,
        drawTab = function(_, _, actions)
            actions.emit(sharedId, "changed", { value = 7 })
            lu.assertNil(delivered)
        end,
    })
    local emitter = self.h.moduleHost.getLiveModule("test-draw-action-emit-only-emitter")

    emitter.drawTab()

    lu.assertNil(delivered)
    lu.assertTrue(emitter.commitIfDirty())
    lu.assertEquals(delivered, { value = 7 })
    lu.assertEquals(#self.h.warnings, 0)
end

function TestModuleHost:testDrawActionsRejectUndeclaredKeys()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "UndeclaredDrawAction",
        name = "Undeclared Draw Action",
        storage = {},
        actions = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedHost(self.h, "test-undeclared-draw-action", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(_, _, actions)
            actions.trigger("missing")
        end,
    })
    local host = self.h.moduleHost.getLiveModule("test-undeclared-draw-action")

    lu.assertErrorMsgContains("actions.unknown_key", function()
        host.drawTab()
    end)
end

function TestModuleHost:testDrawActionsRejectPrivateActionKeys()
    local definition = self.h.moduleHost.prepareDefinitionWithInternalDeclarations({}, {
        id = "PrivateDrawAction",
        name = "Private Draw Action",
        storage = {},
    }, nil, {
        actions = {
            _PrivateAction = function() end,
        },
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedHost(self.h, "test-private-draw-action", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(_, _, actions)
            actions.trigger("_PrivateAction")
        end,
    })
    local host = self.h.moduleHost.getLiveModule("test-private-draw-action")

    lu.assertErrorMsgContains("actions.private_key", function()
        host.drawTab()
    end)
end

function TestModuleHost:testCommitActionsRejectPrivateActionKeys()
    local commitActions = self.h.moduleState.createCommitActions({
        _PrivateAction = true,
    })

    lu.assertErrorMsgContains("actions.private_key", function()
        commitActions.get("_PrivateAction")
    end)
end

function TestModuleHost:testFullHostOwnsManagedModuleCapabilities()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "FullHostCapabilities",
        name = "Full Host Capabilities",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = self.h.moduleHost.create({
        pluginGuid = "test-full-host-capabilities",
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })

    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(type(host.getHostId), "function")
    lu.assertEquals(type(host.getModuleId), "function")
    lu.assertEquals(type(host.getPackId), "function")
    lu.assertNil(host.getIdentity)
    lu.assertEquals(type(host.getMeta), "function")
    lu.assertEquals(type(host.log), "function")
    lu.assertEquals(type(host.logIf), "function")
    lu.assertEquals(type(host.activate), "function")
    lu.assertNil(host.tryActivate)
end

function TestModuleHost:testCreateModuleHostSyncsMutationBeforeCoordinatedRebuild()
    local packId = "reload-pack"
    local rebuildReason = nil

    self.h.coordinator.register(packId, { ModEnabled = true })
    self.h.coordinator.registerRebuild(packId, function(reason)
        rebuildReason = reason
        return true
    end)
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    createActivatedHost(self.h, "reload-pack.ReloadHost", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })

    local applyCalls = 0

    local previousRecord = self.h.moduleHost.getRecord(self.h.moduleHost.getLiveModule("reload-pack.ReloadHost"))
    local prepared = self.h.moduleHost.prepareDefinition({
        _definitionStructuralFingerprint = previousRecord.definition._structuralFingerprint,
    }, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })
    local reloadStore, reloadStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    createActivatedHost(self.h, "reload-pack.ReloadHost", {
        definition = prepared,
        persistentState = reloadStore,
        stagedState = reloadStagedState,
        patchMutation = function(plan)
            applyCalls = applyCalls + 1
            plan:set({}, "unused", true)
        end,
        drawTab = function() end,
    })
    local reloadedHost = self.h.moduleHost.getLiveModule("reload-pack.ReloadHost")

    self.h.coordinator.register(packId, nil)
    self.h.coordinator.registerRebuild(packId, nil)
    lu.assertEquals(applyCalls, 1)
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(self.h.moduleHost.getLiveModule("reload-pack.ReloadHost"), reloadedHost)
end

function TestModuleHost:testStructuralRebuildFailureRestoresPreviousLiveModuleAndMutation()
    local packId = "reload-rollback-pack"
    local pluginGuid = "reload-rollback-pack.ReloadHost"
    local target = { Value = "base" }

    self.h.coordinator.register(packId, { ModEnabled = true })
    self.h.coordinator.registerRebuild(packId, function()
        return false
    end)

    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ReloadRollbackHost",
        name = "Reload Rollback Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    local firstHost = createActivatedHost(self.h, pluginGuid, {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        patchMutation = function(plan)
            plan:set(target, "Value", "first")
        end,
        drawTab = function() end,
    })

    local previousRecord = self.h.moduleHost.getRecord(firstHost)
    local prepared = self.h.moduleHost.prepareDefinition({
        _definitionStructuralFingerprint = previousRecord.definition._structuralFingerprint,
    }, {
        modpack = packId,
        id = "ReloadRollbackHost",
        name = "Reload Rollback Host",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })
    local reloadStore, reloadStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    local replacementHost = self.h:createHost(pluginGuid, {
        definition = prepared,
        persistentState = reloadStore,
        stagedState = reloadStagedState,
        patchMutation = function(plan)
            plan:set(target, "Value", "second")
        end,
        drawTab = function() end,
    })

    local ok, err = replacementHost.activate()

    self.h.coordinator.register(packId, nil)
    self.h.coordinator.registerRebuild(packId, nil)
    lu.assertFalse(ok)
    lu.assertStrContains(err, "managed_module.structural_rebuild_unavailable")
    lu.assertEquals(self.h.moduleHost.getLiveModule(pluginGuid), firstHost)
    lu.assertEquals(target.Value, "first")
end

function TestModuleHost:testActivationFailureRestoresLiveModuleAndShared()
    local pluginGuid = "test-activation-rollback"
    local sharedId = "test.activation.rollback"
    local previousValue = nil

    local firstDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback",
        storage = {},
    })
    local firstStore, firstStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        persistentState = firstStore,
        stagedState = firstStagedState,
        sharedListeners = {
            {
                id = sharedId,
                eventName = "changed",
                callback = function(_, _, payload)
                    previousValue = payload.value
                end,
            },
        },
        drawTab = function() end,
    })

    local secondDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback Replacement",
        storage = {},
    })
    local secondStore, secondStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondSharedRegistrations = self.h.sharedBundle.registrations.create()
    local secondHost
    self.h.sharedBundle.registrations.stageListener(
        secondSharedRegistrations,
        function()
            local record = self.h.moduleHost.getRecord(secondHost)
            return record and record.host or nil
        end,
        sharedId,
        "changed",
        function(payload)
            previousValue = "replacement:" .. tostring(payload.value)
        end)
    secondHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        persistentState = secondStore,
        stagedState = secondStagedState,
        mutationBundle = {
            patchMutation = function()
                error("shared boom")
            end,
        },
        sharedEventRegistrations = secondSharedRegistrations,
        drawTab = function() end,
    })

    local ok, err = secondHost.activate()
    local _, emitter = createSimpleActivatedHost(self.h, "test-activation-rollback-emitter", "ActivationRollbackEmitter")
    emitShared(self.h, emitter, sharedId, "changed", { value = "previous" })

    lu.assertFalse(ok)
    lu.assertStrContains(err, "shared boom")
    lu.assertEquals(self.h.moduleHost.getLiveModule(pluginGuid), firstHost)
    lu.assertEquals(self.h.moduleRegistry.getPluginInfo(pluginGuid), {
        pluginGuid = pluginGuid,
        packId = nil,
        moduleId = "ActivationRollback",
        name = "Activation Rollback",
    })
    lu.assertEquals(previousValue, "previous")
    lu.assertErrorMsgContains("managed_module.not_activated", function()
        secondHost.flush()
    end)
end

function TestModuleHost:testActivationFailureDropsNewStagedSharedListener()
    local pluginGuid = "test-activation-new-shared-rollback"
    local sharedId = "test.activation.new.rollback"
    local delivered = 0

    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationNewSharedRollback",
        name = "Activation New Shared Rollback",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local sharedEventRegistrations = self.h.sharedBundle.registrations.create()
    local host
    self.h.sharedBundle.registrations.stageListener(
        sharedEventRegistrations,
        function()
            local record = self.h.moduleHost.getRecord(host)
            return record and record.host or nil
        end,
        sharedId,
        "changed",
        function()
            delivered = delivered + 1
        end)
    host = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        mutationBundle = {
            patchMutation = function()
                error("new shared boom")
            end,
        },
        sharedEventRegistrations = sharedEventRegistrations,
        drawTab = function() end,
    })

    local ok, err = host.activate()
    local _, emitter = createSimpleActivatedHost(
        self.h,
        "test-activation-new-shared-rollback-emitter",
        "ActivationNewSharedRollbackEmitter")
    local emitOk, count = emitShared(self.h, emitter, sharedId, "changed", {})

    lu.assertFalse(ok)
    lu.assertStrContains(err, "new shared boom")
    lu.assertNil(self.h.moduleHost.getLiveModule(pluginGuid))
    lu.assertNil(self.h.moduleRegistry.getPluginInfo(pluginGuid))
    lu.assertTrue(emitOk)
    lu.assertEquals(count, 0)
    lu.assertEquals(delivered, 0)
    lu.assertErrorMsgContains("managed_module.not_activated", function()
        host.flush()
    end)
end

function TestModuleHost:testRuntimeSyncFailureRestoresPreviousPatchMutation()
    local packId = "activation-runtime-rollback-pack"
    local pluginGuid = "test-activation-runtime-rollback"
    local target = { Value = "base" }

    self.h.coordinator.register(packId, { ModEnabled = true })

    local firstDefinition = self.h.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ActivationRuntimeRollback",
        name = "Activation Runtime Rollback",
        storage = {},
    })
    local firstStore, firstStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        persistentState = firstStore,
        stagedState = firstStagedState,
        patchMutation = function(plan)
            plan:set(target, "Value", "first")
        end,
        drawTab = function() end,
    })

    local secondDefinition = self.h.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "ActivationRuntimeRollback",
        name = "Activation Runtime Rollback",
        storage = {},
    })
    local secondStore, secondStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        persistentState = secondStore,
        stagedState = secondStagedState,
        mutationBundle = {
            patchMutation = function()
                error("replacement boom")
            end,
        },
        drawTab = function() end,
    })

    local ok, err = secondHost.activate()
    local liveModule = self.h.moduleHost.getLiveModule(pluginGuid)
    local targetValue = target.Value

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "replacement boom")
    lu.assertEquals(liveModule, firstHost)
    lu.assertNotEquals(liveModule, secondHost)
    lu.assertEquals(targetValue, "first")
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "managed_module.activate_failed")
    lu.assertStrContains(self.h.warnings[1], "replacement boom")
end

function TestModuleHost:testactivateModuleReturnsErrorAndDoesNotPublishBrokenHost()
    local pluginGuid = "test-try-activate-failure"
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "activateFailure",
        name = "Try Activate Failure",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        mutationBundle = {
            patchMutation = function()
                error("try activate boom")
            end,
        },
        drawTab = function() end,
    })

    local ok, err = host.activate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "try activate boom")
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "managed_module.activate_failed")
    lu.assertStrContains(self.h.warnings[1], "try activate boom")
    lu.assertNil(self.h.moduleHost.getLiveModule(pluginGuid))
    lu.assertErrorMsgContains("managed_module.not_activated", function()
        host.flush()
    end)
end

function TestModuleHost:testactivateModuleSucceedsThroughFullHost()
    local pluginGuid = "test-try-activate-success"
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "activateSuccess",
        name = "Try Activate Success",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })

    local ok, err = host.activate()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(self.h.moduleHost.getLiveModule(pluginGuid), host)
end

function TestModuleHost:testActivationRefreshRemovesOmittedShared()
    local pluginGuid = "test-activation-shared-refresh"
    local sharedId = "test.activation.refresh"
    local delivered = 0

    local firstDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationRefresh",
        name = "Activation Refresh",
        storage = {},
    })
    local firstStore, firstStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        persistentState = firstStore,
        stagedState = firstStagedState,
        sharedListeners = {
            {
                id = sharedId,
                eventName = "changed",
                callback = function()
                    delivered = delivered + 1
                end,
            },
        },
        drawTab = function() end,
    })

    local _, emitter = createSimpleActivatedHost(self.h, "test-activation-refresh-emitter", "ActivationRefreshEmitter")
    local emitOk, firstCount = emitShared(self.h, emitter, sharedId, "changed", {})
    lu.assertTrue(emitOk)
    lu.assertEquals(firstCount, 1)
    lu.assertEquals(delivered, 1)

    local secondDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationRefresh",
        name = "Activation Refresh",
        storage = {},
    })
    local secondStore, secondStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    createActivatedHost(self.h, pluginGuid, {
        definition = secondDefinition,
        persistentState = secondStore,
        stagedState = secondStagedState,
        drawTab = function() end,
    })

    local _, secondCount = emitShared(self.h, emitter, sharedId, "changed", {})
    lu.assertEquals(secondCount, 0)
    lu.assertEquals(delivered, 1)
end

function TestModuleHost:testActivationRejectsReentrantActivateCalls()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "ReentrantActivate",
        name = "Reentrant Activate",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host
    host = self.h.moduleHost.create({
        pluginGuid = "test-reentrant-activate",
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        mutationBundle = {
            patchMutation = function()
                host.activate()
            end,
        },
        drawTab = function() end,
    })

    local ok, err = host.activate()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(self.h.moduleHost.getLiveModule("test-reentrant-activate"), host)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "managed_module.activation_in_progress")
end
