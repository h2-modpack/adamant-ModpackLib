-- luacheck: globals TestFakeEngine
-- luacheck: no unused args

local lu = require("luaunit")
local fakeEngine = require("tests/harness/fake_engine")

TestFakeEngine = {}

local function writeFile(path, contents)
    local file = assert(io.open(path, "w"))
    file:write(contents)
    file:close()
end

local function makeTempDir()
    local path = os.tmpname()
    os.remove(path)
    local ok = os.execute('mkdir -p "' .. path .. '"')
    if ok ~= true and ok ~= 0 then
        error("failed to create temp dir: " .. tostring(path), 2)
    end
    return path
end

function TestFakeEngine:testCreateBaseEnvInstallsSharedRuntime()
    local env, callbacks = fakeEngine.createBaseEnv({
        withReload = true,
        config = {
            DebugMode = false,
            Diagnostics = {},
        },
    })

    lu.assertEquals(env.bit32.band(3, 1), 1)
    lu.assertEquals(env.rom.game.Color.Black, { 0, 0, 0, 255 })

    env.rom.gui.add_imgui(function() end)
    env.rom.gui.add_always_draw_imgui(function() end)
    env.rom.gui.add_to_menu_bar(function() end)
    lu.assertEquals(#callbacks.imgui, 1)
    lu.assertEquals(#callbacks.alwaysDraw, 1)
    lu.assertEquals(#callbacks.menuBar, 1)

    env.rom.game.SetupRunData()
    lu.assertEquals(callbacks.setupRunDataCount, 1)

    local allModsLoaded = 0
    env.rom.mods.on_all_mods_loaded(function()
        allModsLoaded = allModsLoaded + 1
    end)
    fakeEngine.runAllModsLoaded(callbacks)
    lu.assertEquals(allModsLoaded, 1)

    local loaded = 0
    env.rom.mods["SGG_Modding-ReLoad"].auto_single().load(function()
        loaded = loaded + 1
    end)
    lu.assertEquals(loaded, 1)
    lu.assertEquals(#callbacks.reloadLoads, 1)
end

function TestFakeEngine:testCreateBaseEnvPreservesInjectedModUtilPlugin()
    local injectedRuntime = { marker = "injected" }
    local injectedPlugin = {
        globals = {
            ModUtil = injectedRuntime,
        },
    }

    local env = fakeEngine.createBaseEnv({
        rom = {
            mods = {
                ["SGG_Modding-ModUtil"] = injectedPlugin,
            },
        },
    })

    lu.assertIs(env.rom.mods["SGG_Modding-ModUtil"], injectedPlugin)
    lu.assertIs(env.ModUtil, injectedRuntime)
    lu.assertIs(env.rom.game.ModUtil, injectedRuntime)
end

function TestFakeEngine:testFunctionalModUtilWrapTargetsGlobals()
    local env, callbacks = fakeEngine.createBaseEnv({
        modUtilWrapMode = "functional",
    })
    env.game.Target = function(value)
        return value + 1
    end

    env.ModUtil.Path.Wrap("Target", function(base, value)
        return base(value) * 2
    end)

    lu.assertEquals(env.game.Target(4), 10)
    lu.assertEquals(callbacks.wraps[1].kind, "wrap")
    lu.assertEquals(callbacks.wraps[1].name, "Target")

    env.ModUtil.Path.Restore("Target")
    lu.assertEquals(env.game.Target(4), 5)
end

function TestFakeEngine:testLoadPluginBootsSandboxedPlugin()
    local pluginDir = makeTempDir()
    writeFile(pluginDir .. "/child.lua", [[
return {
    value = "from child",
}
]])
    writeFile(pluginDir .. "/main.lua", [[
local child = import("child.lua")
public.owner = _PLUGIN.guid
public.childValue = child.value
public.hasRom = rom ~= nil
]])

    local baseEnv = fakeEngine.createBaseEnv()
    local pluginEnv = fakeEngine.loadPlugin(baseEnv, "test-plugin", pluginDir)

    lu.assertEquals(pluginEnv.public.owner, "test-plugin")
    lu.assertEquals(pluginEnv.public.childValue, "from child")
    lu.assertTrue(pluginEnv.public.hasRom)
    lu.assertEquals(baseEnv.rom.mods["test-plugin"], pluginEnv.public)
end
