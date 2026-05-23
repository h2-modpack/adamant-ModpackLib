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
        drawQuickContent = function(draw, state, actions, services)
            quickArgs = { draw = draw, state = state, actions = actions, services = services }
        end,
        configureHost = function(authorHost)
            callbackHost = authorHost
        end,
    })

    local host = self.h.moduleHost.getLiveHost("test-author-host")
    host.drawTab()
    host.drawQuickContent()

    lu.assertEquals(type(quickArgs.draw.widgets), "table")
    lu.assertEquals(type(quickArgs.state.get), "function")
    lu.assertEquals(type(quickArgs.actions.get), "function")
    lu.assertEquals(type(quickArgs.services.log), "function")
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
    lu.assertEquals(type(callbackHost.cache), "table")
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

function TestModuleHost:testDrawServicesExposeDrawSafeHostSubset()
    local services = nil
    local integrationValue = nil
    local integrationProvider = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = "services-pack",
        id = "DrawServicesModule",
        name = "Draw Services Module",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = true,
    }, definition)
    createActivatedHost(self.h, "test-draw-services", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(_, _, _, drawServices)
            services = drawServices
            integrationValue, integrationProvider = services.pollIntegration("test.draw-services", "value",
                "fallback", "ok")
            services.log("service %s", "log")
            services.logIf("service %s", "debug")
        end,
        configureHost = function(authorHost)
            authorHost.integrations.provide("test.draw-services", {
                providerId = "DrawServicesProvider",
                methods = {
                    value = {
                        handler = function(_, suffix)
                            return "service:" .. tostring(suffix)
                        end,
                    },
                },
            })
        end,
    })
    local host = self.h.moduleHost.getLiveHost("test-draw-services")
    local warningCount = #self.h.warnings

    host.drawTab()

    lu.assertEquals(type(services), "table")
    lu.assertEquals(type(services.log), "function")
    lu.assertEquals(type(services.logIf), "function")
    lu.assertEquals(type(services.pollIntegration), "function")
    lu.assertNil(services.integrations)
    lu.assertNil(services.hooks)
    lu.assertNil(services.overlays)
    lu.assertNil(services.mutation)
    lu.assertNil(services.activate)
    lu.assertNil(services.setEnabled)
    lu.assertEquals(integrationValue, "service:ok")
    lu.assertEquals(integrationProvider, "DrawServicesProvider")
    lu.assertEquals(self.h.warnings[warningCount + 1], "[DrawServicesModule] service log")
    lu.assertEquals(self.h.warnings[warningCount + 2], "[DrawServicesModule] service debug")
    lu.assertEquals(#self.h.warnings, warningCount + 2)
end

function TestModuleHost:testDrawServicesRejectUseOutsideDrawPhase()
    local services = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "DrawServicesPhase",
        name = "Draw Services Phase",
        storage = {},
    })
    local store, stagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    createActivatedHost(self.h, "test-draw-services-phase", {
        definition = definition,
        persistentState = store,
        stagedState = stagedState,
        drawTab = function(_, _, _, drawServices)
            services = drawServices
            services.pollIntegration("missing", "value", nil)
        end,
    })
    local host = self.h.moduleHost.getLiveHost("test-draw-services-phase")

    host.drawTab()

    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        services.log("outside")
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        services.logIf("outside")
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        services.pollIntegration("missing", "value", nil)
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
                hasAny = actions.hasAny(),
                has = actionRef:has(),
                value = actionRef:read(),
            }
        end,
    })
    local host = self.h.moduleHost.getLiveHost("test-draw-actions-phase")

    host.drawTab()

    lu.assertTrue(observed.hasAny)
    lu.assertTrue(observed.has)
    lu.assertEquals(observed.value, { kind = "start" })
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actions.hasAny()
    end)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        actions.get("recording")
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
    local observedCommitAction = nil
    local observedConfigChange = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "DeclaredDrawActions",
        name = "Declared Draw Actions",
        storage = {
            { type = "bool", alias = "Flag", default = false },
        },
        actions = {
            setFlag = function(state, _, value)
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
            actions.get("setFlag"):stage(true)
        end,
    })
    local host = self.h.moduleHost.getLiveHost("test-declared-draw-actions")

    host.drawTab()

    lu.assertTrue(stagedState.read("Flag"))
    lu.assertFalse(store.read("Flag"))

    local ok, err = host.commitIfDirty()

    lu.assertTrue(ok, tostring(err))
    lu.assertNil(err)
    lu.assertTrue(store.read("Flag"))
    lu.assertTrue(observedCommitAction)
    lu.assertTrue(observedConfigChange)
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
            actions.get("missing")
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

function TestModuleHost:testActivationFailureRestoresLiveHostAndIntegrations()
    local pluginGuid = "test-activation-rollback"
    local integrationId = "test.activation.rollback"
    local providerId = "RollbackProvider"
    local previousApi = {
        read = function()
            return "previous"
        end,
    }

    local firstDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback",
        storage = {},
    })
    local firstStore, firstStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost, firstAuthorHost = createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        persistentState = firstStore,
        stagedState = firstStagedState,
        configureHost = function(authorHost)
            authorHost.integrations.provide(integrationId, {
                providerId = providerId,
                methods = {
                    read = {
                        handler = previousApi.read,
                    },
                },
            })
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
        error("integration boom")
    end)
    secondAuthorHost.integrations.provide(integrationId, {
        providerId = providerId,
        methods = {
            read = {
                handler = function()
                    return "replacement"
                end,
            },
        },
    })

    local ok, err = secondAuthorHost.activate()
    local value = firstAuthorHost.integrations.poll(integrationId, "read", nil)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "integration boom")
    lu.assertEquals(self.h.moduleHost.getLiveHost(pluginGuid), firstHost)
    lu.assertEquals(self.h.hostRegistry.getPluginInfo(pluginGuid), {
        pluginGuid = pluginGuid,
        packId = nil,
        moduleId = "ActivationRollback",
        name = "Activation Rollback",
    })
    lu.assertEquals(value, "previous")
    lu.assertErrorMsgContains("host.not_activated", function()
        secondHost.flush()
    end)
end

function TestModuleHost:testActivationFailureDropsNewStagedIntegrationProvider()
    local pluginGuid = "test-activation-new-integration-rollback"
    local integrationId = "test.activation.new.rollback"
    local providerId = "NewRollbackProvider"

    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationNewIntegrationRollback",
        name = "Activation New Integration Rollback",
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
        error("new integration boom")
    end)
    authorHost.integrations.provide(integrationId, {
        providerId = providerId,
        methods = {
            read = {
                handler = function()
                    return "candidate"
                end,
            },
        },
    })

    local ok, err = authorHost.activate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "new integration boom")
    lu.assertNil(self.h.moduleHost.getLiveHost(pluginGuid))
    lu.assertNil(self.h.hostRegistry.getPluginInfo(pluginGuid))
    lu.assertNil(authorHost.integrations.poll(integrationId, "read", nil))
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

function TestModuleHost:testActivationRefreshRemovesOmittedIntegrations()
    local pluginGuid = "test-activation-integration-refresh"
    local integrationId = "test.activation.refresh"
    local providerId = "ActivationRefresh"

    local firstDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = providerId,
        name = "Activation Refresh",
        storage = {},
    })
    local firstStore, firstStagedState = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local _, firstAuthorHost = createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        persistentState = firstStore,
        stagedState = firstStagedState,
        configureHost = function(authorHost)
            authorHost.integrations.provide(integrationId, {
                providerId = providerId,
                methods = {
                    read = {
                        handler = function()
                            return "first"
                        end,
                    },
                },
            })
        end,
        drawTab = function() end,
    })

    lu.assertEquals(firstAuthorHost.integrations.poll(integrationId, "read", nil), "first")

    local secondDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = providerId,
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

    lu.assertNil(firstAuthorHost.integrations.poll(integrationId, "read", nil))
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
