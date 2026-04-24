local lu = require("luaunit")

TestHooks = {}

local savedModutil
local savedRomModutil
local savedGlobals

local function installPathMock()
    local counts = {
        wrap = 0,
        override = 0,
        restore = 0,
        contextWrap = 0,
    }
    local originals = {}

    savedModutil = modutil
    savedGlobals = {}

    local function saveGlobal(path)
        if savedGlobals[path] == nil then
            savedGlobals[path] = _G[path]
        end
    end

    modutil = {
        mod = {
            Path = {
                Wrap = function(path, handler)
                    counts.wrap = counts.wrap + 1
                    saveGlobal(path)
                    local base = _G[path]
                    _G[path] = function(...)
                        return handler(base, ...)
                    end
                end,

                Override = function(path, value)
                    counts.override = counts.override + 1
                    saveGlobal(path)
                    if originals[path] == nil then
                        originals[path] = _G[path]
                    end
                    _G[path] = value
                end,

                Restore = function(path)
                    counts.restore = counts.restore + 1
                    if originals[path] == nil then
                        error("object has no overrides")
                    end
                    _G[path] = originals[path]
                    originals[path] = nil
                end,

                Context = {
                    Wrap = function(path, context)
                        counts.contextWrap = counts.contextWrap + 1
                        saveGlobal(path)
                        local base = _G[path]
                        _G[path] = function(...)
                            context(...)
                            return base(...)
                        end
                    end,
                },
            },
        },
    }
    if rom and rom.mods then
        savedRomModutil = rom.mods["SGG_Modding-ModUtil"]
        rom.mods["SGG_Modding-ModUtil"] = modutil
    end

    return counts
end

local function restorePathMock()
    for path, value in pairs(savedGlobals or {}) do
        _G[path] = value
    end
    savedGlobals = nil
    modutil = savedModutil
    savedModutil = nil
    if rom and rom.mods then
        rom.mods["SGG_Modding-ModUtil"] = savedRomModutil
    end
    savedRomModutil = nil
end

local function createHostWithHooks(owner, registerHooks)
    return lib.createModuleHost({
        definition = { id = "HookTest", name = "Hook Test", storage = {} },
        store = {
            read = function()
                return false
            end,
        },
        session = {
            view = {},
            read = function() end,
            write = function() end,
            reset = function() end,
            isDirty = function()
                return false
            end,
            _flushToConfig = function() end,
            _reloadFromConfig = function() end,
            auditMismatches = function()
                return {}
            end,
        },
        hookOwner = owner,
        registerHooks = registerHooks,
    })
end

function TestHooks:testRefreshIsNotPublicModuleApi()
    lu.assertNil(lib.hooks.Refresh)
end

function TestHooks:testWrapRegistersOnceAndUpdatesHandler()
    local counts = installPathMock()
    local owner = {}
    _G.AdamantHookTestWrap = function(value)
        return "base:" .. value
    end

    lib.hooks.Wrap(owner, "AdamantHookTestWrap", function(base, value)
        return "first:" .. base(value)
    end)
    lib.hooks.Wrap(owner, "AdamantHookTestWrap", function(base, value)
        return "second:" .. base(value)
    end)

    lu.assertEquals(counts.wrap, 1)
    lu.assertEquals(_G.AdamantHookTestWrap("x"), "second:base:x")
    restorePathMock()
end

function TestHooks:testWrapResolvesModUtilFromRomModsWhenGlobalIsMissing()
    local counts = installPathMock()
    local owner = {}
    modutil = nil
    _G.AdamantHookTestWrapRomMods = function(value)
        return "base:" .. value
    end

    lib.hooks.Wrap(owner, "AdamantHookTestWrapRomMods", function(base, value)
        return "wrapped:" .. base(value)
    end)

    lu.assertEquals(counts.wrap, 1)
    lu.assertEquals(_G.AdamantHookTestWrapRomMods("x"), "wrapped:base:x")
    restorePathMock()
end

function TestHooks:testWrapRefreshOmissionFallsBackToBase()
    installPathMock()
    local owner = {}
    _G.AdamantHookTestWrapRefresh = function(value)
        return "base:" .. value
    end

    createHostWithHooks(owner, function()
        lib.hooks.Wrap(owner, "AdamantHookTestWrapRefresh", function(base, value)
            return "wrapped:" .. base(value)
        end)
    end)

    lu.assertEquals(_G.AdamantHookTestWrapRefresh("x"), "wrapped:base:x")

    createHostWithHooks(owner, function() end)

    lu.assertEquals(_G.AdamantHookTestWrapRefresh("x"), "base:x")
    restorePathMock()
end

function TestHooks:testOverrideFunctionRegistersOnceAndUpdatesReplacement()
    local counts = installPathMock()
    local owner = {}
    _G.AdamantHookTestOverride = function()
        return "base"
    end

    lib.hooks.Override(owner, "AdamantHookTestOverride", function()
        return "first"
    end)
    lib.hooks.Override(owner, "AdamantHookTestOverride", function()
        return "second"
    end)

    lu.assertEquals(counts.override, 1)
    lu.assertEquals(_G.AdamantHookTestOverride(), "second")
    restorePathMock()
end

function TestHooks:testOverrideRefreshOmissionRestoresOriginal()
    local counts = installPathMock()
    local owner = {}
    _G.AdamantHookTestOverrideRefresh = function()
        return "base"
    end

    createHostWithHooks(owner, function()
        lib.hooks.Override(owner, "AdamantHookTestOverrideRefresh", function()
            return "override"
        end)
    end)

    lu.assertEquals(_G.AdamantHookTestOverrideRefresh(), "override")

    createHostWithHooks(owner, function() end)

    lu.assertEquals(counts.restore, 1)
    lu.assertEquals(_G.AdamantHookTestOverrideRefresh(), "base")
    restorePathMock()
end

function TestHooks:testContextWrapRegistersOnceAndUpdatesContext()
    local counts = installPathMock()
    local owner = {}
    local observed = {}

    _G.AdamantHookTestContext = function()
        table.insert(observed, "base")
    end

    lib.hooks.Context.Wrap(owner, "AdamantHookTestContext", function()
        table.insert(observed, "first")
    end)
    lib.hooks.Context.Wrap(owner, "AdamantHookTestContext", function()
        table.insert(observed, "second")
    end)

    _G.AdamantHookTestContext()

    lu.assertEquals(counts.contextWrap, 1)
    lu.assertEquals(observed, { "second", "base" })
    restorePathMock()
end

function TestHooks:testContextWrapRefreshOmissionBecomesInert()
    installPathMock()
    local owner = {}
    local observed = {}

    _G.AdamantHookTestContextRefresh = function()
        table.insert(observed, "base")
    end

    createHostWithHooks(owner, function()
        lib.hooks.Context.Wrap(owner, "AdamantHookTestContextRefresh", function()
            table.insert(observed, "context")
        end)
    end)

    createHostWithHooks(owner, function() end)
    _G.AdamantHookTestContextRefresh()

    lu.assertEquals(observed, { "base" })
    restorePathMock()
end

function TestHooks:testRefreshFailureKeepsPreviousLiveHookState()
    local counts = installPathMock()
    local owner = {}
    local observed = {}

    _G.AdamantHookTestFailureWrap = function(value)
        return "base:" .. value
    end
    _G.AdamantHookTestFailureOverride = function()
        return "base-override"
    end
    _G.AdamantHookTestFailureContext = function()
        table.insert(observed, "base")
    end
    _G.AdamantHookTestFailureNew = function(value)
        return "new-base:" .. value
    end

    createHostWithHooks(owner, function()
        lib.hooks.Wrap(owner, "AdamantHookTestFailureWrap", function(base, value)
            return "first:" .. base(value)
        end)
        lib.hooks.Override(owner, "AdamantHookTestFailureOverride", function()
            return "first-override"
        end)
        lib.hooks.Context.Wrap(owner, "AdamantHookTestFailureContext", function()
            table.insert(observed, "first-context")
        end)
    end)

    local ok = pcall(function()
        createHostWithHooks(owner, function()
            lib.hooks.Wrap(owner, "AdamantHookTestFailureWrap", function(base, value)
                return "second:" .. base(value)
            end)
            lib.hooks.Override(owner, "AdamantHookTestFailureOverride", function()
                return "second-override"
            end)
            lib.hooks.Context.Wrap(owner, "AdamantHookTestFailureContext", function()
                table.insert(observed, "second-context")
            end)
            lib.hooks.Wrap(owner, "AdamantHookTestFailureNew", function(base, value)
                return "new:" .. base(value)
            end)
            error("boom")
        end)
    end)

    observed = {}
    _G.AdamantHookTestFailureContext()

    lu.assertFalse(ok)
    lu.assertEquals(counts.wrap, 1)
    lu.assertEquals(counts.override, 1)
    lu.assertEquals(counts.contextWrap, 1)
    lu.assertEquals(_G.AdamantHookTestFailureWrap("x"), "first:base:x")
    lu.assertEquals(_G.AdamantHookTestFailureOverride(), "first-override")
    lu.assertEquals(observed, { "first-context", "base" })
    lu.assertEquals(_G.AdamantHookTestFailureNew("x"), "new-base:x")
    restorePathMock()
end

function TestHooks:testCreateModuleHostSyncsCoordinatedRuntimeImmediately()
    local packId = "hook-pack"
    local applyCalls = 0
    local revertCalls = 0
    lib.lifecycle.registerCoordinator(packId, { ModEnabled = true })

    lib.createModuleHost({
        definition = {
            modpack = packId,
            id = "Alpha",
            name = "Alpha",
            storage = {},
            affectsRunData = true,
            apply = function()
                applyCalls = applyCalls + 1
            end,
            revert = function()
                revertCalls = revertCalls + 1
            end,
        },
        store = {
            read = function(key)
                if key == "Enabled" then
                    return true
                end
                return false
            end,
        },
        session = {
            view = {},
            read = function() end,
            write = function() end,
            reset = function() end,
            isDirty = function()
                return false
            end,
            _flushToConfig = function() end,
            _reloadFromConfig = function() end,
            auditMismatches = function()
                return {}
            end,
        },
    })

    lu.assertEquals(applyCalls, 1)
    lu.assertEquals(revertCalls, 0)
    lib.lifecycle.registerCoordinator(packId, nil)
end

function TestHooks:testCreateModuleHostHotReloadReplacesCoordinatedRuntimeState()
    local packId = "hook-reload-pack"
    local firstApplyCalls = 0
    local firstRevertCalls = 0
    local secondApplyCalls = 0
    local secondRevertCalls = 0
    lib.lifecycle.registerCoordinator(packId, { ModEnabled = true })

    local function createSession()
        return {
            view = {},
            read = function() end,
            write = function() end,
            reset = function() end,
            isDirty = function()
                return false
            end,
            _flushToConfig = function() end,
            _reloadFromConfig = function() end,
            auditMismatches = function()
                return {}
            end,
        }
    end

    local store = {
        read = function(key)
            if key == "Enabled" then
                return true
            end
            return false
        end,
    }

    lib.createModuleHost({
        definition = {
            modpack = packId,
            id = "Alpha",
            name = "Alpha",
            storage = {},
            affectsRunData = true,
            apply = function()
                firstApplyCalls = firstApplyCalls + 1
            end,
            revert = function()
                firstRevertCalls = firstRevertCalls + 1
            end,
        },
        store = store,
        session = createSession(),
    })

    lib.createModuleHost({
        definition = {
            modpack = packId,
            id = "Alpha",
            name = "Alpha",
            storage = {},
            affectsRunData = true,
            apply = function()
                secondApplyCalls = secondApplyCalls + 1
            end,
            revert = function()
                secondRevertCalls = secondRevertCalls + 1
            end,
        },
        store = store,
        session = createSession(),
    })

    lu.assertEquals(firstApplyCalls, 1)
    lu.assertEquals(firstRevertCalls, 1)
    lu.assertEquals(secondApplyCalls, 1)
    lu.assertEquals(secondRevertCalls, 0)

    lib.lifecycle.registerCoordinator(packId, nil)
    lib.lifecycle.revertMutation({
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
        affectsRunData = true,
        apply = function() end,
        revert = function()
            secondRevertCalls = secondRevertCalls + 1
        end,
    }, store)
end
