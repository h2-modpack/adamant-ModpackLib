-- luacheck: globals TestSmokeRunner

local lu = require("luaunit")
local smokeRunner = require("tests/harness/smoke_runner")

TestSmokeRunner = {}

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

local function createModulePlugin()
    local pluginDir = makeTempDir()
    writeFile(pluginDir .. "/main.lua", [[
local lib = rom.mods["adamant-ModpackLib"]
local host = lib.createModule({
    pluginGuid = _PLUGIN.guid,
    modpack = "test-pack",
    id = "Synthetic",
    name = "Synthetic",
})

host.data.define({
    { type = "bool", alias = "SmokeFlag", default = false },
})
host.ui.tab(function() end)
host.activate()
]])
    return pluginDir
end

local function createModuleFixture()
    local dir = makeTempDir()
    local fixturePath = dir .. "/smoke_env.lua"
    writeFile(fixturePath, [[
return {
    expectedPackId = "test-pack",
    expectedModuleId = "Synthetic",
    configureEnv = function(env)
        env.smokeConfigured = true
    end,
}
]])
    return fixturePath
end

local function createCoordinatorPlugin()
    local pluginDir = makeTempDir()
    writeFile(pluginDir .. "/main.lua", [[
local lib = rom.mods["adamant-ModpackLib"]
local config = rom.mods["SGG_Modding-Chalk"].auto("config.lua")
local packId = "test-pack"
local initialized = false

rom.mods.on_all_mods_loaded(function()
    lib.modpack.registerCoordinator(packId, "Test Pack", config, function()
        initialized = false
        return true
    end)
end)

modutil.once_loaded.game(function()
    local callbacks = lib.modpack.createGuiCallbacks(packId)
    rom.gui.add_always_draw_imgui(function()
        if not initialized then
            initialized = lib.modpack.createPack(packId, config, #config.Profiles, {}, {
                moduleOrder = { "Second", "First" },
            }) == true
        end
        callbacks.alwaysDraw()
    end)
end)
]])
    return pluginDir
end

function TestSmokeRunner.testAssertModuleBootsLoadsFixtureAndChecksLiveModule()
    local pluginDir = createModulePlugin()
    local fixturePath = createModuleFixture()

    local boot = smokeRunner.assertModuleBoots({
        libSrcDir = "src",
        pluginGuid = "test-module",
        moduleSrcDir = pluginDir,
        fixturePath = fixturePath,
    })

    lu.assertTrue(boot.env.smokeConfigured)
    lu.assertEquals(boot.liveModule.getModuleId(), "Synthetic")
    lu.assertEquals(boot.liveModule.getPackId(), "test-pack")
end

function TestSmokeRunner.testAssertModulesBootUsesExplicitLayout()
    local pluginDir = createModulePlugin()

    local boots = smokeRunner.assertModulesBoot({
        libSrcDir = "src",
        modules = {
            {
                pluginGuid = "test-module",
                moduleSrcDir = pluginDir,
                expectedPackId = "test-pack",
                expectedModuleId = "Synthetic",
            },
        },
    })

    lu.assertEquals(#boots, 1)
    lu.assertEquals(boots[1].liveModule.getOwnerId(), "test-module")
end

function TestSmokeRunner.testAssertCoordinatorBootsRealCoordinatorWithSyntheticModules()
    local coordinatorDir = createCoordinatorPlugin()

    local boot = smokeRunner.assertCoordinatorBoots({
        libSrcDir = "src",
        packId = "test-pack",
        coordinator = {
            pluginGuid = "test-coordinator",
            srcDir = coordinatorDir,
        },
        modules = {
            {
                pluginGuid = "test-first",
                moduleId = "First",
            },
            {
                pluginGuid = "test-second",
                moduleId = "Second",
            },
        },
    })

    local pack = boot:getRuntimeRegistry().modpacks.packs["test-pack"]
    lu.assertEquals(pack.moduleRegistry.tabOrder[1].id, "Second")
    lu.assertEquals(pack.moduleRegistry.tabOrder[2].id, "First")
end

function TestSmokeRunner.testAssertManifestRunsModuleAndCoordinatorSmoke()
    local moduleDir = createModulePlugin()
    local coordinatorDir = createCoordinatorPlugin()

    local results = smokeRunner.assertManifest({
        libSrcDir = "src",
        packId = "test-pack",
        coordinator = {
            pluginGuid = "test-coordinator",
            srcDir = coordinatorDir,
        },
        modules = {
            {
                pluginGuid = "test-module",
                moduleSrcDir = moduleDir,
                expectedPackId = "test-pack",
                expectedModuleId = "Synthetic",
                moduleId = "Synthetic",
            },
        },
    })

    lu.assertEquals(#results.modules, 1)
    lu.assertEquals(results.modules[1].liveModule.getModuleId(), "Synthetic")
    lu.assertNotNil(results.coordinator:getRuntimeRegistry().modpacks.packs["test-pack"])
end
