local lu = require("luaunit")
local createLibHarness = require('tests/harness/create_lib_harness')

TestHooks = {}

local function createPathMock(target)
    local counts = {
        wrap = 0,
        override = 0,
        restore = 0,
        contextWrap = 0,
    }
    local originals = {}

    local function getEnv()
        return assert(target.env, "hook test env missing")
    end

    local testModUtil = {
        Path = {
            Wrap = function(path, handler)
                counts.wrap = counts.wrap + 1
                local env = getEnv()
                local base = env[path]
                env[path] = function(...)
                    return handler(base, ...)
                end
            end,

            Override = function(path, value)
                counts.override = counts.override + 1
                local env = getEnv()
                if originals[path] == nil then
                    originals[path] = env[path]
                end
                env[path] = value
            end,

            Restore = function(path)
                counts.restore = counts.restore + 1
                if originals[path] == nil then
                    error("object has no overrides")
                end
                getEnv()[path] = originals[path]
                originals[path] = nil
            end,

            Context = {
                Wrap = function(path, context)
                    counts.contextWrap = counts.contextWrap + 1
                    local env = getEnv()
                    local base = env[path]
                    env[path] = function(...)
                        context(...)
                        return base(...)
                    end
                end,
            },
        },
    }
    counts.modutil = testModUtil
    return counts, testModUtil
end

local function createStagedState()
    local stagedState
    stagedState = {
        view = {},
        get = function(alias)
            return {
                read = function()
                    return stagedState.read(alias)
                end,
            }
        end,
        read = function() end,
        write = function() end,
        reset = function() end,
        getAliasSchema = function() end,
        isDirty = function()
            return false
        end,
        _flushToConfig = function() end,
        _reloadFromConfig = function() end,
        auditMismatches = function()
            return {}
        end,
    }
    return stagedState
end

local function createStore(enabled)
    local store
    store = {
        get = function(alias)
            return {
                read = function()
                    return store.read(alias)
                end,
            }
        end,
        read = function(key)
            if key == "Enabled" then
                return enabled == true
            end
            return false
        end,
        getAliasSchema = function() end,
    }
    return store
end

function TestHooks:setUp()
    local target = {}
    self.counts, self.modutil = createPathMock(target)
    self.harness = createLibHarness({
        modutil = self.modutil,
    })
    target.env = self.harness.env
    self.env = self.harness.env
    self.public = self.harness.public
    self.coordinator = self.harness.coordinator
    self.moduleHost = self.harness.moduleHost
    self.mutation = self.harness.mutation
    self.hookRegistry = self.harness.registry.hooks
end

function TestHooks:createHostWithHooks(pluginGuid, registerHooks, activationOpts)
    activationOpts = activationOpts or {}
    local store = createStore(activationOpts.enabled == true)
    local host, authorHost = self.moduleHost.create({
        pluginGuid = pluginGuid,
        definition = self.moduleHost.prepareDefinition({}, { id = "HookTest", name = "Hook Test", storage = {} }),
        persistentState = store,
        stagedState = createStagedState(),
        drawTab = function() end,
    })
    if activationOpts.patchMutation ~= nil then
        authorHost.mutation.patch(activationOpts.patchMutation)
    end
    if registerHooks ~= nil then
        registerHooks(authorHost, store)
    end
    return self.moduleHost.activateOrThrow(host)
end

function TestHooks:testWrapRegistersOnceAndUpdatesHandler()
    self.env.AdamantHookTestWrap = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks("hook-test-wrap-update", function(host)
        host.hooks.wrap("AdamantHookTestWrap", function(base, value)
            return "first:" .. base(value)
        end)
        host.hooks.wrap("AdamantHookTestWrap", function(base, value)
            return "second:" .. base(value)
        end)
    end)

    lu.assertEquals(self.counts.wrap, 1)
    lu.assertEquals(self.env.AdamantHookTestWrap("x"), "second:base:x")
end

function TestHooks:testWrapUsesInjectedModUtilWhenGlobalIsMissing()
    self.env.modutil = nil
    self.env.AdamantHookTestWrapInjected = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks("hook-test-wrap-injected-modutil", function(host)
        host.hooks.wrap("AdamantHookTestWrapInjected", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.counts.wrap, 1)
    lu.assertEquals(self.env.AdamantHookTestWrapInjected("x"), "wrapped:base:x")
end

function TestHooks:testWrapRefreshOmissionFallsBackToBase()
    local pluginGuid = "hook-test-wrap-refresh"
    self.env.AdamantHookTestWrapRefresh = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.wrap("AdamantHookTestWrapRefresh", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestWrapRefresh("x"), "wrapped:base:x")

    self:createHostWithHooks(pluginGuid, function() end)

    lu.assertEquals(self.env.AdamantHookTestWrapRefresh("x"), "base:x")
end

function TestHooks:testMissingRegisterHooksRefreshRemovesPreviousHooks()
    local pluginGuid = "hook-test-missing-register-hooks"
    self.env.AdamantHookTestMissingRegisterHooks = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.wrap("AdamantHookTestMissingRegisterHooks", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestMissingRegisterHooks("x"), "wrapped:base:x")

    self:createHostWithHooks(pluginGuid, nil)

    lu.assertEquals(self.env.AdamantHookTestMissingRegisterHooks("x"), "base:x")
end

function TestHooks:testRetiredHookHostPrunesDeadDispatcherOwnerEntries()
    local pluginGuid = "hook-test-prune-dispatcher"
    local ownerId = pluginGuid
    local path = "AdamantHookTestPruneDispatcher"
    self.env[path] = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.wrap(path, function(base, value)
            return "first:" .. base(value)
        end)
    end)
    local dispatcher = self.hookRegistry.dispatchers.wrap[path]

    lu.assertNotNil(dispatcher)
    lu.assertEquals(dispatcher.ownerOrder, { ownerId })
    lu.assertNotNil(dispatcher.handlers[ownerId])
    lu.assertEquals(self.env[path]("x"), "first:base:x")

    self:createHostWithHooks(pluginGuid, nil)

    lu.assertEquals(self.env[path]("x"), "base:x")
    lu.assertEquals(dispatcher.ownerOrder, {})
    lu.assertNil(dispatcher.ownerSeen[ownerId])
    lu.assertNil(dispatcher.handlers[ownerId])
    lu.assertNil(self.hookRegistry.ownerSlots[ownerId])

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.wrap(path, function(base, value)
            return "second:" .. base(value)
        end)
    end)

    lu.assertEquals(self.counts.wrap, 1)
    lu.assertEquals(dispatcher.ownerOrder, { ownerId })
    lu.assertEquals(self.env[path]("x"), "second:base:x")
end

function TestHooks:testHostHookDeclarationsAreStoredOnHostRegistry()
    local host, authorHost = self.moduleHost.create({
        pluginGuid = "hook-test-state-declarations",
        definition = self.moduleHost.prepareDefinition({}, { id = "HookTest", name = "Hook Test", storage = {} }),
        persistentState = createStore(false),
        stagedState = createStagedState(),
        drawTab = function() end,
    })

    authorHost.hooks.wrap("AdamantHookTestStateDeclarations", function(base)
        return base()
    end)

    local record = self.harness.hostRegistry.getRecord(host)
    lu.assertNotNil(record.hookDeclarations)
    lu.assertNotNil(record.hookDeclarations.wrap.AdamantHookTestStateDeclarations)
end

function TestHooks:testRetiredOverrideHostPrunesEmptyDispatcherPath()
    local pluginGuid = "hook-test-prune-override-dispatcher"
    local path = "AdamantHookTestPruneOverrideDispatcher"
    self.env[path] = function()
        return "base"
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.override(path, function()
            return "override"
        end)
    end)

    lu.assertNotNil(self.hookRegistry.dispatchers.override[path])
    lu.assertEquals(self.env[path](), "override")

    self:createHostWithHooks(pluginGuid, nil)

    lu.assertEquals(self.env[path](), "base")
    lu.assertNil(self.hookRegistry.dispatchers.override[path])
end

function TestHooks:testHostHooksDeclareAgainstAuthorHost()
    local pluginGuid = "hook-test-host-wrap"
    self.env.AdamantHookTestHostWrap = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.wrap("AdamantHookTestHostWrap", function(base, value)
            return "scoped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestHostWrap("x"), "scoped:base:x")
end

function TestHooks:testPublicHookApiIsNotExposed()
    lu.assertNil(self.public.hooks)
end

function TestHooks:testServiceSurfaceOnlyExposesHostInstallation()
    local hooks = self.harness.hooks

    lu.assertEquals(type(hooks.installForHost), "function")
    lu.assertNil(hooks.installModUtilWrap)
    lu.assertNil(hooks.installModUtilContextWrap)
    lu.assertNil(hooks.installPhysicalWrap)
    lu.assertNil(hooks.installPhysicalContextWrap)
    lu.assertNil(hooks.declareWrap)
    lu.assertNil(hooks.declareOverride)
    lu.assertNil(hooks.declareContextWrap)
end

function TestHooks:testSystemHooksDefineAgainstManagedSystemScope()
    self.env.AdamantHookTestSystemWrap = function(value)
        return "base:" .. value
    end

    local system = self.harness.createSystem("test.system.hooks")
    system.hooks.define(function(hooks)
        hooks.wrap("AdamantHookTestSystemWrap", function(base, value)
            return "system:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestSystemWrap("x"), "system:base:x")
end

function TestHooks:testSystemHooksDefineRemovesOmittedDeclarations()
    self.env.AdamantHookTestSystemOmit = function(value)
        return "base:" .. value
    end

    local system = self.harness.createSystem("test.system.hooks.omit")
    system.hooks.define(function(hooks)
        hooks.wrap("AdamantHookTestSystemOmit", function(base, value)
            return "system:" .. base(value)
        end)
    end)
    lu.assertEquals(self.env.AdamantHookTestSystemOmit("x"), "system:base:x")

    system.hooks.define(function() end)

    lu.assertEquals(self.env.AdamantHookTestSystemOmit("x"), "base:x")
end

function TestHooks:testHostHookDeclarationsRejectAfterActivation()
    local host, authorHost = self.moduleHost.create({
        pluginGuid = "hook-test-declare-after-activation",
        definition = self.moduleHost.prepareDefinition({}, { id = "HookTest", name = "Hook Test", storage = {} }),
        persistentState = createStore(false),
        stagedState = createStagedState(),
        drawTab = function() end,
    })
    self.moduleHost.activateOrThrow(host)

    lu.assertErrorMsgContains("cannot be called after host activation", function()
        authorHost.hooks.wrap("AdamantHookTestNoContext", function(base)
            return base()
        end)
    end)
end

function TestHooks:testExplicitHookKeysMustBeNonEmptyStrings()
    lu.assertErrorMsgContains("explicit key must be a non-empty string", function()
        self:createHostWithHooks("hook-test-invalid-wrap-key", function(host)
            host.hooks.wrap("AdamantHookTestInvalidWrapKey", {}, function(base)
                return base()
            end)
        end)
    end)

    lu.assertErrorMsgContains("explicit key must be a non-empty string", function()
        self:createHostWithHooks("hook-test-invalid-override-key", function(host)
            host.hooks.override("AdamantHookTestInvalidOverrideKey", "", function()
                return "override"
            end)
        end)
    end)

    lu.assertErrorMsgContains("explicit key must be a non-empty string", function()
        self:createHostWithHooks("hook-test-invalid-context-key", function(host)
            host.hooks.contextWrap("AdamantHookTestInvalidContextKey", function() end, function() end)
        end)
    end)
end

function TestHooks:testOverrideRequiresFunctionReplacement()
    self.env.AdamantHookTestOverrideFunctionRequired = function()
        return "base"
    end

    local ok = pcall(function()
        self:createHostWithHooks("hook-test-override-function-required", function(host)
            host.hooks.override("AdamantHookTestOverrideFunctionRequired", "not-a-function")
        end)
    end)

    lu.assertFalse(ok)
    lu.assertEquals(self.env.AdamantHookTestOverrideFunctionRequired(), "base")
end

function TestHooks:testOverrideFunctionRegistersOnceAndUpdatesReplacement()
    self.env.AdamantHookTestOverride = function()
        return "base"
    end

    self:createHostWithHooks("hook-test-override-update", function(host)
        host.hooks.override("AdamantHookTestOverride", function()
            return "first"
        end)
        host.hooks.override("AdamantHookTestOverride", function()
            return "second"
        end)
    end)

    lu.assertEquals(self.counts.override, 1)
    lu.assertEquals(self.env.AdamantHookTestOverride(), "second")
end

function TestHooks:testOverrideRefreshOmissionRestoresOriginal()
    local pluginGuid = "hook-test-override-refresh"
    self.env.AdamantHookTestOverrideRefresh = function()
        return "base"
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.override("AdamantHookTestOverrideRefresh", function()
            return "override"
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestOverrideRefresh(), "override")

    self:createHostWithHooks(pluginGuid, function() end)

    lu.assertEquals(self.counts.restore, 1)
    lu.assertEquals(self.env.AdamantHookTestOverrideRefresh(), "base")
end

function TestHooks:testContextWrapRegistersOnceAndUpdatesContext()
    local observed = {}

    self.env.AdamantHookTestContext = function()
        table.insert(observed, "base")
    end

    self:createHostWithHooks("hook-test-context-update", function(host)
        host.hooks.contextWrap("AdamantHookTestContext", function()
            table.insert(observed, "first")
        end)
        host.hooks.contextWrap("AdamantHookTestContext", function()
            table.insert(observed, "second")
        end)
    end)

    self.env.AdamantHookTestContext()

    lu.assertEquals(self.counts.contextWrap, 1)
    lu.assertEquals(observed, { "second", "base" })
end

function TestHooks:testContextWrapRefreshOmissionBecomesInert()
    local pluginGuid = "hook-test-context-refresh"
    local observed = {}

    self.env.AdamantHookTestContextRefresh = function()
        table.insert(observed, "base")
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.contextWrap("AdamantHookTestContextRefresh", function()
            table.insert(observed, "context")
        end)
    end)

    self:createHostWithHooks(pluginGuid, function() end)
    self.env.AdamantHookTestContextRefresh()

    lu.assertEquals(observed, { "base" })
end

function TestHooks:testRefreshFailureKeepsPreviousLiveHookState()
    local pluginGuid = "hook-test-refresh-failure"
    local observed = {}

    self.env.AdamantHookTestFailureWrap = function(value)
        return "base:" .. value
    end
    self.env.AdamantHookTestFailureOverride = function()
        return "base-override"
    end
    self.env.AdamantHookTestFailureContext = function()
        table.insert(observed, "base")
    end
    self.env.AdamantHookTestFailureNew = function(value)
        return "new-base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.wrap("AdamantHookTestFailureWrap", function(base, value)
            return "first:" .. base(value)
        end)
        host.hooks.override("AdamantHookTestFailureOverride", function()
            return "first-override"
        end)
        host.hooks.contextWrap("AdamantHookTestFailureContext", function()
            table.insert(observed, "first-context")
        end)
    end)

    local ok = pcall(function()
        self:createHostWithHooks(pluginGuid, function(host)
            host.hooks.wrap("AdamantHookTestFailureWrap", function(base, value)
                return "second:" .. base(value)
            end)
            host.hooks.override("AdamantHookTestFailureOverride", function()
                return "second-override"
            end)
            host.hooks.contextWrap("AdamantHookTestFailureContext", function()
                table.insert(observed, "second-context")
            end)
            host.hooks.wrap("AdamantHookTestFailureNew", function(base, value)
                return "new:" .. base(value)
            end)
            error("boom")
        end)
    end)

    observed = {}
    self.env.AdamantHookTestFailureContext()

    lu.assertFalse(ok)
    lu.assertEquals(self.counts.wrap, 1)
    lu.assertEquals(self.counts.override, 1)
    lu.assertEquals(self.counts.contextWrap, 1)
    lu.assertEquals(self.env.AdamantHookTestFailureWrap("x"), "first:base:x")
    lu.assertEquals(self.env.AdamantHookTestFailureOverride(), "first-override")
    lu.assertEquals(observed, { "first-context", "base" })
    lu.assertEquals(self.env.AdamantHookTestFailureNew("x"), "new-base:x")
end

function TestHooks:testActivationFailureAfterHookRefreshRestoresPreviousLiveHookState()
    local pluginGuid = "hook-test-activation-rollback"
    self.env.AdamantHookTestActivationRollback = function(value)
        return "base:" .. value
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.wrap("AdamantHookTestActivationRollback", function(base, value)
            return "first:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestActivationRollback("x"), "first:base:x")

    local ok = pcall(function()
        self:createHostWithHooks(pluginGuid, function(host)
            host.hooks.wrap("AdamantHookTestActivationRollback", function(base, value)
                return "second:" .. base(value)
            end)
        end, {
            enabled = true,
            patchMutation = function()
                error("late activation boom")
            end,
        })
    end)

    lu.assertFalse(ok)
    lu.assertEquals(self.env.AdamantHookTestActivationRollback("x"), "first:base:x")
end

function TestHooks:testHookCommitFailureRemovesPartiallyInstalledCandidateSlots()
    local pluginGuid = "hook-test-partial-commit-rollback"
    local wrapPath = "AdamantHookTestPartialCommitWrap"
    local overridePath = "AdamantHookTestPartialCommitOverride"
    self.env[wrapPath] = function(value)
        return "base:" .. value
    end
    self.env[overridePath] = function()
        return "base-override"
    end

    self:createHostWithHooks(pluginGuid, function(host)
        host.hooks.wrap(wrapPath, function(base, value)
            return "first:" .. base(value)
        end)
    end)

    self.counts.modutil.Path.Override = function()
        error("override install boom")
    end

    local ok = pcall(function()
        self:createHostWithHooks(pluginGuid, function(host)
            host.hooks.wrap(wrapPath, function(base, value)
                return "candidate:" .. base(value)
            end)
            host.hooks.override(overridePath, function()
                return "candidate-override"
            end)
        end)
    end)

    lu.assertFalse(ok)
    lu.assertEquals(self.env[wrapPath]("x"), "first:base:x")
end

function TestHooks:testCreateModuleHostSyncsCoordinatedRuntimeImmediately()
    local packId = "hook-pack"
    local buildCalls = 0
    local target = { Value = "base" }
    self.coordinator.register(packId, { ModEnabled = true })

    local definition = self.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local host, authorHost = self.moduleHost.create({
        pluginGuid = "hook-pack.Alpha",
        definition = definition,
        persistentState = createStore(true),
        stagedState = createStagedState(),
        drawTab = function() end,
    })
    authorHost.mutation.patch(function(plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", "patched")
    end)
    self.moduleHost.activateOrThrow(host)

    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "patched")
end

function TestHooks:testCreateModuleHostHotReloadReplacesCoordinatedRuntimeState()
    local packId = "hook-reload-pack"
    local firstBuildCalls = 0
    local secondBuildCalls = 0
    local target = { Value = "base" }
    self.coordinator.register(packId, { ModEnabled = true })

    local store = createStore(true)

    local firstDefinition = self.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local firstHost, firstAuthorHost = self.moduleHost.create({
        pluginGuid = "hook-reload-pack.Alpha",
        definition = firstDefinition,
        persistentState = store,
        stagedState = createStagedState(),
        drawTab = function() end,
    })
    firstAuthorHost.mutation.patch(function(plan)
        firstBuildCalls = firstBuildCalls + 1
        plan:set(target, "Value", "first")
    end)
    self.moduleHost.activateOrThrow(firstHost)

    local secondDefinition = self.moduleHost.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local secondHost, secondAuthorHost = self.moduleHost.create({
        pluginGuid = "hook-reload-pack.Alpha",
        definition = secondDefinition,
        persistentState = store,
        stagedState = createStagedState(),
        drawTab = function() end,
    })
    secondAuthorHost.mutation.patch(function(plan)
        secondBuildCalls = secondBuildCalls + 1
        plan:set(target, "Value", "second")
    end)
    self.moduleHost.activateOrThrow(secondHost)

    lu.assertEquals(firstBuildCalls, 1)
    lu.assertEquals(secondBuildCalls, 1)
    lu.assertEquals(target.Value, "second")

    local mutationHost = {
        getHostId = function()
            return "hook-reload-pack.Alpha"
        end,
    }
    self.harness.hostRegistry.setRecord(mutationHost, {
        pluginGuid = "hook-reload-pack.Alpha",
        definition = {
            modpack = packId,
            id = "Alpha",
            name = "Alpha",
            storage = {},
        },
        mutationBundle = {
            patchMutation = function(plan)
                plan:set(target, "Value", "second")
            end,
        },
        authorHost = nil,
        store = store,
    })

    self.mutation.revertForHost(mutationHost)
    lu.assertEquals(target.Value, "base")
end
