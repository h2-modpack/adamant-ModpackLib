local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestCache = {}

function TestCache:setUp()
    self.harness = createLibHarness()
end

local function activateAndEnableModule(harness, module, pluginGuid)
    lu.assertTrue(module.activate())
    local liveModule = harness.managedModule.getLiveModule(pluginGuid)
    lu.assertNotNil(liveModule)
    lu.assertTrue(liveModule.setEnabled(true))
    return liveModule
end

local function getLiveStore(harness, pluginGuid)
    local liveModule = harness.managedModule.getLiveModule(pluginGuid)
    local record = harness.managedModule.getRecord(liveModule)
    return record and record.store or nil
end

local function createCacheModule(harness, pluginGuid, opts)
    opts = opts or {}
    local module, err = harness.public.createModule({
        pluginGuid = pluginGuid,
        config = opts.config or {},
        modpack = "test-pack",
        id = opts.id or ("Cache" .. tostring(pluginGuid):gsub("[^%w_]", "")),
        name = opts.name or pluginGuid,
    })
    if not module then
        return nil, err
    end
    if opts.cache ~= nil then
        module.cache.define(opts.cache)
    end
    module.ui.tab(function(callbackHost, ui)
        return (opts.drawTab or function() end)(ui.draw, ui.data, ui.actions, ui, callbackHost)
    end)
    return module, nil
end

function TestCache:testDeclaredCacheIsStoreOnlyAndNotUiData()
    self.harness.game.CurrentRun = {}
    local capturedState = nil
    local module = createCacheModule(self.harness, "test-cache-declared-store-only", {
        cache = {
            RunScratch = {
                domain = "currentRun",
                key = "run",
                factory = function()
                    return {}
                end,
            },
        },
        drawTab = function(_, state)
            capturedState = state
            lu.assertNil(state.cache)
        end,
    })

    local liveModule = activateAndEnableModule(self.harness, module, "test-cache-declared-store-only")
    local store = getLiveStore(self.harness, "test-cache-declared-store-only")
    liveModule.drawTab()

    lu.assertNotNil(capturedState)
    lu.assertEquals(store.cache.currentRun.get("RunScratch"), {})
end

function TestCache:testDeclaredCurrentRunCacheCreatesNamespacedStateOnce()
    self.harness.game.CurrentRun = {}
    local calls = 0
    local module = createCacheModule(self.harness, "test-cache-declared-current-run-once", {
        cache = {
            RunScratch = {
                domain = "currentRun",
                key = "run",
                factory = function()
                    calls = calls + 1
                    return {
                        Count = 1,
                    }
                end,
            },
        },
    })
    activateAndEnableModule(self.harness, module, "test-cache-declared-current-run-once")
    local store = getLiveStore(self.harness, "test-cache-declared-current-run-once")

    local first = store.cache.currentRun.get("RunScratch")
    first.Count = 2
    local second = store.cache.currentRun.get("RunScratch")

    lu.assertEquals(calls, 1)
    lu.assertIs(first, second)
    lu.assertEquals(second.Count, 2)
    lu.assertNotNil(self.harness.game.CurrentRun._AdamantModpackLibCache)
end

function TestCache:testDeclaredCurrentRunCacheIsStoreOnly()
    self.harness.game.CurrentRun = {}
    local drawHasCurrentRunCache = nil
    local module = createCacheModule(self.harness, "test-cache-declared-current-run", {
        id = "DeclaredCurrentRunCacheModule",
        name = "Declared Current Run Cache Module",
        cache = {
            RunScratch = {
                domain = "currentRun",
                key = "run",
                factory = function()
                    return {
                        Count = 0,
                    }
                end,
            },
        },
        drawTab = function(_, state)
            drawHasCurrentRunCache = state.cache ~= nil
        end,
    })

    activateAndEnableModule(self.harness, module, "test-cache-declared-current-run")
    local store = getLiveStore(self.harness, "test-cache-declared-current-run")
    store.cache.currentRun.get("RunScratch").Count = 2
    lu.assertTrue(store.cache.currentRun.clear("RunScratch"))
    lu.assertEquals(store.cache.currentRun.get("RunScratch").Count, 0)

    self.harness.managedModule.getLiveModule("test-cache-declared-current-run").drawTab()
    lu.assertFalse(drawHasCurrentRunCache)
end

function TestCache:testDeclaredCurrentRunCacheRejectsInvalidInputs()
    self.harness.game.CurrentRun = {}

    local module = createCacheModule(self.harness, "test-cache-current-run-invalid-factory", {
        cache = {
            RunScratch = {
                domain = "currentRun",
                key = "run",
                factory = true,
            },
        },
    })
    local ok = module.activate()
    lu.assertFalse(ok)

    lu.assertErrorMsgContains("factory must return a table", function()
        local invalidModule = createCacheModule(self.harness, "test-cache-current-run-invalid-return", {
            cache = {
                RunScratch = {
                    domain = "currentRun",
                    key = "run",
                    factory = function()
                        return true
                    end,
                },
            },
        })
        lu.assertTrue(invalidModule.activate())
        local store = getLiveStore(self.harness, "test-cache-current-run-invalid-return")
        store.cache.currentRun.get("RunScratch")
    end)
end

function TestCache:testPersistentCacheDomainIsRejected()
    local module = createCacheModule(self.harness, "test-cache-persistent-domain", {
        cache = {
            RecordingReady = {
                domain = "persistent",
                key = "RecordingReady",
                default = false,
            },
        },
    })

    local ok = module.activate()
    lu.assertFalse(ok)
end
