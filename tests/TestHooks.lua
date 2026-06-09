local lu = require("luaunit")
local createLibHarness = require('tests/harness/create_lib_harness')
local unpackValues = table.unpack or _G.unpack

TestHooks = {}

local function createPathMock(target)
    local counts = {
        wrap = 0,
        override = 0,
        restore = 0,
        contextWrap = 0,
    }
    local originals = {}
    local activeContext = nil

    local function getEnv()
        return assert(target.env, "hook test env missing")
    end

    local function wrapScopedChain(base, wraps)
        local chain = base
        for i = 1, #wraps do
            local handler = wraps[i].handler
            local previous = chain
            chain = function(...)
                return handler(previous, ...)
            end
        end
        return chain
    end

    local function pack(...)
        return {
            n = select("#", ...),
            ...
        }
    end

    local testModUtil = {
        Path = {
            Wrap = function(path, handler)
                counts.wrap = counts.wrap + 1
                if activeContext then
                    table.insert(activeContext.wraps, {
                        path = path,
                        handler = handler,
                    })
                    return
                end
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
                        local scopedContext = { wraps = {} }
                        local previousContext = activeContext
                        activeContext = scopedContext
                        local contextResults = pack(pcall(context, ...))
                        activeContext = previousContext
                        if not contextResults[1] then
                            error(contextResults[2], 0)
                        end

                        local restored = {}
                        for _, wrap in ipairs(scopedContext.wraps) do
                            local current = env[wrap.path]
                            restored[wrap.path] = restored[wrap.path] or current
                            env[wrap.path] = wrapScopedChain(current, { wrap })
                        end

                        local results = pack(base(...))
                        for wrapPath, original in pairs(restored) do
                            env[wrapPath] = original
                        end
                        return unpackValues(results, 1, results.n)
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
    self.managedModule = self.harness.managedModule
    self.mutation = self.harness.mutation
    self.hookRegistry = self.harness.registry.hooks
end

function TestHooks:createModuleWithHooks(pluginGuid, registerHooks, activationOpts)
    activationOpts = activationOpts or {}
    local store = createStore(activationOpts.enabled == true)
    local hookDeclarations = self.harness.hooksBundle.declarations.create()
    local mutationBundle = {
        patchMutation = activationOpts.patchMutation,
    }
    local host = self.managedModule.create({
        pluginGuid = pluginGuid,
        definition = self.managedModule.prepareDefinition({}, { id = "HookTest", name = "Hook Test", storage = {} }),
        persistentState = store,
        stagedState = createStagedState(),
        hookDeclarations = hookDeclarations,
        mutationBundle = mutationBundle,
        drawTab = function() end,
    })
    if registerHooks ~= nil then
        registerHooks(self.harness.hooksBundle.declarations.createRegistrar(hookDeclarations, "module.hooks"), store)
    end
    return self.managedModule.activateOrThrow(host)
end

function TestHooks:testWrapRegistersOnceAndUpdatesHandler()
    self.env.AdamantHookTestWrap = function(value)
        return "base:" .. value
    end

    self:createModuleWithHooks("hook-test-wrap-update", function(host)
        host.wrap("AdamantHookTestWrap", function(base, value)
            return "first:" .. base(value)
        end)
        host.wrap("AdamantHookTestWrap", function(base, value)
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

    self:createModuleWithHooks("hook-test-wrap-injected-modutil", function(host)
        host.wrap("AdamantHookTestWrapInjected", function(base, value)
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

    self:createModuleWithHooks(pluginGuid, function(host)
        host.wrap("AdamantHookTestWrapRefresh", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestWrapRefresh("x"), "wrapped:base:x")

    self:createModuleWithHooks(pluginGuid, function() end)

    lu.assertEquals(self.env.AdamantHookTestWrapRefresh("x"), "base:x")
end

function TestHooks:testMissingRegisterHooksRefreshRemovesPreviousHooks()
    local pluginGuid = "hook-test-missing-register-hooks"
    self.env.AdamantHookTestMissingRegisterHooks = function(value)
        return "base:" .. value
    end

    self:createModuleWithHooks(pluginGuid, function(host)
        host.wrap("AdamantHookTestMissingRegisterHooks", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestMissingRegisterHooks("x"), "wrapped:base:x")

    self:createModuleWithHooks(pluginGuid, nil)

    lu.assertEquals(self.env.AdamantHookTestMissingRegisterHooks("x"), "base:x")
end

function TestHooks:testRetiredHookModulePrunesDeadDispatcherOwnerEntries()
    local pluginGuid = "hook-test-prune-dispatcher"
    local ownerId = pluginGuid
    local path = "AdamantHookTestPruneDispatcher"
    self.env[path] = function(value)
        return "base:" .. value
    end

    self:createModuleWithHooks(pluginGuid, function(host)
        host.wrap(path, function(base, value)
            return "first:" .. base(value)
        end)
    end)
    local dispatcher = self.hookRegistry.dispatchers.wrap[path]

    lu.assertNotNil(dispatcher)
    lu.assertEquals(dispatcher.ownerOrder, { ownerId })
    lu.assertNotNil(dispatcher.handlers[ownerId])
    lu.assertEquals(self.env[path]("x"), "first:base:x")

    self:createModuleWithHooks(pluginGuid, nil)

    lu.assertEquals(self.env[path]("x"), "base:x")
    lu.assertEquals(dispatcher.ownerOrder, {})
    lu.assertNil(dispatcher.ownerSeen[ownerId])
    lu.assertNil(dispatcher.handlers[ownerId])
    lu.assertNil(self.hookRegistry.ownerSlots[ownerId])

    self:createModuleWithHooks(pluginGuid, function(host)
        host.wrap(path, function(base, value)
            return "second:" .. base(value)
        end)
    end)

    lu.assertEquals(self.counts.wrap, 1)
    lu.assertEquals(dispatcher.ownerOrder, { ownerId })
    lu.assertEquals(self.env[path]("x"), "second:base:x")
end

function TestHooks:testModuleHookDeclarationsAreStoredOnModuleRegistry()
    local hookDeclarations = self.harness.hooksBundle.declarations.create()
    local host = self.managedModule.create({
        pluginGuid = "hook-test-state-declarations",
        definition = self.managedModule.prepareDefinition({}, { id = "HookTest", name = "Hook Test", storage = {} }),
        persistentState = createStore(false),
        stagedState = createStagedState(),
        hookDeclarations = hookDeclarations,
        drawTab = function() end,
    })

    self.harness.hooksBundle.declarations.declareWrap(hookDeclarations, "module.hooks.wrap",
        "AdamantHookTestStateDeclarations", function(base)
        return base()
    end)

    local record = self.harness.moduleRegistry.getRecord(host)
    lu.assertNotNil(record.hookDeclarations)
    lu.assertNotNil(record.hookDeclarations.wrap.AdamantHookTestStateDeclarations)
end

function TestHooks:testRetiredOverrideModulePrunesEmptyDispatcherPath()
    local pluginGuid = "hook-test-prune-override-dispatcher"
    local path = "AdamantHookTestPruneOverrideDispatcher"
    self.env[path] = function()
        return "base"
    end

    self:createModuleWithHooks(pluginGuid, function(host)
        host.override(path, function()
            return "override"
        end)
    end)

    lu.assertNotNil(self.hookRegistry.dispatchers.override[path])
    lu.assertEquals(self.env[path](), "override")

    self:createModuleWithHooks(pluginGuid, nil)

    lu.assertEquals(self.env[path](), "base")
    lu.assertNil(self.hookRegistry.dispatchers.override[path])
end

function TestHooks:testModuleHooksDeclareAgainstAuthorModule()
    local pluginGuid = "hook-test-host-wrap"
    self.env.AdamantHookTestHostWrap = function(value)
        return "base:" .. value
    end

    self:createModuleWithHooks(pluginGuid, function(host)
        host.wrap("AdamantHookTestHostWrap", function(base, value)
            return "scoped:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestHostWrap("x"), "scoped:base:x")
end

function TestHooks:testPublicHookApiIsNotExposed()
    lu.assertNil(self.public.hooks)
end

function TestHooks:testServiceSurfaceOnlyExposesModuleInstallation()
    local hooks = self.harness.hooks

    lu.assertEquals(type(hooks.installForModule), "function")
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

function TestHooks:testModuleHookDeclarationsRejectAfterActivation()
    local authorModule = self.public.createModule({
        pluginGuid = "hook-test-declare-after-activation",
        config = {
            Enabled = false,
            DebugMode = false,
        },
        id = "HookTest",
        name = "Hook Test",
    })
    authorModule.ui.tab(function() end)
    lu.assertTrue(authorModule.activate())

    lu.assertErrorMsgContains("cannot be called after module activation begins", function()
        authorModule.hooks.wrap("AdamantHookTestNoContext", function(_, _, base)
            return base()
        end)
    end)
end

function TestHooks:testExplicitHookKeysMustBeNonEmptyStrings()
    lu.assertErrorMsgContains("explicit key must be a non-empty string", function()
        self:createModuleWithHooks("hook-test-invalid-wrap-key", function(host)
            host.wrap("AdamantHookTestInvalidWrapKey", {}, function(base)
                return base()
            end)
        end)
    end)

    lu.assertErrorMsgContains("explicit key must be a non-empty string", function()
        self:createModuleWithHooks("hook-test-invalid-override-key", function(host)
            host.override("AdamantHookTestInvalidOverrideKey", "", function()
                return "override"
            end)
        end)
    end)

    lu.assertErrorMsgContains("explicit key must be a non-empty string", function()
        self:createModuleWithHooks("hook-test-invalid-context-key", function(host)
            host.contextWrap("AdamantHookTestInvalidContextKey", function() end, function() end)
        end)
    end)
end

function TestHooks:testOverrideRequiresFunctionReplacement()
    self.env.AdamantHookTestOverrideFunctionRequired = function()
        return "base"
    end

    local ok = pcall(function()
        self:createModuleWithHooks("hook-test-override-function-required", function(host)
            host.override("AdamantHookTestOverrideFunctionRequired", "not-a-function")
        end)
    end)

    lu.assertFalse(ok)
    lu.assertEquals(self.env.AdamantHookTestOverrideFunctionRequired(), "base")
end

function TestHooks:testOverrideFunctionRegistersOnceAndUpdatesReplacement()
    self.env.AdamantHookTestOverride = function()
        return "base"
    end

    self:createModuleWithHooks("hook-test-override-update", function(host)
        host.override("AdamantHookTestOverride", function()
            return "first"
        end)
        host.override("AdamantHookTestOverride", function()
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

    self:createModuleWithHooks(pluginGuid, function(host)
        host.override("AdamantHookTestOverrideRefresh", function()
            return "override"
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestOverrideRefresh(), "override")

    self:createModuleWithHooks(pluginGuid, function() end)

    lu.assertEquals(self.counts.restore, 1)
    lu.assertEquals(self.env.AdamantHookTestOverrideRefresh(), "base")
end

function TestHooks:testContextWrapRegistersOnceAndUpdatesContext()
    local observed = {}

    self.env.AdamantHookTestContext = function()
        table.insert(observed, "base")
    end

    self:createModuleWithHooks("hook-test-context-update", function(host)
        host.contextWrap("AdamantHookTestContext", function()
            table.insert(observed, "first")
        end)
        host.contextWrap("AdamantHookTestContext", function()
            table.insert(observed, "second")
        end)
    end)

    self.env.AdamantHookTestContext()

    lu.assertEquals(self.counts.contextWrap, 1)
    lu.assertEquals(observed, { "second", "base" })
end

function TestHooks:testContextWrapProvidesScopedWrapSurface()
    local observed = {}
    local capturedContext

    self.env.AdamantHookTestInnerContext = function(value)
        table.insert(observed, "inner:" .. tostring(value))
        return "inner:" .. tostring(value)
    end
    self.env.AdamantHookTestOuterContext = function(value)
        table.insert(observed, "outer:" .. tostring(value))
        return self.env.AdamantHookTestInnerContext(value)
    end

    local authorModule = self.public.createModule({
        pluginGuid = "hook-test-context-surface",
        config = {
            Enabled = false,
            DebugMode = false,
        },
        id = "HookTest",
        name = "Hook Test",
    })
    authorModule.ui.tab(function() end)
    authorModule.hooks.contextWrap("AdamantHookTestOuterContext", function(_, _, context)
        capturedContext = context
        context.wrap("AdamantHookTestInnerContext", function(base, value)
            table.insert(observed, "wrapped:" .. tostring(value))
            return "wrapped:" .. base(value)
        end)
    end)
    lu.assertTrue(authorModule.activate())

    lu.assertEquals(self.env.AdamantHookTestOuterContext("run"), "wrapped:inner:run")
    lu.assertEquals(self.env.AdamantHookTestInnerContext("direct"), "inner:direct")
    lu.assertEquals(self.counts.contextWrap, 1)
    lu.assertEquals(self.counts.wrap, 1)
    lu.assertErrorMsgContains("cannot be called after the context callback returns", function()
        capturedContext.wrap("AdamantHookTestInnerContext", function(base, value)
            return base(value)
        end)
    end)
    lu.assertEquals(observed, {
        "outer:run",
        "wrapped:run",
        "inner:run",
        "inner:direct",
    })
end

function TestHooks:testContextWrapRefreshOmissionBecomesInert()
    local pluginGuid = "hook-test-context-refresh"
    local observed = {}

    self.env.AdamantHookTestContextRefresh = function()
        table.insert(observed, "base")
    end

    self:createModuleWithHooks(pluginGuid, function(host)
        host.contextWrap("AdamantHookTestContextRefresh", function()
            table.insert(observed, "context")
        end)
    end)

    self:createModuleWithHooks(pluginGuid, function() end)
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

    self:createModuleWithHooks(pluginGuid, function(host)
        host.wrap("AdamantHookTestFailureWrap", function(base, value)
            return "first:" .. base(value)
        end)
        host.override("AdamantHookTestFailureOverride", function()
            return "first-override"
        end)
        host.contextWrap("AdamantHookTestFailureContext", function()
            table.insert(observed, "first-context")
        end)
    end)

    local ok = pcall(function()
        self:createModuleWithHooks(pluginGuid, function(host)
            host.wrap("AdamantHookTestFailureWrap", function(base, value)
                return "second:" .. base(value)
            end)
            host.override("AdamantHookTestFailureOverride", function()
                return "second-override"
            end)
            host.contextWrap("AdamantHookTestFailureContext", function()
                table.insert(observed, "second-context")
            end)
            host.wrap("AdamantHookTestFailureNew", function(base, value)
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

    self:createModuleWithHooks(pluginGuid, function(host)
        host.wrap("AdamantHookTestActivationRollback", function(base, value)
            return "first:" .. base(value)
        end)
    end)

    lu.assertEquals(self.env.AdamantHookTestActivationRollback("x"), "first:base:x")

    local ok = pcall(function()
        self:createModuleWithHooks(pluginGuid, function(host)
            host.wrap("AdamantHookTestActivationRollback", function(base, value)
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

    self:createModuleWithHooks(pluginGuid, function(host)
        host.wrap(wrapPath, function(base, value)
            return "first:" .. base(value)
        end)
    end)

    self.counts.modutil.Path.Override = function()
        error("override install boom")
    end

    local ok = pcall(function()
        self:createModuleWithHooks(pluginGuid, function(host)
            host.wrap(wrapPath, function(base, value)
                return "candidate:" .. base(value)
            end)
            host.override(overridePath, function()
                return "candidate-override"
            end)
        end)
    end)

    lu.assertFalse(ok)
    lu.assertEquals(self.env[wrapPath]("x"), "first:base:x")
end

function TestHooks:testManagedModuleSyncsCoordinatedRuntimeImmediately()
    local packId = "hook-pack"
    local buildCalls = 0
    local target = { Value = "base" }
    self.coordinator.register(packId, "Test Pack", { ModEnabled = true })

    local definition = self.managedModule.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local mutationBundle = {
        patchMutation = function(_, _, plan)
            buildCalls = buildCalls + 1
            plan:set(target, "Value", "patched")
        end,
    }
    local host = self.managedModule.create({
        pluginGuid = "hook-pack.Alpha",
        definition = definition,
        persistentState = createStore(true),
        stagedState = createStagedState(),
        mutationBundle = mutationBundle,
        drawTab = function() end,
    })
    self.managedModule.activateOrThrow(host)

    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "patched")
end

function TestHooks:testManagedModuleHotReloadReplacesCoordinatedRuntimeState()
    local packId = "hook-reload-pack"
    local firstBuildCalls = 0
    local secondBuildCalls = 0
    local target = { Value = "base" }
    self.coordinator.register(packId, "Test Pack", { ModEnabled = true })

    local store = createStore(true)

    local firstDefinition = self.managedModule.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local firstHost = self.managedModule.create({
        pluginGuid = "hook-reload-pack.Alpha",
        definition = firstDefinition,
        persistentState = store,
        stagedState = createStagedState(),
        mutationBundle = {
            patchMutation = function(_, _, plan)
                firstBuildCalls = firstBuildCalls + 1
                plan:set(target, "Value", "first")
            end,
        },
        drawTab = function() end,
    })
    self.managedModule.activateOrThrow(firstHost)

    local secondDefinition = self.managedModule.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local secondHost = self.managedModule.create({
        pluginGuid = "hook-reload-pack.Alpha",
        definition = secondDefinition,
        persistentState = store,
        stagedState = createStagedState(),
        mutationBundle = {
            patchMutation = function(_, _, plan)
                secondBuildCalls = secondBuildCalls + 1
                plan:set(target, "Value", "second")
            end,
        },
        drawTab = function() end,
    })
    self.managedModule.activateOrThrow(secondHost)

    lu.assertEquals(firstBuildCalls, 1)
    lu.assertEquals(secondBuildCalls, 1)
    lu.assertEquals(target.Value, "second")

    local mutationHost = {
        getOwnerId = function()
            return "hook-reload-pack.Alpha"
        end,
    }
    self.harness.moduleRegistry.setRecord(mutationHost, {
        pluginGuid = "hook-reload-pack.Alpha",
        definition = {
            modpack = packId,
            id = "Alpha",
            name = "Alpha",
            storage = {},
        },
        mutationBundle = {
            patchMutation = function(_, _, plan)
                plan:set(target, "Value", "second")
            end,
        },
        store = store,
    })

    self.mutation.revertForModule(mutationHost)
    lu.assertEquals(target.Value, "base")
end
