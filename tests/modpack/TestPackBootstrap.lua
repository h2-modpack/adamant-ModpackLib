local lu = require('luaunit')

TestPackBootstrap = {}

local function createPackOrFail(harness, ...)
    local ok, pack, err = harness.createPack(...)
    lu.assertTrue(ok, tostring(err))
    return pack
end

function TestPackBootstrap:setUp()
    local overlays = LibOverlays
    self.previousUiSuppressors = overlays.uiSuppressors
    self.previousNextUiSuppressorId = overlays.nextUiSuppressorId
    overlays.uiSuppressors = {}
    overlays.nextUiSuppressorId = 0
end

function TestPackBootstrap:tearDown()
    local overlays = LibOverlays
    overlays.uiSuppressors = self.previousUiSuppressors
    overlays.nextUiSuppressorId = self.previousNextUiSuppressorId
end

function TestPackBootstrap:testCreateGuiCallbacksAreSafeBeforeInit()
    local callbacks = ModpackTestApi.public.createGuiCallbacks("missing-pack")
    local renderOk = pcall(callbacks.render)
    local alwaysDrawOk = pcall(callbacks.alwaysDraw)
    local menuBarOk = pcall(callbacks.menuBar)

    lu.assertTrue(renderOk)
    lu.assertTrue(alwaysDrawOk)
    lu.assertTrue(menuBarOk)
end

function TestPackBootstrap:testInitLeavesStartupMutationSyncToLiveModuleActivation()
    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0

    local entry = {
        id = "Alpha",
        name = "Alpha",
        pluginGuid = "Alpha",
        storage = {},
        affectsRunData = true,
        definition = {
            id = "Alpha",
            name = "Alpha",
            affectsRunData = true,
        },
    }
    local liveModule = {}

    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end
    local harness = CreateModpackHarness({
        constructors = {
        createModuleRegistry = function()
            return {
                modules = { entry },
                refresh = function() end,
                live = {
                    captureSnapshot = function()
                        return { liveModules = { [entry] = liveModule } }
                    end,
                },
                snapshot = {
                    getLiveModule = function(_, snapshot)
                        return snapshot.liveModules[entry]
                    end,
                },
            }
        end,
        createConfigHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function()
            return {
                install = function() end,
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            return {
                renderWindow = function() end,
                addMenuBar = function() end,
            }
        end,
        },
    })
    harness.registerCoordinator("startup-pack", "Test Pack", { ModEnabled = true })
    createPackOrFail(
        harness,
        "startup-pack",
        {
            ModEnabled = true,
            DebugMode = false,
            Profiles = {
                { Name = "", Hash = "", Tooltip = "" },
            },
        },
        1,
        {}
    )

    rom.game.SetupRunData = previousSetupRunData

    lu.assertEquals(setupRunDataCalls, 0)
end

function TestPackBootstrap:testModuleActivationOwnsStartupSyncBeforeModpackInit()
    local packId = "load-order-pack"

    local previousSetupRunData = rom.game.SetupRunData
    local setupRunDataCalls = 0
    local buildCalls = 0
    local target = { Value = "base" }

    rom.game.SetupRunData = function()
        setupRunDataCalls = setupRunDataCalls + 1
    end

    local definition = LibManagedModule.prepareDefinition({}, {
        modpack = packId,
        id = "Alpha",
        name = "Alpha",
        storage = {},
    })
    local persistentState, stagedState = CreateModuleState({
        Enabled = true,
        DebugMode = false,
    }, definition)
    local mutationBundle = {
        patchMutation = nil,
    }
    LibTestImports["core/mutations/00_init.lua"].lifecycle.declarePatch(mutationBundle, function(_, _, plan)
        buildCalls = buildCalls + 1
        plan:set(target, "Value", "patched")
    end)
    local liveModule = LibManagedModule.create({
        pluginGuid = "test-pack.Alpha",
        definition = definition,
        persistentState = persistentState,
        stagedState = stagedState,
        mutationBundle = mutationBundle,
        drawTab = function() end,
    })
    liveModule.activate()

    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "patched")
    lu.assertEquals(setupRunDataCalls, 1)
    local entry = {
        id = definition.id,
        name = definition.name,
        pluginGuid = "Alpha",
        storage = definition.storage,
        affectsRunData = true,
        definition = definition,
    }

    local harness = CreateModpackHarness({
        constructors = {
        createModuleRegistry = function()
            return {
                modules = { entry },
                refresh = function() end,
                live = {
                    captureSnapshot = function()
                        return { liveModules = { [entry] = liveModule } }
                    end,
                },
                snapshot = {
                    getLiveModule = function(_, snapshot)
                        return snapshot.liveModules[entry]
                    end,
                },
            }
        end,
        createConfigHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function()
            return {
                install = function() end,
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            return {
                renderWindow = function() end,
                addMenuBar = function() end,
            }
        end,
        },
    })
    harness.registerCoordinator(packId, "Test Pack", {
        ModEnabled = true,
    })
    createPackOrFail(
        harness,
        packId,
        {
            ModEnabled = true,
            DebugMode = false,
            Profiles = {
                { Name = "", Hash = "", Tooltip = "" },
            },
        },
        1,
        {}
    )

    local ok, err = liveModule.revertMutation()
    rom.game.SetupRunData = previousSetupRunData

    lu.assertTrue(ok, tostring(err))
    lu.assertEquals(buildCalls, 1)
    lu.assertEquals(target.Value, "base")
    lu.assertEquals(setupRunDataCalls, 1)
end

function TestPackBootstrap:testRepeatedInitReplacesPackStateAndKeepsStablePackIndex()
    local packId = "reinit-pack"
    local hudIndexes = {}
    local firstPack
    local secondPack

    local harness = CreateModpackHarness({
        constructors = {
        createModuleRegistry = function()
            return {
                modules = {},
                refresh = function() end,
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
        end,
        createConfigHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function(_, packIndex)
            table.insert(hudIndexes, packIndex)
            return {
                install = function() end,
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            return {
                renderWindow = function() end,
                addMenuBar = function() end,
                flushPending = function() end,
            }
        end,
        },
    })
    harness.registerCoordinator(packId, "Test Pack", {
        ModEnabled = true,
    })
    local packRegistry = harness.packRegistry
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    firstPack = createPackOrFail(harness, packId, config, 1, {})
    secondPack = createPackOrFail(harness, packId, config, 1, {})

    local packIdCount = 0
    for _, value in ipairs(packRegistry.packList) do
        if value == packId then
            packIdCount = packIdCount + 1
        end
    end
    local activePack = packRegistry.packs[packId]

    lu.assertTrue(firstPack ~= secondPack)
    lu.assertEquals(activePack, secondPack)
    lu.assertEquals(#hudIndexes, 2)
    lu.assertEquals(hudIndexes[1], hudIndexes[2])
    lu.assertEquals(firstPack._index, secondPack._index)
    lu.assertEquals(packIdCount, 1)
end

function TestPackBootstrap:testRepeatedInitDisposesPreviousOpenUiSuppression()
    local packId = "reinit-dispose-pack"
    local suppressCalls = 0
    local releaseCalls = 0
    local flushCalls = 0

    local testOverlaySurface = {
        order = {
            system = 0,
            modpack = 100,
        },
        define = function()
            return true
        end,
        suppressForUi = function()
            suppressCalls = suppressCalls + 1
            local released = false
            return {
                release = function()
                    if released then
                        return
                    end
                    released = true
                    releaseCalls = releaseCalls + 1
                end,
            }
        end,
    }
    local restoreImGui = InstallWindowImGuiStub({
        MenuItem = function()
            return true
        end,
    })

    local harness = CreateModpackHarness({
        overlaySurface = testOverlaySurface,
        constructors = {
            createModuleRegistry = function()
                return {
                    modules = {},
                    modulesById = {},
                    tabOrder = {},
                    modulesWithQuickContent = {},
                    refresh = function() end,
                    live = {
                        captureSnapshot = function()
                            return { liveModules = {} }
                        end,
                    },
                    snapshot = {
                        getLiveModule = function()
                            return nil
                        end,
                        isEntryEnabled = function()
                            return false
                        end,
                        isDebugEnabled = function()
                            return false
                        end,
                    },
                }
            end,
            createConfigHash = function()
                return {}
            end,
            createTheme = function()
                return {
                    colors = {
                        textDisabled = {},
                        warning = {},
                        success = {},
                        info = {},
                    },
                    PushTheme = function() end,
                    PopTheme = function() end,
                }
            end,
            createHud = function()
                return {
                    install = function() end,
                    setModMarker = function() end,
                    setMarkerVisible = function() end,
                    flushPendingHash = function()
                        flushCalls = flushCalls + 1
                    end,
                    getConfigHash = function()
                        return "", ""
                    end,
                    applyConfigHash = function()
                        return true
                    end,
                    markHashDirty = function() end,
                }
            end,
        },
    })
    harness.registerCoordinator(packId, "Test Pack", {
        ModEnabled = true,
    })
    local packRegistry = harness.packRegistry
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local firstPack = createPackOrFail(harness, packId, config, 1, {})
    firstPack.ui.addMenuBar()
    local secondPack = createPackOrFail(harness, packId, config, 1, {})
    local releaseCallsAfterReinit = releaseCalls
    local flushCallsAfterReinit = flushCalls
    firstPack.ui.addMenuBar()
    local suppressCallsAfterDisposedProbe = suppressCalls
    local releaseCallsAfterDisposedProbe = releaseCalls
    local flushCallsAfterDisposedProbe = flushCalls

    local activePack = packRegistry.packs[packId]

    restoreImGui()

    lu.assertTrue(firstPack ~= secondPack)
    lu.assertEquals(activePack, secondPack)
    lu.assertEquals(suppressCallsAfterDisposedProbe, 1)
    lu.assertEquals(releaseCallsAfterReinit, 1)
    lu.assertEquals(releaseCallsAfterDisposedProbe, 1)
    lu.assertEquals(flushCallsAfterReinit, 1)
    lu.assertEquals(flushCallsAfterDisposedProbe, 1)
end

function TestPackBootstrap:testFailedInitDoesNotRegisterPack()
    CaptureWarnings()

    local packId = "failed-init-pack"
    local hudInstallCalls = 0

    local harness = CreateModpackHarness({
        constructors = {
        createModuleRegistry = function()
            return {
                modules = {},
                refresh = function() end,
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
        end,
        createConfigHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function()
            return {
                install = function()
                    hudInstallCalls = hudInstallCalls + 1
                end,
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            error("ui construction boom")
        end,
        },
    })
    harness.registerCoordinator(packId, "Test Pack", {
        ModEnabled = true,
    })
    local packRegistry = harness.packRegistry
    local config = {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }
    local ok, pack, err = harness.createPack(packId, config, 1, {})
    local warnings = Warnings

    local packIdCount = 0
    for _, value in ipairs(packRegistry.packList) do
        if value == packId then
            packIdCount = packIdCount + 1
        end
    end

    RestoreWarnings()

    lu.assertFalse(ok)
    lu.assertNil(pack)
    lu.assertStrContains(tostring(err), "ui construction boom")
    lu.assertEquals(packIdCount, 0)
    lu.assertNil(packRegistry.packs[packId])
    lu.assertEquals(hudInstallCalls, 0)
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "[failed-init-pack] modpack createPack failed; skipping pack:")
end

function TestPackBootstrap:testTryInitReturnsPackOnSuccess()
    local packId = "try-init-success-pack"
    local ok, pack, err
    local harness = CreateModpackHarness({
        constructors = {
        createModuleRegistry = function()
            return {
                modules = {},
                refresh = function() end,
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
        end,
        createConfigHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function()
            return {
                install = function() end,
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            return {
                renderWindow = function() end,
                addMenuBar = function() end,
            }
        end,
        },
    })
    harness.registerCoordinator(packId, "Test Pack", {
        ModEnabled = true,
    })
    ok, pack, err = harness.createPack(packId, {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, 1, {})

    lu.assertTrue(ok)
    lu.assertNotNil(pack)
    lu.assertNil(err)
end

function TestPackBootstrap:testTryInitReturnsErrorAndDoesNotRegisterPack()
    CaptureWarnings()

    local packId = "create-pack-fail-pack"
    local ok, pack, err
    local harness = CreateModpackHarness({
        constructors = {
        createModuleRegistry = function()
            return {
                modules = {},
                refresh = function() end,
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
        end,
        createConfigHash = function()
            return {}
        end,
        createTheme = function()
            return { colors = {} }
        end,
        createHud = function()
            return {
                install = function() end,
                setModMarker = function() end,
                setMarkerVisible = function() end,
            }
        end,
        createUI = function()
            error("try init boom")
        end,
        },
    })
    harness.registerCoordinator(packId, "Test Pack", {
        ModEnabled = true,
    })
    local packRegistry = harness.packRegistry
    ok, pack, err = harness.createPack(packId, {
        ModEnabled = true,
        DebugMode = false,
        Profiles = {
            { Name = "", Hash = "", Tooltip = "" },
        },
    }, 1, {})

    local warnings = Warnings

    local packIdCount = 0
    for _, value in ipairs(packRegistry.packList) do
        if value == packId then
            packIdCount = packIdCount + 1
        end
    end

    RestoreWarnings()

    lu.assertFalse(ok)
    lu.assertNil(pack)
    lu.assertStrContains(tostring(err), "try init boom")
    lu.assertEquals(packIdCount, 0)
    lu.assertNil(packRegistry.packs[packId])
    lu.assertEquals(#warnings, 1)
    lu.assertStrContains(warnings[1], "[create-pack-fail-pack] modpack createPack failed; skipping pack:")
    lu.assertStrContains(warnings[1], "try init boom")
end

function TestPackBootstrap:testAlwaysDrawRendererFlushesPendingHashWhenGuiDisappears()
    local previousGui = rom.gui
    local guiOpen = true
    local flushCalls = 0
    local closeCalls = 0
    local alwaysDraw

    rom.gui = {
        is_open = function()
            return guiOpen
        end,
    }

    local packId = "flush-pack"
    local harness = CreateModpackHarness()
    alwaysDraw = harness.createGuiCallbacks(packId).alwaysDraw

    harness.packRegistry.packs[packId] = {
        ui = {
            flushPending = function()
                flushCalls = flushCalls + 1
            end,
            handleGuiClosed = function()
                closeCalls = closeCalls + 1
            end,
        },
    }

    alwaysDraw()
    guiOpen = false
    alwaysDraw()
    alwaysDraw()

    rom.gui = previousGui

    lu.assertEquals(flushCalls, 0)
    lu.assertEquals(closeCalls, 1)
end
