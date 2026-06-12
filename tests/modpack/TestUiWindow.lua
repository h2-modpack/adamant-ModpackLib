local lu = require('luaunit')

TestUiWindow = {}

local function readPackRestoreMarker(moduleRegistry, entry, snapshot)
    return moduleRegistry.snapshot.getLiveModule(entry, snapshot).read("AdamantFramework_PackRestoreSnapshot")
end

function TestUiWindow:testCreateUIUsesPreparedSnapshotForStartupStaging()
    local entry = {
        id = "Alpha",
        name = "Alpha",
        pluginGuid = "Alpha",
        _tabLabel = "Alpha",
    }
    local liveModule
    liveModule = {
        reloaded = false,
        reloadFromConfig = function()
            reloads = reloads + 1
            liveModule.reloaded = true
        end,
    }
    local reloads = 0
    local moduleRegistry = {
        modules = { entry },
        modulesById = {
            Alpha = entry,
        },
        modulesWithQuickContent = {},
        tabOrder = { entry },
        live = {
            captureSnapshot = function()
                return {
                    liveModules = {
                        [entry] = liveModule,
                    },
                }
            end,
        },
        snapshot = {
            getLiveModule = function(_, snapshot)
                return snapshot.liveModules[entry]
            end,
            isEntryEnabled = function(_, snapshot)
                lu.assertFalse(snapshot.liveModules[entry].reloaded)
                return true
            end,
            isDebugEnabled = function(_, snapshot)
                lu.assertFalse(snapshot.liveModules[entry].reloaded)
                return false
            end,
        },
    }
    local hud = CreateModpackHudStub()
    local theme = ModpackTestApi.createTheme()

    ModpackTestApi.createUI(moduleRegistry, hud, theme, {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, "test-pack", "Test Window", 1, {
        { Name = "", Hash = "", Tooltip = "" },
    })

    lu.assertEquals(reloads, 0)
end

function TestUiWindow:testRenderWindowCleansUpImguiStacksBeforeRethrow()
    local endCalls = 0
    local popStyleCalls = 0

    local restoreImGui = InstallWindowImGuiStub({
        End = function()
            endCalls = endCalls + 1
        end,
        Checkbox = function()
            error("draw boom")
        end,
        PopStyleColor = function()
            popStyleCalls = popStyleCalls + 1
        end,
    })

    local moduleRegistry = {
        modules = {},
        modulesWithQuickContent = {},
        tabOrder = {},
        live = {
            captureSnapshot = function()
                return { liveModules = {} }
            end,
        },
        snapshot = {
            getLiveModule = function()
                return nil
            end,
        },
    }
    local hud = CreateModpackHudStub()
    local theme = ModpackTestApi.createTheme()
    local builtUi = ModpackTestApi.createUI(moduleRegistry, hud, theme, {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, "test-pack", "Test Window", 1, {
        { Name = "", Hash = "", Tooltip = "" },
    })

    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)

    restoreImGui()

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "draw boom")
    lu.assertEquals(endCalls, 1)
    lu.assertEquals(popStyleCalls, 1)
end

function TestUiWindow:testDisabledPackCreationSuspendsEnabledModules()
    local config = {
        ModEnabled = false,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local target = { Value = "base" }
    local buildCalls = 0
    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {},
            patchPlan = function(plan)
                buildCalls = buildCalls + 1
                plan:set(target, "Value", "patched")
            end,
        },
    })
    lu.assertEquals(target.Value, "patched")

    local hud = CreateModpackHudStub()
    local theme = ModpackTestApi.createTheme()

    ModpackTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        1, config.Profiles)
    local snapshot = moduleRegistry.live.captureSnapshot()

    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "base")
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Alpha, snapshot))
    lu.assertEquals(readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Alpha, snapshot), 2)
end

function TestUiWindow:testQuickSetupRendersModuleQuickContent()
    local checkboxLabels = {}

    local restoreImGui = InstallWindowImGuiStub({
        Checkbox = function(label, current)
            table.insert(checkboxLabels, label)
            return current, false
        end,
    })

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {
                { type = "bool", alias = "FlagA", default = false },
            },
            DrawTab = function() end,
            DrawQuickContent = function(draw)
                draw.imgui.Checkbox("Quick B", false)
            end,
        },
    })

    local hud = CreateModpackHudStub()

    local theme = ModpackTestApi.createTheme()
    local setup = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local builtUi = ModpackTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        setup.NUM_PROFILES, setup.defaultProfiles, setup.drawPackQuickContent)
    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)

    restoreImGui()

    lu.assertTrue(ok, tostring(err))
    local joined = table.concat(checkboxLabels, "\n")
    lu.assertStrContains(joined, "Enable Mod")
    lu.assertStrContains(joined, "Quick B")
end

function TestUiWindow:testQuickSetupUsesLatestLiveModuleForQuickContent()
    local firstQuickRenders = 0
    local secondQuickRenders = 0

    local restoreImGui = InstallWindowImGuiStub()

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {
                { type = "bool", alias = "FlagA", default = false },
            },
            DrawTab = function() end,
            DrawQuickContent = function()
                firstQuickRenders = firstQuickRenders + 1
            end,
        },
    })

    local hud = CreateModpackHudStub()

    local theme = ModpackTestApi.createTheme()
    local setup = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local builtUi = ModpackTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        setup.NUM_PROFILES, setup.defaultProfiles, setup.drawPackQuickContent)
    builtUi.addMenuBar()
    local okFirst, errFirst = pcall(builtUi.renderWindow)

    local entry = moduleRegistry.modules[1]
    local replacementDefinition = LibManagedModule.prepareDefinition({}, {
        id = entry.id,
        name = entry.name,
        modpack = entry.modpack,
        storage = {
            { type = "bool", alias = "FlagA", default = false },
        },
    })
    local persistentState, stagedState = CreateModuleState({
        Enabled = true,
        DebugMode = false,
        FlagA = false,
    }, replacementDefinition)
    local replacementLiveModule = LibManagedModule.create({
        pluginGuid = entry.pluginGuid,
        definition = replacementDefinition,
        persistentState = persistentState,
        stagedState = stagedState,
        drawTab = function() end,
        drawQuickContent = function()
            secondQuickRenders = secondQuickRenders + 1
        end,
    })
    replacementLiveModule.activate()

    local okSecond, errSecond = pcall(builtUi.renderWindow)

    restoreImGui()

    lu.assertTrue(okFirst, tostring(errFirst))
    lu.assertTrue(okSecond, tostring(errSecond))
    lu.assertEquals(firstQuickRenders, 1)
    lu.assertEquals(secondQuickRenders, 1)
end

function TestUiWindow:testGuiCloseReleasesOverlaySuppression()
    local flushCalls = 0
    local suppressCalls = 0
    local releaseCalls = 0

    local restoreImGui = InstallWindowImGuiStub({
        MenuItem = function()
            return true
        end,
    })

    local moduleRegistry = ModpackTestApi.createModuleRegistry("test-pack", {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {},
    })
    moduleRegistry.modules = {}
    moduleRegistry.modulesById = {}
    local hud = CreateModpackHudStub({
        flushPendingHash = function()
            flushCalls = flushCalls + 1
        end,
    })
    local theme = ModpackTestApi.createTheme()
    local ui = ModpackTestApi.createUI(moduleRegistry, hud, theme, {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {},
    }, "test-pack", "Test Window", 1, {
        { Name = "", Hash = "", Tooltip = "" },
    }, nil, nil, nil, {
        order = {
            system = 0,
            modpack = 100,
        },
        define = function()
            return true
        end,
        suppressForUi = function()
            suppressCalls = suppressCalls + 1
            return {
                release = function()
                    releaseCalls = releaseCalls + 1
                end,
            }
        end,
    })

    ui.addMenuBar()
    ui.handleGuiClosed()

    restoreImGui()

    lu.assertEquals(flushCalls, 1)
    lu.assertEquals(suppressCalls, 1)
    lu.assertEquals(releaseCalls, 1)
end

function TestUiWindow:testDisablingRunDataModuleFlushesSetupRunDataWhenMenuCloses()
    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    local quickSetupRan = false

    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local restoreImGui = InstallWindowImGuiStub()

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {},
            patchPlan = function(plan)
                plan:set({}, "unused", true)
            end,
            DrawTab = function() end,
        },
    })
    setupRunDataCalls = 0

    local hud = CreateModpackHudStub()

    local theme = ModpackTestApi.createTheme()
    local setup = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
        drawPackQuickContent = function(ctx)
            if not quickSetupRan then
                quickSetupRan = true
                ctx.setModulesEnabled({ "Alpha" }, false)
            end
        end,
    }
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }

    local builtUi = ModpackTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        setup.NUM_PROFILES, setup.defaultProfiles, setup.drawPackQuickContent)
    builtUi.addMenuBar()
    local ok, err = pcall(builtUi.renderWindow)
    builtUi.addMenuBar()

    restoreImGui()
    rom.game.SetupRunData = previousSetupRunData

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(quickSetupRan)
    lu.assertEquals(setupRunDataCalls, 1)
end
