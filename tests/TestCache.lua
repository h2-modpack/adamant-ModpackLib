local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestCache = {}

function TestCache:setUp()
    self.harness = createLibHarness()
end

local function makeChalkConfig(harness)
    local raw = {
        entries = {},
        saved = 0,
    }

    function raw:bind(section, key, defaultValue, description)
        for descriptor in pairs(self.entries) do
            if descriptor.section == section and descriptor.key == key then
                error("duplicate config bind")
            end
        end

        local entry = {
            value = defaultValue,
            description = description or "",
            gets = 0,
        }
        function entry.get(entrySelf)
            entrySelf.gets = entrySelf.gets + 1
            return entrySelf.value
        end
        function entry.set(entrySelf, value)
            entrySelf.value = value
        end

        self.entries[{ section = section, key = key }] = entry
        return entry
    end

    function raw:save()
        self.saved = self.saved + 1
    end

    local wrapper = { __raw = raw }
    local chalk = harness.chalk
    local previousOriginal = chalk.original
    chalk.original = function(config)
        return config.__raw
    end

    return wrapper, raw, function()
        chalk.original = previousOriginal
    end
end

local function findSingleCacheEntry(raw)
    local cacheEntryCount = 0
    local cacheKey
    local cacheEntry
    for descriptor, entry in pairs(raw.entries) do
        if descriptor.section == "cache" then
            cacheEntryCount = cacheEntryCount + 1
            cacheKey = descriptor.key
            cacheEntry = entry
        end
    end
    lu.assertEquals(cacheEntryCount, 1)
    return cacheEntry, cacheKey
end

local function activateAndEnableHost(harness, host, pluginGuid)
    lu.assertTrue(host.activate())
    local fullHost = harness.moduleHost.getLiveHost(pluginGuid)
    lu.assertNotNil(fullHost)
    lu.assertTrue(fullHost.setEnabled(true))
    return fullHost
end

local function createCacheModule(harness, pluginGuid, opts)
    opts = opts or {}
    local host, store = harness.public.createModule({
        pluginGuid = pluginGuid,
        config = opts.config or {},
        modpack = "test-pack",
        id = opts.id or ("Cache" .. tostring(pluginGuid):gsub("[^%w_]", "")),
        name = opts.name or pluginGuid,
        cache = opts.cache,
        drawTab = opts.drawTab or function() end,
    })
    return host, store
end

function TestCache:testDeclaredPersistentCacheIsAvailableOnStore()
    local _, store = createCacheModule(self.harness, "test-cache-declared-persistent", {
        id = "DeclaredPersistentCacheHost",
        name = "Declared Persistent Cache Host",
        cache = {
            RecordingReady = {
                domain = "persistent",
                key = "RecordingReady",
                default = false,
            },
        },
    })

    lu.assertFalse(store.cache.persistent.read("RecordingReady"))
    lu.assertTrue(store.cache.persistent.set("RecordingReady", true))
    lu.assertTrue(store.cache.persistent.read("RecordingReady"))
    lu.assertTrue(store.cache.persistent.clear("RecordingReady"))
    lu.assertFalse(store.cache.persistent.read("RecordingReady"))
end

function TestCache:testDeclaredPersistentCachePreservesFalseAsPresentValue()
    local _, store = createCacheModule(self.harness, "test-cache-declared-persistent-false", {
        cache = {
            RecordingReady = {
                domain = "persistent",
                key = "RecordingReady",
                default = true,
            },
        },
    })

    lu.assertTrue(store.cache.persistent.set("RecordingReady", false))
    lu.assertFalse(store.cache.persistent.read("RecordingReady"))
end

function TestCache:testDeclaredPersistentCacheUsesChalkCacheSection()
    local config, raw, restoreChalk = makeChalkConfig(self.harness)
    local ok, storeOrErr = pcall(function()
        local _, store = createCacheModule(self.harness, "test-cache-declared-persistent-chalk", {
            config = config,
            id = "PersistentChalkCacheHost",
            name = "Persistent Chalk Cache Host",
            cache = {
                RecordingReady = {
                    domain = "persistent",
                    key = "RecordingReady",
                    default = true,
                },
            },
        })
        return store
    end)
    restoreChalk()

    lu.assertTrue(ok, tostring(storeOrErr))
    local store = storeOrErr
    lu.assertTrue(store.cache.persistent.set("RecordingReady", false))
    lu.assertFalse(store.cache.persistent.read("RecordingReady"))

    local entry, cacheKey = findSingleCacheEntry(raw)
    lu.assertFalse(entry:get())
    lu.assertStrContains(cacheKey, "test-cache-declared-persistent-chalk")
end

function TestCache:testDeclaredPersistentCacheDrawReadsRuntimeSnapshot()
    local config, raw, restoreChalk = makeChalkConfig(self.harness)
    local capturedDrawValue = nil
    local ok, host, store = pcall(function()
        return createCacheModule(self.harness, "test-cache-declared-persistent-shared-ref", {
            config = config,
            id = "PersistentSharedRefCacheHost",
            name = "Persistent Shared Ref Cache Host",
            cache = {
                RecordingReady = {
                    domain = "persistent",
                    key = "RecordingReady",
                    default = false,
                },
            },
            drawTab = function(_, state)
                capturedDrawValue = state.cache.persistent.read("RecordingReady")
            end,
        })
    end)
    restoreChalk()

    lu.assertTrue(ok, tostring(host))
    lu.assertTrue(store.cache.persistent.set("RecordingReady", true))
    local entry = findSingleCacheEntry(raw)
    lu.assertEquals(entry.gets, 0)

    activateAndEnableHost(self.harness, host, "test-cache-declared-persistent-shared-ref").drawTab()

    lu.assertTrue(capturedDrawValue)
    lu.assertEquals(entry.gets, 0)
end

function TestCache:testDeclaredPersistentCacheRejectsInvalidInputs()
    local _, store = createCacheModule(self.harness, "test-cache-declared-persistent-invalid", {
        cache = {
            RecordingReady = {
                domain = "persistent",
                key = "RecordingReady",
                default = false,
            },
        },
    })

    lu.assertErrorMsgContains("unknown cache declaration", function()
        store.cache.persistent.read("Missing")
    end)
    lu.assertErrorMsgContains("value must be a boolean, number, or string", function()
        store.cache.persistent.set("RecordingReady", {})
    end)
end

function TestCache:testDeclaredCacheSurfacesArePhaseGated()
    local capturedState = nil
    local drawReadValue = nil
    local host, store
    host, store = createCacheModule(self.harness, "test-cache-declared-phase-gating", {
        cache = {
            RecordingReady = {
                domain = "persistent",
                key = "RecordingReady",
                default = false,
            },
        },
        drawTab = function(_, state)
            capturedState = state
            drawReadValue = state.cache.persistent.read("RecordingReady")
            lu.assertErrorMsgContains("phase.invalid_runtime_access", function()
                store.cache.persistent.read("RecordingReady")
            end)
        end,
    })

    lu.assertTrue(store.cache.persistent.set("RecordingReady", true))
    local fullHost = activateAndEnableHost(self.harness, host, "test-cache-declared-phase-gating")
    fullHost.drawTab()

    lu.assertTrue(drawReadValue)
    lu.assertNotNil(capturedState)
    lu.assertErrorMsgContains("phase.invalid_ui_access", function()
        capturedState.cache.persistent.read("RecordingReady")
    end)
end

function TestCache:testDeclaredCurrentRunCacheCreatesNamespacedStateOnce()
    self.harness.game.CurrentRun = {}
    local calls = 0
    local _, store = createCacheModule(self.harness, "test-cache-declared-current-run-once", {
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
    local host, store = createCacheModule(self.harness, "test-cache-declared-current-run", {
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
            drawHasCurrentRunCache = state.cache.currentRun ~= nil
        end,
    })

    store.cache.currentRun.get("RunScratch").Count = 2
    lu.assertTrue(store.cache.currentRun.clear("RunScratch"))
    lu.assertEquals(store.cache.currentRun.get("RunScratch").Count, 0)

    activateAndEnableHost(self.harness, host, "test-cache-declared-current-run")
    self.harness.moduleHost.getLiveHost("test-cache-declared-current-run").drawTab()
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
    lu.assertNil(host)

    lu.assertErrorMsgContains("factory must return a table", function()
        local _, store = createCacheModule(self.harness, "test-cache-current-run-invalid-return", {
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
        store.cache.currentRun.get("RunScratch")
    end)
end

function TestCache:testDeclaredSharedCachePublishesOwnerAndDrawWrites()
    local publisher = createCacheModule(self.harness, "test-cache-declared-shared-publisher", {
        id = "DeclaredSharedPublisher",
        name = "Declared Shared Publisher",
        cache = {
            Active = {
                domain = "shared",
                id = "test.declared.shared.active",
                access = "owner",
                default = false,
            },
        },
        drawTab = function(_, state)
            state.cache.shared.set("Active", true)
        end,
    })
    local _, readerStore = createCacheModule(self.harness, "test-cache-declared-shared-reader", {
        id = "DeclaredSharedReader",
        name = "Declared Shared Reader",
        cache = {
            Active = {
                domain = "shared",
                id = "test.declared.shared.active",
                access = "reader",
                fallback = false,
            },
        },
    })

    activateAndEnableHost(self.harness, publisher, "test-cache-declared-shared-publisher")
    lu.assertFalse(readerStore.cache.shared.read("Active"))

    self.harness.moduleHost.getLiveHost("test-cache-declared-shared-publisher").drawTab()
    lu.assertTrue(readerStore.cache.shared.read("Active"))
    lu.assertErrorMsgContains("does not support set", function()
        readerStore.cache.shared.set("Active", false)
    end)
end

function TestCache:testDeclaredSharedCacheReadsTableViews()
    local publisher = createCacheModule(self.harness, "test-cache-declared-shared-table-publisher", {
        id = "DeclaredSharedTablePublisher",
        name = "Declared Shared Table Publisher",
        cache = {
            Availability = {
                domain = "shared",
                id = "test.declared.shared.availability",
                access = "owner",
                default = {
                    active = false,
                    available = {},
                },
            },
        },
        drawTab = function(_, state)
            state.cache.shared.set("Availability", {
                active = true,
                available = {
                    Apollo = false,
                },
            })
        end,
    })
    local _, readerStore = createCacheModule(self.harness, "test-cache-declared-shared-table-reader", {
        id = "DeclaredSharedTableReader",
        name = "Declared Shared Table Reader",
        cache = {
            Availability = {
                domain = "shared",
                id = "test.declared.shared.availability",
                access = "reader",
                fallback = {
                    active = false,
                    available = {},
                },
            },
        },
    })

    activateAndEnableHost(self.harness, publisher, "test-cache-declared-shared-table-publisher")
    lu.assertFalse(readerStore.cache.shared.read("Availability").active)

    self.harness.moduleHost.getLiveHost("test-cache-declared-shared-table-publisher").drawTab()
    local availability = readerStore.cache.shared.read("Availability")
    lu.assertTrue(availability.active)
    lu.assertFalse(availability.available.Apollo)
    lu.assertErrorMsgContains("read-only", function()
        availability.available.Apollo = true
    end)
end

function TestCache:testDeclaredSharedCacheOwnerWritesCopyTables()
    local publisher, publisherStore = createCacheModule(self.harness, "test-cache-declared-shared-copy-publisher", {
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.declared.shared.copy",
                access = "owner",
                default = {},
            },
        },
    })
    local _, readerStore = createCacheModule(self.harness, "test-cache-declared-shared-copy-reader", {
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.declared.shared.copy",
                access = "reader",
                fallback = {},
            },
        },
    })

    local snapshot = {
        nested = {
            value = 1,
        },
    }
    activateAndEnableHost(self.harness, publisher, "test-cache-declared-shared-copy-publisher")
    lu.assertTrue(publisherStore.cache.shared.set("Snapshot", snapshot))
    snapshot.nested.value = 2

    local firstRead = readerStore.cache.shared.read("Snapshot")
    lu.assertEquals(firstRead.nested.value, 1)
    lu.assertErrorMsgContains("read-only", function()
        firstRead.nested.value = 3
    end)

    local secondRead = readerStore.cache.shared.read("Snapshot")
    lu.assertEquals(secondRead.nested.value, 1)
end

function TestCache:testDeclaredSharedCacheRejectsInvalidValues()
    local _, store = createCacheModule(self.harness, "test-cache-declared-shared-invalid", {
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.declared.shared.invalid",
                access = "owner",
            },
        },
    })

    lu.assertErrorMsgContains("value must not be nil", function()
        store.cache.shared.set("Snapshot", nil)
    end)
    lu.assertErrorMsgContains("value must be a scalar or table", function()
        store.cache.shared.set("Snapshot", function() end)
    end)
end

function TestCache:testDeclaredSharedCacheDifferentOwnerDuplicateFailsActivation()
    local first = createCacheModule(self.harness, "test-cache-shared-dupe-a", {
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.shared.dupe",
                access = "owner",
            },
        },
    })
    local second = createCacheModule(self.harness, "test-cache-shared-dupe-b", {
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.shared.dupe",
                access = "owner",
            },
        },
    })

    activateAndEnableHost(self.harness, first, "test-cache-shared-dupe-a")
    local ok, err = second.activate()
    lu.assertFalse(ok)
    lu.assertStrContains(err, "already published")
end

function TestCache:testDeclaredSharedCacheSameOwnerHotReloadReplacesPublication()
    local first, firstStore = createCacheModule(self.harness, "test-cache-shared-reload", {
        id = "SharedReload",
        name = "Shared Reload",
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.shared.reload",
                access = "owner",
                default = "first-default",
            },
        },
    })
    local _, readerStore = createCacheModule(self.harness, "test-cache-shared-reload-reader", {
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.shared.reload",
                access = "reader",
                fallback = "fallback",
            },
        },
    })
    activateAndEnableHost(self.harness, first, "test-cache-shared-reload")
    firstStore.cache.shared.set("Snapshot", "first-value")

    local second, secondStore = createCacheModule(self.harness, "test-cache-shared-reload", {
        id = "SharedReload",
        name = "Shared Reload",
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.shared.reload",
                access = "owner",
                default = "second-default",
            },
        },
    })
    activateAndEnableHost(self.harness, second, "test-cache-shared-reload")

    lu.assertEquals(readerStore.cache.shared.read("Snapshot"), "second-default")
    lu.assertTrue(secondStore.cache.shared.set("Snapshot", "second-value"))
    lu.assertEquals(readerStore.cache.shared.read("Snapshot"), "second-value")
    lu.assertErrorMsgContains("requires the active publishing owner", function()
        firstStore.cache.shared.set("Snapshot", "stale")
    end)
end

function TestCache:testDeclaredSharedCacheDisabledOwnerIsInvisibleToReads()
    local publisher, publisherStore = createCacheModule(self.harness, "test-cache-shared-disabled", {
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.shared.disabled",
                access = "owner",
                default = "default",
            },
        },
    })
    local _, readerStore = createCacheModule(self.harness, "test-cache-shared-disabled-reader", {
        cache = {
            Snapshot = {
                domain = "shared",
                id = "test.shared.disabled",
                access = "reader",
                fallback = "fallback",
            },
        },
    })
    activateAndEnableHost(self.harness, publisher, "test-cache-shared-disabled")
    publisherStore.cache.shared.set("Snapshot", "visible")

    local fullHost = self.harness.moduleHost.getLiveHost("test-cache-shared-disabled")
    lu.assertEquals(readerStore.cache.shared.read("Snapshot"), "visible")
    lu.assertTrue(fullHost.setEnabled(false))
    lu.assertEquals(readerStore.cache.shared.read("Snapshot"), "fallback")
    lu.assertTrue(fullHost.setEnabled(true))
    lu.assertEquals(readerStore.cache.shared.read("Snapshot"), "visible")
end
