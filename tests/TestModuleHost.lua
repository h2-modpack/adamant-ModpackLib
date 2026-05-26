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
    local host, authorHost, store = h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = opts.definition,
        persistentState = opts.persistentState,
        stagedState = opts.stagedState,
        onSettingsCommitted = opts.onSettingsCommitted,
        drawTab = opts.drawTab,
        drawQuickContent = opts.drawQuickContent,
    })
    if opts.patchMutation ~= nil then
        authorHost.mutation.patch(opts.patchMutation)
    end
    if type(opts.configureHost) == "function" then
        opts.configureHost(authorHost, store)
    end
    authorHost.activate()
    return host, authorHost, store
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
        configureHost = function(authorHost)
            authorHost.fallbackUi.attachGuiOnce(function() end)
        end,
        drawTab = function()
            drawCalls = drawCalls + 1
        end,
    })
    local moduleHost = self.h.moduleHost.getLiveHost(pluginGuid)
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
    lu.assertEquals(self.h.moduleHost.getLiveHost(pluginGuid), moduleHost)
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
    local _, authorHost = createActivatedHost(self.h, pluginGuid, {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        configureHost = function(activeAuthorHost)
            attached = activeAuthorHost.fallbackUi.attachGuiOnce(function() end)
        end,
        drawTab = function() end,
    })
    local host = self.h.moduleHost.getLiveHost(pluginGuid)

    local runtime = self.h.registry.fallback.runtimes[pluginGuid]

    lu.assertTrue(attached)
    lu.assertEquals(type(runtime.renderWindow), "function")
    lu.assertEquals(type(runtime.addMenuBar), "function")
    lu.assertEquals(type(authorHost.isEnabled), "function")
    lu.assertEquals(type(authorHost.fallbackUi.attachGuiOnce), "function")
    lu.assertEquals(self.h.moduleHost.getLiveHost(pluginGuid), host)
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
        onSettingsCommitted = function(_, activeStore)
            calls = calls + 1
            observedValue = activeStore.read("Value")
        end,
        drawTab = function() end,
    })
    local host = self.h.moduleHost.getLiveHost("test-settings-observer-host")

    host.stage("Value", true)
    local ok, err = host.flush()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(calls, 1)
    lu.assertTrue(observedValue)
end

function TestModuleHost:testPatchMutationReceivesAuthorHost()
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
    local host, authorHost = createActivatedHost(self.h, "test-patch-host", {
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
    lu.assertEquals(patchHost, authorHost)
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

    lu.assertErrorMsgContains("host.not_activated", function()
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
    local host = self.h.moduleHost.getLiveHost("test-reset-host")

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

function TestModuleHost:testCreateModuleHostPassesAuthorHostToCallbacks()
    local callbackHost = nil
    local quickArgs = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = "author-pack",
        id = "AuthorHostModule",
        name = "Author Host Module",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = true,
    }, definition)
    local _, returnedHost = createActivatedHost(self.h, "test-author-host", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
        drawQuickContent = function(draw, state, actions)
            quickArgs = { draw = draw, state = state, actions = actions }
        end,
        configureHost = function(authorHost)
            callbackHost = authorHost
        end,
    })

    local host = self.h.moduleHost.getLiveHost("test-author-host")
    host.drawTab()
    host.drawQuickContent()

    lu.assertEquals(type(quickArgs.draw.widgets), "table")
    lu.assertEquals(type(quickArgs.draw.log), "function")
    lu.assertEquals(type(quickArgs.draw.logIf), "function")
    lu.assertEquals(type(quickArgs.state.get), "function")
    lu.assertEquals(type(quickArgs.actions.get), "function")
    lu.assertEquals(type(quickArgs.actions.trigger), "function")
    lu.assertEquals(type(quickArgs.actions.emit), "function")
    lu.assertNil(quickArgs.actions.hasAny)
    lu.assertEquals(returnedHost, callbackHost)
    lu.assertEquals(callbackHost.getHostId(), "test-author-host")
    lu.assertEquals(callbackHost.getModuleId(), "AuthorHostModule")
    lu.assertEquals(callbackHost.getPackId(), "author-pack")
    lu.assertNil(callbackHost.getIdentity)
    lu.assertEquals(callbackHost.getMeta().name, "Author Host Module")
    lu.assertTrue(callbackHost.isEnabled())
    lu.assertEquals(type(callbackHost.log), "function")
    lu.assertEquals(type(callbackHost.logIf), "function")
    lu.assertEquals(type(callbackHost.fallbackUi), "table")
    lu.assertNil(callbackHost.cache)
    lu.assertEquals(type(callbackHost.hooks), "table")
    lu.assertEquals(type(callbackHost.activate), "function")
    lu.assertNil(callbackHost.read)
    lu.assertNil(callbackHost.setEnabled)

    local warningCount = #self.h.warnings
    callbackHost.log("plain %s", "message")
    callbackHost.logIf("debug %d", 7)
    lu.assertEquals(self.h.warnings[warningCount + 1], "[AuthorHostModule] plain message")
    lu.assertEquals(self.h.warnings[warningCount + 2], "[AuthorHostModule] debug 7")
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

function TestModuleHost:testDrawExposesDrawSafeLogging()
    local drawContext = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = "draw-log-pack",
        id = "DrawLogModule",
        name = "Draw Log Module",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = true,
    }, definition)
    createActivatedHost(self.h, "test-draw-logging", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(draw)
            drawContext = draw
            draw.log("draw %s", "log")
            draw.logIf("draw %s", "debug")
        end,
    })
    local host = self.h.moduleHost.getLiveHost("test-draw-logging")
    local warningCount = #self.h.warnings

    host.drawTab()

    lu.assertEquals(type(drawContext), "table")
    lu.assertEquals(type(drawContext.log), "function")
    lu.assertEquals(type(drawContext.logIf), "function")
    lu.assertNil(drawContext.services)
    lu.assertNil(drawContext.shared)
    lu.assertNil(drawContext.hooks)
    lu.assertNil(drawContext.overlays)
    lu.assertNil(drawContext.mutation)
    lu.assertNil(drawContext.activate)
    lu.assertNil(drawContext.setEnabled)
    lu.assertEquals(self.h.warnings[warningCount + 1], "[DrawLogModule] draw log")
    lu.assertEquals(self.h.warnings[warningCount + 2], "[DrawLogModule] draw debug")
    lu.assertEquals(#self.h.warnings, warningCount + 2)
end

function TestModuleHost:testDrawLoggingRejectsUseOutsideDrawPhase()
    local drawContext = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawLogPhase",
        name = "Draw Log Phase",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedHost(self.h, "test-draw-logging-phase", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(draw)
            drawContext = draw
            draw.log("inside")
        end,
    })
    local host = self.h.moduleHost.getLiveHost("test-draw-logging-phase")

    host.drawTab()

    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        drawContext.log("outside")
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        drawContext.logIf("outside")
    end)
end

function TestModuleHost:testDrawActionsRejectUseOutsideOwningDrawPhase()
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
    local host = self.h.moduleHost.getLiveHost("test-draw-actions-phase")

    host.drawTab()

    lu.assertTrue(observed.has)
    lu.assertEquals(observed.value, { kind = "start" })
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actions.trigger("recording")
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actions.get("recording")
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actions.emit("test.events", "changed", {})
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actionRef:read()
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actionRef:stage({ kind = "again" })
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actionRef:clear()
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actionRef:has()
    end)
end

function TestModuleHost:testDeclaredDrawActionsExecuteAfterDrawBeforeFlush()
    local observedActionHost = nil
    local observedCommitAction = nil
    local observedConfigChange = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "DeclaredDrawActions",
        name = "Declared Draw Actions",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        actions = {
            setFlag = function(host, state, value)
                observedActionHost = host
                state.write("Flag", value == true)
            end,
        },
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        Flag = false,
    }, definition)
    createActivatedHost(self.h, "test-declared-draw-actions", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        onSettingsCommitted = function(_, _, commit)
            observedCommitAction = commit.actions.get("setFlag"):read()
            observedConfigChange = commit.hadConfigChanges()
        end,
        drawTab = function(_, _, actions)
            actions.trigger("setFlag")
        end,
    })
    local host = self.h.moduleHost.getLiveHost("test-declared-draw-actions")

    host.drawTab()

    lu.assertEquals(observedActionHost.getHostId(), "test-declared-draw-actions")
    lu.assertTrue(stagedState.read("Flag"))
    lu.assertFalse(store.read("Flag"))

    local ok, err = host.commitIfDirty()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(err)
    lu.assertTrue(store.read("Flag"))
    lu.assertTrue(observedCommitAction)
    lu.assertTrue(observedConfigChange)
end

function TestModuleHost:testDrawActionsEmitSharedEventsAfterDraw()
    local delivered = nil
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
        configureHost = function(authorHost, store)
            authorHost.shared.listen(sharedId, "changed", function(payload)
                listenerStoreRead = store.read("ListenerFlag")
                delivered = payload
            end)
        end,
        drawTab = function() end,
    })

    local emitterDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawActionEmitEmitter",
        name = "Draw Action Emit Emitter",
        storage = {},
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
            actions.emit(sharedId, "changed", { value = 42 })
            lu.assertNil(delivered)
        end,
    })
    local emitter = self.h.moduleHost.getLiveHost("test-draw-action-emit-emitter")

    emitter.drawTab()

    lu.assertEquals(delivered, { value = 42 })
    lu.assertTrue(listenerStoreRead)
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
    local host = self.h.moduleHost.getLiveHost("test-undeclared-draw-action")

    lu.assertErrorMsgContains("actions.unknown_key", function()
        host.drawTab()
    end)
end

function TestModuleHost:testFullHostOwnsAuthorHostCapabilities()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "FullHostCapabilities",
        name = "Full Host Capabilities",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = self.h.moduleHost.create({
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
    lu.assertEquals(authorHost.activate, host.activate)
    lu.assertNil(host.tryActivate)
end

function TestModuleHost:testCreateModuleHostSkipsImmediateCoordinatedSyncWhenFrameworkRebuildIsPending()
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

    local previousRecord = self.h.moduleHost.getRecord(self.h.moduleHost.getLiveHost("reload-pack.ReloadHost"))
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
    local reloadedHost = self.h.moduleHost.getLiveHost("reload-pack.ReloadHost")

    self.h.coordinator.register(packId, nil)
    self.h.coordinator.registerRebuild(packId, nil)
    lu.assertEquals(applyCalls, 0)
    lu.assertNotNil(rebuildReason)
    lu.assertEquals(self.h.moduleHost.getLiveHost("reload-pack.ReloadHost"), reloadedHost)
end

function TestModuleHost:testActivationFailureRestoresLiveHostAndShared()
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
        configureHost = function(authorHost)
            authorHost.shared.listen(sharedId, "changed", function(payload)
                previousValue = payload.value
            end)
        end,
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
    local secondHost, secondAuthorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        persistentState = secondStore,
        stagedState = secondStagedState,
        drawTab = function() end,
    })
    secondAuthorHost.mutation.patch(function()
        error("shared boom")
    end)
    secondAuthorHost.shared.listen(sharedId, "changed", function(payload)
        previousValue = "replacement:" .. tostring(payload.value)
    end)

    local ok, err = secondAuthorHost.activate()
    local _, emitter = createSimpleActivatedHost(self.h, "test-activation-rollback-emitter", "ActivationRollbackEmitter")
    emitter.shared.emit(sharedId, "changed", { value = "previous" })

    lu.assertFalse(ok)
    lu.assertStrContains(err, "shared boom")
    lu.assertEquals(self.h.moduleHost.getLiveHost(pluginGuid), firstHost)
    lu.assertEquals(self.h.hostRegistry.getPluginInfo(pluginGuid), {
        pluginGuid = pluginGuid,
        packId = nil,
        moduleId = "ActivationRollback",
        name = "Activation Rollback",
    })
    lu.assertEquals(previousValue, "previous")
    lu.assertErrorMsgContains("host.not_activated", function()
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
    local host, authorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })
    authorHost.mutation.patch(function()
        error("new shared boom")
    end)
    authorHost.shared.listen(sharedId, "changed", function()
        delivered = delivered + 1
    end)

    local ok, err = authorHost.activate()
    local _, emitter = createSimpleActivatedHost(
        self.h,
        "test-activation-new-shared-rollback-emitter",
        "ActivationNewSharedRollbackEmitter")
    local emitOk, count = emitter.shared.emit(sharedId, "changed", {})

    lu.assertFalse(ok)
    lu.assertStrContains(err, "new shared boom")
    lu.assertNil(self.h.moduleHost.getLiveHost(pluginGuid))
    lu.assertNil(self.h.hostRegistry.getPluginInfo(pluginGuid))
    lu.assertTrue(emitOk)
    lu.assertEquals(count, 0)
    lu.assertEquals(delivered, 0)
    lu.assertErrorMsgContains("host.not_activated", function()
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
    local secondHost, secondAuthorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        persistentState = secondStore,
        stagedState = secondStagedState,
        drawTab = function() end,
    })
    secondAuthorHost.mutation.patch(function()
        error("replacement boom")
    end)

    local ok, err = secondAuthorHost.activate()
    local liveHost = self.h.moduleHost.getLiveHost(pluginGuid)
    local targetValue = target.Value

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "replacement boom")
    lu.assertEquals(liveHost, firstHost)
    lu.assertNotEquals(liveHost, secondHost)
    lu.assertEquals(targetValue, "first")
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "host.activate_failed")
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
    local host, authorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })
    authorHost.mutation.patch(function()
        error("try activate boom")
    end)

    local ok, err = authorHost.activate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "try activate boom")
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "host.activate_failed")
    lu.assertStrContains(self.h.warnings[1], "try activate boom")
    lu.assertNil(self.h.moduleHost.getLiveHost(pluginGuid))
    lu.assertErrorMsgContains("host.not_activated", function()
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
    lu.assertEquals(self.h.moduleHost.getLiveHost(pluginGuid), host)
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
        configureHost = function(authorHost)
            authorHost.shared.listen(sharedId, "changed", function()
                delivered = delivered + 1
            end)
        end,
        drawTab = function() end,
    })

    local _, emitter = createSimpleActivatedHost(self.h, "test-activation-refresh-emitter", "ActivationRefreshEmitter")
    local emitOk, firstCount = emitter.shared.emit(sharedId, "changed", {})
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

    local _, secondCount = emitter.shared.emit(sharedId, "changed", {})
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
    local host, authorHost
    host, authorHost = self.h.moduleHost.create({
        pluginGuid = "test-reentrant-activate",
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function() end,
    })
    authorHost.mutation.patch(function()
        authorHost.activate()
    end)

    local ok, err = authorHost.activate()

    lu.assertTrue(ok)
    lu.assertNil(err)
    lu.assertEquals(self.h.moduleHost.getLiveHost("test-reentrant-activate"), host)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "host.activation_in_progress")
end
