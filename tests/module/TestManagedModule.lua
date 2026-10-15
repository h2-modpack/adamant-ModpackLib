local lu = require("luaunit")
local createManagedModuleHarness = require("tests/harness/create_managed_module_harness")

TestManagedModule = {}

function TestManagedModule:setUp()
    self.h = createManagedModuleHarness()
    self.h:captureWarnings()
    self.previousImGui = self.h.rom.ImGui
    self.previousImGuiCond = self.h.rom.ImGuiCond
end

function TestManagedModule:tearDown()
    self.h.rom.ImGui = self.previousImGui
    self.h.rom.ImGuiCond = self.previousImGuiCond
    self.h:restoreWarnings()
end

local function createActivatedManagedModule(h, pluginGuid, opts)
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
                local record = h.moduleRegistry.getRecord(host)
                return record and record.host or nil
            end,
            listener.id,
            listener.eventName,
            function(payload)
                local record = h.moduleRegistry.getRecord(host)
                return listener.callback(record and record.host or nil, record and record.runtime or nil, payload)
            end)
    end
    local contexts
    host, contexts = h.harness:createManagedInstance({
        pluginGuid = pluginGuid,
        definition = opts.definition,
        state = opts.state,
        mutationBundle = mutationBundle,
        sharedEventRegistrations = sharedEventRegistrations,
        fallbackUiRequested = opts.fallbackUiRequested,
        onCommit = adaptCommitCallback(opts.onCommit),
        drawTab = adaptDrawCallback(opts.drawTab),
        drawQuickContent = adaptDrawCallback(opts.drawQuickContent),
    })
    store = contexts.runtime.data
    if type(opts.beforeActivate) == "function" then
        opts.beforeActivate(host, store)
    end
    host.activate()
    return host, host, store
end

local function createSimpleActivatedManagedModule(h, pluginGuid, id)
    local definition = h.moduleDefinition.prepareDefinition({}, {
        id = id or pluginGuid,
        name = id or pluginGuid,
        storage = {},
    })
    local _, _, moduleState = h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    return createActivatedManagedModule(h, pluginGuid, {
        definition = definition,
        state = moduleState,
        drawTab = function() end,
    })
end

local function emitShared(h, module, id, eventName, payload)
    local record = h.moduleRegistry.getRecord(module)
    return record.runtime.shared.emit(id, eventName, payload)
end

function TestManagedModule:testFallbackUiWarnsWhenStagedStateCommitFails()
    local drawCalls = 0
    local pluginGuid = "test-fallback-ui-commit"
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        modpack = "fallback-pack",
        id = "FallbackUiTest",
        name = "Fallback UI Test",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)

    local function noop() end

    self.h.rom.ImGuiCond = { FirstUseEver = 1 }
    self.h.rom.ImGuiCol = setmetatable({}, { __index = function() return 0 end })
    self.h.rom.ImGui = {
        PushStyleColor = noop,
        PopStyleColor = noop,
        BeginMenu = function() return true end,
        MenuItem = function() return true end,
        EndMenu = noop,
        SetNextWindowSize = noop,
        Begin = function() return true, true end,
        End = noop,
        Checkbox = function(_, current) return current, false end,
        Button = function() return false end,
        SameLine = noop,
        GetCursorPosX = function() return 0 end,
        SetCursorPosX = noop,
        Separator = noop,
        Spacing = noop,
        BeginTabBar = function() return true end,
        EndTabBar = noop,
        BeginTabItem = function(label) return label:find("###module-", 1, true) ~= nil end,
        EndTabItem = noop,
    }

    createActivatedManagedModule(self.h, pluginGuid, {
        definition = definition,
        state = moduleState,
        fallbackUiRequested = true,
        drawTab = function()
            drawCalls = drawCalls + 1
        end,
    })
    local managedModule = self.h.moduleRegistry.getLiveModule(pluginGuid)
    managedModule.commitIfDirty = function()
        return false, "commit boom", false
    end

    local runtime = self.h.registry.fallback.runtimes[pluginGuid]
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(drawCalls, 1)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "Fallback UI Test staged state commit failed")
    lu.assertStrContains(self.h.warnings[1], "commit boom")
    lu.assertEquals(self.h.moduleRegistry.getLiveModule(pluginGuid), managedModule)
end

function TestManagedModule:testFallbackUiInstallsDuringActivation()
    local pluginGuid = "test-fallback-ui-activation"
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "FallbackUiRegistryHost",
        name = "Fallback UI Registry Host",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local attached = nil
    createActivatedManagedModule(self.h, pluginGuid, {
        definition = definition,
        state = moduleState,
        fallbackUiRequested = true,
        beforeActivate = function(module)
            attached = self.h.fallbackUi.attachGuiOnce(module.getOwnerId(), function() end)
        end,
        drawTab = function() end,
    })
    local host = self.h.moduleRegistry.getLiveModule(pluginGuid)

    local runtime = self.h.registry.fallback.runtimes[pluginGuid]

    lu.assertTrue(attached)
    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(self.h.moduleRegistry.getLiveModule(pluginGuid), host)
end

function TestManagedModule:testFlushNotifiesSettingsObserver()
    local calls = 0
    local observedValue = nil
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "SettingsObserverHost",
        name = "Settings Observer Host",
        storage = {
            { type = "bool", alias = "Value", default = false },
        },
    })
    local _, _, moduleState = self.h:createModuleState({
        Value = false,
    }, definition)
    createActivatedManagedModule(self.h, "test-settings-observer-host", {
        definition = definition,
        state = moduleState,
        onCommit = function(runtime)
            calls = calls + 1
            observedValue = runtime.data.read("Value")
        end,
        drawTab = function() end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-settings-observer-host")

    host.stage("Value", true)
    local ok, err = host.flush()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
end

function TestManagedModule:testPatchMutationReceivesCallbackHostAndRuntimeData()
    local target = { Value = false }
    local patchHost = nil
    local patchStore = nil
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "PatchHostModule",
        name = "Patch Module",
        storage = {},
    })
    local store, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = createActivatedManagedModule(self.h, "test-patch-host", {
        definition = definition,
        state = moduleState,
        patchMutation = function(plan, activeHost, activeStore)
            patchHost = activeHost
            patchStore = activeStore
            plan:set(target, "Value", true)
        end,
        drawTab = function() end,
    })
    local ok, err = host.applyMutation()

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(patchHost, self.h.moduleRegistry.getRecord(host).host)
    lu.assertEquals(patchStore, self.h.moduleRegistry.getRecord(host).runtime.data)
    lu.assertNotEquals(patchStore, store)
    lu.assertTrue(target.Value)
end

function TestManagedModule:testSideEffectingManagedModuleMethodsRequireActivation()
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "InactiveHost",
        name = "Inactive Host",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({}, definition)
    local host = self.h.harness:createManagedInstance({
        pluginGuid = "test-inactive-host",
        definition = definition,
        state = moduleState,
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("managed_module.not_activated", function()
        host.flush()
    end)
end

function TestManagedModule:testOnActivateUsesPreparedRuntimeStateWithoutReloadingConfig()
    local observed = nil
    local reloads = 0
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ActivatePreparedHost",
        name = "Activate Prepared Host",
        storage = {
            { type = "int", alias = "TargetRuns", default = 3, min = 1, max = 10 },
            { type = "string", alias = "Mode", default = "single", maxLen = 16 },
            { type = "bool", alias = "RuntimeReady", mode = "runtime", default = false },
        },
    })
    local config = {
        Enabled = true,
        TargetRuns = 6,
        Mode = "multi",
        RuntimeReady = true,
    }
    local _, _, moduleState = self.h:createModuleState(config, definition)
    local reload = moduleState.txn.reload
    moduleState.txn.reload = function()
        reloads = reloads + 1
        return reload()
    end

    config.Enabled = false
    config.TargetRuns = 3
    config.Mode = "single"
    config.RuntimeReady = false

    local host = self.h.harness:createManagedInstance({
        pluginGuid = "test-on-activate-prepared-config",
        definition = definition,
        state = moduleState,
        drawTab = function() end,
        onActivate = function(callbackHost, runtime)
            observed = {
                enabled = callbackHost.isEnabled(),
                targetRuns = runtime.data.read("TargetRuns"),
                mode = runtime.data.read("Mode"),
                ready = runtime.status.read("RuntimeReady"),
            }
        end,
    })

    local ok, err = host.activate()
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(reloads, 0)
    lu.assertEquals(observed, {
        enabled = true,
        targetRuns = 6,
        mode = "multi",
        ready = true,
    })
end

function TestManagedModule:testManagedModuleResetAllResetsStagedAndStatusState()
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ResetHost",
        name = "Reset Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "int", alias = "Count", default = 2, min = 0, max = 9 },
            { type = "bool", alias = "RuntimeFlag", mode = "runtime", default = false },
        },
    })
    local _, stagedState, moduleState = self.h:createModuleState({
        EnabledFlag = true,
        Count = 7,
    }, definition)
    createActivatedManagedModule(self.h, "test-reset-host", {
        definition = definition,
        state = moduleState,
        drawTab = function() end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-reset-host")
    moduleState.status.write("RuntimeFlag", true)

    host.drawTab()

    local changed, count = host.resetAll()
    lu.assertTrue(changed)
    lu.assertEquals(count, 3)
    lu.assertEquals(stagedState.read("EnabledFlag"), false)
    lu.assertEquals(stagedState.read("Count"), 2)
    lu.assertTrue(moduleState.status.read("RuntimeFlag"))

    local ok, err = host.commitIfDirty()
    lu.assertTrue(ok, tostring(err))
    lu.assertFalse(moduleState.status.read("RuntimeFlag"))

end

function TestManagedModule:testUiResetAllQueuesModuleResetDuringCommit()
    local doReset = false
    local commitHadActions = nil
    local publicActionRan = false
    local delivered = nil
    local sharedId = "test.ui-reset-clears-intent"
    local listenerDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "UiResetAllListener",
        name = "UI Reset All Listener",
        storage = {},
    })
    local _, _, listenerModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, listenerDefinition)
    createActivatedManagedModule(self.h, "test-ui-reset-all-listener", {
        definition = listenerDefinition,
        state = listenerModuleState,
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

    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "UiResetAll",
        name = "UI Reset All",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "int", alias = "Count", default = 2, min = 0, max = 9 },
            { type = "bool", alias = "RuntimeFlag", mode = "runtime", default = false },
        },
        actions = {
            mark = function()
                publicActionRan = true
            end,
        },
    })
    local _, stagedState, moduleState = self.h:createModuleState({
        EnabledFlag = true,
        Count = 7,
    }, definition)
    createActivatedManagedModule(self.h, "test-ui-reset-all", {
        definition = definition,
        state = moduleState,
        onCommit = function(_, _, commit)
            commitHadActions = commit.actions.hasAny()
        end,
        drawTab = function(_, _, actions, ui)
            if doReset then
                actions.trigger("mark", true)
                ui.shared.emit(sharedId, "changed", { value = 7 })
                lu.assertTrue(ui.resetAll({
                    exclude = { Count = true },
                }))
            end
        end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-ui-reset-all")
    moduleState.status.write("RuntimeFlag", true)

    doReset = true
    host.drawTab()
    lu.assertFalse(stagedState.read("EnabledFlag"))
    lu.assertEquals(stagedState.read("Count"), 7)
    lu.assertTrue(moduleState.status.read("RuntimeFlag"))

    local ok, err, committed = host.commitIfDirty()
    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(committed)
    lu.assertFalse(stagedState.read("EnabledFlag"))
    lu.assertEquals(stagedState.read("Count"), 7)
    lu.assertFalse(moduleState.status.read("RuntimeFlag"))
    lu.assertFalse(commitHadActions)
    lu.assertFalse(publicActionRan)
    lu.assertNil(delivered)

end

function TestManagedModule:testManagedModulePassesCallbackHostToCallbacks()
    local callbackHost = nil
    local quickArgs = nil
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        modpack = "author-pack",
        id = "AuthorModuleModule",
        name = "author module Module",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = true,
    }, definition)
    createActivatedManagedModule(self.h, "test-author-module", {
        definition = definition,
        state = moduleState,
        drawTab = function(_, _, _, _, activeHost)
            callbackHost = activeHost
        end,
        drawQuickContent = function(draw, state, actions, ui)
            quickArgs = { draw = draw, state = state, actions = actions, ui = ui }
        end,
    })

    local host = self.h.moduleRegistry.getLiveModule("test-author-module")
    host.drawTab()
    host.drawQuickContent()

    lu.assertEquals(type(quickArgs.draw.widgets), "table")
    lu.assertNil(quickArgs.draw.log)
    lu.assertNil(quickArgs.draw.logIf)
    lu.assertEquals(type(quickArgs.state.get), "function")
    lu.assertEquals(type(quickArgs.actions.get), "function")
    lu.assertEquals(type(quickArgs.actions.trigger), "function")
    lu.assertNil(quickArgs.actions.emit)
    lu.assertEquals(type(quickArgs.ui.shared.emit), "function")
    lu.assertNil(quickArgs.actions.hasAny)
    lu.assertEquals(callbackHost.getOwnerId(), "test-author-module")
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

function TestManagedModule:testDrawCallbackErrorsDoNotPoisonLaterDraws()
    local secondDraws = 0
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "DrawCallbackError",
        name = "Draw Callback Error",
        storage = {},
    })
    local _, _, firstModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local _, _, secondModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)

    local firstHost = createActivatedManagedModule(self.h, "test-draw-callback-error-first", {
        definition = definition,
        state = firstModuleState,
        drawTab = function()
            error("draw boom")
        end,
    })
    local secondHost = createActivatedManagedModule(self.h, "test-draw-callback-error-second", {
        definition = definition,
        state = secondModuleState,
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

function TestManagedModule:testDrawDoesNotExposeLogging()
    local drawContext = nil
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "DrawNoLog",
        name = "Draw No Log",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedManagedModule(self.h, "test-draw-no-log", {
        definition = definition,
        state = moduleState,
        drawTab = function(draw)
            drawContext = draw
        end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-draw-no-log")

    host.drawTab()

    lu.assertNil(drawContext.log)
    lu.assertNil(drawContext.logIf)
end

function TestManagedModule:testDrawActionsStageAndReadIntent()
    local actionRef = nil
    local observed = nil
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "DrawActionsIntent",
        name = "Draw Actions Intent",
        storage = {},
        actions = {
            recording = function() end,
        },
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedManagedModule(self.h, "test-draw-actions-intent", {
        definition = definition,
        state = moduleState,
        drawTab = function(_, _, drawActions)
            actionRef = drawActions.get("recording")
            actionRef:stage({ kind = "start" })
            observed = {
                has = actionRef:has(),
                value = actionRef:read(),
            }
        end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-draw-actions-intent")

    host.drawTab()

    lu.assertTrue(observed.has)
    lu.assertEquals(observed.value, { kind = "start" })
    lu.assertEquals(actionRef:read(), { kind = "start" })
    lu.assertTrue(actionRef:has())
end

function TestManagedModule:testDeclaredActionsExecuteDuringCommit()
    local observedActionHost = nil
    local observedCallbackHost = nil
    local observedRuntime = nil
    local observedRuntimeValue = nil
    local observedCommittedFlagInAction = nil
    local observedCommitAction = nil
    local observedConfigChange = nil
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
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
                observedCommittedFlagInAction = runtime.data.read("Flag")
                runtime.status.write("RuntimeFlag", value == true)
                observedRuntimeValue = runtime.status.read("RuntimeFlag")
            end,
        },
    })
    local persistentState, stagedState, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        Flag = false,
        RuntimeFlag = false,
    }, definition)
    createActivatedManagedModule(self.h, "test-declared-draw-actions", {
        definition = definition,
        state = moduleState,
        onCommit = function(_, _, commit)
            observedCommitAction = commit.actions.get("setFlag"):read()
            observedConfigChange = commit.hadConfigChanges()
        end,
        drawTab = function(_, state, actions)
            state.write("Flag", true)
            actions.trigger("setFlag")
        end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-declared-draw-actions")

    host.drawTab()

    lu.assertNil(observedActionHost)
    lu.assertTrue(stagedState.read("Flag"))
    lu.assertFalse(persistentState.read("Flag"))

    local ok, err = host.commitIfDirty()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(err)
    lu.assertEquals(observedActionHost.getOwnerId(), "test-declared-draw-actions")
    lu.assertEquals(observedCallbackHost.getOwnerId(), "test-declared-draw-actions")
    lu.assertEquals(observedCallbackHost.isEnabled(), true)
    lu.assertEquals(type(observedRuntime.data.read), "function")
    lu.assertTrue(observedCommittedFlagInAction)
    lu.assertEquals(observedRuntimeValue, true)
    lu.assertTrue(persistentState.read("Flag"))
    lu.assertTrue(moduleState.status.read("RuntimeFlag"))
    lu.assertTrue(observedCommitAction)
    lu.assertTrue(observedConfigChange)
end

function TestManagedModule:testDrawTabThenCommitRunsFullDrawLifecycle()
    local observedConfigChange = nil
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "DrawLifecycle",
        name = "Draw Lifecycle",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    local persistentState, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        Flag = false,
    }, definition)
    createActivatedManagedModule(self.h, "test-draw-lifecycle", {
        definition = definition,
        state = moduleState,
        onCommit = function(_, _, commit)
            observedConfigChange = commit.hadConfigChanges()
        end,
        drawTab = function(_, state)
            state.write("Flag", true)
        end,
    })

    local host = self.h.moduleRegistry.getLiveModule("test-draw-lifecycle")
    host.drawTab()
    local ok, err, committed = host.commitIfDirty()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(err)
    lu.assertTrue(committed)
    lu.assertTrue(persistentState.read("Flag"))
    lu.assertTrue(observedConfigChange)
end

function TestManagedModule:testDeclaredActionsRunAfterSuccessfulMutationOnly()
    local target = { Value = false }
    local actionSawMutation = nil
    local failedActionRan = false
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ActionAfterMutation",
        name = "Action After Mutation",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        actions = {
            mark = function()
                actionSawMutation = target.Value
            end,
        },
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        Flag = false,
    }, definition)
    createActivatedManagedModule(self.h, "test-action-after-mutation", {
        definition = definition,
        state = moduleState,
        patchMutation = function(plan)
            plan:set(target, "Value", true)
        end,
        drawTab = function(_, state, actions)
            state.write("Flag", true)
            actions.trigger("mark", true)
        end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-action-after-mutation")
    target.Value = false

    host.drawTab()
    local ok, err = host.commitIfDirty()
    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(actionSawMutation)

    local failingDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ActionAfterFailedMutation",
        name = "Action After Failed Mutation",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        actions = {
            mark = function()
                failedActionRan = true
            end,
        },
    })
    local _, _, failingModuleState = self.h:createModuleState({
        Enabled = false,
        DebugMode = false,
        Flag = false,
    }, failingDefinition)
    createActivatedManagedModule(self.h, "test-action-after-failed-mutation", {
        definition = failingDefinition,
        state = failingModuleState,
        patchMutation = function()
            error("mutation failed")
        end,
        drawTab = function(_, state, actions)
            state.write("Enabled", true)
            state.write("Flag", true)
            actions.trigger("mark", true)
        end,
    })
    local failingHost = self.h.moduleRegistry.getLiveModule("test-action-after-failed-mutation")

    failingHost.drawTab()
    ok, err = failingHost.commitIfDirty()
    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "mutation failed")
    lu.assertFalse(failedActionRan)
end

function TestManagedModule:testOnCommitReceivesRuntimeAndCallbackHost()
    local observedRuntime = nil
    local observedHost = nil
    local observedCommit = nil
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "OnCommit",
        name = "On Commit",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        Flag = false,
    }, definition)
    local host = createActivatedManagedModule(self.h, "test-on-commit", {
        definition = definition,
        state = moduleState,
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
    lu.assertEquals(observedHost.getOwnerId(), "test-on-commit")
    lu.assertTrue(observedHost.isEnabled())
    lu.assertTrue(observedCommit.hadConfigChanges())
end

function TestManagedModule:testUiSharedEmitSharedEventsDuringCommit()
    local delivered = nil
    local actionRan = false
    local actionRanAtDelivery = nil
    local sharedId = "test.draw-action-emit"
    local listenerDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "DrawActionEmitListener",
        name = "Draw Action Emit Listener",
        storage = {
            { type = "bool", alias = "ListenerFlag", default = true },
        },
    })
    local listenerStore, _, listenerModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        ListenerFlag = true,
    }, listenerDefinition)
    local listenerStoreRead = nil
    createActivatedManagedModule(self.h, "test-draw-action-emit-listener", {
        definition = listenerDefinition,
        state = listenerModuleState,
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

    local emitterDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "DrawActionEmitEmitter",
        name = "Draw Action Emit Emitter",
        storage = {},
        actions = {
            mark = function()
                actionRan = true
            end,
        },
    })
    local _, _, emitterModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, emitterDefinition)
    createActivatedManagedModule(self.h, "test-draw-action-emit-emitter", {
        definition = emitterDefinition,
        state = emitterModuleState,
        drawTab = function(_, _, actions, ui)
            actions.trigger("mark", true)
            ui.shared.emit(sharedId, "changed", { value = 42 })
            lu.assertNil(delivered)
        end,
    })
    local emitter = self.h.moduleRegistry.getLiveModule("test-draw-action-emit-emitter")

    emitter.drawTab()

    lu.assertNil(delivered)
    lu.assertTrue(emitter.commitIfDirty())
    lu.assertEquals(delivered, { value = 42 })
    lu.assertTrue(actionRanAtDelivery)
    lu.assertTrue(listenerStoreRead)
    lu.assertEquals(#self.h.warnings, 0)
end

function TestManagedModule:testUiSharedEmitSharedEventsDuringCommitWithoutAction()
    local delivered = nil
    local sharedId = "test.draw-action-emit-only"
    local listenerDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "DrawActionEmitOnlyListener",
        name = "Draw Action Emit Only Listener",
        storage = {},
    })
    local _, _, listenerModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, listenerDefinition)
    createActivatedManagedModule(self.h, "test-draw-action-emit-only-listener", {
        definition = listenerDefinition,
        state = listenerModuleState,
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

    local emitterDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "DrawActionEmitOnlyEmitter",
        name = "Draw Action Emit Only Emitter",
        storage = {},
    })
    local _, _, emitterModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, emitterDefinition)
    createActivatedManagedModule(self.h, "test-draw-action-emit-only-emitter", {
        definition = emitterDefinition,
        state = emitterModuleState,
        drawTab = function(_, _, _, ui)
            ui.shared.emit(sharedId, "changed", { value = 7 })
            lu.assertNil(delivered)
        end,
    })
    local emitter = self.h.moduleRegistry.getLiveModule("test-draw-action-emit-only-emitter")

    emitter.drawTab()

    lu.assertNil(delivered)
    lu.assertTrue(emitter.commitIfDirty())
    lu.assertEquals(delivered, { value = 7 })
    lu.assertEquals(#self.h.warnings, 0)
end

function TestManagedModule:testUiSharedEmitValidatesDuringDraw()
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "DrawSharedEmitValidation",
        name = "Draw Shared Emit Validation",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedManagedModule(self.h, "test-draw-shared-emit-validation", {
        definition = definition,
        state = moduleState,
        drawTab = function(_, _, _, ui)
            lu.assertErrorMsgContains("id must be a non-empty string", function()
                ui.shared.emit("", "changed", {})
            end)
            lu.assertErrorMsgContains("eventName must be a non-empty string", function()
                ui.shared.emit("test.invalid", "", {})
            end)
        end,
    })
    local emitter = self.h.moduleRegistry.getLiveModule("test-draw-shared-emit-validation")

    emitter.drawTab()
    lu.assertEquals(#self.h.warnings, 0)
end

function TestManagedModule:testDrawActionsRejectUndeclaredKeys()
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "UndeclaredDrawAction",
        name = "Undeclared Draw Action",
        storage = {},
        actions = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedManagedModule(self.h, "test-undeclared-draw-action", {
        definition = definition,
        state = moduleState,
        drawTab = function(_, _, actions)
            actions.trigger("missing")
        end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-undeclared-draw-action")

    lu.assertErrorMsgContains("actions.unknown_key", function()
        host.drawTab()
    end)
end

function TestManagedModule:testDrawActionsRejectPrivateActionKeys()
    local definition = self.h.moduleDefinition.prepareDefinitionWithInternalDeclarations({}, {
        id = "PrivateDrawAction",
        name = "Private Draw Action",
        storage = {},
    }, nil, {
        actions = {
            _PrivateAction = function() end,
        },
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedManagedModule(self.h, "test-private-draw-action", {
        definition = definition,
        state = moduleState,
        drawTab = function(_, _, actions)
            actions.trigger("_PrivateAction")
        end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-private-draw-action")

    lu.assertErrorMsgContains("actions.private_key", function()
        host.drawTab()
    end)
end

function TestManagedModule:testCommitActionsRejectPrivateActionKeys()
    local commitActions = self.h.moduleState.createCommitActions({
        _PrivateAction = true,
    })

    lu.assertErrorMsgContains("actions.private_key", function()
        commitActions.get("_PrivateAction")
    end)
end

function TestManagedModule:testLiveModuleOwnsManagedModuleCapabilities()
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "LiveModuleCapabilities",
        name = "Live Module Capabilities",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = self.h.harness:createManagedInstance({
        pluginGuid = "test-live-module-capabilities",
        definition = definition,
        state = moduleState,
        drawTab = function() end,
    })

    lu.assertEquals(type(host.isEnabled), "function")
    lu.assertEquals(type(host.getOwnerId), "function")
    lu.assertEquals(type(host.getModuleId), "function")
    lu.assertEquals(type(host.getPackId), "function")
    lu.assertNil(host.getIdentity)
    lu.assertEquals(type(host.getMeta), "function")
    lu.assertEquals(type(host.log), "function")
    lu.assertEquals(type(host.logIf), "function")
    lu.assertEquals(type(host.activate), "function")
    lu.assertNil(host.tryActivate)
end

function TestManagedModule:testManagedModuleSyncsMutationBeforeCoordinatedRebuild()
    local packId = "reload-pack"
    local rebuildReason = nil

    self.h.coordinator.register(packId, "Test Pack", { ModEnabled = true })
    self.h.coordinator.registerRebuild(packId, function(reason)
        rebuildReason = reason
        return true
    end)
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    createActivatedManagedModule(self.h, "reload-pack.ReloadHost", {
        definition = definition,
        state = moduleState,
        drawTab = function() end,
    })

    local applyCalls = 0

    local previousRecord = self.h.moduleRegistry.getRecord(self.h.moduleRegistry.getLiveModule("reload-pack.ReloadHost"))
    local prepared = self.h.moduleDefinition.prepareDefinition({
        _definitionStructuralFingerprint = previousRecord.definition._structuralFingerprint,
    }, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })
    local _, _, reloadModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    createActivatedManagedModule(self.h, "reload-pack.ReloadHost", {
        definition = prepared,
        state = reloadModuleState,
        patchMutation = function(plan)
            applyCalls = applyCalls + 1
            plan:set({}, "unused", true)
        end,
        drawTab = function() end,
    })
    local reloadedHost = self.h.moduleRegistry.getLiveModule("reload-pack.ReloadHost")

    self.h.coordinator.register(packId, nil)
    self.h.coordinator.registerRebuild(packId, nil)
    lu.assertEquals(applyCalls, 1)
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(self.h.moduleRegistry.getLiveModule("reload-pack.ReloadHost"), reloadedHost)
end

function TestManagedModule:testStructuralRebuildFailureRestoresPreviousLiveModuleAndMutation()
    local packId = "reload-rollback-pack"
    local pluginGuid = "reload-rollback-pack.ReloadHost"
    local target = { Value = "base" }

    self.h.coordinator.register(packId, "Test Pack", { ModEnabled = true })
    self.h.coordinator.registerRebuild(packId, function()
        return false
    end)

    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        modpack = packId,
        id = "ReloadRollbackHost",
        name = "Reload Rollback Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
        },
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    local firstHost = createActivatedManagedModule(self.h, pluginGuid, {
        definition = definition,
        state = moduleState,
        patchMutation = function(plan)
            plan:set(target, "Value", "first")
        end,
        drawTab = function() end,
    })

    local previousRecord = self.h.moduleRegistry.getRecord(firstHost)
    local prepared = self.h.moduleDefinition.prepareDefinition({
        _definitionStructuralFingerprint = previousRecord.definition._structuralFingerprint,
    }, {
        modpack = packId,
        id = "ReloadRollbackHost",
        name = "Reload Rollback Host",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })
    local _, _, reloadModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    local replacementHost = self.h:createManagedModule(pluginGuid, {
        definition = prepared,
        state = reloadModuleState,
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
    lu.assertEquals(self.h.moduleRegistry.getLiveModule(pluginGuid), firstHost)
    lu.assertEquals(target.Value, "first")
end

function TestManagedModule:testActivationFailureRestoresLiveModuleAndShared()
    local pluginGuid = "test-activation-rollback"
    local sharedId = "test.activation.rollback"
    local previousValue = nil

    local firstDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback",
        storage = {},
    })
    local _, _, firstModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedManagedModule(self.h, pluginGuid, {
        definition = firstDefinition,
        state = firstModuleState,
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

    local secondDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback Replacement",
        storage = {},
    })
    local _, _, secondModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondSharedRegistrations = self.h.sharedBundle.registrations.create()
    local secondHost
    self.h.sharedBundle.registrations.stageListener(
        secondSharedRegistrations,
        function()
            local record = self.h.moduleRegistry.getRecord(secondHost)
            return record and record.host or nil
        end,
        sharedId,
        "changed",
        function(payload)
            previousValue = "replacement:" .. tostring(payload.value)
        end)
    secondHost = self.h.harness:createManagedInstance({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        state = secondModuleState,
        mutationBundle = {
            patchMutation = function()
                error("shared boom")
            end,
        },
        sharedEventRegistrations = secondSharedRegistrations,
        drawTab = function() end,
    })

    local ok, err = secondHost.activate()
    local _, emitter = createSimpleActivatedManagedModule(self.h, "test-activation-rollback-emitter", "ActivationRollbackEmitter")
    emitShared(self.h, emitter, sharedId, "changed", { value = "previous" })

    lu.assertFalse(ok)
    lu.assertStrContains(err, "shared boom")
    lu.assertEquals(self.h.moduleRegistry.getLiveModule(pluginGuid), firstHost)
    lu.assertEquals(previousValue, "previous")
    lu.assertErrorMsgContains("managed_module.not_activated", function()
        secondHost.flush()
    end)
end

local function recordReceipt(events, generation, receipt)
    local label = generation .. ":" .. receipt.name
    local recorded = { name = receipt.name, phase = receipt.phase }
    for _, methodName in ipairs({ "commit", "rollback", "retire" }) do
        recorded[methodName] = function()
            events[#events + 1] = methodName .. ":" .. label
            return receipt[methodName]()
        end
    end
    return recorded
end

-- Wraps every capability install activation calls; `getGeneration()` labels the installing module.
local function recordActivationReceipts(h, events, getGeneration)
    local installs = {
        { service = h.sharedBundle, method = "install" },
        { service = h.harness.hooks, method = "install" },
        { service = h.overlays, method = "install" },
    }
    for _, entry in ipairs(installs) do
        local original = entry.service[entry.method]
        entry.service[entry.method] = function(...)
            return recordReceipt(events, getGeneration(), original(...))
        end
    end
    local originalBind = h.harness.mutation.bind
    h.harness.mutation.bind = function(...)
        local bound = originalBind(...)
        local generation = getGeneration()
        local originalSync = bound.sync
        bound.sync = function()
            return recordReceipt(events, generation, originalSync())
        end
        return bound
    end
end

local function createNamedManagedModule(h, pluginGuid, name, onActivate)
    local definition = h.moduleDefinition.prepareDefinition({}, {
        id = "ActivationReceiptOrder",
        name = name,
        storage = {},
    })
    local _, _, moduleState = h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    return h.harness:createManagedInstance({
        pluginGuid = pluginGuid,
        definition = definition,
        state = moduleState,
        onActivate = onActivate,
        drawTab = function() end,
    })
end

function TestManagedModule:testActivationCommitsByPhaseAndReleasesInReverse()
    local pluginGuid = "test-activation-receipt-order"
    local events = {}
    local generation = nil
    recordActivationReceipts(self.h, events, function()
        return generation
    end)
    local function clearEvents()
        for index = #events, 1, -1 do
            events[index] = nil
        end
    end

    generation = "gen1"
    local ok, err = createNamedManagedModule(self.h, pluginGuid, "gen1").activate()
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(events, {
        "commit:gen1:mutation",
        "commit:gen1:shared",
        "commit:gen1:hooks",
        "commit:gen1:overlays",
    })

    clearEvents()
    generation = "gen2"
    ok = createNamedManagedModule(self.h, pluginGuid, "gen2", function()
        error("onActivate boom")
    end).activate()
    lu.assertFalse(ok)
    lu.assertEquals(events, {
        "commit:gen2:mutation",
        "commit:gen2:shared",
        "commit:gen2:hooks",
        "commit:gen2:overlays",
        "rollback:gen2:overlays",
        "rollback:gen2:hooks",
        "rollback:gen2:shared",
        "rollback:gen2:mutation",
    })

    clearEvents()
    generation = "gen3"
    ok, err = createNamedManagedModule(self.h, pluginGuid, "gen3").activate()
    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(events, {
        "commit:gen3:mutation",
        "commit:gen3:shared",
        "commit:gen3:hooks",
        "commit:gen3:overlays",
        "retire:gen1:overlays",
        "retire:gen1:hooks",
        "retire:gen1:shared",
        "retire:gen1:mutation",
    })
end

function TestManagedModule:testActivationFailureDropsNewStagedSharedListener()
    local pluginGuid = "test-activation-new-shared-rollback"
    local sharedId = "test.activation.new.rollback"
    local delivered = 0

    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ActivationNewSharedRollback",
        name = "Activation New Shared Rollback",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local sharedEventRegistrations = self.h.sharedBundle.registrations.create()
    local host
    self.h.sharedBundle.registrations.stageListener(
        sharedEventRegistrations,
        function()
            local record = self.h.moduleRegistry.getRecord(host)
            return record and record.host or nil
        end,
        sharedId,
        "changed",
        function()
            delivered = delivered + 1
        end)
    host = self.h.harness:createManagedInstance({
        pluginGuid = pluginGuid,
        definition = definition,
        state = moduleState,
        mutationBundle = {
            patchMutation = function()
                error("new shared boom")
            end,
        },
        sharedEventRegistrations = sharedEventRegistrations,
        drawTab = function() end,
    })

    local ok, err = host.activate()
    local _, emitter = createSimpleActivatedManagedModule(
        self.h,
        "test-activation-new-shared-rollback-emitter",
        "ActivationNewSharedRollbackEmitter")
    local emitOk, count = emitShared(self.h, emitter, sharedId, "changed", {})

    lu.assertFalse(ok)
    lu.assertStrContains(err, "new shared boom")
    lu.assertNil(self.h.moduleRegistry.getLiveModule(pluginGuid))
    lu.assertTrue(emitOk)
    lu.assertEquals(count, 0)
    lu.assertEquals(delivered, 0)
    lu.assertErrorMsgContains("managed_module.not_activated", function()
        host.flush()
    end)
end

function TestManagedModule:testRuntimeSyncFailureRestoresPreviousPatchMutation()
    local packId = "activation-runtime-rollback-pack"
    local pluginGuid = "test-activation-runtime-rollback"
    local target = { Value = "base" }

    self.h.coordinator.register(packId, "Test Pack", { ModEnabled = true })

    local firstDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        modpack = packId,
        id = "ActivationRuntimeRollback",
        name = "Activation Runtime Rollback",
        storage = {},
    })
    local _, _, firstModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedManagedModule(self.h, pluginGuid, {
        definition = firstDefinition,
        state = firstModuleState,
        patchMutation = function(plan)
            plan:set(target, "Value", "first")
        end,
        drawTab = function() end,
    })

    local secondDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        modpack = packId,
        id = "ActivationRuntimeRollback",
        name = "Activation Runtime Rollback",
        storage = {},
    })
    local _, _, secondModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondHost = self.h.harness:createManagedInstance({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        state = secondModuleState,
        mutationBundle = {
            patchMutation = function()
                error("replacement boom")
            end,
        },
        drawTab = function() end,
    })

    local ok, err = secondHost.activate()
    local liveModule = self.h.moduleRegistry.getLiveModule(pluginGuid)
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

function TestManagedModule:testActivateModuleReturnsErrorAndDoesNotPublishBrokenModule()
    local pluginGuid = "test-try-activate-failure"
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "activateFailure",
        name = "Try Activate Failure",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = self.h.harness:createManagedInstance({
        pluginGuid = pluginGuid,
        definition = definition,
        state = moduleState,
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
    lu.assertNil(self.h.moduleRegistry.getLiveModule(pluginGuid))
    lu.assertErrorMsgContains("managed_module.not_activated", function()
        host.flush()
    end)
end

function TestManagedModule:testActivateModuleSucceedsThroughLiveModule()
    local pluginGuid = "test-try-activate-success"
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "activateSuccess",
        name = "Try Activate Success",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = self.h.harness:createManagedInstance({
        pluginGuid = pluginGuid,
        definition = definition,
        state = moduleState,
        drawTab = function() end,
    })

    local ok, err = host.activate()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(self.h.moduleRegistry.getLiveModule(pluginGuid), host)
end

function TestManagedModule:testActivationRefreshRemovesOmittedShared()
    local pluginGuid = "test-activation-shared-refresh"
    local sharedId = "test.activation.refresh"
    local delivered = 0

    local firstDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ActivationRefresh",
        name = "Activation Refresh",
        storage = {},
    })
    local _, _, firstModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    createActivatedManagedModule(self.h, pluginGuid, {
        definition = firstDefinition,
        state = firstModuleState,
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

    local _, emitter = createSimpleActivatedManagedModule(self.h, "test-activation-refresh-emitter", "ActivationRefreshEmitter")
    local emitOk, firstCount = emitShared(self.h, emitter, sharedId, "changed", {})
    lu.assertTrue(emitOk)
    lu.assertEquals(firstCount, 1)
    lu.assertEquals(delivered, 1)

    local secondDefinition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ActivationRefresh",
        name = "Activation Refresh",
        storage = {},
    })
    local _, _, secondModuleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    createActivatedManagedModule(self.h, pluginGuid, {
        definition = secondDefinition,
        state = secondModuleState,
        drawTab = function() end,
    })

    local _, secondCount = emitShared(self.h, emitter, sharedId, "changed", {})
    lu.assertEquals(secondCount, 0)
    lu.assertEquals(delivered, 1)
end

function TestManagedModule:testActivationRejectsReentrantActivateCalls()
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ReentrantActivate",
        name = "Reentrant Activate",
        storage = {},
    })
    local _, _, moduleState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host
    host = self.h.harness:createManagedInstance({
        pluginGuid = "test-reentrant-activate",
        definition = definition,
        state = moduleState,
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
    lu.assertEquals(self.h.moduleRegistry.getLiveModule("test-reentrant-activate"), host)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "managed_module.activation_in_progress")
end

function TestManagedModule:testResetAllRejectsInvalidOptsAtBoundary()
    local uiResult = nil
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ResetOpts",
        name = "Reset Opts",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "bool", alias = "RuntimeFlag", mode = "runtime", default = false },
        },
    })
    local _, stagedState, moduleState = self.h:createModuleState({
        EnabledFlag = true,
    }, definition)
    createActivatedManagedModule(self.h, "test-reset-opts", {
        definition = definition,
        state = moduleState,
        drawTab = function(_, _, _, ui)
            uiResult = { pcall(ui.resetAll, { exclude = "EnabledFlag" }) }
        end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-reset-opts")
    moduleState.status.write("RuntimeFlag", true)

    lu.assertErrorMsgContains("lifecycle.invalid_reset_opts", function()
        host.resetAll("EnabledFlag")
    end)
    lu.assertErrorMsgContains("lifecycle.invalid_reset_opts", function()
        host.resetAll({ exclude = true })
    end)
    host.drawTab()
    lu.assertFalse(uiResult[1])
    lu.assertStrContains(tostring(uiResult[2]), "lifecycle.invalid_reset_opts")

    lu.assertTrue(stagedState.read("EnabledFlag"))
    lu.assertTrue(moduleState.status.read("RuntimeFlag"))
    lu.assertFalse(moduleState.txn.hasPending())
end

function TestManagedModule:testFailedCommitDiscardsQueuedStatusReset()
    local failPatch = false
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ResetRollback",
        name = "Reset Rollback",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "bool", alias = "RuntimeFlag", mode = "runtime", default = false },
        },
    })
    local _, stagedState, moduleState = self.h:createModuleState({
        Enabled = true,
        EnabledFlag = true,
    }, definition)
    createActivatedManagedModule(self.h, "test-reset-rollback", {
        definition = definition,
        state = moduleState,
        patchMutation = function()
            if failPatch then
                error("patch boom")
            end
        end,
        drawTab = function() end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-reset-rollback")
    moduleState.status.write("RuntimeFlag", true)

    lu.assertTrue(host.resetAll({ exclude = { Enabled = true } }))
    failPatch = true
    local ok, err = host.commitIfDirty()
    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "patch boom")
    lu.assertTrue(stagedState.read("EnabledFlag"))
    lu.assertTrue(moduleState.status.read("RuntimeFlag"))

    failPatch = false
    local committedOk, _, committed = host.commitIfDirty()
    lu.assertTrue(committedOk)
    lu.assertFalse(committed)
    lu.assertTrue(moduleState.status.read("RuntimeFlag"))
end

function TestManagedModule:testReloadFromConfigDiscardsQueuedStatusReset()
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "ResetReload",
        name = "Reset Reload",
        storage = {
            { type = "bool", alias = "RuntimeFlag", mode = "runtime", default = false },
        },
    })
    local _, _, moduleState = self.h:createModuleState({ Enabled = true }, definition)
    createActivatedManagedModule(self.h, "test-reset-reload", {
        definition = definition,
        state = moduleState,
        drawTab = function() end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-reset-reload")
    moduleState.status.write("RuntimeFlag", true)

    lu.assertTrue(host.resetAll())
    host.reloadFromConfig()
    local ok, _, committed = host.commitIfDirty()
    lu.assertTrue(ok)
    lu.assertFalse(committed)
    lu.assertTrue(moduleState.status.read("RuntimeFlag"))
end

local function createCapabilityActivation(h, capabilities)
    return h.harness.import('core/module_bootstrap/managed_module_activation.lua', nil, {
        logging = h.harness.logging,
        coordinator = h.coordinator,
        moduleRegistry = h.moduleRegistry,
        capabilities = capabilities,
    })
end

local function createRecordingCapability(h, events, installs, name, phase, opts)
    opts = opts or {}
    return function(ownerId, owner, inputs)
        installs[#installs + 1] = { name = name, ownerId = ownerId, owner = owner, inputs = inputs }
        if opts.skip then
            return nil
        end
        return h.harness.receipt.create({
            name = name,
            phase = phase,
            commit = function()
                events[#events + 1] = "commit:" .. name
                if opts.failCommit then
                    return false, "boom"
                end
            end,
            rollback = function()
                events[#events + 1] = "rollback:" .. name
            end,
            retire = function()
                events[#events + 1] = "retire:" .. name
            end,
        })
    end
end

local function createCapabilityTestModule(h, pluginGuid)
    local definition = h.moduleDefinition.prepareDefinition({}, {
        id = "CapabilityTable",
        name = "Capability Table",
        storage = {},
    })
    local _, _, moduleState = h:createModuleState({ Enabled = true }, definition)
    return h:createManagedModule(pluginGuid, {
        definition = definition,
        state = moduleState,
        drawTab = function() end,
    })
end

function TestManagedModule:testActivationInstallsProvidedCapabilitiesInPhaseOrder()
    local receiptApi = self.h.harness.receipt
    local events = {}
    local installs = {}
    local activation = createCapabilityActivation(self.h, {
        createRecordingCapability(self.h, events, installs, "effects", receiptApi.PHASE_EFFECTS),
        createRecordingCapability(self.h, events, installs, "skipped", receiptApi.PHASE_EFFECTS, { skip = true }),
        createRecordingCapability(self.h, events, installs, "gameData", receiptApi.PHASE_GAME_DATA),
    })
    local pluginGuid = "test-capability-table"
    local module = createCapabilityTestModule(self.h, pluginGuid)
    local record = self.h.moduleRegistry.getRecord(module)

    lu.assertEquals({ activation.activateOrThrow(module) }, { true })

    lu.assertEquals(#installs, 3)
    lu.assertEquals({ installs[1].name, installs[2].name, installs[3].name }, { "effects", "skipped", "gameData" })
    for _, install in ipairs(installs) do
        lu.assertEquals(install.ownerId, pluginGuid)
        lu.assertIs(install.owner, module)
        lu.assertIs(install.inputs, record.capabilityInputs)
    end
    lu.assertEquals(events, { "commit:gameData", "commit:effects" })
    lu.assertEquals({ record.effectReceipts[1].name, record.effectReceipts[2].name }, { "gameData", "effects" })
    lu.assertEquals(#record.effectReceipts, 2)
    lu.assertTrue(record.activated)
    lu.assertIs(self.h.moduleRegistry.getLiveModule(pluginGuid), module)
end

function TestManagedModule:testActivationRollsBackProvidedCapabilitiesOnCommitFailure()
    local receiptApi = self.h.harness.receipt
    local events = {}
    local installs = {}
    local activation = createCapabilityActivation(self.h, {
        createRecordingCapability(self.h, events, installs, "effects", receiptApi.PHASE_EFFECTS, { failCommit = true }),
        createRecordingCapability(self.h, events, installs, "gameData", receiptApi.PHASE_GAME_DATA),
    })
    local pluginGuid = "test-capability-table-rollback"
    local module = createCapabilityTestModule(self.h, pluginGuid)
    local record = self.h.moduleRegistry.getRecord(module)

    lu.assertErrorMsgContains("effects commit failed: boom", function()
        activation.activateOrThrow(module)
    end)

    lu.assertEquals(events, { "commit:gameData", "commit:effects", "rollback:gameData" })
    lu.assertFalse(record.activated)
    lu.assertEquals(#record.effectReceipts, 0)
    lu.assertNil(self.h.moduleRegistry.getLiveModule(pluginGuid))
end

function TestManagedModule:testCallbackContextsAreBuiltOnceWithLaneFields()
    local definition = self.h.moduleDefinition.prepareDefinition({}, {
        id = "StableContexts",
        name = "Stable Contexts",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
    })
    local _, _, moduleState = self.h:createModuleState({ Enabled = true }, definition)
    local committedRuntimes = {}
    local drawnUis = {}
    createActivatedManagedModule(self.h, "test-stable-contexts", {
        definition = definition,
        state = moduleState,
        onCommit = function(runtime)
            committedRuntimes[#committedRuntimes + 1] = runtime
        end,
        drawTab = function(_, _, _, ui)
            drawnUis[#drawnUis + 1] = ui
        end,
    })
    local host = self.h.moduleRegistry.getLiveModule("test-stable-contexts")
    local record = self.h.moduleRegistry.getRecord(host)

    lu.assertTrue(host.writeAndFlush("Flag", true))
    lu.assertTrue(host.writeAndFlush("Flag", false))
    host.drawTab()
    host.drawTab()

    local runtime = record.runtime
    lu.assertEquals(#committedRuntimes, 2)
    lu.assertIs(committedRuntimes[1], runtime)
    lu.assertIs(committedRuntimes[2], runtime)
    lu.assertNotNil(runtime.cache.currentRun)
    lu.assertIs(runtime.data.cache, runtime.cache)
    lu.assertIs(runtime.data.shared, runtime.shared)
    lu.assertIs(runtime.data.controls, runtime.controls)
    lu.assertNotNil(runtime.status.get)

    lu.assertEquals(#drawnUis, 2)
    lu.assertIs(drawnUis[1], drawnUis[2])
    lu.assertIs(drawnUis[1].data.shared, drawnUis[1].shared)
    lu.assertNotIs(drawnUis[1].shared, runtime.shared)
end
