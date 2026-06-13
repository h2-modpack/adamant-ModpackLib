local lu = require("luaunit")
local fakeEngine = require("tests/harness/fake_engine")

TestMainBoot = {}

local function createBootHarness(opts)
    opts = opts or {}
    local public = {}
    local config = {
        DebugMode = false,
        Diagnostics = {
            configBackend = {
                label = "Config Backend Diagnostics",
                enabled = false,
            },
        },
    }
    local imports = {}
    local callbacks = fakeEngine.createCallbacks()
    local env = fakeEngine.createBaseEnv({
        callbacks = callbacks,
        public = public,
        config = config,
        _PLUGIN = { guid = "test-module" },
        plugin = { guid = "test-module" },
        runtimeRoot = {},
        ScreenData = {
            HUD = {
                ComponentData = {},
            },
        },
        HUDScreen = {
            Components = {},
        },
        ShowingCombatUI = true,
        ModifyTextBox = function() end,
        SetAlpha = function() end,
        CreateComponentFromData = function(_, data)
            return {
                Id = data.Name,
                Name = data.Name,
            }
        end,
        Destroy = function() end,
        ImGuiComboFlags = {
            NoPreview = 64,
        },
        ImGuiTreeNodeFlags = {},
        imports = imports,
        installImport = true,
        chalkOriginal = function(rawConfig)
            return rawConfig
        end,
        modUtilRuntime = opts.ModUtil,
    })

    assert(loadfile("src/main.lua", "t", env))()

    return {
        public = public,
        config = config,
        imports = imports,
        coordinator = imports["core/modpack/coordination.lua"],
        rom = env.rom,
        runtime = env.AdamantModpackLib_Runtime,
        menuCallbacks = callbacks.menuBar,
        imguiCallbacks = callbacks.imgui,
        alwaysDrawCallbacks = callbacks.alwaysDraw,
        onceLoadedCallbacks = callbacks.gameLoaded,
        chalkAutoPaths = callbacks.chalkAutoPaths,
        envyAutoCalls = callbacks.envyAutoCalls,
    }
end

function TestMainBoot.testMainLoadsPublicSurface()
    local h = createBootHarness()

    lu.assertNil(h.public.config)
    lu.assertNil(h.public.resetStorageToDefaults)
    lu.assertEquals(type(h.public.createModule), "function")
    lu.assertNil(h.public.tryCreateModule)
    lu.assertNil(h.public.createSystem)
    lu.assertEquals(type(h.public.modpack), "table")
    lu.assertEquals(type(h.public.modpack.registerCoordinator), "function")
    lu.assertEquals(type(h.public.modpack.createPack), "function")
    lu.assertEquals(type(h.public.modpack.createGuiCallbacks), "function")
    lu.assertNil(h.public.getLiveModuleHost)

    lu.assertNil(h.public.coordinator)
    lu.assertNil(h.public.cache)
    lu.assertNil(h.public.hashing)
    lu.assertNil(h.public.hooks)
    lu.assertNil(h.public.shared)
    lu.assertNil(h.public.mutation)
    lu.assertNil(h.public.overlays)
    lu.assertNil(h.public.widgets)
    lu.assertNil(h.public.nav)
    lu.assertNil(h.public.imguiHelpers)

    lu.assertEquals(type(h.runtime.registry), "table")
    lu.assertEquals(type(h.runtime.registry.modules), "table")
    lu.assertEquals(type(h.runtime.registry.hooks), "table")
    lu.assertEquals(type(h.runtime.registry.overlays), "table")
    lu.assertEquals(type(h.runtime.registry.fallback), "table")
    lu.assertEquals(type(h.runtime.registry.coordinators), "table")
    lu.assertEquals(type(h.runtime.registry.modpacks), "table")
    lu.assertEquals(type(h.runtime.registry.modpacks.packs), "table")
    lu.assertEquals(type(h.runtime.registry.modpacks.packList), "table")
    lu.assertNil(h.runtime.coordinator)
    lu.assertEquals(h.imports["core/init.lua"].modpackCoordination, h.imports["core/modpack/coordination.lua"])
end

function TestMainBoot.testMainLoadsModpackSubsystem()
    local h = createBootHarness()
    local rebuildReason

    lu.assertTrue(h.public.modpack.registerCoordinator("boot-pack", "Boot Pack", {
        ModEnabled = true,
    }, function(reason)
        rebuildReason = reason
        return true
    end))

    lu.assertTrue(h.coordinator.isRegistered("boot-pack"))
    lu.assertEquals(h.coordinator.getDisplayName("boot-pack"), "Boot Pack")
    lu.assertTrue(h.coordinator.requestRebuild("boot-pack", {
        reason = "test",
    }))
    lu.assertEquals(rebuildReason, {
        reason = "test",
    })

    local callbacks = h.public.modpack.createGuiCallbacks("boot-pack")
    lu.assertEquals(type(callbacks.render), "function")
    lu.assertEquals(type(callbacks.alwaysDraw), "function")
    lu.assertEquals(type(callbacks.menuBar), "function")
    callbacks.render()
    callbacks.alwaysDraw()
    callbacks.menuBar()
end

function TestMainBoot.testMainUsesExpectedBootExternals()
    local h = createBootHarness()

    lu.assertEquals(h.envyAutoCalls, 1)
    lu.assertEquals(h.chalkAutoPaths, { "config.lua" })
    lu.assertEquals(#h.menuCallbacks, 1)
    lu.assertEquals(#h.alwaysDrawCallbacks, 1)
    lu.assertEquals(#h.onceLoadedCallbacks, 1)
end

function TestMainBoot.testMainDebugMenuTogglesLibConfig()
    local h = createBootHarness()
    local calls = {
        endMenu = 0,
        checkboxes = {},
    }
    h.rom.ImGui = {
        BeginMenu = function(label)
            calls.beginMenu = label
            return true
        end,
        Checkbox = function(label, current)
            calls.checkboxes[#calls.checkboxes + 1] = {
                label = label,
                current = current,
            }
            return true, true
        end,
        EndMenu = function()
            calls.endMenu = calls.endMenu + 1
        end,
    }

    h.menuCallbacks[1]()

    lu.assertEquals(calls.beginMenu, "adamant-lib")
    lu.assertEquals(calls.checkboxes[1], {
        label = "Lib Policy Debug",
        current = false,
    })
    lu.assertEquals(calls.checkboxes[2], {
        label = "Config Backend Diagnostics",
        current = false,
    })
    lu.assertEquals(calls.endMenu, 1)
    lu.assertTrue(h.config.DebugMode)
    lu.assertTrue(h.config.Diagnostics.configBackend.enabled)
end

function TestMainBoot.testMainDebugMenuHidesWhenCoordinatorIsRegistered()
    local h = createBootHarness()
    local beginMenuCalls = 0
    h.coordinator.register("coordinated-pack", "Test Pack", { ModEnabled = true })
    h.rom.ImGui = {
        BeginMenu = function()
            beginMenuCalls = beginMenuCalls + 1
            return true
        end,
    }

    h.menuCallbacks[1]()

    lu.assertEquals(beginMenuCalls, 0)
end
