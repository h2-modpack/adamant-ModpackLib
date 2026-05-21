local lu = require('luaunit')
local createLibHarness = require('tests/harness/create_lib_harness')

TestCache = {}

function TestCache:setUp()
    self.harness = createLibHarness()
    self.cache = self.harness.cache
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
        }
        function entry.get(entrySelf)
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

function TestCache:testCurrentRunCreatesNamespacedStateOnce()
    local currentRun = {}
    self.harness.env.CurrentRun = currentRun
    local calls = 0

    local first = self.cache.currentRun.get("owner-a", "run", function()
        calls = calls + 1
        return { Count = 1 }
    end)
    first.Count = 2

    local second = self.cache.currentRun.get("owner-a", "run", function()
        calls = calls + 1
        return { Count = 99 }
    end)

    lu.assertEquals(calls, 1)
    lu.assertIs(first, second)
    lu.assertEquals(second.Count, 2)
    lu.assertNotNil(currentRun._AdamantModpackLibCache)
end

function TestCache:testCurrentRunNamespacesPreventOwnerCollisions()
    self.harness.env.CurrentRun = {}

    local a = self.cache.currentRun.get("owner-a", "run")
    local b = self.cache.currentRun.get("owner-b", "run")

    a.Value = "a"
    b.Value = "b"

    lu.assertEquals(self.cache.currentRun.peek("owner-a", "run").Value, "a")
    lu.assertEquals(self.cache.currentRun.peek("owner-b", "run").Value, "b")
end

function TestCache:testCurrentRunPeekAndClearDoNotCreateBuckets()
    local currentRun = {}
    self.harness.env.CurrentRun = currentRun

    lu.assertNil(self.cache.currentRun.peek("owner", "run"))
    lu.assertNil(currentRun._AdamantModpackLibCache)
    lu.assertFalse(self.cache.currentRun.clear("owner", "run"))

    self.cache.currentRun.get("owner", "run")
    lu.assertNotNil(self.cache.currentRun.peek("owner", "run"))
    lu.assertTrue(self.cache.currentRun.clear("owner", "run"))
    lu.assertNil(self.cache.currentRun.peek("owner", "run"))
    lu.assertNil(currentRun._AdamantModpackLibCache)
end

function TestCache:testCurrentRunRejectsInvalidInputs()
    self.harness.env.CurrentRun = {}

    lu.assertErrorMsgContains("ownerId must be a non-empty string", function()
        self.cache.currentRun.get("", "run")
    end)
    lu.assertErrorMsgContains("key must be a non-empty string", function()
        self.cache.currentRun.get("owner", "")
    end)
    lu.assertErrorMsgContains("factory must be a function", function()
        self.cache.currentRun.get("owner", "run", true)
    end)
    lu.assertErrorMsgContains("factory must return a table", function()
        self.cache.currentRun.get("owner", "run", function()
            return true
        end)
    end)
end

function TestCache:testCurrentRunRejectsCorruptedNamespaceBuckets()
    lu.assertErrorMsgContains("root bucket is not a table", function()
        self.harness.env.CurrentRun = { _AdamantModpackLibCache = true }
        self.cache.currentRun.get("owner", "run")
    end)

    lu.assertErrorMsgContains("owner bucket is not a table", function()
        self.harness.env.CurrentRun = {
            _AdamantModpackLibCache = {
                owner = true,
            },
        }
        self.cache.currentRun.get("owner", "run")
    end)
end

function TestCache:testAuthorHostCurrentRunCacheBindsOwnerIdentity()
    local currentRun = {}
    self.harness.env.CurrentRun = currentRun

    local host = self.harness.public.createModule({
        pluginGuid = "test-cache-host",
        config = {},
        modpack = "test-pack",
        id = "CacheHost",
        name = "Cache Host",
        drawTab = function() end,
    })

    local state = host.cache.currentRun.get("run", function()
        return { Count = 1 }
    end)
    state.Count = 2

    lu.assertEquals(self.cache.currentRun.peek("test-cache-host", "run").Count, 2)
    lu.assertIs(host.cache.currentRun.peek("run"), state)
    lu.assertTrue(host.cache.currentRun.clear("run"))
    lu.assertNil(self.cache.currentRun.peek("test-cache-host", "run"))
end

function TestCache:testAuthorHostCurrentRunCacheReturnsEmptyWhenNoCurrentRun()
    self.harness.env.CurrentRun = nil

    local host = self.harness.public.createModule({
        pluginGuid = "test-cache-no-run",
        config = {},
        modpack = "test-pack",
        id = "NoRunCacheHost",
        name = "No Run Cache Host",
        drawTab = function() end,
    })

    lu.assertNil(host.cache.currentRun.get("run"))
    lu.assertNil(host.cache.currentRun.peek("run"))
    lu.assertFalse(host.cache.currentRun.clear("run"))
end

function TestCache:testAuthorHostCurrentRunCacheRejectsInvalidInputsWithoutCurrentRun()
    self.harness.env.CurrentRun = nil

    local host = self.harness.public.createModule({
        pluginGuid = "test-cache-invalid-host",
        config = {},
        id = "InvalidCacheHost",
        name = "Invalid Cache Host",
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("key must be a non-empty string", function()
        host.cache.currentRun.get("")
    end)
    lu.assertErrorMsgContains("factory must be a function", function()
        host.cache.currentRun.get("run", true)
    end)
end

function TestCache:testAuthorCurrentRunCacheRejectsUnmanagedHost()
    local host = self.harness.cacheBundle.author.create({})

    lu.assertErrorMsgContains("expected managed module host state", function()
        host.currentRun.get("run")
    end)
end

function TestCache:testAuthorPersistentCacheReadsWritesAndClearsScalarValues()
    local config = {}
    local host = self.harness.public.createModule({
        pluginGuid = "test-cache-persistent",
        config = config,
        modpack = "test-pack",
        id = "PersistentCacheHost",
        name = "Persistent Cache Host",
        drawTab = function() end,
    })

    lu.assertFalse(host.cache.persistent.has("RecordingReady"))
    lu.assertEquals(host.cache.persistent.read("RecordingReady", false), false)
    lu.assertFalse(host.cache.persistent.has("RecordingReady"))

    lu.assertTrue(host.cache.persistent.write("RecordingReady", true))
    lu.assertTrue(host.cache.persistent.has("RecordingReady"))
    lu.assertTrue(host.cache.persistent.read("RecordingReady", false))

    lu.assertTrue(host.cache.persistent.clear("RecordingReady"))
    lu.assertFalse(host.cache.persistent.has("RecordingReady"))
    lu.assertEquals(host.cache.persistent.read("RecordingReady", false), false)
end

function TestCache:testAuthorPersistentCachePreservesFalseAsPresentValue()
    local host = self.harness.public.createModule({
        pluginGuid = "test-cache-persistent-false",
        config = {},
        id = "PersistentFalseCacheHost",
        name = "Persistent False Cache Host",
        drawTab = function() end,
    })

    host.cache.persistent.write("RecordingReady", false)

    lu.assertTrue(host.cache.persistent.has("RecordingReady"))
    lu.assertFalse(host.cache.persistent.read("RecordingReady", true))
end

function TestCache:testAuthorPersistentCacheNamespacesByOwner()
    local config = {}
    local first = self.harness.public.createModule({
        pluginGuid = "test-cache-persistent-owner-a",
        config = config,
        id = "PersistentOwnerA",
        name = "Persistent Owner A",
        drawTab = function() end,
    })
    local second = self.harness.public.createModule({
        pluginGuid = "test-cache-persistent-owner-b",
        config = config,
        id = "PersistentOwnerB",
        name = "Persistent Owner B",
        drawTab = function() end,
    })

    first.cache.persistent.write("RecordingReady", true)
    second.cache.persistent.write("RecordingReady", false)

    lu.assertTrue(first.cache.persistent.read("RecordingReady", false))
    lu.assertFalse(second.cache.persistent.read("RecordingReady", true))
end

function TestCache:testAuthorPersistentCacheUsesChalkCacheSection()
    local config, raw, restoreChalk = makeChalkConfig(self.harness)
    local ok, host, _, err = pcall(function()
        return self.harness.public.createModule({
            pluginGuid = "test-cache-persistent-chalk",
            config = config,
            id = "PersistentChalkCacheHost",
            name = "Persistent Chalk Cache Host",
            drawTab = function() end,
        })
    end)
    restoreChalk()

    lu.assertTrue(ok)
    lu.assertNotNil(host, tostring(err))

    lu.assertTrue(host.cache.persistent.write("RecordingReady", false))
    lu.assertFalse(host.cache.persistent.read("RecordingReady", true))

    local cacheEntryCount = 0
    local cacheKey
    for descriptor, entry in pairs(raw.entries) do
        if descriptor.section == "cache" then
            cacheEntryCount = cacheEntryCount + 1
            cacheKey = descriptor.key
            lu.assertFalse(entry:get())
        end
    end

    lu.assertEquals(cacheEntryCount, 1)
    lu.assertStrContains(cacheKey, "test-cache-persistent-chalk")
    lu.assertTrue(host.cache.persistent.clear("RecordingReady"))
    lu.assertFalse(host.cache.persistent.has("RecordingReady"))
end

function TestCache:testAuthorPersistentCacheRejectsInvalidInputs()
    local host = self.harness.public.createModule({
        pluginGuid = "test-cache-persistent-invalid",
        config = {},
        id = "PersistentInvalidCacheHost",
        name = "Persistent Invalid Cache Host",
        drawTab = function() end,
    })

    lu.assertErrorMsgContains("key must be a non-empty string", function()
        host.cache.persistent.read("")
    end)
    lu.assertErrorMsgContains("value must be a boolean, number, or string", function()
        host.cache.persistent.read("RecordingReady", {})
    end)
    lu.assertErrorMsgContains("value must be a boolean, number, or string", function()
        host.cache.persistent.write("RecordingReady", nil)
    end)
    lu.assertErrorMsgContains("value must be a boolean, number, or string", function()
        host.cache.persistent.write("RecordingReady", {})
    end)
end
