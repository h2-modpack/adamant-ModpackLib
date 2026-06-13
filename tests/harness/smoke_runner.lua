local source = debug.getinfo(1, "S").source
local harnessDir = source:sub(1, 1) == "@"
    and source:sub(2):match("^(.*)[/\\][^/\\]+$")
    or "tests/harness"
local bootHarness = dofile(harnessDir .. "/plugin_boot_harness.lua")

local SmokeRunner = {}

local function fail(message)
    error(message, 3)
end

local function assertTruthy(value, message)
    if not value then
        fail(message)
    end
end

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        fail(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
    end
end

local function assertString(value, message)
    if type(value) ~= "string" or value == "" then
        fail(message)
    end
end

local function copyTable(input)
    local copy = {}
    for key, value in pairs(input or {}) do
        copy[key] = value
    end
    return copy
end

local function tryReadFile(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

local function combineConfigure(first, second)
    if first == nil then
        return second
    end
    if second == nil then
        return first
    end
    return function(env, callbacks)
        first(env, callbacks)
        second(env, callbacks)
    end
end

local function defaultConfig()
    return {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            {
                Name = "Default",
                Hash = "",
                Tooltip = "",
            },
        },
    }
end

function SmokeRunner.loadFixture(path)
    if not tryReadFile(path) then
        return {}
    end

    local fixture = dofile(path)
    if type(fixture) == "function" then
        return {
            configureEnv = fixture,
        }
    end
    if type(fixture) == "table" then
        if fixture.configureEnv ~= nil and type(fixture.configureEnv) ~= "function" then
            fail(path .. " configureEnv must be a function")
        end
        if fixture.expectedPackId ~= nil and type(fixture.expectedPackId) ~= "string" then
            fail(path .. " expectedPackId must be a string")
        end
        if fixture.expectedModuleId ~= nil and type(fixture.expectedModuleId) ~= "string" then
            fail(path .. " expectedModuleId must be a string")
        end
        return fixture
    end

    fail(path .. " must return a configureEnv function or fixture table")
end

local function moduleBootOpts(module, fixture)
    local bootOpts = copyTable(module.bootOpts)
    bootOpts.libSrcDir = module.libSrcDir or bootOpts.libSrcDir
    bootOpts.pluginGuid = module.pluginGuid
    bootOpts.moduleSrcDir = module.moduleSrcDir
    bootOpts.mainPath = module.mainPath
    bootOpts.public = module.public
    bootOpts.imports = module.imports
    bootOpts.importOverrides = module.importOverrides
    bootOpts.configureEnv = combineConfigure(fixture.configureEnv, module.configureEnv or bootOpts.configureEnv)
    return bootOpts
end

function SmokeRunner.assertModuleBoots(module)
    if type(module) ~= "table" then
        fail("module smoke entry must be a table")
    end
    assertString(module.pluginGuid, "module smoke entry pluginGuid is required")
    assertString(module.moduleSrcDir, module.pluginGuid .. " moduleSrcDir is required")

    local fixture = SmokeRunner.loadFixture(module.fixturePath)
    local ok, boot = xpcall(function()
        return bootHarness.bootModule(moduleBootOpts(module, fixture))
    end, debug.traceback)

    if not ok then
        local hint = module.fixturePath
            and ("If this module needs game globals, add or update " .. module.fixturePath)
            or "If this module needs game globals, pass configureEnv or fixturePath."
        fail(string.format("%s boot smoke failed: %s\n%s", module.pluginGuid, tostring(boot), hint))
    end

    local liveModule = boot.liveModule
    assertTruthy(liveModule, module.pluginGuid .. " did not publish a live module")
    assertEquals(liveModule.getOwnerId(), module.pluginGuid, module.pluginGuid .. " owner id")
    assertTruthy(
        type(liveModule.getModuleId()) == "string" and liveModule.getModuleId() ~= "",
        module.pluginGuid .. " module id"
    )
    assertTruthy(
        type(liveModule.getPackId()) == "string" and liveModule.getPackId() ~= "",
        module.pluginGuid .. " pack id"
    )

    local expectedModuleId = module.expectedModuleId or fixture.expectedModuleId
    local expectedPackId = module.expectedPackId or fixture.expectedPackId
    if expectedModuleId then
        assertEquals(liveModule.getModuleId(), expectedModuleId, module.pluginGuid .. " module id")
    end
    if expectedPackId then
        assertEquals(liveModule.getPackId(), expectedPackId, module.pluginGuid .. " pack id")
    end

    return boot
end

function SmokeRunner.assertModulesBoot(layout)
    if type(layout) ~= "table" then
        fail("module smoke layout must be a table")
    end
    if type(layout.modules) ~= "table" then
        fail("module smoke layout modules must be a table")
    end
    if layout.allowEmpty ~= true then
        assertTruthy(#layout.modules > 0, "module smoke layout modules must not be empty")
    end

    local boots = {}
    for index, module in ipairs(layout.modules) do
        local moduleOpts = copyTable(layout.defaults)
        if layout.libSrcDir ~= nil then
            moduleOpts.libSrcDir = layout.libSrcDir
        end
        if layout.bootOpts ~= nil then
            moduleOpts.bootOpts = copyTable(layout.bootOpts)
        end
        for key, value in pairs(module) do
            moduleOpts[key] = value
        end
        boots[index] = SmokeRunner.assertModuleBoots(moduleOpts)
    end
    return boots
end

local function installSyntheticModules(boot, layout)
    for _, module in ipairs(layout.modules) do
        assertString(module.pluginGuid, "coordinator smoke module pluginGuid is required")
        local moduleId = module.moduleId or module.id
        assertString(moduleId, module.pluginGuid .. " moduleId is required")

        boot.env.rom.mods[module.pluginGuid] = module.public or {}
        local host = boot.lib.createModule({
            pluginGuid = module.pluginGuid,
            modpack = layout.packId,
            id = moduleId,
            name = module.name or moduleId,
            shortName = module.shortName,
            tooltip = module.tooltip,
        })

        if type(module.defineData) == "function" then
            module.defineData(host)
        else
            host.data.define({
                { type = "bool", alias = "SmokeFlag", default = false },
            })
        end

        if type(module.configureHost) == "function" then
            module.configureHost(host)
        else
            host.ui.tab(function() end)
        end

        local ok, err = host.activate()
        assertTruthy(ok, module.pluginGuid .. " synthetic module did not activate: " .. tostring(err))
    end
end

local function assertPackModules(boot, layout)
    local registry = boot:getRuntimeRegistry()
    local packRegistry = registry and registry.modpacks
    local pack = packRegistry and packRegistry.packs and packRegistry.packs[layout.packId]
    assertTruthy(pack, "Core did not initialize the modpack")
    assertEquals(#pack.moduleRegistry.modules, #layout.modules, "Modpack discovered module count")

    for _, module in ipairs(layout.modules) do
        local moduleId = module.moduleId or module.id
        assertTruthy(pack.moduleRegistry.modulesById[moduleId],
            "Modpack did not discover " .. moduleId)
    end
end

function SmokeRunner.assertCoordinatorBoots(layout)
    if type(layout) ~= "table" then
        fail("coordinator smoke layout must be a table")
    end
    if type(layout.coordinator) ~= "table" then
        fail("coordinator smoke layout coordinator must be a table")
    end
    assertString(layout.packId, "coordinator smoke layout packId is required")
    if type(layout.modules) ~= "table" or #layout.modules == 0 then
        fail("coordinator smoke layout modules must be a non-empty table")
    end

    local coordinator = layout.coordinator
    assertString(coordinator.pluginGuid or coordinator.guid, "coordinator pluginGuid is required")
    assertString(coordinator.srcDir, "coordinator srcDir is required")

    local bootOpts = copyTable(layout.bootOpts)
    bootOpts.libSrcDir = layout.libSrcDir or bootOpts.libSrcDir
    bootOpts.config = layout.config or bootOpts.config or defaultConfig()
    bootOpts.ScreenData = layout.ScreenData or bootOpts.ScreenData or {
        HUD = {
            ComponentData = {},
        },
    }
    bootOpts.HUDScreen = layout.HUDScreen or bootOpts.HUDScreen or {
        Components = {},
    }
    bootOpts.ShowingCombatUI = layout.ShowingCombatUI
    if bootOpts.ShowingCombatUI == nil then
        bootOpts.ShowingCombatUI = true
    end
    bootOpts.ModifyTextBox = layout.ModifyTextBox or bootOpts.ModifyTextBox or function() end
    bootOpts.SetAlpha = layout.SetAlpha or bootOpts.SetAlpha or function() end
    bootOpts.CreateComponentFromData = layout.CreateComponentFromData or bootOpts.CreateComponentFromData
        or function(_, data)
            return {
                Id = data.Name,
                Name = data.Name,
            }
        end
    bootOpts.Destroy = layout.Destroy or bootOpts.Destroy or function() end

    local boot = bootHarness.boot(bootOpts)
    installSyntheticModules(boot, layout)
    boot:loadPlugin({
        guid = coordinator.pluginGuid or coordinator.guid,
        srcDir = coordinator.srcDir,
        mainPath = coordinator.mainPath,
        public = coordinator.public,
        imports = coordinator.imports,
        importOverrides = coordinator.importOverrides,
        configureEnv = coordinator.configureEnv,
    })

    if layout.runAllModsLoaded ~= false then
        boot:runAllModsLoaded()
    end
    if layout.runGameLoaded ~= false then
        boot:runGameLoaded()
    end
    if layout.runAlwaysDraw ~= false then
        boot:runAlwaysDraw()
    end

    assertPackModules(boot, layout)
    return boot
end

function SmokeRunner.assertManifest(manifest)
    if type(manifest) ~= "table" then
        fail("smoke manifest must be a table")
    end

    local results = {}
    if manifest.modules ~= nil then
        results.modules = SmokeRunner.assertModulesBoot(manifest)
    end
    if manifest.coordinator ~= nil then
        results.coordinator = SmokeRunner.assertCoordinatorBoots(manifest)
    end
    return results
end

return SmokeRunner
