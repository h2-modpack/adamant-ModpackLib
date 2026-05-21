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
    local host, authorHost, authorStore = h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = opts.definition,
        store = opts.store,
        session = opts.session,
        onSettingsCommitted = opts.onSettingsCommitted,
        drawTab = opts.drawTab,
        drawQuickContent = opts.drawQuickContent,
    })
    if opts.patchMutation ~= nil then
        authorHost.mutation.patch(opts.patchMutation)
    end
    if type(opts.configureHost) == "function" then
        opts.configureHost(authorHost, authorStore)
    end
    authorHost.activate()
    return host, authorHost, authorStore
end

function TestModuleHost:testFallbackUiWarnsWhenSessionCommitFails()
    local drawCalls = 0
    local pluginGuid = "test-fallback-ui-commit"
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = "fallback-pack",
        id = "FallbackUiTest",
        name = "Fallback UI Test",
        storage = {},
    })
    local store, session = self.h:createModuleState({
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
        store = store,
        session = session,
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

    local runtime = self.h.runtime.fallbackUi.runtimes[pluginGuid]
    runtime.addMenuBar()
    runtime.renderWindow()

    lu.assertEquals(drawCalls, 1)
    lu.assertEquals(#self.h.warnings, 1)
    lu.assertStrContains(self.h.warnings[1], "Fallback UI Test session commit failed")
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
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local attached = nil
    local _, authorHost = createActivatedHost(self.h, pluginGuid, {
        definition = definition,
        store = store,
        session = session,
        configureHost = function(activeAuthorHost)
            attached = activeAuthorHost.fallbackUi.attachGuiOnce(function() end)
        end,
        drawTab = function() end,
    })
    local host = self.h.moduleHost.getLiveHost(pluginGuid)

    local runtime = self.h.runtime.fallbackUi.runtimes[pluginGuid]

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
    local store, session = self.h:createModuleState({
        Value = false,
    }, definition)
    createActivatedHost(self.h, "test-settings-observer-host", {
        definition = definition,
        store = store,
        session = session,
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
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = createActivatedHost(self.h, "test-patch-host", {
        definition = definition,
        store = store,
        session = session,
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
    lu.assertEquals(patchStore, self.h.moduleHost.getState(host).authorStore)
    lu.assertNotEquals(patchStore, store)
    lu.assertTrue(target.Value)
end

function TestModuleHost:testSideEffectingHostMethodsRequireActivation()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "InactiveHost",
        name = "Inactive Host",
        storage = {},
    })
    local store, session = self.h:createModuleState({}, definition)
    local host = self.h.moduleHost.create({
        pluginGuid = "test-inactive-host",
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("host.not_activated", function()
        host.flush()
    end)
end

function TestModuleHost:testHostAndAuthorSessionResetToDefaultsDelegateToLibHelper()
    local capturedAuthorSession = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "ResetHost",
        name = "Reset Host",
        storage = {
            { type = "bool", alias = "EnabledFlag", default = false },
            { type = "int", alias = "Count", default = 2, min = 0, max = 9 },
        },
    })
    local store, session = self.h:createModuleState({
        EnabledFlag = true,
        Count = 7,
    }, definition)
    createActivatedHost(self.h, "test-reset-host", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function(_, data)
            capturedAuthorSession = data
        end,
    })
    local host = self.h.moduleHost.getLiveHost("test-reset-host")

    host.drawTab({})

    local changed, count = host.resetToDefaults()
    lu.assertTrue(changed)
    lu.assertEquals(count, 2)
    lu.assertEquals(session.read("EnabledFlag"), false)
    lu.assertEquals(session.read("Count"), 2)

    session.write("EnabledFlag", true)
    session.write("Count", 6)
    local authorChanged, authorCount = capturedAuthorSession.resetToDefaults({
        exclude = { Count = true },
    })
    lu.assertTrue(authorChanged)
    lu.assertEquals(authorCount, 1)
    lu.assertEquals(session.read("EnabledFlag"), false)
    lu.assertEquals(session.read("Count"), 6)
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
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = true,
    }, definition)
    local _, returnedHost = createActivatedHost(self.h, "test-author-host", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
        drawQuickContent = function(draw, data, actions, services)
            quickArgs = { draw = draw, data = data, actions = actions, services = services }
        end,
        configureHost = function(authorHost)
            callbackHost = authorHost
        end,
    })

    local host = self.h.moduleHost.getLiveHost("test-author-host")
    host.drawTab({})
    host.drawQuickContent({})

    lu.assertEquals(type(quickArgs.draw.widgets), "table")
    lu.assertEquals(type(quickArgs.data.get), "function")
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

function TestModuleHost:testDrawServicesExposeDrawSafeHostSubset()
    local services = nil
    local enabled = nil
    local integrationValue = nil
    local integrationProvider = nil
    local definition = self.h.moduleHost.prepareDefinition({}, {
        modpack = "services-pack",
        id = "DrawServicesModule",
        name = "Draw Services Module",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = true,
    }, definition)
    createActivatedHost(self.h, "test-draw-services", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function(_, _, _, drawServices)
            services = drawServices
            enabled = services.isHostEnabled()
            integrationValue, integrationProvider = services.invokeIntegration("test.draw-services", "value",
                "fallback", "ok")
            services.log("service %s", "log")
            services.logIf("service %s", "debug")
        end,
        configureHost = function(authorHost)
            authorHost.integrations.register("test.draw-services", {
                providerId = "DrawServicesProvider",
                api = {
                    value = function(suffix)
                        return "service:" .. tostring(suffix)
                    end,
                },
            })
        end,
    })
    local host = self.h.moduleHost.getLiveHost("test-draw-services")
    local warningCount = #self.h.warnings

    host.drawTab({})

    lu.assertEquals(type(services), "table")
    lu.assertEquals(type(services.log), "function")
    lu.assertEquals(type(services.logIf), "function")
    lu.assertEquals(type(services.isHostEnabled), "function")
    lu.assertEquals(type(services.invokeIntegration), "function")
    lu.assertNil(services.integrations)
    lu.assertNil(services.hooks)
    lu.assertNil(services.overlays)
    lu.assertNil(services.mutation)
    lu.assertNil(services.activate)
    lu.assertNil(services.setEnabled)
    lu.assertTrue(enabled)
    lu.assertEquals(integrationValue, "service:ok")
    lu.assertEquals(integrationProvider, "DrawServicesProvider")
    lu.assertEquals(self.h.warnings[warningCount + 1], "[DrawServicesModule] service log")
    lu.assertEquals(self.h.warnings[warningCount + 2], "[DrawServicesModule] service debug")
    lu.assertEquals(#self.h.warnings, warningCount + 2)
end

function TestModuleHost:testFullHostOwnsAuthorHostCapabilities()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "FullHostCapabilities",
        name = "Full Host Capabilities",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = self.h.moduleHost.create({
        pluginGuid = "test-full-host-capabilities",
        definition = definition,
        store = store,
        session = session,
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
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        EnabledFlag = false,
    }, definition)
    createActivatedHost(self.h, "reload-pack.ReloadHost", {
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })

    local applyCalls = 0

    local previousState = self.h.moduleHost.getState(self.h.moduleHost.getLiveHost("reload-pack.ReloadHost"))
    local prepared = self.h.moduleHost.prepareDefinition({
        _definitionStructuralFingerprint = previousState.definition._structuralFingerprint,
    }, {
        modpack = packId,
        id = "ReloadHost",
        name = "Reload Host",
        storage = {
            { type = "bool", alias = "OtherFlag", default = false },
        },
    })
    local reloadStore, reloadSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
        OtherFlag = false,
    }, prepared)
    createActivatedHost(self.h, "reload-pack.ReloadHost", {
        definition = prepared,
        store = reloadStore,
        session = reloadSession,
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
    local firstStore, firstSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost, firstAuthorHost = createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
        configureHost = function(authorHost)
            authorHost.integrations.register(integrationId, {
                providerId = providerId,
                api = previousApi,
            })
        end,
        drawTab = function() end,
    })

    local secondDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = "ActivationRollback",
        name = "Activation Rollback Replacement",
        storage = {},
    })
    local secondStore, secondSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondHost, secondAuthorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
        drawTab = function() end,
    })
    secondAuthorHost.mutation.patch(function()
        error("integration boom")
    end)
    secondAuthorHost.integrations.register(integrationId, {
        providerId = providerId,
        api = {
            read = function()
                return "replacement"
            end,
        },
    })

    local ok, err = secondAuthorHost.activate()
    local value = firstAuthorHost.integrations.invoke(integrationId, "read", nil)

    lu.assertFalse(ok)
    lu.assertStrContains(err, "integration boom")
    lu.assertEquals(self.h.moduleHost.getLiveHost(pluginGuid), firstHost)
    lu.assertEquals(self.h.moduleRuntimeRegistry.getPluginInfo(pluginGuid), {
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
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
        drawTab = function() end,
    })
    authorHost.mutation.patch(function()
        error("new integration boom")
    end)
    authorHost.integrations.register(integrationId, {
        providerId = providerId,
        api = {
            read = function()
                return "candidate"
            end,
        },
    })

    local ok, err = authorHost.activate()

    lu.assertFalse(ok)
    lu.assertStrContains(err, "new integration boom")
    lu.assertNil(self.h.moduleHost.getLiveHost(pluginGuid))
    lu.assertNil(self.h.moduleRuntimeRegistry.getPluginInfo(pluginGuid))
    lu.assertNil(authorHost.integrations.invoke(integrationId, "read", nil))
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
    local firstStore, firstSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local firstHost = createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
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
    local secondStore, secondSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    local secondHost, secondAuthorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
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
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
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
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host = self.h.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = definition,
        store = store,
        session = session,
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
    local firstStore, firstSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, firstDefinition)
    local _, firstAuthorHost = createActivatedHost(self.h, pluginGuid, {
        definition = firstDefinition,
        store = firstStore,
        session = firstSession,
        configureHost = function(authorHost)
            authorHost.integrations.register(integrationId, {
                providerId = providerId,
                api = {
                    read = function()
                        return "first"
                    end,
                },
            })
        end,
        drawTab = function() end,
    })

    lu.assertEquals(firstAuthorHost.integrations.invoke(integrationId, "read", nil), "first")

    local secondDefinition = self.h.moduleHost.prepareDefinition({}, {
        id = providerId,
        name = "Activation Refresh",
        storage = {},
    })
    local secondStore, secondSession = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, secondDefinition)
    createActivatedHost(self.h, pluginGuid, {
        definition = secondDefinition,
        store = secondStore,
        session = secondSession,
        drawTab = function() end,
    })

    lu.assertNil(firstAuthorHost.integrations.invoke(integrationId, "read", nil))
end

function TestModuleHost:testActivationRejectsReentrantActivateCalls()
    local definition = self.h.moduleHost.prepareDefinition({}, {
        id = "ReentrantActivate",
        name = "Reentrant Activate",
        storage = {},
    })
    local store, session = self.h:createModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local host, authorHost
    host, authorHost = self.h.moduleHost.create({
        pluginGuid = "test-reentrant-activate",
        definition = definition,
        store = store,
        session = session,
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
