local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestCache = {}

function TestCache:setUp()
    self.harness = createLibHarness()
end

local function activateAndEnableHost(harness, host, pluginGuid)
    lu.assertTrue(host.activate())
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
    local host, err = harness.public.createModule({
        pluginGuid = pluginGuid,
        config = opts.config or {},
        modpack = "test-pack",
        id = opts.id or ("Cache" .. tostring(pluginGuid):gsub("[^%w_]", "")),
        name = opts.name or pluginGuid,
    })
    if not host then
        return nil, err
    end
    if opts.cache ~= nil then
        host.cache.define(opts.cache)
    end
    host.ui.tab(function(callbackHost, ui)
        return (opts.drawTab or function() end)(ui.draw, ui.data, ui.actions, ui, callbackHost)
    end)
    return host, nil
end

function TestCache:testDeclaredCacheIsStoreOnlyAndNotUiData()
    self.harness.game.CurrentRun = {}
    local capturedState = nil
    local host = createCacheModule(self.harness, "test-cache-declared-store-only", {
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

    local liveModule = activateAndEnableHost(self.harness, host, "test-cache-declared-store-only")
    local store = getLiveStore(self.harness, "test-cache-declared-store-only")
    liveModule.drawTab()

    lu.assertNotNil(capturedState)
    lu.assertEquals(store.cache.currentRun.get("RunScratch"), {})
end

function TestCache:testDeclaredCurrentRunCacheCreatesNamespacedStateOnce()
    self.harness.game.CurrentRun = {}
    local calls = 0
    local host = createCacheModule(self.harness, "test-cache-declared-current-run-once", {
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
    activateAndEnableHost(self.harness, host, "test-cache-declared-current-run-once")
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
    local host = createCacheModule(self.harness, "test-cache-declared-current-run", {
        id = "DeclaredCurrentRunCacheHost",
        name = "Declared Current Run Cache Host",
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

    activateAndEnableHost(self.harness, host, "test-cache-declared-current-run")
    local store = getLiveStore(self.harness, "test-cache-declared-current-run")
    store.cache.currentRun.get("RunScratch").Count = 2
    lu.assertTrue(store.cache.currentRun.clear("RunScratch"))
    lu.assertEquals(store.cache.currentRun.get("RunScratch").Count, 0)

    self.harness.managedModule.getLiveModule("test-cache-declared-current-run").drawTab()
    lu.assertFalse(drawHasCurrentRunCache)
end

function TestCache:testDeclaredCurrentRunCacheRejectsInvalidInputs()
    self.harness.game.CurrentRun = {}

    local host = createCacheModule(self.harness, "test-cache-current-run-invalid-factory", {
        cache = {
            RunScratch = {
                domain = "currentRun",
                key = "run",
                factory = true,
            },
        },
    })
    local ok = host.activate()
    lu.assertFalse(ok)

    lu.assertErrorMsgContains("factory must return a table", function()
        local invalidHost = createCacheModule(self.harness, "test-cache-current-run-invalid-return", {
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
        lu.assertTrue(invalidHost.activate())
        local store = getLiveStore(self.harness, "test-cache-current-run-invalid-return")
        store.cache.currentRun.get("RunScratch")
    end)
end

function TestCache:testPersistentCacheDomainIsRejected()
    local host = createCacheModule(self.harness, "test-cache-persistent-domain", {
        cache = {
            RecordingReady = {
                domain = "persistent",
                key = "RecordingReady",
                default = false,
            },
        },
    })

    local ok = host.activate()
    lu.assertFalse(ok)
end
