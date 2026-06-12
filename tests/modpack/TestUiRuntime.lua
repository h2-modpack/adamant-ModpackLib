local lu = require('luaunit')

TestUiRuntime = {}

local function readPackRestoreMarker(moduleRegistry, entry, snapshot)
    return moduleRegistry.snapshot.getLiveModule(entry, snapshot).read("__Modpack_PackRestoreMarker")
end

function TestUiRuntime:testMasterToggleRollsBackTouchedRuntimeStateOnFailure()
    CaptureWarnings()

    local config = {
        ModEnabled = false,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local masterCheckboxPass = 1
    local secondPassCurrent = nil

    local restoreImGui = InstallWindowImGuiStub({
        Checkbox = function(label, current)
            if label == "Enable Mod" then
                if masterCheckboxPass == 1 then
                    masterCheckboxPass = 2
                    return true, true
                end
                secondPassCurrent = current
                return current, false
            end
            return current, false
        end,
    })

    local firstState = { built = 0, target = { Value = "base" } }
    local secondState = { built = 0, target = { Value = "base" } }

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = false,
            values = {
                __Modpack_PackRestoreMarker = 2,
            },
            storage = {},
            patchPlan = function(plan)
                firstState.built = firstState.built + 1
                plan:set(firstState.target, "Value", "patched")
            end,
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = false,
            values = {
                __Modpack_PackRestoreMarker = 2,
            },
            storage = {},
            patchPlan = function()
                secondState.built = secondState.built + 1
                error("apply boom")
            end,
        },
    })

    local hudMarkers = {}
    local hud = CreateModpackHudStub({
        setModMarker = function(val)
            table.insert(hudMarkers, val)
        end,
    })

    local theme = ModpackTestApi.createTheme()
    local setup = {
        NUM_PROFILES = 1,
        defaultProfiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local builtUi = ModpackTestApi.createUI(moduleRegistry, hud, theme, config, "test-pack", "Test Window",
        setup.NUM_PROFILES, setup.defaultProfiles, setup.drawPackQuickContent)
    builtUi.addMenuBar()

    local okFirst, errFirst = pcall(builtUi.renderWindow)
    local okSecond, errSecond = pcall(builtUi.renderWindow)
    local warnings = Warnings

    restoreImGui()
    rom.game.SetupRunData = previousSetupRunData
    RestoreWarnings()

    lu.assertTrue(okFirst, tostring(errFirst))
    lu.assertTrue(okSecond, tostring(errSecond))
    lu.assertFalse(config.ModEnabled)
    lu.assertEquals(secondPassCurrent, false)
    lu.assertEquals(setupRunDataCalls, 0)
    lu.assertEquals(#hudMarkers, 0)
    lu.assertEquals(firstState.built, 1)
    lu.assertEquals(firstState.target.Value, "base")
    lu.assertEquals(secondState.built, 1)
    lu.assertEquals(secondState.target.Value, "base")
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "[test-pack] Enable Mod toggle failed; restoring previous runtime state: ")
    lu.assertStrContains(warnings[1], "apply boom")
end

function TestUiRuntime:testModuleBatchToggleRollsBackTouchedModulesOnFailure()
    CaptureWarnings()

    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local firstState = { built = 0, target = { Value = "base" } }
    local secondState = { built = 0, target = { Value = "base" } }

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = false,
            storage = {},
            patchPlan = function(plan)
                firstState.built = firstState.built + 1
                plan:set(firstState.target, "Value", "patched")
            end,
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = false,
            storage = {},
            patchPlan = function()
                secondState.built = secondState.built + 1
                error("apply boom")
            end,
        },
    })

    local markHashDirtyCalls = 0
    local function noop() end
    local hud = {
        markHashDirty = function()
            markHashDirtyCalls = markHashDirtyCalls + 1
        end,
        getConfigHash = function()
            return "hash", "fingerprint"
        end,
        setMarkerVisible = noop,
    }
    local staging = {
        ModEnabled = true,
        modules = {
            Alpha = false,
            Bravo = false,
        },
        debug = {},
    }
    local snapshotAccess = {
        get = function()
            return nil
        end,
        capture = function()
            return moduleRegistry.live.captureSnapshot()
        end,
        getLiveModule = function(entry, snapshot)
            return moduleRegistry.snapshot.getLiveModule(entry, snapshot)
        end,
    }
    local runtime = ModpackTestApi.createUIRuntime({
        moduleRegistry = moduleRegistry,
        hud = hud,
        config = {
            ModEnabled = true,
            DebugMode = false,
        },
        packId = "test-pack",
        colors = {},
        staging = staging,
        snapshotAccess = snapshotAccess,
        snapshotToStaging = function() end,
        logging = ModpackTestApi.logging,
    })

    local snapshot = moduleRegistry.live.captureSnapshot()
    local ok, err = runtime.setModulesEnabled({ "Alpha", "Bravo" }, true, snapshot)
    runtime.flushPendingRunData()

    local warnings = Warnings
    rom.game.SetupRunData = previousSetupRunData
    RestoreWarnings()

    lu.assertFalse(ok)
    lu.assertStrContains(tostring(err), "apply boom")
    lu.assertFalse(staging.modules.Alpha)
    lu.assertFalse(staging.modules.Bravo)
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Alpha, snapshot))
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Bravo, snapshot))
    lu.assertEquals(firstState.built, 1)
    lu.assertEquals(firstState.target.Value, "base")
    lu.assertEquals(secondState.built, 1)
    lu.assertEquals(secondState.target.Value, "base")
    lu.assertEquals(markHashDirtyCalls, 0)
    lu.assertEquals(setupRunDataCalls, 0)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "[test-pack] Module batch toggle failed; restoring previous module states: ")
end

function TestUiRuntime:testPackDisableSnapshotsModuleEnabledState()
    local config = {
        ModEnabled = true,
        DebugMode = false,
    }

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            storage = {},
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = false,
            storage = {},
        },
    })
    local staging = {
        ModEnabled = true,
        modules = {
            Alpha = true,
            Bravo = false,
        },
        debug = {},
    }
    local hudMarkers = {}
    local runtime = ModpackTestApi.createUIRuntime({
        moduleRegistry = moduleRegistry,
        hud = {
            markHashDirty = function() end,
            setModMarker = function(value)
                hudMarkers[#hudMarkers + 1] = value
            end,
        },
        config = config,
        packId = "test-pack",
        colors = {},
        staging = staging,
        snapshotAccess = {
            get = function() return nil end,
            capture = function() return moduleRegistry.live.captureSnapshot() end,
            getLiveModule = function(entry, snapshot)
                return moduleRegistry.snapshot.getLiveModule(entry, snapshot)
            end,
        },
        snapshotToStaging = function() end,
        logging = ModpackTestApi.logging,
    })
    local snapshot = moduleRegistry.live.captureSnapshot()

    local ok, err = runtime.setPackRuntimeState(false, snapshot)

    lu.assertTrue(ok, tostring(err))
    lu.assertFalse(config.ModEnabled)
    lu.assertFalse(staging.ModEnabled)
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Alpha, snapshot))
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Bravo, snapshot))
    lu.assertEquals(
        readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Alpha, snapshot),
        2)
    lu.assertEquals(
        readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Bravo, snapshot),
        1)
    lu.assertEquals(hudMarkers, { false })
end

function TestUiRuntime:testPackEnableRestoresPersistedPackRestoreMarkers()
    local config = {
        ModEnabled = false,
        DebugMode = false,
    }

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = false,
            values = {
                __Modpack_PackRestoreMarker = 2,
            },
            storage = {},
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = false,
            values = {
                __Modpack_PackRestoreMarker = 1,
            },
            storage = {},
        },
    })
    local staging = {
        ModEnabled = false,
        modules = {
            Alpha = false,
            Bravo = false,
        },
        debug = {},
    }
    local hudMarkers = {}
    local runtime = ModpackTestApi.createUIRuntime({
        moduleRegistry = moduleRegistry,
        hud = {
            markHashDirty = function() end,
            setModMarker = function(value)
                hudMarkers[#hudMarkers + 1] = value
            end,
        },
        config = config,
        packId = "test-pack",
        colors = {},
        staging = staging,
        snapshotAccess = {
            get = function() return nil end,
            capture = function() return moduleRegistry.live.captureSnapshot() end,
            getLiveModule = function(entry, snapshot)
                return moduleRegistry.snapshot.getLiveModule(entry, snapshot)
            end,
        },
        snapshotToStaging = function() end,
        logging = ModpackTestApi.logging,
    })
    local snapshot = moduleRegistry.live.captureSnapshot()

    local ok, err = runtime.setPackRuntimeState(true, snapshot)

    lu.assertTrue(ok, tostring(err))
    lu.assertTrue(config.ModEnabled)
    lu.assertTrue(staging.ModEnabled)
    lu.assertTrue(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Alpha, snapshot))
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(moduleRegistry.modulesById.Bravo, snapshot))
    lu.assertEquals(
        readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Alpha, snapshot),
        0)
    lu.assertEquals(
        readPackRestoreMarker(moduleRegistry, moduleRegistry.modulesById.Bravo, snapshot),
        0)
    lu.assertEquals(hudMarkers, { true })
end

function TestUiRuntime:testRuntimeResetAllModulesCommitsModuleDefaults()
    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local moduleRegistry = MockModuleRegistry.create({
        {
            pluginGuid = "Alpha",
            id = "Alpha",
            name = "Alpha",
            enabled = true,
            values = {
                Flag = true,
            },
            storage = {
                { type = "bool", alias = "Flag", default = false },
            },
            patchPlan = function(plan)
                plan:set({}, "unused", true)
            end,
        },
        {
            pluginGuid = "Bravo",
            id = "Bravo",
            name = "Bravo",
            enabled = false,
            values = {
                Count = 4,
            },
            storage = {
                { type = "int", alias = "Count", default = 1, min = 0, max = 9 },
            },
        },
    })
    local snapshotToStagingCalls = 0
    local markHashDirtyCalls = 0
    local updateHashCalls = 0
    local runtime = ModpackTestApi.createUIRuntime({
        moduleRegistry = moduleRegistry,
        hud = {
            markHashDirty = function()
                markHashDirtyCalls = markHashDirtyCalls + 1
            end,
            updateHash = function()
                updateHashCalls = updateHashCalls + 1
            end,
        },
        config = {
            ModEnabled = true,
            DebugMode = false,
        },
        packId = "test-pack",
        colors = {},
        staging = {
            ModEnabled = true,
            modules = {},
            debug = {},
        },
        snapshotAccess = {
            get = function() return nil end,
            capture = function() return moduleRegistry.live.captureSnapshot() end,
            getLiveModule = function(entry, snapshot)
                return moduleRegistry.snapshot.getLiveModule(entry, snapshot)
            end,
        },
        snapshotToStaging = function()
            snapshotToStagingCalls = snapshotToStagingCalls + 1
        end,
        logging = ModpackTestApi.logging,
    })
    local snapshot = moduleRegistry.live.captureSnapshot()
    local alpha = moduleRegistry.modulesById.Alpha
    local bravo = moduleRegistry.modulesById.Bravo

    local ok, err, resetCount = runtime.resetAllModules()
    runtime.flushPendingRunData()
    rom.game.SetupRunData = previousSetupRunData

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(resetCount, 3)
    lu.assertFalse(moduleRegistry.snapshot.isEntryEnabled(alpha, snapshot))
    lu.assertFalse(moduleRegistry.snapshot.getStorageValue(alpha, "Flag", snapshot))
    lu.assertEquals(moduleRegistry.snapshot.getStorageValue(bravo, "Count", snapshot), 1)
    lu.assertEquals(snapshotToStagingCalls, 1)
    lu.assertEquals(markHashDirtyCalls, 1)
    lu.assertEquals(updateHashCalls, 1)
    lu.assertEquals(setupRunDataCalls, 2)
end
