-- luacheck: globals TestPluginBootHarness

local lu = require("luaunit")
local bootHarness = require("tests/harness/plugin_boot_harness")

TestPluginBootHarness = {}

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

local function createPlugin()
    local pluginDir = makeTempDir()
    writeFile(pluginDir .. "/child.lua", [[
return {
    value = "from child",
}
]])
    writeFile(pluginDir .. "/main.lua", [[
local child = import("child.lua")
local lib = rom.mods["adamant-ModpackLib"]
local host = lib.createModule({
    pluginGuid = _PLUGIN.guid,
    id = "Synthetic",
    name = "Synthetic",
})

host.ui.tab(function() end)
host.activate()

public.childValue = child.value
public.owner = _PLUGIN.guid
public.allModsLoaded = false
public.gameLoaded = false

rom.mods.on_all_mods_loaded(function()
    public.allModsLoaded = true
end)

modutil.once_loaded.game(function()
    public.gameLoaded = true
end)
]])
    return pluginDir
end

function TestPluginBootHarness.testBootLoadsLibAndPluginPaths()
    local pluginDir = createPlugin()

    local boot = bootHarness.boot({
        libSrcDir = "src",
        plugins = {
            {
                guid = "test-plugin",
                srcDir = pluginDir,
            },
        },
    })

    local pluginEnv = boot.pluginsByGuid["test-plugin"]
    lu.assertEquals(type(boot.lib.createModule), "function")
    lu.assertEquals(pluginEnv.public.owner, "test-plugin")
    lu.assertEquals(pluginEnv.public.childValue, "from child")
    lu.assertEquals(boot.env.rom.mods["test-plugin"], pluginEnv.public)
    lu.assertEquals(boot:getLiveModule("test-plugin").getModuleId(), "Synthetic")

    boot:runAllModsLoaded()
    boot:runGameLoaded()
    lu.assertTrue(pluginEnv.public.allModsLoaded)
    lu.assertTrue(pluginEnv.public.gameLoaded)
end

function TestPluginBootHarness.testBootModuleCompatibilityShape()
    local pluginDir = createPlugin()

    local boot = bootHarness.bootModule({
        libSrcDir = "src",
        pluginGuid = "test-module",
        moduleSrcDir = pluginDir,
    })

    lu.assertEquals(boot.moduleEnv.public.owner, "test-module")
    lu.assertEquals(boot.liveModule.getOwnerId(), "test-module")
    lu.assertTrue(boot.moduleEnv.public.gameLoaded)
end

function TestPluginBootHarness.testBootModuleForwardsBootOptions()
    local pluginDir = createPlugin()
    local customScreenData = { marker = "screen" }
    local customSetAlpha = function()
        return "custom-alpha"
    end

    local boot = bootHarness.bootModule({
        libSrcDir = "src",
        pluginGuid = "test-module",
        moduleSrcDir = pluginDir,
        ScreenData = customScreenData,
        SetAlpha = customSetAlpha,
    })

    lu.assertIs(boot.env.ScreenData, customScreenData)
    lu.assertIs(boot.env.SetAlpha, customSetAlpha)
end
